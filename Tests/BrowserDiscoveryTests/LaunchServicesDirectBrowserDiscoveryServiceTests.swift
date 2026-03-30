import XCTest
@testable import DefaultBrowserSwitcher

final class LaunchServicesDirectBrowserDiscoveryServiceTests: XCTestCase {
    func testPreferencesWriterReplacesBrowserHandlersAndPreservesUnrelatedEntries() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferencesURL = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let originalHandlers: [[String: Any]] = [
            [
                "LSHandlerURLScheme": "mailto",
                "LSHandlerRoleAll": "com.apple.mail",
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"]
            ],
            [
                "LSHandlerURLScheme": "http",
                "LSHandlerRoleAll": "com.apple.safari",
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"]
            ],
            [
                "LSHandlerContentType": "public.html",
                "LSHandlerRoleAll": "com.apple.safari",
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"]
            ]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["LSHandlers": originalHandlers, "PreservedKey": "value"],
            format: .binary,
            options: 0
        )
        try data.write(to: preferencesURL)

        let writer = LaunchServicesPreferencesWriter(preferencesURL: preferencesURL)
        try writer.setDefaultBrowser(bundleIdentifier: "com.google.Chrome")

        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: preferencesURL), options: [], format: nil) as? [String: Any]
        )
        let handlers = try XCTUnwrap(propertyList["LSHandlers"] as? [[String: Any]])

        XCTAssertEqual(propertyList["PreservedKey"] as? String, "value")
        XCTAssertEqual(handlers.count, 6)
        XCTAssertEqual(handlers.filter { LaunchServicesPreferencesWriter.isBrowserHandler($0) }.count, 5)
        XCTAssertEqual(handlers.first(where: { ($0["LSHandlerURLScheme"] as? String) == "mailto" })?["LSHandlerRoleAll"] as? String, "com.apple.mail")
        XCTAssertEqual(handlers.first(where: { ($0["LSHandlerURLScheme"] as? String) == "http" })?["LSHandlerRoleAll"] as? String, "com.google.Chrome")
        XCTAssertEqual(handlers.first(where: { ($0["LSHandlerContentType"] as? String) == "public.html" })?["LSHandlerRoleAll"] as? String, "com.google.Chrome")
    }

    func testPreferencesWriterCreatesBrowserHandlersWhenFileDoesNotExist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferencesURL = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let writer = LaunchServicesPreferencesWriter(preferencesURL: preferencesURL)

        try writer.setDefaultBrowser(bundleIdentifier: "company.theBrowser")

        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: preferencesURL), options: [], format: nil) as? [String: Any]
        )
        let handlers = try XCTUnwrap(propertyList["LSHandlers"] as? [[String: Any]])
        XCTAssertEqual(handlers.count, 5)
        XCTAssertTrue(handlers.allSatisfy { LaunchServicesPreferencesWriter.isBrowserHandler($0) })
    }

    func testDirectServiceFailsWhenTargetBundleIdentifierIsMissing() async {
        let directory = try! makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = RecordingPreferencesWriter()
        let runner = RecordingCommandRunner()
        let service = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [
                    .http: URL(fileURLWithPath: "/Applications/Safari.app"),
                    .https: URL(fileURLWithPath: "/Applications/Safari.app")
                ],
                candidateURLs: [
                    .http: [URL(fileURLWithPath: "/Applications/Safari.app")],
                    .https: [URL(fileURLWithPath: "/Applications/Safari.app")]
                ]
            ),
            completionTimeout: 0.01,
            preferencesWriter: writer,
            commandRunner: runner,
            preferencesURL: directory.appendingPathComponent("ignored.plist")
        )
        let target = BrowserSwitchTarget(
            bundleIdentifier: nil,
            displayName: "Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/Browser.app")
        )

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(result.schemeOutcomes.map(\.status), [.failure, .failure])
        XCTAssertFalse(writer.didWrite)
        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testDirectServiceReturnsOptimisticSuccessAndSchedulesBackgroundActivation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let baselineSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_800)
        )

        let writer = RecordingPreferencesWriter()
        let runner = RecordingCommandRunner()
        let service = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
                candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]]
            ),
            completionTimeout: 0.01,
            preferencesWriter: writer,
            commandRunner: runner,
            preferencesURL: directory.appendingPathComponent("ignored.plist")
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))

        let result = await service.switchDefaultBrowser(to: target, baselineSnapshot: baselineSnapshot)

        XCTAssertTrue(writer.didWrite)
        XCTAssertEqual(runner.commands, [.init(path: "/usr/bin/killall", arguments: ["lsd"])])
        XCTAssertEqual(result.evidence, .optimistic)
        XCTAssertEqual(result.classification, .success)
        XCTAssertNil(result.verifiedSnapshot)
        XCTAssertEqual(result.optimisticSnapshot, baselineSnapshot.projectedSwitchSnapshot(for: target))
    }

    func testDirectServiceFailsWhenBackgroundActivationCannotBeStarted() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = RecordingPreferencesWriter()
        let runner = RecordingCommandRunner()
        runner.error = LaunchServicesDirectBrowserDiscoveryServiceError.commandFailed("killall", "launch failed")
        let service = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [
                    .http: URL(fileURLWithPath: "/Applications/Safari.app"),
                    .https: URL(fileURLWithPath: "/Applications/Safari.app")
                ],
                candidateURLs: [
                    .http: [URL(fileURLWithPath: "/Applications/Safari.app")],
                    .https: [URL(fileURLWithPath: "/Applications/Safari.app")]
                ]
            ),
            completionTimeout: 0.01,
            preferencesWriter: writer,
            commandRunner: runner,
            preferencesURL: directory.appendingPathComponent("ignored.plist")
        )
        let target = BrowserSwitchTarget(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )

        let result = await service.switchDefaultBrowser(to: target)

        XCTAssertTrue(writer.didWrite)
        XCTAssertEqual(runner.commands, [.init(path: "/usr/bin/killall", arguments: ["lsd"])])
        XCTAssertEqual(result.classification, .failure)
        XCTAssertEqual(result.evidence, .verified)
        XCTAssertNil(result.optimisticSnapshot)
        XCTAssertEqual(result.readbackErrorMessage, "killall failed: launch failed")
    }

    func testOptimisticVerificationUsesPreferencesAsPrimarySourceAndWorkspaceAsSecondaryProbe() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferencesURL = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let writer = LaunchServicesPreferencesWriter(preferencesURL: preferencesURL)
        try writer.setDefaultBrowser(bundleIdentifier: "company.theBrowser")

        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "company.theBrowser", displayName: "Arc", path: "/Applications/Arc.app")
        let baselineSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_801)
        )

        let service = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
                candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]]
            ),
            completionTimeout: 0.01,
            preferencesWriter: writer,
            preferencesReader: writer,
            commandRunner: RecordingCommandRunner(),
            preferencesURL: preferencesURL
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let lastSwitchResult = BrowserSwitchResult.optimisticSuccess(
            target: target,
            optimisticSnapshot: baselineSnapshot.projectedSwitchSnapshot(for: target),
            completedAt: Date(timeIntervalSince1970: 1_710_200_802)
        )

        let rawOutcome = await service.reconcileOptimisticSwitch(lastSwitchResult: lastSwitchResult)
        let outcome = try XCTUnwrap(rawOutcome)

        XCTAssertTrue(outcome.isAuthoritative)
        XCTAssertEqual(outcome.result.classification, BrowserSwitchResult.Classification.success)
        XCTAssertEqual(outcome.result.verifiedSnapshot?.coherentCurrentBrowser?.resolvedDisplayName, "Arc")
        XCTAssertEqual(
            outcome.logs,
            [
                BrowserOptimisticVerificationLog(
                    level: .warning,
                    message: "Workspace readback still reported Safari for the HTTP sample URL."
                )
            ]
        )
    }

    func testOptimisticVerificationFailsWhenPreferencesStillReportOldBrowser() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let preferencesURL = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let writer = LaunchServicesPreferencesWriter(preferencesURL: preferencesURL)
        try writer.setDefaultBrowser(bundleIdentifier: "com.apple.Safari")

        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "company.theBrowser", displayName: "Arc", path: "/Applications/Arc.app")
        let baselineSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_803)
        )

        let service = LaunchServicesDirectBrowserDiscoveryService(
            workspace: StaticBrowserWorkspace(
                currentHandlers: [.http: safari.applicationURL, .https: safari.applicationURL],
                candidateURLs: [.http: [safari.applicationURL, chrome.applicationURL], .https: [safari.applicationURL, chrome.applicationURL]]
            ),
            completionTimeout: 0.01,
            preferencesWriter: writer,
            preferencesReader: writer,
            commandRunner: RecordingCommandRunner(),
            preferencesURL: preferencesURL
        )
        let target = BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        let lastSwitchResult = BrowserSwitchResult.optimisticSuccess(
            target: target,
            optimisticSnapshot: baselineSnapshot.projectedSwitchSnapshot(for: target),
            completedAt: Date(timeIntervalSince1970: 1_710_200_804)
        )

        let rawOutcome = await service.reconcileOptimisticSwitch(lastSwitchResult: lastSwitchResult)
        let outcome = try XCTUnwrap(rawOutcome)

        XCTAssertTrue(outcome.isAuthoritative)
        XCTAssertEqual(outcome.result.classification, BrowserSwitchResult.Classification.failure)
        XCTAssertEqual(
            outcome.result.visibleErrorMessage,
            "LaunchServices preferences still reported Safari for the HTTP browser handler."
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchServicesDirectBrowserDiscoveryServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class RecordingPreferencesWriter: LaunchServicesPreferencesWriting {
    private(set) var didWrite = false

    func setDefaultBrowser(bundleIdentifier: String) throws {
        didWrite = true
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
