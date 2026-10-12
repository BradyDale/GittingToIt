import SwiftUI

struct RestoreFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary

    let document: WritingDocument
    let commit: CommitSummary

    @State private var note = ""
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var result: FileRestoreResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RESTORE ONE FILE")
                .font(.system(.title2, design: .rounded).weight(.black))

            if let result {
                restoredView(result)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.name).font(.title3.weight(.bold))
                    Text("Version \(commit.shortHash)").monospaced()
                    Text(commit.date?.formatted(.dateTime.year().month(.abbreviated).day().hour().minute()) ?? "Unknown date")
                    Text(commit.message).foregroundStyle(.secondary)
                }
                .gtPanel(GTTheme.blush)

                Text("Only this file will be restored. If it currently has edits, GittingToIt saves them in a safety checkpoint first. Other files and staged work remain untouched.")
                    .foregroundStyle(.secondary)

                Text("Why are you restoring this version?")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.3)
                TextEditor(text: $note)
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(.white)
                    .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(GTActionButtonStyle())
                    Button(isRestoring ? "Restoring…" : "Restore This File") { restore() }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.blush))
                        .disabled(isRestoring || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .background(GTTheme.paper)
        .frame(minWidth: 620, minHeight: 480)
    }

    @ViewBuilder
    private func restoredView(_ result: FileRestoreResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File restored").font(.title3.weight(.bold))
            Text(result.restoredURL.lastPathComponent)
            Text("Source: \(result.sourceCommit.shortHash)").monospaced()
            if let safetyCommit = result.safetyCommit {
                Text("Previous edits preserved in safety checkpoint \(safetyCommit.shortHash).")
            } else {
                Text("The file had no unsaved Git changes before restoration.")
            }
            Text("The restored file and its File Note are ready for review and checkpointing.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gtPanel(GTTheme.mint)
        Spacer()
        Button("Done") { dismiss() }
            .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
    }

    private func restore() {
        isRestoring = true
        errorMessage = nil
        Task {
            do { result = try await library.restore(document, from: commit, note: note) }
            catch { errorMessage = error.localizedDescription }
            isRestoring = false
        }
    }
}
