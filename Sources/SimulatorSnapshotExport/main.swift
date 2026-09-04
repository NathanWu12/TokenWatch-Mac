#if DEBUG
import Darwin
import Domain
import Foundation
import MacProviderAdapters
import SyncProtocol

@main
enum SimulatorSnapshotExport {
    static func main() async {
        guard ProcessInfo.processInfo.environment[
            "TOKENWATCH_ALLOW_REAL_SIMULATOR_DATA"
        ] == "1" else {
            fail("Real simulator export requires an explicit debug-only opt-in.")
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let outputIndex = arguments.firstIndex(of: "--output"),
              arguments.indices.contains(outputIndex + 1) else {
            fail("Usage: SimulatorSnapshotExport --output <file>")
        }
        let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
            .standardizedFileURL
        let cacheDirectory: URL? = arguments.firstIndex(of: "--cache-directory").flatMap { index in
            guard arguments.indices.contains(index + 1) else { return nil }
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
        }
        guard outputURL.pathExtension == "json" else {
            fail("The debug snapshot output must be a JSON file.")
        }

        let priorMask = umask(0o077)
        defer { _ = umask(priorMask) }

        do {
            let locations = LocalAIClientDiscovery().discover()
            var snapshots: [UsageSnapshot] = []
            let now = Date()

            if let codex = locations.first(where: { $0.client == .codex }),
               let snapshot = try? await CodexLogCollector().fetchSnapshot(
                    codexDirectory: codex.rootDirectory,
                    now: now,
                    cacheDirectory: cacheDirectory
               ) {
                snapshots.append(snapshot)
            }
            if let claude = locations.first(where: { $0.client == .claudeCode }),
               let snapshot = try? await ClaudeCodeLogCollector().fetchSnapshot(
                    claudeDirectory: claude.rootDirectory,
                    now: now
               ) {
                snapshots.append(snapshot)
            }
            let antigravity = locations
                .filter { $0.client == .antigravity }
                .map(\.rootDirectory)
            if !antigravity.isEmpty,
               let snapshot = try? await AntigravityLogCollector().fetchSnapshot(
                    antigravityDirectories: antigravity,
                    now: now
               ) {
                snapshots.append(snapshot)
            }
            if let openCode = locations.first(where: { $0.client == .openCode }),
               let snapshot = try? await OpenCodeLogCollector().fetchSnapshot(
                    openCodeDirectory: openCode.rootDirectory,
                    now: now
               ) {
                snapshots.append(snapshot)
            }

            guard !snapshots.isEmpty else {
                fail("No readable supported AI client usage data was found.")
            }

            let snapshot = LocalUsageSnapshotMerger.merge(snapshots, generatedAt: now)
            let data = try SnapshotCodec.encode(snapshot)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: outputURL.path
            )

            let detected = Set(locations.map { $0.client.displayName }).sorted().joined(separator: ", ")
            let providers = snapshot.providers
                .map { "\($0.displayName)=\($0.periods.recordedAllTime.usage.totalTokens)" }
                .joined(separator: ", ")
            print("✓ Auto-discovery: \(detected)")
            print("✓ Snapshot providers: \(providers)")
        } catch {
            fail("Unable to export the debug simulator snapshot.")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}
#else
import Foundation

@main
enum SimulatorSnapshotExport {
    static func main() {
        FileHandle.standardError.write(
            Data("SimulatorSnapshotExport is unavailable in Release builds.\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
}
#endif
