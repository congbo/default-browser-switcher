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
        let switchSettings = BrowserSwitchSettings(userDefaults: UserDefaults(suiteName: "AppShellSmokeTests")!)

        _ = MenuBarContentView()
            .environmentObject(store)
            .environmentObject(BrowserIconProvider.shared)
        _ = SettingsView()
            .environmentObject(store)
            .environmentObject(BrowserIconProvider.shared)
            .environmentObject(launchAtLoginService)
            .environmentObject(switchSettings)
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

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testRegisterConfiguresWindow() {
        let controller = SettingsWindowController(
            activateApplication: { _ in }
        )
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let isNewWindow = controller.register(window: window)

        XCTAssertTrue(isNewWindow)
        XCTAssertEqual(
            window.identifier?.rawValue,
            DefaultBrowserSwitcherApp.settingsWindowIdentifier
        )
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertEqual(window.minSize, NSSize(width: 600, height: 460))
    }

    func testActivateBringsRegisteredWindowToFront() {
        var activateApplicationCallCount = 0
        let controller = SettingsWindowController(
            activateApplication: { _ in
                activateApplicationCallCount += 1
            }
        )
        let window = SpyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        _ = controller.register(window: window)

        controller.activate(window: window)

        XCTAssertEqual(activateApplicationCallCount, 1)
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
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

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot _: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
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

private final class SpyWindow: NSWindow {
    private(set) var orderFrontRegardlessCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0

    override func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }
}
