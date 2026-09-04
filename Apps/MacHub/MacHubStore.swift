import CoreServices
import Domain
import Foundation
import Observation
import OSLog
import MacProviderAdapters
import SyncProtocol

@MainActor
@Observable
final class MacHubStore {
    private static let logger = Logger(
        subsystem: "com.nathanwu.TokenWatch",
        category: "NativeCollection"
    )
    private static let signposter = OSSignposter(logger: logger)
    private(set) var snapshot: UsageSnapshot
    private(set) var isRefreshing = false
    private(set) var statusText: String.LocalizationValue = "等待首次刷新"
    private(set) var lastError: String?
    private(set) var codexDirectoryURL: URL?
    private(set) var detectedClientLocations: [LocalAIClientLocation] = []
    private(set) var enabledClients: Set<LocalAIClient>
    private(set) var settingsNavigationRequest = 0
    private(set) var refreshIntervalSeconds: Int
    private(set) var deviceSyncEnabled: Bool
    @ObservationIgnored
    let peerPublisher: MacPeerPublisher
    @ObservationIgnored
    private let clientDiscovery = LocalAIClientDiscovery()
    @ObservationIgnored
    private let codexCollector = CodexLogCollector()
    @ObservationIgnored
    private let codexQuotaCollector = CodexQuotaCollector()
    @ObservationIgnored
    private let claudeCollector = ClaudeCodeLogCollector()
    @ObservationIgnored
    private let antigravityCollector = AntigravityLogCollector()
    @ObservationIgnored
    private let antigravityQuotaCollector = AntigravityQuotaCollector()
    @ObservationIgnored
    private let openCodeCollector = OpenCodeLogCollector()
    @ObservationIgnored
    private let resetDetector = QuotaResetDetector()
    @ObservationIgnored
    private let cache = SnapshotFileCache(filename: "mac-snapshot.json")
    @ObservationIgnored
    private let resetStateCache = QuotaResetStateFileCache()
    @ObservationIgnored
    private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored
    private var fileChangeRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var usageChangeMonitor: LocalUsageChangeMonitor?
    @ObservationIgnored
    private var consecutiveRefreshFailures = 0
    @ObservationIgnored
    private var lastClientDiscoveryAt = Date.distantPast
    private static let refreshIntervalKey = "MacRefreshIntervalSeconds"
    private static let legacyRefreshIntervalKey = "MacRefreshIntervalMinutes"
    private static let codexBookmarkKey = "CodexDataDirectoryBookmark"
    private static let codexQuotaCachedAtKey = "CodexQuotaCachedAt"
    private static let antigravityQuotaCachedAtKey = "AntigravityQuotaCachedAt"
    private static let enabledClientsKey = "EnabledLocalAIClients"
    private static let deviceSyncEnabledKey = "DeviceSyncEnabled"
    private static let clientDiscoveryInterval: TimeInterval = 5 * 60
    private static let quotaRefreshInterval: TimeInterval = 5 * 60

    init() {
        let defaults = UserDefaults.standard
        enabledClients = LocalAIClient.enabledClients(
            fromStoredRawValues: defaults.stringArray(forKey: Self.enabledClientsKey)
        )
        let initialDeviceSyncEnabled = defaults.object(forKey: Self.deviceSyncEnabledKey) != nil
            ? defaults.bool(forKey: Self.deviceSyncEnabledKey)
            : AppPreferenceDefaults.crossDeviceSyncEnabled
        deviceSyncEnabled = initialDeviceSyncEnabled
        let initialRefreshIntervalSeconds: Int
        if defaults.object(forKey: Self.refreshIntervalKey) != nil {
            initialRefreshIntervalSeconds = min(
                3_600,
                max(10, defaults.integer(forKey: Self.refreshIntervalKey))
            )
        } else if defaults.object(forKey: Self.legacyRefreshIntervalKey) != nil {
            initialRefreshIntervalSeconds = min(
                3_600,
                max(10, defaults.integer(forKey: Self.legacyRefreshIntervalKey) * 60)
            )
        } else {
            initialRefreshIntervalSeconds = 60
        }
        refreshIntervalSeconds = initialRefreshIntervalSeconds
        defaults.set(initialRefreshIntervalSeconds, forKey: Self.refreshIntervalKey)
        let discovered = Self.includingLegacyCodexLocation(
            clientDiscovery.discover()
        )
        detectedClientLocations = discovered
        codexDirectoryURL = discovered.first(where: { $0.client == .codex })?.rootDirectory
        lastClientDiscoveryAt = Date()
        snapshot = UsageSnapshot(generatedAt: Date(), providers: [])
        peerPublisher = MacPeerPublisher(enabled: initialDeviceSyncEnabled)
        if let cached = try? cache.load(), Self.isNativeLocalSnapshot(cached) {
            let now = Date()
            let cachedAt = UserDefaults.standard.object(
                forKey: Self.codexQuotaCachedAtKey
            ) as? Date
            let cachedWindows = cached.providers.first(where: { $0.id == "codex" })?.windows ?? []
            let usableWindows = CodexQuotaCollector.usableCachedWindows(
                cachedWindows,
                cachedAt: cachedAt,
                now: now
            )
            snapshot = Self.retainingEnabledClients(
                Self.applyingQuota(
                    usableWindows,
                    providerID: "codex",
                    detail: usableWindows.isEmpty
                        ? cached.providers.first?.detail
                        : String(localized: "显示上次有效额度。"),
                    forceStale: !usableWindows.isEmpty,
                    to: cached.refreshed(at: now)
                ),
                enabledClients: enabledClients
            )
            // Persist the filtered cache immediately so disabled-provider data does not
            // remain on disk while a full refresh is still running.
            try? cache.save(snapshot)
            statusText = "已载入本地缓存"
            peerPublisher.publish(snapshot)
        } else {
            statusText = detectedClientLocations.isEmpty
                ? "未检测到支持的 AI 客户端"
                : "等待首次刷新"
        }
#if DEBUG
        if let fixtureID = Self.resetEventFixtureID() {
            let now = Date()
            let event = QuotaResetEvent(
                id: fixtureID,
                providerID: "codex",
                providerName: "Codex",
                windowID: "device-validation",
                windowLabel: "真机验收",
                detectedAt: now,
                expiresAt: now.addingTimeInterval(15 * 60),
                previousUsedPercent: 80,
                currentUsedPercent: 1,
                previousResetAt: now.addingTimeInterval(-5 * 60 * 60),
                currentResetAt: now.addingTimeInterval(5 * 60 * 60)
            )
            snapshot = Self.attachingResetEvents([event], to: snapshot)
            peerPublisher.publish(snapshot)
            Self.logger.notice("Published synthetic quota reset event for device validation")
        }
#endif
        peerPublisher.onAuthenticatedPeerConnected = { [weak self] in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        configureUsageChangeMonitor()
        startAutomaticRefresh()
    }

    isolated deinit {
        fileChangeRefreshTask?.cancel()
        refreshLoop?.cancel()
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return false }
        let signpostID = Self.signposter.makeSignpostID()
        let signpostState = Self.signposter.beginInterval("NativeRefresh", id: signpostID)
        defer { Self.signposter.endInterval("NativeRefresh", signpostState) }
        rescanLocalAIClientsIfNeeded()
        guard !enabledDetectedClientLocations.isEmpty else {
            lastError = String(localized: "没有启用且可用的 AI 客户端")
            statusText = "没有启用且可用的 AI 客户端"
            return false
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await fetchNativeLocalSnapshot()
            let now = Date()
            var resetState = (try? resetStateCache.load()) ?? .init()
            if fetched.codexQuotaState == .live {
                let result = resetDetector.evaluate(
                    snapshot: fetched.snapshot,
                    state: resetState,
                    now: now
                )
                resetState = result.state
                if !result.events.isEmpty {
                    Self.logger.info(
                        "Detected quota reset; count=\(result.events.count, privacy: .public)"
                    )
                }
                try resetStateCache.save(resetState)
            }
            let outgoing = Self.attachingResetEvents(
                resetState.recentEvents.filter { $0.expiresAt > now },
                to: fetched.snapshot
            )
            let contentChanged = !snapshot.hasSameContent(as: outgoing)
            snapshot = outgoing
            if contentChanged {
                try cache.save(outgoing)
                peerPublisher.publish(outgoing)
            }
            lastError = nil
            switch fetched.codexQuotaState {
            case .live:
                statusText = "用量与额度数据已更新"
            case .cached:
                statusText = "用量已更新 · 显示上次额度"
            case .unavailable:
                statusText = "用量已更新 · 暂无额度数据"
            }
            consecutiveRefreshFailures = 0
            Self.logger.info(
                "Native snapshot refreshed; providers=\(outgoing.providers.count, privacy: .public); codexQuota=\(String(describing: fetched.codexQuotaState), privacy: .public)"
            )
            return true
        } catch {
            snapshot = snapshot.refreshed(at: Date())
            lastError = Self.userMessage(for: error)
            statusText = "刷新失败 · 显示最后已知数据"
            consecutiveRefreshFailures += 1
            Self.logger.error(
                "Native refresh failed; attempt=\(self.consecutiveRefreshFailures, privacy: .public)"
            )
            return false
        }
    }

    func setRefreshIntervalSeconds(_ value: Int) {
        let clampedValue = min(3_600, max(10, value))
        guard clampedValue != refreshIntervalSeconds else { return }
        refreshIntervalSeconds = clampedValue
        UserDefaults.standard.set(clampedValue, forKey: Self.refreshIntervalKey)
    }

    func refreshAfterActivation() {
        Task { await refresh() }
    }

    func requestSettingsNavigation() {
        settingsNavigationRequest &+= 1
    }


    func rescanLocalAIClients() {
        let discovered = Self.includingLegacyCodexLocation(
            clientDiscovery.discover()
        )
        detectedClientLocations = discovered
        codexDirectoryURL = discovered.first(where: { $0.client == .codex })?.rootDirectory
        lastClientDiscoveryAt = Date()
        configureUsageChangeMonitor()
    }

    private func configureUsageChangeMonitor() {
        let paths = enabledDetectedClientLocations.map(\.rootDirectory)
        usageChangeMonitor = LocalUsageChangeMonitor(paths: paths) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefreshAfterFileChange()
            }
        }
    }

    private func scheduleRefreshAfterFileChange() {
        fileChangeRefreshTask?.cancel()
        fileChangeRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isRefreshing {
                    _ = await self.refresh()
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func rescanLocalAIClientsIfNeeded(now: Date = Date()) {
        guard now.timeIntervalSince(lastClientDiscoveryAt) >= Self.clientDiscoveryInterval
                || now < lastClientDiscoveryAt else {
            return
        }
        rescanLocalAIClients()
    }

    var enabledDetectedClientLocations: [LocalAIClientLocation] {
        detectedClientLocations.filter { enabledClients.contains($0.client) }
    }

    func isClientDetected(_ client: LocalAIClient) -> Bool {
        detectedClientLocations.contains { $0.client == client }
    }

    func isClientEnabled(_ client: LocalAIClient) -> Bool {
        enabledClients.contains(client)
    }

    func setClientEnabled(_ client: LocalAIClient, enabled: Bool) {
        if enabled {
            enabledClients.insert(client)
        } else {
            enabledClients.remove(client)
        }
        UserDefaults.standard.set(
            enabledClients.map(\.rawValue).sorted(),
            forKey: Self.enabledClientsKey
        )
        if client == .codex {
            UserDefaults.standard.removeObject(forKey: Self.codexQuotaCachedAtKey)
            try? resetStateCache.save(.init())
        }
        if client == .antigravity {
            UserDefaults.standard.removeObject(forKey: Self.antigravityQuotaCachedAtKey)
        }
        configureUsageChangeMonitor()

        // Hide disabled-provider values immediately. Global analytics are rebuilt on
        // refresh because their merged form cannot safely subtract one provider.
        snapshot = Self.retainingEnabledClients(snapshot, enabledClients: enabledClients)
        try? cache.save(snapshot)
        peerPublisher.publish(snapshot)
        refreshAfterActivation()
    }

    func publishCurrentSnapshot() {
        guard deviceSyncEnabled else {
            statusText = "iPhone 与 Apple Watch 数据传输已关闭"
            return
        }
        guard !snapshot.providers.isEmpty else {
            statusText = "暂无可推送的真实数据"
            return
        }
        peerPublisher.publish(snapshot.refreshed(at: Date()))
        statusText = "已向已配对 iPhone 推送"
    }

    func setDeviceSyncEnabled(_ enabled: Bool) {
        guard deviceSyncEnabled != enabled else { return }
        deviceSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.deviceSyncEnabledKey)
        peerPublisher.setEnabled(enabled)
    }

    private func startAutomaticRefresh() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let succeeded = await refresh()
                let configuredDelay = TimeInterval(refreshIntervalSeconds)
                let delay = succeeded
                    ? configuredDelay
                    : RetrySchedule.delay(
                        attempt: consecutiveRefreshFailures,
                        baseDelay: 15,
                        maximumDelay: 15 * 60,
                        jitterFraction: 0.2,
                        jitterUnit: Double.random(in: 0...1)
                    )
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }
    }

    private static func userMessage(for error: Error) -> String {
        if error as? LocalCollectionError == .noReadableProviderData {
            return String(localized: "已检测到 AI 客户端，但无法读取本地用量数据。")
        }
        return "用量数据暂不可用：\(error.localizedDescription)"
    }

    private func fetchNativeLocalSnapshot() async throws -> NativeLocalFetch {
        let now = Date()
        let collectorCacheDirectory = Self.collectorCacheDirectory()
        var jobs: [LocalUsageCollectionJob] = []
        var codexURL: URL?

        if isClientEnabled(.codex), let url = codexDirectoryURL {
            codexURL = url
            jobs.append(.codex(codexCollector, url, collectorCacheDirectory))
        }
        if isClientEnabled(.claudeCode),
           let location = detectedClientLocations.first(where: { $0.client == .claudeCode }) {
            jobs.append(.claude(claudeCollector, location.rootDirectory))
        }
        let antigravityRoots = isClientEnabled(.antigravity)
            ? detectedClientLocations
                .filter { $0.client == .antigravity }
                .map(\.rootDirectory)
            : []
        if !antigravityRoots.isEmpty {
            jobs.append(.antigravity(antigravityCollector, antigravityRoots))
        }
        if isClientEnabled(.openCode),
           let location = detectedClientLocations.first(where: { $0.client == .openCode }) {
            jobs.append(.openCode(openCodeCollector, location.rootDirectory))
        }

        let collectionID = Self.signposter.makeSignpostID()
        let collectionState = Self.signposter.beginInterval("LocalUsageCollection", id: collectionID)
        let results = await runLocalUsageCollectionJobs(jobs, now: now, maximumConcurrency: 2)
        Self.signposter.endInterval("LocalUsageCollection", collectionState)
        var usageByClient: [LocalAIClient: UsageSnapshot] = [:]
        for result in results {
            switch result {
            case let .success(client, usageSnapshot):
                usageByClient[client] = usageSnapshot
            case let .failure(client):
                Self.logger.error(
                    "Local collection failed; provider=\(client.rawValue, privacy: .public); continuing"
                )
            }
        }

        var snapshots: [UsageSnapshot] = []
        var codexQuotaState: NativeLocalFetch.QuotaState = .unavailable
        if let usageSnapshot = usageByClient[.codex], let codexURL {
            let result = await attachCodexQuota(to: usageSnapshot, codexDirectory: codexURL, now: now)
            snapshots.append(result.snapshot)
            codexQuotaState = result.state
        }
        if let usageSnapshot = usageByClient[.claudeCode] {
            snapshots.append(usageSnapshot)
        }
        if let usageSnapshot = usageByClient[.antigravity] {
            snapshots.append(await attachAntigravityQuota(to: usageSnapshot, now: now))
        }
        if let usageSnapshot = usageByClient[.openCode] {
            snapshots.append(usageSnapshot)
        }

        guard !snapshots.isEmpty else {
            throw LocalCollectionError.noReadableProviderData
        }
        return NativeLocalFetch(
            snapshot: Self.retainingEnabledClients(
                LocalUsageSnapshotMerger.merge(snapshots, generatedAt: now),
                enabledClients: enabledClients
            ),
            codexQuotaState: isClientEnabled(.codex) ? codexQuotaState : .unavailable
        )
    }

    private func attachCodexQuota(
        to usageSnapshot: UsageSnapshot,
        codexDirectory: URL,
        now: Date
    ) async -> (snapshot: UsageSnapshot, state: NativeLocalFetch.QuotaState) {
        let cachedWindows = cachedQuotaWindows(at: now)
        guard Self.quotaRefreshDue(key: Self.codexQuotaCachedAtKey, now: now) else {
            return (
                Self.applyingQuota(
                    cachedWindows,
                    providerID: "codex",
                    detail: nil,
                    to: usageSnapshot
                ),
                cachedWindows.isEmpty ? .unavailable : .cached
            )
        }

        do {
            let windows = try await codexQuotaCollector.fetchWindows(
                codexDirectory: codexDirectory,
                now: now
            )
            if !windows.isEmpty {
                UserDefaults.standard.set(now, forKey: Self.codexQuotaCachedAtKey)
            }
            return (
                Self.applyingQuota(
                    windows,
                    providerID: "codex",
                    detail: windows.isEmpty
                        ? String(localized: "当前账号未返回可展示的 Codex 额度窗口。")
                        : nil,
                    to: usageSnapshot
                ),
                windows.isEmpty ? .unavailable : .live
            )
        } catch {
            return (
                Self.applyingQuota(
                    cachedWindows,
                    providerID: "codex",
                    detail: Self.quotaMessage(for: error, hasFallback: !cachedWindows.isEmpty),
                    forceStale: !cachedWindows.isEmpty,
                    to: usageSnapshot
                ),
                cachedWindows.isEmpty ? .unavailable : .cached
            )
        }
    }

    private func attachAntigravityQuota(
        to usageSnapshot: UsageSnapshot,
        now: Date
    ) async -> UsageSnapshot {
        let cachedWindows = cachedAntigravityQuotaWindows(at: now)
        let cachedDetail = cachedAntigravityDetail(
            fallback: usageSnapshot.providers.first?.detail
        )
        guard Self.quotaRefreshDue(key: Self.antigravityQuotaCachedAtKey, now: now) else {
            return Self.applyingQuota(
                cachedWindows,
                providerID: "antigravity",
                detail: cachedDetail,
                to: usageSnapshot
            )
        }

        do {
            let quota = try await antigravityQuotaCollector.fetchQuota()
            if !quota.windows.isEmpty {
                UserDefaults.standard.set(now, forKey: Self.antigravityQuotaCachedAtKey)
            }
            return Self.applyingQuota(
                quota.windows,
                providerID: "antigravity",
                detail: Self.antigravityDetail(
                    planName: quota.planName,
                    fallback: usageSnapshot.providers.first?.detail
                ),
                planName: quota.planName,
                to: usageSnapshot
            )
        } catch {
            Self.logger.info(
                "Antigravity quota service unavailable; using valid cached windows when possible"
            )
            return Self.applyingQuota(
                cachedWindows,
                providerID: "antigravity",
                detail: cachedDetail,
                forceStale: !cachedWindows.isEmpty,
                to: usageSnapshot
            )
        }
    }

    private func cachedAntigravityQuotaWindows(at now: Date) -> [QuotaWindow] {
        snapshot.providers
            .first(where: { $0.id == "antigravity" })?
            .windows
            .filter { window in
                guard let resetAt = window.resetAt else { return true }
                return resetAt > now
            } ?? []
    }

    private func cachedAntigravityDetail(fallback: String?) -> String? {
        snapshot.providers.first(where: { $0.id == "antigravity" })?.detail ?? fallback
    }

    private static func antigravityDetail(planName: String?, fallback: String?) -> String? {
        guard let planName, !planName.isEmpty else { return fallback }
        if let fallback, !fallback.isEmpty {
            return "Plan: \(planName) · \(fallback)"
        }
        return "Plan: \(planName)"
    }

    private func cachedQuotaWindows(at now: Date) -> [QuotaWindow] {
        let cachedAt = UserDefaults.standard.object(
            forKey: Self.codexQuotaCachedAtKey
        ) as? Date
        let windows = snapshot.providers.first(where: { $0.id == "codex" })?.windows ?? []
        return CodexQuotaCollector.usableCachedWindows(
            windows,
            cachedAt: cachedAt,
            now: now
        )
    }

    private static func quotaRefreshDue(key: String, now: Date) -> Bool {
        guard let cachedAt = UserDefaults.standard.object(forKey: key) as? Date else {
            return true
        }
        let age = now.timeIntervalSince(cachedAt)
        return age < 0 || age >= quotaRefreshInterval
    }

    private static func collectorCacheDirectory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base
            .appending(path: "TokenWatch", directoryHint: .isDirectory)
            .appending(path: "CollectorCache", directoryHint: .isDirectory)
    }

    private static func applyingQuota(
        _ windows: [QuotaWindow],
        providerID: String,
        detail: String?,
        planName: String? = nil,
        forceStale: Bool = false,
        to snapshot: UsageSnapshot
    ) -> UsageSnapshot {
        UsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: snapshot.generatedAt,
            providers: snapshot.providers.map { provider in
                guard provider.id == providerID else { return provider }
                return ProviderSnapshot(
                    id: provider.id,
                    displayName: provider.displayName,
                    sourceUpdatedAt: provider.sourceUpdatedAt,
                    freshness: forceStale ? .stale : provider.freshness,
                    usage: provider.usage,
                    periods: provider.periods,
                    windows: windows,
                    availability: provider.availability,
                    detail: detail ?? provider.detail,
                    sourceKind: provider.sourceKind,
                    planName: planName ?? provider.planName,
                    isEstimated: provider.isEstimated
                )
            },
            analytics: snapshot.analytics,
            resetEvents: snapshot.resetEvents
        )
    }

    private static func retainingEnabledClients(
        _ snapshot: UsageSnapshot,
        enabledClients: Set<LocalAIClient>
    ) -> UsageSnapshot {
        let enabledIDs = Set(enabledClients.map(\.rawValue))
        let providers = snapshot.providers.filter { enabledIDs.contains($0.id) }
        let resetEvents = snapshot.resetEvents.filter { enabledIDs.contains($0.providerID) }
        let providerIDsBefore = Set(snapshot.providers.map(\.id))
        let providerIDsAfter = Set(providers.map(\.id))
        let analytics = providerIDsBefore == providerIDsAfter ? snapshot.analytics : nil
        return UsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: snapshot.generatedAt,
            providers: providers,
            analytics: analytics,
            resetEvents: resetEvents,
            mode: snapshot.mode
        )
    }

    private static func attachingResetEvents(
        _ resetEvents: [QuotaResetEvent],
        to snapshot: UsageSnapshot
    ) -> UsageSnapshot {
        let newestEventDate = resetEvents.map(\.detectedAt).max() ?? snapshot.generatedAt
        return UsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: max(snapshot.generatedAt, newestEventDate),
            providers: snapshot.providers,
            analytics: snapshot.analytics,
            resetEvents: resetEvents
        )
    }

    private static func quotaMessage(for error: Error, hasFallback: Bool) -> String {
        if hasFallback {
            return String(localized: "额度接口暂不可用，显示上次有效额度。")
        }
        switch error as? CodexQuotaCollector.CollectorError {
        case .notConfigured, .invalidAuthenticationFile:
            return String(localized: "未找到有效的 Codex 登录信息，请运行 codex 登录。")
        case .authenticationRequired:
            return String(localized: "Codex 认证已失效，请运行 codex 重新登录。")
        case .unavailableForAccount:
            return String(localized: "当前 Codex 账号暂不提供额度数据。")
        case .rateLimited:
            return String(localized: "Codex 额度请求过于频繁，请稍后重试。")
        default:
            return String(localized: "Codex 额度接口暂不可用，本地 token 统计不受影响。")
        }
    }

    private static func isNativeLocalSnapshot(_ snapshot: UsageSnapshot) -> Bool {
        let supported = Set(LocalAIClient.allCases.map(\.rawValue))
        return !snapshot.providers.isEmpty && snapshot.providers.allSatisfy {
            supported.contains($0.id)
        }
    }

    private static func includingLegacyCodexLocation(
        _ discovered: [LocalAIClientLocation]
    ) -> [LocalAIClientLocation] {
        guard let legacy = restoreCodexDirectoryBookmark(),
              FileManager.default.isReadableFile(atPath: legacy.path) else {
            return discovered
        }
        let location = LocalAIClientLocation(client: .codex, rootDirectory: legacy)
        guard !discovered.contains(where: { $0.id == location.id }) else {
            return discovered
        }
        return [location] + discovered
    }

    private static func restoreCodexDirectoryBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: codexBookmarkKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale,
           let refreshed = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: [.isDirectoryKey],
               relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: codexBookmarkKey)
        }
        return url
    }

#if DEBUG
    private static func resetEventFixtureID() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-TokenWatchResetEventFixture"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        let value = arguments[flagIndex + 1]
        guard !value.isEmpty else { return nil }
        return "device-validation." + value
    }
#endif
}

private enum LocalUsageCollectionJob: Sendable {
    case codex(CodexLogCollector, URL, URL?)
    case claude(ClaudeCodeLogCollector, URL)
    case antigravity(AntigravityLogCollector, [URL])
    case openCode(OpenCodeLogCollector, URL)

    func run(now: Date) async -> LocalUsageCollectionResult {
        switch self {
        case let .codex(collector, directory, cacheDirectory):
            do {
                return .success(
                    .codex,
                    try await collector.fetchSnapshot(
                        codexDirectory: directory,
                        now: now,
                        cacheDirectory: cacheDirectory
                    )
                )
            } catch {
                return .failure(.codex)
            }
        case let .claude(collector, directory):
            do {
                return .success(
                    .claudeCode,
                    try await collector.fetchSnapshot(claudeDirectory: directory, now: now)
                )
            } catch {
                return .failure(.claudeCode)
            }
        case let .antigravity(collector, directories):
            do {
                return .success(
                    .antigravity,
                    try await collector.fetchSnapshot(
                        antigravityDirectories: directories,
                        now: now
                    )
                )
            } catch {
                return .failure(.antigravity)
            }
        case let .openCode(collector, directory):
            do {
                return .success(
                    .openCode,
                    try await collector.fetchSnapshot(openCodeDirectory: directory, now: now)
                )
            } catch {
                return .failure(.openCode)
            }
        }
    }
}

private enum LocalUsageCollectionResult: Sendable {
    case success(LocalAIClient, UsageSnapshot)
    case failure(LocalAIClient)
}

private func runLocalUsageCollectionJobs(
    _ jobs: [LocalUsageCollectionJob],
    now: Date,
    maximumConcurrency: Int
) async -> [LocalUsageCollectionResult] {
    guard !jobs.isEmpty else { return [] }
    let limit = max(1, min(maximumConcurrency, jobs.count))
    return await withTaskGroup(of: LocalUsageCollectionResult.self) { group in
        var nextIndex = 0
        for _ in 0..<limit {
            let job = jobs[nextIndex]
            nextIndex += 1
            group.addTask { await job.run(now: now) }
        }

        var results: [LocalUsageCollectionResult] = []
        results.reserveCapacity(jobs.count)
        while let result = await group.next() {
            results.append(result)
            if nextIndex < jobs.count {
                let job = jobs[nextIndex]
                nextIndex += 1
                group.addTask { await job.run(now: now) }
            }
        }
        return results
    }
}

private enum LocalCollectionError: Error, Equatable {
    case noReadableProviderData
}

private struct NativeLocalFetch: Sendable {
    enum QuotaState: Equatable, Sendable {
        case live
        case cached
        case unavailable
    }

    let snapshot: UsageSnapshot
    let codexQuotaState: QuotaState
}

private struct QuotaResetStateFileCache: Sendable {
    private let filename = "quota-reset-state.json"

    func save(_ state: QuotaResetDetectionState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let url = try fileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func load() throws -> QuotaResetDetectionState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            QuotaResetDetectionState.self,
            from: Data(contentsOf: try fileURL())
        )
    }

    private func fileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "TokenWatch", directoryHint: .isDirectory)
            .appending(path: filename)
    }
}

struct SnapshotFileCache: Sendable {
    let filename: String

    func save(_ snapshot: UsageSnapshot) throws {
        let data = try SnapshotCodec.encode(snapshot)
        let url = try fileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> UsageSnapshot {
        try SnapshotCodec.decode(Data(contentsOf: try fileURL()))
    }

    private func fileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "TokenWatch", directoryHint: .isDirectory)
            .appending(path: filename)
    }
}

/// Lightweight recursive watcher for the small whitelist of enabled provider roots.
/// It only signals that local usage may have changed; collectors remain the source
/// of truth and still validate their manifests before reading any content.
final class LocalUsageChangeMonitor {
    private final class CallbackBox {
        let handler: @Sendable () -> Void

        init(handler: @escaping @Sendable () -> Void) {
            self.handler = handler
        }
    }

    private let callbackBox: CallbackBox
    private let queue = DispatchQueue(label: "com.nathanwu.TokenWatch.LocalUsageChanges", qos: .utility)
    private var stream: FSEventStreamRef?

    init?(paths: [URL], handler: @escaping @Sendable () -> Void) {
        let normalized = Array(Set(paths.map { $0.standardizedFileURL.path })).sorted()
        guard !normalized.isEmpty else { return nil }
        callbackBox = CallbackBox(handler: handler)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<CallbackBox>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, eventCount, _, _, _ in
            guard eventCount > 0, let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            box.handler()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            normalized as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.75,
            flags
        ) else {
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
