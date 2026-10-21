import AppKit
import SwiftUI

final class GittingToItAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct GittingToItApp: App {
    @NSApplicationDelegateAdaptor(GittingToItAppDelegate.self) private var appDelegate
    @StateObject private var library = RepositoryLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit GittingToIt") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Add Writing Folder…") { library.addFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Versioning") {
                Button("Select Versions…") { library.requestedVersioningAction = .selectVersions }
                    .disabled(library.activeDocument == nil)
                Button("View Versions") { library.requestedVersioningAction = .viewVersions }
                    .disabled(library.activeDocument.flatMap { library.versionFamily(for: $0) } == nil)
                Button("Review Versioning Documentation") { library.requestedVersioningAction = .reviewDocumentation }
                    .disabled(library.activeDocument.flatMap { library.versionFamily(for: $0) } == nil)
                Button("Compare Versions…") { library.requestedVersioningAction = .compareVersions }
                    .disabled(library.activeDocument.flatMap { library.versionFamily(for: $0) } == nil)
                Divider()
                Button("Make Canonical") { library.requestedVersioningAction = .makeCanonical }
                    .disabled(library.activeDocument.flatMap { library.versionFamily(for: $0) } == nil)
                Button("Remove Version") { library.requestedVersioningAction = .removeVersion }
                    .disabled(library.activeDocument.flatMap { library.versionFamily(for: $0) } == nil)
            }
        }
    }
}
