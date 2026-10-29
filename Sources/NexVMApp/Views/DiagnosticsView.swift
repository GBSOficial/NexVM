import SwiftUI
import NexVMDiagnostics

struct DiagnosticsView: View {
    @Bindable var model: LibraryViewModel
    @State private var entries: [LogEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L("diag.system")) {
                    LabeledContent(L("diag.memory"), value: formatMemory(model.host.physicalMemoryMiB))
                    LabeledContent(L("diag.cores"), value: "\(model.host.cpuCores)")
                    LabeledContent(L("diag.freedisk"), value: "\(model.host.availableDiskGiB) GB")
                    LabeledContent("QEMU") {
                        Text(model.qemuPath ?? L("diag.qemu.missing")).textSelection(.enabled)
                            .foregroundStyle(model.qemuAvailable ? Color.secondary : Color.red).lineLimit(1).truncationMode(.middle)
                    }
                }
                Section(L("diag.log")) {
                    if entries.isEmpty {
                        Text(L("diag.log.empty")).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(entries.prefix(200).enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: icon(e.level)).foregroundStyle(color(e.level)).accessibilityLabel(e.level.rawValue)
                                Text(e.timestamp.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                                Text("\(e.category): \(e.message)").textSelection(.enabled)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle(L("sidebar.diagnostics"))
        .toolbar {
            ToolbarItemGroup {
                Button { entries = model.readAppLog(); model.refreshHost() } label: { Label(L("action.refresh"), systemImage: "arrow.clockwise") }
                    .help(L("action.refresh"))
                Button { model.revealLog() } label: { Label(L("action.revealLog"), systemImage: "folder") }
                    .help(L("action.revealLog"))
            }
        }
        .onAppear { entries = model.readAppLog(); model.refreshHost() }
    }

    private func icon(_ l: LogLevel) -> String {
        switch l { case .debug: "ladybug"; case .info: "info.circle"; case .warning: "exclamationmark.triangle"; case .error: "xmark.octagon" }
    }
    private func color(_ l: LogLevel) -> Color {
        switch l { case .debug, .info: .secondary; case .warning: .orange; case .error: .red }
    }
}
