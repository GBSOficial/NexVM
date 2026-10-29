import SwiftUI
import UniformTypeIdentifiers
import NexVMCore
import NexVMStorage

private enum WizardStep: Int, CaseIterable {
    case system, hardware, storage, review
    var titleKey: String {
        switch self {
        case .system: "wizard.step.system"
        case .hardware: "wizard.step.hardware"
        case .storage: "wizard.step.storage"
        case .review: "wizard.step.review"
        }
    }
}

struct NewVMWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LibraryViewModel

    @State private var step: WizardStep = .system
    @State private var name = ""
    @State private var guest: GuestOS = .windows11ARM64
    @State private var isoPath: String?
    @State private var cpu = 4
    @State private var mem = 4096
    @State private var disk = 64
    @State private var importing = false
    @State private var creating = false
    @FocusState private var nameFocused: Bool

    /// Windows 11 Setup requires Secure Boot; use the Secure Boot UEFI when it is installed.
    private var firmware: FirmwareKind { guest == .windows11ARM64 && model.secureBootAvailable ? .secureBoot : .standard }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftConfig: VMConfiguration {
        VMConfiguration(name: trimmedName, guest: guest, cpuCount: cpu, memoryMiB: mem,
                        disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: disk, format: .raw,
                                                  interface: guest == .windows11ARM64 ? .nvme : .virtioBlk)],
                        installMedia: isoPath.map(InstallMedia.init(path:)), firmware: firmware == .standard ? nil : firmware)
    }

    // Per-step validation. Returns a blocking message, or nil when the step is valid.
    private var isoProblem: String? {
        guard let isoPath else { return L("wizard.iso.required") }
        do { try ISOValidator.validate(path: isoPath); return nil } catch let e as ISOValidator.Issue {
            switch e {
            case .missingISO9660Signature: return nil   // warning only (UDF-only images exist); see isoWarning
            case .notFound: return L("wizard.iso.notfound")
            case .notAFile: return L("wizard.iso.notafile")
            case .wrongExtension: return L("wizard.iso.extension")
            case .tooSmall: return L("wizard.iso.toosmall")
            }
        } catch { return error.localizedDescription }
    }
    private var isoWarning: String? {
        guard let isoPath, isoProblem == nil else { return nil }
        return (try? ISOValidator.validate(path: isoPath)) == nil ? L("wizard.iso.nosignature") : nil
    }
    private var nameProblem: String? {
        if trimmedName.isEmpty { return L("wizard.name.required") }
        if trimmedName.count > ConfigurationValidator.maxNameLength { return L("wizard.name.toolong", ConfigurationValidator.maxNameLength) }
        return nil
    }
    private var storageProblem: String? {
        if disk < ResourcePolicy.minimumDiskGiB { return L("wizard.disk.toosmall", ResourcePolicy.minimumDiskGiB) }
        if disk > model.host.availableDiskGiB { return L("wizard.disk.toobig", model.host.availableDiskGiB) }
        return nil
    }
    private var reviewIssues: [ConfigurationIssue] { ConfigurationValidator.validate(draftConfig, host: model.host) }

    private func valid(_ s: WizardStep) -> Bool {
        switch s {
        case .system: nameProblem == nil && isoProblem == nil
        case .hardware: true
        case .storage: storageProblem == nil
        case .review: reviewIssues.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(current: step)
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case .system: systemStep
                    case .hardware: hardwareStep
                    case .storage: storageStep
                    case .review: reviewStep
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 440, idealHeight: 500)
        .onAppear {
            model.refreshHost()
            applyDefaults(for: guest)
            nameFocused = true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "iso") ?? .data]) { result in
            if case .success(let url) = result { isoPath = url.path }
        }
        .disabled(creating)
    }

    // MARK: Steps

    private var systemStep: some View {
        Form {
            TextField(L("field.name"), text: $name, prompt: Text(L("wizard.name.prompt")))
                .focused($nameFocused)
                .onSubmit { if valid(.system) { step = .hardware } }
            if let p = nameProblem, !name.isEmpty { problem(p) }
            Picker(L("field.os"), selection: $guest) {
                ForEach(GuestOS.allCases, id: \.self) { g in Text(L(g.titleKey)).tag(g) }
            }
            .onChange(of: guest) { _, g in applyDefaults(for: g) }
            LabeledContent(L("field.iso")) {
                HStack {
                    Text(isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? L("wizard.iso.none"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button(L("action.choose")) { importing = true }
                }
            }
            if let p = isoProblem, isoPath != nil { problem(p) }
            if let w = isoWarning { Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
            if guest == .windows11ARM64 && !model.secureBootAvailable {
                Label(L("wizard.sb.missing"), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if guest == .windows11ARM64 && !model.swtpmAvailable {
                Label(L("error.notpm"), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            Text(guest == .windows11ARM64 ? L("wizard.iso.hint.windows") : L("wizard.iso.hint.linux"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.columns)
    }

    private var hardwareStep: some View {
        let maxCPU = ResourcePolicy.maxCPUCount(host: model.host)
        let maxMem = ResourcePolicy.maxMemoryMiB(host: model.host)
        return Form {
            Stepper(value: $cpu, in: 1...maxCPU) { LabeledContent(L("field.cpus"), value: "\(cpu)") }
            Stepper(value: $mem, in: ResourcePolicy.minimumMemoryMiB...max(maxMem, ResourcePolicy.minimumMemoryMiB), step: 512) {
                LabeledContent(L("field.memory"), value: formatMemory(mem))
            }
            Text(L("hint.hostlimits", maxCPU, formatMemory(maxMem))).font(.footnote).foregroundStyle(.secondary)
            Button(L("wizard.useRecommended")) { applyDefaults(for: guest) }.controlSize(.small)
        }
        .formStyle(.columns)
    }

    private var storageStep: some View {
        Form {
            Stepper(value: $disk, in: ResourcePolicy.minimumDiskGiB...max(ResourcePolicy.minimumDiskGiB, model.host.availableDiskGiB), step: 8) {
                LabeledContent(L("field.disk"), value: "\(disk) GB")
            }
            if let p = storageProblem { problem(p) }
            LabeledContent(L("wizard.disk.free"), value: "\(model.host.availableDiskGiB) GB")
            LabeledContent(L("wizard.disk.location")) {
                Text(model.libraryRoot.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled).foregroundStyle(.secondary)
            }
            Text(L("wizard.disk.hint")).font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.columns)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OSIcon(guest: guest, size: 44)
                VStack(alignment: .leading) {
                    Text(trimmedName).font(.title3.weight(.semibold))
                    Text(L(guest.titleKey)).foregroundStyle(.secondary)
                }
            }
            Form {
                LabeledContent(L("field.iso"), value: isoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—")
                LabeledContent(L("field.cpus"), value: "\(cpu)")
                LabeledContent(L("field.memory"), value: formatMemory(mem))
                LabeledContent(L("field.disk"), value: "\(disk) GB")
                LabeledContent(L("field.network"), value: L("network.nat"))
                LabeledContent(L("field.firmware"), value: L(firmware == .secureBoot ? "firmware.secureboot" : "firmware.standard"))
            }
            .formStyle(.columns)
            ForEach(Array(reviewIssues.enumerated()), id: \.offset) { _, i in problem(i.description) }
            Text(L("wizard.review.hint")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func problem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(.red)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(L("action.cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            if creating { ProgressView().controlSize(.small); Text(L("wizard.creating")).foregroundStyle(.secondary) }
            if step != .system {
                Button(L("wizard.back")) { step = WizardStep(rawValue: step.rawValue - 1) ?? .system }
            }
            if step == .review {
                Button(L("action.create")) { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!valid(.review) || creating)
            } else {
                Button(L("wizard.next")) { step = WizardStep(rawValue: step.rawValue + 1) ?? .review }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!valid(step))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func create() {
        creating = true
        let ok = model.create(NewVMRequest(name: trimmedName, guest: guest, cpuCount: cpu, memoryMiB: mem, diskGiB: disk, isoPath: isoPath, firmware: firmware))
        creating = false
        if ok { dismiss() }
    }

    private func applyDefaults(for g: GuestOS) {
        let r = HardwareDefaults.resolved(for: g, host: model.host)
        cpu = r.cpuCount; mem = r.memoryMiB; disk = r.diskGiB
    }
}

private struct StepHeader: View {
    let current: WizardStep
    var body: some View {
        HStack(spacing: 0) {
            ForEach(WizardStep.allCases, id: \.self) { s in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(s.rawValue <= current.rawValue ? NexVMTheme.accent : Color.secondary.opacity(0.25))
                        if s.rawValue < current.rawValue {
                            Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        } else {
                            Text("\(s.rawValue + 1)").font(.caption2.weight(.bold))
                                .foregroundStyle(s == current ? Color.white : Color.secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(L(s.titleKey)).font(.callout.weight(s == current ? .semibold : .regular))
                        .foregroundStyle(s == current ? Color.primary : Color.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("a11y.step", s.rawValue + 1, WizardStep.allCases.count, L(s.titleKey)))
                .accessibilityAddTraits(s == current ? .isSelected : [])
                if s != WizardStep.allCases.last { Spacer(minLength: 8); Divider().frame(height: 14); Spacer(minLength: 8) }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }
}
