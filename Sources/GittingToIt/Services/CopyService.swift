import Foundation

enum RelatedCopyError: LocalizedError {
    case emptyNote
    case sourceOutsideRepository
    case sourceMissing

    var errorDescription: String? {
        switch self {
        case .emptyNote: return "Please explain why you are making this version."
        case .sourceOutsideRepository: return "The selected file is outside this repository."
        case .sourceMissing: return "The selected source file no longer exists."
        }
    }
}

enum FileNoteError: LocalizedError {
    case emptyNote
    case fileOutsideRepository

    var errorDescription: String? {
        switch self {
        case .emptyNote: return "Please add a short note."
        case .fileOutsideRepository: return "The selected file is outside this repository."
        }
    }
}

struct CopyService: Sendable {
    static let notesFilename = "GittingToIt Notes.md"

    func makeRelatedCopy(
        repositoryRoot: URL,
        relativePath: String,
        purpose: String,
        sourceCommit: String,
        now: Date = Date()
    ) throws -> RelatedCopyResult {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty else { throw RelatedCopyError.emptyNote }

        let root = repositoryRoot.standardizedFileURL
        let source = root.appendingPathComponent(relativePath).standardizedFileURL
        guard source.path.hasPrefix(root.path + "/") else { throw RelatedCopyError.sourceOutsideRepository }
        guard FileManager.default.fileExists(atPath: source.path) else { throw RelatedCopyError.sourceMissing }

        return try makeRelatedCopy(
            repositoryRoot: root,
            relativePath: relativePath,
            contents: Data(contentsOf: source),
            purpose: cleanPurpose,
            sourceCommit: sourceCommit,
            now: now
        )
    }

    func makeRelatedCopy(
        repositoryRoot: URL,
        relativePath: String,
        contents: Data,
        purpose: String,
        sourceCommit: String,
        now: Date = Date()
    ) throws -> RelatedCopyResult {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty else { throw RelatedCopyError.emptyNote }

        let root = repositoryRoot.standardizedFileURL
        let source = root.appendingPathComponent(relativePath).standardizedFileURL
        guard source.path.hasPrefix(root.path + "/") else { throw RelatedCopyError.sourceOutsideRepository }

        let copy = availableCopyURL(for: source, now: now)
        let notes = source.deletingLastPathComponent().appendingPathComponent(Self.notesFilename)
        let oldNotes = (try? String(contentsOf: notes, encoding: .utf8)) ?? "# GittingToIt File Notes\n"
        let entry = noteEntry(
            source: source.lastPathComponent,
            copy: copy.lastPathComponent,
            purpose: cleanPurpose,
            sourceCommit: sourceCommit,
            now: now
        )

        try contents.write(to: copy, options: .atomic)
        do {
            try notesWithNewestEntry(entry, before: oldNotes)
                .write(to: notes, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }

        return RelatedCopyResult(sourceURL: source, copyURL: copy, notesURL: notes)
    }

    func notesURL(repositoryRoot: URL, relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.notesFilename)
    }

    func isKnownFamilyMember(repositoryRoot: URL, relativePath: String) -> Bool {
        let file = repositoryRoot.appendingPathComponent(relativePath)
        let notes = notesURL(repositoryRoot: repositoryRoot, relativePath: relativePath)
        guard let contents = try? String(contentsOf: notes, encoding: .utf8) else { return false }
        return contents.contains(file.lastPathComponent) && contents.contains("- Event: Copied")
    }

    /// Adds a required revision note for every selected document already known to belong to a
    /// family, and returns the original paths plus the human-readable notes files to commit.
    func documentFamilyChanges(
        repositoryRoot: URL,
        paths: [String],
        checkpointMessage: String,
        commit: String
    ) throws -> [String] {
        var pathsToCommit = Set(paths)
        for path in paths where URL(fileURLWithPath: path).lastPathComponent != Self.notesFilename {
            guard isKnownFamilyMember(repositoryRoot: repositoryRoot, relativePath: path) else { continue }
            let notes = try addFileNote(
                repositoryRoot: repositoryRoot,
                relativePath: path,
                eventType: "Revised",
                note: checkpointMessage,
                commit: commit
            )
            let relativeNotes = notes.path.replacingOccurrences(
                of: repositoryRoot.standardizedFileURL.path + "/",
                with: ""
            )
            pathsToCommit.insert(relativeNotes)
        }
        return pathsToCommit.sorted()
    }

    @discardableResult
    func addFileNote(
        repositoryRoot: URL,
        relativePath: String,
        eventType: String,
        note: String,
        commit: String,
        now: Date = Date()
    ) throws -> URL {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNote.isEmpty else { throw FileNoteError.emptyNote }

        let root = repositoryRoot.standardizedFileURL
        let file = root.appendingPathComponent(relativePath).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw FileNoteError.fileOutsideRepository }

        let notes = notesURL(repositoryRoot: root, relativePath: relativePath)
        let oldNotes = (try? String(contentsOf: notes, encoding: .utf8)) ?? "# GittingToIt File Notes\n"
        let safeNote = cleanNote.replacingOccurrences(of: "\n", with: " ")
        let entry = """


        ## \(file.lastPathComponent) — \(eventType)

        - Date: \(Self.noteDate(now))
        - File: `\(file.lastPathComponent)`
        - Related commit: `\(commit)`
        - Note: \(safeNote)
        """
        try notesWithNewestEntry(entry, before: oldNotes)
            .write(to: notes, atomically: true, encoding: .utf8)
        return notes
    }

    func editableNotesDraft(
        repositoryRoot: URL,
        relativePath: String,
        now: Date = Date()
    ) throws -> String {
        let root = repositoryRoot.standardizedFileURL
        let file = root.appendingPathComponent(relativePath).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw FileNoteError.fileOutsideRepository }

        let notes = notesURL(repositoryRoot: root, relativePath: relativePath)
        let oldNotes = (try? String(contentsOf: notes, encoding: .utf8)) ?? "# GittingToIt File Notes\n"
        let entry = "\n\n## \(Self.diaryDate(now)) — \(file.lastPathComponent)\n\n\n\n"
        return notesWithNewestEntry(entry, before: oldNotes)
    }

    func saveNotes(repositoryRoot: URL, relativePath: String, contents: String) throws -> URL {
        let root = repositoryRoot.standardizedFileURL
        let file = root.appendingPathComponent(relativePath).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw FileNoteError.fileOutsideRepository }
        let notes = notesURL(repositoryRoot: root, relativePath: relativePath)
        try contents.write(to: notes, atomically: true, encoding: .utf8)
        return notes
    }

    private func availableCopyURL(for source: URL, now: Date) -> URL {
        let folder = source.deletingLastPathComponent()
        let ext = source.pathExtension
        let filename = source.deletingPathExtension().lastPathComponent
        let rootName = filename.replacingOccurrences(
            of: #" c \d{8}(?: \d+)?$"#,
            with: "",
            options: .regularExpression
        )
        let date = Self.filenameDate(now)
        var counter = 1

        while true {
            let suffix = counter == 1 ? "" : " \(counter)"
            let name = "\(rootName) c \(date)\(suffix)"
            let candidate = folder.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func noteEntry(
        source: String,
        copy: String,
        purpose: String,
        sourceCommit: String,
        now: Date
    ) -> String {
        let safePurpose = purpose.replacingOccurrences(of: "\n", with: " ")
        return """


        ## \(copy)

        - Event: Copied
        - Date: \(Self.noteDate(now))
        - Source: `\(source)`
        - Source commit: `\(sourceCommit)`
        - Purpose: \(safePurpose)
        - Status: Active experiment
        """
    }

    private func notesWithNewestEntry(_ entry: String, before oldNotes: String) -> String {
        let header = "# GittingToIt File Notes"
        let body: String
        if oldNotes.hasPrefix(header) {
            body = String(oldNotes.dropFirst(header.count)).trimmingCharacters(in: .newlines)
        } else {
            body = oldNotes.trimmingCharacters(in: .newlines)
        }
        return header + entry + (body.isEmpty ? "\n" : "\n" + body + "\n")
    }

    private static func filenameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func noteDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }

    private static func diaryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
