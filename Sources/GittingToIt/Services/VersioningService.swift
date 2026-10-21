import Foundation

enum VersioningError: LocalizedError {
    case selectAtLeastTwo
    case documentNotVersioned

    var errorDescription: String? {
        switch self {
        case .selectAtLeastTwo: return "Select at least two files that are versions of one another."
        case .documentNotVersioned: return "This file is not part of a version set."
        }
    }
}

struct VersionFamily: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var members: [String]
    var canonicalPath: String?
}

struct VersionNoteEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date?
    let filename: String
    let text: String
}

struct VersioningService: Sendable {
    static let metadataDirectory = ".gittingtoit"
    static let metadataFilename = "version-families.json"

    func families(repositoryRoot: URL) -> [VersionFamily] {
        guard let data = try? Data(contentsOf: registryURL(repositoryRoot: repositoryRoot)),
              let decoded = try? JSONDecoder().decode([VersionFamily].self, from: data) else { return [] }
        return decoded
    }

    func family(repositoryRoot: URL, containing relativePath: String) -> VersionFamily? {
        families(repositoryRoot: repositoryRoot).first { $0.members.contains(relativePath) }
    }

    @discardableResult
    func associate(repositoryRoot: URL, paths: [String]) throws -> VersionFamily {
        let cleanPaths = Array(Set(paths)).sorted()
        guard cleanPaths.count >= 2 else { throw VersioningError.selectAtLeastTwo }

        var allFamilies = families(repositoryRoot: repositoryRoot)
        let relatedIDs = Set(allFamilies.filter { family in
            !Set(family.members).isDisjoint(with: cleanPaths)
        }.map(\.id))
        let related = allFamilies.filter { relatedIDs.contains($0.id) }
        let mergedMembers = Array(Set(cleanPaths + related.flatMap(\.members))).sorted()
        let existingCanonical = related.compactMap(\.canonicalPath).first { mergedMembers.contains($0) }
        let family = VersionFamily(
            id: related.first?.id ?? UUID(),
            members: mergedMembers,
            canonicalPath: existingCanonical ?? cleanPaths.first
        )
        allFamilies.removeAll { relatedIDs.contains($0.id) }
        allFamilies.append(family)
        try save(allFamilies, repositoryRoot: repositoryRoot)
        return family
    }

    func makeCanonical(repositoryRoot: URL, relativePath: String) throws {
        var allFamilies = families(repositoryRoot: repositoryRoot)
        guard let index = allFamilies.firstIndex(where: { $0.members.contains(relativePath) }) else {
            throw VersioningError.documentNotVersioned
        }
        allFamilies[index].canonicalPath = relativePath
        try save(allFamilies, repositoryRoot: repositoryRoot)
    }

    func remove(repositoryRoot: URL, relativePath: String) throws {
        var allFamilies = families(repositoryRoot: repositoryRoot)
        guard let index = allFamilies.firstIndex(where: { $0.members.contains(relativePath) }) else {
            throw VersioningError.documentNotVersioned
        }
        allFamilies[index].members.removeAll { $0 == relativePath }
        if allFamilies[index].canonicalPath == relativePath {
            allFamilies[index].canonicalPath = allFamilies[index].members.first
        }
        if allFamilies[index].members.count < 2 {
            allFamilies.remove(at: index)
        }
        try save(allFamilies, repositoryRoot: repositoryRoot)
    }

    func combinedNotes(repositoryRoot: URL, family: VersionFamily) -> [VersionNoteEntry] {
        let memberNames = Set(family.members.map { URL(fileURLWithPath: $0).lastPathComponent })
        let noteURLs = Set(family.members.map {
            CopyService().notesURL(repositoryRoot: repositoryRoot, relativePath: $0)
        })
        var results: [VersionNoteEntry] = []
        for url in noteURLs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let blocks = text.components(separatedBy: "\n## ").dropFirst()
            for rawBlock in blocks {
                let block = "## " + rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let filename = memberNames.first(where: { block.contains($0) }) else { continue }
                let body = block.split(separator: "\n", omittingEmptySubsequences: false)
                    .dropFirst()
                    .filter { !$0.hasPrefix("- Date: ") && !$0.hasPrefix("- File: ") }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(VersionNoteEntry(date: entryDate(in: block), filename: filename, text: body))
            }
        }
        return results.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    private func registryURL(repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent(Self.metadataDirectory, isDirectory: true)
            .appendingPathComponent(Self.metadataFilename)
    }

    private func save(_ families: [VersionFamily], repositoryRoot: URL) throws {
        let url = registryURL(repositoryRoot: repositoryRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(families.sorted { $0.id.uuidString < $1.id.uuidString })
            .write(to: url, options: .atomic)
    }

    private func entryDate(in block: String) -> Date? {
        if let line = block.split(separator: "\n").first(where: { $0.hasPrefix("- Date: ") }) {
            return ISO8601DateFormatter().date(from: String(line.dropFirst(8)))
        }
        guard let heading = block.split(separator: "\n").first else { return nil }
        let title = String(heading).replacingOccurrences(of: "## ", with: "")
        guard let separator = title.range(of: " — ") else { return nil }
        let value = String(title[..<separator.lowerBound])
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.date(from: value)
    }
}
