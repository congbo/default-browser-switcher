import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: BrowserDiscoveryStore
    @EnvironmentObject private var iconProvider: BrowserIconProvider
    @EnvironmentObject private var launchAtLoginService: LaunchAtLoginService

    private var presentation: BrowserPresentation {
        store.presentation
    }

    var body: some View {
        Form {
            Section(DefaultBrowserSwitcherApp.settingsTitle) {
                LabeledContent(String(localized: "settings.defaultBrowser")) {
                    HStack(spacing: 12) {
                        currentBrowserSummary
                        browserPicker
                    }
                }

                Text(verbatim: presentation.settingsHelperText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                actionRow
            }

            launchAtLoginSection

            DisclosureGroup(String(localized: "settings.advanced")) {
                currentHandlersSection
                retrySection
                advancedVerificationSection
                advancedNonActionableSection
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
        .task {
            await store.bootstrapIfNeeded()
            await launchAtLoginService.bootstrapIfNeeded()
        }
    }

    private var currentBrowserSummary: some View {
        Group {
            if let currentBrowser = presentation.currentBrowser {
                HStack(spacing: 8) {
                    Image(nsImage: iconProvider.icon(for: currentBrowser.application))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: currentBrowser.application.resolvedDisplayName)
                            .lineLimit(1)
                        Text(verbatim: presentation.currentInspectionSummaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.settingsPickerPlaceholder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: presentation.currentInspectionSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var browserPicker: some View {
        Picker(String(localized: "settings.defaultBrowser"), selection: pickerSelection) {
            if presentation.selectedActionableBrowserID == nil {
                Text(verbatim: presentation.settingsPickerPlaceholder)
                    .tag(Optional<String>.none)
            }

            ForEach(presentation.pickerBrowsers) { row in
                HStack(spacing: 8) {
                    Image(nsImage: iconProvider.icon(for: row.candidate))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(.rect(cornerRadius: 4))
                    Text(verbatim: row.candidate.resolvedDisplayName)
                }
                .tag(Optional(row.candidate.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 200)
        .disabled(presentation.isPickerDisabled)
    }

    private var pickerSelection: Binding<String?> {
        Binding(
            get: { presentation.selectedActionableBrowserID },
            set: { newValue in
                guard let newValue,
                      let candidate = presentation.switchableBrowsers.first(where: { $0.candidate.id == newValue })?.candidate
                else {
                    return
                }

                Task {
                    await store.switchToBrowser(candidate)
                }
            }
        )
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(String(localized: "settings.advanced.refresh")) {
                Task {
                    await store.refresh()
                }
            }
            .disabled(store.phase == .refreshing || store.switchPhase == .switching)

            Button(presentation.retryButtonTitle) {
                Task {
                    await store.retryLastSwitchTarget()
                }
            }
            .disabled(!isRetryEnabled)

            Spacer(minLength: 0)
        }
    }

    private var isRetryEnabled: Bool {
        if case .enabled = presentation.retryAvailability {
            return true
        }

        return false
    }

    private var currentHandlersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.currentHandlers"))
                .font(.subheadline.weight(.semibold))

            Text(verbatim: presentation.currentInspectionSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(presentation.currentHandlerInspections) { row in
                LabeledContent(row.scheme.rawValue.uppercased()) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: row.displayName)
                            .fontWeight(row.state == .currentBrowser ? .semibold : .regular)
                        Text(verbatim: row.detailText)
                            .font(.caption)
                            .foregroundStyle(detailColor(for: row))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func detailColor(for row: BrowserPresentation.CurrentHandlerInspection) -> Color {
        switch row.state {
        case .currentBrowser:
            return .secondary
        case .mixed, .missing, .nonActionable:
            return .orange
        }
    }

    private var retrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Retry")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Button(presentation.retryButtonTitle) {
                    Task {
                        await store.retryLastSwitchTarget()
                    }
                }
                .disabled(!isRetryEnabled)

                Text(verbatim: presentation.retryHelpText)
                    .font(.caption)
                    .foregroundStyle(isRetryEnabled ? Color.secondary : Color.orange)
            }
        }
    }

    private var launchAtLoginSection: some View {
        Section(String(localized: "settings.launchAtLogin.section")) {
            Toggle(String(localized: "settings.launchAtLogin.toggle"), isOn: launchAtLoginBinding)
                .disabled(!launchAtLoginService.model.canToggle)

            Text(verbatim: launchAtLoginStatusText)
                .font(.callout)
                .foregroundStyle(launchAtLoginService.model.needsAttention ? .orange : .secondary)

            if let errorMessage = launchAtLoginService.model.errorMessage, !errorMessage.isEmpty {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(launchAtLoginRefreshTitle) {
                Task {
                    await launchAtLoginService.refresh()
                }
            }
            .disabled(launchAtLoginService.model.isRefreshing || launchAtLoginService.model.isApplyingChange)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginService.model.isToggleOn },
            set: { newValue in
                Task {
                    await launchAtLoginService.setEnabled(newValue)
                }
            }
        )
    }

    private var launchAtLoginStatusText: String {
        if launchAtLoginService.model.isLoading || launchAtLoginService.model.isRefreshing {
            return String(localized: "settings.launchAtLogin.loading")
        }

        switch launchAtLoginService.model.resolvedStatus {
        case .enabled?:
            return String(localized: "settings.launchAtLogin.enabled")
        case .disabled?:
            return String(localized: "settings.launchAtLogin.disabled")
        case .unavailable?:
            return String(localized: "settings.launchAtLogin.unavailable")
        case .approvalRequired?:
            return String(localized: "settings.launchAtLogin.approvalRequired")
        case nil:
            return String(localized: "settings.launchAtLogin.loading")
        }
    }

    private var launchAtLoginRefreshTitle: String {
        String(localized: launchAtLoginService.model.canRetry ? "settings.launchAtLogin.retry" : "settings.launchAtLogin.refresh")
    }

    private var advancedVerificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.advanced.verification"))
                .font(.subheadline.weight(.semibold))

            if let result = store.lastSwitchResult {
                LabeledContent(String(localized: "settings.switch.target")) {
                    Text(verbatim: result.requestedTarget.displayName)
                }

                LabeledContent(String(localized: "settings.switch.completedAt")) {
                    Text(verbatim: Self.timestampFormatter.string(from: result.completedAt))
                }

                ForEach(result.schemeOutcomes, id: \.scheme) { outcome in
                    let outcomeText = schemeOutcomeText(outcome)
                    let outcomeColor: Color = (outcome.status == .success || outcome.status == .skipped) ? .secondary : .orange

                    return LabeledContent(outcome.scheme.rawValue.uppercased()) {
                        Text(verbatim: outcomeText)
                            .foregroundStyle(outcomeColor)
                    }
                }

                if let visibleErrorMessage = result.visibleErrorMessage, !visibleErrorMessage.isEmpty {
                    Text(verbatim: visibleErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(String(localized: "settings.advanced.noVerification"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func schemeOutcomeText(_ outcome: BrowserSwitchSchemeOutcome) -> String {
        switch outcome.status {
        case .success:
            return "Verified"
        case .skipped:
            return "Already current"
        case .failure, .timedOut:
            return outcome.errorMessage ?? "Needs attention"
        }
    }

    private var advancedNonActionableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.advanced.otherApps"))
                .font(.subheadline.weight(.semibold))

            if presentation.candidates.isEmpty {
                Text(String(localized: "settings.advanced.otherApps.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.candidates) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(nsImage: iconProvider.icon(for: row.candidate))
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(.rect(cornerRadius: 4))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.candidate.resolvedDisplayName)
                            Text(verbatim: reasonText(for: row))
                                .font(.caption)
                                .foregroundStyle(row.isActionable ? .secondary : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func reasonText(for row: BrowserPresentation.Candidate) -> String {
        switch row.actionState {
        case .currentSelection:
            return String(localized: "settings.advanced.reason.current")
        case .switchable:
            return String(localized: "settings.advanced.reason.switchable")
        case let .disabled(reason):
            switch reason {
            case .missingBundleIdentifier:
                return String(localized: "settings.advanced.reason.bundle")
            case .missingRequiredSchemes:
                return String(localized: "settings.advanced.reason.schemes")
            case .ineligibleTarget:
                return String(localized: "settings.advanced.reason.ineligible")
            case .switchInProgress:
                return String(localized: "settings.advanced.reason.pending")
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
