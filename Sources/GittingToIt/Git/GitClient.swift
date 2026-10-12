import Foundation

enum GitClientError: LocalizedError {
    case commandFailed(arguments: [String], message: String)
    case notARepository(URL)
    case emptyCommitMessage
    case noFilesSelected
    case noSelectedChanges

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, message):
            return "Git could not complete ‘git \(arguments.joined(separator: " "))’: \(message)"
        case let .notARepository(url):
            return "\(url.lastPathComponent) is not a Git repository."
        case .emptyCommitMessage:
            return "Please add a checkpoint message."
        case .noFilesSelected:
            return "Select at least one changed file."
        case .noSelectedChanges:
            return "The selected files do not contain changes to save."
        }
    }
}

struct GitClient: Sendable {
    private static let supportedWritingExtensions: Set<String> = [
        "md", "markdown", "txt", "rtf", "doc", "docx", "pdf"
    ]

    func repositoryRoot(for folder: URL) throws -> URL {
        let output = try run(["-C", folder.path, "rev-parse", "--show-toplevel"])
        guard !output.isEmpty else { throw GitClientError.notARepository(folder) }
        return URL(fileURLWithPath: output).standardizedFileURL
    }

    func initializeRepository(at folder: URL) throws {
        _ = try run(["-C", folder.path, "init"])
    }

    func snapshot(for repository: RepositoryReference) throws -> RepositorySnapshot {
        let root = try repositoryRoot(for: repository.folderURL)
        guard root == repository.folderURL.standardizedFileURL else {
            throw GitClientError.notARepository(repository.folderURL)
        }

        let branch = (try? run(["-C", root.path, "symbolic-ref", "--short", "HEAD"])) ?? "Detached"
        let currentCommit = (try? run(["-C", root.path, "rev-parse", "--short", "HEAD"])) ?? "No commits yet"

        return RepositorySnapshot(
            branch: branch,
            currentCommit: currentCommit,
            changes: try changes(in: root),
            commits: try commits(in: root),
            documents: try documents(in: root)
        )
    }

    func changes(in root: URL) throws -> [GitChange] {
        let output = try run([
            "-C", root.path, "status", "--porcelain=v1", "-z", "--untracked-files=all"
        ], trimOutput: false)
        let records = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [GitChange] = []
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 4 else { index += 1; continue }
            let rawStatus = String(record.prefix(2))
            let status = rawStatus.trimmingCharacters(in: .whitespaces)
            let path = String(record.dropFirst(3))
            result.append(GitChange(status: status, path: path))
            index += (rawStatus.contains("R") || rawStatus.contains("C")) ? 2 : 1
        }
        return result
    }

    func commits(in root: URL, limit: Int = 250) throws -> [CommitSummary] {
        let format = "%H%x1f%h%x1f%aI%x1f%an%x1f%s%x1e"
        let output = try run([
            "-C", root.path, "log", "-n", String(limit), "--date=iso-strict", "--pretty=format:\(format)"
        ], allowEmptyRepository: true)
        return parseCommits(output)
    }

    func fileHistory(in root: URL, relativePath: String) throws -> [CommitSummary] {
        let format = "%H%x1f%h%x1f%aI%x1f%an%x1f%s%x1e"
        let output = try run([
            "-C", root.path, "log", "--follow", "--date=iso-strict",
            "--pretty=format:\(format)", "--", relativePath
        ], allowEmptyRepository: true)
        return parseCommits(output)
    }

    func filesChanged(in root: URL, commit: String) throws -> [GitChange] {
        let output = try run([
            "-C", root.path, "show", "--format=", "--name-status", commit
        ])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            return GitChange(status: String(parts[0]), path: String(parts.last!))
        }
    }

    func text(in root: URL, relativePath: String, at commit: String) throws -> String {
        try run(["-C", root.path, "show", "\(commit):\(relativePath)"], trimOutput: false)
    }

    func wordDiffFromWorkingFile(in root: URL, relativePath: String, from commit: String) throws -> String {
        let raw = try run([
            "-C", root.path, "diff", "--word-diff=plain", "--no-color", commit, "--", relativePath
        ], trimOutput: false)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                !line.hasPrefix("diff --git ") &&
                !line.hasPrefix("index ") &&
                !line.hasPrefix("--- ") &&
                !line.hasPrefix("+++ ") &&
                !line.hasPrefix("@@ ")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fileData(in root: URL, relativePath: String, at commit: String) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "show", "\(commit):./\(relativePath)"]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw GitClientError.commandFailed(
                arguments: process.arguments ?? [],
                message: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return data
    }

    func hasWorkingChange(in root: URL, relativePath: String) throws -> Bool {
        !(try run(["-C", root.path, "status", "--porcelain=v1", "--", relativePath])).isEmpty
    }

    func restoreFile(
        in root: URL,
        relativePath: String,
        from sourceCommit: CommitSummary,
        note: String
    ) throws -> FileRestoreResult {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNote.isEmpty else { throw FileNoteError.emptyNote }

        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let destination = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard destination.path.hasPrefix(rootURL.path + "/") else {
            throw FileNoteError.fileOutsideRepository
        }

        var safetyCommit: CommitSummary?
        if try hasWorkingChange(in: rootURL, relativePath: relativePath) {
            safetyCommit = try commitSelected(
                in: rootURL,
                paths: [relativePath],
                message: "Safety checkpoint before restoring \(destination.lastPathComponent)"
            )
        }

        let historicalData = try fileData(
            in: rootURL,
            relativePath: relativePath,
            at: sourceCommit.hash
        )
        try historicalData.write(to: destination, options: .atomic)

        let currentCommit = (try? run(["-C", rootURL.path, "rev-parse", "--short", "HEAD"])) ?? "No commits yet"
        _ = try CopyService().addFileNote(
            repositoryRoot: rootURL,
            relativePath: relativePath,
            eventType: "Restored",
            note: "Restored from \(sourceCommit.shortHash). \(cleanNote)",
            commit: currentCommit
        )

        return FileRestoreResult(
            restoredURL: destination,
            sourceCommit: sourceCommit,
            safetyCommit: safetyCommit
        )
    }

    /// Commits exactly the selected paths through a temporary index. The user's real index is
    /// never used to construct the commit, so unrelated staged work cannot leak into it.
    func commitSelected(
        in root: URL,
        paths: [String],
        message: String
    ) throws -> CommitSummary {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { throw GitClientError.emptyCommitMessage }
        let selectedPaths = Array(Set(paths)).sorted()
        guard !selectedPaths.isEmpty else { throw GitClientError.noFilesSelected }

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GittingToIt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }

        let temporaryIndex = temporaryFolder.appendingPathComponent("index")
        let environment = ["GIT_INDEX_FILE": temporaryIndex.path]

        if (try? run(["-C", root.path, "rev-parse", "--verify", "HEAD"])) != nil {
            _ = try run(["-C", root.path, "read-tree", "HEAD"], environment: environment)
        } else {
            _ = try run(["-C", root.path, "read-tree", "--empty"], environment: environment)
        }

        _ = try run(["-C", root.path, "add", "-A", "--"] + selectedPaths, environment: environment)
        let stagedNames = try run(
            ["-C", root.path, "diff", "--cached", "--name-only"],
            environment: environment
        )
        guard !stagedNames.isEmpty else { throw GitClientError.noSelectedChanges }

        _ = try run([
            "-C", root.path, "commit", "--no-verify", "--no-gpg-sign", "-m", cleanMessage
        ], environment: environment)

        // Bring only the committed paths in the real index forward to the new HEAD. Any staged
        // changes to unselected files stay staged exactly as they were.
        _ = try run(["-C", root.path, "reset", "-q", "HEAD", "--"] + selectedPaths)

        guard let commit = try commits(in: root, limit: 1).first else {
            throw GitClientError.commandFailed(arguments: ["log", "-1"], message: "The checkpoint was created but could not be read back.")
        }
        return commit
    }

    private func documents(in root: URL) throws -> [WritingDocument] {
        let output = try run([
            "-C", root.path, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
        ], trimOutput: false)

        let paths = Set(output.split(separator: "\0").map(String.init))
            .filter { path in
                let url = URL(fileURLWithPath: path)
                return Self.supportedWritingExtensions.contains(url.pathExtension.lowercased()) &&
                    url.lastPathComponent != "GittingToIt Notes.md"
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let datesByPath = documentDates(in: root)
        return paths.map { relativePath in
            let fileURL = root.appendingPathComponent(relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let gitDates = datesByPath[relativePath]
            return WritingDocument(
                relativePath: relativePath,
                createdAt: gitDates?.first ?? values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastCommittedAt: gitDates?.last,
                creationSource: gitDates?.first == nil ? .fileSystem : .gitHistory
            )
        }
    }

    private func documentDates(in root: URL) -> [String: (first: Date, last: Date)] {
        let history = try? run([
            "-C", root.path, "log", "--date=iso-strict", "--format=__GTDATE__%aI", "--name-only"
        ])
        var result: [String: (first: Date, last: Date)] = [:]
        var currentDate: Date?

        for line in (history ?? "").split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("__GTDATE__") {
                currentDate = Self.isoDate(String(text.dropFirst("__GTDATE__".count)))
            } else if !text.isEmpty, let date = currentDate {
                if let existing = result[text] {
                    result[text] = (first: date, last: existing.last)
                } else {
                    result[text] = (first: date, last: date)
                }
            }
        }
        return result
    }

    private func parseCommits(_ output: String) -> [CommitSummary] {
        output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\u{1f}", omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 5 else { return nil }
            return CommitSummary(
                hash: fields[0],
                shortHash: fields[1],
                date: Self.isoDate(fields[2]),
                author: fields[3],
                message: fields[4]
            )
        }
    }

    private static func isoDate(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    @discardableResult
    func run(
        _ arguments: [String],
        trimOutput: Bool = true,
        allowEmptyRepository: Bool = false,
        environment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let message = String(decoding: errorData, as: UTF8.self)

        if process.terminationStatus != 0 {
            if allowEmptyRepository && message.localizedCaseInsensitiveContains("does not have any commits") {
                return ""
            }
            throw GitClientError.commandFailed(
                arguments: arguments,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return trimOutput ? output.trimmingCharacters(in: .whitespacesAndNewlines) : output
    }
}
