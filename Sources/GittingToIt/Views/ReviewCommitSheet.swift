import SwiftUI

struct ReviewCommitSheet: View {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "webp", "bmp", "psd"
    ]
    private static let imageRules = imageExtensions.sorted().map { "*.\($0)" }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary

    let changes: [GitChange]

    @State private var selectedPaths: Set<String>
    @State private var message = ""
    @State private var isSaving = false
    @State private var ignoredPaths: Set<String> = []
    @State private var stopTrackingPaths: Set<String> = []
    @State private var ignoreNotice: String?
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

                HStack {
                    Button("Ignore All .DS_Store") { ignoreAllDSStores() }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                    Button("Ignore All Images") { ignoreAllImages() }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                }
                .disabled(isSaving)

                if changes.contains(where: { $0.path.range(of: #" c \d{8}"#, options: .regularExpression) != nil }) {
                    Text("A related copy changed. Your checkpoint message will also be added to its File Notes.")
                        .fontWeight(.semibold)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GTTheme.yellow.opacity(0.75))
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(changes.filter { !ignoredPaths.contains($0.path) }) { change in
                            HStack {
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
                                Spacer()
                                Button("Ignore") { ignore(change) }
                                    .buttonStyle(.borderless)
                                    .help("Keep this file on your Mac but leave it out of future checkpoints.")
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                .frame(minHeight: 160, maxHeight: 260)

                if let ignoreNotice {
                    Text(ignoreNotice)
                        .font(.callout.weight(.semibold))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GTTheme.yellow.opacity(0.65))
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                }

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
                    if !stopTrackingPaths.isEmpty || selectedPaths.contains(".gitignore") {
                        Button(isSaving ? "Saving…" : "Save Ignore Rules") {
                            saveIgnores()
                        }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                        .disabled(isSaving || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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
                    stopTrackingPaths: Array(stopTrackingPaths),
                    message: message
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func ignore(_ change: GitChange) {
        if URL(fileURLWithPath: change.path).lastPathComponent == ".DS_Store" {
            ignoreAllDSStores()
            return
        }
        Task {
            do {
                let result = try await library.ignoreFile(path: change.path)
                ignoredPaths.insert(change.path)
                if result.wasTracked {
                    stopTrackingPaths.insert(change.path)
                    selectedPaths.insert(change.path)
                    selectedPaths.insert(".gitignore")
                    ignoreNotice = "\(change.path) will stay on your Mac and be removed from Git when you save this checkpoint."
                } else {
                    selectedPaths.remove(change.path)
                    selectedPaths.insert(".gitignore")
                    ignoreNotice = "\(change.path) will stay on your Mac and is now excluded from future checkpoints."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ignoreAllDSStores() {
        let matching = changes.filter {
            URL(fileURLWithPath: $0.path).lastPathComponent == ".DS_Store"
        }
        ignoreBatch(
            matching,
            rules: [".DS_Store"],
            includeEveryTrackedDSStore: true,
            label: ".DS_Store files"
        )
    }

    private func ignoreAllImages() {
        let matching = changes.filter {
            Self.imageExtensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
        }
        ignoreBatch(matching, rules: Self.imageRules, label: "image files")
    }

    private func ignoreBatch(
        _ matching: [GitChange],
        rules: [String],
        includeEveryTrackedDSStore: Bool = false,
        label: String
    ) {
        Task {
            do {
                let results = try await library.ignoreFiles(
                    paths: matching.map(\.path),
                    rules: rules,
                    includeEveryTrackedDSStore: includeEveryTrackedDSStore
                )
                ignoredPaths.formUnion(matching.map(\.path))
                for result in results {
                    if result.wasTracked {
                        stopTrackingPaths.insert(result.path)
                        selectedPaths.insert(result.path)
                    } else {
                        selectedPaths.remove(result.path)
                    }
                }
                selectedPaths.insert(".gitignore")
                let trackedCount = results.filter(\.wasTracked).count
                ignoreNotice = "Ignored \(matching.count) changed \(label). \(trackedCount) already-tracked files will stay on your Mac and leave Git when you save the ignore rules."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveIgnores() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                savedCommit = try await library.saveCheckpoint(
                    paths: Array(stopTrackingPaths) + [".gitignore"],
                    stopTrackingPaths: Array(stopTrackingPaths),
                    message: message
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
