import SwiftUI
import NexVMCore
import NexVMEngine

/// One window per VM, separate from the management window. It never draws guest output:
/// the guest display is the QEMU window (embedded display is not implemented yet).
struct VMWindowView: View {
    @Bindable var model: LibraryViewModel
    let vmID: UUID?
    @State private var logTail = ""

    var body: some View {
        if let item = model.item(vmID) {
            content(item)
        } else {
            ContentUnavailableView(L("vmwindow.missing"), systemImage: "questionmark.folder")
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func content(_ item: VMItem) -> some View {
        let c = item.configuration
        let state = model.state(of: item)
        let cmd = LifecycleCommands(state: state, qemuAvailable: model.qemuAvailable)
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
                        LabeledContent(L("field.iso"), value: c.installMedia.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "—")
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
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle(c.name)
        .navigationSubtitle(L(state.titleKey))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.start(item) } label: { Label(L("action.run"), systemImage: "play.fill") }
                    .disabled(!cmd.canStart).help(model.qemuAvailable ? L("help.start") : L("error.noqemu"))
                Button { model.requestShutdown(item) } label: { Label(L("action.shutdown"), systemImage: "power") }
                    .disabled(!cmd.canShutdown).help(L("help.shutdown"))
                Button { model.restart(item) } label: { Label(L("action.restart"), systemImage: "arrow.clockwise") }
                    .disabled(!cmd.canRestart).help(L("help.restart"))
                Button { model.forceStop(item) } label: { Label(L("action.forcestop"), systemImage: "xmark.octagon") }
                    .disabled(!cmd.canForceStop).help(L("help.forcestop"))
            }
        }
        .task(id: item.id) {
            while !Task.isCancelled {
                logTail = model.qemuLogTail(for: item)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
