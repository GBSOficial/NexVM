import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: LibraryViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no Info.plist); harmless in a .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    // Closing the management window must not stop running VMs, so the app stays alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.runningItems.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("quit.title")
        alert.informativeText = L("quit.message", model.runningItems.count)
        alert.addButton(withTitle: L("quit.confirm"))
        alert.addButton(withTitle: L("action.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task { @MainActor in
            await model.stopAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct NexVMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = LibraryViewModel()

    /// Debug aid: NEXVM_COLOR_SCHEME=light|dark forces the app's appearance (system setting untouched).
    private var forcedScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["NEXVM_COLOR_SCHEME"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        Window("NexVM", id: "main") {
            MainWindowView(model: library)
                .frame(minWidth: 760, minHeight: 480)
                .tint(NexVMTheme.accent)
                .preferredColorScheme(forcedScheme)
                .onAppear { delegate.model = library }
        }
        .defaultSize(width: 1000, height: 660)
        .commands { NexVMCommands(model: library) }

        WindowGroup(L("vmwindow.title"), id: "vm", for: UUID.self) { $id in
            VMWindowView(model: library, vmID: id)
                .tint(NexVMTheme.accent)
                .preferredColorScheme(forcedScheme)
        }
        .defaultSize(width: 640, height: 560)

        Settings {
            SettingsView(model: library).tint(NexVMTheme.accent).preferredColorScheme(forcedScheme)
        }
    }
}

struct NexVMCommands: Commands {
    @Bindable var model: LibraryViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("action.newvm")) {
                openWindow(id: "main")
                model.showingNewVM = true
            }
            .keyboardShortcut("n")
        }
        CommandMenu(L("menu.vm")) {
            let item = model.item(model.selection)
            let cmd = LifecycleCommands(state: item.map { model.state(of: $0) } ?? .stopped, startBlocked: model.startBlocker(for: item?.configuration.guest ?? .linuxARM64) != nil)
            Button(L("action.run")) { if let item { model.start(item) } }
                .keyboardShortcut("r").disabled(item == nil || !cmd.canStart)
            Button(L("action.shutdown")) { if let item { model.requestShutdown(item) } }
                .disabled(item == nil || !cmd.canShutdown)
            Button(L("action.restart")) { if let item { model.restart(item) } }
                .disabled(item == nil || !cmd.canRestart)
            Button(L("action.forcestop")) { if let item { model.forceStop(item) } }
                .disabled(item == nil || !cmd.canForceStop)
            Divider()
            Button(L("action.details")) { if let item { openWindow(value: item.id) } }
                .keyboardShortcut("i").disabled(item == nil)
        }
    }
}
