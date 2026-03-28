# Default Browser UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Settings window and menu bar so the app presents one native-feeling “default browser” concept, uses the current browser icon in the status item, and keeps protocol-level verification details behind Advanced while preserving the existing S02 truth/report contract.

**Architecture:** Add a presentation seam on top of `BrowserDiscoveryStore` instead of letting SwiftUI views interpret raw `snapshot` and `BrowserSwitchResult` state directly. Use that seam to drive a system-style Settings picker, a simplified browser-picker menu, and a dynamic status-item icon backed by a shared icon provider. Keep the raw report model unchanged on success and derive post-switch mixed/failure presentation from `lastSwitchResult.verifiedSnapshot` without mutating the top-level discovered snapshot.

**Tech Stack:** SwiftUI, AppKit (`NSImage`, possibly status-item bridging), XCTest, Xcode/macOS app scenes, existing `BrowserDiscoveryStore` / `SystemBrowserDiscoveryService` switching stack.

---

## File structure map

### Existing files to modify

- `App/Application/BrowserDiscovery/BrowserDiscoveryStore.swift`
  - Add a product-facing presentation seam that computes coherent current-browser state, actionable/non-actionable candidate groupings, menu refresh visibility, and post-switch mixed/failure derived presentation without mutating the main discovered `snapshot`.
- `App/Application/BrowserDiscovery/BrowserDiscoverySnapshot.swift`
  - Add small helpers for coherent-current-browser checks and candidate/actionability helpers if the store needs them; keep the raw snapshot model focused.
- `App/Features/Settings/SettingsView.swift`
  - Replace the protocol-heavy form with a native-feeling default-browser row + Picker + Advanced disclosure driven only by the new presentation seam.
- `App/Features/MenuBar/MenuBarContentView.swift`
  - Replace the multi-section diagnostic menu with a browser picker driven by the new presentation seam; remove default-path protocol rows/badges and keep Refresh only in attention/stale states.
- `App/DefaultBrowserSwitcherApp.swift`
  - Replace the fixed globe status-item shell contract with a dynamic icon/label contract fed by presentation state.
- `App/Resources/Localizable.xcstrings`
  - Add strings for the new Settings labels, Picker placeholders, stale/attention copy, and simplified menu copy.
- `Tests/BrowserDiscoveryTests/BrowserDiscoveryStoreTests.swift`
  - Add/store-focused tests for coherent current browser derivation, post-switch mixed/failure presentation precedence, `lastCoherentBrowser`, and menu-refresh visibility.
- `Tests/BrowserDiscoveryTests/AppShellSmokeTests.swift`
  - Replace/extend shell assertions so they validate the new status-item contract, menu presentation model, and simplified candidate/menu behavior.

### New files to create

- `App/Application/BrowserDiscovery/BrowserPresentation.swift`
  - Small presentation-domain types consumed by Settings/menu/status-item: current browser source, actionable browser rows, user-visible status, advanced summary, and status-item presentation.
- `App/Application/BrowserDiscovery/BrowserIconProvider.swift`
  - Shared icon-loading/cache service keyed by app URL.
- `Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift`
  - Focused unit tests for presentation rules that should not require rendering full SwiftUI views.

### Notes on boundaries

- Do **not** move raw report/export code out of `BrowserDiscoveryStore` in this pass.
- Do **not** change `SystemBrowserDiscoveryService` switching semantics unless required to support the new presentation seam.
- Prefer extracting pure presentation/value types into `BrowserPresentation.swift` so `SettingsView` and `MenuBarContentView` stay thin.

---

## Chunk 1: Presentation seam and icon infrastructure

### Task 1: Define the presentation model and lock its semantics with tests

**Files:**
- Create: `App/Application/BrowserDiscovery/BrowserPresentation.swift`
- Create: `App/Application/BrowserDiscovery/BrowserIconProvider.swift`
- Modify: `App/Application/BrowserDiscovery/BrowserDiscoveryStore.swift`
- Modify: `App/Application/BrowserDiscovery/BrowserDiscoverySnapshot.swift`
- Modify: `DefaultBrowserSwitcher.xcodeproj/project.pbxproj`
- Create: `Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift`
- Modify: `Tests/BrowserDiscoveryTests/BrowserDiscoveryStoreTests.swift`

- [ ] **Step 1: Write failing presentation tests for coherent vs mixed current-browser state**

```swift
func testPresentationUsesCoherentSnapshotAsCurrentBrowser() {
    let presentation = BrowserDiscoveryPresentation.make(
        snapshot: coherentSnapshot,
        lastSwitchResult: nil,
        phase: .loaded,
        switchPhase: .idle,
        lastErrorMessage: nil,
        lastCoherentBrowser: nil
    )

    XCTAssertEqual(presentation.currentBrowser?.resolvedDisplayName, "Safari")
    XCTAssertEqual(presentation.currentBrowserSource, .live)
    XCTAssertEqual(presentation.selectedActionableBrowserID, safariCandidate.id)
    XCTAssertFalse(presentation.showRefreshInMenu)
}

func testPresentationFallsIntoAttentionStateWhenHandlersDiffer() {
    let presentation = BrowserDiscoveryPresentation.make(
        snapshot: mixedSnapshot,
        lastSwitchResult: nil,
        phase: .loaded,
        switchPhase: .idle,
        lastErrorMessage: nil,
        lastCoherentBrowser: nil
    )

    XCTAssertNil(presentation.currentBrowser)
    XCTAssertEqual(presentation.userVisibleStatus, .needsAttention("Default browser needs attention"))
    XCTAssertTrue(presentation.showRefreshInMenu)
}
```

- [ ] **Step 2: Add the new source/test files to the Xcode project and target membership**

Update `DefaultBrowserSwitcher.xcodeproj/project.pbxproj` so:

- `BrowserPresentation.swift` and `BrowserIconProvider.swift` are in the app target
- `BrowserPresentationTests.swift` is in the `BrowserDiscoveryTests` target

Do this before relying on focused `-only-testing:` runs.

- [ ] **Step 3: Run the new presentation tests and verify they fail**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/BrowserPresentationTests
```

Expected: FAIL at compile or test time because the presentation types/functions do not exist yet. Do **not** treat a run that executes 0 tests as proof; confirm the output shows `BrowserPresentationTests` was discovered and attempted.

- [ ] **Step 4: Write failing store tests for mixed/failure derived presentation precedence**

Add tests in `Tests/BrowserDiscoveryTests/BrowserDiscoveryStoreTests.swift` covering:

- coherent live snapshot wins over all fallbacks
- `.mixed`/`.failure` results with `verifiedSnapshot` derive UI truth from `lastSwitchResult.verifiedSnapshot` without mutating `store.snapshot`
- `lastCoherentBrowser` updates only when a coherent browser is observed
- stale refresh failure keeps `lastCoherentBrowser` informationally but does not mark it selected
- actionable candidate filtering requires both schemes + non-empty bundle identifier + eligibility as a real full-browser switch target
- informational/helper-style apps can still be non-actionable even when they advertise both schemes and have a bundle identifier

Example shape:

```swift
func testMixedResultWithCoherentVerifiedSnapshotDerivesPresentationFromVerifiedSnapshot() async throws {
    let result = await store.switchToBrowser(candidate)

    XCTAssertEqual(result.classification, .mixed)
    XCTAssertEqual(store.snapshot, initialSnapshot)
    XCTAssertEqual(store.presentation.currentBrowserSource, .verifiedPostSwitch)
    XCTAssertEqual(store.presentation.currentBrowser?.resolvedDisplayName, "Google Chrome")
    XCTAssertEqual(store.presentation.selectedActionableBrowserID, chrome.id)
}
```

Also add separate tests that keep selection cleared for:

- stale fallback state
- coherent but non-actionable current browser
- mixed/unresolved verified snapshot


Also add tests that lock the reset transitions:

- a successful refresh replaces prior `verifiedPostSwitch` presentation with the live coherent snapshot
- a new switch attempt clears prior derived post-switch presentation immediately
- stale fallback remains informational only until a coherent live or verified source replaces it

- [ ] **Step 5: Run the focused store tests and verify they fail for the new assertions**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/BrowserDiscoveryStoreTests -only-testing:BrowserDiscoveryTests/BrowserPresentationTests
```

Expected: FAIL because `BrowserDiscoveryStore` does not yet expose the required presentation state and precedence behavior. Do **not** treat `Executed 0 tests` as a real failure signal; confirm both `BrowserPresentationTests` and `BrowserDiscoveryStoreTests` actually ran.

- [ ] **Step 6: Implement `BrowserPresentation.swift` as pure value types**

Implement a focused presentation model, for example:

```swift
enum CurrentBrowserSource {
    case live
    case verifiedPostSwitch
    case staleFallback
    case none
}

enum BrowserUserVisibleStatus: Equatable {
    case loading
    case idle
    case stale(String)
    case switching(String)
    case updated(String)
    case needsAttention(String)
}

struct ActionableBrowserRow: Equatable, Identifiable {
    let candidate: BrowserCandidate
    let isSelected: Bool
    var id: String { candidate.id }
}

struct NonActionableBrowserRow: Equatable, Identifiable {
    enum Reason: Equatable {
        case missingBundleIdentifier
        case missingRequiredSchemes
        case informational
    }

    let candidate: BrowserCandidate
    let reason: Reason
    var id: String { candidate.id }
}

struct BrowserDiscoveryPresentation: Equatable {
    let currentBrowser: BrowserApplication?
    let currentBrowserSource: CurrentBrowserSource
    let currentBrowserIsActionable: Bool
    let selectedActionableBrowserID: String?
    let switchableBrowsers: [ActionableBrowserRow]
    let nonActionableBrowsers: [NonActionableBrowserRow]
    let userVisibleStatus: BrowserUserVisibleStatus
    let showRefreshInMenu: Bool
    let advancedSummary: BrowserAdvancedSummary
}
```

Keep creation logic pure so it is easy to test without rendering SwiftUI.

- [ ] **Step 7: Add small snapshot/store helpers instead of view-side re-derivation**

In `BrowserDiscoverySnapshot.swift`, add only small helpers that clarify intent, such as:

```swift
var coherentCurrentBrowser: BrowserApplication? {
    guard let http = currentHTTPHandler,
          let https = currentHTTPSHandler,
          http.normalizedApplicationPath == https.normalizedApplicationPath
    else { return nil }
    return http.merged(with: https)
}
```

In `BrowserDiscoveryStore.swift`:

- add `@Published private(set) var lastCoherentBrowser: BrowserApplication?`
- add a computed or published `presentation`
- update `refresh()` to refresh `lastCoherentBrowser` when a coherent browser is discovered
- when `lastSwitchResult.verifiedSnapshot` is coherent, update `lastCoherentBrowser` from that verified snapshot even for `.mixed` / `.failure`
- keep `snapshot` unchanged on `.mixed` / `.failure`
- derive presentation from `lastSwitchResult.verifiedSnapshot` when required

- [ ] **Step 8: Add `BrowserIconProvider.swift` with a minimal cache and tests-by-contract comments**

Implement a shared icon provider, e.g.:

```swift
@MainActor
final class BrowserIconProvider: ObservableObject {
    private let workspace: NSWorkspace
    private var cache: [String: NSImage] = [:]

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func icon(for applicationURL: URL) -> NSImage {
        let key = applicationURL.standardizedFileURL.path
        if let cached = cache[key] { return cached }
        let image = workspace.icon(forFile: key)
        cache[key] = image
        return image
    }
}
```

Keep it simple; no async loading unless profiling later proves it necessary.

- [ ] **Step 9: Write failing tests for deterministic success-state expiry and reset**

Add focused tests that lock the `updated(browserName)` lifecycle before implementing it.

Required cases:

- verified success enters `updated(browserName)`
- the state clears after the chosen expiry window
- the state clears immediately on refresh
- the state clears immediately on a new switch attempt

Use an injectable clock/timer seam so the tests do not rely on wall-clock sleeps.

- [ ] **Step 10: Implement deterministic success-state expiry in the presentation seam**

Add a small injectable timing/reset seam so `updated(browserName)` can be tested without sleeps baked into the view layer.

Requirements:

- verified success enters `updated(browserName)` presentation state
- that state clears after the chosen 3–5 second expiry
- it clears immediately on a new refresh
- it clears immediately on a new switch attempt

Prefer a small clock/reset abstraction owned by the store/presentation layer rather than ad hoc `DispatchQueue` calls in `SettingsView`.

- [ ] **Step 11: Re-run focused presentation/store tests until they pass**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/BrowserPresentationTests -only-testing:BrowserDiscoveryTests/BrowserDiscoveryStoreTests
```

Expected: PASS with the new presentation tests green and no regressions in existing store tests.

- [ ] **Step 12: Commit chunk 1**

```bash
git add App/Application/BrowserDiscovery/BrowserPresentation.swift \
        App/Application/BrowserDiscovery/BrowserIconProvider.swift \
        App/Application/BrowserDiscovery/BrowserDiscoveryStore.swift \
        App/Application/BrowserDiscovery/BrowserDiscoverySnapshot.swift \
        DefaultBrowserSwitcher.xcodeproj/project.pbxproj \
        Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift \
        Tests/BrowserDiscoveryTests/BrowserDiscoveryStoreTests.swift
git commit -m "feat: add browser presentation seam for native ui"
```

---

## Chunk 2: Rebuild Settings around the new presentation seam

### Task 2: Replace the protocol-heavy Settings form with a system-style default-browser control

**Files:**
- Modify: `App/Features/Settings/SettingsView.swift`
- Modify: `App/DefaultBrowserSwitcherApp.swift`
- Modify: `App/Application/BrowserDiscovery/BrowserPresentation.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Modify: `Tests/BrowserDiscoveryTests/AppShellSmokeTests.swift`
- Modify: `Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift`

- [ ] **Step 1: Write failing Settings-facing presentation tests for the new Picker contract**

Add tests in `Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift` that lock the Settings behavior without depending on brittle UI inspection.

Example assertions:

```swift
func testSettingsPresentationUsesChooseBrowserPlaceholderForMixedState() {
    XCTAssertNil(presentation.selectedActionableBrowserID)
    XCTAssertEqual(presentation.settingsPickerPlaceholder, "Choose a browser")
    XCTAssertEqual(presentation.userVisibleStatus, .needsAttention("Default browser needs attention"))
}

func testSettingsPresentationDisablesPickerWhenNoActionableCandidatesExist() {
    XCTAssertTrue(presentation.switchableBrowsers.isEmpty)
    XCTAssertTrue(presentation.isPickerDisabled)
    XCTAssertEqual(presentation.settingsPickerPlaceholder, "No supported browsers found")
}

func testSettingsPresentationShowsInformationalCurrentBrowserForNonActionableCoherentState() {
    XCTAssertEqual(presentation.currentBrowser?.resolvedDisplayName, "Helper Browser")
    XCTAssertNil(presentation.selectedActionableBrowserID)
    XCTAssertEqual(presentation.userVisibleStatus, .needsAttention("Current browser can’t be managed here"))
}
```

Also add one test that proves Picker `nil` is presentation-only and does not produce a switch target.

- [ ] **Step 2: Run the focused presentation tests and verify they fail**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/BrowserPresentationTests
```

Expected: FAIL until the Settings-facing presentation helpers/state exist. `AppShellSmokeTests` may still pass at this point and should **not** be treated as the failing gate for this chunk.

- [ ] **Step 3: Extend `BrowserPresentation.swift` with Settings-facing derived state**

Add the minimal extra values `SettingsView` needs so the view does not re-derive behavior from raw store state, for example:

```swift
struct BrowserDiscoveryPresentation: Equatable {
    let currentBrowser: BrowserApplication?
    let selectedActionableBrowserID: String?
    let switchableBrowsers: [ActionableBrowserRow]
    let settingsPickerPlaceholder: String
    let isPickerDisabled: Bool
    let userVisibleStatus: BrowserUserVisibleStatus
    let advancedSummary: BrowserAdvancedSummary
}
```

Keep the rule that primary views read only the presentation seam, not raw `snapshot`, `lastSwitchResult`, per-scheme outcomes, or candidate counts.

- [ ] **Step 4: Rewrite `SettingsView.swift` around the presentation model**

Target structure:

```swift
struct SettingsView: View {
    @EnvironmentObject private var store: BrowserDiscoveryStore
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    var body: some View {
        Form {
            Section {
                defaultBrowserRow
                statusFootnote
            }

            DisclosureGroup("Advanced") {
                advancedRefreshRow
                advancedVerificationSummary
                advancedCandidateList
            }
        }
        .formStyle(.grouped)
        .task { await store.bootstrapIfNeeded() }
    }
}
```

Ownership rule:

- create one shared `BrowserIconProvider` in `DefaultBrowserSwitcherApp.swift`
- inject the same instance into `SettingsView`, `MenuBarContentView`, and the status-item/AppKit shell path
- do not create per-view icon-provider instances


Implementation rules:

- main surface reads only `store.presentation`
- default row shows current browser icon/name informationally when available
- Picker lists actionable browsers only
- Picker `nil` is presentation-only; the user cannot select “none”
- Picker change triggers an immediate switch attempt to the chosen actionable browser
- Picker retains the prior selected actionable browser visually while switching, then resolves to the actual post-switch presentation state
- Picker is disabled during switching and when no actionable browsers exist
- Advanced contains refresh, last verification summary, non-actionable apps with reasons, and technical detail text
- do **not** render `http`/`https`, candidate counts, or raw per-scheme rows in the main section

- [ ] **Step 5: Add localized strings for the new Settings copy**

Add strings for at least:

- `Default web browser`
- `Choose a browser`
- `No supported browsers found`
- `Current browser can’t be managed here`
- `Default browser needs attention`
- `Current browser may be out of date`
- `Advanced`
- `Refreshing current browser…` / equivalent concise copy if needed

- [ ] **Step 6: Re-run the focused Settings-related tests**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/AppShellSmokeTests -only-testing:BrowserDiscoveryTests/BrowserPresentationTests -only-testing:BrowserDiscoveryTests/BrowserDiscoveryStoreTests
```

Expected: PASS with the new Settings contract and no regressions in presentation/store behavior.

- [ ] **Step 7: Wire the shared `BrowserIconProvider` through `DefaultBrowserSwitcherApp.swift` for Settings**

In this chunk, instantiate one shared `BrowserIconProvider` in `DefaultBrowserSwitcherApp.swift` and inject it into `SettingsView` so the new Settings surface compiles and uses the shared cache before the menu-shell rewrite lands.

Do not wait for Chunk 3 to introduce this dependency injection.

- [ ] **Step 8: Commit chunk 2**

```bash
git add App/Features/Settings/SettingsView.swift \
        App/DefaultBrowserSwitcherApp.swift \
        App/Application/BrowserDiscovery/BrowserPresentation.swift \
        App/Resources/Localizable.xcstrings \
        Tests/BrowserDiscoveryTests/AppShellSmokeTests.swift \
        Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift
git commit -m "feat: redesign settings around default browser picker"
```

---

## Chunk 3: Simplify the menu and switch the shell to a dynamic browser icon

### Task 3: Replace the menu diagnostics panel with a browser picker and dynamic status-item icon

**Files:**
- Modify: `App/Features/MenuBar/MenuBarContentView.swift`
- Modify: `App/DefaultBrowserSwitcherApp.swift`
- Modify: `App/Application/BrowserDiscovery/BrowserPresentation.swift`
- Modify: `Tests/BrowserDiscoveryTests/AppShellSmokeTests.swift`
- Modify: `Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Conditional if AppKit bridge is needed: modify/create the minimal bridge file(s) and update `DefaultBrowserSwitcher.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests for the new shell/status-item presentation contract**

Add tests for a small status-item presentation model in `BrowserPresentation.swift` rather than only testing the SwiftUI shell directly.

Example shape:

```swift
func testStatusItemPresentationUsesCurrentBrowserIconWhenCoherent() {
    let item = StatusItemPresentation.make(from: presentation)
    XCTAssertEqual(item.accessibilityLabel, "Default browser: Arc")
    XCTAssertEqual(item.iconSource, .browser("/Applications/Arc.app"))
}

func testStatusItemPresentationFallsBackToNeutralIconForAttentionState() {
    let item = StatusItemPresentation.make(from: attentionPresentation)
    XCTAssertEqual(item.iconSource, .neutral)
    XCTAssertEqual(item.accessibilityLabel, "Default browser needs attention")
}
```

Also add explicit cases for:

- coherent but **non-actionable** current browser still using the browser icon
- `.mixed` / `.failure` with a **coherent verified snapshot** using the verified browser icon
- stale fallback using a browser icon but **no normal selected checkmark** in menu state
- menu Refresh visibility following `presentation.showRefreshInMenu` exactly

Also replace the old fixed-globe shell smoke assertion:

```swift
XCTAssertEqual(DefaultBrowserSwitcherApp.menuBarSystemImage, "globe")
```

with assertions against the new status-item contract type or API.

- [ ] **Step 2: Run focused shell tests and verify they fail under the old globe-based shell**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/AppShellSmokeTests -only-testing:BrowserDiscoveryTests/BrowserPresentationTests
```

Expected: FAIL because the app shell still exposes a static globe symbol and the menu still renders protocol/status sections.

- [ ] **Step 3: Simplify `MenuBarContentView.swift` to a browser-picker menu**

Rewrite the menu to consume only the presentation seam.

Target behavior:

- compact title/current-browser header when coherent
- simplified switch-status copy only
- actionable browser rows with icon + title + optional selected checkmark
- Refresh shown only when `presentation.showRefreshInMenu` is true
- Settings + Quit always available
- no default-path protocol rows, candidate counts, helper badges, or raw verification section

Implementation rules:

- render the primary list from `store.presentation.switchableBrowsers` only
- never rebuild selection logic from raw `snapshot`
- never show stale fallback as a normal selected row
- use `presentation.showRefreshInMenu` as the only gate for Refresh visibility

Candidate row shape should become much simpler, e.g.:

```swift
private struct BrowserMenuRow: View {
    let row: ActionableBrowserRow
    let icon: NSImage

    var body: some View {
        HStack(spacing: 10) {
            if row.isSelected { Image(systemName: "checkmark") }
            Image(nsImage: icon)
            Text(row.candidate.resolvedDisplayName)
        }
    }
}
```

- [ ] **Step 4: Update `DefaultBrowserSwitcherApp.swift` to use the new shell/status-item contract**

Implement `StatusItemPresentation` in `App/Application/BrowserDiscovery/BrowserPresentation.swift`, then consume it from `DefaultBrowserSwitcherApp.swift`.

Preferred approach order:

1. derive a `StatusItemPresentation` value from `store.presentation`
2. if SwiftUI `MenuBarExtra` can be driven with that dynamic icon cleanly, keep it
3. otherwise bridge only the status-item/icon shell to AppKit while leaving menu/settings content in SwiftUI

Minimum contract to expose/test:

```swift
struct StatusItemPresentation: Equatable {
    enum IconSource: Equatable {
        case browser(URL)
        case neutral
    }

    let iconSource: IconSource
    let accessibilityLabel: String
    let tooltip: String
}
```

Neutral icon rule:

- `.neutral` resolves to the app bundle’s generic status icon (not a browser-specific icon)
- if an AppKit bridge is introduced, keep the same `.neutral` contract rather than inventing a separate fallback path
- add one small test seam proving `.browser(URL)` vs `.neutral` resolution at the presentation layer

If `MenuBarExtra` cannot reliably update the icon, introduce the minimal AppKit status-item bridge in this chunk and add its test seam here rather than deferring that decision to final verification.

- [ ] **Step 5: Add localized strings for the simplified menu and status-item copy**

Add or replace strings for:

- menu/status-item accessibility labels and tooltips
- simplified menu header copy
- stale/attention Refresh wording
- concise switching / updated / needs-attention menu copy

- [ ] **Step 6: Re-run shell/menu/presentation tests until green**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests/AppShellSmokeTests -only-testing:BrowserDiscoveryTests/BrowserPresentationTests -only-testing:BrowserDiscoveryTests/BrowserDiscoveryStoreTests
```

Expected: PASS with the new dynamic-shell/menu presentation contract.

- [ ] **Step 7: Run the broader BrowserDiscovery suite as regression coverage**

Run:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests
```

Expected: PASS. This is the regression gate before claiming the redesign complete.

- [ ] **Step 8: Commit chunk 3**

```bash
git add App/Features/MenuBar/MenuBarContentView.swift \
        App/DefaultBrowserSwitcherApp.swift \
        App/Application/BrowserDiscovery/BrowserPresentation.swift \
        App/Resources/Localizable.xcstrings \
        Tests/BrowserDiscoveryTests/AppShellSmokeTests.swift \
        Tests/BrowserDiscoveryTests/BrowserPresentationTests.swift \
        Tests/BrowserDiscoveryTests/BrowserDiscoveryStoreTests.swift
# If an AppKit bridge was needed, also add the bridge file(s) and DefaultBrowserSwitcher.xcodeproj/project.pbxproj
git commit -m "feat: redesign menu bar around current browser icon"
```

---

## Final verification checklist

- [ ] Run the focused BrowserDiscovery test suite:

```bash
xcodebuild test -project DefaultBrowserSwitcher.xcodeproj -scheme DefaultBrowserSwitcher -destination 'platform=macOS' -only-testing:BrowserDiscoveryTests
```

Expected: all BrowserDiscovery tests pass.

- [ ] Re-run the live S02 proof:

```bash
bash Scripts/verify-s02.sh
```

Expected: PASS with successful build, switch, verified readback, and restore. This is required because the redesign must preserve the existing script/report/UAT contract.

- [ ] Re-run the live S01 proof:

```bash
bash Scripts/verify-s01.sh
```

Expected: PASS. This is required because the redesign changes app-shell wiring and must preserve the earlier discovery/report contract as well.

- [ ] If the dynamic status-item shell required AppKit bridging, add/adjust smoke tests so the shell contract is asserted via value-level presentation tests rather than brittle UI-only checks.

- [ ] Confirm the raw-contract invariants still hold:
  - success keeps top-level `snapshot` aligned with verified success state
  - mixed/failure does not overwrite the top-level discovered `snapshot`
  - mixed/failure UI truth may still derive from `lastSwitchResult.verifiedSnapshot`

- [ ] Review the final strings in `Localizable.xcstrings` for awkward technical phrasing.

- [ ] Required manual macOS spot-check:
  - open Settings and confirm the default-browser row feels system-like
  - open the menu and confirm the current browser icon/checkmark flow matches the simplified design
  - confirm stale/attention states show Refresh only when intended
  - confirm the status-item icon/tooltip/accessibility label match the current presentation state

---

## Plan review notes for implementers

- Keep commits scoped to the chunk boundaries above.
- Do not collapse the presentation seam and UI rewrite into one massive commit.
- If the status-item icon cannot be made dynamic with the existing `MenuBarExtra` shell, bridge only the shell layer; do not rewrite the rest of the app architecture.
- Preserve the S02 verification/report semantics even if the UI language becomes much simpler.

Plan complete and saved to `docs/superpowers/plans/2026-03-27-default-browser-ui-redesign.md`. Ready to execute?