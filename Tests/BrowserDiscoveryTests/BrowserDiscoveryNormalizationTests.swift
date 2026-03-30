import XCTest
@testable import DefaultBrowserSwitcher

final class BrowserDiscoveryNormalizationTests: XCTestCase {
    func testNormalizedSnapshotMergesCandidatesAcrossSchemesAndCurrentHandlers() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari],
            httpsCandidates: [chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_000)
        )

        XCTAssertEqual(snapshot.currentHTTPHandler, safari)
        XCTAssertEqual(snapshot.currentHTTPSHandler, chrome)
        XCTAssertEqual(snapshot.candidates.count, 2)
        XCTAssertEqual(snapshot.candidates.first(where: { $0.bundleIdentifier == safari.bundleIdentifier })?.supportedSchemes, [.http])
        XCTAssertEqual(snapshot.candidates.first(where: { $0.bundleIdentifier == chrome.bundleIdentifier })?.supportedSchemes, [.https])
    }

    func testNormalizedSnapshotDeduplicatesNoisyCandidatesByBundleIdentifierAndPath() {
        let safariBundleMatch = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let safariBundleDuplicate = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari Technology Preview", path: "/Applications/Safari.app")
        let helperWithoutBundleID = BrowserApplication.fixture(bundleIdentifier: nil, displayName: nil, path: "/Applications/Browser Helper.app")
        let helperDuplicatePath = BrowserApplication.fixture(bundleIdentifier: nil, displayName: "Browser Helper", path: "/Applications/Browser Helper.app")

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [safariBundleMatch, helperWithoutBundleID],
            httpsCandidates: [safariBundleDuplicate, helperDuplicatePath],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_100)
        )

        XCTAssertEqual(snapshot.candidates.count, 2)
        XCTAssertEqual(snapshot.candidates.first(where: { $0.bundleIdentifier == "com.apple.Safari" })?.supportedSchemes, [.http, .https])

        let helperCandidate = snapshot.candidates.first(where: { $0.bundleIdentifier == nil })
        XCTAssertEqual(helperCandidate?.supportedSchemes, [.http, .https])
        XCTAssertEqual(helperCandidate?.applicationURL.path, "/Applications/Browser Helper.app")
    }

    func testNormalizedSnapshotFiltersNestedApplicationBundlesFromCandidates() {
        let outerAtlas = BrowserApplication.fixture(
            bundleIdentifier: "com.openai.atlas",
            displayName: "ChatGPT Atlas",
            path: "/Applications/ChatGPT Atlas.app"
        )
        let nestedAtlas = BrowserApplication.fixture(
            bundleIdentifier: "com.openai.atlas.web",
            displayName: "ChatGPT Atlas",
            path: "/Applications/ChatGPT Atlas.app/Contents/Support/ChatGPT Atlas.app"
        )

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [outerAtlas, nestedAtlas],
            httpsCandidates: [outerAtlas, nestedAtlas],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_200)
        )

        XCTAssertEqual(snapshot.candidates.map(\.applicationURL.path), [outerAtlas.applicationURL.path])
        XCTAssertEqual(snapshot.candidates.first?.bundleIdentifier, outerAtlas.bundleIdentifier)
        XCTAssertEqual(snapshot.candidates.first?.supportedSchemes, [.http, .https])
    }

    func testNormalizedSnapshotDoesNotReintroduceNestedApplicationBundlesAfterCrossSchemeMerge() {
        let nestedAtlas = BrowserApplication.fixture(
            bundleIdentifier: "com.openai.atlas.web",
            displayName: "ChatGPT Atlas",
            path: "/Applications/ChatGPT Atlas.app/Contents/Support/ChatGPT Atlas.app"
        )

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: nil,
            httpCandidates: [nestedAtlas],
            httpsCandidates: [nestedAtlas],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_300)
        )

        XCTAssertTrue(snapshot.candidates.isEmpty)
    }

    func testNormalizedSnapshotPreservesNestedCurrentHandlersWhileFilteringNestedCandidates() {
        let nestedAtlas = BrowserApplication.fixture(
            bundleIdentifier: "com.openai.atlas.web",
            displayName: "ChatGPT Atlas",
            path: "/Applications/ChatGPT Atlas.app/Contents/Support/ChatGPT Atlas.app"
        )

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nestedAtlas,
            currentHTTPSHandler: nestedAtlas,
            httpCandidates: [nestedAtlas],
            httpsCandidates: [nestedAtlas],
            refreshedAt: Date(timeIntervalSince1970: 1_710_001_400)
        )

        XCTAssertEqual(snapshot.currentHTTPHandler, nestedAtlas)
        XCTAssertEqual(snapshot.currentHTTPSHandler, nestedAtlas)
        XCTAssertEqual(snapshot.coherentCurrentBrowser, nestedAtlas)
        XCTAssertTrue(snapshot.candidates.isEmpty)
    }
}

private extension BrowserApplication {
    static func fixture(bundleIdentifier: String?, displayName: String?, path: String) -> BrowserApplication {
        BrowserApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: URL(fileURLWithPath: path)
        )
    }
}
