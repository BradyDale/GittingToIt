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
        }
    }
}
