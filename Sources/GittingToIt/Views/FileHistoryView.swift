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
    @State private var detailMode = DetailMode.version
    @State private var detailText = "Select a checkpoint to inspect this file."
    @State private var isLoadingDetail = false

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
        .sheet(isPresented: $showingRestore) {
            if let id = selectedCommitID,
               let commit = commits.first(where: { $0.id == id }) {
                RestoreFileSheet(document: document, commit: commit)
                    .environmentObject(library)
            }
        }
    }

    private func loadDetail() {
        guard documentSupportsTextPreview,
              let id = selectedCommitID,
              let commit = commits.first(where: { $0.id == id }) else {
            detailText = documentSupportsTextPreview
                ? "Select a checkpoint to inspect this file."
                : "Text preview is not available for .\(document.fileExtension) files. The complete file version can still be restored."
            return
        }

        isLoadingDetail = true
        Task {
            do {
                switch detailMode {
                case .version:
                    detailText = try await library.historicalText(for: document, at: commit)
                case .changes:
                    let diff = try await library.wordDiffToCurrent(for: document, from: commit)
                    detailText = diff.isEmpty ? "No differences from the current file." : diff
                }
            } catch {
                detailText = "Preview unavailable: \(error.localizedDescription)"
            }
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

    @State private var eventType = "Note"
    @State private var newNote = ""
    @State private var displayedNotes = ""
    @State private var errorMessage: String?

    private let eventTypes = [
        "Note", "Revised", "Uploaded to Google Docs", "Shared", "Submitted",
        "Declared canonical", "Reference only", "Abandoned", "Exported"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FILE NOTES — \(document.name)")
                    .font(.system(.title3, design: .rounded).weight(.black))
                Spacer()
                Button("Done") { dismiss() }
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 9) {
                    Text("HISTORY").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.4)
                    ScrollView {
                        Text(displayedNotes)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(12)
                    .background(.white)
                    .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ADD DOCUMENTATION").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.4)
                    Picker("Event", selection: $eventType) {
                        ForEach(eventTypes, id: \.self) { Text($0).tag($0) }
                    }
                    TextEditor(text: $newNote)
                        .frame(minHeight: 130)
                        .padding(6)
                        .background(.white)
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Button("Save File Note") {
                        do {
                            try library.addFileNote(to: document, eventType: eventType, note: newNote)
                            newNote = ""
                            errorMessage = nil
                            displayedNotes = library.notes(for: document)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .frame(minWidth: 260)
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { displayedNotes = library.notes(for: document) }
    }
}
