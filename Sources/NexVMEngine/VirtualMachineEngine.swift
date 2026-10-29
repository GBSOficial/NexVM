import Foundation
import NexVMCore

public enum VMRuntimeState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case paused
    case error(String)
}

public enum EngineError: Error, Equatable, Sendable {
    case alreadyRunning(UUID)
    case notRunning(UUID)
    case backendUnavailable(String)
    case launchFailed(String)
    case timedOut(String)
}

/// Contract every virtualization backend implements. The UI and application layers
/// depend on this protocol only, so backends can be swapped.
public protocol VirtualMachineEngine: Sendable {
    func start(_ configuration: VMConfiguration, bundleURL: URL) async throws
    /// Asks the guest to power off (ACPI). Does not kill the VM.
    func requestShutdown(vmID: UUID) async throws
    /// Resets the guest like a hardware reset button (not a graceful reboot). VM keeps running.
    func restart(vmID: UUID) async throws
    /// Terminates only the process this engine started for `vmID`.
    func forceStop(vmID: UUID) async throws
    func state(of vmID: UUID) async -> VMRuntimeState
}
