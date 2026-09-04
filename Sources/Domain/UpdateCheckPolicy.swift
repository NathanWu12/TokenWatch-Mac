import Foundation

public enum UpdateCheckPolicy {
    public static let dashboardProbeMinimumInterval: TimeInterval = 15 * 60

    public static func shouldProbeOnDashboardOpen(
        automaticChecksEnabled: Bool,
        sessionInProgress: Bool,
        hasKnownUpdate: Bool,
        lastCheckDate: Date?,
        now: Date
    ) -> Bool {
        guard automaticChecksEnabled, !sessionInProgress, !hasKnownUpdate else {
            return false
        }

        guard let lastCheckDate else { return true }
        return now.timeIntervalSince(lastCheckDate) >= dashboardProbeMinimumInterval
    }
}
