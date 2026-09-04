import Domain
import Foundation
import Testing

@Suite("Quota reset detection")
struct QuotaResetDetectorTests {
    private let detector = QuotaResetDetector()

    @Test("first observation establishes a baseline without an event")
    func firstObservation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let result = detector.evaluate(
            snapshot: snapshot(usedPercent: 80, resetAt: now.addingTimeInterval(4_000)),
            state: .init(),
            now: now
        )
        #expect(result.events.isEmpty)
        #expect(result.state.observations["codex.primary"]?.usedPercent == 80)
    }

    @Test("reset timestamp advance plus usage drop emits one event")
    func detectsActualReset() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let baseline = detector.evaluate(
            snapshot: snapshot(usedPercent: 80, resetAt: now.addingTimeInterval(4_000)),
            state: .init(),
            now: now
        ).state
        let result = detector.evaluate(
            snapshot: snapshot(usedPercent: 2, resetAt: now.addingTimeInterval(9_000)),
            state: baseline,
            now: now.addingTimeInterval(100)
        )
        let event = try #require(result.events.first)
        #expect(event.providerID == "codex")
        #expect(event.windowID == "primary")
        #expect(event.previousUsedPercent == 80)
        #expect(result.state.recentEvents == [event])
    }

    @Test("usage drop without a new reset window does not emit")
    func rejectsPercentOnlyDrop() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = now.addingTimeInterval(4_000)
        let baseline = detector.evaluate(
            snapshot: snapshot(usedPercent: 80, resetAt: resetAt),
            state: .init(),
            now: now
        ).state
        let result = detector.evaluate(
            snapshot: snapshot(usedPercent: 2, resetAt: resetAt),
            state: baseline,
            now: now.addingTimeInterval(100)
        )
        #expect(result.events.isEmpty)
    }

    @Test("new reset timestamp without a meaningful usage drop does not emit")
    func rejectsSlidingTimestamp() {
        let now = Date(timeIntervalSince1970: 1_000)
        let baseline = detector.evaluate(
            snapshot: snapshot(usedPercent: 80, resetAt: now.addingTimeInterval(4_000)),
            state: .init(),
            now: now
        ).state
        let result = detector.evaluate(
            snapshot: snapshot(usedPercent: 79, resetAt: now.addingTimeInterval(9_000)),
            state: baseline,
            now: now.addingTimeInterval(100)
        )
        #expect(result.events.isEmpty)
    }

    @Test("cooldown suppresses a duplicate reset event")
    func cooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        let baseline = detector.evaluate(
            snapshot: snapshot(usedPercent: 80, resetAt: now.addingTimeInterval(4_000)),
            state: .init(),
            now: now
        ).state
        let first = detector.evaluate(
            snapshot: snapshot(usedPercent: 2, resetAt: now.addingTimeInterval(9_000)),
            state: baseline,
            now: now.addingTimeInterval(100)
        ).state
        let climbed = detector.evaluate(
            snapshot: snapshot(usedPercent: 90, resetAt: now.addingTimeInterval(9_000)),
            state: first,
            now: now.addingTimeInterval(200)
        ).state
        let duplicate = detector.evaluate(
            snapshot: snapshot(usedPercent: 1, resetAt: now.addingTimeInterval(14_000)),
            state: climbed,
            now: now.addingTimeInterval(300)
        )
        #expect(duplicate.events.isEmpty)
    }

    private func snapshot(usedPercent: Double, resetAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "Codex",
                    sourceUpdatedAt: Date(timeIntervalSince1970: 1_000),
                    freshness: .fresh,
                    usage: TokenUsage(totalTokens: 1),
                    windows: [
                        QuotaWindow(
                            id: "primary",
                            label: "5 小时",
                            usedPercent: usedPercent,
                            resetAt: resetAt
                        ),
                    ]
                ),
            ]
        )
    }
}
