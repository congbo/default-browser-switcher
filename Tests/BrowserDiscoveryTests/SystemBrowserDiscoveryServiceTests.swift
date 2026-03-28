import XCTest
@testable import DefaultBrowserSwitcher

final class SystemBrowserDiscoveryServiceTests: XCTestCase {
    func testFetchSnapshotReturnsCoherentLiveState() async throws {
        let service = SystemBrowserDiscoveryService()
        let before = Date()

        let snapshot = try await service.fetchSnapshot()

        XCTAssertGreaterThanOrEqual(snapshot.refreshedAt.timeIntervalSince1970, before.timeIntervalSince1970)

        let uniqueIdentifiers = Set(snapshot.candidates.map(\.id))
        XCTAssertEqual(uniqueIdentifiers.count, snapshot.candidates.count)
        XCTAssertTrue(snapshot.candidates.allSatisfy { !$0.supportedSchemes.isEmpty })
        XCTAssertTrue(snapshot.candidates.allSatisfy { $0.applicationURL.isFileURL })

        if let httpHandler = snapshot.currentHTTPHandler {
            XCTAssertTrue(httpHandler.applicationURL.isFileURL)
            XCTAssertFalse(httpHandler.id.isEmpty)
        }

        if let httpsHandler = snapshot.currentHTTPSHandler {
            XCTAssertTrue(httpsHandler.applicationURL.isFileURL)
            XCTAssertFalse(httpsHandler.id.isEmpty)
        }
    }

    func testSwitchDefaultBrowserCapturesPerSchemeCompletionsAndVerifiedSuccess() async throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_000)
        )
        let workspace = FakeBrowserWorkspace(
            currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
            candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]],
            switchCompletionResults: [.http: .success, .https: .success],
            postSwitchSnapshot: verifiedSnapshot
        )
        let service = SystemBrowserDiscoveryService(workspace: workspace, completionTimeout: 0.05)
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.requestedTarget, target)
        XCTAssertEqual(result.classification, BrowserSwitchResult.Classification.success)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPHandler?.applicationURL.standardizedFileURL.path, verifiedSnapshot.currentHTTPHandler?.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPSHandler?.applicationURL.standardizedFileURL.path, verifiedSnapshot.currentHTTPSHandler?.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(result.verifiedSnapshot?.candidates.map { $0.applicationURL.standardizedFileURL.path }, verifiedSnapshot.candidates.map { $0.applicationURL.standardizedFileURL.path })
        XCTAssertEqual(result.schemeOutcomes.map { $0.scheme }, [BrowserURLScheme.http, BrowserURLScheme.https])
        XCTAssertEqual(result.schemeOutcomes.map { $0.status }, [BrowserSwitchSchemeOutcome.Status.success, BrowserSwitchSchemeOutcome.Status.success])
        XCTAssertNil(result.readbackErrorMessage)
        XCTAssertEqual(Set(workspace.recordedSwitchSchemes), Set(BrowserURLScheme.allCases))
        XCTAssertEqual(workspace.recordedSwitchTargets.map { $0.standardizedFileURL.path }.sorted(), [chrome.applicationURL.standardizedFileURL.path, chrome.applicationURL.standardizedFileURL.path].sorted())
    }

    func testSwitchDefaultBrowserPollsForVerifiedReadbackAfterDelayedSystemConvergence() async {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_050)
        )
        let workspace = FakeBrowserWorkspace(
            currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
            candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]],
            switchCompletionResults: [.http: .success, .https: .success],
            postSwitchSnapshot: verifiedSnapshot,
            delayedPostSwitchReadCallCount: 4
        )
        let service = SystemBrowserDiscoveryService(workspace: workspace, completionTimeout: 0.2)
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.classification, BrowserSwitchResult.Classification.success)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPHandler?.applicationURL.standardizedFileURL.path, chrome.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPSHandler?.applicationURL.standardizedFileURL.path, chrome.applicationURL.standardizedFileURL.path)
    }

    func testSwitchDefaultBrowserSurfacesMixedReadbackWithoutCollapsingPerSchemeFailures() async {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let mixedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_002_100)
        )
        let workspace = FakeBrowserWorkspace(
            currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
            candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]],
            switchCompletionResults: [.http: .success, .https: .failure(FixtureWorkspaceError.httpsWriteFailed)],
            postSwitchSnapshot: mixedSnapshot
        )
        let service = SystemBrowserDiscoveryService(workspace: workspace, completionTimeout: 0.05)
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.classification, BrowserSwitchResult.Classification.mixed)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPHandler?.applicationURL.standardizedFileURL.path, mixedSnapshot.currentHTTPHandler?.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(result.verifiedSnapshot?.currentHTTPSHandler?.applicationURL.standardizedFileURL.path, mixedSnapshot.currentHTTPSHandler?.applicationURL.standardizedFileURL.path)
        XCTAssertEqual(result.verifiedSnapshot?.candidates.map { $0.applicationURL.standardizedFileURL.path }, mixedSnapshot.candidates.map { $0.applicationURL.standardizedFileURL.path })
        XCTAssertEqual(result.schemeOutcomes.map { $0.status }, [BrowserSwitchSchemeOutcome.Status.success, BrowserSwitchSchemeOutcome.Status.failure])
        XCTAssertEqual(result.schemeOutcomes.last?.errorMessage, FixtureWorkspaceError.httpsWriteFailed.errorDescription)
        XCTAssertEqual(result.mismatchDetails, ["https handler remained Safari"])
    }

    func testSwitchDefaultBrowserMarksTimedOutSchemesAndReadbackFailure() async {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let workspace = FakeBrowserWorkspace(
            currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
            candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]],
            switchCompletionResults: [.http: .success, .https: .noCallback],
            postSwitchSnapshot: nil,
            postSwitchReadError: FixtureWorkspaceError.readbackFailed
        )
        let service = SystemBrowserDiscoveryService(workspace: workspace, completionTimeout: 0.01)
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.classification, BrowserSwitchResult.Classification.failure)
        XCTAssertNil(result.verifiedSnapshot)
        XCTAssertEqual(result.readbackErrorMessage, FixtureWorkspaceError.readbackFailed.errorDescription)
        XCTAssertEqual(result.schemeOutcomes.map { $0.status }, [BrowserSwitchSchemeOutcome.Status.success, BrowserSwitchSchemeOutcome.Status.timedOut])
        XCTAssertEqual(result.schemeOutcomes.last?.scheme, BrowserURLScheme.https)
    }
}

private final class FakeBrowserWorkspace: BrowserWorkspace {
    var currentHandlers: [BrowserURLScheme: URL]
    let candidateURLs: [BrowserURLScheme: [URL]]
    let switchCompletionResults: [BrowserURLScheme: SwitchCompletionBehavior]
    let postSwitchSnapshot: BrowserDiscoverySnapshot?
    let postSwitchReadError: Error?
    let delayedPostSwitchReadCallCount: Int
    private let lock = NSLock()
    private(set) var recordedSwitchSchemes: [BrowserURLScheme] = []
    private(set) var recordedSwitchTargets: [URL] = []
    private var hasSwitched = false
    private var postSwitchReadCalls = 0

    init(
        currentHandlers: [BrowserURLScheme: URL],
        candidateURLs: [BrowserURLScheme: [URL]],
        switchCompletionResults: [BrowserURLScheme: SwitchCompletionBehavior],
        postSwitchSnapshot: BrowserDiscoverySnapshot?,
        postSwitchReadError: Error? = nil,
        delayedPostSwitchReadCallCount: Int = 0
    ) {
        self.currentHandlers = currentHandlers
        self.candidateURLs = candidateURLs
        self.switchCompletionResults = switchCompletionResults
        self.postSwitchSnapshot = postSwitchSnapshot
        self.postSwitchReadError = postSwitchReadError
        self.delayedPostSwitchReadCallCount = delayedPostSwitchReadCallCount
    }

    func currentHandlerURL(for scheme: BrowserURLScheme) throws -> URL? {
        let state = readState()
        if let postSwitchReadError = state.postSwitchReadError {
            throw postSwitchReadError
        }

        if let snapshot = state.snapshot {
            return snapshot.currentHandler(for: scheme)?.applicationURL
        }

        return currentHandlers[scheme]
    }

    func candidateHandlerURLs(for scheme: BrowserURLScheme) throws -> [URL] {
        let state = readState()
        if let postSwitchReadError = state.postSwitchReadError {
            throw postSwitchReadError
        }

        if let snapshot = state.snapshot {
            return snapshot.candidates.filter { $0.supports(scheme) }.map(\.applicationURL)
        }

        return candidateURLs[scheme] ?? []
    }

    func setDefaultApplication(at applicationURL: URL, for scheme: BrowserURLScheme, completionHandler: @escaping @Sendable (Error?) -> Void) {
        lock.lock()
        recordedSwitchSchemes.append(scheme)
        recordedSwitchTargets.append(applicationURL)
        hasSwitched = true
        lock.unlock()

        switch switchCompletionResults[scheme] ?? .success {
        case .success:
            completionHandler(nil)
        case let .failure(error):
            completionHandler(error)
        case .noCallback:
            return
        }
    }

    private func readState() -> (snapshot: BrowserDiscoverySnapshot?, postSwitchReadError: Error?) {
        lock.lock()
        defer { lock.unlock() }

        guard hasSwitched else {
            return (nil, nil)
        }

        if let postSwitchReadError {
            return (nil, postSwitchReadError)
        }

        guard let postSwitchSnapshot else {
            return (nil, nil)
        }

        defer {
            postSwitchReadCalls += 1
        }

        guard postSwitchReadCalls >= delayedPostSwitchReadCallCount else {
            return (nil, nil)
        }

        return (postSwitchSnapshot, nil)
    }
}

private enum SwitchCompletionBehavior {
    case success
    case failure(Error)
    case noCallback

    init(_ error: Error?) {
        if let error {
            self = .failure(error)
        } else {
            self = .success
        }
    }
}

private enum FixtureWorkspaceError: LocalizedError {
    case httpsWriteFailed
    case readbackFailed

    var errorDescription: String? {
        switch self {
        case .httpsWriteFailed:
            return "Injected https write failure"
        case .readbackFailed:
            return "Injected readback failure"
        }
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
