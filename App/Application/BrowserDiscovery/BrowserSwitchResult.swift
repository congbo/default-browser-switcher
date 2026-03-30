import Foundation

struct BrowserSwitchTarget: Codable, Hashable, Identifiable {
    let bundleIdentifier: String?
    let displayName: String
    let applicationURL: URL

    var id: String {
        applicationURL.standardizedFileURL.path
    }

    init(candidate: BrowserCandidate) {
        self.bundleIdentifier = candidate.bundleIdentifier
        self.displayName = candidate.resolvedDisplayName
        self.applicationURL = candidate.applicationURL.standardizedFileURL
    }

    init(bundleIdentifier: String?, displayName: String?, applicationURL: URL) {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = (trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        self.applicationURL = applicationURL.standardizedFileURL
    }
}

struct BrowserSwitchSchemeOutcome: Codable, Hashable {
    enum Status: String, Codable {
        case success
        case failure
        case timedOut
        case skipped
    }

    let scheme: BrowserURLScheme
    let status: Status
    let errorMessage: String?

    static func success(_ scheme: BrowserURLScheme) -> BrowserSwitchSchemeOutcome {
        BrowserSwitchSchemeOutcome(scheme: scheme, status: .success, errorMessage: nil)
    }

    static func skipped(_ scheme: BrowserURLScheme) -> BrowserSwitchSchemeOutcome {
        BrowserSwitchSchemeOutcome(scheme: scheme, status: .skipped, errorMessage: nil)
    }

    static func failure(_ scheme: BrowserURLScheme, message: String) -> BrowserSwitchSchemeOutcome {
        BrowserSwitchSchemeOutcome(scheme: scheme, status: .failure, errorMessage: message)
    }

    static func timedOut(_ scheme: BrowserURLScheme, message: String) -> BrowserSwitchSchemeOutcome {
        BrowserSwitchSchemeOutcome(scheme: scheme, status: .timedOut, errorMessage: message)
    }
}

struct BrowserSwitchResult: Codable, Hashable {
    enum Evidence: String, Codable {
        case verified
        case optimistic
    }

    enum Classification: String, Codable {
        case success
        case mixed
        case failure
    }

    let requestedTarget: BrowserSwitchTarget
    let schemeOutcomes: [BrowserSwitchSchemeOutcome]
    let evidence: Evidence
    let verifiedSnapshot: BrowserDiscoverySnapshot?
    let optimisticSnapshot: BrowserDiscoverySnapshot?
    let readbackErrorMessage: String?
    let classification: Classification
    let mismatchDetails: [String]
    let completedAt: Date

    static func verified(
        target: BrowserSwitchTarget,
        schemeOutcomes: [BrowserSwitchSchemeOutcome],
        verifiedSnapshot: BrowserDiscoverySnapshot,
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        let mismatchDetails = verificationDetails(target: target, snapshot: verifiedSnapshot)
        let classification: Classification
        if mismatchDetails.isEmpty {
            classification = .success
        } else if snapshotContainsTarget(target, in: verifiedSnapshot, schemes: BrowserURLScheme.allCases) {
            classification = .success
        } else if snapshotContainsTarget(target, in: verifiedSnapshot, schemes: [.http]) || snapshotContainsTarget(target, in: verifiedSnapshot, schemes: [.https]) {
            classification = .mixed
        } else {
            classification = .failure
        }

        return BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: completeOutcomes(schemeOutcomes),
            evidence: .verified,
            verifiedSnapshot: verifiedSnapshot,
            optimisticSnapshot: nil,
            readbackErrorMessage: nil,
            classification: classification,
            mismatchDetails: mismatchDetails,
            completedAt: completedAt
        )
    }

    static func verifiedSuccess(
        target: BrowserSwitchTarget,
        verifiedSnapshot: BrowserDiscoverySnapshot,
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: BrowserURLScheme.allCases.map(BrowserSwitchSchemeOutcome.success),
            evidence: .verified,
            verifiedSnapshot: verifiedSnapshot,
            optimisticSnapshot: nil,
            readbackErrorMessage: nil,
            classification: .success,
            mismatchDetails: [],
            completedAt: completedAt
        )
    }

    static func verifiedMixed(
        target: BrowserSwitchTarget,
        verifiedSnapshot: BrowserDiscoverySnapshot,
        schemeOutcomes: [BrowserSwitchSchemeOutcome]? = nil,
        mismatchDetails: [String],
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: completeOutcomes(schemeOutcomes ?? BrowserURLScheme.allCases.map(BrowserSwitchSchemeOutcome.success)),
            evidence: .verified,
            verifiedSnapshot: verifiedSnapshot,
            optimisticSnapshot: nil,
            readbackErrorMessage: nil,
            classification: .mixed,
            mismatchDetails: mismatchDetails,
            completedAt: completedAt
        )
    }

    static func verifiedFailure(
        target: BrowserSwitchTarget,
        verifiedSnapshot: BrowserDiscoverySnapshot? = nil,
        schemeOutcomes: [BrowserSwitchSchemeOutcome]? = nil,
        mismatchDetails: [String],
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: completeOutcomes(schemeOutcomes ?? BrowserURLScheme.allCases.map(BrowserSwitchSchemeOutcome.success)),
            evidence: .verified,
            verifiedSnapshot: verifiedSnapshot,
            optimisticSnapshot: nil,
            readbackErrorMessage: nil,
            classification: .failure,
            mismatchDetails: mismatchDetails,
            completedAt: completedAt
        )
    }

    static func optimisticSuccess(
        target: BrowserSwitchTarget,
        optimisticSnapshot: BrowserDiscoverySnapshot,
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: BrowserURLScheme.allCases.map(BrowserSwitchSchemeOutcome.success),
            evidence: .optimistic,
            verifiedSnapshot: nil,
            optimisticSnapshot: optimisticSnapshot,
            readbackErrorMessage: nil,
            classification: .success,
            mismatchDetails: [],
            completedAt: completedAt
        )
    }

    static func serviceFailure(
        target: BrowserSwitchTarget,
        schemeOutcomes: [BrowserSwitchSchemeOutcome]? = nil,
        readbackErrorMessage: String,
        completedAt: Date = .now
    ) -> BrowserSwitchResult {
        BrowserSwitchResult(
            requestedTarget: target,
            schemeOutcomes: completeOutcomes(schemeOutcomes ?? []),
            evidence: .verified,
            verifiedSnapshot: nil,
            optimisticSnapshot: nil,
            readbackErrorMessage: readbackErrorMessage,
            classification: .failure,
            mismatchDetails: [],
            completedAt: completedAt
        )
    }

    var visibleErrorMessage: String? {
        guard classification != .success else {
            return nil
        }

        if let readbackErrorMessage, !readbackErrorMessage.isEmpty {
            return readbackErrorMessage
        }

        if let firstSchemeError = schemeOutcomes.first(where: { $0.errorMessage?.isEmpty == false })?.errorMessage {
            return firstSchemeError
        }

        if let mismatch = mismatchDetails.first, !mismatch.isEmpty {
            return mismatch
        }

        return nil
    }

    private static func completeOutcomes(_ schemeOutcomes: [BrowserSwitchSchemeOutcome]) -> [BrowserSwitchSchemeOutcome] {
        var byScheme = Dictionary(uniqueKeysWithValues: schemeOutcomes.map { ($0.scheme, $0) })
        for scheme in BrowserURLScheme.allCases where byScheme[scheme] == nil {
            byScheme[scheme] = .timedOut(scheme, message: "No completion callback was received for \(scheme.rawValue).")
        }

        return BrowserURLScheme.allCases.compactMap { byScheme[$0] }
    }

    private static func verificationDetails(target: BrowserSwitchTarget, snapshot: BrowserDiscoverySnapshot) -> [String] {
        BrowserURLScheme.allCases.compactMap { scheme in
            guard let handler = snapshot.currentHandler(for: scheme) else {
                return "\(scheme.rawValue) handler is unavailable"
            }

            guard handler.applicationURL.standardizedFileURL.path != target.id else {
                return nil
            }

            return "\(scheme.rawValue) handler remained \(handler.resolvedDisplayName)"
        }
    }

    private static func snapshotContainsTarget(_ target: BrowserSwitchTarget, in snapshot: BrowserDiscoverySnapshot, schemes: [BrowserURLScheme]) -> Bool {
        schemes.allSatisfy { scheme in
            snapshot.currentHandler(for: scheme)?.applicationURL.standardizedFileURL.path == target.id
        }
    }
}
