# Default Browser UI Redesign

- **Date:** 2026-03-27
- **Project:** `default-browser-switcher`
- **Status:** Proposed and user-approved for planning
- **Scope:** UI/presentation redesign for the menu bar and Settings surfaces. The verified browser-switching contract from S02 remains intact.

## Context

The current S02 implementation is functionally correct but presents too much of the switch/verification machinery directly in the product UI. The Settings window and menu bar expose internal concepts such as `http` / `https`, phase labels, candidate counts, per-scheme outcomes, mismatch details, and helper/partial-candidate explanations in the default path.

That makes the app feel like a debugging surface instead of a native macOS utility. The user wants the product to feel closer to the system’s own **Default web browser** control in **Desktop & Dock**:

- the main concept should be **one default browser**, not two protocols
- the menu bar should show the **current browser icon**, not a generic globe
- verification details should continue to exist, but should move behind an **Advanced** affordance instead of dominating the default UI

## User-approved direction

The approved redesign direction is:

1. **System-style Settings surface** as the primary presentation
2. **Current browser icon in the menu bar**
3. **Hide protocol details from the default UI**
4. **Keep verification details behind an advanced/debug surface**

## Goals

### Product goals

- Make the app feel native to macOS rather than tool-like
- Present a single understandable concept: **the current default web browser** when the discovered current state is coherent
- Preserve trust by keeping post-switch verification, but surface it with concise human-facing language first
- Keep menu bar switching fast and obvious

### Technical goals

- Preserve the existing verified write/readback switching contract from S02
- Avoid duplicating interpretation logic between menu bar and Settings
- Add a reusable browser-icon provider instead of scattering `NSWorkspace` icon lookups inside views
- Introduce a higher-level presentation seam so SwiftUI views do not depend on raw protocol-level switch state

### Non-goals

- Rewriting the switching backend or discarding readback verification
- Changing the JSON/report contract used by scripts and UAT
- Adding a new user-triggered export flow in this redesign pass
- Expanding scope into launch-at-login, restart continuity, or other later-slice work
- Designing a custom non-native control style that diverges from macOS conventions

## UX principles

1. **One concept in the main UI** — the app should talk about the current default browser, not protocol handlers.
2. **Diagnostics are secondary** — keep them available, but not in the user’s face.
3. **Short-lived success, persistent attention** — verified success should settle quickly; unresolved or mixed state should remain visible until the system is coherent again.
4. **Native-first** — prefer system-style rows, icons, checkmarks, disclosure, and menu structure over explanatory badges and internal-state copy.
5. **Truth remains grounded in current discovered state plus verified switch outcomes** — simplification in UI language must not weaken the readback-based truth model.

## Information architecture

### Actionable full-browser candidate

A candidate is **actionable** only when all of these are true:

- it has a non-empty bundle identifier
- it supports both `http` and `https`
- it is suitable for a full default-browser switch target in the existing store/service contract

A candidate is **non-actionable** when any of these apply:

- missing bundle identifier
- missing required schemes
- informational/helper-style app that should not be used as the primary default-browser target

Non-actionable candidates must appear only in **Settings > Advanced**, along with a reason string derived from one of those categories.

### Settings window

#### Main surface

The Settings window should primarily show a system-style **Default web browser** control.

Recommended structure:

- Title/section label: `Default web browser`
- A single row showing:
  - current browser app icon when a coherent current browser exists
  - current browser display name when a coherent current browser exists
  - a trailing **Picker** affordance that mirrors the system’s default-browser style more closely than a custom button row
- Optional short helper text beneath the row explaining that the app verifies the result after changing it

What should **not** appear in the default Settings surface:

- `http` / `https` rows
- generic phase labels like `loaded`, `refreshing`, `failed`
- candidate count
- raw mismatch details
- per-scheme callback results

#### Picker behavior rules

The Settings Picker lists **actionable full-browser candidates only**.

Behavior by state:

1. **Coherent and actionable current browser**
   - Picker shows that browser as the selected value
2. **No coherent current browser**
   - Picker shows no selected browser and uses a placeholder such as `Choose a browser`
   - Primary helper/status copy explains that the current browser cannot be represented as one coherent default browser
   - User may still choose an actionable browser from the Picker
3. **Coherent current browser exists but is not actionable in this app**
   - Main row still shows the current browser icon/name as informational state
   - Picker shows no selected actionable browser and uses the same `Choose a browser` placeholder
   - Helper copy explains that the current browser is detected but cannot be managed as a full-browser switch target here
4. **Zero actionable candidates available**
   - Picker is disabled
   - Picker shows a placeholder such as `No supported browsers found`
   - Helper copy explains that the app can read the current browser state but has no full-browser target it can switch to

#### Advanced disclosure

The Settings window should include an **Advanced** disclosure group or secondary section that is collapsed by default.

That section must contain, at minimum:

- Refresh current browser state
- Last verification time/result
- Technical mismatch details when present
- Per-scheme callback/readback details when relevant
- Informational/non-switchable detected apps and why they are not actionable

This preserves observability and supportability without making the main Settings experience feel technical.

### Menu bar surface

#### Menu bar item

The menu bar item should prefer the **current browser icon derived from the current coherent snapshot**.

This is a requirement for the redesign, not a best-effort enhancement. If `MenuBarExtra` cannot reliably support a dynamic app icon, a small AppKit bridge for the status-item/icon layer is in scope.

Icon fallback chain:

1. use the icon for the current coherent browser from the current snapshot
2. if icon lookup fails for a coherent current browser, use a neutral app/status icon
3. if there is no coherent current browser, use a neutral app/status icon

Shell contract:

- the menu bar item is **icon-only** in the status bar
- its accessibility label and tooltip should always expose a human-readable state, e.g. `Default browser: Arc` or `Default browser needs attention`
- the neutral fallback asset is the app’s generic status icon, not a browser-specific icon

#### Opened menu

The opened menu should behave like a focused browser picker.

Recommended structure:

- Optional compact header showing `Default browser` + current browser name when coherent
- Browser list:
  - app icon on the left
  - current selection indicated with a checkmark only when one coherent actionable browser is selected
  - only actionable full-browser candidates in the main list
- Concise status line for switching / updated / needs attention
- Refresh action shown only in stale or attention states
- Settings
- Quit

What should **not** appear in the default menu:

- `HTTP` / `HTTPS` badges
- protocol-specific handler rows
- candidate counts
- helper/partial candidate explanation badges in the main switch list
- default-visible verification dump blocks

#### Informational or partial candidates

Candidates that cannot serve as the complete default-browser target should not clutter the primary switch list.

Explicit rule:

- keep them visible only in **Settings > Advanced** for truthful reporting
- do **not** surface them in the primary menu-bar switch list
- do **not** present them as equivalent first-class switch targets in the default UI

## Interaction model

### Coherent current browser

A single current browser exists only when the discovered current handlers resolve to the same app.

Definition:

- `currentBrowser` is present when `currentHTTPHandler` and `currentHTTPSHandler` are both resolvable and share the same normalized application path
- otherwise `currentBrowser` is absent and the primary UI enters an attention state rather than inventing a single-browser answer

This is the core rule that allows the UI to simplify to one browser concept without lying.

### `lastCoherentBrowser`

`lastCoherentBrowser` is an in-memory presentation aid, not persisted product state.

Rules:

- set it whenever a refresh or a verified switch snapshot yields a coherent current browser
- keep it only for the current app session
- do not restore it across app relaunch; a fresh discovery pass must rebuild truth
- use it only for stale-state fallback presentation when current discovery fails
- clear it when the app has never observed a coherent browser in the current session

### Attention states

The UI is in an **attention state** when any of these are true:

- the current discovered handlers are mixed or unresolved
- the current browser is coherent but non-actionable
- the latest verified switch result is `.mixed` or `.failure`
- refresh failed and the UI is showing stale fallback state
- no resolvable current browser exists

Menu rule:

- show **Refresh** in the menu only while an attention state or stale state is active
- keep **Refresh** always available in **Settings > Advanced**

### Presentation source precedence

The presentation layer must not guess between sources. It should follow this precedence order:

1. **Live coherent `snapshot`**
   - use when the current discovered snapshot is coherent and available
2. **Post-switch `lastSwitchResult.verifiedSnapshot`**
   - use for presentation after a switch returns `.mixed` or `.failure` with a verified snapshot
   - this derived presentation state remains active until the next refresh or switch attempt replaces it
3. **`lastCoherentBrowser` stale fallback**
   - use only when no current coherent source is available and refresh has failed or the latest switch result lacks a coherent verified snapshot
   - this is informational only and must never be treated as a selected actionable browser
4. **No current browser presentation**
   - use when none of the above sources can truthfully supply a coherent browser

Reset rules:

- a successful refresh with a coherent live `snapshot` replaces any post-switch derived presentation state
- a new switch attempt replaces the previous post-switch derived presentation state
- `lastCoherentBrowser` updates only when a coherent browser is observed from a live refresh or a verified switch snapshot
- `lastCoherentBrowser` is never persisted across app relaunch

### Primary-surface state table

| State | Primary current browser | Checkmark in menu | Menu bar icon | Main status copy | Change control |
|---|---|---|---|---|---|
| Initial loading before first snapshot | None | None | Neutral icon | `Loading current browser…` | Disabled |
| Loaded, coherent current browser | That browser | Yes if actionable | Browser icon | None | Enabled when actionable candidates exist |
| Loaded, mixed or unresolved current handlers | None | None | Neutral icon | `Default browser needs attention` | Enabled when actionable candidates exist |
| Loaded, coherent but non-actionable current browser | Show current browser informationally in Settings | None | Browser icon | `Current browser can’t be managed here` | Enabled when actionable candidates exist |
| Switching in progress | Last coherent browser if available, else none | Existing coherent selection only | Existing browser icon or neutral fallback | `Switching default browser…` / optional `Verifying…` | Disabled |
| Verified success | Requested browser | Yes if actionable | Requested browser icon | Brief success copy, then clear | Enabled when actionable candidates exist |
| Verified mixed/failure with coherent verified snapshot | Show the browser from `lastSwitchResult.verifiedSnapshot` as the current informational browser | Yes if that browser is actionable | Browser icon from the verified snapshot | `Couldn’t verify the browser change` plus concise copy such as `System still appears to be using Arc` | Enabled when actionable candidates exist |
| Verified mixed/failure with mixed or unresolved verified snapshot | None | None | Neutral icon | `Couldn’t verify the browser change` | Enabled when actionable candidates exist |
| Verified mixed/failure with no verified snapshot | Keep last coherent browser only as stale informational fallback if available, else none | No normal checkmark | Last coherent browser icon if available, else neutral icon | `Couldn’t verify the browser change` | Enabled when actionable candidates exist |
| Refresh failed with stale last coherent state available | Show last coherent browser as stale informational fallback | No normal checkmark | Last coherent browser icon | `Current browser may be out of date` | Enabled when actionable candidates exist |
| No resolvable current browser and no coherent fallback | None | None | Neutral icon | `Current browser unavailable` | Enabled when actionable candidates exist |

### Normal state

In the settled coherent state:

- show the current browser
- do not keep a persistent success banner visible
- let the UI feel calm and stable

### While switching

During a requested switch:

- temporarily disable repeat switch actions
- show concise user-language feedback, e.g. `Switching default browser…`
- optionally show `Verifying…` while readback completes

### After a verified success

Immediately after success:

- the current browser icon/name updates to the verified result
- Settings may show a brief confirmation such as `Default browser updated` for roughly 3–5 seconds, then return to the calm settled state
- the `updated(browserName)` presentation state clears on timer expiry or immediately when a new refresh/switch action replaces it
- the menu should not depend on a transient success banner for trust; the authoritative signal is the updated icon/checkmark/current browser state the next time it is opened

### Mixed or failed verification

If readback cannot confirm the requested result:

- show concise human-language feedback first, e.g.:
  - `Couldn’t verify the browser change`
  - `The system still appears to be using Arc`
- leave this attention state visible until the next successful refresh or switch attempt resolves the system into a coherent state
- point the user to **Advanced** for details when necessary
- do not surface raw `http` / `https` or callback output in the default path

### Refresh failure or stale state

If refresh fails but the app still has a previously coherent browser snapshot:

- keep showing the last coherent browser icon/name only as stale fallback presentation
- do not render a normal current-selection checkmark for it in the menu
- add concise stale-state copy such as `Current browser may be out of date`
- show Refresh in the menu while this stale/attention state is active
- always keep Refresh available in **Settings > Advanced**

## Presentation model redesign

The current views pull too much raw state directly from `BrowserDiscoveryStore`. The redesign should introduce a higher-level presentation seam so views consume product-oriented state rather than reinterpreting low-level switching details.

Recommended layers:

### 1. Primary UI state

Used by the default Settings and menu bar UI:

- `currentBrowser: BrowserApplication?`
- `currentBrowserSource` (`live`, `verifiedPostSwitch`, `staleFallback`, `none`)
- `currentBrowserIsActionable: Bool`
- `selectedActionableBrowserID: String?`
- `lastCoherentBrowser: BrowserApplication?`
- `switchableBrowsers: [BrowserCandidate]`
- `nonActionableCandidatesWithReasons: [(candidate, reason)]`
- `isSwitching: Bool`
- `showRefreshInMenu: Bool`
- `userVisibleStatus`
- `advancedVerificationSummary`

Example `userVisibleStatus` states:

- `loading`
- `idle`
- `stale(message)`
- `switching(targetName)`
- `updated(browserName)`
- `needsAttention(message)`

Rules:

- primary views must not inspect raw `snapshot`, raw `schemeOutcomes`, or per-scheme data to decide checkmarks, placeholders, or default-path messaging
- the presentation seam must already answer those questions before the view layer renders
- `selectedActionableBrowserID` is non-nil only when one coherent actionable browser is currently selected

This layer must not expose `http` / `https` as first-class UI concepts.

### 2. Advanced status

Used by the Settings **Advanced** disclosure:

- last verification time
- last requested target
- high-level verification outcome
- optional technical detail summaries
- informational/non-switchable candidates

### 3. Raw diagnostics

Preserved for scripts, exported reports, tests, and support/debugging:

- `BrowserSwitchResult`
- per-scheme outcomes
- readback error messages
- mismatch details
- exported JSON snapshot/report contract

## Code structure changes

### `App/Features/Settings/SettingsView.swift`

Refactor from a protocol-oriented status form into a system-style preference surface.

Responsibilities after redesign:

- render the main **Default web browser** row
- render concise user-facing switch status
- host the collapsed **Advanced** section
- render the native-style **Picker** control for actionable browsers
- support nil-selection behavior when no actionable coherent current browser exists
- avoid direct presentation of raw protocol-level state in the primary surface

### `App/Features/MenuBar/MenuBarContentView.swift`

Simplify from a multi-section diagnostic panel into a focused browser picker.

Responsibilities after redesign:

- render the browser list with icons and current-selection checkmark only for coherent actionable current state
- trigger switching through the existing shared store boundary
- render short status copy only
- show Refresh only when stale or attention states need a quick recovery path
- keep Settings and Quit actions
- remove main-path protocol badges, phase rows, and verification dump sections

### `App/DefaultBrowserSwitcherApp.swift`

Revisit the status-item representation so the menu bar can show the current browser icon instead of a fixed symbol.

This is the highest-risk implementation point. The redesign should try the lightest native approach first. If `MenuBarExtra` cannot reliably support a dynamic app-icon presentation, bridge only the status-item/icon layer instead of rewriting the app shell.

This redesign intentionally changes the current static menu-bar shell contract from a fixed globe symbol to a dynamic icon-first status item with accessibility labeling driven by presentation state.

### `App/Application/BrowserDiscovery/BrowserDiscoveryStore.swift`

Keep the verified switching contract, but add or expose a higher-level product-facing presentation seam.

Responsibilities after redesign:

- derive `currentBrowser` only when the discovered current handlers agree
- derive `lastCoherentBrowser`
- derive `switchableBrowsers`
- derive concise user-visible switch state
- separate informational/non-switchable candidates for Settings Advanced
- retain raw switch result and diagnostics for advanced/debug inspection
- when a switch result includes a `verifiedSnapshot`, do **not** overwrite the store’s top-level discovered `snapshot` on `.mixed` or `.failure`
- instead, derive post-switch presentation state from `lastSwitchResult.verifiedSnapshot` when it exists, so the UI can reflect the actual post-switch reality without mutating the existing report/test contract around the main discovered snapshot

The store should remain the single truth source for both menu bar and Settings.

### New `BrowserIconProvider`

Add a small shared component, e.g. `App/Application/BrowserDiscovery/BrowserIconProvider.swift`.

Responsibilities:

- resolve an app icon from `applicationURL`
- cache icon lookups
- serve both Settings and menu bar
- keep AppKit icon-loading logic out of SwiftUI view bodies

## Implementation sequence

1. **Add the presentation seam first**
   - define product-facing UI state in or near the store
   - codify coherent vs mixed current-browser rules
   - codify `lastCoherentBrowser` lifecycle
   - avoid starting with ad hoc SwiftUI rewrites
2. **Redesign Settings next**
   - validate the system-style control first in the lower-risk surface
3. **Redesign the opened menu**
   - simplify sections and candidate rows
   - confirm stale/attention refresh behavior
4. **Finish with the menu bar icon**
   - handle the highest-risk dynamic status-item work after the data and opened-menu surfaces are stable

## Risks

### Dynamic status-item icon support

Biggest uncertainty: whether the current SwiftUI `MenuBarExtra` usage can reliably show a dynamic browser icon that updates with current coherent state.

Mitigation:

- first attempt a native SwiftUI-compatible approach
- if insufficient, bridge only the status-item/icon layer via AppKit
- dynamic browser icon remains required for the redesign target

### Oversimplifying feedback

If the UI becomes too quiet, switching may feel opaque.

Mitigation:

- keep short transient switching feedback
- keep concise failure/needs-attention messaging
- preserve visible access to Advanced details
- rely on coherent icon/name/checkmark state as the durable success signal

### Partial/helper candidate truthfulness

Removing badges from the main UI can accidentally hide truthful system reporting if not replaced thoughtfully.

Mitigation:

- separate main actionable candidates from informational ones
- keep informational visibility in **Settings > Advanced**
- do not pretend unsupported candidates are actionable full-browser targets

### Regression against script/UAT proof

The redesign must not weaken the live proof surfaces used by `verify-s02.sh` and related tests.

Mitigation:

- treat this as a presentation refactor
- preserve exported report structure and readback verification semantics
- ensure tests and scripts continue to assert against the raw diagnostic layer, not the simplified UI layer

## Acceptance criteria

The redesign is successful when:

1. Settings presents a system-style **Default web browser** control as the primary surface.
2. The default UI no longer exposes `http` / `https` as primary concepts.
3. The Settings main row uses a native-style **Picker** for actionable browsers, with explicit nil-selection behavior when no actionable coherent current browser exists.
4. The menu bar item reflects the current coherent browser icon when one exists, and falls back to a neutral icon otherwise.
5. The opened menu behaves like a native browser picker with icons and a current-selection checkmark only when one coherent actionable current browser exists.
6. Verification continues to drive truth, but its details live behind **Advanced** instead of the default UI.
7. Informational/non-switchable candidates are visible only in **Settings > Advanced**.
8. Refresh remains available in **Settings > Advanced** and appears in the menu only during stale or attention states.
9. When a switch result includes a `verifiedSnapshot` for a `.mixed` or `.failure` result, the UI may derive post-switch presentation from `lastSwitchResult.verifiedSnapshot` without rewriting the store’s top-level discovered `snapshot`.
10. On success, the existing raw report contract remains intact: the top-level `snapshot` continues to match the verified live success snapshot/report behavior.
11. The existing script/report/UAT contract remains valid.

## Remaining implementation questions

1. Which lightest dynamic-icon approach works first with the current `MenuBarExtra` shell before an AppKit bridge is needed?
2. Should success copy in Settings clear after 3 seconds or 5 seconds?
3. What exact stale-state wording reads best when refresh fails but a last coherent browser is still available?

These are implementation-tuning questions, not product-direction blockers.

## Recommendation

Proceed with planning and implementation using this redesign as the target shape. Keep the backend truth model from S02, but simplify the default product-facing language and visual structure so the app feels like a native macOS default-browser control rather than a protocol-level inspection tool.