import Foundation

enum BrowserURLScheme: String, CaseIterable, Codable, Hashable {
    case http
    case https
}

struct BrowserApplication: Codable, Hashable, Identifiable {
    let bundleIdentifier: String?
    let displayName: String?
    let applicationURL: URL

    var id: String {
        normalizedIdentifier(bundleIdentifier: bundleIdentifier, applicationURL: applicationURL)
    }

    var normalizedApplicationURL: URL {
        applicationURL.standardizedFileURL
    }

    var normalizedApplicationPath: String {
        normalizedApplicationURL.path
    }

    var resolvedDisplayName: String {
        displayName?.trimmedNonEmpty ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    var isNestedApplicationBundle: Bool {
        applicationURL.containsParentApplicationBundle
    }

    func merged(with other: BrowserApplication) -> BrowserApplication {
        BrowserApplication(
            bundleIdentifier: bundleIdentifier?.trimmedNonEmpty ?? other.bundleIdentifier?.trimmedNonEmpty,
            displayName: displayName?.trimmedNonEmpty ?? other.displayName?.trimmedNonEmpty,
            applicationURL: applicationURL.standardizedFileURL
        )
    }
}

struct BrowserCandidate: Codable, Hashable, Identifiable {
    let bundleIdentifier: String?
    let displayName: String?
    let applicationURL: URL
    let supportedSchemes: Set<BrowserURLScheme>

    var id: String {
        normalizedIdentifier(bundleIdentifier: bundleIdentifier, applicationURL: applicationURL)
    }

    var normalizedApplicationURL: URL {
        applicationURL.standardizedFileURL
    }

    var normalizedApplicationPath: String {
        normalizedApplicationURL.path
    }

    var resolvedDisplayName: String {
        displayName?.trimmedNonEmpty ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    var isNestedApplicationBundle: Bool {
        applicationURL.containsParentApplicationBundle
    }

    func supports(_ scheme: BrowserURLScheme) -> Bool {
        supportedSchemes.contains(scheme)
    }

    var supportsRequiredSchemes: Bool {
        BrowserURLScheme.allCases.allSatisfy(supports)
    }

    func merged(with other: BrowserCandidate) -> BrowserCandidate {
        BrowserCandidate(
            bundleIdentifier: bundleIdentifier?.trimmedNonEmpty ?? other.bundleIdentifier?.trimmedNonEmpty,
            displayName: displayName?.trimmedNonEmpty ?? other.displayName?.trimmedNonEmpty,
            applicationURL: applicationURL.standardizedFileURL,
            supportedSchemes: supportedSchemes.union(other.supportedSchemes)
        )
    }
}

struct BrowserDiscoverySnapshot: Codable, Hashable {
    let currentHTTPHandler: BrowserApplication?
    let currentHTTPSHandler: BrowserApplication?
    let candidates: [BrowserCandidate]
    let refreshedAt: Date
    let issues: [String]

    func currentHandler(for scheme: BrowserURLScheme) -> BrowserApplication? {
        switch scheme {
        case .http:
            currentHTTPHandler
        case .https:
            currentHTTPSHandler
        }
    }

    func candidate(matchingNormalizedApplicationPath path: String) -> BrowserCandidate? {
        candidates.first { $0.normalizedApplicationPath == path }
    }

    var coherentCurrentBrowser: BrowserApplication? {
        guard let currentHTTPHandler, let currentHTTPSHandler else {
            return nil
        }

        guard currentHTTPHandler.normalizedApplicationPath == currentHTTPSHandler.normalizedApplicationPath else {
            return nil
        }

        return currentHTTPHandler.merged(with: currentHTTPSHandler)
    }

    func projectedSwitchSnapshot(for target: BrowserSwitchTarget) -> BrowserDiscoverySnapshot {
        let projectedApplication = BrowserApplication(
            bundleIdentifier: target.bundleIdentifier,
            displayName: target.displayName,
            applicationURL: target.applicationURL
        )
        let projectedCandidate = BrowserCandidate(
            bundleIdentifier: target.bundleIdentifier,
            displayName: target.displayName,
            applicationURL: target.applicationURL,
            supportedSchemes: Set(BrowserURLScheme.allCases)
        )
        let projectedCandidates: [BrowserCandidate]

        if candidates.contains(where: { $0.normalizedApplicationPath == projectedCandidate.normalizedApplicationPath }) {
            projectedCandidates = candidates
        } else {
            projectedCandidates = (candidates + [projectedCandidate]).sorted(by: Self.sortCandidates)
        }

        return BrowserDiscoverySnapshot(
            currentHTTPHandler: projectedApplication,
            currentHTTPSHandler: projectedApplication,
            candidates: projectedCandidates,
            refreshedAt: refreshedAt,
            issues: issues
        )
    }

    static func normalized(
        currentHTTPHandler: BrowserApplication?,
        currentHTTPSHandler: BrowserApplication?,
        httpCandidates: [BrowserApplication],
        httpsCandidates: [BrowserApplication],
        refreshedAt: Date = .now,
        issues: [String] = []
    ) -> BrowserDiscoverySnapshot {
        var mergedCandidates: [String: BrowserCandidate] = [:]

        func merge(_ application: BrowserApplication, scheme: BrowserURLScheme) {
            let candidate = BrowserCandidate(
                bundleIdentifier: application.bundleIdentifier?.trimmedNonEmpty,
                displayName: application.displayName?.trimmedNonEmpty,
                applicationURL: application.applicationURL.standardizedFileURL,
                supportedSchemes: [scheme]
            )

            if let existing = mergedCandidates[candidate.id] {
                mergedCandidates[candidate.id] = existing.merged(with: candidate)
            } else {
                mergedCandidates[candidate.id] = candidate
            }
        }

        httpCandidates.forEach { merge($0, scheme: .http) }
        httpsCandidates.forEach { merge($0, scheme: .https) }

        if let currentHTTPHandler {
            merge(currentHTTPHandler, scheme: .http)
        }

        if let currentHTTPSHandler {
            merge(currentHTTPSHandler, scheme: .https)
        }

        return BrowserDiscoverySnapshot(
            currentHTTPHandler: currentHTTPHandler,
            currentHTTPSHandler: currentHTTPSHandler,
            candidates: mergedCandidates.values
                .filter { !$0.isNestedApplicationBundle }
                .sorted(by: Self.sortCandidates),
            refreshedAt: refreshedAt,
            issues: issues
        )
    }

    private static func sortCandidates(_ lhs: BrowserCandidate, _ rhs: BrowserCandidate) -> Bool {
        let lhsName = lhs.resolvedDisplayName.localizedCaseInsensitiveCompare(rhs.resolvedDisplayName)
        if lhsName != .orderedSame {
            return lhsName == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}

private func normalizedIdentifier(bundleIdentifier: String?, applicationURL: URL) -> String {
    bundleIdentifier?.trimmedNonEmpty ?? applicationURL.standardizedFileURL.path
}

private extension URL {
    var containsParentApplicationBundle: Bool {
        standardizedFileURL.pathComponents.dropLast().contains { component in
            component.range(of: ".app", options: [.caseInsensitive, .anchored, .backwards]) != nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
