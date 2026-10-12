import SwiftUI

struct RelatedCopySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RepositoryLibrary
    let document: WritingDocument

    @State private var purpose = ""
    @State private var errorMessage: String?
    @State private var result: RelatedCopyResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Make a related copy")
                .font(.system(.title2, design: .rounded).weight(.black))
            Text(document.name)
                .font(.headline)
            Text("The copy will use the form “filename c YYYYMMDD” and keep today’s creation date in its name permanently.")
                .foregroundStyle(.secondary)

            if let result {
                GroupBox("Copy created") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.copyURL.lastPathComponent).fontWeight(.medium)
                        Text("Its origin and your note were added to \(result.notesURL.lastPathComponent).")
                            .foregroundStyle(.secondary)
                        Text("Review and save a Git checkpoint when you are ready.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                }
            } else {
                Text("Why are you creating this version?")
                    .fontWeight(.medium)
                TextEditor(text: $purpose)
                    .frame(minHeight: 110)
                    .border(.quaternary)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(GTActionButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create Documented Copy") {
                        do {
                            result = try library.makeRelatedCopy(of: document, purpose: purpose)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(GTActionButtonStyle(color: GTTheme.mint))
                    .disabled(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .background(GTTheme.paper)
        .frame(minWidth: 560, minHeight: 360)
    }
}
