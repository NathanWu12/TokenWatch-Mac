import Domain
import MacProviderAdapters
import Observation
import ServiceManagement
import SwiftUI

struct MacSettingsView: View {
    @Bindable var store: MacHubStore
    let embedded: Bool
    @State private var launchAtLogin = LaunchAtLoginController()
    @Binding var languageIdentifier: String
    @Environment(\.locale) private var locale

    init(
        store: MacHubStore,
        embedded: Bool = false,
        languageIdentifier: Binding<String>
    ) {
        self.store = store
        self.embedded = embedded
        _languageIdentifier = languageIdentifier
    }

    var body: some View {
        Form {
            Section("语言") {
                Picker("应用语言", selection: $languageIdentifier) {
                    ForEach(SupportedAppLanguage.allCases) { language in
                        Text(verbatim: language.nativeDisplayName)
                            .tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("主窗口、设置和菜单栏窗口会使用同一种语言。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI 客户端") {
                ForEach(LocalAIClient.allCases) { client in
                    Toggle(
                        isOn: Binding(
                            get: { store.isClientEnabled(client) },
                            set: { store.setClientEnabled(client, enabled: $0) }
                        )
                    ) {
                        HStack(spacing: 8) {
                            Text(verbatim: client.displayName)
                            if store.isClientDetected(client) {
                                Label("已检测", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("未检测到")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("重新扫描") {
                        store.rescanLocalAIClients()
                        Task { await store.refresh() }
                    }
                    Spacer()
                    Text("自动检查受支持客户端的标准本地数据目录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Codex、Claude Code 和 OpenCode 使用本地用量计数与最少必要元数据；Codex 还会在内存中使用现有登录令牌发起只读额度请求。Antigravity 因本地不提供权威 token 计数，会在内存中临时读取 transcript 文本进行估算并立即丢弃；TokenWatch 不会缓存或同步提示词、回复、工具参数、凭证或完整项目路径。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刷新") {
                Stepper(
                    value: Binding(
                        get: { store.refreshIntervalSeconds },
                        set: { store.setRefreshIntervalSeconds($0) }
                    ),
                    in: 10...3_600,
                    step: 1
                ) {
                    HStack(spacing: 3) {
                        Text("自动刷新间隔")
                        Spacer()
                        Text("\(store.refreshIntervalSeconds)")
                            .monospacedDigit()
                        Text("秒")
                    }
                }
                .accessibilityLabel("Automatic refresh interval")
                .accessibilityValue("\(store.refreshIntervalSeconds) seconds")
                Text("可按 1 秒调整，最短 10 秒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("立即刷新") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
            }

            Section("启动") {
                Toggle(
                    "开机时启动 TokenWatch",
                    isOn: Binding(
                        get: { launchAtLogin.isRequested },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .disabled(launchAtLogin.isChanging)

                if launchAtLogin.requiresApproval {
                    Label(
                        "需要在系统设置的登录项中批准",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    Button("打开登录项设置") {
                        launchAtLogin.openSystemSettings()
                    }
                } else {
                    Text("启用后，登录 Mac 时会自动启动菜单栏应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("iPhone 与 Apple Watch") {
                LabeledContent("配对码") {
                    Text(store.peerPublisher.pairingCode)
                        .font(.title2.monospacedDigit().bold())
                        .privacySensitive()
                }
                LabeledContent("连接状态") {
                    Text(localizedAppString(store.peerPublisher.stateText, locale: locale))
                }
                LabeledContent("远程同步") {
                    Text(localizedAppString(store.peerPublisher.remoteStatusText, locale: locale))
                }
                LabeledContent("Mac 指纹") {
                    Text(store.peerPublisher.publicKeyFingerprint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                HStack {
                    Button("发送当前数据") {
                        store.publishCurrentSnapshot()
                    }
                    Button("更新配对码", role: .destructive) {
                        store.peerPublisher.rotatePairingCode()
                    }
                }
                if !store.peerPublisher.pairedDevices.isEmpty {
                    ForEach(store.peerPublisher.pairedDevices, id: \.deviceId) { device in
                        HStack {
                            Label(device.displayName, systemImage: "iphone")
                            Spacer()
                            Button("撤销", role: .destructive) {
                                store.peerPublisher.revoke(deviceId: device.deviceId)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(
            maxWidth: embedded ? 760 : 560,
            minHeight: embedded ? 0 : 480,
            maxHeight: embedded ? .infinity : 480
        )
        .background {
            if embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacTheme.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MacTheme.border, lineWidth: 1)
                }
            }
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }


}

@MainActor
@Observable
private final class LaunchAtLoginController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var isChanging = false
    private(set) var lastError: String?

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = String(
                localized: "无法更新开机启动设置：\(error.localizedDescription)"
            )
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
