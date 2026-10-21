import Foundation

struct RepositoryReference: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var folderURL: URL

    init(id: UUID = UUID(), displayName: String, folderURL: URL) {
        self.id = id
        self.displayName = displayName
        self.folderURL = folderURL.standardizedFileURL
    }
}

struct GitChange: Hashable, Identifiable, Sendable {
    let status: String
    let path: String
    var id: String { status + "\u{0}" + path }
}

struct IgnoreFileResult: Sendable {
    let path: String
    let rule: String
    let wasTracked: Bool
}

struct CommitSummary: Hashable, Identifiable, Sendable {
    let hash: String
    let shortHash: String
    let date: Date?
    let author: String
    let message: String
    let historicalPath: String?
    var id: String { hash }

    init(
        hash: String,
        shortHash: String,
        date: Date?,
        author: String,
        message: String,
        historicalPath: String? = nil
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.date = date
        self.author = author
        self.message = message
        self.historicalPath = historicalPath
    }
}

struct WritingDocument: Hashable, Identifiable, Sendable {
    enum DateSource: String, Sendable {
        case gitHistory = "Git history"
        case fileSystem = "File system"
        case unavailable = "Unknown"
    }

    let relativePath: String
    let createdAt: Date?
    let modifiedAt: Date?
    let lastCommittedAt: Date?
    let creationSource: DateSource

    var id: String { relativePath }
    var name: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var fileExtension: String { URL(fileURLWithPath: relativePath).pathExtension.lowercased() }
}

struct RepositorySnapshot: Sendable {
    let branch: String
    let currentCommit: String
    let changes: [GitChange]
    let commits: [CommitSummary]
    let documents: [WritingDocument]
}

struct RelatedCopyResult: Sendable {
    let sourceURL: URL
    let copyURL: URL
    let notesURL: URL
}

struct FileRestoreResult: Sendable {
    let restoredURL: URL
    let sourceCommit: CommitSummary
    let safetyCommit: CommitSummary?
}

enum VersioningAction: String, Identifiable, Sendable {
    case selectVersions
    case viewVersions
    case reviewDocumentation
    case compareVersions
    case makeCanonical
    case removeVersion

    var id: String { rawValue }
}

struct VersionComparison: Sendable {
    let earlierText: String
    let laterText: String
    let markedUpText: String
}
