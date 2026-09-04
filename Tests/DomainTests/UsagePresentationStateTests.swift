import Foundation
import Testing
@testable import Domain

@Suite("Usage presentation state")
struct UsagePresentationStateTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("recency boundaries remain stable")
    func recencyBoundaries() {
        #expect(DataUpdateRecency(
            sourceUpdatedAt: now.addingTimeInterval(60),
            now: now
        ) == .current)
        #expect(DataUpdateRecency(
            sourceUpdatedAt: now.addingTimeInterval(-5 * 60),
            now: now
        ) == .current)
        #expect(DataUpdateRecency(
            sourceUpdatedAt: now.addingTimeInterval(-(5 * 60 + 1)),
            now: now
        ) == .updated(minutesAgo: 5))
        #expect(DataUpdateRecency(
            sourceUpdatedAt: now.addingTimeInterval(-30 * 60),
            now: now
        ) == .updated(minutesAgo: 30))
        #expect(DataUpdateRecency(
            sourceUpdatedAt: now.addingTimeInterval(-(30 * 60 + 1)),
            now: now
        ) == .lastUpdated(minutesAgo: 30))
    }

    @Test("quota levels match the shared color thresholds")
    func quotaLevels() {
        #expect(RemainingQuotaLevel(remainingPercent: nil) == .unknown)
        #expect(RemainingQuotaLevel(remainingPercent: .nan) == .unknown)
        #expect(RemainingQuotaLevel(remainingPercent: 19.9) == .low)
        #expect(RemainingQuotaLevel(remainingPercent: 20) == .reduced)
        #expect(RemainingQuotaLevel(remainingPercent: 49.9) == .reduced)
        #expect(RemainingQuotaLevel(remainingPercent: 50) == .healthy)
    }
}
