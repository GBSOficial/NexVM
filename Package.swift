// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NexVM",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NexVM", targets: ["NexVMApp"]),
        .library(name: "NexVMCore", targets: ["NexVMCore"]),
        .library(name: "NexVMStorage", targets: ["NexVMStorage"]),
        .library(name: "NexVMEngine", targets: ["NexVMEngine"]),
        .library(name: "NexVMQEMU", targets: ["NexVMQEMU"]),
        .library(name: "NexVMDiagnostics", targets: ["NexVMDiagnostics"]),
        .library(name: "NexVMDisplay", targets: ["NexVMDisplay"]),
    ],
    targets: [
        .target(name: "NexVMCore"),
        .target(name: "NexVMDiagnostics"),
        .target(name: "NexVMDisplay"),
        .target(name: "NexVMStorage", dependencies: ["NexVMCore"]),
        .target(name: "NexVMEngine", dependencies: ["NexVMCore"]),
        .target(name: "NexVMQEMU", dependencies: ["NexVMCore", "NexVMEngine", "NexVMStorage", "NexVMDiagnostics"]),
        .executableTarget(
            name: "NexVMApp",
            dependencies: ["NexVMCore", "NexVMStorage", "NexVMEngine", "NexVMQEMU", "NexVMDiagnostics", "NexVMDisplay"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "NexVMCoreTests", dependencies: ["NexVMCore"]),
        .testTarget(name: "NexVMStorageTests", dependencies: ["NexVMStorage", "NexVMCore"]),
        .testTarget(name: "NexVMQEMUTests", dependencies: ["NexVMQEMU", "NexVMCore", "NexVMStorage", "NexVMDisplay"]),
        .testTarget(name: "NexVMDiagnosticsTests", dependencies: ["NexVMDiagnostics"]),
        .testTarget(name: "NexVMDisplayTests", dependencies: ["NexVMDisplay"]),
    ],
    swiftLanguageModes: [.v6]
)
