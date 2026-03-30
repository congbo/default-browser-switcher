import XCTest
@testable import DefaultBrowserSwitcher

final class BrowserPresentationTests: XCTestCase {
    func testCoherentLiveSnapshotWinsOverVerifiedAndFallbackBrowsers() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")

        let liveSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_000)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_100)
        )
        let result = BrowserSwitchResult.verifiedFailure(
            target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
            verifiedSnapshot: verifiedSnapshot,
            mismatchDetails: ["callback failed despite coherent readback"]
        )

        let presentation = BrowserPresentation(
            snapshot: liveSnapshot,
            lastSwitchResult: result,
            lastCoherentBrowser: firefox,
            preferVerifiedPostSwitch: false,
            switchPhase: .failure,
            successState: .none
        )

        XCTAssertEqual(presentation.currentBrowser?.application, safari)
        XCTAssertEqual(presentation.currentBrowser?.source, .liveSnapshot)
        XCTAssertNil(presentation.fallbackBrowser)
    }

    func testMixedOrFailureUsesCoherentVerifiedSnapshotAsDisplayedCurrentBrowser() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_200)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_300)
        )

        let presentation = BrowserPresentation(
            snapshot: staleSnapshot,
            lastSwitchResult: .verifiedMixed(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                verifiedSnapshot: verifiedSnapshot,
                mismatchDetails: ["switch callback reported a partial failure"]
            ),
            lastCoherentBrowser: safari,
            preferVerifiedPostSwitch: true,
            switchPhase: .mixed,
            successState: .none
        )

        XCTAssertEqual(presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(presentation.currentBrowser?.source, .verifiedPostSwitch)
        XCTAssertNil(presentation.fallbackBrowser)
    }

    func testOptimisticSuccessUsesOptimisticCurrentBrowserCopy() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let liveSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_350)
        )

        let presentation = BrowserPresentation(
            snapshot: liveSnapshot,
            lastSwitchResult: .optimisticSuccess(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                optimisticSnapshot: liveSnapshot
            ),
            lastCoherentBrowser: safari,
            preferOptimisticPostSwitch: true,
            switchPhase: .success,
            successState: .updated(browserName: "Google Chrome")
        )

        XCTAssertEqual(presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(presentation.currentBrowserSource, .optimisticPostSwitch)
        XCTAssertEqual(presentation.settingsHelperText, "The app is refreshing browser state in the background.")
        XCTAssertEqual(presentation.currentInspectionSummaryText, "Showing the requested browser while background refresh catches up.")
    }

    func testOptimisticVerificationWarningKeepsOptimisticSelectionWithoutAttentionState() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let projectedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_351)
        )

        let presentation = BrowserPresentation(
            snapshot: projectedSnapshot,
            lastSwitchResult: .optimisticSuccess(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                optimisticSnapshot: projectedSnapshot
            ),
            lastCoherentBrowser: safari,
            optimisticVerificationMessage: "The browser switch was submitted, but verification has not caught up yet.",
            preferOptimisticPostSwitch: true,
            switchPhase: .success,
            successState: .none
        )

        XCTAssertEqual(presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(presentation.currentBrowserSource, .optimisticPostSwitch)
        XCTAssertEqual(presentation.userVisibleStatus, .idle)
        XCTAssertFalse(presentation.showRefreshInMenu)
        XCTAssertEqual(
            presentation.settingsHelperText,
            "The browser switch was submitted, but verification has not caught up yet."
        )
    }

    func testIncoherentLiveSnapshotFallsBackToLastCoherentBrowserWithoutClaimingLiveCurrentBrowser() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let incoherentSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_400)
        )

        let presentation = BrowserPresentation(
            snapshot: incoherentSnapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .failure,
            successState: .none
        )

        XCTAssertEqual(presentation.currentBrowser?.application, safari)
        XCTAssertEqual(presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(presentation.currentBrowser?.source, .staleFallback)
        XCTAssertEqual(presentation.userVisibleStatus, .needsAttention(message: "Current default browser could not be verified."))
        XCTAssertTrue(presentation.showRefreshInMenu)
    }

    func testRefreshFailureShowsStaleStatusAndStaleFallbackCurrentBrowser() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari],
            httpsCandidates: [safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_450)
        )

        let presentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none,
            phase: .failed,
            lastErrorMessage: "Refresh failed"
        )

        XCTAssertEqual(presentation.currentBrowser?.application, safari)
        XCTAssertEqual(presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(presentation.userVisibleStatus, .stale(message: "Refresh failed"))
        XCTAssertTrue(presentation.showRefreshInMenu)
    }

    func testActionableCandidatesRequireBundleIdentifierBothSchemesAndTargetEligibility() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let helperWithoutBundleIdentifier = BrowserApplication.fixture(bundleIdentifier: nil, displayName: "Browser Helper", path: "/Applications/Browser Helper.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome, helperWithoutBundleIdentifier, firefox],
            httpsCandidates: [safari, chrome, helperWithoutBundleIdentifier],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_500)
        )

        let presentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none
        )

        let currentRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == safari.applicationURL }))
        let switchableRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == chrome.applicationURL }))
        let helperRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == helperWithoutBundleIdentifier.applicationURL }))
        let partialRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == firefox.applicationURL }))

        XCTAssertEqual(currentRow.actionState, .currentSelection)
        XCTAssertFalse(currentRow.isActionable)
        XCTAssertEqual(switchableRow.actionState, .switchable)
        XCTAssertTrue(switchableRow.isActionable)
        XCTAssertEqual(helperRow.actionState, .disabled(.missingBundleIdentifier))
        XCTAssertEqual(partialRow.actionState, .disabled(.missingRequiredSchemes))
        XCTAssertEqual(presentation.switchableBrowsers.map(\.candidate.applicationURL.path), [chrome.applicationURL.path])
        XCTAssertEqual(presentation.selectedActionableBrowserID, currentRow.candidate.id)
        XCTAssertEqual(presentation.advancedSummary, .init(actionableCount: 1, nonActionableCount: 3))
    }

    func testSelectedActionableBrowserIDUsesVerifiedPostSwitchCurrentBrowserWhenActionable() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_550)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_560)
        )

        let presentation = BrowserPresentation(
            snapshot: staleSnapshot,
            lastSwitchResult: .verifiedFailure(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                verifiedSnapshot: verifiedSnapshot,
                mismatchDetails: ["callback failed despite coherent readback"]
            ),
            lastCoherentBrowser: safari,
            preferVerifiedPostSwitch: true,
            switchPhase: .failure,
            successState: .none
        )

        let currentRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == chrome.applicationURL }))

        XCTAssertEqual(presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(presentation.currentBrowserSource, .verifiedPostSwitch)
        XCTAssertEqual(currentRow.actionState, .currentSelection)
        XCTAssertEqual(presentation.selectedActionableBrowserID, currentRow.candidate.id)
        XCTAssertEqual(presentation.switchableBrowsers.map(\.candidate.applicationURL.path), [safari.applicationURL.path])
    }

    func testSelectedActionableBrowserIDRemainsNilForStaleUnresolvedAndNonActionableStates() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let helperBrowser = BrowserApplication.fixture(bundleIdentifier: "com.example.HelperBrowser", displayName: "Helper Browser", path: "/Applications/Helper Browser.app")

        let stalePresentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: chrome,
                httpCandidates: [safari, chrome],
                httpsCandidates: [safari, chrome],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_570)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .failure,
            successState: .none
        )

        let unresolvedPresentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: nil,
                currentHTTPSHandler: nil,
                httpCandidates: [safari],
                httpsCandidates: [safari],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_580)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: nil,
            switchPhase: .idle,
            successState: .none
        )

        let nonActionablePresentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: helperBrowser,
                currentHTTPSHandler: helperBrowser,
                httpCandidates: [helperBrowser, safari],
                httpsCandidates: [helperBrowser, safari],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_590)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: helperBrowser,
            switchPhase: .idle,
            successState: .none,
            isEligibleSwitchTarget: { $0.bundleIdentifier != "com.example.HelperBrowser" }
        )

        XCTAssertEqual(stalePresentation.currentBrowserSource, .staleFallback)
        XCTAssertNil(stalePresentation.selectedActionableBrowserID)
        XCTAssertEqual(
            stalePresentation.candidates.first(where: { $0.candidate.applicationURL == safari.applicationURL })?.actionState,
            .switchable
        )

        XCTAssertEqual(unresolvedPresentation.currentBrowserSource, .none)
        XCTAssertNil(unresolvedPresentation.selectedActionableBrowserID)

        XCTAssertEqual(nonActionablePresentation.currentBrowserSource, .liveSnapshot)
        XCTAssertNil(nonActionablePresentation.selectedActionableBrowserID)
    }

    func testSelectedActionableBrowserIDUsesTrustedStalePostSwitchSelectionWhenRequestedBrowserMatchesFallback() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let firefox = BrowserApplication.fixture(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox", path: "/Applications/Firefox.app")

        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: firefox,
            httpCandidates: [safari, chrome, firefox],
            httpsCandidates: [safari, chrome, firefox],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_595)
        )

        let presentation = BrowserPresentation(
            snapshot: staleSnapshot,
            lastSwitchResult: .verifiedSuccess(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                verifiedSnapshot: BrowserDiscoverySnapshot.normalized(
                    currentHTTPHandler: chrome,
                    currentHTTPSHandler: chrome,
                    httpCandidates: [safari, chrome, firefox],
                    httpsCandidates: [safari, chrome, firefox],
                    refreshedAt: Date(timeIntervalSince1970: 1_710_200_596)
                )
            ),
            lastCoherentBrowser: chrome,
            switchPhase: .success,
            successState: .none
        )

        let chromeRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == chrome.applicationURL }))

        XCTAssertEqual(presentation.currentBrowser?.application, chrome)
        XCTAssertEqual(presentation.currentBrowserSource, .staleFallback)
        XCTAssertEqual(chromeRow.actionState, .trustedSelection)
        XCTAssertEqual(presentation.selectedActionableBrowserID, chromeRow.candidate.id)
    }

    func testLiveSnapshotClearsTrustedStaleSelectionWhenSystemStateDisagrees() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let liveSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_597)
        )

        let presentation = BrowserPresentation(
            snapshot: liveSnapshot,
            lastSwitchResult: .verifiedSuccess(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                verifiedSnapshot: BrowserDiscoverySnapshot.normalized(
                    currentHTTPHandler: chrome,
                    currentHTTPSHandler: chrome,
                    httpCandidates: [safari, chrome],
                    httpsCandidates: [safari, chrome],
                    refreshedAt: Date(timeIntervalSince1970: 1_710_200_598)
                )
            ),
            lastCoherentBrowser: chrome,
            switchPhase: .success,
            successState: .none
        )

        let safariRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == safari.applicationURL }))
        let chromeRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == chrome.applicationURL }))

        XCTAssertEqual(presentation.currentBrowser?.application, safari)
        XCTAssertEqual(presentation.currentBrowserSource, .liveSnapshot)
        XCTAssertEqual(safariRow.actionState, .currentSelection)
        XCTAssertEqual(chromeRow.actionState, .switchable)
        XCTAssertEqual(presentation.selectedActionableBrowserID, safariRow.candidate.id)
    }

    func testInformationalAppsCanBeMarkedNonActionableEvenWithBundleIdentifierAndBothSchemes() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let browserHelper = BrowserApplication.fixture(bundleIdentifier: "com.example.HelperBrowser", displayName: "Helper Browser", path: "/Applications/Helper Browser.app")

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, browserHelper],
            httpsCandidates: [safari, browserHelper],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_600)
        )

        let presentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none,
            isEligibleSwitchTarget: { $0.bundleIdentifier != "com.example.HelperBrowser" }
        )

        let helperRow = try XCTUnwrap(presentation.candidates.first(where: { $0.candidate.applicationURL == browserHelper.applicationURL }))
        XCTAssertEqual(helperRow.actionState, .disabled(.ineligibleTarget))
    }

    func testCoherentNonActionableCurrentBrowserIsInformationalOnlyAndNotSelectedActionableBrowser() throws {
        let helperBrowser = BrowserApplication.fixture(bundleIdentifier: "com.example.HelperBrowser", displayName: "Helper Browser", path: "/Applications/Helper Browser.app")
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")

        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: helperBrowser,
            currentHTTPSHandler: helperBrowser,
            httpCandidates: [helperBrowser, safari],
            httpsCandidates: [helperBrowser, safari],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_650)
        )

        let presentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: helperBrowser,
            switchPhase: .idle,
            successState: .none,
            isEligibleSwitchTarget: { $0.bundleIdentifier != "com.example.HelperBrowser" }
        )

        XCTAssertEqual(presentation.currentBrowser?.application, helperBrowser)
        XCTAssertEqual(presentation.currentBrowserSource, .liveSnapshot)
        XCTAssertNil(presentation.selectedActionableBrowserID)
        XCTAssertEqual(presentation.switchableBrowsers.map(\.candidate.applicationURL.path), [safari.applicationURL.path])

        let helperRow = try XCTUnwrap(presentation.nonActionableCandidatesWithReasons.first(where: { $0.candidate.applicationURL == helperBrowser.applicationURL }))
        XCTAssertEqual(helperRow.actionState, .disabled(.ineligibleTarget))
    }

    func testSettingsPlaceholderUsesChooseBrowserForAttentionStateWithActionableCandidates() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: chrome,
                httpCandidates: [safari, chrome],
                httpsCandidates: [safari, chrome],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_705)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none
        )

        XCTAssertEqual(presentation.settingsPickerPlaceholder, "Choose a browser")
        XCTAssertFalse(presentation.isPickerDisabled)
        XCTAssertNil(presentation.selectedActionableBrowserID)
    }

    func testSettingsPlaceholderDisablesPickerWhenNoActionableCandidatesExist() {
        let helperBrowser = BrowserApplication.fixture(bundleIdentifier: nil, displayName: "Helper Browser", path: "/Applications/Helper Browser.app")

        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: helperBrowser,
                currentHTTPSHandler: helperBrowser,
                httpCandidates: [helperBrowser],
                httpsCandidates: [helperBrowser],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_706)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: helperBrowser,
            switchPhase: .idle,
            successState: .none
        )

        XCTAssertEqual(presentation.settingsPickerPlaceholder, "No supported browsers found")
        XCTAssertTrue(presentation.isPickerDisabled)
        XCTAssertFalse(presentation.currentBrowserIsActionable)
    }

    func testSwitchingStateDisablesPickerEvenWithActionableCandidates() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: safari,
                httpCandidates: [safari, chrome],
                httpsCandidates: [safari, chrome],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_707)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .switching,
            successState: .none,
            activeSwitchTarget: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https]))
        )

        XCTAssertTrue(presentation.isPickerDisabled)
        XCTAssertEqual(presentation.settingsPickerPlaceholder, "Choose a browser")
    }

    func testStatusItemUsesBrowserIconForCoherentCurrentBrowser() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: safari,
                httpCandidates: [safari],
                httpsCandidates: [safari],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_701)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none
        )

        XCTAssertEqual(presentation.statusItem.iconSource, .browser(safari.applicationURL))
        XCTAssertEqual(presentation.statusItem.accessibilityLabel, "Default browser: Safari")
    }

    func testStatusItemFallsBackToNeutralIconWithoutCurrentBrowser() {
        let presentation = BrowserPresentation(
            snapshot: nil,
            lastSwitchResult: nil,
            lastCoherentBrowser: nil,
            switchPhase: .idle,
            successState: .none,
            phase: .refreshing
        )

        XCTAssertEqual(presentation.statusItem.iconSource, .neutral)
        XCTAssertEqual(presentation.statusItem.accessibilityLabel, "Loading current browser")
    }

    func testStatusItemKeepsBrowserIconForStaleFallbackState() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: chrome,
                httpCandidates: [safari, chrome],
                httpsCandidates: [safari, chrome],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_702)
            ),
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .failure,
            successState: .none
        )

        XCTAssertEqual(presentation.statusItem.iconSource, .browser(safari.applicationURL))
        XCTAssertEqual(presentation.statusItem.accessibilityLabel, "Default browser: Safari")
    }

    func testStatusMappingCoversIdleLoadingSwitchingAndUpdatedStates() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let snapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_700)
        )

        let idlePresentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none
        )
        XCTAssertEqual(idlePresentation.userVisibleStatus, .idle)
        XCTAssertFalse(idlePresentation.showRefreshInMenu)

        let loadingPresentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .idle,
            successState: .none,
            phase: .refreshing
        )
        XCTAssertEqual(loadingPresentation.userVisibleStatus, .loading)
        XCTAssertFalse(loadingPresentation.showRefreshInMenu)

        let switchingPresentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .switching,
            successState: .none,
            activeSwitchTarget: BrowserSwitchTarget(candidate: BrowserCandidate.fixture(from: chrome, supportedSchemes: [.http, .https]))
        )
        XCTAssertEqual(switchingPresentation.userVisibleStatus, .switching(targetName: "Google Chrome"))
        XCTAssertFalse(switchingPresentation.showRefreshInMenu)

        let updatedPresentation = BrowserPresentation(
            snapshot: snapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .success,
            successState: .updated(browserName: "Google Chrome")
        )
        XCTAssertEqual(updatedPresentation.userVisibleStatus, .updated(browserName: "Google Chrome"))
        XCTAssertFalse(updatedPresentation.showRefreshInMenu)
    }

    func testStatusCopyAndRetryAffordanceStaySharedAcrossSurfaces() {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")
        let result = BrowserSwitchResult.serviceFailure(
            target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
            readbackErrorMessage: "Injected switch failure"
        )

        let presentation = BrowserPresentation(
            snapshot: BrowserDiscoverySnapshot.normalized(
                currentHTTPHandler: safari,
                currentHTTPSHandler: safari,
                httpCandidates: [safari, chrome],
                httpsCandidates: [safari, chrome],
                refreshedAt: Date(timeIntervalSince1970: 1_710_200_710)
            ),
            lastSwitchResult: result,
            lastCoherentBrowser: safari,
            switchPhase: .failure,
            successState: .none,
            retryAvailability: .enabled(targetName: "Google Chrome")
        )

        XCTAssertEqual(presentation.statusMessageText, "Injected switch failure")
        XCTAssertEqual(presentation.settingsHelperText, "Injected switch failure")
        XCTAssertEqual(presentation.retryButtonTitle, "Retry Google Chrome")
        XCTAssertEqual(presentation.retryHelpText, "Retry the last requested browser target with the current snapshot.")
    }

    func testCurrentHandlerInspectionsUseVerifiedSnapshotWhenPreferred() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let staleSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: safari,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_720)
        )
        let verifiedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: chrome,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_730)
        )

        let presentation = BrowserPresentation(
            snapshot: staleSnapshot,
            lastSwitchResult: .verifiedFailure(
                target: BrowserSwitchTarget(candidate: .fixture(from: chrome, supportedSchemes: [.http, .https])),
                verifiedSnapshot: verifiedSnapshot,
                mismatchDetails: ["callback failed despite coherent readback"]
            ),
            lastCoherentBrowser: safari,
            preferVerifiedPostSwitch: true,
            switchPhase: .failure,
            successState: .none,
            retryAvailability: .enabled(targetName: "Google Chrome")
        )

        let httpInspection = try XCTUnwrap(presentation.currentHandlerInspections.first(where: { $0.scheme == .http }))
        let httpsInspection = try XCTUnwrap(presentation.currentHandlerInspections.first(where: { $0.scheme == .https }))

        XCTAssertEqual(httpInspection.application?.resolvedDisplayName, "Google Chrome")
        XCTAssertEqual(httpInspection.source, .verifiedPostSwitch)
        XCTAssertEqual(httpInspection.state, .currentBrowser)
        XCTAssertEqual(httpsInspection.application?.resolvedDisplayName, "Google Chrome")
        XCTAssertEqual(httpsInspection.source, .verifiedPostSwitch)
        XCTAssertEqual(httpsInspection.state, .currentBrowser)
    }

    func testCurrentHandlerInspectionsExposeMixedAndMissingStateTruthfully() throws {
        let safari = BrowserApplication.fixture(bundleIdentifier: "com.apple.Safari", displayName: "Safari", path: "/Applications/Safari.app")
        let chrome = BrowserApplication.fixture(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", path: "/Applications/Google Chrome.app")

        let mixedSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: safari,
            currentHTTPSHandler: chrome,
            httpCandidates: [safari, chrome],
            httpsCandidates: [safari, chrome],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_740),
            issues: ["handlers differ"]
        )

        let mixedPresentation = BrowserPresentation(
            snapshot: mixedSnapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: safari,
            switchPhase: .failure,
            successState: .none,
            retryAvailability: .disabled(.targetMissing(displayName: "Google Chrome"))
        )

        let httpInspection = try XCTUnwrap(mixedPresentation.currentHandlerInspections.first(where: { $0.scheme == .http }))
        let httpsInspection = try XCTUnwrap(mixedPresentation.currentHandlerInspections.first(where: { $0.scheme == .https }))
        XCTAssertEqual(httpInspection.state, .mixed)
        XCTAssertEqual(httpsInspection.state, .mixed)
        XCTAssertEqual(httpInspection.detailText, "HTTP currently resolves to Safari.")
        XCTAssertEqual(httpsInspection.detailText, "HTTPS currently resolves to Google Chrome.")

        let partialSnapshot = BrowserDiscoverySnapshot.normalized(
            currentHTTPHandler: nil,
            currentHTTPSHandler: BrowserApplication.fixture(bundleIdentifier: nil, displayName: nil, path: "/Applications/Unnamed Browser.app"),
            httpCandidates: [],
            httpsCandidates: [BrowserApplication.fixture(bundleIdentifier: nil, displayName: nil, path: "/Applications/Unnamed Browser.app")],
            refreshedAt: Date(timeIntervalSince1970: 1_710_200_750)
        )

        let partialPresentation = BrowserPresentation(
            snapshot: partialSnapshot,
            lastSwitchResult: nil,
            lastCoherentBrowser: nil,
            switchPhase: .idle,
            successState: .none,
            retryAvailability: .disabled(.noPreviousTarget)
        )

        let missingHTTPInspection = try XCTUnwrap(partialPresentation.currentHandlerInspections.first(where: { $0.scheme == .http }))
        let partialHTTPSInspection = try XCTUnwrap(partialPresentation.currentHandlerInspections.first(where: { $0.scheme == .https }))
        XCTAssertEqual(missingHTTPInspection.state, .missing)
        XCTAssertEqual(missingHTTPInspection.displayName, "No default handler")
        XCTAssertEqual(partialHTTPSInspection.state, .nonActionable(.missingBundleIdentifier))
        XCTAssertEqual(partialHTTPSInspection.displayName, "Unnamed Browser")
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

private extension BrowserCandidate {
    static func fixture(from application: BrowserApplication, supportedSchemes: Set<BrowserURLScheme>) -> BrowserCandidate {
        BrowserCandidate(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName,
            applicationURL: application.applicationURL,
            supportedSchemes: supportedSchemes
        )
    }
}
