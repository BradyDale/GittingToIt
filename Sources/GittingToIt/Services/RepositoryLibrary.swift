import AppKit
import Foundation

@MainActor
final class RepositoryLibrary: ObservableObject {
    @Published private(set) var repositories: [RepositoryReference] = []
    @Published private(set) var snapshots: [UUID: RepositorySnapshot] = [:]
    @Published var selectedRepositoryID: UUID?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let git = GitClient()
    private var historyCache: [String: [CommitSummary]] = [:]

    init() {
        loadCatalog()
        selectedRepositoryID = repositories.first?.id
        refreshSelected()
    }

    var selectedRepository: RepositoryReference? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add a writing folder"
        panel.prompt = "Add Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultSyncFolder()

        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        do {
            let root: URL
            if let detected = try? git.repositoryRoot(for: chosen) {
                root = detected
                if detected != chosen.standardizedFileURL {
                    let alert = NSAlert()
                    alert.messageText = "This folder is inside another repository"
                    alert.informativeText = "GittingToIt can add the repository root, \(detected.lastPathComponent), without creating a nested repository."
                    alert.addButton(withTitle: "Add Repository Root")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "Start tracking \(chosen.lastPathComponent)?"
                alert.informativeText = "This creates a Git repository in the folder. Existing files will not be changed or committed yet."
                alert.addButton(withTitle: "Create Repository")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try git.initializeRepository(at: chosen)
                root = chosen.standardizedFileURL
            }

            if let existing = repositories.first(where: { $0.folderURL == root }) {
                selectedRepositoryID = existing.id
            } else {
                let reference = RepositoryReference(displayName: root.lastPathComponent, folderURL: root)
                repositories.append(reference)
                selectedRepositoryID = reference.id
                saveCatalog()
            }
            refreshSelected()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromLibrary(_ repository: RepositoryReference) {
        repositories.removeAll { $0.id == repository.id }
        snapshots[repository.id] = nil
        if selectedRepositoryID == repository.id {
            selectedRepositoryID = repositories.first?.id
        }
        saveCatalog()
        refreshSelected()
    }

    func select(_ repository: RepositoryReference) {
        selectedRepositoryID = repository.id
        if snapshots[repository.id] == nil { refreshSelected() }
    }

    func refreshSelected() {
        guard let repository = selectedRepository else { return }
        historyCache = historyCache.filter { !$0.key.hasPrefix(repository.id.uuidString + "\u{0}") }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await Task.detached {
                    try GitClient().snapshot(for: repository)
                }.value
                snapshots[repository.id] = snapshot
                warmRecentHistories(for: repository, documents: snapshot.documents)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func history(for document: WritingDocument) async throws -> [CommitSummary] {
        guard let repository = selectedRepository else { return [] }
        let cacheKey = repository.id.uuidString + "\u{0}" + document.relativePath
        if let cached = historyCache[cacheKey] { return cached }
        let history = try await Task.detached {
            try GitClient().fileHistory(in: repository.folderURL, relativePath: document.relativePath)
        }.value
        historyCache[cacheKey] = history
        return history
    }

    func changedFiles(for commit: CommitSummary) async throws -> [GitChange] {
        guard let repository = selectedRepository else { return [] }
        return try await Task.detached {
            try GitClient().filesChanged(in: repository.folderURL, commit: commit.hash)
        }.value
    }

    func historicalText(for document: WritingDocument, at commit: CommitSummary) async throws -> String {
        guard let repository = selectedRepository else { return "" }
        return try await Task.detached {
            try GitClient().text(
                in: repository.folderURL,
                relativePath: commit.historicalPath ?? document.relativePath,
                at: commit.hash
            )
        }.value
    }

    func wordDiffToCurrent(for document: WritingDocument, from commit: CommitSummary) async throws -> String {
        guard let repository = selectedRepository else { return "" }
        return try await Task.detached {
            try GitClient().wordDiffFromWorkingFile(
                in: repository.folderURL,
                relativePath: document.relativePath,
                historicalPath: commit.historicalPath,
                from: commit.hash
            )
        }.value
    }

    func notes(for document: WritingDocument) -> String {
        guard let repository = selectedRepository else { return "" }
        let url = CopyService().notesURL(repositoryRoot: repository.folderURL, relativePath: document.relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "No file notes yet."
    }

    func makeRelatedCopy(of document: WritingDocument, purpose: String) throws -> RelatedCopyResult {
        guard let repository = selectedRepository,
              let snapshot = snapshots[repository.id] else {
            throw RelatedCopyError.sourceMissing
        }
        let result = try CopyService().makeRelatedCopy(
            repositoryRoot: repository.folderURL,
            relativePath: document.relativePath,
            purpose: purpose,
            sourceCommit: snapshot.currentCommit
        )
        refreshSelected()
        return result
    }

    func forkHistoricalVersion(
        of document: WritingDocument,
        from commit: CommitSummary,
        purpose: String
    ) async throws -> RelatedCopyResult {
        guard let repository = selectedRepository else { throw RelatedCopyError.sourceMissing }
        let data = try await Task.detached {
            try GitClient().fileData(
                in: repository.folderURL,
                relativePath: commit.historicalPath ?? document.relativePath,
                at: commit.hash
            )
        }.value
        let result = try CopyService().makeRelatedCopy(
            repositoryRoot: repository.folderURL,
            relativePath: document.relativePath,
            contents: data,
            purpose: purpose,
            sourceCommit: commit.shortHash
        )
        refreshSelected()
        return result
    }

    func addFileNote(to document: WritingDocument, eventType: String, note: String) throws {
        guard let repository = selectedRepository,
              let snapshot = snapshots[repository.id] else {
            throw FileNoteError.fileOutsideRepository
        }
        try CopyService().addFileNote(
            repositoryRoot: repository.folderURL,
            relativePath: document.relativePath,
            eventType: eventType,
            note: note,
            commit: snapshot.currentCommit
        )
        refreshSelected()
    }

    func editableNotesDraft(for document: WritingDocument) throws -> String {
        guard let repository = selectedRepository else { throw FileNoteError.fileOutsideRepository }
        return try CopyService().editableNotesDraft(
            repositoryRoot: repository.folderURL,
            relativePath: document.relativePath
        )
    }

    func saveNotes(for document: WritingDocument, contents: String) throws {
        guard let repository = selectedRepository else { throw FileNoteError.fileOutsideRepository }
        _ = try CopyService().saveNotes(
            repositoryRoot: repository.folderURL,
            relativePath: document.relativePath,
            contents: contents
        )
        refreshSelected()
    }

    func ignoreFile(path: String) async throws -> IgnoreFileResult {
        guard let repository = selectedRepository else { throw GitClientError.noFilesSelected }
        let result = try await Task.detached {
            try GitClient().ignoreFile(in: repository.folderURL, relativePath: path)
        }.value
        return result
    }

    func ignoreFiles(
        paths: [String],
        rules: [String],
        includeEveryTrackedDSStore: Bool = false
    ) async throws -> [IgnoreFileResult] {
        guard let repository = selectedRepository else { throw GitClientError.noFilesSelected }
        return try await Task.detached {
            try GitClient().ignoreFiles(
                in: repository.folderURL,
                relativePaths: paths,
                rules: rules,
                includeEveryTrackedDSStore: includeEveryTrackedDSStore
            )
        }.value
    }

    func saveCheckpoint(
        paths: [String],
        stopTrackingPaths: [String] = [],
        message: String
    ) async throws -> CommitSummary {
        guard let repository = selectedRepository,
              let snapshot = snapshots[repository.id] else { throw GitClientError.noFilesSelected }
        let commit = try await Task.detached {
            let documentedPaths = try CopyService().documentFamilyChanges(
                repositoryRoot: repository.folderURL,
                paths: paths,
                checkpointMessage: message,
                commit: snapshot.currentCommit
            )
            return try GitClient().commitSelected(
                in: repository.folderURL,
                paths: documentedPaths,
                stopTrackingPaths: stopTrackingPaths,
                message: message
            )
        }.value
        refreshSelected()
        return commit
    }

    func restore(
        _ document: WritingDocument,
        from commit: CommitSummary,
        note: String
    ) async throws -> FileRestoreResult {
        guard let repository = selectedRepository else { throw FileNoteError.fileOutsideRepository }
        let result = try await Task.detached {
            try GitClient().restoreFile(
                in: repository.folderURL,
                relativePath: document.relativePath,
                from: commit,
                note: note
            )
        }.value
        refreshSelected()
        return result
    }

    private func defaultSyncFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let documentsSync = home.appendingPathComponent("Documents/Sync", isDirectory: true)
        if FileManager.default.fileExists(atPath: documentsSync.path) { return documentsSync }
        let directSync = home.appendingPathComponent("Sync", isDirectory: true)
        if FileManager.default.fileExists(atPath: directSync.path) { return directSync }
        return home.appendingPathComponent("Documents", isDirectory: true)
    }

    private func warmRecentHistories(for repository: RepositoryReference, documents: [WritingDocument]) {
        let recent = documents.sorted {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }.prefix(4)
        let uncached = recent.filter {
            historyCache[repository.id.uuidString + "\u{0}" + $0.relativePath] == nil
        }
        guard !uncached.isEmpty else { return }

        Task(priority: .utility) {
            let warmed = await Task.detached(priority: .utility) {
                uncached.compactMap { document -> (String, [CommitSummary])? in
                    guard let history = try? GitClient().fileHistory(
                        in: repository.folderURL,
                        relativePath: document.relativePath
                    ) else { return nil }
                    return (document.relativePath, history)
                }
            }.value
            guard repositories.contains(where: { $0.id == repository.id }) else { return }
            for (path, history) in warmed {
                historyCache[repository.id.uuidString + "\u{0}" + path] = history
            }
        }
    }

    private func catalogURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("GittingToIt", isDirectory: true)
            .appendingPathComponent("repositories.json")
    }

    private func loadCatalog() {
        guard let url = catalogURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RepositoryReference].self, from: data) else { return }
        repositories = decoded.filter { FileManager.default.fileExists(atPath: $0.folderURL.path) }
    }

    private func saveCatalog() {
        guard let url = catalogURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(repositories)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "GittingToIt could not save its local folder list: \(error.localizedDescription)"
        }
    }
}
