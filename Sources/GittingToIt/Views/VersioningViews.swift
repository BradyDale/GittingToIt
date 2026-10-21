import SwiftUI

struct SelectVersionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let startingDocument: WritingDocument
    let documents: [WritingDocument]

    @State private var selectedPaths: Set<String> = []
    @State private var errorMessage: String?
    @State private var search = ""

    private var filteredDocuments: [WritingDocument] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return documents }
        return documents.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.relativePath.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SELECT VERSIONS")
                .font(.system(.title2, design: .rounded).weight(.black))
            Text("Choose every file that represents a version of the same piece of writing.")
                .foregroundStyle(.secondary)

            TextField("Search filenames or folders", text: $search)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.white)
                .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

            Text("\(selectedPaths.count) selected • \(filteredDocuments.count) shown")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            List(filteredDocuments) { document in
                Toggle(isOn: Binding(
                    get: { selectedPaths.contains(document.relativePath) },
                    set: { selected in
                        if selected { selectedPaths.insert(document.relativePath) }
                        else { selectedPaths.remove(document.relativePath) }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(document.name).fontWeight(.medium)
                        Text(document.relativePath).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))

            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GTActionButtonStyle())
                Button("Save Version Set") { save() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(selectedPaths.count < 2)
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            if let family = library.versionFamily(for: startingDocument) {
                selectedPaths = Set(family.members)
            } else {
                selectedPaths = [startingDocument.relativePath]
            }
        }
    }

    private func save() {
        do {
            try library.associateVersions(documents.filter { selectedPaths.contains($0.relativePath) })
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VersionDocumentationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let document: WritingDocument

    @State private var entries: [VersionNoteEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("VERSIONING DOCUMENTATION")
                        .font(.system(.title2, design: .rounded).weight(.black))
                    Text("One diary assembled from every version, newest first")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
            }

            if let errorMessage {
                ContentUnavailableView("Documentation unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if entries.isEmpty {
                ContentUnavailableView("No version notes yet", systemImage: "note.text", description: Text("Use Make Note to begin the shared record."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.date?.formatted(date: .long, time: .shortened) ?? "Date not recorded")
                                    .font(.headline)
                                Text(entry.filename)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.white)
                            .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.25))
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(20)
        .background(GTTheme.paper)
        .frame(minWidth: 850, minHeight: 650)
        .onAppear {
            do { entries = try library.versionNotes(for: document) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
