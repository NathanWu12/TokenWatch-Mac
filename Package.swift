// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TokenWatchCore",
    platforms: [.macOS(.v14), .iOS(.v18), .watchOS(.v11)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "MacProviderAdapters", targets: ["MacProviderAdapters"]),
        .library(name: "SyncProtocol", targets: ["SyncProtocol"]),
        .library(name: "SyncSecurity", targets: ["SyncSecurity"]),
        .library(name: "LocalTransport", targets: ["LocalTransport"]),
        .library(name: "RemoteSync", targets: ["RemoteSync"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .executable(name: "SimulatorSnapshotExport", targets: ["SimulatorSnapshotExport"]),
    ],
    targets: [
        .target(name: "Domain"),
                .target(
            name: "MacProviderAdapters",
            dependencies: ["Domain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "SyncProtocol", dependencies: ["Domain"]),
        .target(name: "SyncSecurity", dependencies: ["Domain"], path: "Sources/Security"),
        .target(name: "LocalTransport"),
        .target(name: "RemoteSync", dependencies: ["Domain", "SyncSecurity"]),
        .target(name: "TestSupport", dependencies: ["Domain"]),
        .executableTarget(
            name: "SimulatorSnapshotExport",
            dependencies: ["MacProviderAdapters", "Domain", "SyncProtocol"]
        ),
        .testTarget(name: "DomainTests", dependencies: ["Domain", "TestSupport"]),
        .testTarget(
            name: "MacProviderAdaptersTests",
            dependencies: ["MacProviderAdapters", "Domain", "TestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "SyncProtocolTests", dependencies: ["SyncProtocol", "Domain", "TestSupport"]),
        .testTarget(
            name: "SyncSecurityTests",
            dependencies: ["SyncSecurity", "Domain", "TestSupport"],
            path: "Tests/SecurityTests"
        ),
        .testTarget(name: "LocalTransportTests", dependencies: ["LocalTransport"]),
        .testTarget(
            name: "RemoteSyncTests",
            dependencies: ["RemoteSync", "SyncSecurity", "Domain", "TestSupport"]
        ),
    ]
)
