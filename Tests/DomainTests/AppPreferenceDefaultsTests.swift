import Testing
@testable import Domain

@Suite("App preference defaults")
struct AppPreferenceDefaultsTests {
    @Test("cross-device transmission is opt-in")
    func crossDeviceTransmissionDefaultsOff() {
        #expect(AppPreferenceDefaults.crossDeviceSyncEnabled == false)
    }

    @Test("launch at login defaults on")
    func launchAtLoginDefaultsOn() {
        #expect(AppPreferenceDefaults.launchAtLoginEnabled == true)
    }
}
