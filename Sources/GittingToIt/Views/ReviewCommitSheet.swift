import SwiftUI

struct ReviewCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary

    let changes: [GitChange]

    @State private var selectedPaths: Set<String>
    @State private var message = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedCommit: CommitSummary?

    init(changes: [GitChange]) {
        self.changes = changes
        _selectedPaths = State(initialValue: Set(changes.map(\.path)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("REVIEW & SAVE CHECKPOINT")
                .font(.system(.title2, design: .rounded).weight(.black))

            if let savedCommit {
                savedView(savedCommit)
            } else {
                Text("Only checked files will be included. Unrelated staged work remains staged.")
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(changes) { change in
                            Toggle(isOn: Binding(
                                get: { selectedPaths.contains(change.path) },
                                set: { checked in
                                    if checked { selectedPaths.insert(change.path) }
                                    else { selectedPaths.remove(change.path) }
                                }
                            )) {
                                HStack {
                                    Text(change.status).monospaced().foregroundStyle(.secondary)
                                    Text(change.path).textSelection(.enabled)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                .frame(minHeight: 160, maxHeight: 260)

                Text("Checkpoint message")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.3)
                TextField("What changed, and why?", text: $message, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.white)
                    .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(GTActionButtonStyle())
                    Button(isSaving ? "Saving…" : "Save Checkpoint") {
                        save()
                    }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(isSaving || selectedPaths.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .background(GTTheme.paper)
        .frame(minWidth: 680, minHeight: 520)
    }

    @ViewBuilder
    private func savedView(_ commit: CommitSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Checkpoint saved").font(.title3.weight(.bold))
            Text(commit.shortHash).font(.title2.monospaced()).textSelection(.enabled)
            Text(commit.message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gtPanel(GTTheme.mint)
        Spacer()
        Button("Done") { dismiss() }
            .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                savedCommit = try await library.saveCheckpoint(
                    paths: Array(selectedPaths),
                    message: message
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
