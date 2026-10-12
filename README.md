# GittingToIt

GittingToIt is a local, writing-focused Git client for understanding what changed, when it changed, and why alternate copies exist.

This repository contains **application source code only**. It must never contain the user's writing, repository catalog, absolute folder paths, File Notes, Git history exports, credentials, or other private data.

## Current checkpoint

The native macOS prototype includes:

- Explicit folder addition with a default starting location of `Documents/Sync`
- Protection against accidental nested repositories
- Repository tabs and removal from the local library without deleting data
- Branch, current commit, and working-change summaries
- Commit history with hashes, dates, times, messages, and changed files
- Writing-document discovery for Markdown, text, RTF, Word, and PDF files
- Creation, modification, and last-committed dates
- Per-file Git history
- Exact historical text preview and word-focused comparison with the current file
- Reading and adding human-readable `GittingToIt Notes.md` entries
- Documented related copies named `filename c YYYYMMDD.ext`
- Required purpose notes for copies
- Automatic family-history notes whenever a known original or copy is checkpointed
- A bold, high-contrast visual system inspired by the supplied mood board
- Selective checkpoints that cannot include unrelated staged work
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
