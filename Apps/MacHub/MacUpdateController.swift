import Combine
import Domain
import Foundation
import Sparkle

@MainActor
final class MacUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var dismissedVersion: String?

    private var standardUpdaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        standardUpdaterController.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        standardUpdaterController.updater.automaticallyDownloadsUpdates
    }

    var allowsAutomaticUpdates: Bool {
        standardUpdaterController.updater.allowsAutomaticUpdates
    }

    var canCheckForUpdates: Bool {
        standardUpdaterController.updater.canCheckForUpdates
    }

    var shouldShowDashboardBanner: Bool {
        guard let availableVersion else { return false }
        return availableVersion != dismissedVersion
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        objectWillChange.send()
        let updater = standardUpdaterController.updater
        updater.automaticallyChecksForUpdates = enabled
        if !enabled && updater.automaticallyDownloadsUpdates {
            updater.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        objectWillChange.send()
        let updater = standardUpdaterController.updater
        if enabled && !updater.automaticallyChecksForUpdates {
            updater.automaticallyChecksForUpdates = true
        }
        updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates() {
        guard standardUpdaterController.updater.canCheckForUpdates else { return }
        dismissedVersion = nil
        standardUpdaterController.updater.checkForUpdates()
    }

    func dashboardDidAppear(now: Date = Date()) {
        let updater = standardUpdaterController.updater
        guard UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: updater.automaticallyChecksForUpdates,
            sessionInProgress: updater.sessionInProgress,
            hasKnownUpdate: availableVersion != nil,
            lastCheckDate: updater.lastUpdateCheckDate,
            now: now
        ) else {
            return
        }

        isChecking = true
        updater.checkForUpdateInformation()
    }

    func dismissAvailableUpdate() {
        dismissedVersion = availableVersion
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        if dismissedVersion != item.displayVersionString {
            dismissedVersion = nil
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availableVersion = nil
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        isChecking = false
    }
}
