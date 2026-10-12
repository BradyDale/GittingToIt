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

struct GitClientCommitTests {
    @Test func selectedCommitDoesNotIncludeOrUnstageOtherWork() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "A one".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "B one".write(to: root.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])

        try "A two".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "B two".write(to: root.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "B.md"])

        let commit = try git.commitSelected(in: root, paths: ["A.md"], message: "Revise A")

        #expect(commit.message == "Revise A")
        let committedFiles = try git.run(["-C", root.path, "show", "--format=", "--name-only", "HEAD"])
        #expect(committedFiles == "A.md")
        let stagedFiles = try git.run(["-C", root.path, "diff", "--cached", "--name-only"])
        #expect(stagedFiles == "B.md")
        #expect(try String(contentsOf: root.appendingPathComponent("B.md"), encoding: .utf8) == "B two")
    }


    @Test func restorePreservesCurrentFileAndLeavesOtherWorkUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "Old chapter".write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        try "Other one".write(to: root.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])
        let source = try #require(git.commits(in: root, limit: 1).first)

        try "Current chapter".write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        try "Other two".write(to: root.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)

        let result = try git.restoreFile(
            in: root,
            relativePath: "Chapter.md",
            from: source,
            note: "Return to the quieter opening."
        )

        #expect(result.safetyCommit != nil)
        #expect(try String(contentsOf: root.appendingPathComponent("Chapter.md"), encoding: .utf8) == "Old chapter")
        #expect(try String(contentsOf: root.appendingPathComponent("Other.md"), encoding: .utf8) == "Other two")
        let preserved = try git.run(["-C", root.path, "show", "HEAD:Chapter.md"])
        #expect(preserved == "Current chapter")
        let status = try git.run(["-C", root.path, "status", "--porcelain=v1"])
        #expect(status.contains("Chapter.md"))
        #expect(status.contains("Other.md"))
        #expect(status.contains(CopyService.notesFilename))
    }
}
