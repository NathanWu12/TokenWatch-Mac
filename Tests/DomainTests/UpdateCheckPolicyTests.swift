import Foundation
import Testing
@testable import Domain

@Suite("Update check policy")
struct UpdateCheckPolicyTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("dashboard probe runs on first open when automatic checks are enabled")
    func firstOpenChecks() {
        #expect(UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: true,
            sessionInProgress: false,
            hasKnownUpdate: false,
            lastCheckDate: nil,
            now: now
        ))
    }

    @Test("dashboard probe is suppressed while disabled, busy, or already showing an update")
    func suppressionRules() {
        #expect(!UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: false,
            sessionInProgress: false,
            hasKnownUpdate: false,
            lastCheckDate: nil,
            now: now
        ))
        #expect(!UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: true,
            sessionInProgress: true,
            hasKnownUpdate: false,
            lastCheckDate: nil,
            now: now
        ))
        #expect(!UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: true,
            sessionInProgress: false,
            hasKnownUpdate: true,
            lastCheckDate: nil,
            now: now
        ))
    }

    @Test("dashboard probe is throttled for fifteen minutes")
    func throttleBoundary() {
        #expect(!UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: true,
            sessionInProgress: false,
            hasKnownUpdate: false,
            lastCheckDate: now.addingTimeInterval(-(15 * 60 - 1)),
            now: now
        ))
        #expect(UpdateCheckPolicy.shouldProbeOnDashboardOpen(
            automaticChecksEnabled: true,
            sessionInProgress: false,
            hasKnownUpdate: false,
            lastCheckDate: now.addingTimeInterval(-15 * 60),
            now: now
        ))
    }
}
