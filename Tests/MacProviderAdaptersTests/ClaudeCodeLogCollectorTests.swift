import Domain
import Foundation
import MacProviderAdapters
import Testing

@Suite("Claude Code log collector")
struct ClaudeCodeLogCollectorTests {
    @Test("aggregates usage and deduplicates repeated assistant message records")
    func aggregatesUsage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-claude-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "projects/-Users-test-Alpha", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appending(path: "session-a.jsonl")
        let lines = [
            assistantLine(
                timestamp: "2026-09-03T10:00:00.000Z",
                session: "session-a",
                message: "msg-1",
                model: "claude-sonnet-test",
                cwd: "/Users/test/Alpha",
                input: 10,
                output: 5,
                cacheCreate: 2,
                cacheRead: 3
            ),
            assistantLine(
                timestamp: "2026-09-03T10:00:01.000Z",
                session: "session-a",
                message: "msg-1",
                model: "claude-sonnet-test",
                cwd: "/Users/test/Alpha",
                input: 12,
                output: 6,
                cacheCreate: 2,
                cacheRead: 4
            ),
            assistantLine(
                timestamp: "2026-09-03T10:05:00.000Z",
                session: "session-a",
                message: "msg-2",
                model: "claude-opus-test",
                cwd: "/Users/test/Alpha",
                input: 7,
                output: 8,
                cacheCreate: 1,
                cacheRead: 0
            ),
            #"{"type":"user","timestamp":"2026-09-03T10:06:00Z","message":{"content":"ignored"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let snapshot = try await ClaudeCodeLogCollector(calendar: calendar)
            .fetchSnapshot(claudeDirectory: root, now: now)

        let provider = try #require(snapshot.providers.first)
        #expect(provider.id == "claude-code")
        #expect(provider.periods.today.usage.inputTokens == 19)
        #expect(provider.periods.today.usage.outputTokens == 14)
        #expect(provider.periods.today.usage.cachedInputTokens == 7)
        #expect(provider.periods.today.usage.totalTokens == 40)
        let analytics = try #require(snapshot.analytics)
        #expect(analytics.projects.first?.displayName == "Alpha")
        #expect(Set(analytics.models.map(\.model)) == ["claude-sonnet-test", "claude-opus-test"])
    }

    @Test("manifest fast path invalidates after session append")
    func manifestInvalidatesAfterAppend() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-claude-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "projects/-Users-test-Cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appending(path: "session-cache.jsonl")
        let firstLine = assistantLine(
            timestamp: "2026-09-03T10:00:00.000Z",
            session: "session-cache",
            message: "msg-1",
            model: "claude-cache",
            cwd: "/Users/test/CacheProject",
            input: 10,
            output: 5,
            cacheCreate: 0,
            cacheRead: 0
        ) + "\n"
        try firstLine.write(to: session, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let collector = ClaudeCodeLogCollector(calendar: calendar)
        let first = try await collector.fetchSnapshot(claudeDirectory: root, now: now)
        #expect(first.providers.first?.periods.today.usage.totalTokens == 15)

        let secondLine = assistantLine(
            timestamp: "2026-09-03T10:01:00.000Z",
            session: "session-cache",
            message: "msg-2",
            model: "claude-cache",
            cwd: "/Users/test/CacheProject",
            input: 20,
            output: 5,
            cacheCreate: 0,
            cacheRead: 0
        ) + "\n"
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(secondLine.utf8))
        try handle.close()

        let second = try await collector.fetchSnapshot(claudeDirectory: root, now: now)
        #expect(second.providers.first?.periods.today.usage.totalTokens == 40)
        let later = now.addingTimeInterval(60)
        let third = try await collector.fetchSnapshot(claudeDirectory: root, now: later)
        #expect(third.providers.first?.periods.today.usage.totalTokens == 40)
        #expect(third.generatedAt == later)
        #expect(third.providers.first?.periods.today.endsAt == later)
    }

    private func assistantLine(
        timestamp: String,
        session: String,
        message: String,
        model: String,
        cwd: String,
        input: Int,
        output: Int,
        cacheCreate: Int,
        cacheRead: Int
    ) -> String {
        #"{"type":"assistant","timestamp":"\#(timestamp)","sessionId":"\#(session)","cwd":"\#(cwd)","message":{"id":"\#(message)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead)}}}"#
    }
}
