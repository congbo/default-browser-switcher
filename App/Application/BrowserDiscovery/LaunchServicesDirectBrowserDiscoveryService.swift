import AppKit
import Foundation

protocol CommandRunning {
    func runDetached(executableURL: URL, arguments: [String]) throws
}

struct ProcessCommandRunner: CommandRunning {
    func runDetached(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        try process.run()
    }
}

protocol LaunchServicesPreferencesWriting {
    func setDefaultBrowser(bundleIdentifier: String) throws
}

protocol LaunchServicesPreferencesReading {
    func readBrowserVerificationSnapshot() throws -> LaunchServicesVerificationSnapshot
}

enum LaunchServicesBrowserHandlerKey: CaseIterable, Equatable {
    case http
    case https
    case publicURL
    case publicHTML
    case publicXHTML

    var contentType: String? {
        switch self {
        case .publicURL:
            return "public.url"
        case .publicHTML:
            return "public.html"
        case .publicXHTML:
            return "public.xhtml"
        case .http, .https:
            return nil
        }
    }

    var scheme: String? {
        switch self {
        case .http:
            return "http"
        case .https:
            return "https"
        case .publicURL, .publicHTML, .publicXHTML:
            return nil
        }
    }

    var preferencesLabel: String {
        switch self {
        case .http:
            return "HTTP browser handler"
        case .https:
            return "HTTPS browser handler"
        case .publicURL:
            return "public.url browser handler"
        case .publicHTML:
            return "public.html browser handler"
        case .publicXHTML:
            return "public.xhtml browser handler"
        }
    }

    var workspaceProbeLabel: String? {
        switch self {
        case .http:
            return "HTTP sample URL"
        case .https:
            return "HTTPS sample URL"
        case .publicURL, .publicHTML, .publicXHTML:
            return nil
        }
    }

    func matches(_ handler: [String: Any]) -> Bool {
        if let contentType {
            return handler["LSHandlerContentType"] as? String == contentType
        }

        if let scheme {
            return handler["LSHandlerURLScheme"] as? String == scheme
        }

        return false
    }
}

struct LaunchServicesVerificationSnapshot: Equatable {
    struct Entry: Equatable {
        let key: LaunchServicesBrowserHandlerKey
        let bundleIdentifier: String?
    }

    let entries: [Entry]

    func bundleIdentifier(for key: LaunchServicesBrowserHandlerKey) -> String? {
        entries.first(where: { $0.key == key })?.bundleIdentifier
    }

    func firstMismatchedKey(expected bundleIdentifier: String) -> LaunchServicesBrowserHandlerKey? {
        LaunchServicesBrowserHandlerKey.allCases.first { key in
            self.bundleIdentifier(for: key) != bundleIdentifier
        }
    }
}

enum LaunchServicesDirectBrowserDiscoveryServiceError: LocalizedError {
    case unsupportedTarget(String)
    case invalidPreferencesFile
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedTarget(identifier):
            return BrowserDiscoveryServiceError.unsupportedTarget(identifier).errorDescription
        case .invalidPreferencesFile:
            return "The LaunchServices preferences file is not a property-list dictionary."
        case let .commandFailed(command, reason):
            return "\(command) failed: \(reason)"
        }
    }
}

struct LaunchServicesPreferencesWriter: LaunchServicesPreferencesWriting {
    static let defaultRelativePath = "Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"

    let preferencesURL: URL
    let fileManager: FileManager

    init(
        preferencesURL: URL,
        fileManager: FileManager = .default
    ) {
        self.preferencesURL = preferencesURL
        self.fileManager = fileManager
    }

    func setDefaultBrowser(bundleIdentifier: String) throws {
        var root = try loadRootDictionary()
        var handlers = (root["LSHandlers"] as? [[String: Any]]) ?? []
        handlers.removeAll(where: Self.isBrowserHandler(_:))
        handlers.append(contentsOf: Self.browserHandlers(for: bundleIdentifier))
        root["LSHandlers"] = handlers

        try fileManager.createDirectory(
            at: preferencesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try data.write(to: preferencesURL, options: .atomic)
    }

    private func loadRootDictionary() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: preferencesURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: preferencesURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        guard let dictionary = propertyList as? [String: Any] else {
            throw LaunchServicesDirectBrowserDiscoveryServiceError.invalidPreferencesFile
        }

        return dictionary
    }

    static func browserHandlers(for bundleIdentifier: String) -> [[String: Any]] {
        [
            [
                "LSHandlerContentType": "public.url",
                "LSHandlerPreferredVersions": ["LSHandlerRoleViewer": "-"],
                "LSHandlerRoleViewer": bundleIdentifier
            ],
            [
                "LSHandlerContentType": "public.xhtml",
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                "LSHandlerRoleAll": bundleIdentifier
            ],
            [
                "LSHandlerContentType": "public.html",
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                "LSHandlerRoleAll": bundleIdentifier
            ],
            [
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                "LSHandlerRoleAll": bundleIdentifier,
                "LSHandlerURLScheme": "https"
            ],
            [
                "LSHandlerPreferredVersions": ["LSHandlerRoleAll": "-"],
                "LSHandlerRoleAll": bundleIdentifier,
                "LSHandlerURLScheme": "http"
            ]
        ]
    }

    static func isBrowserHandler(_ handler: [String: Any]) -> Bool {
        let contentType = handler["LSHandlerContentType"] as? String
        let scheme = handler["LSHandlerURLScheme"] as? String
        return ["public.url", "public.xhtml", "public.html"].contains(contentType)
            || ["http", "https"].contains(scheme)
    }
}

extension LaunchServicesPreferencesWriter: LaunchServicesPreferencesReading {
    func readBrowserVerificationSnapshot() throws -> LaunchServicesVerificationSnapshot {
        let root = try loadRootDictionary()
        let handlers = (root["LSHandlers"] as? [[String: Any]]) ?? []

        let entries = LaunchServicesBrowserHandlerKey.allCases.map { key in
            LaunchServicesVerificationSnapshot.Entry(
                key: key,
                bundleIdentifier: handlers.last(where: { key.matches($0) }).flatMap(Self.bundleIdentifier(in:))
            )
        }

        return LaunchServicesVerificationSnapshot(entries: entries)
    }

    private static func bundleIdentifier(in handler: [String: Any]) -> String? {
        let viewer = (handler["LSHandlerRoleViewer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let viewer, !viewer.isEmpty {
            return viewer
        }

        let all = (handler["LSHandlerRoleAll"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let all, !all.isEmpty {
            return all
        }

        return nil
    }
}

struct LaunchServicesDirectBrowserDiscoveryService: BrowserDiscoveryService, BrowserOptimisticSwitchVerifying {
    private let runtime: BrowserDiscoveryRuntime
    private let preferencesWriter: any LaunchServicesPreferencesWriting
    private let preferencesReader: any LaunchServicesPreferencesReading
    private let commandRunner: any CommandRunning
    private let killallURL: URL

    init(
        workspace: BrowserWorkspace = NSWorkspace.shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        completionTimeout: TimeInterval = 5,
        preferencesWriter: (any LaunchServicesPreferencesWriting)? = nil,
        preferencesReader: (any LaunchServicesPreferencesReading)? = nil,
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        preferencesURL: URL? = nil,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        killallURL: URL = URL(fileURLWithPath: "/usr/bin/killall")
    ) {
        runtime = BrowserDiscoveryRuntime(
            workspace: workspace,
            environment: environment,
            completionTimeout: completionTimeout
        )
        self.commandRunner = commandRunner
        self.killallURL = killallURL
        let resolvedPreferencesStore = LaunchServicesPreferencesWriter(
            preferencesURL: preferencesURL ?? homeDirectoryURL.appendingPathComponent(LaunchServicesPreferencesWriter.defaultRelativePath)
        )
        self.preferencesWriter = preferencesWriter ?? resolvedPreferencesStore
        self.preferencesReader = preferencesReader ?? resolvedPreferencesStore
    }

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        try await runtime.fetchSnapshot()
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        let bundleIdentifier: String

        do {
            bundleIdentifier = try validatedBundleIdentifier(from: target)
        } catch {
            let message = error.localizedDescription
            return BrowserSwitchResult.serviceFailure(
                target: target,
                schemeOutcomes: BrowserURLScheme.allCases.map { .failure($0, message: message) },
                readbackErrorMessage: message
            )
        }

        do {
            try preferencesWriter.setDefaultBrowser(bundleIdentifier: bundleIdentifier)
            try commandRunner.runDetached(
                executableURL: killallURL,
                arguments: ["lsd"]
            )

            let optimisticSnapshot = await makeOptimisticSnapshot(
                for: target,
                baselineSnapshot: baselineSnapshot
            )
            return .optimisticSuccess(
                target: target,
                optimisticSnapshot: optimisticSnapshot
            )
        } catch {
            let message = error.localizedDescription
            return BrowserSwitchResult.serviceFailure(
                target: target,
                schemeOutcomes: BrowserURLScheme.allCases.map { .failure($0, message: message) },
                readbackErrorMessage: message
            )
        }
    }

    func reconcileOptimisticSwitch(lastSwitchResult: BrowserSwitchResult) async -> BrowserOptimisticVerificationOutcome? {
        guard lastSwitchResult.evidence == .optimistic else {
            return nil
        }

        let target = lastSwitchResult.requestedTarget
        let expectedBundleIdentifier: String

        do {
            expectedBundleIdentifier = try validatedBundleIdentifier(from: target)
        } catch {
            return BrowserOptimisticVerificationOutcome(
                result: .serviceFailure(
                    target: target,
                    schemeOutcomes: lastSwitchResult.schemeOutcomes,
                    readbackErrorMessage: error.localizedDescription,
                    completedAt: lastSwitchResult.completedAt
                ),
                logs: [],
                isAuthoritative: true
            )
        }

        let workspaceProbeSnapshot: BrowserDiscoverySnapshot?
        let workspaceProbeLog: BrowserOptimisticVerificationLog?
        do {
            let snapshot = try await runtime.fetchSnapshot()
            workspaceProbeSnapshot = snapshot
            workspaceProbeLog = workspaceProbeLogMessage(
                target: target,
                snapshot: snapshot,
                baselineSnapshot: lastSwitchResult.optimisticSnapshot
            )
        } catch {
            workspaceProbeSnapshot = nil
            workspaceProbeLog = .init(
                level: .error,
                message: "Workspace readback failed for sample URLs: \(error.localizedDescription)"
            )
        }

        do {
            let verificationSnapshot = try preferencesReader.readBrowserVerificationSnapshot()
            if let mismatchedKey = verificationSnapshot.firstMismatchedKey(expected: expectedBundleIdentifier) {
                let reportedName = resolveDisplayName(
                    for: verificationSnapshot.bundleIdentifier(for: mismatchedKey),
                    target: target,
                    baselineSnapshot: lastSwitchResult.optimisticSnapshot,
                    workspaceSnapshot: workspaceProbeSnapshot
                )
                let message = "LaunchServices preferences still reported \(reportedName) for the \(mismatchedKey.preferencesLabel)."
                let result: BrowserSwitchResult
                if let workspaceProbeSnapshot {
                    result = .verifiedFailure(
                        target: target,
                        verifiedSnapshot: workspaceProbeSnapshot,
                        schemeOutcomes: lastSwitchResult.schemeOutcomes,
                        mismatchDetails: [message],
                        completedAt: lastSwitchResult.completedAt
                    )
                } else {
                    result = .serviceFailure(
                        target: target,
                        schemeOutcomes: lastSwitchResult.schemeOutcomes,
                        readbackErrorMessage: message,
                        completedAt: lastSwitchResult.completedAt
                    )
                }

                return BrowserOptimisticVerificationOutcome(
                    result: result,
                    logs: workspaceProbeLog.map { [$0] } ?? [],
                    isAuthoritative: true
                )
            }

            let verifiedSnapshot = makePrimaryVerifiedSnapshot(
                for: target,
                workspaceSnapshot: workspaceProbeSnapshot,
                baselineSnapshot: lastSwitchResult.optimisticSnapshot
            )
            return BrowserOptimisticVerificationOutcome(
                result: .verifiedSuccess(
                    target: target,
                    verifiedSnapshot: verifiedSnapshot,
                    completedAt: lastSwitchResult.completedAt
                ),
                logs: workspaceProbeLog.map { [$0] } ?? [],
                isAuthoritative: true
            )
        } catch {
            return BrowserOptimisticVerificationOutcome(
                result: .serviceFailure(
                    target: target,
                    schemeOutcomes: lastSwitchResult.schemeOutcomes,
                    readbackErrorMessage: "LaunchServices preferences readback failed: \(error.localizedDescription)",
                    completedAt: lastSwitchResult.completedAt
                ),
                logs: workspaceProbeLog.map { [$0] } ?? [],
                isAuthoritative: true
            )
        }
    }

    private func validatedBundleIdentifier(from target: BrowserSwitchTarget) throws -> String {
        guard let bundleIdentifier = target.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            throw LaunchServicesDirectBrowserDiscoveryServiceError.unsupportedTarget(target.id)
        }

        return bundleIdentifier
    }

    private func makeOptimisticSnapshot(
        for target: BrowserSwitchTarget,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) async -> BrowserDiscoverySnapshot {
        if let baselineSnapshot {
            return baselineSnapshot.projectedSwitchSnapshot(for: target)
        }

        if let fetchedSnapshot = try? await runtime.fetchSnapshot() {
            return fetchedSnapshot.projectedSwitchSnapshot(for: target)
        }

        return BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: BrowserApplication(
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.displayName,
                applicationURL: target.applicationURL
            ),
            currentHTTPSHandler: BrowserApplication(
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.displayName,
                applicationURL: target.applicationURL
            ),
            httpCandidates: [
                BrowserApplication(
                    bundleIdentifier: target.bundleIdentifier,
                    displayName: target.displayName,
                    applicationURL: target.applicationURL
                )
            ],
            httpsCandidates: [
                BrowserApplication(
                    bundleIdentifier: target.bundleIdentifier,
                    displayName: target.displayName,
                    applicationURL: target.applicationURL
                )
            ]
        )
    }

    private func makePrimaryVerifiedSnapshot(
        for target: BrowserSwitchTarget,
        workspaceSnapshot: BrowserDiscoverySnapshot?,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) -> BrowserDiscoverySnapshot {
        if let workspaceSnapshot {
            return workspaceSnapshot.projectedSwitchSnapshot(for: target)
        }

        if let baselineSnapshot {
            return baselineSnapshot.projectedSwitchSnapshot(for: target)
        }

        return BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: BrowserApplication(
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.displayName,
                applicationURL: target.applicationURL
            ),
            currentHTTPSHandler: BrowserApplication(
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.displayName,
                applicationURL: target.applicationURL
            ),
            httpCandidates: [],
            httpsCandidates: []
        )
    }

    private func workspaceProbeLogMessage(
        target: BrowserSwitchTarget,
        snapshot: BrowserDiscoverySnapshot,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) -> BrowserOptimisticVerificationLog? {
        for key in [LaunchServicesBrowserHandlerKey.http, LaunchServicesBrowserHandlerKey.https] {
            guard let probeLabel = key.workspaceProbeLabel,
                  let handler = snapshot.currentHandler(for: key == .http ? .http : .https)
            else {
                continue
            }

            guard handler.applicationURL.standardizedFileURL.path != target.id else {
                continue
            }

            let reportedName = resolveDisplayName(
                for: handler.bundleIdentifier,
                fallbackApplication: handler,
                target: target,
                baselineSnapshot: baselineSnapshot,
                workspaceSnapshot: snapshot
            )
            return BrowserOptimisticVerificationLog(
                level: .warning,
                message: "Workspace readback still reported \(reportedName) for the \(probeLabel)."
            )
        }

        return nil
    }

    private func resolveDisplayName(
        for bundleIdentifier: String?,
        fallbackApplication: BrowserApplication? = nil,
        target: BrowserSwitchTarget,
        baselineSnapshot: BrowserDiscoverySnapshot?,
        workspaceSnapshot: BrowserDiscoverySnapshot?
    ) -> String {
        if let fallbackApplication {
            return fallbackApplication.resolvedDisplayName
        }

        let candidates = (baselineSnapshot?.candidates ?? []) + (workspaceSnapshot?.candidates ?? [])
        if let bundleIdentifier,
           let match = candidates.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return match.resolvedDisplayName
        }

        if let bundleIdentifier, bundleIdentifier == target.bundleIdentifier {
            return target.displayName
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return "an unknown browser"
    }
}
