import AppKit
import Domain
import SwiftUI

struct MenuBarDashboardView: View {
    @Bindable var store: MacHubStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TokenWatch")
                        .font(.headline)
                    Text(localizedAppString(store.statusText, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if store.enabledDetectedClientLocations.isEmpty {
                Button {
                    store.requestSettingsNavigation()
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                            .foregroundStyle(MacTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("没有启用且可用的 AI 客户端")
                                .font(.callout.weight(.semibold))
                            Text("打开设置重新扫描本地 AI 客户端")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(MacTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(MacTheme.accent.opacity(0.45), lineWidth: 1)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MenuMetric(title: "今天", value: total(for: .today))
                MenuMetric(title: "7 天", value: total(for: .last7Days))
                MenuMetric(title: "30 天", value: total(for: .last30Days))
                MenuMetric(title: "累计", value: total(for: .recordedAllTime))
            }

            Divider()

            Text("限额 · 余量")
                .font(.headline)
            let limitProviders = store.snapshot.providers.filter { !$0.windows.isEmpty }
            if limitProviders.isEmpty {
                Label("暂无额度数据", systemImage: "gauge.with.dots.needle.0percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(limitProviders.prefix(3))) { provider in
                    MenuLimitProviderView(
                        provider: provider,
                        refreshedAt: store.snapshot.generatedAt
                    )
                }
            }

            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Button("打开仪表盘") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("刷新") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
                Spacer()
                Button("设置") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(MacTheme.background)
        .preferredColorScheme(.dark)
    }

    private func total(for period: UsagePeriod) -> String {
        store.snapshot.hasKnownUsage(for: period)
            ? UsageFormatting.compactTokens(
                    store.snapshot.totalTokens(for: period),
                    estimated: store.snapshot.hasEstimatedUsage(for: period)
                )
            : "—"
    }

}

private struct MenuLimitProviderView: View {
    let provider: ProviderSnapshot
    let refreshedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(provider.displayName, systemImage: "bolt.circle.fill")
                Spacer()
                ProviderCollectionStatusLabel(
                    provider: provider,
                    refreshedAt: refreshedAt
                )
            }
            .font(.callout.weight(.medium))
            ForEach(provider.windows) { window in
                MenuQuotaWindowView(window: window)
            }
        }
    }
}

struct ProviderCollectionStatusLabel: View {
    let provider: ProviderSnapshot
    let refreshedAt: Date
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(StatusPresentation.providerText(
                provider,
                refreshedAt: refreshedAt,
                at: context.date,
                locale: locale
            ))
                .foregroundStyle(
                    provider.availability == .available
                        ? Color.secondary
                        : Color.orange
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MenuQuotaWindowView: View {
    let window: QuotaWindow
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: QuotaResetCountdown.localizedLabel(for: window.label, locale: locale))
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(verbatim: summary(at: context.date))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            ProgressView(value: window.remainingPercent ?? 0, total: 100)
                .tint(MacTheme.quotaColor(remaining: window.remainingPercent))
        }
    }

    private func summary(at now: Date) -> String {
        var components: [String] = []
        if let remaining = window.remainingPercent {
            components.append("\(Int(remaining.rounded()))% \(localizedAppString("剩余", locale: locale))")
        }
        if let countdown = QuotaResetCountdown.text(until: window.resetAt, now: now, locale: locale) {
            components.append(countdown)
        }
        return components.isEmpty ? "—" : components.joined(separator: " · ")
    }
}

enum QuotaResetCountdown {
    static func localizedLabel(for label: String, locale: Locale) -> String {
        switch label {
        case "5 小时": localizedAppString("5 小时", locale: locale)
        case "7 天", "每周": localizedAppString("7 天", locale: locale)
        case "Spark 5 小时": "Spark \(localizedAppString("5 小时", locale: locale))"
        case "Spark 7 天": "Spark \(localizedAppString("7 天", locale: locale))"
        default: label
        }
    }

    static func text(
        until resetAt: Date?,
        now: Date = .now,
        locale: Locale
    ) -> String? {
        guard let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        guard interval > 0 else {
            return localizedAppString("正在重置", locale: locale)
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: interval)
    }
}

private struct MenuMetric: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(MacTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(MacTheme.border, lineWidth: 1)
        }
    }
}
