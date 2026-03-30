import Combine
import XCTest
@testable import DefaultBrowserSwitcher

@MainActor
final class BrowserDiscoveryStoreTests: XCTestCase {
    func testRefreshPublishesLoadingThenLoadedSnapshotAndClearsPreviousError() async {
        let controller = ControlledDiscoveryServiceController()
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        let refreshTask = Task {
            await store.refresh()
        }

        await waitForFetchCount(controller, expected: 1)
        XCTAssertEqual(store.phase, .refreshing)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.lastRefreshAt)

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            currentHTTPSHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            httpCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            httpsCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_100)
        )

        await controller.resumeFetch(with: .success(snapshot))
        await refreshTask.value

        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(store.lastRefreshAt, snapshot.refreshedAt)
        XCTAssertNil(store.lastErrorMessage)
    }

    func testRefreshFailurePromotesPresentationToStaleFallbackStatus() async {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_150)
        )
        let service = SequencedBrowserDiscoveryService(fetchResults: [
            .success(initialSnapshot),
            .failure(FixtureError.forcedFailure)
        ])
        let store = BrowserDiscoveryStore(service: service)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.snapshot, initialSnapshot)
        XCTAssertEqual(store.presentation.currentBrowser?.application, safari)
        XCTAssertEqual(store.presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(store.presentation.userVisibleStatus, .stale(message: FixtureError.forcedFailure.errorDescription ?? ""))
        XCTAssertTrue(store.presentation.showRefreshInMenu)
    }

    func testServiceFailureWithIncoherentLiveSnapshotAndNoVerifiedReadbackNeedsAttention() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")

        let coherentSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_155)
        )
        let incoherentSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_156)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(coherentSnapshot), .success(incoherentSnapshot)],
            initialSwitchResults: [.serviceFailure(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: firefox, supportedSchemes: [.http, .https])), readbackErrorMessage: "Injected switch failure")]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        await store.refresh()
        let firefoxCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == firefox.applicationURL }))

        _ = await store.switchToBrowser(firefoxCandidate)

        XCTAssertEqual(store.presentation.currentBrowser?.application, safari)
        XCTAssertEqual(store.presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(store.presentation.userVisibleStatus, .needsAttention(message: "Injected switch failure"))
        XCTAssertTrue(store.presentation.showRefreshInMenu)
    }

    func testRefreshFailurePreservesExistingSnapshotAndStoresVisibleError() async {
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            currentHTTPSHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            httpCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            httpsCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let service = SequencedBrowserDiscoveryService(fetchResults: [
            .success(initialSnapshot),
            .failure(FixtureError.forcedFailure)
        ])
        let store = BrowserDiscoveryStore(service: service)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.snapshot, initialSnapshot)
        XCTAssertEqual(store.lastRefreshAt, initialSnapshot.refreshedAt)
        XCTAssertEqual(store.lastErrorMessage, FixtureError.forcedFailure.errorDescription)
    }

    func testRefreshReplacesStaleSnapshotAndAllowsRetryAfterOverlapGuard() async {
        let controller = ControlledDiscoveryServiceController()
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        let firstRefresh = Task {
            await store.refresh()
        }

        await waitForFetchCount(controller, expected: 1)
        await store.refresh()
        let fetchCountAfterOverlap = await controller.currentFetchCount()
        XCTAssertEqual(fetchCountAfterOverlap, 1)
        XCTAssertEqual(store.phase, .refreshing)

        let firstSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app"),
            currentHTTPSHandler: nil,
            httpCandidates: [.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")],
            httpsCandidates: [],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_200)
        )
        await controller.resumeFetch(with: .success(firstSnapshot))
        await firstRefresh.value

        let secondSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: .fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app"),
            httpCandidates: [],
            httpsCandidates: [.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_300)
        )
        await controller.enqueueFetch(result: .success(secondSnapshot))

        await store.refresh()

        let finalFetchCount = await controller.currentFetchCount()
        XCTAssertEqual(finalFetchCount, 2)
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.snapshot, secondSnapshot)
        XCTAssertEqual(store.lastRefreshAt, secondSnapshot.refreshedAt)
    }

    func testRefreshPublishesPartialSnapshotTruthfully() async {
        let partialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: .fixture(bundleIdentifier: "com.apple.Safari", displayName: nil, path: "/Applications/Safari.app"),
            httpCandidates: [],
            httpsCandidates: [.fixture(bundleIdentifier: nil, displayName: nil, path: "/Applications/Unnamed Browser.app")],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_400),
            issues: ["https current handler metadata is incomplete"]
        )
        let store = BrowserDiscoveryStore(service: SequencedBrowserDiscoveryService(fetchResults: [.success(partialSnapshot)]))

        await store.refresh()

        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.snapshot?.currentHTTPHandler, nil)
        XCTAssertEqual(store.snapshot?.currentHTTPSHandler?.displayName, nil)
        XCTAssertEqual(store.snapshot?.candidates.count, 2)
        XCTAssertEqual(
            store.snapshot?.candidates.first(where: { $0.applicationURL.lastPathComponent == "Unnamed Browser.app" })?.displayName,
            nil
        )
        XCTAssertEqual(store.snapshot?.issues, ["https current handler metadata is incomplete"])
    }

    func testSwitchPublishesSwitchingThenVerifiedSuccessAndUpdatesSnapshot() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_500)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_600)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(initialSnapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let switchTask = Task {
            await store.switchToBrowser(candidate)
        }

        await waitForSwitchCount(controller, expected: 1)
        XCTAssertEqual(store.switchPhase, .switching)
        let recordedTargets = await controller.recordedSwitchTargets().map(\.applicationURL.path)
        XCTAssertEqual(recordedTargets, [chrome.applicationURL.standardizedFileURL.path])

        await controller.resumeSwitch(with: .verifiedSuccess(target: BrowserSwitchTarget(candidate: candidate), verifiedSnapshot: verifiedSnapshot))
        let result = await switchTask.value

        XCTAssertEqual(result.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertEqual(store.lastSwitchResult, result)
        XCTAssertEqual(store.lastSwitchAt, result.completedAt)
        XCTAssertNil(store.lastErrorMessage)
    }

    func testOptimisticSuccessUpdatesSnapshotImmediatelyAndReconcilesInBackground() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_610)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_620)
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let backgroundRefreshScheduler = ManualBackgroundRefreshScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.optimisticSuccess(target: target, optimisticSnapshot: initialSnapshot.projectedSwitchSnapshot(for: target))]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.evidence, .optimistic)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, initialSnapshot.projectedSwitchSnapshot(for: target))
        XCTAssertEqual(store.presentation.currentBrowserSource, .optimisticPostSwitch)
        XCTAssertEqual(store.presentation.settingsHelperText, "The app is refreshing browser state in the background.")
        XCTAssertEqual(store.logEntries.map(\.stage), [.refresh, .refresh, .switching, .switching, .verification])

        await controller.enqueueFetch(result: .success(verifiedSnapshot))
        await backgroundRefreshScheduler.fireNext()

        XCTAssertEqual(store.lastSwitchResult?.evidence, .verified)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertEqual(store.presentation.currentBrowserSource, .liveSnapshot)
        XCTAssertEqual(store.logEntries.last?.stage, .verification)
        XCTAssertEqual(store.logEntries.last?.level, .info)
    }

    func testOptimisticSuccessMismatchKeepsProjectedSnapshotAndLogsWarning() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_630)
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let backgroundRefreshScheduler = ManualBackgroundRefreshScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.optimisticSuccess(target: target, optimisticSnapshot: initialSnapshot.projectedSwitchSnapshot(for: target))]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        _ = await store.switchToBrowser(candidate)
        await controller.enqueueFetch(result: .success(initialSnapshot))
        await backgroundRefreshScheduler.fireNext()

        XCTAssertEqual(store.lastSwitchResult?.classification, .success)
        XCTAssertEqual(store.lastSwitchResult?.evidence, .optimistic)
        XCTAssertEqual(store.snapshot, initialSnapshot.projectedSwitchSnapshot(for: target))
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowserSource, .optimisticPostSwitch)
        XCTAssertEqual(store.presentation.userVisibleStatus, .updated(browserName: "Google Chrome"))
        XCTAssertEqual(
            store.presentation.settingsHelperText,
            "The browser switch was submitted, but verification has not caught up yet."
        )
        XCTAssertFalse(store.presentation.showRefreshInMenu)
        XCTAssertEqual(store.logEntries.last?.stage, .verification)
        XCTAssertEqual(store.logEntries.last?.level, .warning)
        XCTAssertEqual(store.logEntries.last?.message, "http handler remained Safari")
    }

    func testOptimisticSuccessVerificationReadFailureKeepsProjectedSnapshotAndLogsError() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_631)
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let backgroundRefreshScheduler = ManualBackgroundRefreshScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.optimisticSuccess(target: target, optimisticSnapshot: initialSnapshot.projectedSwitchSnapshot(for: target))]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        _ = await store.switchToBrowser(candidate)
        await controller.enqueueFetch(result: .failure(FixtureError.forcedFailure))
        await backgroundRefreshScheduler.fireNext()

        XCTAssertEqual(store.snapshot, initialSnapshot.projectedSwitchSnapshot(for: target))
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowserSource, .optimisticPostSwitch)
        XCTAssertEqual(
            store.presentation.settingsHelperText,
            "The browser switch was submitted, but verification has not caught up yet."
        )
        XCTAssertEqual(store.logEntries.last?.stage, .verification)
        XCTAssertEqual(store.logEntries.last?.level, .error)
        XCTAssertEqual(store.logEntries.last?.message, FixtureError.forcedFailure.errorDescription)
    }

    func testDirectOptimisticVerificationPrefersPreferencesOverWorkspaceProbe() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferencesURL = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let switchSettings = BrowserSwitchSettings(userDefaults: UserDefaults(suiteName: "DirectOptimisticVerification-\(UUID().uuidString)")!)
        switchSettings.switchMode = .launchServicesDirect

        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let arc = BrowserApplication.fixture(bundleIdentifier: "company.theBrowser", displayName: "Arc", path: "/Applications/Arc.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, arc],
            httpsCandidates: [safari, arc],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_631)
        )

        let snapshotService = SequencedBrowserDiscoveryService(fetchResults: [.success(initialSnapshot)])
        let scheduler = ManualBackgroundRefreshScheduler()
        let directService = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
                candidateURLs: [.http: [safari.applicationURL, arc.applicationURL], .https: [safari.applicationURL, arc.applicationURL]]
            ),
            completionTimeout: 0.01,
            commandRunner: RecordingCommandRunner(),
            preferencesURL: preferencesURL
        )
        let store = BrowserDiscoveryStore(
            service: SwitchModeBrowserDiscoveryService(
                snapshotService: snapshotService,
                launchServicesDirectService: directService,
                systemPromptService: snapshotService,
                settings: switchSettings
            ),
            backgroundRefreshScheduler: scheduler
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == arc.applicationURL }))

        _ = await store.switchToBrowser(candidate)
        await scheduler.fireNext()

        XCTAssertEqual(store.lastSwitchResult?.evidence, .verified)
        XCTAssertEqual(store.lastSwitchResult?.classification, .success)
        XCTAssertEqual(store.presentation.currentBrowser?.application, arc)
        XCTAssertEqual(store.presentation.currentBrowserSource, .liveSnapshot)
        XCTAssertEqual(store.logEntries.last?.level, .warning)
        XCTAssertEqual(store.logEntries.last?.message, "Workspace readback still reported Safari for the HTTP sample URL.")
    }

    func testManualRefreshCanReplaceDeferredOptimisticSelectionWithLiveSnapshot() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_632)
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let backgroundRefreshScheduler = ManualBackgroundRefreshScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot), .success(initialSnapshot), .success(initialSnapshot)],
            initialSwitchResults: [.optimisticSuccess(target: target, optimisticSnapshot: initialSnapshot.projectedSwitchSnapshot(for: target))]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        _ = await store.switchToBrowser(candidate)
        await backgroundRefreshScheduler.fireNext()
        await store.refresh()

        XCTAssertEqual(store.snapshot, initialSnapshot)
        XCTAssertEqual(store.presentation.currentBrowser?.application, safari)
        XCTAssertEqual(store.presentation.currentBrowserSource, .liveSnapshot)
    }

    func testVerifiedSuccessSuppressesPerSchemeCallbackErrorsInStoreState() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_650)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_660)
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [
                BrowserSwitchResult.verified(
                    target: target,
                    schemeOutcomes: [
                        .timedOut(.http, message: "Timed out waiting for the http switch completion callback."),
                        .failure(.https, message: "The file couldn’t be opened.")
                    ],
                    verifiedSnapshot: verifiedSnapshot
                )
            ]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertNil(store.lastErrorMessage)
    }

    func testSwitchRejectsCandidateMissingRequiredSchemeWithoutClaimingSuccess() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, firefox],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_700)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(snapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let invalidCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == firefox.applicationURL }))

        let result = await store.switchToBrowser(invalidCandidate)

        let switchCount = await controller.currentSwitchCount()
        XCTAssertEqual(switchCount, 0)
        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.switchPhase, .failure)
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertNotNil(store.lastErrorMessage)
        XCTAssertEqual(result.requestedTarget.applicationURL, firefox.applicationURL.standardizedFileURL)
    }

    func testSwitchMatchingNormalizedApplicationPathUsesSnapshotCandidateAndSwitches() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_750)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_760)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.verifiedSuccess(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot)]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()

        let result = await store.switchToBrowser(matchingNormalizedApplicationPath: chrome.applicationURL.path)

        XCTAssertEqual(result.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertEqual(result.requestedTarget.applicationURL.standardizedFileURL.path, chrome.applicationURL.standardizedFileURL.path)
        let recordedTargets = await controller.recordedSwitchTargets().map(\.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(recordedTargets, [chrome.applicationURL.standardizedFileURL.path])
    }

    func testSwitchMatchingNormalizedApplicationPathReportsUnknownCandidateWithoutCallingService() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_770)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(snapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()

        let missingPath = "/Applications/Firefox.app"
        let result = await store.switchToBrowser(matchingNormalizedApplicationPath: missingPath)

        let switchCount = await controller.currentSwitchCount()
        XCTAssertEqual(switchCount, 0)
        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.switchPhase, .failure)
        XCTAssertEqual(result.requestedTarget.applicationURL.standardizedFileURL.path, missingPath)
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.unknownCandidate(missingPath).errorDescription)
    }

    func testSwitchMixedResultRetainsLastGoodSnapshotAndExportsVerifiedReadback() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_800)
        )
        let mixedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_000_900)
        )
        let reportURL = temporaryDirectory().appendingPathComponent("switch-report.json")
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.verifiedMixed(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: mixedSnapshot, mismatchDetails: ["https remained Safari"])]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            environment: ["DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH": reportURL.path]
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)
        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder.reportDecoder.decode(BrowserDiscoveryStore.Report.self, from: reportData)

        XCTAssertEqual(result.classification, .mixed)
        XCTAssertEqual(store.switchPhase, .mixed)
        XCTAssertEqual(store.snapshot, initialSnapshot)
        XCTAssertEqual(store.lastSwitchResult?.verifiedSnapshot, mixedSnapshot)
        XCTAssertEqual(report.lastSwitchResult?.requestedTarget.applicationURL, chrome.applicationURL.standardizedFileURL)
        XCTAssertEqual(report.lastSwitchResult?.classification, .mixed)
        XCTAssertEqual(report.lastSwitchResult?.mismatchDetails, ["https remained Safari"])
    }

    func testSwitchRejectsOverlapAndAllowsRetryAfterActiveAttemptFinishes() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_000)
        )
        let failedVerifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_050)
        )
        let successVerifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_100)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(snapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let firstSwitchTask = Task {
            await store.switchToBrowser(candidate)
        }

        await waitForSwitchCount(controller, expected: 1)
        let overlappingResult = await store.switchToBrowser(candidate)

        let switchCountAfterOverlap = await controller.currentSwitchCount()
        XCTAssertEqual(switchCountAfterOverlap, 1)
        XCTAssertEqual(overlappingResult.classification, .failure)
        XCTAssertEqual(store.switchPhase, .switching)
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.switchAlreadyInProgress.errorDescription)

        await controller.resumeSwitch(with: .verifiedFailure(target: BrowserSwitchTarget(candidate: candidate), verifiedSnapshot: failedVerifiedSnapshot, mismatchDetails: ["Both schemes still resolved to Safari"]))
        let failedResult = await firstSwitchTask.value
        XCTAssertEqual(failedResult.classification, .failure)
        XCTAssertEqual(store.switchPhase, .failure)

        await controller.enqueueSwitch(result: .verifiedSuccess(target: BrowserSwitchTarget(candidate: candidate), verifiedSnapshot: successVerifiedSnapshot))
        let retryResult = await store.switchToBrowser(candidate)

        let finalSwitchCount = await controller.currentSwitchCount()
        XCTAssertEqual(finalSwitchCount, 2)
        XCTAssertEqual(retryResult.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, successVerifiedSnapshot)
    }

    func testSwitchReportWriteFailureKeepsInMemoryResultTruthfulAndSurfacesError() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_200)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_300)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.verifiedSuccess(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot)]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            environment: ["DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH": temporaryDirectory().appendingPathComponent("report.json").path],
            reportWriter: { _, _ in throw FixtureError.reportWriteFailure }
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertEqual(store.lastSwitchResult, result)
        XCTAssertEqual(store.phase, .loaded)
        XCTAssertEqual(store.lastErrorMessage, FixtureError.reportWriteFailure.errorDescription)
    }

    func testMixedResultWithCoherentVerifiedSnapshotKeepsRawSnapshotButUpdatesPresentationAndLastCoherentBrowser() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_400)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_500)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.verifiedFailure(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot, mismatchDetails: ["callback reported failure despite coherent readback"])]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.snapshot, initialSnapshot)
        XCTAssertEqual(store.lastCoherentBrowser, chrome)
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowser?.source, .verifiedPostSwitch)
    }

    func testVerifiedSwitchResultOverridesPriorRefreshFailureForPostSwitchPresentation() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_510)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_520)
        )
        let service = SequencedBrowserDiscoveryService(
            fetchResults: [
                .success(initialSnapshot),
                .failure(FixtureError.forcedFailure)
            ],
            switchResults: [
                .verifiedFailure(
                    target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])),
                    verifiedSnapshot: verifiedSnapshot,
                    mismatchDetails: ["callback reported failure despite coherent readback"]
                )
            ]
        )
        let store = BrowserDiscoveryStore(service: service)

        await store.refresh()
        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowser?.source, .verifiedPostSwitch)
        XCTAssertEqual(store.presentation.currentBrowserSource, .verifiedPostSwitch)
        XCTAssertEqual(store.presentation.userVisibleStatus, .needsAttention(message: "callback reported failure despite coherent readback"))
        XCTAssertTrue(store.presentation.showRefreshInMenu)
    }

    func testVerifiedSuccessPublishesUpdatedSuccessStateAndExpiresThroughResetScheduler() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_600)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_700)
        )
        let scheduler = ManualSuccessResetScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [.verifiedSuccess(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot)]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            successResetScheduler: scheduler,
            successResetInterval: 30
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        let result = await store.switchToBrowser(candidate)

        XCTAssertEqual(result.classification, .success)
        XCTAssertEqual(store.presentation.successState, .updated(browserName: "Google Chrome"))

        await scheduler.fireNext()

        XCTAssertEqual(store.presentation.successState, .none)
    }

    func testRefreshClearsSuccessStateAndLiveSnapshotReplacesPriorVerifiedPostSwitchPresentation() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_800)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_900)
        )
        let refreshedLiveSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_000)
        )
        let scheduler = ManualSuccessResetScheduler()
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(staleSnapshot), .success(refreshedLiveSnapshot)],
            initialSwitchResults: [.verifiedSuccess(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot)]
        )
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            successResetScheduler: scheduler,
            successResetInterval: 30
        )

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        _ = await store.switchToBrowser(candidate)
        XCTAssertEqual(store.presentation.successState, .updated(browserName: "Google Chrome"))
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)

        await store.refresh()

        XCTAssertEqual(store.presentation.successState, .none)
        XCTAssertEqual(store.presentation.currentBrowser?.application, safari)
        XCTAssertEqual(store.presentation.currentBrowser?.source, .liveSnapshot)
    }

    func testRefreshFailureAfterSuccessfulSwitchKeepsTrustedStaleSelectionForRequestedBrowser() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_010)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_020)
        )
        let service = SequencedBrowserDiscoveryService(
            fetchResults: [
                .success(initialSnapshot),
                .failure(FixtureError.forcedFailure)
            ],
            switchResults: [
                .verifiedSuccess(
                    target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])),
                    verifiedSnapshot: verifiedSnapshot
                )
            ]
        )
        let store = BrowserDiscoveryStore(service: service)

        await store.refresh()
        let chromeCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))

        _ = await store.switchToBrowser(chromeCandidate)
        await store.refresh()

        let chromeRow = try XCTUnwrap(store.presentation.candidates.first(where: { $0.candidate.applicationURL == chrome.applicationURL }))

        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(chromeRow.actionState, .trustedSelection)
        XCTAssertEqual(store.presentation.selectedActionableBrowserID, chromeRow.candidate.id)
    }

    func testNewSwitchAttemptClearsPriorSuccessStateImmediately() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")
        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_100)
        )
        let verifiedChromeSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_200)
        )
        let scheduler = ManualSuccessResetScheduler()
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(staleSnapshot)])
        let store = BrowserDiscoveryStore(
            service: ControlledBrowserDiscoveryService(controller: controller),
            successResetScheduler: scheduler,
            successResetInterval: 30
        )

        await store.refresh()
        let chromeCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))
        let firefoxCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == firefox.applicationURL }))

        await controller.enqueueSwitch(result: .verifiedSuccess(target: BrowserSwitchTarget(candidate: chromeCandidate), verifiedSnapshot: verifiedChromeSnapshot))
        _ = await store.switchToBrowser(chromeCandidate)

        XCTAssertEqual(store.presentation.successState, .updated(browserName: "Google Chrome"))

        let secondSwitch = Task {
            await store.switchToBrowser(firefoxCandidate)
        }

        await waitForSwitchCount(controller, expected: 2)
        XCTAssertEqual(store.switchPhase, .switching)
        XCTAssertEqual(store.presentation.successState, .none)

        await controller.resumeSwitch(with: .serviceFailure(target: BrowserSwitchTarget(candidate: firefoxCandidate), readbackErrorMessage: "Injected switch failure"))
        _ = await secondSwitch.value
    }

    func testNewSwitchAttemptClearsPriorDerivedVerifiedPostSwitchPresentationImmediately() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")
        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_300)
        )
        let verifiedChromeSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_400)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(staleSnapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let chromeCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))
        let firefoxCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == firefox.applicationURL }))

        await controller.enqueueSwitch(result: .verifiedFailure(target: BrowserSwitchTarget(candidate: chromeCandidate), verifiedSnapshot: verifiedChromeSnapshot, mismatchDetails: ["callback failed despite coherent readback"]))
        _ = await store.switchToBrowser(chromeCandidate)

        XCTAssertEqual(store.presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(store.presentation.currentBrowser?.source, .verifiedPostSwitch)

        let secondSwitch = Task {
            await store.switchToBrowser(firefoxCandidate)
        }

        await waitForSwitchCount(controller, expected: 2)
        XCTAssertEqual(store.switchPhase, .switching)
        XCTAssertEqual(store.presentation.currentBrowser?.application, safari)
        XCTAssertEqual(store.presentation.currentBrowser?.source, .liveSnapshot)

        await controller.resumeSwitch(with: .serviceFailure(target: BrowserSwitchTarget(candidate: firefoxCandidate), readbackErrorMessage: "Injected switch failure"))
        _ = await secondSwitch.value
    }

    func testRetryLastSwitchTargetReusesCurrentSnapshotCandidateAndSucceeds() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_500)
        )
        let staleTargetResult = BrowserSwitchResult.serviceFailure(
            target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])),
            readbackErrorMessage: "Injected switch failure"
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_600)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot)],
            initialSwitchResults: [staleTargetResult, .verifiedSuccess(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), verifiedSnapshot: verifiedSnapshot)]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))
        _ = await store.switchToBrowser(candidate)

        let retryResult = await store.retryLastSwitchTarget()

        XCTAssertEqual(retryResult.classification, .success)
        XCTAssertEqual(store.switchPhase, .success)
        XCTAssertEqual(store.snapshot, verifiedSnapshot)
        XCTAssertEqual(store.retryAvailability, .enabled(targetName: "Google Chrome"))
        let recordedTargets = await controller.recordedSwitchTargets().map(\.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(recordedTargets, [chrome.applicationURL.standardizedFileURL.path, chrome.applicationURL.standardizedFileURL.path])
    }

    func testRetryLastSwitchTargetFailsWithoutPriorSwitchResult() async {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_700)
        )
        let controller = ControlledDiscoveryServiceController(initialFetchResults: [.success(snapshot)])
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()

        let result = await store.retryLastSwitchTarget()

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.switchPhase, .failure)
        XCTAssertEqual(store.retryAvailability, .disabled(.noPreviousTarget))
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.missingRetryTarget.errorDescription)
        let switchCount = await controller.currentSwitchCount()
        XCTAssertEqual(switchCount, 0)
    }

    func testRetryLastSwitchTargetFailsWhenTargetIsMissingFromCurrentSnapshot() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_800)
        )
        let refreshedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, firefox],
            httpsCandidates: [safari, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_900)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot), .success(refreshedSnapshot)],
            initialSwitchResults: [.serviceFailure(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), readbackErrorMessage: "Injected switch failure")]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let originalCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))
        _ = await store.switchToBrowser(originalCandidate)
        await store.refresh()

        let result = await store.retryLastSwitchTarget()

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.snapshot, refreshedSnapshot)
        XCTAssertEqual(store.retryAvailability, .disabled(.targetMissing(displayName: "Google Chrome")))
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.retryTargetMissingFromSnapshot(originalCandidate.normalizedApplicationPath).errorDescription)
        let switchCount = await controller.currentSwitchCount()
        XCTAssertEqual(switchCount, 1)
    }

    func testRetryLastSwitchTargetFailsWhenTargetNoLongerSupportsBothSchemes() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")
        let initialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, firefox],
            httpsCandidates: [safari, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_003_000)
        )
        let refreshedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, firefox],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_003_100)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(initialSnapshot), .success(refreshedSnapshot)],
            initialSwitchResults: [.serviceFailure(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: firefox, supportedSchemes: [.http, .https])), readbackErrorMessage: "Injected switch failure")]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let originalCandidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == firefox.applicationURL }))
        _ = await store.switchToBrowser(originalCandidate)
        await store.refresh()

        let result = await store.retryLastSwitchTarget()

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(store.snapshot, refreshedSnapshot)
        XCTAssertEqual(store.retryAvailability, .disabled(.missingRequiredSchemes(targetName: "Firefox")))
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.retryTargetMissingSupportedSchemes(originalCandidate.normalizedApplicationPath).errorDescription)
        let switchCount = await controller.currentSwitchCount()
        XCTAssertEqual(switchCount, 1)
    }

    func testRetryLastSwitchTargetRejectsOverlapWhileAnotherSwitchIsRunning() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_003_200)
        )
        let controller = ControlledDiscoveryServiceController(
            initialFetchResults: [.success(snapshot)],
            initialSwitchResults: [.serviceFailure(target: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https])), readbackErrorMessage: "Injected switch failure")]
        )
        let store = BrowserDiscoveryStore(service: ControlledBrowserDiscoveryService(controller: controller))

        await store.refresh()
        let candidate = try XCTUnwrap(store.snapshot?.candidates.first(where: { $0.applicationURL == chrome.applicationURL }))
        _ = await store.switchToBrowser(candidate)

        let activeSwitchTask = Task {
            await store.switchToBrowser(candidate)
        }

        await waitForSwitchCount(controller, expected: 1)
        let retryResult = await store.retryLastSwitchTarget()

        XCTAssertEqual(retryResult.classification, .failure)
        XCTAssertEqual(store.switchPhase, .switching)
        XCTAssertEqual(store.retryAvailability, .disabled(.switchInProgress(targetName: "Google Chrome")))
        XCTAssertEqual(store.lastErrorMessage, BrowserDiscoveryStore.StoreError.switchAlreadyInProgress.errorDescription)

        await controller.resumeSwitch(with: .serviceFailure(target: BrowserSwitchTarget(candidate: candidate), readbackErrorMessage: "Injected switch failure"))
        _ = await activeSwitchTask.value
    }

    private func waitForFetchCount(_ controller: ControlledDiscoveryServiceController, expected: Int) async {
        while await controller.currentFetchCount() < expected {
            await Task.yield()
        }
    }

    private func waitForSwitchCount(_ controller: ControlledDiscoveryServiceController, expected: Int) async {
        while await controller.currentSwitchCount() < expected {
            await Task.yield()
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor ControlledDiscoveryServiceController {
    private var fetchQueue: [Result<BrowserDiscoverySnapshot, Error>]
    private var switchQueue: [BrowserSwitchResult]
    private var fetchContinuations: [CheckedContinuation<BrowserDiscoverySnapshot, Error>] = []
    private var switchContinuations: [CheckedContinuation<BrowserSwitchResult, Never>] = []
    private(set) var fetchCount = 0
    private(set) var switchCount = 0
    private(set) var switchTargets: [BrowserSwitchTarget] = []

    init(
        initialFetchResults: [Result<BrowserDiscoverySnapshot, Error>] = [],
        initialSwitchResults: [BrowserSwitchResult] = []
    ) {
        fetchQueue = initialFetchResults
        switchQueue = initialSwitchResults
    }

    func currentFetchCount() -> Int {
        fetchCount
    }

    func currentSwitchCount() -> Int {
        switchCount
    }

    func recordedSwitchTargets() -> [BrowserSwitchTarget] {
        switchTargets
    }

    func nextSnapshot() async throws -> BrowserDiscoverySnapshot {
        fetchCount += 1

        if !fetchQueue.isEmpty {
            return try fetchQueue.removeFirst().get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuations.append(continuation)
        }
    }

    func nextSwitchResult(for target: BrowserSwitchTarget) async -> BrowserSwitchResult {
        switchCount += 1
        switchTargets.append(target)

        if !switchQueue.isEmpty {
            return switchQueue.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            switchContinuations.append(continuation)
        }
    }

    func enqueueFetch(result: Result<BrowserDiscoverySnapshot, Error>) {
        if !fetchContinuations.isEmpty {
            fetchContinuations.removeFirst().resume(with: result)
            return
        }

        fetchQueue.append(result)
    }

    func resumeFetch(with result: Result<BrowserDiscoverySnapshot, Error>) {
        enqueueFetch(result: result)
    }

    func enqueueSwitch(result: BrowserSwitchResult) {
        if !switchContinuations.isEmpty {
            switchContinuations.removeFirst().resume(returning: result)
            return
        }

        switchQueue.append(result)
    }

    func resumeSwitch(with result: BrowserSwitchResult) {
        enqueueSwitch(result: result)
    }
}

private struct ControlledBrowserDiscoveryService: BrowserDiscoveryService {
    let controller: ControlledDiscoveryServiceController

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        try await controller.nextSnapshot()
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot _: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        await controller.nextSwitchResult(for: target)
    }
}

private final class SequencedBrowserDiscoveryService: BrowserDiscoveryService {
    private var fetchResults: [Result<BrowserDiscoverySnapshot, Error>]
    private var switchResults: [BrowserSwitchResult]
    private var fetchIndex = 0
    private var switchIndex = 0

    init(
        fetchResults: [Result<BrowserDiscoverySnapshot, Error>] = [],
        switchResults: [BrowserSwitchResult] = []
    ) {
        self.fetchResults = fetchResults
        self.switchResults = switchResults
    }

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        guard fetchIndex < fetchResults.count else {
            XCTFail("Requested more BrowserDiscoveryService fetch results than the test configured.")
            throw FixtureError.unconfiguredResult
        }

        defer { fetchIndex += 1 }
        return try fetchResults[fetchIndex].get()
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot _: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        guard switchIndex < switchResults.count else {
            XCTFail("Requested more BrowserDiscoveryService switch results than the test configured for \(target.id).")
            return .serviceFailure(target: target, readbackErrorMessage: FixtureError.unconfiguredSwitchResult.localizedDescription)
        }

        defer { switchIndex += 1 }
        return switchResults[switchIndex]
    }
}

private enum FixtureError: LocalizedError {
    case forcedFailure
    case unconfiguredResult
    case unconfiguredSwitchResult
    case reportWriteFailure

    var errorDescription: String? {
        switch self {
        case .forcedFailure:
            return "Injected discovery failure"
        case .unconfiguredResult:
            return "Missing discovery fixture result"
        case .unconfiguredSwitchResult:
            return "Missing browser switch fixture result"
        case .reportWriteFailure:
            return "Injected report write failure"
        }
    }
}

private final class ManualSuccessResetScheduler: BrowserPresentationSuccessResetScheduling {
    private var actions: [UUID: @MainActor () async -> Void] = [:]
    private var order: [UUID] = []

    func schedule(after _: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let id = UUID()
        actions[id] = action
        order.append(id)

        return AnyCancellable { [weak self] in
            self?.actions[id] = nil
            self?.order.removeAll(where: { $0 == id })
        }
    }

    @MainActor
    func fireNext() async {
        guard let id = order.first, let action = actions[id] else {
            XCTFail("Expected a scheduled success reset action.")
            return
        }

        order.removeFirst()
        actions[id] = nil
        await action()
    }
}

private final class ManualBackgroundRefreshScheduler: BrowserDiscoveryBackgroundRefreshScheduling {
    private var actions: [UUID: @MainActor () async -> Void] = [:]
    private var order: [UUID] = []

    func schedule(after _: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let id = UUID()
        actions[id] = action
        order.append(id)

        return AnyCancellable { [weak self] in
            self?.actions[id] = nil
            self?.order.removeAll(where: { $0 == id })
        }
    }

    @MainActor
    func fireNext() async {
        guard let id = order.first, let action = actions[id] else {
            XCTFail("Expected a scheduled background refresh action.")
            return
        }

        order.removeFirst()
        actions[id] = nil
        await action()
    }
}

private final class RecordingCommandRunner: CommandRunning {
    struct Invocation: Equatable {
        let path: String
        let arguments: [String]
    }

    private(set) var commands: [Invocation] = []
    var error: Error?

    func runDetached(executableURL: URL, arguments: [String]) throws {
        commands.append(.init(path: executableURL.path, arguments: arguments))
        if let error {
            throw error
        }
    }
}

private final class StaticBrowserWorkspace: BrowserWorkspace {
    let currentHandlers: [BrowserURLScheme: URL]
    let candidateURLs: [BrowserURLScheme: [URL]]

    init(currentHandlers: [BrowserURLScheme: URL], candidateURLs: [BrowserURLScheme: [URL]]) {
        self.currentHandlers = currentHandlers
        self.candidateURLs = candidateURLs
    }

    func currentHandlerURL(for scheme: BrowserURLScheme) throws -> URL? {
        currentHandlers[scheme]
    }

    func candidateHandlerURLs(for scheme: BrowserURLScheme) throws -> [URL] {
        candidateURLs[scheme] ?? []
    }

    func setDefaultApplication(
        at applicationURL: URL,
        for scheme: BrowserURLScheme,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        completionHandler(nil)
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

private extension BrowserCandidate {
    static func fixture(from application: BrowserApplication, supportedSchemes: Set<BrowserURLScheme>) -> BrowserCandidate {
        BrowserCandidate(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName,
            applicationURL: application.applicationURL,
            supportedSchemes: supportedSchemes
        )
    }
}

private extension JSONDecoder {
    static var reportDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
