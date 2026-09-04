import Charts
import Domain
import SwiftUI

enum MacTheme {
    static let accent = Color(red: 0.04, green: 0.48, blue: 1)
    static let background = Color(red: 0.035, green: 0.04, blue: 0.055)
    static let sidebar = Color(red: 0.055, green: 0.06, blue: 0.078)
    static let card = Color.white.opacity(0.055)
    static let elevatedCard = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.09)
    static let muted = Color.white.opacity(0.58)

    static func quotaColor(remaining: Double?) -> Color {
        StatusPresentation.quotaColor(remainingPercent: remaining)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case usage
    case limits
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .usage: "用量"
        case .limits: "限额"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .usage: "chart.bar.xaxis"
        case .limits: "gauge.with.dots.needle.50percent"
        case .settings: "gearshape"
        }
    }
}

struct MacHubView: View {
    @Bindable var store: MacHubStore
    @ObservedObject var updateController: MacUpdateController
    @Binding var languageIdentifier: String
    @State private var selection: DashboardSection

    init(
        store: MacHubStore,
        updateController: MacUpdateController,
        languageIdentifier: Binding<String>
    ) {
        self.store = store
        self.updateController = updateController
        _languageIdentifier = languageIdentifier
        _selection = State(
            initialValue: store.enabledDetectedClientLocations.isEmpty ? .settings : .usage
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("概览") {
                    ForEach([DashboardSection.usage, .limits]) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                Section("账户") {
                    Label(DashboardSection.settings.title, systemImage: DashboardSection.settings.symbol)
                        .tag(DashboardSection.settings)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MacTheme.sidebar)
            .navigationTitle("TokenWatch")
            .safeAreaInset(edge: .bottom) {
                SidebarStatus(store: store)
            }
            .navigationSplitViewColumnWidth(min: 176, ideal: 204, max: 224)
        } detail: {
            Group {
                switch selection {
                case .usage:
                    NavigationStack {
                        UsageDashboard(store: store)
                    }
                case .limits:
                    LimitsDashboard(store: store)
                case .settings:
                    SettingsDashboard(
                        store: store,
                        updateController: updateController,
                        languageIdentifier: $languageIdentifier
                    )
                }
            }
            .background(MacTheme.background)
        }
        .tint(MacTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: store.settingsNavigationRequest) {
            selection = .settings
        }
        .onChange(of: store.detectedClientLocations) { _, locations in
            if locations.isEmpty {
                selection = .settings
            } else if selection == .settings {
                selection = .usage
            }
        }
    }
}

private struct SidebarStatus: View {
    @Bindable var store: MacHubStore
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(localizedAppString(store.statusText, locale: locale))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("TokenWatch Native Collection")
                .font(.caption2)
                .foregroundStyle(MacTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .background(MacTheme.sidebar)
    }

    private var statusColor: Color {
        if store.lastError != nil { return .orange }
        if store.isRefreshing { return MacTheme.accent }
        return .green
    }
}

private struct UsageDashboard: View {
    @Bindable var store: MacHubStore
    @State private var selectedPeriod: UsagePeriod = .last30Days
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DashboardHeader(
                    title: "用量",
                    subtitle: localizedAppString(store.statusText, locale: locale),
                    isRefreshing: store.isRefreshing,
                    refresh: { Task { await store.refresh() } }
                )

                PeriodSummaryGrid(snapshot: store.snapshot)

                HStack(alignment: .top, spacing: 16) {
                    UsageHeroCard(
                        snapshot: store.snapshot,
                        selectedPeriod: $selectedPeriod
                    )
                    .frame(maxWidth: .infinity)

                    ProjectRankingCard(projects: store.snapshot.analytics?.projects ?? [])
                        .frame(width: 310)
                }

                HStack(alignment: .top, spacing: 16) {
                    UsageTrendCard(analytics: store.snapshot.analytics)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        ModelRankingCard(analytics: store.snapshot.analytics)
                        ActivityHeatmapCard(analytics: store.snapshot.analytics)
                    }
                    .frame(width: 310)
                }

                DailyUsageCard(analytics: store.snapshot.analytics)
            }
            .padding(20)
        }
    }
}

private struct ProjectRankingCard: View {
    let projects: [ProjectTokenUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("项目", trailing: projects.isEmpty ? nil : "\(projects.count)")
            if projects.isEmpty {
                EmptyCardLabel("暂无项目数据", symbol: "folder")
            } else {
                ForEach(projects.prefix(6)) { project in
                    NavigationLink {
                        MacProjectDetailView(project: project)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(MacTheme.accent)
                            Text(project.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(UsageFormatting.compactTokens(
                                project.usage(for: .recordedAllTime).totalTokens
                            ))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if projects.count > 6 {
                    NavigationLink {
                        MacProjectListView(projects: projects)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.accent)
                }
            }
        }
        .dashboardCard()
    }
}

private struct MacProjectListView: View {
    let projects: [ProjectTokenUsage]

    var body: some View {
        List(projects) { project in
            NavigationLink {
                MacProjectDetailView(project: project)
            } label: {
                HStack {
                    Label(project.displayName, systemImage: "folder.fill")
                    Spacer()
                    Text(UsageFormatting.compactTokens(
                        project.usage(for: .recordedAllTime).totalTokens
                    ))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("All Projects")
    }
}

private struct MacModelListView: View {
    let models: [ModelTokenUsage]

    private var total: Int64 { max(models.reduce(0) { $0 + $1.totalTokens }, 1) }

    var body: some View {
        List(Array(models.enumerated()), id: \.element.id) { index, model in
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(model.model)
                Spacer()
                Text(UsageFormatting.compactTokens(model.totalTokens))
                    .monospacedDigit()
                Text(Double(model.totalTokens) / Double(total), format: .percent.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .navigationTitle("All Models")
    }
}

private struct DatedTrendPoint: Identifiable {
    let source: TokenTrendPoint
    let date: Date

    var id: String { source.id }

    init?(_ source: TokenTrendPoint) {
        let parts = source.periodStart.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(
            year: parts[0],
            month: parts[1],
            day: parts[2]
        )) else { return nil }
        self.source = source
        self.date = date
    }
}

private func macTrendAxisDates(
    _ dates: [Date],
    _ granularity: UsageTrendGranularity
) -> [Date] {
    let sorted = Array(Set(dates)).sorted()
    guard sorted.count > 3, let first = sorted.first, let last = sorted.last else { return sorted }
    let midpoint = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
    return [first, midpoint, last]
}

@MainActor
private func macTrendSelectionLabel(
    _ point: DatedTrendPoint,
    granularity: UsageTrendGranularity,
    locale: Locale
) -> String {
    "\(MacTrendDateFormatterCache.string(from: point.date, granularity: granularity, locale: locale)) · \(UsageFormatting.compactTokens(point.source.totalTokens))"
}

@MainActor
private enum MacTrendDateFormatterCache {
    private static var formatters: [String: DateFormatter] = [:]

    static func string(
        from date: Date,
        granularity: UsageTrendGranularity,
        locale: Locale
    ) -> String {
        let template = granularity == .month ? "yMMM" : "MMMd"
        let timeZone = TimeZone.current
        let key = "\(locale.identifier)|\(timeZone.identifier)|\(template)"
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.locale = locale
            created.timeZone = timeZone
            created.setLocalizedDateFormatFromTemplate(template)
            if formatters.count >= 12 { formatters.removeAll(keepingCapacity: true) }
            formatters[key] = created
            formatter = created
        }
        return formatter.string(from: date)
    }
}

private struct TrendAxisLabels: View {
    let dates: [Date]
    let granularity: UsageTrendGranularity
    let locale: Locale

    private func label(for date: Date) -> String {
        MacTrendDateFormatterCache.string(from: date, granularity: granularity, locale: locale)
    }

    var body: some View {
        let values = macTrendAxisDates(dates, granularity)
        if let first = values.first, let last = values.last {
            let middle = values.count > 2 ? values[1] : nil
            ZStack {
                Text(verbatim: label(for: first))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let middle {
                    Text(verbatim: label(for: middle))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Text(verbatim: label(for: last))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.trailing, 52)
        }
    }
}

private struct MacProjectDetailView: View {
    let project: ProjectTokenUsage
    @Environment(\.locale) private var locale
    @State private var selectedPeriod: UsagePeriod = .last30Days
    @State private var granularity: UsageTrendGranularity = .day
    @State private var selectedTrendDate: Date?

    private var points: [TokenTrendPoint] {
        let values = project.trend(groupedBy: granularity)
        switch granularity {
        case .day: return Array(values.suffix(30))
        case .week: return Array(values.suffix(26))
        case .month: return Array(values.suffix(12))
        }
    }

    private var datedPoints: [DatedTrendPoint] {
        points.compactMap(DatedTrendPoint.init)
    }

    private var selectedPoint: DatedTrendPoint? {
        guard let selectedTrendDate else { return nil }
        return datedPoints.min {
            abs($0.date.timeIntervalSince(selectedTrendDate))
                < abs($1.date.timeIntervalSince(selectedTrendDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(project.displayName, systemImage: "folder.fill")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Spacer()
                    Text(UsageFormatting.compactTokens(
                        project.usage(for: .recordedAllTime).totalTokens
                    ))
                    .font(.title2.bold())
                    .monospacedDigit()
                }

                projectPeriodGrid
                projectBreakdown
                projectTrend
                projectModels
            }
            .padding(20)
        }
        .navigationTitle(project.displayName)
        .background(MacTheme.background)
        .onChange(of: granularity) { selectedTrendDate = nil }
    }

    private var projectPeriodGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            projectMetric("Today", .today)
            projectMetric("7 days", .last7Days)
            projectMetric("30 days", .last30Days)
            projectMetric("Total", .recordedAllTime)
        }
        .dashboardCard()
    }

    private func projectMetric(_ title: LocalizedStringKey, _ period: UsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(UsageFormatting.compactTokens(project.usage(for: period).totalTokens))
                .font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 11))
    }

    private var projectBreakdown: some View {
        let usage = project.usage(for: selectedPeriod)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Token 构成", trailing: nil)
                Picker("周期", selection: $selectedPeriod) {
                    Text("日").tag(UsagePeriod.today)
                    Text("周").tag(UsagePeriod.last7Days)
                    Text("月").tag(UsagePeriod.last30Days)
                    Text("累计").tag(UsagePeriod.recordedAllTime)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            HStack(spacing: 12) {
                breakdownMetric("Input", usage.inputTokens)
                breakdownMetric("Output", usage.outputTokens)
                breakdownMetric("Cached", usage.cachedInputTokens)
                breakdownMetric("Reasoning", usage.reasoningOutputTokens)
            }
        }
        .dashboardCard()
    }

    private func breakdownMetric(_ title: LocalizedStringKey, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(UsageFormatting.compactTokens(value)).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var projectTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("使用趋势", trailing: selectedPoint.map {
                    macTrendSelectionLabel($0, granularity: granularity, locale: locale)
                })
                Picker("分组", selection: $granularity) {
                    Text("日").tag(UsageTrendGranularity.day)
                    Text("周").tag(UsageTrendGranularity.week)
                    Text("月").tag(UsageTrendGranularity.month)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            if points.isEmpty {
                EmptyCardLabel("暂无趋势数据", symbol: "chart.xyaxis.line")
            } else {
                Chart(datedPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.source.totalTokens)
                    )
                    .foregroundStyle(MacTheme.accent.opacity(0.12))
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.source.totalTokens)
                    )
                    .foregroundStyle(MacTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if selectedPoint?.id == point.id {
                        RuleMark(x: .value("Selected", point.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Tokens", point.source.totalTokens)
                        )
                        .foregroundStyle(MacTheme.accent)
                        .symbolSize(70)
                    }
                }
                .chartXSelection(value: $selectedTrendDate)
                .chartXAxis {
                    AxisMarks(values: macTrendAxisDates(datedPoints.map(\.date), granularity)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    }
                }
                .chartXScale(range: .plotDimension(startPadding: 36, endPadding: 36))
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let value = value.as(Int64.self) {
                                Text(UsageFormatting.compactTokens(value))
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
                TrendAxisLabels(
                    dates: datedPoints.map(\.date),
                    granularity: granularity,
                    locale: locale
                )
            }
        }
        .dashboardCard()
    }

    private var projectModels: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("模型", trailing: "\(project.models.count)")
            if project.models.isEmpty {
                EmptyCardLabel("暂无模型数据", symbol: "cpu")
            } else {
                ForEach(project.models.prefix(6)) { model in
                    HStack {
                        Text(model.model).lineLimit(1)
                        Spacer()
                        Text(UsageFormatting.compactTokens(model.totalTokens)).monospacedDigit()
                    }
                }
                if project.models.count > 6 {
                    NavigationLink {
                        MacModelListView(models: project.models)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.accent)
                }
            }
        }
        .dashboardCard()
    }
}

private struct DashboardHeader: View {
    let title: LocalizedStringKey
    let subtitle: String
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: refresh) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help("刷新")
            .disabled(isRefreshing)
        }
    }
}

private struct PeriodSummaryGrid: View {
    let snapshot: UsageSnapshot

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            metric("今天", .today)
            metric("7 天", .last7Days)
            metric("30 天", .last30Days)
            metric("累计", .recordedAllTime)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ period: UsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value(period))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MacTheme.border, lineWidth: 1)
        }
    }

    private func value(_ period: UsagePeriod) -> String {
        snapshot.hasKnownUsage(for: period)
            ? UsageFormatting.compactTokens(
                snapshot.totalTokens(for: period),
                estimated: snapshot.hasEstimatedUsage(for: period)
            )
            : "—"
    }
}

private struct ModelRankingCard: View {
    let analytics: UsageAnalytics?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("模型", trailing: analytics.map { "\($0.models.count)" })
            if let models = analytics?.models, !models.isEmpty {
                let total = max(models.reduce(0) { $0 + $1.totalTokens }, 1)
                ForEach(Array(models.prefix(6).enumerated()), id: \.element.id) { index, model in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 23, height: 23)
                            .background(.white.opacity(0.07), in: Circle())
                        Text(model.model)
                            .lineLimit(1)
                        Spacer()
                        Text(Double(model.totalTokens) / Double(total), format: .percent.precision(.fractionLength(1)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
                if models.count > 6 {
                    NavigationLink {
                        MacModelListView(models: models)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.accent)
                }
            } else {
                EmptyCardLabel("暂无模型数据", symbol: "cpu")
            }
        }
        .dashboardCard()
    }
}

private struct ActivityHeatmapCard: View {
    let analytics: UsageAnalytics?

    private var cells: [HeatmapCell] {
        guard let analytics else { return [] }
        let values = Dictionary(uniqueKeysWithValues: analytics.daily.map { ($0.day, $0.totalTokens) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(16 * 7 - 1), to: today) ?? today
        return (0..<(16 * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let day = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
            return HeatmapCell(date: date, total: values[day] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("活跃度", trailing: analytics.map { "\($0.activeDays) active days" })
            if !cells.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(cells.chunked(into: 7).enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            ForEach(week) { cell in
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(activityColor(cell.total))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    Text("少")
                    ForEach(1...5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MacTheme.accent.opacity(Double(level) * 0.18))
                            .frame(width: 11, height: 11)
                    }
                    Text("多")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                EmptyCardLabel("暂无活跃度数据", symbol: "square.grid.3x3")
            }
        }
        .dashboardCard()
    }

    private func activityColor(_ total: Int64) -> Color {
        guard total > 0 else { return .white.opacity(0.055) }
        let maximum = max(cells.map(\.total).max() ?? 1, 1)
        return MacTheme.accent.opacity(0.2 + 0.8 * Double(total) / Double(maximum))
    }
}

private struct UsageHeroCard: View {
    let snapshot: UsageSnapshot
    @Binding var selectedPeriod: UsagePeriod

    private var providers: [ProviderSnapshot] {
        snapshot.providers
            .filter { $0.usage(for: selectedPeriod).isKnown && $0.usage(for: selectedPeriod).totalTokens > 0 }
            .sorted { $0.usage(for: selectedPeriod).totalTokens > $1.usage(for: selectedPeriod).totalTokens }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                periodPicker
                Spacer()
                Text(snapshot.generatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                Text("TOKEN 总数")
                    .font(.caption)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(totalText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        Capsule()
                            .fill(providerColor(index))
                            .frame(width: max(3, geometry.size.width * share(provider)))
                    }
                }
            }
            .frame(height: 7)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Array(providers.prefix(4).enumerated()), id: \.element.id) { index, provider in
                    HStack(spacing: 9) {
                        Circle().fill(providerColor(index)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName).fontWeight(.semibold)
                            Text(share(provider), format: .percent.precision(.fractionLength(1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(UsageFormatting.compactTokens(
                            provider.usage(for: selectedPeriod).totalTokens,
                            estimated: provider.isEstimated
                        ))
                            .monospacedDigit()
                    }
                    .padding(10)
                    .background(MacTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .dashboardCard()
    }

    private var periodPicker: some View {
        Picker("周期", selection: $selectedPeriod) {
            Text("日").tag(UsagePeriod.today)
            Text("周").tag(UsagePeriod.last7Days)
            Text("月").tag(UsagePeriod.last30Days)
            Text("累计").tag(UsagePeriod.recordedAllTime)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
    }

    private var total: Int64 { snapshot.totalTokens(for: selectedPeriod) }
    private var totalText: String {
        snapshot.hasKnownUsage(for: selectedPeriod)
            ? UsageFormatting.compactTokens(
                total,
                estimated: snapshot.hasEstimatedUsage(for: selectedPeriod)
            )
            : "—"
    }
    private func share(_ provider: ProviderSnapshot) -> Double {
        guard total > 0 else { return 0 }
        return Double(provider.usage(for: selectedPeriod).totalTokens) / Double(total)
    }
    private func providerColor(_ index: Int) -> Color {
        [MacTheme.accent, .cyan, .purple, .indigo, .mint][index % 5]
    }
}

private struct UsageTrendCard: View {
    let analytics: UsageAnalytics?
    @Environment(\.locale) private var locale
    @State private var granularity: UsageTrendGranularity = .day
    @State private var selectedTrendDate: Date?

    private var points: [TokenTrendPoint] {
        let values = analytics?.trend(groupedBy: granularity) ?? []
        switch granularity {
        case .day: return Array(values.suffix(30))
        case .week: return Array(values.suffix(26))
        case .month: return Array(values.suffix(12))
        }
    }

    private var datedPoints: [DatedTrendPoint] {
        points.compactMap(DatedTrendPoint.init)
    }

    private var selectedPoint: DatedTrendPoint? {
        guard let selectedTrendDate else { return nil }
        return datedPoints.min {
            abs($0.date.timeIntervalSince(selectedTrendDate))
                < abs($1.date.timeIntervalSince(selectedTrendDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("使用趋势", trailing: selectedPoint.map {
                    macTrendSelectionLabel($0, granularity: granularity, locale: locale)
                })
                Picker("分组", selection: $granularity) {
                    Text("日").tag(UsageTrendGranularity.day)
                    Text("周").tag(UsageTrendGranularity.week)
                    Text("月").tag(UsageTrendGranularity.month)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            if points.isEmpty {
                EmptyCardLabel("暂无趋势数据", symbol: "chart.xyaxis.line")
            } else {
                Chart(datedPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.source.totalTokens)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MacTheme.accent.opacity(0.28), MacTheme.accent.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.source.totalTokens)
                    )
                    .foregroundStyle(MacTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    if selectedPoint?.id == point.id {
                        RuleMark(x: .value("Selected", point.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Tokens", point.source.totalTokens)
                        )
                        .foregroundStyle(MacTheme.accent)
                        .symbolSize(60)
                    }
                }
                .chartXSelection(value: $selectedTrendDate)
                .chartXAxis {
                    AxisMarks(values: macTrendAxisDates(datedPoints.map(\.date), granularity)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    }
                }
                .chartXScale(range: .plotDimension(startPadding: 36, endPadding: 36))
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let tokens = value.as(Int64.self) {
                                Text(UsageFormatting.compactTokens(tokens))
                            }
                        }
                    }
                }
                .frame(minHeight: 190)
                TrendAxisLabels(
                    dates: datedPoints.map(\.date),
                    granularity: granularity,
                    locale: locale
                )
            }
        }
        .dashboardCard()
        .onChange(of: granularity) { selectedTrendDate = nil }
    }
}

private struct DailyUsageCard: View {
    let analytics: UsageAnalytics?

    private var days: [DailyTokenUsage] {
        Array((analytics?.daily ?? []).suffix(14).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle("每日明细", trailing: nil)
                .padding(.bottom, 10)
            HStack {
                Text("日期")
                Spacer()
                Text("TOKEN 总数")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            if days.isEmpty {
                EmptyCardLabel("暂无每日数据", symbol: "tablecells")
            } else {
                ForEach(days.prefix(8)) { day in
                    Divider().overlay(.white.opacity(0.05))
                    HStack {
                        Text(day.day)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageFormatting.compactTokens(day.totalTokens))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
        .dashboardCard()
    }
}

private struct LimitsDashboard: View {
    @Bindable var store: MacHubStore
    @Environment(\.locale) private var locale

    private var providers: [ProviderSnapshot] {
        store.snapshot.providers.filter { !$0.windows.isEmpty }
    }

    private var criticalCount: Int {
        providers.flatMap(\.windows).count { ($0.remainingPercent ?? 100) < 20 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DashboardHeader(
                    title: "限额",
                    subtitle: localizedAppString(store.statusText, locale: locale),
                    isRefreshing: store.isRefreshing,
                    refresh: { Task { await store.refresh() } }
                )

                HStack(spacing: 12) {
                    LimitSummaryMetric(title: "可用数据源", value: "\(providers.count)", color: MacTheme.accent)
                    LimitSummaryMetric(title: "额度窗口", value: "\(providers.flatMap(\.windows).count)", color: .green)
                    LimitSummaryMetric(title: "低于 20%", value: "\(criticalCount)", color: criticalCount > 0 ? .red : .green)
                }

                if providers.isEmpty {
                    ContentUnavailableView(
                        "暂无额度数据",
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text(
                            store.snapshot.providers.first(where: { $0.id == "codex" })?.detail
                                ?? String(localized: "尚未获取到 Codex 额度数据。")
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .dashboardCard()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(providers) { provider in
                            ProviderLimitCard(
                                provider: provider,
                                refreshedAt: store.snapshot.generatedAt
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct LimitSummaryMetric: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color.opacity(0.18)).frame(width: 38, height: 38)
                .overlay(Circle().fill(color).frame(width: 8, height: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .dashboardCard()
    }
}

private struct ProviderLimitCard: View {
    let provider: ProviderSnapshot
    let refreshedAt: Date
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MacTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.headline)
                    ProviderCollectionStatusLabel(
                        provider: provider,
                        refreshedAt: refreshedAt
                    )
                        .font(.caption)
                }
                Spacer()
            }
            ForEach(provider.windows) { window in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(
                            verbatim: QuotaResetCountdown.localizedLabel(for: window.label, locale: locale)
                        )
                        .fontWeight(.medium)
                        Spacer()
                        if let remainingPercent = window.remainingPercent {
                            Text(verbatim: "\(Int(remainingPercent.rounded()))% \(localizedAppString("剩余", locale: locale))")
                                .monospacedDigit()
                        } else {
                            Text(verbatim: "—")
                        }
                    }
                    ProgressView(value: window.remainingPercent ?? 0, total: 100)
                        .tint(MacTheme.quotaColor(remaining: window.remainingPercent))
                    if let resetAt = window.resetAt {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            HStack {
                                Text("距离重置")
                                Spacer()
                                Text(
                                    verbatim: QuotaResetCountdown.text(
                                        until: resetAt,
                                        now: context.date,
                                        locale: locale
                                    ) ?? "—"
                                )
                                .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }
}

private struct SettingsDashboard: View {
    @Bindable var store: MacHubStore
    @ObservedObject var updateController: MacUpdateController
    @Binding var languageIdentifier: String
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardHeader(
                title: "设置",
                subtitle: localizedAppString("采集、同步与设备", locale: locale),
                isRefreshing: store.isRefreshing,
                refresh: { Task { await store.refresh() } }
            )
            MacSettingsView(
                store: store,
                embedded: true,
                updateController: updateController,
                languageIdentifier: $languageIdentifier
            )
        }
        .padding(20)
    }
}

private struct CardTitle: View {
    let title: LocalizedStringKey
    let trailing: String?

    init(_ title: LocalizedStringKey, trailing: String?) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyCardLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    init(_ title: LocalizedStringKey, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70)
    }
}

private struct HeatmapCell: Identifiable {
    let date: Date
    let total: Int64
    var id: Date { date }
}

private extension View {
    func dashboardCard() -> some View {
        self
            .padding(16)
            .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MacTheme.border, lineWidth: 1)
            }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
