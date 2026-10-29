import SwiftUI
import NexVMCore

struct SettingsView: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label(L("settings.general"), systemImage: "gearshape") }
            HardwareSettings(model: model).tabItem { Label(L("settings.hardware"), systemImage: "cpu") }
            StorageSettings(model: model).tabItem { Label(L("settings.storage"), systemImage: "internaldrive") }
            NetworkSettings().tabItem { Label(L("settings.network"), systemImage: "network") }
            AdvancedSettings(model: model).tabItem { Label(L("settings.advanced"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540, height: 360)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: LibraryViewModel
    var body: some View {
        Form {
            HStack(spacing: 14) {
                BrandSymbol(size: 52)
                VStack(alignment: .leading) {
                    Text("NexVM").font(.title2.weight(.semibold))
                    Text(L("brand.tagline")).foregroundStyle(.secondary)
                    Text(L("settings.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("QEMU") {
                    Label(model.qemuAvailable ? L("settings.qemu.found") : L("settings.qemu.missing"),
                          systemImage: model.qemuAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.qemuAvailable ? Color.green : Color.orange)
                }
                if let p = model.qemuPath {
                    LabeledContent(L("settings.qemu.path")) {
                        Text(p).textSelection(.enabled).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            Text(L("settings.privacy")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct HardwareSettings: View {
    @Bindable var model: LibraryViewModel
    @AppStorage(HardwareDefaults.useRecommendedKey) private var useRecommended = true
    @AppStorage(HardwareDefaults.cpuKey) private var cpu = 4
    @AppStorage(HardwareDefaults.memoryKey) private var mem = 4096

    var body: some View {
        let maxCPU = ResourcePolicy.maxCPUCount(host: model.host)
        let maxMem = ResourcePolicy.maxMemoryMiB(host: model.host)
        Form {
            Toggle(L("settings.useRecommended"), isOn: $useRecommended)
            Stepper(value: $cpu, in: 1...maxCPU) { LabeledContent(L("field.cpus"), value: "\(min(cpu, maxCPU))") }
                .disabled(useRecommended)
            Stepper(value: $mem, in: ResourcePolicy.minimumMemoryMiB...max(maxMem, ResourcePolicy.minimumMemoryMiB), step: 512) {
                LabeledContent(L("field.memory"), value: formatMemory(min(mem, maxMem)))
            }
            .disabled(useRecommended)
            Text(L("settings.hardware.note", maxCPU, formatMemory(maxMem))).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct StorageSettings: View {
    @Bindable var model: LibraryViewModel
    @AppStorage(HardwareDefaults.useRecommendedKey) private var useRecommended = true
    @AppStorage(HardwareDefaults.diskKey) private var disk = 64

    var body: some View {
        Form {
            LabeledContent(L("wizard.disk.location")) {
                Text(model.libraryRoot.path).textSelection(.enabled).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            LabeledContent(L("wizard.disk.free"), value: "\(model.host.availableDiskGiB) GB")
            Stepper(value: $disk, in: ResourcePolicy.minimumDiskGiB...max(ResourcePolicy.minimumDiskGiB, model.host.availableDiskGiB), step: 8) {
                LabeledContent(L("settings.defaultDisk"), value: "\(disk) GB")
            }
            .disabled(useRecommended)
            Button(L("action.revealLibrary")) { model.revealLibrary() }
            Text(L("settings.storage.note")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { model.refreshHost() }
    }
}

private struct NetworkSettings: View {
    var body: some View {
        Form {
            LabeledContent(L("field.network"), value: L("network.nat"))
            Text(L("settings.network.note")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Bindable var model: LibraryViewModel
    @AppStorage(LibraryViewModel.embeddedDisplayKey) private var embeddedDisplay = true
    var body: some View {
        Form {
            Toggle(L("settings.display.embedded"), isOn: $embeddedDisplay)
            Text(L("settings.display.note")).font(.footnote).foregroundStyle(.secondary)
            LabeledContent(L("settings.logfile")) {
                Text(model.logURL.path).textSelection(.enabled).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Button(L("action.revealLog")) { model.revealLog() }
            Text(L("settings.advanced.note")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
