import Domain
import Foundation

/// Passive Antigravity transcript reader.
///
/// Antigravity transcripts currently do not expose authoritative token usage,
/// so this collector produces an explicit text-size estimate. It never retains
/// transcript content in the resulting snapshot.
public actor AntigravityLogCollector {
    public enum CollectorError: Error, Equatable {
        case directoryNotReadable
    }

    private let calendar: Calendar
    private var cachedManifest: [LocalFileStamp]?
    private var cachedSnapshot: UsageSnapshot?

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func fetchSnapshot(
        antigravityDirectories: [URL],
        now: Date = Date()
    ) async throws -> UsageSnapshot {
        let readable = antigravityDirectories.filter {
            FileManager.default.isReadableFile(atPath: $0.path)
        }
        guard !readable.isEmpty else { throw CollectorError.directoryNotReadable }

        let files = readable.flatMap(Self.transcriptFiles(in:))
            .sorted { $0.stamp.path < $1.stamp.path }
        let manifest = files.map(\.stamp)
        if manifest == cachedManifest, let cachedSnapshot {
            return LocalCollectorSupport.refreshedSnapshot(cachedSnapshot, at: now)
        }

        let samples = try files.flatMap { try Self.parseTranscript($0.url) }
        let snapshot = LocalUsageSnapshotBuilder.makeSnapshot(
            providerID: LocalAIClient.antigravity.rawValue,
            displayName: LocalAIClient.antigravity.displayName,
            samples: samples,
            now: now,
            calendar: calendar,
            detail: samples.isEmpty
                ? "Local Antigravity transcripts found; no estimable usage records"
                : "Estimated from local transcript text; Antigravity does not expose exact token counts locally",
            isEstimated: true
        )
        cachedManifest = manifest
        cachedSnapshot = snapshot
        return snapshot
    }

    private static func transcriptFiles(in root: URL) -> [(url: URL, stamp: LocalFileStamp)] {
        let brain = root.appending(path: "brain", directoryHint: .isDirectory)
        guard let conversations = try? FileManager.default.contentsOfDirectory(
            at: brain,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return conversations.compactMap { conversation in
            let logs = conversation
                .appending(path: ".system_generated", directoryHint: .isDirectory)
                .appending(path: "logs", directoryHint: .isDirectory)
            let full = logs.appending(path: "transcript_full.jsonl", directoryHint: .notDirectory)
            let compact = logs.appending(path: "transcript.jsonl", directoryHint: .notDirectory)
            let transcript: URL
            if FileManager.default.isReadableFile(atPath: full.path) {
                transcript = full
            } else if FileManager.default.isReadableFile(atPath: compact.path) {
                transcript = compact
            } else {
                return nil
            }
            guard let rawStamp = LocalCollectorSupport.fileStamp(transcript, relativeTo: root) else {
                return nil
            }
            let stamp = LocalFileStamp(
                path: root.standardizedFileURL.path + "|" + rawStamp.path,
                fileSize: rawStamp.fileSize,
                modificationDate: rawStamp.modificationDate
            )
            return (transcript, stamp)
        }
    }

    private static func parseTranscript(_ url: URL) throws -> [LocalUsageSample] {
        var pendingInput: Int64 = 0
        var currentProject = "Unknown Antigravity Project"
        var result: [LocalUsageSample] = []

        try JSONLStreamReader.forEachLine(at: url) { line, _ in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let timestampText = object["created_at"] as? String,
                  let timestamp = LocalCollectorSupport.parseTimestamp(timestampText) else {
                return
            }

            if let detectedProject = projectName(from: object["tool_calls"]) {
                currentProject = detectedProject
            }

            let type = (object["type"] as? String)?.uppercased() ?? ""
            if type == "PLANNER_RESPONSE" {
                let output = estimatedTokens(object["content"])
                    + estimatedTokens(object["tool_calls"])
                let reasoning = estimatedTokens(object["thinking"])
                let total = pendingInput + output + reasoning
                if total > 0 {
                    result.append(
                        LocalUsageSample(
                            timestamp: timestamp,
                            model: "Antigravity",
                            projectName: currentProject,
                            usage: TokenUsage(
                                measurement: .incremental,
                                inputTokens: pendingInput,
                                outputTokens: output,
                                cachedInputTokens: 0,
                                reasoningOutputTokens: reasoning,
                                totalTokens: total
                            )
                        )
                    )
                }
                // The planner response becomes part of the next turn's context.
                pendingInput = output
            } else {
                pendingInput += estimatedTokens(object["content"])
                    + estimatedTokens(object["tool_calls"])
            }
        }
        return result
    }

    private static func projectName(from toolCalls: Any?) -> String? {
        guard let calls = toolCalls as? [[String: Any]] else { return nil }
        for call in calls {
            guard let args = call["args"] as? [String: Any] else { continue }
            let cwd = (args["Cwd"] as? String) ?? (args["cwd"] as? String)
            guard let cwd, !cwd.isEmpty else { continue }
            let name = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Conservative local approximation used only when the provider supplies no
    /// usage counters. The output is labeled as estimated in ProviderSnapshot.
    private static func estimatedTokens(_ value: Any?) -> Int64 {
        guard let value else { return 0 }
        let bytes: Int
        if let text = value as? String {
            bytes = text.lengthOfBytes(using: .utf8)
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value) {
            bytes = data.count
        } else {
            return 0
        }
        guard bytes > 0 else { return 0 }
        return Int64((bytes + 3) / 4)
    }
}
