import Foundation

public enum DataUpdateRecency: Equatable, Sendable {
    case current
    case updated(minutesAgo: Int)
    case lastUpdated(minutesAgo: Int)

    public init(
        sourceUpdatedAt: Date,
        now: Date,
        currentInterval: TimeInterval = 5 * 60,
        recentInterval: TimeInterval = 30 * 60
    ) {
        let age = max(0, now.timeIntervalSince(sourceUpdatedAt))
        if age <= currentInterval {
            self = .current
            return
        }
        let minutes = max(1, Int(age / 60))
        self = age <= recentInterval
            ? .updated(minutesAgo: minutes)
            : .lastUpdated(minutesAgo: minutes)
    }
}

public enum RemainingQuotaLevel: Equatable, Sendable {
    case unknown
    case low
    case reduced
    case healthy

    public init(remainingPercent: Double?) {
        guard let remainingPercent, remainingPercent.isFinite else {
            self = .unknown
            return
        }
        if remainingPercent < 20 {
            self = .low
        } else if remainingPercent < 50 {
            self = .reduced
        } else {
            self = .healthy
        }
    }
}
