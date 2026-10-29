import SwiftUI
import NexVMCore
import NexVMEngine

func L(_ key: String) -> String { Bundle.module.localizedString(forKey: key, value: key, table: nil) }

extension GuestOS {
    var titleKey: String { self == .windows11ARM64 ? "guest.windows11arm64" : "guest.linuxarm64" }
    var symbol: String { self == .windows11ARM64 ? "macwindow" : "terminal" }
}

struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    @State private var selection: UUID?
    @State private var showingNew = false
    @State private var pendingDelete: VMItem?

    var body: some View {
        NavigationSplitView {
            List(model.items, selection: $selection) { item in
                Label(item.configuration.name, systemImage: item.configuration.guest.symbol)
                    .tag(item.id)
            }
            .navigationTitle("NexVM")
            .overlay {
                if model.items.isEmpty {
                    ContentUnavailableView {
                        Label(L("library.empty.title"), systemImage: "externaldrive.badge.plus")
                    } description: {
                        Text(L("library.empty.description"))
                    }
                }
            }
        } detail: {
            if let item = model.items.first(where: { $0.id == selection }) {
                DetailView(item: item, state: model.state(of: item), qemuAvailable: model.qemuAvailable,
                           onStart: { model.start(item) },
                           onShutdown: { model.requestShutdown(item) },
                           onForceStop: { model.forceStop(item) },
                           onRemove: { model.remove(item); selection = nil },
                           onDelete: { pendingDelete = item })
            } else {
                Text(L("detail.noselection")).foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showingNew = true } label: { Label(L("action.newvm"), systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) { NewVMSheet(model: model) }
        .confirmationDialog(L("delete.title"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete
        ) { item in
            Button(L("delete.confirm"), role: .destructive) { model.deleteData(item); selection = nil }
        } message: { item in
            Text(String(format: L("delete.message %@"), item.configuration.name))
        }
        .alert(L("error.title"), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct DetailView: View {
    let item: VMItem
    let state: VMRuntimeState
    let qemuAvailable: Bool
    var onStart: () -> Void
    var onShutdown: () -> Void
    var onForceStop: () -> Void
    var onRemove: () -> Void
    var onDelete: () -> Void

    private var idle: Bool {
        switch state { case .stopped, .error: true; default: false }
    }

    private var stateText: String {
        switch state {
        case .stopped: L("state.stopped")
        case .starting: L("state.starting")
        case .running: L("state.running")
        case .stopping: L("state.stopping")
        case .paused: L("state.paused")
        case .error(let m): "\(L("state.error")): \(m)"
        }
    }

    var body: some View {
        let c = item.configuration
        Form {
            Section {
                LabeledContent(L("field.os"), value: L(c.guest.titleKey))
                LabeledContent(L("field.cpus"), value: "\(c.cpuCount)")
                LabeledContent(L("field.memory"), value: "\(c.memoryMiB) MiB")
                LabeledContent(L("field.disk"), value: "\(c.disks.first?.sizeGiB ?? 0) GiB")
                LabeledContent(L("field.state"), value: stateText)
            }
            Section {
                HStack {
                    Button(L("action.start"), systemImage: "play.fill", action: onStart)
                        .disabled(!idle || !qemuAvailable)
                    Button(L("action.shutdown"), systemImage: "power", action: onShutdown)
                        .disabled(state != .running)
                    Button(L("action.forcestop"), systemImage: "xmark.octagon", role: .destructive, action: onForceStop)
                        .disabled(idle)
                }
                if !qemuAvailable { Text(L("error.noqemu")).foregroundStyle(.secondary) }
                Text(L("detail.display")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(L("action.remove"), action: onRemove).disabled(!idle)
                Button(L("action.delete"), role: .destructive, action: onDelete).disabled(!idle)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(c.name)
    }
}

struct NewVMSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LibraryViewModel
    @State private var name = ""
    @State private var guest: GuestOS = .windows11ARM64
    @State private var cpu = 4
    @State private var mem = 4096
    @State private var disk = 64
    @State private var isoPath: String?
    @State private var importing = false

    var body: some View {
        let maxCPU = ResourcePolicy.maxCPUCount(host: model.host)
        let maxMem = ResourcePolicy.maxMemoryMiB(host: model.host)
        Form {
            TextField(L("field.name"), text: $name)
            Picker(L("field.os"), selection: $guest) {
                ForEach(GuestOS.allCases, id: \.self) { g in Text(L(g.titleKey)).tag(g) }
            }
            .onChange(of: guest) { _, g in apply(model.recommendation(for: g)) }
            Stepper(value: $cpu, in: 1...maxCPU) { LabeledContent(L("field.cpus"), value: "\(cpu)") }
            Stepper(value: $mem, in: ResourcePolicy.minimumMemoryMiB...maxMem, step: 512) {
                LabeledContent(L("field.memory"), value: "\(mem) MiB")
            }
            Stepper(value: $disk, in: ResourcePolicy.minimumDiskGiB...max(ResourcePolicy.minimumDiskGiB, model.host.availableDiskGiB), step: 8) {
                LabeledContent(L("field.disk"), value: "\(disk) GiB")
            }
            LabeledContent(L("field.iso")) {
                HStack {
                    Text(isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—").foregroundStyle(.secondary)
                    Button(L("action.choose")) { importing = true }
                }
            }
            Text(L("hint.hostlimits")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.bottom, 8)
        .onAppear { apply(model.recommendation(for: guest)) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.init(filenameExtension: "iso") ?? .data]) { result in
            if case .success(let url) = result { isoPath = url.path }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("action.create")) {
                    let ok = model.create(NewVMRequest(name: name, guest: guest, cpuCount: cpu, memoryMiB: mem, diskGiB: disk, isoPath: isoPath))
                    if ok { dismiss() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func apply(_ r: ResourceRecommendation) { cpu = r.cpuCount; mem = r.memoryMiB; disk = r.diskGiB }
}
