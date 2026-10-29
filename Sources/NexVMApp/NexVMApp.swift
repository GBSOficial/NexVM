import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no Info.plist); harmless in a .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct NexVMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            LibraryView(model: library)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
    }
}
