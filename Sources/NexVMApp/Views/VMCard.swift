import SwiftUI
import NexVMCore
import NexVMEngine

struct VMCard: View {
    @Bindable var model: LibraryViewModel
    let item: VMItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let c = item.configuration
        let state = model.state(of: item)
        let cmd = LifecycleCommands(state: state, startBlocked: model.startBlocker(for: c.guest) != nil)
        let selected = model.selection == item.id

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                OSIcon(guest: c.guest)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline).lineLimit(1).truncationMode(.tail)
                    Text(L(c.guest.titleKey)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                StateBadge(state: state)
            }

            HStack(spacing: 14) {
                SpecLabel(symbol: "cpu", text: "\(c.cpuCount)", accessibility: L("a11y.cpus", c.cpuCount))
                SpecLabel(symbol: "memorychip", text: formatMemory(c.memoryMiB), accessibility: L("a11y.memory", formatMemory(c.memoryMiB)))
                SpecLabel(symbol: "internaldrive", text: "\(c.disks.first?.sizeGiB ?? 0) GB", accessibility: L("a11y.disk", c.disks.first?.sizeGiB ?? 0))
            }

            if case .error(let message) = state {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
            }

            HStack {
                primaryAction(cmd)
                Button { openWindow(value: item.id) } label: { Label(L("action.details"), systemImage: "slider.horizontal.3") }
                    .help(L("help.details"))
                Spacer()
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(NexVMTheme.cardBackground, in: RoundedRectangle(cornerRadius: NexVMTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NexVMTheme.cardRadius, style: .continuous)
                .strokeBorder(selected ? NexVMTheme.accent : NexVMTheme.cardBorder, lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: NexVMTheme.cardRadius, style: .continuous))
        .onTapGesture(count: 2) { openWindow(value: item.id) }
        .onTapGesture { model.selection = item.id }
        .contextMenu { VMContextMenu(model: model, item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(c.name), \(L(c.guest.titleKey)), \(L(state.titleKey))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func primaryAction(_ cmd: LifecycleCommands) -> some View {
        if cmd.isTransitioning {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L(model.state(of: item).titleKey)) }
                .font(.callout).foregroundStyle(.secondary)
        } else if cmd.canShutdown {
            Button { model.requestShutdown(item) } label: { Label(L("action.shutdown"), systemImage: "power") }
                .help(L("help.shutdown"))
        } else {
            Button {
                model.start(item)
                if model.embeddedDisplay { openWindow(value: item.id) }   // the display lives in the VM window
            } label: { Label(L("action.start"), systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(!cmd.canStart)
                .help(model.startBlocker(for: item.configuration.guest) ?? L("help.start"))
        }
    }
}

struct VMContextMenu: View {
    @Bindable var model: LibraryViewModel
    let item: VMItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let cmd = LifecycleCommands(state: model.state(of: item), startBlocked: model.startBlocker(for: item.configuration.guest) != nil)
        Button(L("action.start"), systemImage: "play.fill") {
            model.start(item)
            if model.embeddedDisplay { openWindow(value: item.id) }
        }.disabled(!cmd.canStart)
        Button(L("action.shutdown"), systemImage: "power") { model.requestShutdown(item) }.disabled(!cmd.canShutdown)
        Button(L("action.restart"), systemImage: "arrow.clockwise") { model.restart(item) }.disabled(!cmd.canRestart)
        Button(L("action.forcestop"), systemImage: "xmark.octagon") { model.forceStop(item) }.disabled(!cmd.canForceStop)
        Button(L("action.eject"), systemImage: "eject") { model.ejectInstallMedia(item) }
            .disabled(!cmd.canStart || item.configuration.installMedia == nil)
        Divider()
        Button(L("action.details"), systemImage: "slider.horizontal.3") { openWindow(value: item.id) }
        Button(L("action.reveal"), systemImage: "folder") { model.revealInFinder(item) }
        Divider()
        Button(L("action.remove"), systemImage: "tray.and.arrow.up") { model.remove(item) }.disabled(cmd.canForceStop)
        Button(L("action.delete"), systemImage: "trash", role: .destructive) { model.pendingDeletion = item }.disabled(cmd.canForceStop)
    }
}
