import XCTest
@testable import DefaultBrowserSwitcher

final class BrowserSwitchSettingsTests: XCTestCase {
    func testSettingsDefaultToLaunchServicesDirectWhenUnset() {
        let defaults = makeUserDefaults()
        let settings = BrowserSwitchSettings(userDefaults: defaults)

        XCTAssertEqual(settings.switchMode, .launchServicesDirect)
    }

    func testSettingsPersistAndReloadSwitchMode() {
        let defaults = makeUserDefaults()
        let settings = BrowserSwitchSettings(userDefaults: defaults)

        settings.switchMode = .systemPrompt

        let reloadedSettings = BrowserSwitchSettings(userDefaults: defaults)
        XCTAssertEqual(reloadedSettings.switchMode, .systemPrompt)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "BrowserSwitchSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
