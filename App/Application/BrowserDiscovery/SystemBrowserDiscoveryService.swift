import AppKit
import Foundation

protocol BrowserWorkspace: AnyObject {
    func currentHandlerURL(for scheme: BrowserURLScheme) throws -> URL?
    func candidateHandlerURLs(for scheme: BrowserURLScheme) throws -> [URL]
    func setDefaultApplication(
        at applicationURL: URL,
        for scheme: BrowserURLScheme,
        completionHandler: @escaping @Sendable (Error?) -> Void
    )
}

extension NSWorkspace: BrowserWorkspace {
    func currentHandlerURL(for scheme: BrowserURLScheme) throws -> URL? {
        guard let sampleURL = URL(string: "\(scheme.rawValue)://example.com") else {
            throw BrowserDiscoveryServiceError.invalidSampleURL(scheme.rawValue)
        }

        return urlForApplication(toOpen: sampleURL)
    }

    func candidateHandlerURLs(for scheme: BrowserURLScheme) throws -> [URL] {
        guard let sampleURL = URL(string: "\(scheme.rawValue)://example.com") else {
            throw BrowserDiscoveryServiceError.invalidSampleURL(scheme.rawValue)
        }

        return urlsForApplications(toOpen: sampleURL)
    }

    func setDefaultApplication(
        at applicationURL: URL,
        for scheme: BrowserURLScheme,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: scheme.rawValue, completion: completionHandler)
    }
}

struct SystemBrowserDiscoveryService: BrowserDiscoveryService {
    private let workspace: BrowserWorkspace
    private let environment: [String: String]
    private let completionTimeout: TimeInterval

    init(
        workspace: BrowserWorkspace = NSWorkspace.shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        completionTimeout: TimeInterval = 5
    ) {
        self.workspace = workspace
        self.environment = environment
        self.completionTimeout = completionTimeout
    }

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        if let forcedMessage = environment["DEFAULT_BROWSER_SWITCHER_FORCE_DISCOVERY_ERROR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !forcedMessage.isEmpty {
            throw BrowserDiscoveryServiceError.forcedFailure(forcedMessage)
        }

        let currentHTTPHandler = try workspace.currentHandlerURL(for: .http).map(resolveApplication(at:))
        let currentHTTPSHandler = try workspace.currentHandlerURL(for: .https).map(resolveApplication(at:))
        let httpCandidates = try workspace.candidateHandlerURLs(for: .http).map(resolveApplication(at:))
        let httpsCandidates = try workspace.candidateHandlerURLs(for: .https).map(resolveApplication(at:))

        return BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: currentHTTPHandler,
            currentHTTPSHandler: currentHTTPSHandler,
            httpCandidates: httpCandidates,
            httpsCandidates: httpsCandidates,
            refreshedAt: .now
        )
    }

    func switchDefaultBrowser(to target: BrowserSwitchTarget) async -> BrowserSwitchResult {
        async let httpOutcome = performSwitch(to: target, scheme: .http)
        async let httpsOutcome = performSwitch(to: target, scheme: .https)

        let schemeOutcomes = [await httpOutcome, await httpsOutcome]
        return await awaitVerifiedReadback(for: target, schemeOutcomes: schemeOutcomes)
    }

    private func awaitVerifiedReadback(
        for target: BrowserSwitchTarget,
        schemeOutcomes: [BrowserSwitchSchemeOutcome]
    ) async -> BrowserSwitchResult {
        let timeout = max(completionTimeout, 0)
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval = verificationPollInterval(for: timeout)
        var lastVerifiedResult: BrowserSwitchResult?
        var lastReadbackErrorMessage: String?

        while true {
            do {
                let verifiedSnapshot = try await fetchSnapshot()
                let result = BrowserSwitchResult.verified(
                    target: target,
                    schemeOutcomes: schemeOutcomes,
                    verifiedSnapshot: verifiedSnapshot,
                    completedAt: .now
                )

                if result.classification == .success {
                    return result
                }

                lastVerifiedResult = result
            } catch {
                lastReadbackErrorMessage = error.localizedDescription
            }

            guard Date() < deadline else {
                break
            }

            try? await Task.sleep(nanoseconds: pollInterval)
        }

        if let lastVerifiedResult {
            return lastVerifiedResult
        }

        return BrowserSwitchResult.serviceFailure(
            target: target,
            schemeOutcomes: schemeOutcomes,
            readbackErrorMessage: lastReadbackErrorMessage ?? "Unable to verify the system default browser state after switching.",
            completedAt: .now
        )
    }

    private func verificationPollInterval(for timeout: TimeInterval) -> UInt64 {
        let boundedInterval = max(0.05, min(timeout / 10, 0.25))
        return UInt64(boundedInterval * 1_000_000_000)
    }

    private func performSwitch(to target: BrowserSwitchTarget, scheme: BrowserURLScheme) async -> BrowserSwitchSchemeOutcome {
        await withCheckedContinuation { continuation in
            let resolver = SwitchContinuationResolver(continuation: continuation)
            let standardizedURL = target.applicationURL.standardizedFileURL

            workspace.setDefaultApplication(at: standardizedURL, for: scheme) { error in
                if let error {
                    resolver.resolve(.failure(scheme, message: error.localizedDescription))
                } else {
                    resolver.resolve(.success(scheme))
                }
            }

            Task {
                let nanoseconds = UInt64(max(completionTimeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                let message = BrowserDiscoveryServiceError.switchTimedOut(scheme).errorDescription ?? "Timed out waiting for the \(scheme.rawValue) switch completion callback."
                resolver.resolve(.timedOut(scheme, message: message))
            }
        }
    }

    private func resolveApplication(at url: URL) -> BrowserApplication {
        let standardizedURL = url.standardizedFileURL
        let bundle = Bundle(url: standardizedURL)
        let displayName = [
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
            FileManager.default.displayName(atPath: standardizedURL.path)
        ]
            .compactMap { candidate in
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .first

        return BrowserApplication(
            bundleIdentifier: bundle?.bundleIdentifier,
            displayName: displayName,
            applicationURL: standardizedURL
        )
    }
}

private final class SwitchContinuationResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<BrowserSwitchSchemeOutcome, Never>?
    private var didResolve = false

    init(continuation: CheckedContinuation<BrowserSwitchSchemeOutcome, Never>) {
        self.continuation = continuation
    }

    func resolve(_ outcome: BrowserSwitchSchemeOutcome) {
        lock.lock()
        guard !didResolve, let continuation else {
            lock.unlock()
            return
        }

        didResolve = true
        self.continuation = nil
        lock.unlock()

        continuation.resume(returning: outcome)
    }
}
