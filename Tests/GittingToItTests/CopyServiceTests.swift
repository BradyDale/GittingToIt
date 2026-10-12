import Foundation
import Testing
@testable import GittingToIt

struct CopyServiceTests {
    @Test func copyUsesCreationDateAndWritesHumanReadableNotes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Chapter 4.md")
        try "Original words".write(to: source, atomically: true, encoding: .utf8)
        let date = Date(timeIntervalSince1970: 1_796_000_000)

        let result = try CopyService().makeRelatedCopy(
            repositoryRoot: root,
            relativePath: "Chapter 4.md",
            purpose: "Try the ending without the courtroom scene.",
            sourceCommit: "abc1234",
            now: date
        )

        #expect(result.copyURL.lastPathComponent.contains(" c 202611"))
        #expect(try String(contentsOf: result.copyURL, encoding: .utf8) == "Original words")
        let notes = try String(contentsOf: result.notesURL, encoding: .utf8)
        #expect(notes.contains("Try the ending without the courtroom scene."))
        #expect(notes.contains("abc1234"))
    }

    @Test func copyingACopyDoesNotStackDateSuffixes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Chapter 4 c 20260928.md")
        try "Alternate words".write(to: source, atomically: true, encoding: .utf8)

        let result = try CopyService().makeRelatedCopy(
            repositoryRoot: root,
            relativePath: source.lastPathComponent,
            purpose: "A second direction.",
            sourceCommit: "def5678"
        )

        #expect(!result.copyURL.lastPathComponent.contains("20260928 c"))
    }

    @Test func copyRequiresPurposeNote() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Words".write(to: root.appendingPathComponent("Draft.md"), atomically: true, encoding: .utf8)

        #expect(throws: RelatedCopyError.self) {
            try CopyService().makeRelatedCopy(
                repositoryRoot: root,
                relativePath: "Draft.md",
                purpose: "   ",
                sourceCommit: "abc1234"
            )
        }
    }

    @Test func arbitraryFileNoteIsStoredBesideTheDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Words".write(to: root.appendingPathComponent("Draft.md"), atomically: true, encoding: .utf8)
        let notesURL = try CopyService().addFileNote(
            repositoryRoot: root,
            relativePath: "Draft.md",
            eventType: "Uploaded to Google Docs",
            note: "This may now be the canonical version.",
            commit: "abc1234"
        )

        #expect(notesURL.deletingLastPathComponent() == root)
        let notes = try String(contentsOf: notesURL, encoding: .utf8)
        #expect(notes.contains("Uploaded to Google Docs"))
        #expect(notes.contains("canonical version"))
    }
}
