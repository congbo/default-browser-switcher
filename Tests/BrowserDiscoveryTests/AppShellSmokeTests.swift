import AppKit
import XCTest
@testable import DefaultBrowserSwitcher

@MainActor
final class AppShellSmokeTests: XCTestCase {
    func testShellScaffoldExposesMenuBarAndSettingsPlaceholders() {
        XCTAssertEqual(DefaultBrowserSwitcherApp.menuBarTitle, "Default Browser Switcher")
        XCTAssertEqual(DefaultBrowserSwitcherApp.settingsTitle, "Settings")

        let store = BrowserDiscoveryStore(service: AppShellSmokeBrowserDiscoveryService())
        let launchAtLoginService = LaunchAtLoginService(controller: AppShellSmokeLaunchAtLoginController())

        _ = MenuBarContentView()
            .environmentObject(store)
            .environmentObject(BrowserIconProvider.shared)
        _ = SettingsView()
            .environmentObject(store)
            .environmentObject(BrowserIconProvider.shared)
            .environmentObject(launchAtLoginService)
    }

    func testStandardAboutPanelOptionsExposeApplicationNameAndProjectCredits() throws {
        let options = StandardAboutPanelConfiguration.options(applicationName: "Test Browser Switcher")

        XCTAssertEqual(
            options[.applicationName] as? String,
            "Test Browser Switcher"
        )

        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertEqual(credits.string, StandardAboutPanelConfiguration.projectURL.absoluteString)
        let fullRange = NSRange(location: 0, length: credits.length)
        let linkValue = credits.attribute(.link, at: 0, effectiveRange: nil) as? URL

        XCTAssertEqual(linkValue, StandardAboutPanelConfiguration.projectURL)
        XCTAssertNotNil(credits.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNotNil(credits.attribute(.paragraphStyle, at: fullRange.location, effectiveRange: nil))
    }
}

private struct AppShellSmokeBrowserDiscoveryService: BrowserDiscoveryService {
    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [],
            httpsCandidates: []
        )
    }

    func switchDefaultBrowser(to target: BrowserSwitchTarget) async -> BrowserSwitchResult {
        BrowserSwitchResult.serviceFailure(target: target, readbackErrorMessage: "not used in smoke test")
    }
}

private final class AppShellSmokeLaunchAtLoginController: LaunchAtLoginControlling {
    func currentStatus() async -> LaunchAtLoginService.ControllerStatus {
        .notFound
    }

    func register() async throws {}

    func unregister() async throws {}
}
