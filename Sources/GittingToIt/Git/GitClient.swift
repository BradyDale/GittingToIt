import Foundation

enum GitClientError: LocalizedError {
    case commandFailed(arguments: [String], message: String)
    case notARepository(URL)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, message):
            return "Git could not complete ‘git \(arguments.joined(separator: " "))’: \(message)"
        case let .notARepository(url):
            return "\(url.lastPathComponent) is not a Git repository."
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
        let output = try run(["-C", root.path, "status", "--porcelain=v1", "--untracked-files=all"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let text = String(line)
            guard text.count >= 4 else { return nil }
            let status = String(text.prefix(2)).trimmingCharacters(in: .whitespaces)
            let rawPath = String(text.dropFirst(3))
            let path = rawPath.components(separatedBy: " -> ").last ?? rawPath
            return GitChange(status: status, path: path.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
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

        return paths.map { relativePath in
            let fileURL = root.appendingPathComponent(relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let gitDates = gitDates(in: root, relativePath: relativePath)
            return WritingDocument(
                relativePath: relativePath,
                createdAt: gitDates.first ?? values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastCommittedAt: gitDates.last,
                creationSource: gitDates.first == nil ? .fileSystem : .gitHistory
            )
        }
    }

    private func gitDates(in root: URL, relativePath: String) -> (first: Date?, last: Date?) {
        let allDates = try? run([
            "-C", root.path, "log", "--follow", "--format=%aI", "--", relativePath
        ])
        let dates = (allDates ?? "").split(separator: "\n").compactMap {
            Self.isoDate(String($0))
        }
        return (dates.last, dates.first)
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
        allowEmptyRepository: Bool = false
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
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
