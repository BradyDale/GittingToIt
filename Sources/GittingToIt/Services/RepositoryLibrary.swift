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
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await Task.detached {
                    try GitClient().snapshot(for: repository)
                }.value
                snapshots[repository.id] = snapshot
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func history(for document: WritingDocument) async throws -> [CommitSummary] {
        guard let repository = selectedRepository else { return [] }
        return try await Task.detached {
            try GitClient().fileHistory(in: repository.folderURL, relativePath: document.relativePath)
        }.value
    }

    func changedFiles(for commit: CommitSummary) async throws -> [GitChange] {
        guard let repository = selectedRepository else { return [] }
        return try await Task.detached {
            try GitClient().filesChanged(in: repository.folderURL, commit: commit.hash)
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

    func saveCheckpoint(paths: [String], message: String) async throws -> CommitSummary {
        guard let repository = selectedRepository else { throw GitClientError.noFilesSelected }
        let commit = try await Task.detached {
            try GitClient().commitSelected(in: repository.folderURL, paths: paths, message: message)
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
