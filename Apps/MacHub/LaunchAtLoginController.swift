import Domain
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private static let preferenceKey = "LaunchAtLoginEnabled"

    @ObservationIgnored
    private let defaults: UserDefaults
    private(set) var status = SMAppService.mainApp.status
    private(set) var isChanging = false
    private(set) var lastError: String?
    @ObservationIgnored
    private var requestedEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        requestedEnabled = Self.preferredValue(defaults: defaults)
        reconcileRequestedState()
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    static func applyDefaultPreference(defaults: UserDefaults = .standard) {
        let requested = preferredValue(defaults: defaults)
        try? apply(requested)
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        isChanging = true
        requestedEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        defer { isChanging = false }

        do {
            try Self.apply(enabled)
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

    private func reconcileRequestedState() {
        do {
            try Self.apply(requestedEnabled)
            lastError = nil
        } catch {
            lastError = String(
                localized: "无法更新开机启动设置：\(error.localizedDescription)"
            )
        }
        refresh()
    }

    private static func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .notRegistered {
                try service.register()
            }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
    }

    private static func preferredValue(defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: preferenceKey) == nil {
            defaults.set(AppPreferenceDefaults.launchAtLoginEnabled, forKey: preferenceKey)
            return AppPreferenceDefaults.launchAtLoginEnabled
        }
        return defaults.bool(forKey: preferenceKey)
    }
}
