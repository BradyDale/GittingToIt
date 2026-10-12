import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: RepositoryLibrary

    var body: some View {
        VStack(spacing: 0) {
            header
            repositoryTabs
            Rectangle().fill(GTTheme.ink).frame(height: 2)

            if let repository = library.selectedRepository,
               let snapshot = library.snapshots[repository.id] {
                RepositoryDashboard(repository: repository, snapshot: snapshot)
            } else if library.isLoading {
                ProgressView("Reading writing history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(GTTheme.paper)
        .alert("GittingToIt needs attention", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "Unknown problem")
        }
    }

    private var header: some View {
        HStack {
            Text("GittingToIt")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-1)
            Spacer()
            Button {
                library.refreshSelected()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GTActionButtonStyle())
            .fixedSize()
            .disabled(library.selectedRepository == nil || library.isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(GTTheme.ink)
    }

    private var repositoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(library.repositories) { repository in
                    let selected = library.selectedRepositoryID == repository.id
                    Button {
                        library.select(repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(repository.displayName)
                                .font(.system(.headline, design: .rounded).weight(.black))
                            Text(selected ? "OPEN" : "REPOSITORY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.3)
                        }
                        .foregroundStyle(GTTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minWidth: 130, alignment: .leading)
                        .background(selected ? GTTheme.repositoryColor(for: repository.id) : GTTheme.paper)
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from GittingToIt", role: .destructive) {
                            library.removeFromLibrary(repository)
                        }
                    }
                }

                Button {
                    library.addFolder()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.black))
                        .foregroundStyle(GTTheme.ink)
                        .frame(width: 46, height: 46)
                        .background(GTTheme.yellow)
                        .overlay(Rectangle().stroke(GTTheme.ink, lineWidth: 1.5))
                        .accessibilityLabel("Add writing folder")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add a writing repository", systemImage: "books.vertical")
        } description: {
            Text("GittingToIt only reads folders you explicitly add. Your folder list stays on this Mac.")
        } actions: {
            Button("Add Writing Folder") { library.addFolder() }
                .buttonStyle(GTActionButtonStyle(color: GTTheme.yellow))
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
