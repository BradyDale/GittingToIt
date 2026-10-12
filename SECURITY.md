# Security

## Reporting

Until a public security contact is chosen, report security concerns privately to the repository owner rather than opening an issue containing sensitive data.

## Publishing checklist

Before pushing to GitHub:

1. Review every staged file.
2. Confirm no writing, File Notes, local repository catalog, absolute user path, credentials, signing material, or private remote URL is present.
3. Run `swift test`.
4. Run `Scripts/public-safety-check.sh`.
5. Confirm `.gitignore` still excludes local settings and signing material.
6. Enable GitHub secret scanning after the repository is created.

GittingToIt executes `/usr/bin/git` directly with argument arrays. It does not construct shell command strings from filenames or user input.
