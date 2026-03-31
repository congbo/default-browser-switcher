import AppKit
import SwiftUI

enum SettingsLayoutMetrics {
    static let minWindowWidth: CGFloat = 520
    static let minWindowHeight: CGFloat = 460
    static let controlColumnWidth: CGFloat = 190
}

struct SettingsView: View {
    @EnvironmentObject private var store: BrowserDiscoveryStore
    @EnvironmentObject private var iconProvider: BrowserIconProvider
    @EnvironmentObject private var launchAtLoginService: LaunchAtLoginService
    @EnvironmentObject private var switchSettings: BrowserSwitchSettings

    private var presentation: BrowserPresentation {
        store.presentation
    }

    var body: some View {
        Form {
            browserSection
            launchAtLoginSection
            refreshSection
            switchModeSection
            logsSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(
            minWidth: SettingsLayoutMetrics.minWindowWidth,
            minHeight: SettingsLayoutMetrics.minWindowHeight
        )
        .background(SettingsWindowObserver())
        .task {
            await store.bootstrapIfNeeded()
            await launchAtLoginService.bootstrapIfNeeded()
        }
    }

    private var browserSection: some View {
        Section {
            LabeledContent(AppStrings.Settings.defaultBrowser) {
                browserPicker
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: presentation.settingsHelperText)
                    .font(.callout)

                if shouldShowCurrentInspectionSummary {
                    Text(verbatim: presentation.currentInspectionSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var launchAtLoginSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(AppStrings.Settings.launchAtLoginSection) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(!launchAtLoginService.model.canToggle)
                }

                Text(verbatim: launchAtLoginDetailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var refreshSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.Settings.refreshSection)

                    Text(AppStrings.Settings.refreshDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(AppStrings.Settings.refresh) {
                    Task {
                        await store.refresh()
                    }
                }
                .disabled(store.phase == .refreshing || store.switchPhase == .switching)
            }
        }
    }

    private var logsSection: some View {
        Section {
            if reversedLogEntries.isEmpty {
                Text(AppStrings.Settings.logsEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reversedLogEntries) { entry in
                    logRow(for: entry)
                }
        }
        } header: {
            Text(AppStrings.Settings.logs)
        }
    }

    private var switchModeSection: some View {
        Section {
            LabeledContent(AppStrings.Settings.switchModeLabel) {
                Picker(AppStrings.Settings.switchModeLabel, selection: switchModeBinding) {
                    ForEach(BrowserSwitchMode.allCases) { mode in
                        Text(verbatim: title(for: mode))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
            }
        } header: {
            Text(AppStrings.Settings.switchModeSection)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Settings.switchModeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(verbatim: detail(for: switchSettings.switchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var browserPicker: some View {
        Picker(AppStrings.Settings.defaultBrowser, selection: pickerSelection) {
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
        .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
        .disabled(presentation.isPickerDisabled)
    }

    private var shouldShowCurrentInspectionSummary: Bool {
        !presentation.currentInspectionSummaryText.isEmpty
            && (presentation.currentBrowser == nil || !presentation.currentBrowserIsActionable)
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

    private var switchModeBinding: Binding<BrowserSwitchMode> {
        Binding(
            get: { switchSettings.switchMode },
            set: { switchSettings.switchMode = $0 }
        )
    }

    private func title(for mode: BrowserSwitchMode) -> String {
        switch mode {
        case .launchServicesDirect:
            return AppStrings.SwitchMode.launchServicesDirect
        case .systemPrompt:
            return AppStrings.SwitchMode.systemPrompt
        }
    }

    private func detail(for mode: BrowserSwitchMode) -> String {
        switch mode {
        case .launchServicesDirect:
            return AppStrings.SwitchMode.launchServicesDirectDetail
        case .systemPrompt:
            return AppStrings.SwitchMode.systemPromptDetail
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

    private var launchAtLoginDetailText: String {
        if let errorMessage = launchAtLoginService.model.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        if launchAtLoginService.model.isLoading || launchAtLoginService.model.isRefreshing {
            return AppStrings.LaunchAtLogin.loading
        }

        switch launchAtLoginService.model.detailState {
        case .enabled?:
            return AppStrings.LaunchAtLogin.enabled
        case .neutral?:
            return AppStrings.LaunchAtLogin.neutral
        case .disabled?:
            return AppStrings.LaunchAtLogin.disabled
        case .approvalRequired?:
            return AppStrings.LaunchAtLogin.approvalRequired
        case nil:
            return AppStrings.LaunchAtLogin.loading
        }
    }

    private var reversedLogEntries: [BrowserSwitchLogEntry] {
        Array(store.logEntries.reversed())
    }

    private func logRow(for entry: BrowserSwitchLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(verbatim: logLevelTitle(for: entry.level))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(logLevelColor(for: entry.level))

                Text(verbatim: logStageTitle(for: entry.stage))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let targetDisplayName = entry.targetDisplayName, !targetDisplayName.isEmpty {
                    Text(verbatim: targetDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(verbatim: entry.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func logLevelTitle(for level: BrowserSwitchLogEntry.Level) -> String {
        switch level {
        case .info:
            return AppStrings.Logs.info
        case .warning:
            return AppStrings.Logs.warning
        case .error:
            return AppStrings.Logs.error
        }
    }

    private func logStageTitle(for stage: BrowserSwitchLogEntry.Stage) -> String {
        switch stage {
        case .refresh:
            return AppStrings.Logs.refresh
        case .switching:
            return AppStrings.Logs.switching
        case .verification:
            return AppStrings.Logs.verification
        }
    }

    private func logLevelColor(for level: BrowserSwitchLogEntry.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct SettingsWindowObserver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            registerWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            registerWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    private func registerWindow(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else {
            DispatchQueue.main.async {
                registerWindow(from: view, coordinator: coordinator)
            }
            return
        }

        _ = SettingsWindowController.shared.register(window: window)

        if coordinator.lastActivatedWindow !== window {
            coordinator.lastActivatedWindow = window
            SettingsWindowController.shared.activate(window: window)
        }
    }

    final class Coordinator {
        weak var lastActivatedWindow: NSWindow?
    }
}
