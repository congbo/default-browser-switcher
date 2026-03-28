import AppKit
import Foundation

@MainActor
final class BrowserIconProvider: ObservableObject {
    static let shared = BrowserIconProvider()

    private let workspace: NSWorkspace
    private var cache: [String: NSImage] = [:]

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func icon(for applicationURL: URL) -> NSImage {
        let normalizedURL = applicationURL.standardizedFileURL
        let cacheKey = normalizedURL.path

        if let cached = cache[cacheKey] {
            return cached
        }

        let icon = workspace.icon(forFile: cacheKey)
        cache[cacheKey] = icon
        return icon
    }

    func neutralIcon() -> NSImage {
        let bundlePath = Bundle.main.bundleURL.path
        return icon(for: URL(fileURLWithPath: bundlePath))
    }

    func icon(for application: BrowserApplication) -> NSImage {
        icon(for: application.applicationURL)
    }

    func icon(for candidate: BrowserCandidate) -> NSImage {
        icon(for: candidate.applicationURL)
    }

    func resetCache() {
        cache.removeAll()
    }
}
