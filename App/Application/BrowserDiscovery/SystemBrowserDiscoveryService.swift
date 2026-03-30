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
    private let runtime: BrowserDiscoveryRuntime
    private let completionTimeout: TimeInterval
    private let workspace: BrowserWorkspace

    init(
        workspace: BrowserWorkspace = NSWorkspace.shared,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        completionTimeout: TimeInterval = 5
    ) {
        runtime = BrowserDiscoveryRuntime(
            workspace: workspace,
            environment: environment,
            completionTimeout: completionTimeout
        )
        self.workspace = workspace
        self.completionTimeout = completionTimeout
    }

    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot {
        try await runtime.fetchSnapshot()
    }

    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot _: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult {
        async let httpOutcome = performSwitch(to: target, scheme: .http)
        async let httpsOutcome = performSwitch(to: target, scheme: .https)

        let schemeOutcomes = [await httpOutcome, await httpsOutcome]
        return await runtime.awaitVerifiedReadback(for: target, schemeOutcomes: schemeOutcomes)
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
