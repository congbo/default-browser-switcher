import Foundation

protocol BrowserDiscoveryService {
    func fetchSnapshot() async throws -> BrowserDiscoverySnapshot
    func switchDefaultBrowser(to target: BrowserSwitchTarget) async -> BrowserSwitchResult
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
