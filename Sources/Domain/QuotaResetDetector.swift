import Foundation

public struct QuotaResetEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let providerID: String
    public let providerName: String
    public let windowID: String
    public let windowLabel: String
    public let detectedAt: Date
    public let expiresAt: Date
    public let previousUsedPercent: Double
    public let currentUsedPercent: Double
    public let previousResetAt: Date
    public let currentResetAt: Date

    public init(
        id: String,
        providerID: String,
        providerName: String,
        windowID: String,
        windowLabel: String,
        detectedAt: Date,
        expiresAt: Date,
        previousUsedPercent: Double,
        currentUsedPercent: Double,
        previousResetAt: Date,
        currentResetAt: Date
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.windowID = windowID
        self.windowLabel = windowLabel
        self.detectedAt = detectedAt
        self.expiresAt = expiresAt
        self.previousUsedPercent = previousUsedPercent
        self.currentUsedPercent = currentUsedPercent
        self.previousResetAt = previousResetAt
        self.currentResetAt = currentResetAt
    }
}

public struct QuotaResetDetectionState: Codable, Equatable, Sendable {
    public struct Observation: Codable, Equatable, Sendable {
        public let usedPercent: Double
        public let resetAt: Date

        public init(usedPercent: Double, resetAt: Date) {
            self.usedPercent = usedPercent
            self.resetAt = resetAt
        }
    }

    public var observations: [String: Observation]
    public var lastEventAt: [String: Date]
    public var recentEvents: [QuotaResetEvent]

    public init(
        observations: [String: Observation] = [:],
        lastEventAt: [String: Date] = [:],
        recentEvents: [QuotaResetEvent] = []
    ) {
        self.observations = observations
        self.lastEventAt = lastEventAt
        self.recentEvents = recentEvents
    }
}

public struct QuotaResetDetector: Sendable {
    public var minimumUsageDrop: Double
    public var resetAdvanceTolerance: TimeInterval
    public var cooldown: TimeInterval
    public var eventLifetime: TimeInterval

    public init(
        minimumUsageDrop: Double = 5,
        resetAdvanceTolerance: TimeInterval = 60,
        cooldown: TimeInterval = 60 * 60,
        eventLifetime: TimeInterval = 24 * 60 * 60
    ) {
        self.minimumUsageDrop = minimumUsageDrop
        self.resetAdvanceTolerance = resetAdvanceTolerance
        self.cooldown = cooldown
        self.eventLifetime = eventLifetime
    }

    public func evaluate(
        snapshot: UsageSnapshot,
        state: QuotaResetDetectionState,
        now: Date
    ) -> (events: [QuotaResetEvent], state: QuotaResetDetectionState) {
        var updated = state
        updated.recentEvents.removeAll { $0.expiresAt <= now }
        updated.lastEventAt = updated.lastEventAt.filter {
            now.timeIntervalSince($0.value) < eventLifetime
        }
        var events: [QuotaResetEvent] = []

        for provider in snapshot.providers where provider.availability == .available {
            for window in provider.windows {
                guard let usedPercent = window.usedPercent,
                      let resetAt = window.resetAt else { continue }
                let key = provider.id + "." + window.id
                let previous = state.observations[key]
                updated.observations[key] = .init(
                    usedPercent: usedPercent,
                    resetAt: resetAt
                )

                guard let previous,
                      resetAt.timeIntervalSince(previous.resetAt) > resetAdvanceTolerance,
                      previous.usedPercent - usedPercent >= minimumUsageDrop else { continue }
                if let lastEventAt = state.lastEventAt[key],
                   now.timeIntervalSince(lastEventAt) < cooldown {
                    continue
                }

                let event = QuotaResetEvent(
                    id: key + "." + String(Int64(resetAt.timeIntervalSince1970)),
                    providerID: provider.id,
                    providerName: provider.displayName,
                    windowID: window.id,
                    windowLabel: window.label,
                    detectedAt: now,
                    expiresAt: now.addingTimeInterval(eventLifetime),
                    previousUsedPercent: previous.usedPercent,
                    currentUsedPercent: usedPercent,
                    previousResetAt: previous.resetAt,
                    currentResetAt: resetAt
                )
                updated.lastEventAt[key] = now
                updated.recentEvents.removeAll { $0.id == event.id }
                updated.recentEvents.append(event)
                events.append(event)
            }
        }

        updated.recentEvents.sort { $0.detectedAt < $1.detectedAt }
        return (events, updated)
    }
}
