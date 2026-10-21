import SwiftUI

struct HistoricalForkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary

    let document: WritingDocument
    let commit: CommitSummary

    @State private var purpose = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var result: RelatedCopyResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FORK THIS VERSION")
                .font(.system(.title2, design: .rounded).weight(.black))

            if let result {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Documented copy created").font(.title3.weight(.bold))
                    Text(result.copyURL.lastPathComponent)
                    Text("Copied from checkpoint \(commit.shortHash).")
                    Text("The current version of \(document.name) was not changed.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gtPanel(GTTheme.mint)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(document.name).font(.title3.weight(.bold))
                    Text("Version \(commit.shortHash)").monospaced()
                    Text(commit.date?.formatted(.dateTime.year().month(.abbreviated).day().hour().minute()) ?? "Unknown date")
                    Text(commit.message).foregroundStyle(.secondary)
                }
                .gtPanel(GTTheme.yellow)

                Text("This creates a new dated document from the selected historical version. Your current document stays exactly as it is.")
                    .foregroundStyle(.secondary)

                Text("Why are you returning to this version?")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.3)
                TextEditor(text: $purpose)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(.white)
                    .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(GTActionButtonStyle())
                    Button(isCreating ? "Creating…" : "Create Documented Fork") { createFork() }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                        .disabled(isCreating || purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .background(GTTheme.paper)
        .frame(minWidth: 640, minHeight: 500)
    }

    private func createFork() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                result = try await library.forkHistoricalVersion(
                    of: document,
                    from: commit,
                    purpose: purpose
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
