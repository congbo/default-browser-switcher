import AppKit
import Foundation

struct BrowserDiscoveryRuntime {
    let workspace: BrowserWorkspace
    let environment: [String: String]
    let completionTimeout: TimeInterval

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

    func awaitVerifiedReadback(
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
