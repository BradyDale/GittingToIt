import SwiftUI

struct RepositoryDashboard: View {
    @EnvironmentObject private var library: RepositoryLibrary
    let repository: RepositoryReference
    let snapshot: RepositorySnapshot

    @State private var selectedDocument: WritingDocument?
    @State private var selectedCommitID: CommitSummary.ID?
    @State private var commitFiles: [GitChange] = []
    @State private var showingCopySheet = false
    @State private var showingFileHistory = false
    @State private var showingNotes = false

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 350, idealWidth: 420)
            historyPane
                .frame(minWidth: 520)
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(GTTheme.ink.opacity(0.16))
                Text("CURRENT STATE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.6)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow { Text("Branch").foregroundStyle(.secondary); Text(snapshot.branch) }
                    GridRow { Text("Commit").foregroundStyle(.secondary); Text(snapshot.currentCommit).monospaced() }
                    GridRow { Text("Changes").foregroundStyle(.secondary); Text("\(snapshot.changes.count)") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .gtPanel(GTTheme.repositoryColor(for: repository.id))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                Button("Review & Commit") { }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.blush))
                    .disabled(true)
                    .help("Commit writing is intentionally guarded in this first checkpoint.")
                Button("Restore") { }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.blush))
                    .disabled(true)
                    .help("Select a historical file version before restoration.")
            }

            Text("WRITING DOCUMENTS")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .tracking(1.6)

            List(snapshot.documents, selection: $selectedDocument) { document in
                DocumentRow(document: document)
                    .tag(document)
            }
            .listStyle(.inset)

            HStack {
                Button("File History") { showingFileHistory = true }
                    .buttonStyle(GTActionButtonStyle())
                    .disabled(selectedDocument == nil)
                Button("Make Related Copy") { showingCopySheet = true }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(selectedDocument == nil)
                Button("File Notes") { showingNotes = true }
                    .buttonStyle(GTActionButtonStyle())
                    .disabled(selectedDocument == nil)
            }
        }
        .padding(16)
        .sheet(isPresented: $showingFileHistory) {
            if let selectedDocument {
                FileHistoryView(document: selectedDocument)
                    .environmentObject(library)
            }
        }
        .sheet(isPresented: $showingCopySheet) {
            if let selectedDocument {
                RelatedCopySheet(document: selectedDocument)
                    .environmentObject(library)
            }
        }
        .sheet(isPresented: $showingNotes) {
            if let selectedDocument {
                FileNotesView(document: selectedDocument)
                    .environmentObject(library)
            }
        }
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("HISTORY")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Spacer()
                Text("\(snapshot.commits.count) CHECKPOINTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(GTTheme.gray)
            }

            Table(snapshot.commits, selection: $selectedCommitID) {
                TableColumn("Hash") { commit in Text(commit.shortHash).monospaced() }
                    .width(76)
                TableColumn("Date") { commit in
                    Text(commit.date?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "—")
                }
                    .width(105)
                TableColumn("Time") { commit in
                    Text(commit.date?.formatted(.dateTime.hour().minute()) ?? "—")
                }
                    .width(75)
                TableColumn("Message") { commit in Text(commit.message).lineLimit(1) }
            }
            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
            .onChange(of: selectedCommitID) { _, newValue in
                guard let id = newValue,
                      let commit = snapshot.commits.first(where: { $0.id == id }) else {
                    commitFiles = []
                    return
                }
                Task { commitFiles = (try? await library.changedFiles(for: commit)) ?? [] }
            }

            GroupBox(selectedCommitID == nil ? "Select a checkpoint to see its files" : "Files changed") {
                if commitFiles.isEmpty {
                    Text("No changed-file details loaded.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(commitFiles) { change in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(change.status).monospaced().foregroundStyle(.secondary)
                                    Text(change.path).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }
            .groupBoxStyle(.automatic)
        }
        .padding(16)
        .background(GTTheme.paper)
    }
}

private struct DocumentRow: View {
    let document: WritingDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.name).fontWeight(.medium)
            Text(document.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 10) {
                Label {
                    Text(document.createdAt?.formatted(.dateTime.year().month(.abbreviated).day()) ?? "Unknown")
                } icon: { Image(systemName: "sparkles") }
                Label {
                    Text(document.modifiedAt?.formatted(.dateTime.year().month(.abbreviated).day()) ?? "Unknown")
                } icon: { Image(systemName: "pencil") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .foregroundStyle(GTTheme.ink)
    }
}
