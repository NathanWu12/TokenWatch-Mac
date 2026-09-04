import Domain
import Foundation

struct LocalUsageSample: Equatable, Sendable {
    let timestamp: Date
    let model: String
    let projectName: String
    let usage: TokenUsage
}

enum LocalUsageSnapshotBuilder {
    static func makeSnapshot(
        providerID: String,
        displayName: String,
        samples: [LocalUsageSample],
        now: Date,
        calendar: Calendar,
        detail: String? = nil,
        isEstimated: Bool = false
    ) -> UsageSnapshot {
        let today = calendar.startOfDay(for: now)
        let last7Days = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let last30Days = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let allTimeStart = Date(timeIntervalSince1970: 0)

        var sourceUpdatedAt: Date?
        var provider = PeriodAccumulator()
        var daily: [String: Int64] = [:]
        var models: [String: Int64] = [:]
        var projects: [String: ProjectAccumulator] = [:]

        for sample in samples {
            sourceUpdatedAt = max(sourceUpdatedAt ?? sample.timestamp, sample.timestamp)
            provider.add(
                sample,
                today: today,
                last7Days: last7Days,
                last30Days: last30Days,
                allTimeStart: allTimeStart,
                now: now
            )

            if sample.timestamp >= last30Days && sample.timestamp <= now {
                let day = dayKey(sample.timestamp, calendar: calendar)
                daily[day, default: 0] += sample.usage.totalTokens
                models[sample.model, default: 0] += sample.usage.totalTokens
            }

            projects[sample.projectName, default: ProjectAccumulator()].add(
                sample,
                today: today,
                last7Days: last7Days,
                last30Days: last30Days,
                allTimeStart: allTimeStart,
                now: now,
                calendar: calendar
            )
        }

        let providerPeriods = provider.periods(
            timeZoneIdentifier: calendar.timeZone.identifier,
            today: today,
            last7Days: last7Days,
            last30Days: last30Days,
            allTimeStart: allTimeStart,
            now: now
        )
        let projectSnapshots = projects.map { name, value in
            ProjectTokenUsage(
                id: projectIdentifier(name),
                displayName: name,
                periods: value.periods.periods(
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    today: today,
                    last7Days: last7Days,
                    last30Days: last30Days,
                    allTimeStart: allTimeStart,
                    now: now
                ),
                daily: value.daily.map { DailyTokenUsage(day: $0.key, totalTokens: $0.value) },
                models: value.models.map { ModelTokenUsage(model: $0.key, totalTokens: $0.value) }
            )
        }

        let updatedAt = sourceUpdatedAt ?? now
        return UsageSnapshot(
            generatedAt: now,
            providers: [
                ProviderSnapshot(
                    id: providerID,
                    displayName: displayName,
                    sourceUpdatedAt: updatedAt,
                    freshness: Freshness.classify(sourceUpdatedAt: updatedAt, now: now),
                    usage: providerPeriods.last30Days.usage,
                    periods: providerPeriods,
                    availability: .available,
                    detail: detail,
                    isEstimated: isEstimated
                ),
            ],
            analytics: UsageAnalytics(
                daily: daily.map { DailyTokenUsage(day: $0.key, totalTokens: $0.value) },
                models: models.map { ModelTokenUsage(model: $0.key, totalTokens: $0.value) },
                projects: projectSnapshots
            )
        )
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func projectIdentifier(_ name: String) -> String {
        let normalized = name.precomposedStringWithCanonicalMapping
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
        let value = String(normalized).split(separator: "-").joined(separator: "-")
        return "project-" + (value.isEmpty ? "unknown" : value)
    }
}

private struct ProjectAccumulator {
    var periods = PeriodAccumulator()
    var daily: [String: Int64] = [:]
    var models: [String: Int64] = [:]

    mutating func add(
        _ sample: LocalUsageSample,
        today: Date,
        last7Days: Date,
        last30Days: Date,
        allTimeStart: Date,
        now: Date,
        calendar: Calendar
    ) {
        periods.add(
            sample,
            today: today,
            last7Days: last7Days,
            last30Days: last30Days,
            allTimeStart: allTimeStart,
            now: now
        )
        if sample.timestamp >= last30Days && sample.timestamp <= now {
            let components = calendar.dateComponents([.year, .month, .day], from: sample.timestamp)
            let day = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
            daily[day, default: 0] += sample.usage.totalTokens
        }
        // Preserve the existing contract: project model totals represent all recorded
        // samples, while the top-level model breakdown is limited to the last 30 days.
        models[sample.model, default: 0] += sample.usage.totalTokens
    }
}

private struct PeriodAccumulator {
    var today = TokenUsage(totalTokens: 0)
    var last7Days = TokenUsage(totalTokens: 0)
    var last30Days = TokenUsage(totalTokens: 0)
    var allTime = TokenUsage(totalTokens: 0)

    mutating func add(
        _ sample: LocalUsageSample,
        today todayStart: Date,
        last7Days last7Start: Date,
        last30Days last30Start: Date,
        allTimeStart: Date,
        now: Date
    ) {
        guard sample.timestamp <= now else { return }
        if sample.timestamp >= allTimeStart { allTime = adding(allTime, sample.usage) }
        if sample.timestamp >= last30Start { last30Days = adding(last30Days, sample.usage) }
        if sample.timestamp >= last7Start { last7Days = adding(last7Days, sample.usage) }
        if sample.timestamp >= todayStart { today = adding(today, sample.usage) }
    }

    func periods(
        timeZoneIdentifier: String,
        today todayStart: Date,
        last7Days last7Start: Date,
        last30Days last30Start: Date,
        allTimeStart: Date,
        now: Date
    ) -> UsagePeriods {
        UsagePeriods(
            timeZoneIdentifier: timeZoneIdentifier,
            today: PeriodTokenUsage(usage: today, startsAt: todayStart, endsAt: now),
            last7Days: PeriodTokenUsage(usage: last7Days, startsAt: last7Start, endsAt: now),
            last30Days: PeriodTokenUsage(usage: last30Days, startsAt: last30Start, endsAt: now),
            recordedAllTime: PeriodTokenUsage(usage: allTime, startsAt: allTimeStart, endsAt: now)
        )
    }

    private func adding(_ lhs: TokenUsage, _ rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            measurement: .aggregate,
            isKnown: lhs.isKnown || rhs.isKnown,
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }
}
