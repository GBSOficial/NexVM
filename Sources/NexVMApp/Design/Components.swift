import SwiftUI
import NexVMCore
import NexVMEngine

extension GuestOS {
    var titleKey: String { self == .windows11ARM64 ? "guest.windows11arm64" : "guest.linuxarm64" }
    /// SF Symbols only; no third-party OS logos are bundled.
    var symbol: String { self == .windows11ARM64 ? "macwindow" : "terminal" }
}

extension VMRuntimeState {
    var isIdle: Bool {
        switch self { case .stopped, .error: true; default: false }
    }
    var titleKey: String {
        switch self {
        case .stopped: "state.stopped"
        case .starting: "state.starting"
        case .running: "state.running"
        case .stopping: "state.stopping"
        case .paused: "state.paused"
        case .error: "state.error"
        }
    }
}

struct BrandSymbol: View {
    var size: CGFloat = 28
    var body: some View {
        Image("NexVMSymbol", bundle: .module)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct OSIcon: View {
    let guest: GuestOS
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(NexVMTheme.tint(for: guest).opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: guest.symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(NexVMTheme.tint(for: guest)))
            .accessibilityHidden(true)
    }
}

/// State is always communicated by icon + text, never by color alone.
struct StateBadge: View {
    let state: VMRuntimeState
    var body: some View {
        let color = NexVMTheme.color(for: state)
        Label(L(state.titleKey), systemImage: NexVMTheme.symbol(for: state))
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("a11y.state", L(state.titleKey)))
    }
}

struct SpecLabel: View {
    let symbol: String
    let text: String
    let accessibility: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)
    }
}

func formatMemory(_ mib: Int) -> String {
    mib % 1024 == 0 ? "\(mib / 1024) GB" : "\(mib) MiB"
}

/// Primary lifecycle control shared by cards, the VM window and menus.
struct LifecycleCommands {
    let state: VMRuntimeState
    let qemuAvailable: Bool
    var canStart: Bool { qemuAvailable && state.isIdle }
    var canShutdown: Bool { state == .running }
    var canRestart: Bool { state == .running }
    var canForceStop: Bool { !state.isIdle }
    var isTransitioning: Bool { state == .starting || state == .stopping }
}
