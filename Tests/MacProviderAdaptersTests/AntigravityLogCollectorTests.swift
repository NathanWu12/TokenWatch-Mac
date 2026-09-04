import Domain
import Foundation
import MacProviderAdapters
import Testing

@Suite("Antigravity log collector")
struct AntigravityLogCollectorTests {
    @Test("estimates transcript usage without persisting transcript text")
    func estimatesTranscript() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-antigravity-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root
            .appending(path: "brain/conversation-a/.system_generated/logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let transcript = logs.appending(path: "transcript_full.jsonl")
        let records = [
            #"{"type":"USER_INPUT","created_at":"2026-09-03T10:00:00Z","content":"abcdefgh"}"#,
            #"{"type":"PLANNER_RESPONSE","created_at":"2026-09-03T10:00:01Z","content":"abcd","thinking":"efgh"}"#,
            #"{"type":"VIEW_FILE","created_at":"2026-09-03T10:00:02Z","content":"abcdefgh"}"#,
            #"{"type":"PLANNER_RESPONSE","created_at":"2026-09-03T10:00:03Z","content":"abcdefgh"}"#,
        ]
        try records.joined(separator: "\n").write(
            to: transcript,
            atomically: true,
            encoding: .utf8
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let snapshot = try await AntigravityLogCollector(calendar: calendar)
            .fetchSnapshot(antigravityDirectories: [root], now: now)
        let provider = try #require(snapshot.providers.first)

        // 1st turn: input 2 + output 1 + reasoning 1 = 4
        // 2nd turn: prior planner output 1 + new context 2 + output 2 = 5
        #expect(provider.periods.today.usage.inputTokens == 5)
        #expect(provider.periods.today.usage.outputTokens == 3)
        #expect(provider.periods.today.usage.reasoningOutputTokens == 1)
        #expect(provider.periods.today.usage.totalTokens == 9)
        #expect(provider.detail?.contains("Estimated") == true)
        #expect(provider.isEstimated == true)
        #expect(snapshot.hasEstimatedUsage(for: .today) == true)
    }
    @Test("manifest fast path invalidates after transcript append")
    func manifestInvalidatesAfterAppend() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tokenwatch-antigravity-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root
            .appending(path: "brain/conversation-a/.system_generated/logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let transcript = logs.appending(path: "transcript_full.jsonl")
        let firstRecords = [
            #"{"type":"USER_INPUT","created_at":"2026-09-03T10:00:00Z","content":"abcdefgh"}"#,
            #"{"type":"PLANNER_RESPONSE","created_at":"2026-09-03T10:00:01Z","content":"abcd","thinking":"efgh"}"#,
        ].joined(separator: "\n") + "\n"
        try firstRecords.write(to: transcript, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
        let collector = AntigravityLogCollector(calendar: calendar)
        let first = try await collector.fetchSnapshot(antigravityDirectories: [root], now: now)
        #expect(first.providers.first?.periods.today.usage.totalTokens == 4)

        let appended = [
            #"{"type":"VIEW_FILE","created_at":"2026-09-03T10:00:02Z","content":"abcdefgh"}"#,
            #"{"type":"PLANNER_RESPONSE","created_at":"2026-09-03T10:00:03Z","content":"abcdefgh"}"#,
        ].joined(separator: "\n") + "\n"
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let second = try await collector.fetchSnapshot(antigravityDirectories: [root], now: now)
        #expect(second.providers.first?.periods.today.usage.totalTokens == 9)
        let third = try await collector.fetchSnapshot(
            antigravityDirectories: [root],
            now: now.addingTimeInterval(60)
        )
        #expect(third.providers.first?.periods.today.usage.totalTokens == 9)
    }

}
