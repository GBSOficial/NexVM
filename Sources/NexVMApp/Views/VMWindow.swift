import SwiftUI
import AppKit
import NexVMCore
import NexVMEngine

/// One window per VM, separate from the management window. While the VM runs (and the embedded
/// display is enabled) it shows the guest screen; otherwise it shows the VM's details.
struct VMWindowView: View {
    @Bindable var model: LibraryViewModel
    let vmID: UUID?
    @State private var logTail = ""
    @State private var display = DisplaySession()
    @State private var showInspector = false

    var body: some View {
        if let item = model.item(vmID) {
            content(item)
        } else {
            ContentUnavailableView(L("vmwindow.missing"), systemImage: "questionmark.folder")
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func isLive(_ s: VMRuntimeState) -> Bool { s == .running || s == .stopping || s == .paused }

    private func content(_ item: VMItem) -> some View {
        let c = item.configuration
        let state = model.state(of: item)
        let cmd = LifecycleCommands(state: state, startBlocked: model.startBlocker(for: c.guest) != nil)
        let showDisplay = model.embeddedDisplay && isLive(state)

        return Group {
            if showDisplay {
                displayArea
                    .inspector(isPresented: $showInspector) { details(item, state: state).inspectorColumnWidth(min: 260, ideal: 320, max: 420) }
            } else {
                details(item, state: state)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle(c.name)
        .navigationSubtitle(L(state.titleKey))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if showDisplay {
                    Button { Task { await display.sendCtrlAltDel() } } label: { Label(L("action.ctrlaltdel"), systemImage: "command.square") }
                        .disabled(display.status != .connected).help(L("help.ctrlaltdel"))
                    Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Label(L("action.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right") }
                        .help(L("help.fullscreen"))
                    Button { showInspector.toggle() } label: { Label(L("action.inspector"), systemImage: "sidebar.right") }
                        .help(L("action.inspector"))
                }
                Button { model.start(item) } label: { Label(L("action.run"), systemImage: "play.fill") }
                    .disabled(!cmd.canStart).help(model.startBlocker(for: c.guest) ?? L("help.start"))
                Button { model.requestShutdown(item) } label: { Label(L("action.shutdown"), systemImage: "power") }
                    .disabled(!cmd.canShutdown).help(L("help.shutdown"))
                Button { model.restart(item) } label: { Label(L("action.restart"), systemImage: "arrow.clockwise") }
                    .disabled(!cmd.canRestart).help(L("help.restart"))
                Button { model.forceStop(item) } label: { Label(L("action.forcestop"), systemImage: "xmark.octagon") }
                    .disabled(!cmd.canForceStop).help(L("help.forcestop"))
            }
        }
        // Attach to the VM's VNC display while it is live; drop it when the VM stops.
        .task(id: showDisplay) {
            if showDisplay {
                for _ in 0..<20 {   // the engine publishes the socket right after QEMU starts
                    if let path = await model.displaySocketPath(for: item) { await display.connect(socketPath: path); return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                await display.connect(socketPath: "")   // surfaces a clear failure
            } else {
                display.disconnect()
            }
        }
        .task(id: item.id) {
            while !Task.isCancelled {
                logTail = model.qemuLogTail(for: item)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onDisappear { display.disconnect() }
    }

    private var displayArea: some View {
        ZStack {
            EmbeddedDisplayView(session: display)
            switch display.status {
            case .connecting, .idle:
                VStack(spacing: 10) { ProgressView(); Text(L("display.connecting")).foregroundStyle(.secondary) }
                    .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            case .failed(let message):
                Label(L("display.failed", message), systemImage: "exclamationmark.triangle.fill")
                    .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            case .connected:
                EmptyView()
            }
        }
        .background(Color.black)
    }

    private func details(_ item: VMItem, state: VMRuntimeState) -> some View {
        let c = item.configuration
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    OSIcon(guest: c.guest, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name).font(.title2.weight(.semibold))
                        Text(L(c.guest.titleKey)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StateBadge(state: state)
                }

                if case .error(let m) = state {
                    Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }

                GroupBox {
                    Form {
                        LabeledContent(L("field.cpus"), value: "\(c.cpuCount)")
                        LabeledContent(L("field.memory"), value: formatMemory(c.memoryMiB))
                        LabeledContent(L("field.disk"), value: "\(c.disks.first?.sizeGiB ?? 0) GB")
                        LabeledContent(L("field.network"), value: L("network.nat"))
                        LabeledContent(L("field.iso")) {
                            HStack {
                                Text(c.installMedia.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? L("vmwindow.iso.none"))
                                    .foregroundStyle(.secondary)
                                if c.installMedia != nil {
                                    Button(L("action.eject")) { model.ejectInstallMedia(item) }
                                        .controlSize(.small).disabled(!state.isIdle).help(L("help.eject"))
                                }
                            }
                        }
                    }
                    .formStyle(.columns)
                    .padding(4)
                } label: { Text(L("vmwindow.hardware")).font(.headline) }

                GroupBox {
                    Label(L("vmwindow.display.note"), systemImage: "display")
                        .foregroundStyle(.secondary).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                } label: { Text(L("vmwindow.display")).font(.headline) }

                GroupBox {
                    ScrollView {
                        Text(logTail.isEmpty ? L("vmwindow.log.empty") : logTail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(logTail.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                } label: { Text(L("vmwindow.log")).font(.headline) }
            }
            .padding(20)
        }
    }
}
