import AppKit
import Foundation
import CoreGraphics

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

    func icon(for applicationURL: URL, size: CGFloat) -> NSImage {
        let baseIcon = icon(for: applicationURL)
        let icon = baseIcon.copy() as? NSImage ?? baseIcon
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    func neutralIcon() -> NSImage {
        let bundlePath = Bundle.main.bundleURL.path
        return icon(for: URL(fileURLWithPath: bundlePath))
    }

    func neutralIcon(size: CGFloat) -> NSImage {
        let baseIcon = neutralIcon()
        let icon = baseIcon.copy() as? NSImage ?? baseIcon
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    func icon(for application: BrowserApplication) -> NSImage {
        icon(for: application.applicationURL)
    }

    func icon(for application: BrowserApplication, size: CGFloat) -> NSImage {
        icon(for: application.applicationURL, size: size)
    }

    func icon(for candidate: BrowserCandidate) -> NSImage {
        icon(for: candidate.applicationURL)
    }

    func icon(for candidate: BrowserCandidate, size: CGFloat) -> NSImage {
        icon(for: candidate.applicationURL, size: size)
    }

    func resetCache() {
        cache.removeAll()
    }
}
