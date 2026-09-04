import Foundation

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let providers: [ProviderSnapshot]
    public let analytics: UsageAnalytics?
    public let resetEvents: [QuotaResetEvent]
    public let mode: SnapshotMode

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date,
        providers: [ProviderSnapshot],
        analytics: UsageAnalytics? = nil,
        resetEvents: [QuotaResetEvent] = [],
        mode: SnapshotMode = .live
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
        self.analytics = analytics
        self.resetEvents = resetEvents
        self.mode = mode
    }

    public var totalTokens: Int64 {
        totalTokens(for: .last30Days)
    }

    public var hasKnownUsage: Bool {
        hasKnownUsage(for: .last30Days)
    }

    public func totalTokens(for period: UsagePeriod) -> Int64 {
        providers.reduce(0) {
            let usage = $1.usage(for: period)
            return $0 + (usage.isKnown ? usage.totalTokens : 0)
        }
    }

    public func hasKnownUsage(for period: UsagePeriod) -> Bool {
        providers.contains { $0.usage(for: period).isKnown }
    }

    public func hasEstimatedUsage(for period: UsagePeriod) -> Bool {
        providers.contains { provider in
            let usage = provider.usage(for: period)
            return provider.isEstimated && usage.isKnown && usage.totalTokens > 0
        }
    }

    public var primaryProvider: ProviderSnapshot? {
        let candidates = providers.filter {
            $0.availability != .notConfigured && $0.availability != .unsupported
        }
        for period in [UsagePeriod.today, .last7Days, .last30Days] {
            if let provider = candidates
                .filter({ $0.usage(for: period).isKnown && $0.usage(for: period).totalTokens > 0 })
                .max(by: {
                    $0.usage(for: period).totalTokens < $1.usage(for: period).totalTokens
                }) {
                return provider
            }
        }
        return candidates.first { !$0.windows.isEmpty }
    }

    /// Compares the user-visible payload while ignoring collection-clock churn.
    /// `generatedAt` and period `endsAt` advance on every refresh even when no
    /// provider data changed, so they must not trigger disk/network work by themselves.
    public func hasSameContent(as other: Self) -> Bool {
        guard schemaVersion == other.schemaVersion,
              analytics == other.analytics,
              resetEvents == other.resetEvents,
              mode == other.mode,
              providers.count == other.providers.count else {
            return false
        }
        let lhs = providers.sorted { $0.id < $1.id }
        let rhs = other.providers.sorted { $0.id < $1.id }
        return zip(lhs, rhs).allSatisfy { $0.hasSameContent(as: $1) }
    }

    public func refreshed(at now: Date) -> Self {
        Self(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            providers: providers.map { $0.refreshed(at: now) },
            analytics: analytics,
            resetEvents: resetEvents,
            mode: mode
        )
    }

    /// Combines snapshots that may arrive out of order on an at-least-once transport.
    /// Provider and analytics state come from the newest snapshot, while still-valid
    /// reset events are unioned so an older queued snapshot cannot erase an alert.
    public func mergingOutOfOrderUpdate(_ incoming: Self, now: Date) -> Self {
        let newest = incoming.generatedAt >= generatedAt ? incoming : self
        var eventsByID: [String: QuotaResetEvent] = [:]
        for event in resetEvents + incoming.resetEvents where event.expiresAt > now {
            if let existing = eventsByID[event.id], existing.detectedAt >= event.detectedAt {
                continue
            }
            eventsByID[event.id] = event
        }
        return Self(
            schemaVersion: newest.schemaVersion,
            generatedAt: newest.generatedAt,
            providers: newest.providers,
            analytics: newest.analytics,
            resetEvents: eventsByID.values.sorted {
                if $0.detectedAt == $1.detectedAt { return $0.id < $1.id }
                return $0.detectedAt < $1.detectedAt
            },
            mode: newest.mode
        )
    }

    /// Replaces provider quota data with a newer iPhone-direct result while keeping
    /// Mac-observed token periods and analytics. Quota and token values are never added.
    public func mergingDirectProviders(
        _ directProviders: [ProviderSnapshot],
        generatedAt directGeneratedAt: Date
    ) -> Self {
        guard !directProviders.isEmpty else { return self }
        var merged = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })

        for direct in directProviders {
            if let observed = merged[direct.id] {
                merged[direct.id] = ProviderSnapshot(
                    id: direct.id,
                    displayName: direct.displayName,
                    sourceUpdatedAt: direct.sourceUpdatedAt,
                    freshness: direct.freshness,
                    usage: observed.usage,
                    periods: observed.periods,
                    windows: direct.windows,
                    availability: direct.availability,
                    detail: direct.detail,
                    sourceKind: direct.sourceKind,
                    planName: direct.planName,
                    isEstimated: observed.isEstimated
                )
            } else {
                merged[direct.id] = direct
            }
        }

        return Self(
            schemaVersion: schemaVersion,
            generatedAt: max(generatedAt, directGeneratedAt),
            providers: merged.values.sorted { $0.id < $1.id },
            analytics: analytics,
            resetEvents: resetEvents,
            mode: .live
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case providers
        case analytics
        case resetEvents
        case mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            providers: try container.decode([ProviderSnapshot].self, forKey: .providers),
            analytics: try container.decodeIfPresent(UsageAnalytics.self, forKey: .analytics),
            resetEvents: try container.decodeIfPresent(
                [QuotaResetEvent].self,
                forKey: .resetEvents
            ) ?? [],
            mode: try container.decodeIfPresent(SnapshotMode.self, forKey: .mode) ?? .live
        )
    }
}

public enum SnapshotMode: String, Codable, Equatable, Sendable {
    case live
    case demo
}

public struct UsageAnalytics: Codable, Equatable, Sendable {
    public let daily: [DailyTokenUsage]
    public let models: [ModelTokenUsage]
    public let projects: [ProjectTokenUsage]

    public init(
        daily: [DailyTokenUsage],
        models: [ModelTokenUsage],
        projects: [ProjectTokenUsage] = []
    ) {
        self.daily = daily.sorted { $0.day < $1.day }
        self.models = models
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
        self.projects = projects
            .filter { $0.periods.recordedAllTime.usage.totalTokens > 0 }
            .sorted {
                $0.periods.recordedAllTime.usage.totalTokens
                    > $1.periods.recordedAllTime.usage.totalTokens
            }
    }

    public var activeDays: Int {
        daily.count { $0.totalTokens > 0 }
    }

    public func trend(
        groupedBy granularity: UsageTrendGranularity,
        calendar: Calendar = .current
    ) -> [TokenTrendPoint] {
        daily.groupedTrend(by: granularity, calendar: calendar)
    }

    private enum CodingKeys: String, CodingKey {
        case daily
        case models
        case projects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            daily: try container.decode([DailyTokenUsage].self, forKey: .daily),
            models: try container.decode([ModelTokenUsage].self, forKey: .models),
            projects: try container.decodeIfPresent(
                [ProjectTokenUsage].self,
                forKey: .projects
            ) ?? []
        )
    }
}

public struct DailyTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day }
    public let day: String
    public let totalTokens: Int64

    public init(day: String, totalTokens: Int64) {
        self.day = day
        self.totalTokens = max(0, totalTokens)
    }
}

public struct ModelTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let totalTokens: Int64

    public init(model: String, totalTokens: Int64) {
        self.model = model
        self.totalTokens = max(0, totalTokens)
    }
}

public struct ProjectTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let periods: UsagePeriods
    public let daily: [DailyTokenUsage]
    public let models: [ModelTokenUsage]

    public init(
        id: String,
        displayName: String,
        periods: UsagePeriods,
        daily: [DailyTokenUsage],
        models: [ModelTokenUsage]
    ) {
        self.id = id
        self.displayName = displayName
        self.periods = periods
        self.daily = daily.sorted { $0.day < $1.day }
        self.models = models
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    public func usage(for period: UsagePeriod) -> TokenUsage {
        periods.value(for: period).usage
    }

    public func trend(
        groupedBy granularity: UsageTrendGranularity,
        calendar: Calendar = .current
    ) -> [TokenTrendPoint] {
        daily.groupedTrend(by: granularity, calendar: calendar)
    }
}

public enum UsageTrendGranularity: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month
}

public struct TokenTrendPoint: Equatable, Identifiable, Sendable {
    public var id: String { periodStart }
    public let periodStart: String
    public let totalTokens: Int64

    public init(periodStart: String, totalTokens: Int64) {
        self.periodStart = periodStart
        self.totalTokens = max(0, totalTokens)
    }
}

private extension Collection where Element == DailyTokenUsage {
    func groupedTrend(
        by granularity: UsageTrendGranularity,
        calendar: Calendar
    ) -> [TokenTrendPoint] {
        var totals: [String: Int64] = [:]
        for value in self {
            let parts = value.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(
                      calendar: calendar,
                      timeZone: calendar.timeZone,
                      year: parts[0],
                      month: parts[1],
                      day: parts[2]
                  )) else { continue }
            let start: Date
            switch granularity {
            case .day:
                start = calendar.startOfDay(for: date)
            case .week:
                start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
                    ?? calendar.startOfDay(for: date)
            case .month:
                start = calendar.dateInterval(of: .month, for: date)?.start
                    ?? calendar.startOfDay(for: date)
            }
            let components = calendar.dateComponents([.year, .month, .day], from: start)
            let key = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
            totals[key, default: 0] += value.totalTokens
        }
        return totals.map { TokenTrendPoint(periodStart: $0.key, totalTokens: $0.value) }
            .sorted { $0.periodStart < $1.periodStart }
    }
}

public struct ProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let sourceUpdatedAt: Date
    public let freshness: Freshness
    public let periods: UsagePeriods
    public let windows: [QuotaWindow]
    public let availability: ProviderAvailability
    public let detail: String?
    public let sourceKind: ProviderSourceKind
    public let planName: String?
    public let isEstimated: Bool

    public init(
        id: String,
        displayName: String,
        sourceUpdatedAt: Date,
        freshness: Freshness,
        usage: TokenUsage,
        periods: UsagePeriods? = nil,
        windows: [QuotaWindow] = [],
        availability: ProviderAvailability = .available,
        detail: String? = nil,
        sourceKind: ProviderSourceKind = .macObserved,
        planName: String? = nil,
        isEstimated: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceUpdatedAt = sourceUpdatedAt
        self.freshness = freshness
        self.periods = periods ?? .legacy(last30Days: usage, generatedAt: sourceUpdatedAt)
        self.windows = windows
        self.availability = availability
        self.detail = detail
        self.sourceKind = sourceKind
        self.planName = planName
        self.isEstimated = isEstimated
    }

    public var usage: TokenUsage {
        periods.last30Days.usage
    }

    public func usage(for period: UsagePeriod) -> TokenUsage {
        periods.value(for: period).usage
    }

    public func hasSameContent(as other: Self) -> Bool {
        id == other.id
            && displayName == other.displayName
            && sourceUpdatedAt == other.sourceUpdatedAt
            && freshness == other.freshness
            && periods.hasSameContent(as: other.periods)
            && windows == other.windows
            && availability == other.availability
            && detail == other.detail
            && sourceKind == other.sourceKind
            && planName == other.planName
            && isEstimated == other.isEstimated
    }

    public func refreshed(at now: Date) -> Self {
        let computedFreshness = Freshness.classify(sourceUpdatedAt: sourceUpdatedAt, now: now)
        return Self(
            id: id,
            displayName: displayName,
            sourceUpdatedAt: sourceUpdatedAt,
            freshness: availability == .available ? computedFreshness : .offline,
            usage: usage,
            periods: periods,
            windows: windows,
            availability: availability,
            detail: detail,
            sourceKind: sourceKind,
            planName: planName,
            isEstimated: isEstimated
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case sourceUpdatedAt
        case freshness
        case usage
        case periods
        case windows
        case availability
        case detail
        case sourceKind
        case planName
        case isEstimated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceUpdatedAt = try container.decode(Date.self, forKey: .sourceUpdatedAt)
        let legacyUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .usage)
            ?? .unknown
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            sourceUpdatedAt: sourceUpdatedAt,
            freshness: try container.decode(Freshness.self, forKey: .freshness),
            usage: legacyUsage,
            periods: try container.decodeIfPresent(UsagePeriods.self, forKey: .periods),
            windows: try container.decodeIfPresent([QuotaWindow].self, forKey: .windows) ?? [],
            availability: try container.decodeIfPresent(
                ProviderAvailability.self,
                forKey: .availability
            ) ?? .available,
            detail: try container.decodeIfPresent(String.self, forKey: .detail),
            sourceKind: try container.decodeIfPresent(
                ProviderSourceKind.self,
                forKey: .sourceKind
            ) ?? .macObserved,
            planName: try container.decodeIfPresent(String.self, forKey: .planName),
            isEstimated: try container.decodeIfPresent(Bool.self, forKey: .isEstimated) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(sourceUpdatedAt, forKey: .sourceUpdatedAt)
        try container.encode(freshness, forKey: .freshness)
        try container.encode(usage, forKey: .usage)
        try container.encode(periods, forKey: .periods)
        try container.encode(windows, forKey: .windows)
        try container.encode(availability, forKey: .availability)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encodeIfPresent(planName, forKey: .planName)
        if isEstimated {
            try container.encode(true, forKey: .isEstimated)
        }
    }
}

public enum ProviderSourceKind: String, Codable, CaseIterable, Equatable, Sendable {
    case macObserved
    case iphoneDirect
    case officialAdminAPI
    case demo
}

public enum UsagePeriod: String, Codable, CaseIterable, Equatable, Sendable {
    case today
    case last7Days
    case last30Days
    case recordedAllTime
}

public struct PeriodTokenUsage: Codable, Equatable, Sendable {
    public let usage: TokenUsage
    public let startsAt: Date
    public let endsAt: Date

    public init(usage: TokenUsage, startsAt: Date, endsAt: Date) {
        self.usage = usage
        self.startsAt = startsAt
        self.endsAt = max(startsAt, endsAt)
    }

    public func hasSameContent(as other: Self) -> Bool {
        usage == other.usage && startsAt == other.startsAt
    }
}

public struct UsagePeriods: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let today: PeriodTokenUsage
    public let last7Days: PeriodTokenUsage
    public let last30Days: PeriodTokenUsage
    public let recordedAllTime: PeriodTokenUsage

    public init(
        timeZoneIdentifier: String,
        today: PeriodTokenUsage,
        last7Days: PeriodTokenUsage,
        last30Days: PeriodTokenUsage,
        recordedAllTime: PeriodTokenUsage
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.today = today
        self.last7Days = last7Days
        self.last30Days = last30Days
        self.recordedAllTime = recordedAllTime
    }

    public func hasSameContent(as other: Self) -> Bool {
        timeZoneIdentifier == other.timeZoneIdentifier
            && today.hasSameContent(as: other.today)
            && last7Days.hasSameContent(as: other.last7Days)
            && last30Days.hasSameContent(as: other.last30Days)
            && recordedAllTime.hasSameContent(as: other.recordedAllTime)
    }

    public func value(for period: UsagePeriod) -> PeriodTokenUsage {
        switch period {
        case .today: today
        case .last7Days: last7Days
        case .last30Days: last30Days
        case .recordedAllTime: recordedAllTime
        }
    }

    public static func legacy(last30Days: TokenUsage, generatedAt: Date) -> Self {
        let unknown = PeriodTokenUsage(
            usage: .unknown,
            startsAt: generatedAt,
            endsAt: generatedAt
        )
        return Self(
            timeZoneIdentifier: "UTC",
            today: unknown,
            last7Days: unknown,
            last30Days: PeriodTokenUsage(
                usage: last30Days,
                startsAt: generatedAt,
                endsAt: generatedAt
            ),
            recordedAllTime: unknown
        )
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public let measurement: TokenUsageMeasurement
    public let isKnown: Bool
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cachedInputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public init(
        measurement: TokenUsageMeasurement = .aggregate,
        isKnown: Bool = true,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64
    ) {
        self.measurement = measurement
        self.isKnown = isKnown
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.totalTokens = max(0, totalTokens)
    }

    public static let unknown = Self(isKnown: false, totalTokens: 0)

    private enum CodingKeys: String, CodingKey {
        case isKnown
        case measurement
        case inputTokens
        case outputTokens
        case cachedInputTokens
        case reasoningOutputTokens
        case totalTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            measurement: try container.decodeIfPresent(
                TokenUsageMeasurement.self,
                forKey: .measurement
            ) ?? .aggregate,
            isKnown: try container.decodeIfPresent(Bool.self, forKey: .isKnown) ?? true,
            inputTokens: try container.decode(Int64.self, forKey: .inputTokens),
            outputTokens: try container.decode(Int64.self, forKey: .outputTokens),
            cachedInputTokens: try container.decode(Int64.self, forKey: .cachedInputTokens),
            reasoningOutputTokens: try container.decode(Int64.self, forKey: .reasoningOutputTokens),
            totalTokens: try container.decode(Int64.self, forKey: .totalTokens)
        )
    }
}

public enum TokenUsageMeasurement: String, Codable, Equatable, Sendable {
    case aggregate
    case cumulative
    case incremental
    case contextSnapshot
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double?
    public let resetAt: Date?

    public init(id: String, label: String, usedPercent: Double?, resetAt: Date?) {
        self.id = id
        self.label = label
        if let usedPercent, usedPercent.isFinite {
            self.usedPercent = min(100, max(0, usedPercent))
        } else {
            self.usedPercent = nil
        }
        self.resetAt = resetAt
    }

    public var remainingPercent: Double? {
        usedPercent.map { 100 - $0 }
    }
}

public enum ProviderAvailability: String, Codable, Equatable, Sendable {
    case available
    case notConfigured
    case authenticationRequired
    case temporarilyUnavailable
    case unsupported
}

public enum Freshness: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case offline

    public static func classify(
        sourceUpdatedAt: Date,
        now: Date,
        freshTTL: TimeInterval = 5 * 60,
        staleTTL: TimeInterval = 60 * 60
    ) -> Self {
        let age = max(0, now.timeIntervalSince(sourceUpdatedAt))
        if age <= freshTTL { return .fresh }
        if age <= staleTTL { return .stale }
        return .offline
    }
}
