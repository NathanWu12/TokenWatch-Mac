import Domain
import Foundation

public enum SampleSnapshots {
    public static func p0(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            generatedAt: now,
            providers: [
                ProviderSnapshot(
                    id: "codex",
                    displayName: "Codex",
                    sourceUpdatedAt: now,
                    freshness: .fresh,
                    usage: TokenUsage(
                        inputTokens: 1_240_000,
                        outputTokens: 186_000,
                        cachedInputTokens: 3_820_000,
                        reasoningOutputTokens: 42_000,
                        totalTokens: 5_288_000
                    ),
                    periods: periods(
                        today: 286_000,
                        last7Days: 1_742_000,
                        last30Days: 5_288_000,
                        recordedAllTime: 18_640_000,
                        now: now
                    ),
                    windows: [
                        QuotaWindow(
                            id: "codex-primary",
                            label: "5 小时",
                            usedPercent: 63,
                            resetAt: now.addingTimeInterval(72 * 60)
                        ),
                        QuotaWindow(
                            id: "codex-secondary",
                            label: "7 天",
                            usedPercent: 37,
                            resetAt: now.addingTimeInterval(3 * 24 * 60 * 60)
                        ),
                    ]
                ),
                ProviderSnapshot(
                    id: "claude",
                    displayName: "Claude Code",
                    sourceUpdatedAt: now.addingTimeInterval(-8 * 60),
                    freshness: .stale,
                    usage: TokenUsage(
                        inputTokens: 420_000,
                        outputTokens: 96_000,
                        cachedInputTokens: 1_050_000,
                        totalTokens: 1_566_000
                    ),
                    periods: periods(
                        today: 94_000,
                        last7Days: 580_000,
                        last30Days: 1_566_000,
                        recordedAllTime: 7_420_000,
                        now: now
                    ),
                    windows: [
                        QuotaWindow(
                            id: "claude-five-hour",
                            label: "5 小时",
                            usedPercent: 82,
                            resetAt: now.addingTimeInterval(48 * 60)
                        ),
                    ]
                ),
                ProviderSnapshot(
                    id: "cursor",
                    displayName: "Cursor",
                    sourceUpdatedAt: now,
                    freshness: .fresh,
                    usage: TokenUsage(totalTokens: 684_000),
                    periods: periods(
                        today: 32_000,
                        last7Days: 188_000,
                        last30Days: 684_000,
                        recordedAllTime: 2_160_000,
                        now: now
                    ),
                    availability: .available
                ),
            ],
            analytics: UsageAnalytics(
                daily: dailyUsage(now: now),
                models: [
                    ModelTokenUsage(model: "gpt-5.6-sol", totalTokens: 4_427_000),
                    ModelTokenUsage(model: "gpt-5.5", totalTokens: 777_000),
                    ModelTokenUsage(model: "codex-auto-review", totalTokens: 84_000),
                ],
                projects: [
                    project("SampleProject", total: 12_800_000, multiplier: 1, now: now),
                    project("ERP_Zuxus", total: 8_100_000, multiplier: 0.63, now: now),
                    project(
                        "Public Resource Management",
                        total: 5_200_000,
                        multiplier: 0.41,
                        now: now
                    ),
                ]
            )
        )
    }

    private static func project(
        _ name: String,
        total: Int64,
        multiplier: Double,
        now: Date
    ) -> ProjectTokenUsage {
        ProjectTokenUsage(
            id: "sample-project-" + name.lowercased().replacingOccurrences(of: " ", with: "-"),
            displayName: name,
            periods: periods(
                today: Int64(286_000 * multiplier),
                last7Days: Int64(1_742_000 * multiplier),
                last30Days: Int64(5_288_000 * multiplier),
                recordedAllTime: total,
                now: now
            ),
            daily: dailyUsage(now: now).map {
                DailyTokenUsage(
                    day: $0.day,
                    totalTokens: Int64(Double($0.totalTokens) * multiplier)
                )
            },
            models: [
                ModelTokenUsage(model: "gpt-5.6-sol", totalTokens: Int64(Double(total) * 0.82)),
                ModelTokenUsage(model: "gpt-5.5", totalTokens: Int64(Double(total) * 0.18)),
            ]
        )
    }

    private static func dailyUsage(now: Date) -> [DailyTokenUsage] {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<26 * 7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset - (26 * 7 - 1), to: now) ?? now
            let activity = offset % 9 == 0 || offset > 26 * 7 - 24
            let wave = Int64((offset % 7) + 1) * 42_000
            return DailyTokenUsage(
                day: formatter.string(from: day),
                totalTokens: activity ? wave : 0
            )
        }
    }

    private static func periods(
        today: Int64,
        last7Days: Int64,
        last30Days: Int64,
        recordedAllTime: Int64,
        now: Date
    ) -> UsagePeriods {
        UsagePeriods(
            timeZoneIdentifier: "Asia/Shanghai",
            today: PeriodTokenUsage(usage: TokenUsage(totalTokens: today), startsAt: now, endsAt: now),
            last7Days: PeriodTokenUsage(usage: TokenUsage(totalTokens: last7Days), startsAt: now, endsAt: now),
            last30Days: PeriodTokenUsage(usage: TokenUsage(totalTokens: last30Days), startsAt: now, endsAt: now),
            recordedAllTime: PeriodTokenUsage(
                usage: TokenUsage(totalTokens: recordedAllTime),
                startsAt: Date(timeIntervalSince1970: 0),
                endsAt: now
            )
        )
    }
}
