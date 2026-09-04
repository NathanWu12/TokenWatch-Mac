import Domain
import Foundation
import Testing

@Suite("Usage domain")
struct UsageSnapshotTests {
    @Test("freshness boundaries remain explicit")
    func freshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(Freshness.classify(sourceUpdatedAt: now.addingTimeInterval(-300), now: now) == .fresh)
        #expect(Freshness.classify(sourceUpdatedAt: now.addingTimeInterval(-301), now: now) == .stale)
        #expect(Freshness.classify(sourceUpdatedAt: now.addingTimeInterval(-3_601), now: now) == .offline)
        #expect(Freshness.classify(sourceUpdatedAt: now.addingTimeInterval(60), now: now) == .fresh)
    }

    @Test("compact formatting")
    func compactFormatting() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(UsageFormatting.compactTokens(999, locale: locale) == "999")
        #expect(UsageFormatting.compactTokens(1_200, locale: locale) == "1.2K")
        #expect(UsageFormatting.compactTokens(5_000_000, locale: locale) == "5M")
        #expect(UsageFormatting.compactTokens(1_200, estimated: true, locale: locale) == "~1.2K")
    }

    @Test("older usage payloads default to known")
    func decodesLegacyUsage() throws {
        let data = Data(
            """
            {
              "inputTokens": 1,
              "outputTokens": 2,
              "cachedInputTokens": 3,
              "reasoningOutputTokens": 4,
              "totalTokens": 10
            }
            """.utf8
        )
        let usage = try JSONDecoder().decode(TokenUsage.self, from: data)
        #expect(usage.isKnown)
        #expect(usage.measurement == .aggregate)
        #expect(usage.totalTokens == 10)
    }

    @Test("period totals remain independent and select the recent primary provider")
    func periodTotalsAndPrimaryProvider() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = UsageSnapshot(
            generatedAt: now,
            providers: [
                provider(id: "codex", today: 80, last7Days: 200, last30Days: 500, allTime: 900, now: now),
                provider(id: "claude", today: 20, last7Days: 400, last30Days: 700, allTime: 1_100, now: now),
            ]
        )

        #expect(snapshot.totalTokens(for: .today) == 100)
        #expect(snapshot.totalTokens(for: .last7Days) == 600)
        #expect(snapshot.totalTokens(for: .last30Days) == 1_200)
        #expect(snapshot.totalTokens(for: .recordedAllTime) == 2_000)
        #expect(snapshot.primaryProvider?.id == "codex")
    }

    @Test("legacy provider snapshots preserve 30-day data without inventing other periods")
    func legacyProviderPeriods() throws {
        let data = Data(
            """
            {
              "id": "codex",
              "displayName": "Codex",
              "sourceUpdatedAt": "1970-01-01T00:00:00Z",
              "freshness": "fresh",
              "usage": {
                "inputTokens": 0,
                "outputTokens": 0,
                "cachedInputTokens": 0,
                "reasoningOutputTokens": 0,
                "totalTokens": 42,
                "isKnown": true,
                "measurement": "aggregate"
              },
              "windows": [],
              "availability": "available",
              "capabilities": ["usage"]
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let provider = try decoder.decode(ProviderSnapshot.self, from: data)

        #expect(provider.usage(for: .last30Days).totalTokens == 42)
        #expect(provider.usage(for: .today).isKnown == false)
        #expect(provider.isEstimated == false)
        #expect(provider.usage(for: .recordedAllTime).isKnown == false)
        #expect(provider.sourceKind == .macObserved)
    }

    @Test("legacy snapshots decode as live data")
    func legacySnapshotMode() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "generatedAt": "1970-01-01T00:00:00Z",
              "providers": []
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(UsageSnapshot.self, from: data).mode == .live)
    }

    @Test("legacy analytics decode without inventing projects")
    func legacyAnalyticsProjects() throws {
        let data = Data(#"{"daily":[],"models":[]}"#.utf8)
        let analytics = try JSONDecoder().decode(UsageAnalytics.self, from: data)
        #expect(analytics.projects.isEmpty)
    }

    @Test("project trend groups daily values into calendar weeks and months")
    func projectTrendGrouping() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 10_000)
        let project = ProjectTokenUsage(
            id: "project-sample-project",
            displayName: "SampleProject",
            periods: provider(
                id: "codex",
                today: 10,
                last7Days: 30,
                last30Days: 60,
                allTime: 60,
                now: now
            ).periods,
            daily: [
                DailyTokenUsage(day: "2026-07-27", totalTokens: 10),
                DailyTokenUsage(day: "2026-07-28", totalTokens: 20),
                DailyTokenUsage(day: "2026-08-03", totalTokens: 30),
            ],
            models: []
        )

        #expect(project.trend(groupedBy: .day, calendar: calendar).map(\.totalTokens) == [10, 20, 30])
        #expect(project.trend(groupedBy: .week, calendar: calendar).map(\.totalTokens) == [30, 30])
        #expect(project.trend(groupedBy: .month, calendar: calendar).map(\.totalTokens) == [30, 30])
    }

    @Test("direct quota replaces Mac quota without adding token usage")
    func directQuotaMerge() {
        let now = Date(timeIntervalSince1970: 10_000)
        let mac = UsageSnapshot(
            generatedAt: now.addingTimeInterval(-60),
            providers: [provider(
                id: "codex",
                today: 10,
                last7Days: 20,
                last30Days: 30,
                allTime: 40,
                now: now.addingTimeInterval(-60)
            )]
        )
        let direct = ProviderSnapshot(
            id: "codex",
            displayName: "ChatGPT / Codex",
            sourceUpdatedAt: now,
            freshness: .fresh,
            usage: .unknown,
            windows: [QuotaWindow(
                id: "primary",
                label: "5 小时",
                usedPercent: 25,
                resetAt: now.addingTimeInterval(600)
            )],
            sourceKind: .iphoneDirect,
            planName: "Plus"
        )

        let merged = mac.mergingDirectProviders([direct], generatedAt: now)
        let provider = merged.providers.first

        #expect(merged.generatedAt == now)
        #expect(provider?.usage(for: .last30Days).totalTokens == 30)
        #expect(provider?.windows.first?.remainingPercent == 75)
        #expect(provider?.sourceKind == .iphoneDirect)
        #expect(provider?.planName == "Plus")
    }

    @Test("quota remaining is the complement of used percentage")
    func quotaRemaining() {
        #expect(QuotaWindow(id: "known", label: "Known", usedPercent: 63, resetAt: nil).remainingPercent == 37)
        #expect(QuotaWindow(id: "unknown", label: "Unknown", usedPercent: nil, resetAt: nil).remainingPercent == nil)
    }

    @Test("retry delay is bounded and deterministic with injected jitter")
    func retrySchedule() {
        #expect(RetrySchedule.delay(
            attempt: 0,
            baseDelay: 10,
            maximumDelay: 100,
            jitterFraction: 0.25,
            jitterUnit: 0
        ) == 10)
        #expect(RetrySchedule.delay(
            attempt: 2,
            baseDelay: 10,
            maximumDelay: 100,
            jitterFraction: 0.25,
            jitterUnit: 1
        ) == 50)
        #expect(RetrySchedule.delay(
            attempt: 20,
            baseDelay: 10,
            maximumDelay: 100,
            jitterFraction: 0.25,
            jitterUnit: 1
        ) == 100)
    }

    @Test("out-of-order snapshots keep newest state and union reset events")
    func outOfOrderSnapshotMerge() {
        let now = Date(timeIntervalSince1970: 10_000)
        let oldEvent = resetEvent(
            id: "reset-old",
            detectedAt: now.addingTimeInterval(-20),
            expiresAt: now.addingTimeInterval(300)
        )
        let newEvent = resetEvent(
            id: "reset-new",
            detectedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(300)
        )
        let newest = UsageSnapshot(
            generatedAt: now,
            providers: [provider(
                id: "newest",
                today: 200,
                last7Days: 200,
                last30Days: 200,
                allTime: 200,
                now: now
            )],
            resetEvents: [newEvent]
        )
        let delayedOlder = UsageSnapshot(
            generatedAt: now.addingTimeInterval(-60),
            providers: [provider(
                id: "older",
                today: 100,
                last7Days: 100,
                last30Days: 100,
                allTime: 100,
                now: now.addingTimeInterval(-60)
            )],
            resetEvents: [oldEvent]
        )

        let merged = newest.mergingOutOfOrderUpdate(delayedOlder, now: now)

        #expect(merged.providers.first?.id == "newest")
        #expect(merged.resetEvents.map(\.id) == ["reset-old", "reset-new"])
    }

    @Test("out-of-order snapshot merge prunes expired reset events")
    func outOfOrderSnapshotMergePrunesExpiredEvents() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = UsageSnapshot(
            generatedAt: now,
            providers: [],
            resetEvents: [resetEvent(
                id: "expired",
                detectedAt: now.addingTimeInterval(-100),
                expiresAt: now.addingTimeInterval(-1)
            )]
        )

        #expect(snapshot.mergingOutOfOrderUpdate(snapshot, now: now).resetEvents.isEmpty)
    }

    @Test("content equivalence ignores refresh-clock-only changes")
    func contentEquivalenceIgnoresRefreshClockOnlyChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = provider(
            id: "codex",
            today: 10,
            last7Days: 20,
            last30Days: 30,
            allTime: 40,
            now: now
        )
        func extendingEnds(_ value: PeriodTokenUsage) -> PeriodTokenUsage {
            PeriodTokenUsage(
                usage: value.usage,
                startsAt: value.startsAt,
                endsAt: value.endsAt.addingTimeInterval(60)
            )
        }
        let laterProvider = ProviderSnapshot(
            id: original.id,
            displayName: original.displayName,
            sourceUpdatedAt: original.sourceUpdatedAt,
            freshness: original.freshness,
            usage: original.usage,
            periods: UsagePeriods(
                timeZoneIdentifier: original.periods.timeZoneIdentifier,
                today: extendingEnds(original.periods.today),
                last7Days: extendingEnds(original.periods.last7Days),
                last30Days: extendingEnds(original.periods.last30Days),
                recordedAllTime: extendingEnds(original.periods.recordedAllTime)
            ),
            windows: original.windows,
            availability: original.availability,
            detail: original.detail,
            sourceKind: original.sourceKind,
            planName: original.planName,
            isEstimated: original.isEstimated
        )
        let first = UsageSnapshot(generatedAt: now, providers: [original])
        let later = UsageSnapshot(
            generatedAt: now.addingTimeInterval(60),
            providers: [laterProvider]
        )
        #expect(first.hasSameContent(as: later))

        let changed = UsageSnapshot(
            generatedAt: now.addingTimeInterval(60),
            providers: [provider(
                id: "codex",
                today: 11,
                last7Days: 21,
                last30Days: 31,
                allTime: 41,
                now: now
            )]
        )
        #expect(!first.hasSameContent(as: changed))
    }

    private func resetEvent(id: String, detectedAt: Date, expiresAt: Date) -> QuotaResetEvent {
        QuotaResetEvent(
            id: id,
            providerID: "codex",
            providerName: "Codex",
            windowID: "weekly",
            windowLabel: "长周期",
            detectedAt: detectedAt,
            expiresAt: expiresAt,
            previousUsedPercent: 90,
            currentUsedPercent: 1,
            previousResetAt: detectedAt.addingTimeInterval(-100),
            currentResetAt: detectedAt.addingTimeInterval(300)
        )
    }

    private func provider(
        id: String,
        today: Int64,
        last7Days: Int64,
        last30Days: Int64,
        allTime: Int64,
        now: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: id,
            sourceUpdatedAt: now,
            freshness: .fresh,
            usage: TokenUsage(totalTokens: last30Days),
            periods: UsagePeriods(
                timeZoneIdentifier: "UTC",
                today: PeriodTokenUsage(usage: TokenUsage(totalTokens: today), startsAt: now, endsAt: now),
                last7Days: PeriodTokenUsage(usage: TokenUsage(totalTokens: last7Days), startsAt: now, endsAt: now),
                last30Days: PeriodTokenUsage(usage: TokenUsage(totalTokens: last30Days), startsAt: now, endsAt: now),
                recordedAllTime: PeriodTokenUsage(
                    usage: TokenUsage(totalTokens: allTime),
                    startsAt: Date(timeIntervalSince1970: 0),
                    endsAt: now
                )
            )
        )
    }
}
