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

    @Test func historicalForkCreatesANewFileWithoutChangingCurrentDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Chapter.md")
        try "Current words".write(to: source, atomically: true, encoding: .utf8)
        let result = try CopyService().makeRelatedCopy(
            repositoryRoot: root,
            relativePath: "Chapter.md",
            contents: Data("Earlier words".utf8),
            purpose: "Reconsider the quieter opening.",
            sourceCommit: "abc1234"
        )

        #expect(try String(contentsOf: source, encoding: .utf8) == "Current words")
        #expect(try String(contentsOf: result.copyURL, encoding: .utf8) == "Earlier words")
        #expect(try String(contentsOf: result.notesURL, encoding: .utf8).contains("Reconsider the quieter opening."))
    }

    @Test func editableNotesDraftStartsWithANewDatedEntryAboveOlderNotes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Words".write(to: root.appendingPathComponent("Draft.md"), atomically: true, encoding: .utf8)
        let service = CopyService()
        _ = try service.addFileNote(
            repositoryRoot: root,
            relativePath: "Draft.md",
            eventType: "Note",
            note: "Older thought",
            commit: "abc1234",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let draft = try service.editableNotesDraft(
            repositoryRoot: root,
            relativePath: "Draft.md",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(draft.hasPrefix("# GittingToIt File Notes\n\n## "))
        #expect(draft.contains("Draft.md\n\n\n\n"))
        #expect(try #require(draft.range(of: "Draft.md")).lowerBound < #require(draft.range(of: "Older thought")).lowerBound)
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

    @Test func familyChangeAddsRevisionDocumentationToCheckpointPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "Original".write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        let service = CopyService()
        let copy = try service.makeRelatedCopy(
            repositoryRoot: root,
            relativePath: "Chapter.md",
            purpose: "Try a different narrator.",
            sourceCommit: "abc1234"
        )
        let copyName = copy.copyURL.lastPathComponent

        #expect(service.isKnownFamilyMember(repositoryRoot: root, relativePath: "Chapter.md"))
        #expect(service.isKnownFamilyMember(repositoryRoot: root, relativePath: copyName))

        let paths = try service.documentFamilyChanges(
            repositoryRoot: root,
            paths: [copyName],
            checkpointMessage: "The new narrator makes the opening clearer.",
            commit: "def5678"
        )

        #expect(paths.contains(copyName))
        #expect(paths.contains(CopyService.notesFilename))
        let notes = try String(contentsOf: copy.notesURL, encoding: .utf8)
        #expect(notes.contains("- Event: Copied"))
        #expect(notes.contains("Revised"))
        #expect(notes.contains("new narrator makes the opening clearer"))
    }
}

struct GitClientCommitTests {
    @Test func ignoreOnlyCheckpointFiltersStaleIgnoredSelections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("cover.jpg"))
        _ = try git.ignoreFiles(
            in: root,
            relativePaths: ["cover.jpg"],
            rules: ["*.jpg"]
        )

        let commit = try git.commitSelected(
            in: root,
            paths: [".gitignore", "cover.jpg"],
            message: "Ignore images"
        )

        #expect(commit.message == "Ignore images")
        #expect(try git.run(["-C", root.path, "show", "--format=", "--name-only", "HEAD"]) == ".gitignore")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("cover.jpg").path))
    }

    @Test func batchDSStoreIgnoreFindsAlreadyTrackedCopies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        let nested = root.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "finder data".write(to: nested.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "-f", ".gitignore", "Drafts/.DS_Store"])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])

        let results = try git.ignoreFiles(
            in: root,
            relativePaths: [],
            rules: [".DS_Store"],
            includeEveryTrackedDSStore: true
        )

        #expect(results.contains { $0.path == "Drafts/.DS_Store" && $0.wasTracked })
    }

    @Test func ignoreUntrackedFileAddsExactRuleWithoutDeletingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        let file = root.appendingPathComponent("Audio/interview.mp3")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: file)

        let result = try git.ignoreFile(in: root, relativePath: "Audio/interview.mp3")

        #expect(!result.wasTracked)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try git.run(["-C", root.path, "check-ignore", "Audio/interview.mp3"]) == "Audio/interview.mp3")
    }

    @Test func ignoreTrackedFileStopsTrackingAtNextCheckpointWithoutDeletingIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        let file = root.appendingPathComponent("private notes.txt")
        try "Keep me".write(to: file, atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])

        let result = try git.ignoreFile(in: root, relativePath: "private notes.txt")
        _ = try git.commitSelected(
            in: root,
            paths: ["private notes.txt", ".gitignore"],
            stopTrackingPaths: ["private notes.txt"],
            message: "Ignore private notes"
        )

        #expect(result.wasTracked)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try git.run(["-C", root.path, "ls-files", "--", "private notes.txt"]).isEmpty)
        #expect(try git.run(["-C", root.path, "check-ignore", "private notes.txt"]) == "private notes.txt")
    }

    @Test func newRepositoryStartsWithAPrivateIgnoredFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        let privateFolder = root.appendingPathComponent("Git Ignore", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: privateFolder.path))

        try "private".write(
            to: privateFolder.appendingPathComponent("Anything.txt"),
            atomically: true,
            encoding: .utf8
        )
        let ignored = try git.run(["-C", root.path, "check-ignore", "Git Ignore/Anything.txt"])
        #expect(ignored == "Git Ignore/Anything.txt")
    }

    @Test func commandRunnerHandlesOutputLargerThanAPipeBuffer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        let largeText = String(repeating: "A long writing line for output testing.\n", count: 20_000)
        try largeText.write(to: root.appendingPathComponent("Long Draft.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Large draft"])

        let recovered = try git.run(
            ["-C", root.path, "show", "HEAD:Long Draft.md"],
            trimOutput: false
        )

        #expect(recovered == largeText)
    }

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

    @Test func wordDiffExplainsHistoricalChangesToCurrentFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "The river was quiet.".write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])
        let source = try #require(git.commits(in: root, limit: 1).first)

        try "The river was loud.".write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        let diff = try git.wordDiffFromWorkingFile(in: root, relativePath: "Chapter.md", from: source.hash)

        #expect(diff.contains("[-quiet.-]"))
        #expect(diff.contains("{+loud.+}"))
    }

    @Test func fileHistoryPreviewsAndDiffsVersionsFromBeforeARename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "The old opening.".write(
            to: root.appendingPathComponent("First Draft.md"), atomically: true, encoding: .utf8
        )
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Old title"])
        let oldHash = try git.run(["-C", root.path, "rev-parse", "HEAD"])

        _ = try git.run(["-C", root.path, "mv", "First Draft.md", "ONE.md"])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Rename the chapter"])
        try "The new opening.".write(
            to: root.appendingPathComponent("ONE.md"), atomically: true, encoding: .utf8
        )

        let history = try git.fileHistory(in: root, relativePath: "ONE.md")
        let rename = try #require(history.first { $0.message == "Rename the chapter" })
        let oldVersion = try #require(history.first { $0.hash == oldHash })

        #expect(rename.historicalPath == "ONE.md")
        #expect(oldVersion.historicalPath == "First Draft.md")
        #expect(try git.text(
            in: root,
            relativePath: try #require(oldVersion.historicalPath),
            at: oldVersion.hash
        ) == "The old opening.")

        let diff = try git.wordDiffFromWorkingFile(
            in: root,
            relativePath: "ONE.md",
            historicalPath: oldVersion.historicalPath,
            from: oldVersion.hash
        )
        #expect(diff.contains("[-old-]"))
        #expect(diff.contains("{+new+}"))
    }

    @Test func restoreFromBeforeRenameWritesToTheCurrentFilename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "Original words".write(
            to: root.appendingPathComponent("Old Name.md"), atomically: true, encoding: .utf8
        )
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Original"])
        _ = try git.run(["-C", root.path, "mv", "Old Name.md", "Current Name.md"])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Rename"])
        try "Current words".write(
            to: root.appendingPathComponent("Current Name.md"), atomically: true, encoding: .utf8
        )

        let source = try #require(
            git.fileHistory(in: root, relativePath: "Current Name.md").first { $0.message == "Original" }
        )
        _ = try git.restoreFile(
            in: root,
            relativePath: "Current Name.md",
            from: source,
            note: "Recover the original opening."
        )

        #expect(try String(
            contentsOf: root.appendingPathComponent("Current Name.md"), encoding: .utf8
        ) == "Original words")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Old Name.md").path))
    }

    @Test func statusPreservesSpacesAndUsesNewNameForRenames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let git = GitClient()
        try git.initializeRepository(at: root)
        _ = try git.run(["-C", root.path, "config", "user.name", "Test Writer"])
        _ = try git.run(["-C", root.path, "config", "user.email", "writer@example.invalid"])
        try "Draft".write(to: root.appendingPathComponent("Old Chapter.md"), atomically: true, encoding: .utf8)
        _ = try git.run(["-C", root.path, "add", "."])
        _ = try git.run(["-C", root.path, "commit", "--no-gpg-sign", "-m", "Initial"])
        _ = try git.run(["-C", root.path, "mv", "Old Chapter.md", "New Chapter.md"])
        try "Loose".write(to: root.appendingPathComponent("Loose Notes.md"), atomically: true, encoding: .utf8)

        let changes = try git.changes(in: root)
        #expect(changes.contains { $0.path == "New Chapter.md" && $0.status.contains("R") })
        #expect(changes.contains { $0.path == "Loose Notes.md" && $0.status == "??" })
        #expect(!changes.contains { $0.path == "Old Chapter.md" })
    }
}
