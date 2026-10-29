import SwiftUI
import NexVMCore

enum SidebarSection: String, Hashable, CaseIterable {
    case machines, diagnostics
    var titleKey: String { self == .machines ? "sidebar.machines" : "sidebar.diagnostics" }
    var symbol: String { self == .machines ? "desktopcomputer" : "stethoscope" }
}

struct MainWindowView: View {
    @Bindable var model: LibraryViewModel
    @State private var section: SidebarSection? = .machines

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, id: \.self, selection: $section) { s in
                Label(L(s.titleKey), systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .top, spacing: 0) { SidebarHeader() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    SettingsLink { Label(L("sidebar.settings"), systemImage: "gearshape") }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(L("help.settings"))
                }
            }
        } detail: {
            switch section ?? .machines {
            case .machines: MachinesView(model: model)
            case .diagnostics: DiagnosticsView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showingNewVM = true } label: { Label(L("action.newvm"), systemImage: "plus") }
                    .help(L("help.newvm"))
            }
        }
        .sheet(isPresented: $model.showingNewVM) { NewVMWizard(model: model) }
        .confirmationDialog(L("delete.title"), isPresented: Binding(
            get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } }),
            presenting: model.pendingDeletion
        ) { item in
            Button(L("delete.confirm"), role: .destructive) { model.deleteData(item) }
            Button(L("action.cancel"), role: .cancel) {}
        } message: { item in
            Text(L("delete.message", item.configuration.name))
        }
        .alert(L("error.title"), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            BrandSymbol(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("NexVM").font(.headline)
                Text(L("brand.tagline")).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NexVM, \(L("brand.tagline"))")
    }
}

struct MachinesView: View {
    @Bindable var model: LibraryViewModel

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16, alignment: .top)]

    var body: some View {
        Group {
            if model.items.isEmpty {
                EmptyLibraryView { model.showingNewVM = true }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !model.qemuAvailable {
                            Label(L("error.noqemu"), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.callout)
                        }
                        if !model.failedBundles.isEmpty {
                            Label(L("library.unreadable", model.failedBundles.count), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary).font(.callout)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(model.items) { item in VMCard(model: model, item: item) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(L("library.title"))
        .navigationSubtitle(model.items.isEmpty ? "" : (model.items.count == 1 ? L("library.count.one") : L("library.count.other", model.items.count)))
    }
}

struct EmptyLibraryView: View {
    var create: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image("NexVMHorizontal", bundle: .module)
                .resizable().scaledToFit().frame(maxWidth: 260)
                .accessibilityLabel("NexVM")
            Text(L("library.empty.title")).font(.title2.weight(.semibold))
            Text(L("library.empty.description"))
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button(action: create) { Label(L("action.createvm"), systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .help(L("help.newvm"))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
