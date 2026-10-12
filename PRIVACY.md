# Privacy architecture

GittingToIt separates two kinds of data.

## Public application repository

Safe to publish when reviewed:

- Swift source code
- Tests using generated temporary fixtures
- Documentation
- Build configuration

## Private user data

Never place in the application repository:

- Writing documents or copies
- `GittingToIt Notes.md` files belonging to writing projects
- Repository paths or the local repository catalog
- Git logs exported from writing repositories
- Credentials, tokens, remote URLs containing secrets, or signing keys

The app stores its repository catalog under macOS Application Support. Writing and File Notes remain inside repositories selected by the user. The application does not contain network or telemetry code.

Before publishing, inspect the complete staged diff and run the test suite. Do not use real writing repositories as test fixtures.
