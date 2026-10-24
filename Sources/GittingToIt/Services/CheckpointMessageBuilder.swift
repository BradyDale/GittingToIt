import Foundation

enum CheckpointMessageBuilder {
    static func summary(for changes: [GitChange]) -> String {
        var created: [String] = []
        var changed: [String] = []
        var deleted: [String] = []
        var forked: [(source: String, copy: String)] = []

        for change in changes {
            let status = change.status
            if status == "??" || status.contains("A") {
                if let source = sourcePathForDatedCopy(change.path) {
                    forked.append((source, change.path))
                } else {
                    created.append(change.path)
                }
            } else if status.contains("D") {
                deleted.append(change.path)
            } else {
                changed.append(change.path)
            }
        }

        return (
            created.sorted().map { "CREATED: \($0)" } +
            changed.sorted().map { "CHANGED: \($0)" } +
            deleted.sorted().map { "DELETED: \($0)" } +
            forked.sorted { $0.copy < $1.copy }.map { "FORKED: \($0.source) with \($0.copy)" }
        ).joined(separator: "\n")
    }

    private static func sourcePathForDatedCopy(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let originalStem = stem.replacingOccurrences(
            of: #" c \d{8}(?: \d+)?$"#,
            with: "",
            options: .regularExpression
        )
        guard originalStem != stem else { return nil }
        let filename = ext.isEmpty ? originalStem : "\(originalStem).\(ext)"
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? filename : (directory as NSString).appendingPathComponent(filename)
    }
}
