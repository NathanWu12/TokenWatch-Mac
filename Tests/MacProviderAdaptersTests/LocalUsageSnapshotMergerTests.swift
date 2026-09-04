import Domain
import Foundation
import MacProviderAdapters
import Testing

@Suite("Local usage snapshot merger")
struct LocalUsageSnapshotMergerTests {
    @Test("combines provider, trend, model, and same-name project totals")
    func mergesSnapshots() throws {
        let now = Date(timeIntervalSince1970: 1_788_429_600)
        let codex = fixture(
            providerID: "codex",
            displayName: "Codex",
            model: "gpt-test",
            project: "SharedProject",
            total: 10,
            now: now
        )
        let claude = fixture(
            providerID: "claude-code",
            displayName: "Claude Code",
            model: "claude-test",
            project: "SharedProject",
            total: 20,
            now: now
        )

        let merged = LocalUsageSnapshotMerger.merge([codex, claude], generatedAt: now)
        #expect(Set(merged.providers.map(\.id)) == ["codex", "claude-code"])
        #expect(merged.totalTokens(for: .today) == 30)

        let analytics = try #require(merged.analytics)
        #expect(analytics.daily.first?.totalTokens == 30)
        #expect(Set(analytics.models.map(\.model)) == ["gpt-test", "claude-test"])
        #expect(analytics.projects.count == 1)
        #expect(analytics.projects.first?.periods.today.usage.totalTokens == 30)
    }

    private func fixture(
        providerID: String,
        displayName: String,
        model: String,
        project: String,
        total: Int64,
        now: Date
    ) -> UsageSnapshot {
        let usage = TokenUsage(inputTokens: total, totalTokens: total)
        let period = PeriodTokenUsage(usage: usage, startsAt: now, endsAt: now)
        let periods = UsagePeriods(
            timeZoneIdentifier: "UTC",
            today: period,
            last7Days: period,
            last30Days: period,
            recordedAllTime: period
        )
        return UsageSnapshot(
            generatedAt: now,
            providers: [
                ProviderSnapshot(
                    id: providerID,
                    displayName: displayName,
                    sourceUpdatedAt: now,
                    freshness: .fresh,
                    usage: usage,
                    periods: periods
                ),
            ],
            analytics: UsageAnalytics(
                daily: [DailyTokenUsage(day: "2026-09-03", totalTokens: total)],
                models: [ModelTokenUsage(model: model, totalTokens: total)],
                projects: [
                    ProjectTokenUsage(
                        id: "project-shared",
                        displayName: project,
                        periods: periods,
                        daily: [DailyTokenUsage(day: "2026-09-03", totalTokens: total)],
                        models: [ModelTokenUsage(model: model, totalTokens: total)]
                    ),
                ]
            )
        )
    }
}
