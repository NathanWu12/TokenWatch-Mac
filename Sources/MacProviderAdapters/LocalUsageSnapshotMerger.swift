import Domain
import Foundation

/// Combines independently collected provider snapshots into one TokenWatch
/// snapshot. A provider parser can fail without invalidating successful peers;
/// callers pass only successful snapshots here.
public enum LocalUsageSnapshotMerger {
    public static func merge(
        _ snapshots: [UsageSnapshot],
        generatedAt: Date = Date()
    ) -> UsageSnapshot {
        guard !snapshots.isEmpty else {
            return UsageSnapshot(generatedAt: generatedAt, providers: [])
        }

        var providerByID: [String: ProviderSnapshot] = [:]
        var resetEventByID: [String: QuotaResetEvent] = [:]
        for snapshot in snapshots {
            for provider in snapshot.providers {
                if let existing = providerByID[provider.id],
                   existing.sourceUpdatedAt > provider.sourceUpdatedAt {
                    continue
                }
                providerByID[provider.id] = provider
            }
            for event in snapshot.resetEvents {
                resetEventByID[event.id] = event
            }
        }

        let analytics = mergeAnalytics(snapshots.compactMap(\.analytics))
        return UsageSnapshot(
            generatedAt: generatedAt,
            providers: providerByID.values.sorted { $0.displayName < $1.displayName },
            analytics: analytics,
            resetEvents: resetEventByID.values.sorted { $0.detectedAt < $1.detectedAt }
        )
    }

    private static func mergeAnalytics(_ values: [UsageAnalytics]) -> UsageAnalytics? {
        guard !values.isEmpty else { return nil }

        var daily: [String: Int64] = [:]
        var models: [String: Int64] = [:]
        var projectGroups: [String: [ProjectTokenUsage]] = [:]

        for analytics in values {
            for value in analytics.daily {
                daily[value.day, default: 0] += value.totalTokens
            }
            for value in analytics.models {
                models[value.model, default: 0] += value.totalTokens
            }
            for project in analytics.projects {
                projectGroups[project.displayName, default: []].append(project)
            }
        }

        return UsageAnalytics(
            daily: daily.map { DailyTokenUsage(day: $0.key, totalTokens: $0.value) },
            models: models.map { ModelTokenUsage(model: $0.key, totalTokens: $0.value) },
            projects: projectGroups.map { name, projects in
                mergeProjects(name: name, projects: projects)
            }
        )
    }

    private static func mergeProjects(
        name: String,
        projects: [ProjectTokenUsage]
    ) -> ProjectTokenUsage {
        guard let first = projects.first else {
            fatalError("LocalUsageSnapshotMerger requires a non-empty project group")
        }
        guard projects.count > 1 else { return first }

        var daily: [String: Int64] = [:]
        var models: [String: Int64] = [:]
        for project in projects {
            for value in project.daily {
                daily[value.day, default: 0] += value.totalTokens
            }
            for value in project.models {
                models[value.model, default: 0] += value.totalTokens
            }
        }

        return ProjectTokenUsage(
            id: first.id,
            displayName: name,
            periods: UsagePeriods(
                timeZoneIdentifier: first.periods.timeZoneIdentifier,
                today: mergePeriod(projects.map { $0.periods.today }),
                last7Days: mergePeriod(projects.map { $0.periods.last7Days }),
                last30Days: mergePeriod(projects.map { $0.periods.last30Days }),
                recordedAllTime: mergePeriod(projects.map { $0.periods.recordedAllTime })
            ),
            daily: daily.map { DailyTokenUsage(day: $0.key, totalTokens: $0.value) },
            models: models.map { ModelTokenUsage(model: $0.key, totalTokens: $0.value) }
        )
    }

    private static func mergePeriod(_ values: [PeriodTokenUsage]) -> PeriodTokenUsage {
        let start = values.map(\.startsAt).min() ?? Date(timeIntervalSince1970: 0)
        let end = values.map(\.endsAt).max() ?? start
        return PeriodTokenUsage(
            usage: sum(values.map(\.usage)),
            startsAt: start,
            endsAt: end
        )
    }

    private static func sum(_ values: [TokenUsage]) -> TokenUsage {
        let known = values.filter(\.isKnown)
        guard !known.isEmpty else { return .unknown }
        return TokenUsage(
            measurement: .aggregate,
            inputTokens: known.reduce(0) { $0 + $1.inputTokens },
            outputTokens: known.reduce(0) { $0 + $1.outputTokens },
            cachedInputTokens: known.reduce(0) { $0 + $1.cachedInputTokens },
            reasoningOutputTokens: known.reduce(0) { $0 + $1.reasoningOutputTokens },
            totalTokens: known.reduce(0) { $0 + $1.totalTokens }
        )
    }
}
