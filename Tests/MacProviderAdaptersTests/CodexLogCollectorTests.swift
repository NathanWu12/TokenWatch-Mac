@testable import MacProviderAdapters
import Domain
import Foundation
import Testing

struct CodexLogCollectorTests {
    @Test
    func collectsOnlyTokenCountersAcrossPeriodsAndModels() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let secret = "PROMPT-MUST-NOT-LEAK"
        let rows = [
            #"{"timestamp":"2026-07-20T01:00:00Z","type":"turn_context","payload":{"model":"gpt-test","cwd":"/Users/test/SampleProject"}}"#,
            #"{"timestamp":"2026-07-20T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"\#(secret)"}}"#,
            tokenRow(timestamp: "2026-07-20T01:00:02Z", input: 100, cached: 40, output: 20, reasoning: 5, total: 120),
            tokenRow(timestamp: "2026-07-20T01:01:00Z", input: 140, cached: 50, output: 30, reasoning: 7, total: 170),
            #"{"timestamp":"2026-07-21T01:00:00Z","type":"turn_context","payload":{"model":"gpt-next","cwd":"/Users/test/ERP_Zuxus"}}"#,
            tokenRow(timestamp: "2026-07-21T01:00:01Z", input: 200, cached: 70, output: 50, reasoning: 10, total: 250),
        ]
        try rows.joined(separator: "\n").write(
            to: root.appending(path: "rollout-2026-07-20-00000000-0000-4000-8000-000000000001.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        let snapshot = try await CodexLogCollector(calendar: calendar).fetchSnapshot(
            codexDirectory: root,
            now: now
        )

        let provider = try #require(snapshot.providers.first)
        #expect(provider.id == "codex")
        #expect(provider.usage(for: .today).totalTokens == 80)
        #expect(provider.usage(for: .last7Days).totalTokens == 250)
        #expect(provider.usage(for: .recordedAllTime).inputTokens == 200)
        #expect(provider.usage(for: .recordedAllTime).cachedInputTokens == 70)
        #expect(snapshot.analytics?.models.map(\.model) == ["gpt-test", "gpt-next"])
        #expect(snapshot.analytics?.projects.map(\.displayName) == ["SampleProject", "ERP_Zuxus"])
        #expect(snapshot.analytics?.projects.first?.usage(for: .recordedAllTime).totalTokens == 170)
        #expect(snapshot.analytics?.projects.last?.usage(for: .today).totalTokens == 80)
        #expect(String(describing: snapshot).contains("/Users/test") == false)
        #expect(String(describing: snapshot).contains(secret) == false)
    }

    @Test
    func nestedTokenMessageAndCounterResetRemainIncremental() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rows = [
            nestedTokenRow(timestamp: "2026-07-21T01:00:00Z", input: 100, output: 20, total: 120),
            nestedTokenRow(timestamp: "2026-07-21T01:01:00Z", input: 20, output: 5, total: 25),
        ]
        try rows.joined(separator: "\n").write(
            to: root.appending(path: "session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        let snapshot = try await CodexLogCollector().fetchSnapshot(codexDirectory: root, now: now)
        #expect(snapshot.providers.first?.usage(for: .recordedAllTime).totalTokens == 145)
    }

    @Test
    func skipsForkReplayPrefixButCountsLaterLiveUsage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rows = [
            #"{"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"forked_from_id":"parent"}}"#,
            nestedTokenRow(timestamp: "2026-07-21T01:00:00.100Z", input: 100, output: 20, total: 120),
            nestedTokenRow(timestamp: "2026-07-21T01:00:00.200Z", input: 150, output: 30, total: 180),
            nestedTokenRow(timestamp: "2026-07-21T01:00:05.000Z", input: 175, output: 35, total: 210),
        ]
        try rows.joined(separator: "\n").write(
            to: root.appending(path: "forked.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        let snapshot = try await CodexLogCollector().fetchSnapshot(codexDirectory: root, now: now)
        #expect(snapshot.providers.first?.usage(for: .recordedAllTime).totalTokens == 30)
    }

    @Test
    func persistentIndexConsumesOnlyAppendedCounters() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let root = base.appending(path: "codex", directoryHint: .isDirectory)
        let cache = base.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let file = root.appending(path: "rollout-2026-07-20-00000000-0000-4000-8000-000000000001.jsonl")
        let initial = [
            #"{"timestamp":"2026-07-20T01:00:00Z","type":"turn_context","payload":{"model":"gpt-test","cwd":"/Users/test/SampleProject"}}"#,
            tokenRow(timestamp: "2026-07-20T01:00:01Z", input: 100, cached: 40, output: 20, reasoning: 5, total: 120),
        ].joined(separator: "\n") + "\n"
        try initial.write(to: file, atomically: true, encoding: .utf8)

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z"))
        let collector = CodexLogCollector()
        let first = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(first.providers.first?.usage(for: .recordedAllTime).totalTokens == 120)

        let append = tokenRow(
            timestamp: "2026-07-20T01:01:00Z",
            input: 140,
            cached: 50,
            output: 30,
            reasoning: 7,
            total: 170
        ) + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(append.utf8))
        try handle.close()

        let second = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(second.providers.first?.usage(for: .recordedAllTime).totalTokens == 170)

        let third = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(third.providers.first?.usage(for: .recordedAllTime).totalTokens == 170)
    }

    @Test
    func persistentIndexReplaysOnlyAnIncompleteFinalLine() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let root = base.appending(path: "codex", directoryHint: .isDirectory)
        let cache = base.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let file = root.appending(path: "rollout-2026-07-20-00000000-0000-4000-8000-000000000002.jsonl")
        let firstRow = tokenRow(
            timestamp: "2026-07-20T01:00:01Z",
            input: 100,
            cached: 40,
            output: 20,
            reasoning: 5,
            total: 120
        )
        let nextRow = tokenRow(
            timestamp: "2026-07-20T01:01:00Z",
            input: 140,
            cached: 50,
            output: 30,
            reasoning: 7,
            total: 170
        )
        let split = nextRow.index(nextRow.startIndex, offsetBy: nextRow.count / 2)
        try (firstRow + "\n" + nextRow[..<split]).write(
            to: file,
            atomically: true,
            encoding: .utf8
        )

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z"))
        let collector = CodexLogCollector()
        let first = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(first.providers.first?.usage(for: .recordedAllTime).totalTokens == 120)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(nextRow[split...]) + "\n").utf8))
        try handle.close()

        let second = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(second.providers.first?.usage(for: .recordedAllTime).totalTokens == 170)
        let third = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(third.providers.first?.usage(for: .recordedAllTime).totalTokens == 170)
    }

    @Test
    func persistentIndexRebuildsATruncatedRollout() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let root = base.appending(path: "codex", directoryHint: .isDirectory)
        let cache = base.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let file = root.appending(path: "rollout-2026-07-20-00000000-0000-4000-8000-000000000003.jsonl")
        let initial = [
            tokenRow(timestamp: "2026-07-20T01:00:01Z", input: 100, cached: 0, output: 20, reasoning: 0, total: 120),
            tokenRow(timestamp: "2026-07-20T01:01:00Z", input: 130, cached: 0, output: 30, reasoning: 0, total: 160),
        ].joined(separator: "\n") + "\n"
        try initial.write(to: file, atomically: true, encoding: .utf8)

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z"))
        let collector = CodexLogCollector()
        let first = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(first.providers.first?.usage(for: .recordedAllTime).totalTokens == 160)

        let replacement = tokenRow(
            timestamp: "2026-07-20T02:00:00Z",
            input: 30,
            cached: 0,
            output: 10,
            reasoning: 0,
            total: 40
        ) + "\n"
        try replacement.write(to: file, atomically: true, encoding: .utf8)

        let second = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(second.providers.first?.usage(for: .recordedAllTime).totalTokens == 40)
    }

    @Test
    func persistentIndexRebuildsSameSizeModifiedRollout() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let root = base.appending(path: "codex", directoryHint: .isDirectory)
        let cache = base.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let file = root.appending(path: "rollout-2026-07-20-00000000-0000-4000-8000-000000000004.jsonl")
        let stablePrefix = #"{"timestamp":"2026-07-20T00:00:00Z","type":"event_msg","payload":{"type":"user_message","message":""#
            + String(repeating: "x", count: 5_000)
            + #""}}"#
        let firstToken = tokenRow(
            timestamp: "2026-07-20T01:00:01Z",
            input: 100,
            cached: 0,
            output: 20,
            reasoning: 0,
            total: 120
        )
        let replacementToken = tokenRow(
            timestamp: "2026-07-20T01:00:01Z",
            input: 120,
            cached: 0,
            output: 20,
            reasoning: 0,
            total: 140
        )
        #expect(firstToken.utf8.count == replacementToken.utf8.count)
        try (stablePrefix + "\n" + firstToken + "\n").write(
            to: file,
            atomically: true,
            encoding: .utf8
        )

        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z"))
        let collector = CodexLogCollector()
        let first = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(first.providers.first?.usage(for: .recordedAllTime).totalTokens == 120)
        let originalSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize

        try (stablePrefix + "\n" + replacementToken + "\n").write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(5)],
            ofItemAtPath: file.path
        )
        #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == originalSize)

        let second = try await collector.fetchSnapshot(
            codexDirectory: root,
            now: now,
            cacheDirectory: cache
        )
        #expect(second.providers.first?.usage(for: .recordedAllTime).totalTokens == 140)
    }

    private func tokenRow(
        timestamp: String,
        input: Int,
        cached: Int,
        output: Int,
        reasoning: Int,
        total: Int
    ) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(total)}}}}"#
    }

    private func nestedTokenRow(
        timestamp: String,
        input: Int,
        output: Int,
        total: Int
    ) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"msg":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(total)}}}}}"#
    }
}
