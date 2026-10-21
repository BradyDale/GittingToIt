import SwiftUI

struct FileHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let document: WritingDocument

    @State private var commits: [CommitSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedCommitID: CommitSummary.ID?
    @State private var showingRestore = false
    @State private var showingFork = false
    @State private var detailMode = DetailMode.version
    @State private var detailText = "Select a checkpoint to inspect this file."
    @State private var isLoadingDetail = false
    @State private var detailTask: Task<Void, Never>?

    private enum DetailMode: String, CaseIterable, Identifiable {
        case version = "This version"
        case changes = "Changes to current"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(document.name).font(.system(.title2, design: .rounded).weight(.black))
                    Text("Every checkpoint that changed this file")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fork This Version") { showingFork = true }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(selectedCommitID == nil)
                Button("Restore Selected Version") { showingRestore = true }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.blush))
                    .disabled(selectedCommitID == nil)
                Button("Done") { dismiss() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                    .keyboardShortcut(.cancelAction)
            }

            if isLoading {
                ProgressView("Reading file history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                HSplitView {
                    List(commits, selection: $selectedCommitID) { commit in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(commit.message).fontWeight(.medium)
                            HStack {
                                Text(commit.shortHash).monospaced()
                                Text(commit.date?.formatted(.dateTime.year().month(.abbreviated).day().hour().minute()) ?? "Unknown date")
                                Text(commit.author)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $detailMode) {
                            ForEach(DetailMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if isLoadingDetail {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView([.horizontal, .vertical]) {
                                Text(detailText)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(14)
                            }
                            .background(.white)
                            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                        }
                    }
                    .padding(.leading, 10)
                    .frame(minWidth: 420)
                }
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(width: 1_050, height: 680)
        .task {
            do { commits = try await library.history(for: document) }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
        .onChange(of: selectedCommitID) { _, _ in loadDetail() }
        .onChange(of: detailMode) { _, _ in loadDetail() }
        .onDisappear { detailTask?.cancel() }
        .sheet(isPresented: $showingRestore) {
            if let id = selectedCommitID,
               let commit = commits.first(where: { $0.id == id }) {
                RestoreFileSheet(document: document, commit: commit)
                    .environmentObject(library)
            }
        }
        .sheet(isPresented: $showingFork) {
            if let id = selectedCommitID,
               let commit = commits.first(where: { $0.id == id }) {
                HistoricalForkSheet(document: document, commit: commit)
                    .environmentObject(library)
            }
        }
    }

    private func loadDetail() {
        detailTask?.cancel()
        guard documentSupportsTextPreview,
              let id = selectedCommitID,
              let commit = commits.first(where: { $0.id == id }) else {
            isLoadingDetail = false
            detailText = documentSupportsTextPreview
                ? "Select a checkpoint to inspect this file."
                : "Text preview is not available for .\(document.fileExtension) files. The complete file version can still be restored."
            return
        }

        isLoadingDetail = true
        let requestedID = commit.id
        let requestedMode = detailMode
        detailTask = Task {
            let loadedText: String
            do {
                switch requestedMode {
                case .version:
                    loadedText = try await library.historicalText(for: document, at: commit)
                case .changes:
                    let diff = try await library.wordDiffToCurrent(for: document, from: commit)
                    loadedText = diff.isEmpty ? "No differences from the current file." : diff
                }
            } catch {
                loadedText = "Preview unavailable: \(error.localizedDescription)"
            }
            guard !Task.isCancelled,
                  selectedCommitID == requestedID,
                  detailMode == requestedMode else { return }
            detailText = loadedText
            isLoadingDetail = false
        }
    }

    private var documentSupportsTextPreview: Bool {
        ["md", "markdown", "txt", "rtf"].contains(document.fileExtension)
    }
}

struct FileNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let document: WritingDocument

    @State private var draftNotes = ""
    @State private var hasLoadedDraft = false
    @State private var didSave = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FILE NOTES — \(document.name)")
                    .font(.system(.title3, design: .rounded).weight(.black))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("A dated entry has been placed at the top. Write beneath it; older notes stay below.")
                .foregroundStyle(.secondary)

            TextEditor(text: $draftNotes)
                .font(.body.monospaced())
                .padding(10)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if didSave { Text("Notes saved beside this document.").foregroundStyle(GTTheme.mint) }

            HStack {
                Text("Saved in GittingToIt Notes.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Notes") { saveNotes() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(!hasLoadedDraft)
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            guard !hasLoadedDraft else { return }
            do {
                draftNotes = try library.editableNotesDraft(for: document)
                hasLoadedDraft = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveNotes() {
        do {
            try library.saveNotes(for: document, contents: draftNotes)
            errorMessage = nil
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
