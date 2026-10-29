import SwiftUI
import NexVMEngine
import NexVMCore

/// NexVM design tokens (from the Brand Kit, assets/brand/BRAND_GUIDE.md).
/// Brand colors carry identity and active states; body surfaces and text use system
/// semantic colors so Light/Dark Mode and accessibility settings keep working.
enum NexVMTheme {
    static let blue = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    static let purple = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
    static let cyan = Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)
    static let dark = Color(red: 11 / 255, green: 15 / 255, blue: 26 / 255)
    static let gray = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let light = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)

    static let accent = blue
    /// Use sparingly (hero symbol, selection accents), never behind body text.
    static let gradient = LinearGradient(colors: [cyan, blue, purple], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBorder = Color(nsColor: .separatorColor)
    static let cardRadius: CGFloat = 12

    static func color(for state: VMRuntimeState) -> Color {
        switch state {
        case .stopped: .secondary
        case .starting, .stopping: .orange
        case .running: .green
        case .paused: .yellow
        case .error: .red
        }
    }

    static func symbol(for state: VMRuntimeState) -> String {
        switch state {
        case .stopped: "stop.circle.fill"
        case .starting, .stopping: "clock.fill"
        case .running: "play.circle.fill"
        case .paused: "pause.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    static func tint(for guest: GuestOS) -> Color { guest == .windows11ARM64 ? blue : purple }
}
