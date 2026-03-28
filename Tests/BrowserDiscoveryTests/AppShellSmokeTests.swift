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
