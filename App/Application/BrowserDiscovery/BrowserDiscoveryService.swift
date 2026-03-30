import Foundation

protocol BrowserDiscoveryService {
    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot
    func switchDefaultBrowser(
        to target: BrowserSwitchTarget,
        baselineSnapshot: BrowserDiscoverySnapshot?
    ) async -> BrowserSwitchResult
}

extension BrowserDiscoveryService {
    func switchDefaultBrowser(to target: BrowserSwitchTarget) async -> BrowserSwitchResult {
        await switchDefaultBrowser(to: target, baselineSnapshot: nil)
    }
}

enum BrowserOptimisticVerificationLogLevel: Equatable {
    case info
    case warning
    case error
}

struct BrowserOptimisticVerificationLog: Equatable {
    let level: BrowserOptimisticVerificationLogLevel
    let message: String
}

struct BrowserOptimisticVerificationOutcome {
    let result: BrowserSwitchResult
    let logs: [BrowserOptimisticVerificationLog]
    let isAuthoritative: Bool
}

protocol BrowserOptimisticSwitchVerifying {
    func reconcileOptimisticSwitch(lastSwitchResult: BrowserSwitchResult) async -> BrowserOptimisticVerificationOutcome?
}

enum BrowserDiscoveryServiceError: LocalizedError {
    case forcedFailure(String)
    case invalidSampleURL(String)
    case unsupportedTarget(String)
    case switchTimedOut(BrowserURLScheme)

    var errorDescription: String? {
        switch self {
        case let .forcedFailure(message):
            return message
        case let .invalidSampleURL(sample):
            return "Unable to build a sample URL for \(sample) discovery."
        case let .unsupportedTarget(identifier):
            return "The requested browser target is not supported: \(identifier)"
        case let .switchTimedOut(scheme):
            return "Timed out waiting for the \(scheme.rawValue) switch completion callback."
        }
    }
}
