# GittingToIt

**Version control for writers.**

- Three years ago, you made three different versions of the same essay. Now you want to try to get it published, but you can't remember how they differ.
- **GittingToIt** is for that.

GittingToIt is a local, writing-focused Git client for understanding what changed, when it changed, and why alternate copies exist.

This repository contains **application source code only**. It must never contain the user's writing, repository catalog, absolute folder paths, File Notes, Git history exports, credentials, or other private data.

![GittingToIt showing the history of a fictional manuscript](docs/images/gittingtoit-file-history.jpg)

_The screenshot uses a disposable fictional repository; it contains no personal files or real writing._

## Best practices

- Keep large groups of interconnected writing in one large folder that will be managed by this client. You don't need a tab for every piece of writing. You can have sub-folders in the large folder separating each piece of writing, however.
- After every writing session, open GittingToIt, go to the folder that holds your newly edited writing and close the day by hitting "Review and Commit," note the new piece of writing or which file changed, write as much or as little as you want about what you did and then finalize it.
- GittingToIt provides a diary for every file. This is a separate notes file associated with a piece of writing, allowing you to document changes without putting those notes inside the writing itself. It is a good place to log changes, particularly for files edited over a long period of time, and is especially important when you have multiple versions of the same piece of writing.
- GittingToIt currently works best with Markdown (`.md`) and plain-text (`.txt`) files, especially when comparing versions. We recommend [Typora](https://typora.io/), a beautiful Markdown editor that keeps the formatting out of your way while you write.
- **If you want to make a new version** of a file, make the copy from within GittingToIt. This will force you to log why you are making the copy. This is "forking for writers." By logging what you're doing, you will be more likely to be able to know which file to use in the future.
- If you keep images or other multimedia in the same folders as your writing, select "Ignore" on those files in the dialogue when making a commit (unless you modify these files a lot, you'll just be burning Git repository storage by tracking them).

## Versioning: forking for writers

Writers often make copies when they want to explore a different direction without disturbing the current draft. That works well in the moment, but it can become difficult to remember which copy came first, why it was created, and which version should now be treated as the master.

GittingToIt organizes related drafts into **version sets**.

From the **Versioning** menu, you can:

- **Select Versions** to search for and designate multiple existing files as versions of the same piece of writing.
- **View Versions** to temporarily filter the file list to that version set.
- **Review Versioning Documentation** to read the notes from every version as one continuous, chronological record.
- **Compare Versions** to choose any two Markdown or plain-text drafts from the set, read them in a single writer-friendly view, switch between the earlier and later text, and move through additions and deletions. When a set contains exactly two versions, both are selected automatically with the most recently edited file on the left.
- **Make Canonical** to identify the file currently considered the master copy. Canonical files are highlighted in the file list.
- **Remove Version** to remove a file from its version set without deleting the file.

When you fork a document through GittingToIt, the new copy is automatically associated with its source document. The copy uses the filename convention `filename c YYYYMMDD.ext`, preserving the date on which that version was created.

GittingToIt requires a note when a fork is created. That note becomes part of the versioning documentation, alongside later diary entries and revision notes. This creates a record not only of what changed, but why another version exists.

GittingToIt never stores user data itself. The version relationships and canonical status are stored in a small, human-readable file inside the folder where the user keeps their writing. GittingToIt users always retain 100% control of all the writing they create—including their notes about that writing. The relationships file appears in the folder at:

`.gittingtoit/version-families.json`

This file contains relative filenames and version-family information. It does not contain the writing itself. Because it lives with the writing repository, Git can preserve the version relationships alongside the documents.

## Current checkpoint

The native macOS prototype includes:

- Explicit folder addition with a default starting location of `Documents/Sync`
- Protection against accidental nested repositories
- Repository tabs and removal from the local library without deleting data
- Branch, current commit, and working-change summaries
- Commit history with hashes, dates, times, messages, and changed files
- Fast document and commit-history filtering
- Writing-document discovery for Markdown, text, RTF, Word, and PDF files
- Creation, modification, and last-committed dates
- Per-file Git history
- Background history warming for recently edited documents
- Exact historical text preview and word-focused comparison with the current file
- A dated, editable notes diary stored in human-readable `GittingToIt Notes.md`
- Documented related copies named `filename c YYYYMMDD.ext`
- Version sets that keep related drafts together, identify the canonical copy, and combine their notes into one timeline
- Single-view comparison of related Markdown and plain-text versions, with marked-up, earlier, and later reading modes
- Documented forks made from any historical version without replacing the current file
- Required purpose notes for copies
- Automatic family-history notes whenever a known original or copy is checkpointed
- A bold, high-contrast visual system
- Selective checkpoints that cannot include unrelated staged work
- Per-file and grouped ignore controls, including convenient rules for Finder metadata and image-heavy folders
- Safe one-file restoration with an automatic safety checkpoint for current edits

Compare/reconcile and richer text-diff views remain planned work.

## Run locally

Requirements: macOS 14 or newer and Swift 6 command-line tools.

```sh
swift run
```

Run tests with:

```sh
swift test
```

Check the repository for common private paths and secrets before publishing:

```sh
Scripts/public-safety-check.sh
```

Package a launchable local app with:

```sh
chmod +x Scripts/package-app.sh
Scripts/package-app.sh
open .build/GittingToIt.app
```

## Privacy boundary

- The app has no analytics, telemetry, advertising, or network client.
- It scans only folders explicitly added by the user.
- The repository catalog is stored in the user's Application Support directory, outside this source repository.
- The default Sync location is constructed from the current user's home directory at runtime; no username or private absolute path is compiled into the app.
- File Notes live beside the documented writing because they belong to that writing repository, not this application repository.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) before publishing.

## License

GittingToIt is open-source software available under the [MIT License](LICENSE). Use it, modify it, and share it however you like under those terms.
