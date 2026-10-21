import AppKit
import SwiftUI

struct CompareVersionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let family: VersionFamily
    let startingDocument: WritingDocument

    @State private var earlierPath = ""
    @State private var laterPath = ""
    @State private var comparison: VersionComparison?
    @State private var mode = Mode.markedUp
    @State private var selectedChange = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case markedUp = "Marked Up"
        case earlier = "Earlier"
        case later = "Later"
        var id: String { rawValue }
    }

    private var documents: [WritingDocument] {
        library.documents(in: family).filter { DocumentTextExtractor.supportedExtensions.contains($0.fileExtension) }
    }
    private var displayedText: String {
        guard let comparison else { return "Choose two versions to compare." }
        switch mode {
        case .markedUp: return comparison.markedUpText
        case .earlier: return comparison.earlierText
        case .later: return comparison.laterText
        }
    }
    private var changeCount: Int {
        guard let comparison else { return 0 }
        return WriterDiffTextView.changeCount(in: comparison.markedUpText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COMPARE VERSIONS")
                    .font(.system(.title2, design: .rounded).weight(.black))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
            }

            HStack {
                Picker("Most recent / revised", selection: $laterPath) {
                    ForEach(documents) { Text($0.name).tag($0.relativePath) }
                }
                Picker("Compared against", selection: $earlierPath) {
                    ForEach(documents) { Text($0.name).tag($0.relativePath) }
                }
                Button("Compare") { loadComparison() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(earlierPath.isEmpty || laterPath.isEmpty || earlierPath == laterPath || isLoading)
            }

            HStack {
                ForEach(Mode.allCases) { option in
                    Button(option.rawValue) { mode = option }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(mode == option ? GTTheme.yellow : .white)
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.25))
                }
                Text("Showing: \(mode.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Previous Change") { selectedChange = max(0, selectedChange - 1) }
                    .disabled(mode != .markedUp || selectedChange <= 0)
                Text(changeCount == 0 ? "No changes" : "\(selectedChange + 1) of \(changeCount)")
                    .monospacedDigit().frame(minWidth: 80)
                Button("Next Change") { selectedChange = min(changeCount - 1, selectedChange + 1) }
                    .disabled(mode != .markedUp || selectedChange >= changeCount - 1)
            }

            if isLoading {
                ProgressView("Comparing versions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("Comparison unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                WriterDiffTextView(text: displayedText, markedUp: mode == .markedUp, selectedChange: selectedChange)
                    .id(mode)
                    .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(minWidth: 950, minHeight: 700)
        .onAppear {
            guard documents.count >= 2 else {
                errorMessage = "Compare Versions needs two supported writing files in this version set. Supported formats include Markdown, text, RTF, HTML, Word, and OpenDocument."
                return
            }
            let mostRecentFirst = documents.sorted {
                ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
            if documents.count == 2 {
                laterPath = mostRecentFirst[0].relativePath
                earlierPath = mostRecentFirst[1].relativePath
            } else {
                laterPath = documents.contains(where: { $0.relativePath == startingDocument.relativePath })
                    ? startingDocument.relativePath : mostRecentFirst[0].relativePath
                earlierPath = family.canonicalPath ?? mostRecentFirst.first(where: { $0.relativePath != laterPath })?.relativePath ?? ""
                if earlierPath == laterPath {
                    earlierPath = mostRecentFirst.first(where: { $0.relativePath != laterPath })?.relativePath ?? ""
                }
            }
            loadComparison()
        }
    }

    private func loadComparison() {
        guard let earlier = documents.first(where: { $0.relativePath == earlierPath }),
              let later = documents.first(where: { $0.relativePath == laterPath }) else { return }
        isLoading = true
        errorMessage = nil
        selectedChange = 0
        Task {
            do { comparison = try await library.compareVersions(earlier: earlier, later: later) }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}

private struct WriterDiffTextView: NSViewRepresentable {
    let text: String
    let markedUp: Bool
    let selectedChange: Int

    static func changeCount(in text: String) -> Int {
        let pattern = #"\[-[\s\S]*?-\]|\{\+[\s\S]*?\+\}"#
        return (try? NSRegularExpression(pattern: pattern).numberOfMatches(
            in: text, range: NSRange(text.startIndex..., in: text)
        )) ?? 0
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = NSSize(width: 20, height: 20)
        view.backgroundColor = .white
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let rendered = Self.render(text: text, markedUp: markedUp, selectedChange: selectedChange)
        view.textStorage?.setAttributedString(rendered.text)
        if markedUp, rendered.ranges.indices.contains(selectedChange) {
            view.scrollRangeToVisible(rendered.ranges[selectedChange])
        }
    }

    private static func render(text: String, markedUp: Bool, selectedChange: Int) -> (text: NSAttributedString, ranges: [NSRange]) {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.textColor
        ]
        guard markedUp else { return (NSAttributedString(string: text, attributes: base), []) }
        let result = NSMutableAttributedString(string: "")
        let regex = try! NSRegularExpression(pattern: #"\[-([\s\S]*?)-\]|\{\+([\s\S]*?)\+\}"#)
        let source = text as NSString
        var cursor = 0
        var ranges: [NSRange] = []
        for (index, match) in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).enumerated() {
            if match.range.location > cursor {
                result.append(NSAttributedString(string: source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), attributes: base))
            }
            let addition = match.range(at: 2).location != NSNotFound
            let contentRange = addition ? match.range(at: 2) : match.range(at: 1)
            var style = base
            style[.foregroundColor] = addition ? NSColor.systemGreen : NSColor.systemRed
            if addition { style[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.13) }
            else { style[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if index == selectedChange { style[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.38) }
            let outputRange = NSRange(location: result.length, length: contentRange.length)
            result.append(NSAttributedString(string: source.substring(with: contentRange), attributes: style))
            ranges.append(outputRange)
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            result.append(NSAttributedString(string: source.substring(from: cursor), attributes: base))
        }
        return (result, ranges)
    }
}
