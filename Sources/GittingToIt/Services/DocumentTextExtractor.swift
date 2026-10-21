import Foundation

enum DocumentTextExtractor {
    static let supportedExtensions: Set<String> = [
        "md", "markdown", "txt", "rtf", "html", "htm", "xhtml",
        "doc", "docx", "odt", "fodt"
    ]

    static func text(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "txt": return try String(contentsOf: url, encoding: .utf8)
        case "rtf", "doc", "docx", "odt": return try convertedText(from: url)
        case "html", "htm", "xhtml": return try visibleHTMLText(from: url)
        case "fodt": return try visibleOpenDocumentText(from: url)
        default: throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private static func convertedText(from url: URL) throws -> String {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("GittingToIt-Extract-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", "--", url.path]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try handle.close()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return try String(contentsOf: output, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func visibleHTMLText(from url: URL) throws -> String {
        var html = try String(contentsOf: url, encoding: .utf8)
        html = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</li>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities { html = html.replacingOccurrences(of: entity, with: value) }
        return html.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func visibleOpenDocumentText(from url: URL) throws -> String {
        var xml = try String(contentsOf: url, encoding: .utf8)
        xml = xml.replacingOccurrences(of: #"(?i)</text:p>|</text:h>|<text:line-break\s*/>"#, with: "\n", options: .regularExpression)
        xml = xml.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"]
        for (entity, value) in entities { xml = xml.replacingOccurrences(of: entity, with: value) }
        return xml.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
