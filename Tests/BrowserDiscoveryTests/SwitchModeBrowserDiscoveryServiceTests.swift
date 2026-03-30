import XCTest
@testable import DefaultBrowserSwitcher

final class SwitchModeBrowserDiscoveryServiceTests: XCTestCase {
    func testFetchSnapshotAlwaysUsesSnapshotService() async throws {
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            currentHTTPSHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            httpCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            httpsCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")]
        )
        let snapshotService = RecordingBrowserDiscoveryService(fetchSnapshot: snapshot)
        let directService = RecordingBrowserDiscoveryService(switchResult: .serviceFailure(
            target: BrowserSwitchTarget(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
            readbackErrorMessage: "not used"
        ))
        let systemService = RecordingBrowserDiscoveryService(switchResult: .serviceFailure(
            target: BrowserSwitchTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari", applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")),
            readbackErrorMessage: "not used"
        ))
        let settings = BrowserSwitchSettings(userDefaults: makeUserDefaults())
        let service = SwitchModeBrowserDiscoveryService(
            snapshotService: snapshotService,
            launchServicesDirectService: directService,
            systemPromptService: systemService,
            settings: settings
        )

        let result = try await service.fetchSnapshot()

        XCTAssertEqual(result, snapshot)
        XCTAssertEqual(snapshotService.fetchCount, 1)
        XCTAssertEqual(directService.fetchCount, 0)
        XCTAssertEqual(systemService.fetchCount, 0)
    }

    func testSwitchUsesLaunchServicesDirectModeByDefault() async {
        let target = BrowserSwitchTarget(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        let directResult = BrowserSwitchResult.serviceFailure(target: target, readbackErrorMessage: "direct")
        let systemResult = BrowserSwitchResult.serviceFailure(target: target, readbackErrorMessage: "system")
        let settings = BrowserSwitchSettings(userDefaults: makeUserDefaults())
        let service = SwitchModeBrowserDiscoveryService(
            snapshotService: RecordingBrowserDiscoveryService(fetchSnapshot: emptySnapshot),
            launchServicesDirectService: RecordingBrowserDiscoveryService(switchResult: directResult),
            systemPromptService: RecordingBrowserDiscoveryService(switchResult: systemResult),
            settings: settings
        )

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.readbackErrorMessage, "direct")
    }

    func testSwitchUsesSystemPromptModeWhenSelected() async {
        let target = BrowserSwitchTarget(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        let directService = RecordingBrowserDiscoveryService(switchResult: .serviceFailure(target: target, readbackErrorMessage: "direct"))
        let systemService = RecordingBrowserDiscoveryService(switchResult: .serviceFailure(target: target, readbackErrorMessage: "system"))
        let settings = BrowserSwitchSettings(userDefaults: makeUserDefaults())
        settings.switchMode = .systemPrompt
        let service = SwitchModeBrowserDiscoveryService(
            snapshotService: RecordingBrowserDiscoveryService(fetchSnapshot: emptySnapshot),
            launchServicesDirectService: directService,
            systemPromptService: systemService,
            settings: settings
        )

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.readbackErrorMessage, "system")
        XCTAssertEqual(directService.switchCount, 0)
        XCTAssertEqual(systemService.switchCount, 1)
    }

    private var emptySnapshot: BrowserDiscoverySnapshot {
        BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [],
            httpsCandidates: []
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "SwitchModeBrowserDiscoveryServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class RecordingBrowserDiscoveryService: BrowserDiscoveryService {
    private let fetchSnapshotResult: BrowserDiscoverySnapshot
    private let switchResult: BrowserSwitchResult
    private(set) var fetchCount = 0
    private(set) var switchCount = 0

    init(
        fetchSnapshot: BrowserDiscoverySnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [],
            httpsCandidates: []
        ),
        switchResult: BrowserSwitchResult = .serviceFailure(
            target: BrowserSwitchTarget(bundleIdentifier: nil, displayName: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app")),
            readbackErrorMessage: "unused"
        )
    ) {
        fetchSnapshotResult = fetchSnapshot
        self.switchResult = switchResult
    }

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        fetchCount += 1
        return fetchSnapshotResult
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot _: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        switchCount += 1
        return switchResult.requestedTarget == target
            ? switchResult
            : .serviceFailure(target: target, readbackErrorMessage: switchResult.readbackErrorMessage ?? "unexpected target")
    }
}

private extension BrowserApplication {
    static func fixture(bundleIdentifier: String?, displayName: String?, path: String) -> BrowserApplication {
        BrowserApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: URL(fileURLWithPath: path)
        )
    }
}
