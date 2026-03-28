#!/usr/bin/env swift

import AppKit
import Foundation

enum BrowserURLScheme: String, Codable {
    case http
    case https
}

struct BrowserApplication: Codable {
    let bundleIdentifier: String?
    let displayName: String?
    let applicationURL: URL

    var id: String {
        bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? applicationURL.standardizedFileURL.path
    }

    var resolvedDisplayName: String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? applicationURL.deletingPathExtension().lastPathComponent
    }
}

struct BrowserCandidate: Codable {
    let bundleIdentifier: String?
    let displayName: String?
    let applicationURL: URL
    let supportedSchemes: Set<BrowserURLScheme>

    var id: String {
        bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? applicationURL.standardizedFileURL.path
    }

    var resolvedDisplayName: String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? applicationURL.deletingPathExtension().lastPathComponent
    }
}

struct BrowserDiscoverySnapshot: Codable {
    let currentHTTPHandler: BrowserApplication?
    let currentHTTPSHandler: BrowserApplication?
    let candidates: [BrowserCandidate]
    let refreshedAt: Date
    let issues: [String]

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
                bundleIdentifier: application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                displayName: application.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                applicationURL: application.applicationURL.standardizedFileURL,
                supportedSchemes: [scheme]
            )

            if let existing = mergedCandidates[candidate.id] {
                mergedCandidates[candidate.id] = BrowserCandidate(
                    bundleIdentifier: existing.bundleIdentifier ?? candidate.bundleIdentifier,
                    displayName: existing.displayName ?? candidate.displayName,
                    applicationURL: existing.applicationURL,
                    supportedSchemes: existing.supportedSchemes.union(candidate.supportedSchemes)
                )
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
            candidates: mergedCandidates.values.sorted { lhs, rhs in
                let nameOrder = lhs.resolvedDisplayName.localizedCaseInsensitiveCompare(rhs.resolvedDisplayName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }

                return lhs.id < rhs.id
            },
            refreshedAt: refreshedAt,
            issues: issues
        )
    }
}

private let workspace = NSWorkspace.shared

func resolveApplication(at url: URL) -> BrowserApplication {
    let standardizedURL = url.standardizedFileURL
    let bundle = Bundle(url: standardizedURL)
    let displayName = [
        bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
        bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
        FileManager.default.displayName(atPath: standardizedURL.path)
    ]
        .compactMap { candidate in
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.nilIfEmpty
        }
        .first

    return BrowserApplication(
        bundleIdentifier: bundle?.bundleIdentifier,
        displayName: displayName,
        applicationURL: standardizedURL
    )
}

guard
    let httpSampleURL = URL(string: "http://example.com"),
    let httpsSampleURL = URL(string: "https://example.com")
else {
    fputs("Failed to build HTTP sample URLs for discovery.\n", stderr)
    exit(1)
}

let snapshot = BrowserDiscoverySnapshot.normalized(
    currentHTTPHandler: workspace.urlForApplication(toOpen: httpSampleURL).map(resolveApplication(at:)),
    currentHTTPSHandler: workspace.urlForApplication(toOpen: httpsSampleURL).map(resolveApplication(at:)),
    httpCandidates: workspace.urlsForApplications(toOpen: httpSampleURL).map(resolveApplication(at:)),
    httpsCandidates: workspace.urlsForApplications(toOpen: httpsSampleURL).map(resolveApplication(at:)),
    refreshedAt: .now
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601

let data = try encoder.encode(snapshot)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
