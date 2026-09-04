import Domain
import Foundation

/// Read-only parser for Claude Code session JSONL files. It decodes only
/// timestamps, model/cwd metadata and message usage counters; message content is
/// never retained or copied into TokenWatch snapshots.
public actor ClaudeCodeLogCollector {
    public enum CollectorError: Error, Equatable {
        case directoryNotReadable
    }

    private static let usageNeedle = Array("\"usage\"".utf8)
    private let calendar: Calendar
    private var cachedManifest: [LocalFileStamp]?
    private var cachedSnapshot: UsageSnapshot?

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func fetchSnapshot(
        claudeDirectory: URL,
        now: Date = Date()
    ) async throws -> UsageSnapshot {
        guard FileManager.default.isReadableFile(atPath: claudeDirectory.path) else {
            throw CollectorError.directoryNotReadable
        }

        let files = Self.sessionFiles(in: claudeDirectory)
        let manifest = files.map(\.stamp)
        if manifest == cachedManifest, let cachedSnapshot {
            return LocalCollectorSupport.refreshedSnapshot(cachedSnapshot, at: now)
        }

        var deduplicated: [String: LocalUsageSample] = [:]
        for file in files {
            for (key, sample) in try Self.parseSession(file.url) {
                if let previous = deduplicated[key], previous.usage.totalTokens >= sample.usage.totalTokens {
                    continue
                }
                deduplicated[key] = sample
            }
        }

        let samples = Array(deduplicated.values)
        let snapshot = LocalUsageSnapshotBuilder.makeSnapshot(
            providerID: LocalAIClient.claudeCode.rawValue,
            displayName: LocalAIClient.claudeCode.displayName,
            samples: samples,
            now: now,
            calendar: calendar,
            detail: samples.isEmpty ? "No local Claude Code token records found" : nil
        )
        cachedManifest = manifest
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func sessionFiles(in root: URL) -> [(url: URL, stamp: LocalFileStamp)] {
        let projects = root.appending(path: "projects", directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var result: [(URL, LocalFileStamp)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let stamp = LocalCollectorSupport.fileStamp(fileURL, relativeTo: root) else { continue }
            result.append((fileURL, stamp))
        }
        return result.sorted { $0.1.path < $1.1.path }
    }

    private static func parseSession(_ url: URL) throws -> [(String, LocalUsageSample)] {
        var result: [(String, LocalUsageSample)] = []
        try JSONLStreamReader.forEachLine(at: url, containingAny: [usageNeedle]) { line, index in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usageObject = message["usage"] as? [String: Any],
                  let timestampText = object["timestamp"] as? String,
                  let timestamp = LocalCollectorSupport.parseTimestamp(timestampText) else {
                return
            }

            let input = integer(usageObject["input_tokens"])
            let output = integer(usageObject["output_tokens"])
            let cacheCreation = integer(usageObject["cache_creation_input_tokens"])
            let cacheRead = integer(usageObject["cache_read_input_tokens"])
            let cached = cacheCreation + cacheRead
            let total = input + output + cached
            guard total > 0 else { return }

            let model = nonEmptyString(message["model"]) ?? "Unknown Claude model"
            let projectName = projectName(from: object["cwd"] as? String)
            let sessionID = nonEmptyString(object["sessionId"])
                ?? url.deletingPathExtension().lastPathComponent
            let messageID = nonEmptyString(message["id"])
                ?? nonEmptyString(object["uuid"])
                ?? "line-\(index)"
            let key = "\(sessionID)|\(messageID)"

            result.append((
                key,
                LocalUsageSample(
                    timestamp: timestamp,
                    model: model,
                    projectName: projectName,
                    usage: TokenUsage(
                        measurement: .incremental,
                        inputTokens: input,
                        outputTokens: output,
                        cachedInputTokens: cached,
                        reasoningOutputTokens: 0,
                        totalTokens: total
                    )
                )
            ))
        }
        return result
    }

    private static func projectName(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Unknown Claude Project" }
        let name = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
        return name.isEmpty ? "Unknown Claude Project" : name
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func integer(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let string = value as? String, let number = Int64(string) { return max(0, number) }
        return 0
    }
}
