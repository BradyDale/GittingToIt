import SwiftUI

struct RepositoryDashboard: View {
    @EnvironmentObject private var library: RepositoryLibrary
    let repository: RepositoryReference
    let snapshot: RepositorySnapshot

    @State private var selectedDocument: WritingDocument?
    @State private var selectedCommitID: CommitSummary.ID?
    @State private var commitFiles: [GitChange] = []
    @State private var showingCopySheet = false
    @State private var showingCommitSheet = false
    @State private var showingFileHistory = false
    @State private var showingNotes = false
    @State private var showingVersionSelection = false
    @State private var showingVersionDocumentation = false
    @State private var versionFamilyFilter: VersionFamily?
    @State private var documentSearch = ""
    @State private var historySearch = ""

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 430, idealWidth: 520)
            historyPane
                .frame(minWidth: 480)
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(GTTheme.ink.opacity(0.16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT STATE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.4)
                    Text("\(snapshot.branch)  •  \(snapshot.currentCommit)  •  \(snapshot.changes.count) changes")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Button("Review & Commit") { showingCommitSheet = true }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.blush))
                    .fixedSize()
                    .disabled(snapshot.changes.isEmpty)
            }
            .gtPanel(GTTheme.repositoryColor(for: repository.id))

            HStack(alignment: .firstTextBaseline) {
                Text(versionFamilyFilter == nil ? "FILES" : "VERSIONS")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Spacer()
                Text("\(snapshot.documents.count) WRITING DOCUMENTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(GTTheme.gray)
            }

            if let family = versionFamilyFilter {
                HStack {
                    Text("Showing \(family.members.count) related versions")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Show All Files") { versionFamilyFilter = nil }
                        .buttonStyle(.link)
                }
            }

            TextField("Find a document", text: $documentSearch)
                .textFieldStyle(.plain)
                .padding(9)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

            List(filteredDocuments, selection: $selectedDocument) { document in
                DocumentRow(
                    document: document,
                    isCanonical: library.versionFamily(for: document)?.canonicalPath == document.relativePath
                )
                    .tag(document)
                    .contextMenu { documentContextMenu(document) }
            }
            .listStyle(.inset)
            .frame(minHeight: 320)

            HStack {
                Button("File History") { showingFileHistory = true }
                    .buttonStyle(GTActionButtonStyle())
                    .disabled(selectedDocument == nil)
                Button("Make Related Copy") { showingCopySheet = true }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(selectedDocument == nil)
                Button("Make Note") { showingNotes = true }
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
        .sheet(isPresented: $showingCommitSheet) {
            ReviewCommitSheet(changes: snapshot.changes)
                .environmentObject(library)
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
        .sheet(isPresented: $showingVersionSelection) {
            if let selectedDocument {
                SelectVersionsSheet(startingDocument: selectedDocument, documents: snapshot.documents)
                    .environmentObject(library)
            }
        }
        .sheet(isPresented: $showingVersionDocumentation) {
            if let selectedDocument {
                VersionDocumentationView(document: selectedDocument)
                    .environmentObject(library)
            }
        }
        .onChange(of: selectedDocument) { _, document in library.activeDocument = document }
        .onChange(of: library.requestedVersioningAction) { _, action in
            guard let action else { return }
            handleVersioningAction(action)
            library.requestedVersioningAction = nil
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

            TextField("Search message, hash, author, or date", text: $historySearch)
                .textFieldStyle(.plain)
                .padding(9)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

            Table(filteredCommits, selection: $selectedCommitID) {
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

    private var filteredDocuments: [WritingDocument] {
        let baseDocuments: [WritingDocument]
        if let family = versionFamilyFilter {
            let paths = Set(family.members)
            baseDocuments = snapshot.documents.filter { paths.contains($0.relativePath) }
        } else {
            baseDocuments = snapshot.documents
        }
        let query = documentSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseDocuments }
        return baseDocuments.filter {
            $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func documentContextMenu(_ document: WritingDocument) -> some View {
        if let family = library.versionFamily(for: document) {
            Button("View Versions") {
                selectedDocument = document
                versionFamilyFilter = family
            }
            Button("Review Versioning Documentation") {
                selectedDocument = document
                showingVersionDocumentation = true
            }
        }
        Button("Fork This File…") {
            selectedDocument = document
            showingCopySheet = true
        }
        Button("Make Note") {
            selectedDocument = document
            showingNotes = true
        }
        Button("File History") {
            selectedDocument = document
            showingFileHistory = true
        }
        if let family = library.versionFamily(for: document) {
            Divider()
            if family.canonicalPath != document.relativePath {
                Button("Make Canonical") {
                    selectedDocument = document
                    try? library.makeCanonical(document)
                }
            }
            Button("Remove Version", role: .destructive) {
                selectedDocument = document
                try? library.removeVersion(document)
                versionFamilyFilter = nil
            }
        }
    }

    private func handleVersioningAction(_ action: VersioningAction) {
        guard let selectedDocument else { return }
        switch action {
        case .selectVersions: showingVersionSelection = true
        case .viewVersions: versionFamilyFilter = library.versionFamily(for: selectedDocument)
        case .reviewDocumentation: showingVersionDocumentation = true
        case .makeCanonical:
            do { try library.makeCanonical(selectedDocument) }
            catch { library.errorMessage = error.localizedDescription }
        case .removeVersion:
            do {
                try library.removeVersion(selectedDocument)
                versionFamilyFilter = nil
            } catch { library.errorMessage = error.localizedDescription }
        }
    }

    private var filteredCommits: [CommitSummary] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshot.commits }
        return snapshot.commits.filter { commit in
            let date = commit.date?.formatted(.dateTime.year().month().day().hour().minute()) ?? ""
            return commit.hash.localizedCaseInsensitiveContains(query) ||
                commit.shortHash.localizedCaseInsensitiveContains(query) ||
                commit.message.localizedCaseInsensitiveContains(query) ||
                commit.author.localizedCaseInsensitiveContains(query) ||
                date.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct DocumentRow: View {
    let document: WritingDocument
    let isCanonical: Bool

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
        .padding(.horizontal, 5)
        .background(isCanonical ? GTTheme.yellow.opacity(0.48) : .clear)
        .foregroundStyle(GTTheme.ink)
    }
}
