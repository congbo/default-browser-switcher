import Combine
import Foundation

struct BrowserPresentation: Equatable {
    enum CurrentBrowserSource: Equatable {
        case liveSnapshot
        case verifiedPostSwitch
        case staleFallback
        case none
    }

    struct CurrentBrowser: Equatable {
        let application: BrowserApplication
        let source: CurrentBrowserSource
    }

    struct Candidate: Identifiable, Equatable {
        enum DisabledReason: Equatable {
            case missingBundleIdentifier
            case missingRequiredSchemes
            case ineligibleTarget
            case switchInProgress
        }

        enum ActionState: Equatable {
            case currentSelection
            case switchable
            case disabled(DisabledReason)
        }

        let candidate: BrowserCandidate
        let actionState: ActionState
        let isCurrentBrowser: Bool

        var id: String {
            candidate.id
        }

        var isActionable: Bool {
            switch actionState {
            case .switchable:
                true
            case .currentSelection, .disabled:
                false
            }
        }
    }

    struct CurrentHandlerInspection: Identifiable, Equatable {
        enum State: Equatable {
            case currentBrowser
            case mixed
            case nonActionable(Candidate.DisabledReason)
            case missing
        }

        let scheme: BrowserURLScheme
        let application: BrowserApplication?
        let displayName: String
        let source: CurrentBrowserSource
        let state: State
        let detailText: String

        var id: String {
            scheme.rawValue
        }
    }

    enum SuccessState: Equatable {
        case none
        case updated(browserName: String)
    }

    enum UserVisibleStatus: Equatable {
        case loading
        case idle
        case stale(message: String)
        case switching(targetName: String)
        case updated(browserName: String)
        case needsAttention(message: String)
    }

    struct StatusItemPresentation: Equatable {
        enum IconSource: Equatable {
            case browser(URL)
            case neutral
        }

        let iconSource: IconSource
        let accessibilityLabel: String
        let tooltip: String
    }

    struct AdvancedSummary: Equatable {
        let actionableCount: Int
        let nonActionableCount: Int
    }

    let currentBrowser: CurrentBrowser?
    let currentBrowserSource: CurrentBrowserSource
    let fallbackBrowser: BrowserApplication?
    let candidates: [Candidate]
    let pickerBrowsers: [Candidate]
    let switchableBrowsers: [Candidate]
    let nonActionableCandidatesWithReasons: [Candidate]
    let selectedActionableBrowserID: String?
    let successState: SuccessState
    let userVisibleStatus: UserVisibleStatus
    let currentBrowserIsActionable: Bool
    let settingsPickerPlaceholder: String
    let isPickerDisabled: Bool
    let showRefreshInMenu: Bool
    let advancedSummary: AdvancedSummary
    let statusItem: StatusItemPresentation
    let retryAvailability: BrowserDiscoveryStore.RetryAvailability
    let statusMessageText: String?
    let settingsHelperText: String
    let retryButtonTitle: String
    let retryHelpText: String
    let currentInspectionSummaryText: String
    let currentHandlerInspections: [CurrentHandlerInspection]

    init(
        snapshot: BrowserDiscoverySnapshot?,
        lastSwitchResult: BrowserSwitchResult?,
        lastCoherentBrowser: BrowserApplication?,
        preferVerifiedPostSwitch: Bool = false,
        switchPhase: BrowserDiscoveryStore.SwitchPhase,
        successState: SuccessState,
        phase: BrowserDiscoveryStore.Phase = .loaded,
        lastErrorMessage: String? = nil,
        activeSwitchTarget: BrowserSwitchTarget? = nil,
        retryAvailability: BrowserDiscoveryStore.RetryAvailability = .disabled(.noPreviousTarget),
        isEligibleSwitchTarget: (BrowserCandidate) -> Bool = { _ in true }
    ) {
        let liveCurrentBrowser = snapshot?.coherentCurrentBrowser
        let verifiedCurrentBrowser = switchPhase == .switching ? nil : lastSwitchResult?.verifiedSnapshot?.coherentCurrentBrowser

        currentBrowser = Self.resolveCurrentBrowser(
            phase: phase,
            switchPhase: switchPhase,
            liveCurrentBrowser: liveCurrentBrowser,
            verifiedCurrentBrowser: verifiedCurrentBrowser,
            lastCoherentBrowser: lastCoherentBrowser,
            preferVerifiedPostSwitch: preferVerifiedPostSwitch
        )
        currentBrowserSource = currentBrowser?.source ?? .none
        fallbackBrowser = currentBrowserSource == .staleFallback ? currentBrowser?.application : nil
        self.successState = successState
        self.retryAvailability = retryAvailability

        let currentBrowserPath = currentBrowser?.application.normalizedApplicationPath
        let allCandidates = (snapshot?.candidates ?? []).map { candidate in
            let isCurrentBrowser = candidate.normalizedApplicationPath == currentBrowserPath
            let intrinsicDisabledReason = Self.intrinsicDisabledReason(
                for: candidate,
                isEligibleSwitchTarget: isEligibleSwitchTarget
            )
            let actionState: Candidate.ActionState

            if let intrinsicDisabledReason {
                actionState = .disabled(intrinsicDisabledReason)
            } else if isCurrentBrowser {
                actionState = .currentSelection
            } else if switchPhase == .switching {
                actionState = .disabled(.switchInProgress)
            } else {
                actionState = .switchable
            }

            return Candidate(
                candidate: candidate,
                actionState: actionState,
                isCurrentBrowser: isCurrentBrowser
            )
        }

        candidates = allCandidates
        pickerBrowsers = allCandidates.filter {
            switch $0.actionState {
            case .currentSelection, .switchable, .disabled(.switchInProgress):
                true
            case .disabled:
                false
            }
        }
        switchableBrowsers = allCandidates.filter(\.isActionable)
        nonActionableCandidatesWithReasons = allCandidates.filter { !$0.isActionable }
        selectedActionableBrowserID = Self.resolveSelectedActionableBrowserID(
            from: allCandidates,
            currentBrowserSource: currentBrowserSource
        )
        currentBrowserIsActionable = selectedActionableBrowserID != nil
        settingsPickerPlaceholder = pickerBrowsers.isEmpty ? "No supported browsers found" : "Choose a browser"
        userVisibleStatus = Self.resolveUserVisibleStatus(
            phase: phase,
            switchPhase: switchPhase,
            successState: successState,
            lastSwitchResult: lastSwitchResult,
            lastErrorMessage: lastErrorMessage,
            currentBrowserSource: currentBrowserSource,
            hasDiscoveryContext: snapshot != nil || lastSwitchResult?.verifiedSnapshot != nil,
            activeSwitchTarget: activeSwitchTarget
        )
        isPickerDisabled = switchPhase == .switching || switchableBrowsers.isEmpty
        showRefreshInMenu = Self.shouldShowRefreshInMenu(for: userVisibleStatus)
        advancedSummary = AdvancedSummary(
            actionableCount: switchableBrowsers.count,
            nonActionableCount: nonActionableCandidatesWithReasons.count
        )
        statusItem = Self.resolveStatusItem(
            currentBrowser: currentBrowser,
            userVisibleStatus: userVisibleStatus
        )
        statusMessageText = Self.resolveStatusMessageText(for: userVisibleStatus)
        settingsHelperText = Self.resolveSettingsHelperText(
            statusMessageText: statusMessageText,
            currentBrowser: currentBrowser,
            currentBrowserIsActionable: currentBrowserIsActionable
        )
        retryButtonTitle = Self.resolveRetryButtonTitle(for: retryAvailability)
        retryHelpText = Self.resolveRetryHelpText(for: retryAvailability)
        currentInspectionSummaryText = Self.resolveCurrentInspectionSummaryText(
            snapshot: snapshot,
            lastSwitchResult: lastSwitchResult,
            preferVerifiedPostSwitch: preferVerifiedPostSwitch,
            phase: phase,
            currentBrowserSource: currentBrowserSource
        )
        currentHandlerInspections = Self.resolveCurrentHandlerInspections(
            snapshot: snapshot,
            lastSwitchResult: lastSwitchResult,
            preferVerifiedPostSwitch: preferVerifiedPostSwitch,
            phase: phase,
            candidates: allCandidates
        )
    }

    private static func intrinsicDisabledReason(
        for candidate: BrowserCandidate,
        isEligibleSwitchTarget: (BrowserCandidate) -> Bool
    ) -> Candidate.DisabledReason? {
        if candidate.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return .missingBundleIdentifier
        }

        if !candidate.supportsRequiredSchemes {
            return .missingRequiredSchemes
        }

        if !isEligibleSwitchTarget(candidate) {
            return .ineligibleTarget
        }

        return nil
    }

    private static func resolveCurrentBrowser(
        phase: BrowserDiscoveryStore.Phase,
        switchPhase: BrowserDiscoveryStore.SwitchPhase,
        liveCurrentBrowser: BrowserApplication?,
        verifiedCurrentBrowser: BrowserApplication?,
        lastCoherentBrowser: BrowserApplication?,
        preferVerifiedPostSwitch: Bool
    ) -> CurrentBrowser? {
        if let verifiedCurrentBrowser,
           shouldPreferVerifiedCurrentBrowser(
               switchPhase: switchPhase,
               preferVerifiedPostSwitch: preferVerifiedPostSwitch
           ) {
            return CurrentBrowser(application: verifiedCurrentBrowser, source: .verifiedPostSwitch)
        }

        if phase == .failed {
            if let fallback = staleFallbackBrowser(
                switchPhase: switchPhase,
                liveCurrentBrowser: liveCurrentBrowser,
                verifiedCurrentBrowser: verifiedCurrentBrowser,
                lastCoherentBrowser: lastCoherentBrowser,
                preferVerifiedPostSwitch: preferVerifiedPostSwitch
            ) {
                return CurrentBrowser(application: fallback, source: .staleFallback)
            }

            return nil
        }

        if let liveCurrentBrowser {
            return CurrentBrowser(application: liveCurrentBrowser, source: .liveSnapshot)
        }

        if let lastCoherentBrowser {
            return CurrentBrowser(application: lastCoherentBrowser, source: .staleFallback)
        }

        return nil
    }

    private static func staleFallbackBrowser(
        switchPhase: BrowserDiscoveryStore.SwitchPhase,
        liveCurrentBrowser: BrowserApplication?,
        verifiedCurrentBrowser: BrowserApplication?,
        lastCoherentBrowser: BrowserApplication?,
        preferVerifiedPostSwitch: Bool
    ) -> BrowserApplication? {
        if let verifiedCurrentBrowser,
           shouldPreferVerifiedCurrentBrowser(
               switchPhase: switchPhase,
               preferVerifiedPostSwitch: preferVerifiedPostSwitch
           ) {
            return verifiedCurrentBrowser
        }

        return liveCurrentBrowser ?? verifiedCurrentBrowser ?? lastCoherentBrowser
    }

    private static func shouldPreferVerifiedCurrentBrowser(
        switchPhase: BrowserDiscoveryStore.SwitchPhase,
        preferVerifiedPostSwitch: Bool
    ) -> Bool {
        guard preferVerifiedPostSwitch else {
            return false
        }

        return switchPhase != .switching
    }

    private static func resolveSelectedActionableBrowserID(
        from candidates: [Candidate],
        currentBrowserSource: CurrentBrowserSource
    ) -> String? {
        switch currentBrowserSource {
        case .liveSnapshot, .verifiedPostSwitch:
            return candidates.first(where: { $0.actionState == .currentSelection })?.candidate.id
        case .staleFallback, .none:
            return nil
        }
    }

    private static func resolveUserVisibleStatus(
        phase: BrowserDiscoveryStore.Phase,
        switchPhase: BrowserDiscoveryStore.SwitchPhase,
        successState: SuccessState,
        lastSwitchResult: BrowserSwitchResult?,
        lastErrorMessage: String?,
        currentBrowserSource: CurrentBrowserSource,
        hasDiscoveryContext: Bool,
        activeSwitchTarget: BrowserSwitchTarget?
    ) -> UserVisibleStatus {
        if phase == .refreshing {
            return .loading
        }

        if switchPhase == .switching {
            return .switching(targetName: activeSwitchTarget?.displayName ?? "Browser")
        }

        if case let .updated(browserName) = successState {
            return .updated(browserName: browserName)
        }

        if phase == .failed, currentBrowserSource != .verifiedPostSwitch {
            return .stale(message: nonEmpty(lastErrorMessage) ?? Self.defaultStaleMessage)
        }

        if switchPhase == .mixed || switchPhase == .failure {
            return .needsAttention(
                message: nonEmpty(lastSwitchResult?.visibleErrorMessage)
                    ?? nonEmpty(lastErrorMessage)
                    ?? Self.defaultNeedsAttentionMessage
            )
        }

        if currentBrowserSource == .staleFallback {
            return .needsAttention(
                message: nonEmpty(lastErrorMessage) ?? Self.defaultNeedsAttentionMessage
            )
        }

        if currentBrowserSource == .none,
           hasDiscoveryContext || lastSwitchResult != nil || nonEmpty(lastErrorMessage) != nil {
            return .needsAttention(
                message: nonEmpty(lastSwitchResult?.visibleErrorMessage)
                    ?? nonEmpty(lastErrorMessage)
                    ?? Self.defaultNeedsAttentionMessage
            )
        }

        return .idle
    }

    private static func shouldShowRefreshInMenu(for status: UserVisibleStatus) -> Bool {
        switch status {
        case .stale, .needsAttention:
            true
        case .loading, .idle, .switching, .updated:
            false
        }
    }

    private static func resolveStatusItem(
        currentBrowser: CurrentBrowser?,
        userVisibleStatus: UserVisibleStatus
    ) -> StatusItemPresentation {
        let iconSource: StatusItemPresentation.IconSource
        if let currentBrowser {
            iconSource = .browser(currentBrowser.application.applicationURL)
        } else {
            iconSource = .neutral
        }

        let accessibilityLabel: String
        let tooltip: String
        switch userVisibleStatus {
        case .idle, .updated, .switching:
            if let currentBrowser {
                accessibilityLabel = "Default browser: \(currentBrowser.application.resolvedDisplayName)"
                tooltip = accessibilityLabel
            } else {
                accessibilityLabel = "Default browser"
                tooltip = accessibilityLabel
            }
        case let .stale(message), let .needsAttention(message):
            if let currentBrowser {
                accessibilityLabel = "Default browser: \(currentBrowser.application.resolvedDisplayName)"
                tooltip = message
            } else {
                accessibilityLabel = "Default browser needs attention"
                tooltip = message
            }
        case .loading:
            accessibilityLabel = "Loading current browser"
            tooltip = accessibilityLabel
        }

        return StatusItemPresentation(
            iconSource: iconSource,
            accessibilityLabel: accessibilityLabel,
            tooltip: tooltip
        )
    }

    private static func resolveStatusMessageText(for status: UserVisibleStatus) -> String? {
        switch status {
        case .idle:
            return nil
        case .loading:
            return "Loading current browser…"
        case let .switching(targetName):
            return "Switching default browser to \(targetName)…"
        case let .updated(browserName):
            return "Default browser updated to \(browserName)."
        case let .stale(message), let .needsAttention(message):
            return message
        }
    }

    private static func resolveSettingsHelperText(
        statusMessageText: String?,
        currentBrowser: CurrentBrowser?,
        currentBrowserIsActionable: Bool
    ) -> String {
        if currentBrowser != nil, !currentBrowserIsActionable {
            return "This browser is detected, but it can’t be managed here."
        }

        return statusMessageText ?? "The app verifies the browser after switching."
    }

    private static func resolveRetryButtonTitle(for retryAvailability: BrowserDiscoveryStore.RetryAvailability) -> String {
        switch retryAvailability {
        case let .enabled(targetName):
            return "Retry \(targetName)"
        case let .disabled(reason):
            switch reason {
            case .noPreviousTarget, .missingSnapshot:
                return "Retry last browser change"
            case let .targetMissing(displayName), let .missingRequiredSchemes(targetName: displayName), let .switchInProgress(targetName: displayName):
                return "Retry \(displayName)"
            }
        }
    }

    private static func resolveRetryHelpText(for retryAvailability: BrowserDiscoveryStore.RetryAvailability) -> String {
        switch retryAvailability {
        case .enabled:
            return "Retry the last requested browser target with the current snapshot."
        case let .disabled(reason):
            switch reason {
            case .noPreviousTarget:
                return "Retry becomes available after a browser change has been attempted in this app session."
            case .missingSnapshot:
                return "Refresh browser discovery before retrying the last requested browser change."
            case let .targetMissing(displayName):
                return "\(displayName) is no longer in the current browser snapshot. Refresh or choose a different browser."
            case let .missingRequiredSchemes(targetName):
                return "\(targetName) no longer supports both HTTP and HTTPS in the current browser snapshot."
            case let .switchInProgress(targetName):
                return "Wait for the current switch to finish before retrying \(targetName)."
            }
        }
    }

    private static func resolveCurrentInspectionSummaryText(
        snapshot: BrowserDiscoverySnapshot?,
        lastSwitchResult: BrowserSwitchResult?,
        preferVerifiedPostSwitch: Bool,
        phase: BrowserDiscoveryStore.Phase,
        currentBrowserSource: CurrentBrowserSource
    ) -> String {
        if shouldUseVerifiedInspectionSnapshot(lastSwitchResult: lastSwitchResult, preferVerifiedPostSwitch: preferVerifiedPostSwitch) {
            return "Showing the verified post-switch handlers."
        }

        if snapshot != nil {
            if phase == .failed || currentBrowserSource == .staleFallback {
                return "Showing the latest discovered handlers while the current browser needs attention."
            }

            return "Showing the current system-discovered handlers."
        }

        return "No discovered browser handlers are available yet."
    }

    private static func resolveCurrentHandlerInspections(
        snapshot: BrowserDiscoverySnapshot?,
        lastSwitchResult: BrowserSwitchResult?,
        preferVerifiedPostSwitch: Bool,
        phase: BrowserDiscoveryStore.Phase,
        candidates: [Candidate]
    ) -> [CurrentHandlerInspection] {
        let (inspectionSnapshot, source) = resolveInspectionSnapshot(
            snapshot: snapshot,
            lastSwitchResult: lastSwitchResult,
            preferVerifiedPostSwitch: preferVerifiedPostSwitch,
            phase: phase
        )
        let handlersAreMixed = inspectionSnapshot?.currentHTTPHandler != nil
            && inspectionSnapshot?.currentHTTPSHandler != nil
            && inspectionSnapshot?.currentHTTPHandler?.normalizedApplicationPath != inspectionSnapshot?.currentHTTPSHandler?.normalizedApplicationPath
        let coherentPath = inspectionSnapshot?.coherentCurrentBrowser?.normalizedApplicationPath

        return BrowserURLScheme.allCases.map { scheme in
            let application = inspectionSnapshot?.currentHandler(for: scheme)
            let displayName = application?.resolvedDisplayName ?? "No default handler"
            let candidate = application.flatMap { app in
                candidates.first(where: { $0.candidate.normalizedApplicationPath == app.normalizedApplicationPath })
            }

            let state: CurrentHandlerInspection.State
            if application == nil {
                state = .missing
            } else if handlersAreMixed {
                state = .mixed
            } else if let candidate,
                      case let .disabled(reason) = candidate.actionState {
                state = .nonActionable(reason)
            } else if coherentPath == application?.normalizedApplicationPath {
                state = .currentBrowser
            } else {
                state = .currentBrowser
            }

            return CurrentHandlerInspection(
                scheme: scheme,
                application: application,
                displayName: displayName,
                source: source,
                state: state,
                detailText: resolveInspectionDetailText(
                    scheme: scheme,
                    displayName: displayName,
                    source: source,
                    state: state
                )
            )
        }
    }

    private static func resolveInspectionSnapshot(
        snapshot: BrowserDiscoverySnapshot?,
        lastSwitchResult: BrowserSwitchResult?,
        preferVerifiedPostSwitch: Bool,
        phase: BrowserDiscoveryStore.Phase
    ) -> (BrowserDiscoverySnapshot?, CurrentBrowserSource) {
        if shouldUseVerifiedInspectionSnapshot(lastSwitchResult: lastSwitchResult, preferVerifiedPostSwitch: preferVerifiedPostSwitch),
           let verifiedSnapshot = lastSwitchResult?.verifiedSnapshot {
            return (verifiedSnapshot, .verifiedPostSwitch)
        }

        if let snapshot {
            return (snapshot, phase == .failed ? .staleFallback : .liveSnapshot)
        }

        if let verifiedSnapshot = lastSwitchResult?.verifiedSnapshot {
            return (verifiedSnapshot, .verifiedPostSwitch)
        }

        return (nil, .none)
    }

    private static func shouldUseVerifiedInspectionSnapshot(
        lastSwitchResult: BrowserSwitchResult?,
        preferVerifiedPostSwitch: Bool
    ) -> Bool {
        preferVerifiedPostSwitch && lastSwitchResult?.verifiedSnapshot != nil
    }

    private static func resolveInspectionDetailText(
        scheme: BrowserURLScheme,
        displayName: String,
        source: CurrentBrowserSource,
        state: CurrentHandlerInspection.State
    ) -> String {
        let schemeLabel = scheme.rawValue.uppercased()

        switch state {
        case .missing:
            return "\(schemeLabel) default handler is unavailable."
        case .mixed:
            return "\(schemeLabel) currently resolves to \(displayName)."
        case .currentBrowser:
            if source == .verifiedPostSwitch {
                return "\(schemeLabel) verified as \(displayName)."
            }

            return "\(schemeLabel) currently resolves to \(displayName)."
        case let .nonActionable(reason):
            return "\(schemeLabel) resolves to \(displayName), but \(disabledReasonDetail(reason))."
        }
    }

    private static func disabledReasonDetail(_ reason: Candidate.DisabledReason) -> String {
        switch reason {
        case .missingBundleIdentifier:
            return "it is missing a bundle identifier"
        case .missingRequiredSchemes:
            return "it does not support both HTTP and HTTPS"
        case .ineligibleTarget:
            return "it is informational here and not offered as a switch target"
        case .switchInProgress:
            return "another browser switch is already in progress"
        }
    }

    private static let defaultStaleMessage = "Browser information may be stale."
    private static let defaultNeedsAttentionMessage = "Current default browser could not be verified."
}

protocol BrowserPresentationSuccessResetScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable
}

struct BrowserPresentationSuccessResetScheduler: BrowserPresentationSuccessResetScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let task = Task {
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await action()
        }

        return AnyCancellable {
            task.cancel()
        }
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
        return nil
    }

    return trimmedValue
}
