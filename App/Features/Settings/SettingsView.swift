import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Layout {
        static let controlColumnWidth: CGFloat = 220
    }

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
        .frame(minWidth: 600, minHeight: 460)
        .background(SettingsWindowObserver())
        .task {
            await store.bootstrapIfNeeded()
            await launchAtLoginService.bootstrapIfNeeded()
        }
    }

    private var browserSection: some View {
        Section {
            LabeledContent(String(localized: "settings.defaultBrowser")) {
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
            Toggle(isOn: launchAtLoginBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.launchAtLogin.section"))

                    Text(verbatim: launchAtLoginStatusText)
                        .font(.callout)
                        .foregroundStyle(launchAtLoginService.model.needsAttention ? .orange : .secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!launchAtLoginService.model.canToggle)

            if shouldShowLaunchAtLoginRefreshAction {
                HStack {
                    Spacer()

                    Button(launchAtLoginRefreshTitle) {
                        Task {
                            await launchAtLoginService.refresh()
                        }
                    }
                    .disabled(launchAtLoginService.model.isRefreshing || launchAtLoginService.model.isApplyingChange)
                }
            }

            if let errorMessage = launchAtLoginService.model.errorMessage, !errorMessage.isEmpty {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var refreshSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.refresh.section"))

                    Text(String(localized: "settings.refresh.description"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(String(localized: "settings.refresh")) {
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
                Text(String(localized: "settings.logs.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reversedLogEntries) { entry in
                    logRow(for: entry)
                }
            }
        } header: {
            Text(String(localized: "settings.logs"))
        }
    }

    private var switchModeSection: some View {
        Section {
            LabeledContent(String(localized: "settings.switchMode.label")) {
                Picker(String(localized: "settings.switchMode.label"), selection: switchModeBinding) {
                    ForEach(BrowserSwitchMode.allCases) { mode in
                        Text(verbatim: title(for: mode))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: Layout.controlColumnWidth, alignment: .trailing)
            }
        } header: {
            Text(String(localized: "settings.switchMode.section"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.switchMode.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(verbatim: detail(for: switchSettings.switchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: Layout.controlColumnWidth, alignment: .trailing)
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
            return String(localized: "settings.switchMode.option.launchServicesDirect")
        case .systemPrompt:
            return String(localized: "settings.switchMode.option.systemPrompt")
        }
    }

    private func detail(for mode: BrowserSwitchMode) -> String {
        switch mode {
        case .launchServicesDirect:
            return String(localized: "settings.switchMode.detail.launchServicesDirect")
        case .systemPrompt:
            return String(localized: "settings.switchMode.detail.systemPrompt")
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

    private var shouldShowLaunchAtLoginRefreshAction: Bool {
        launchAtLoginService.model.needsAttention
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
            return String(localized: "settings.logs.level.info")
        case .warning:
            return String(localized: "settings.logs.level.warning")
        case .error:
            return String(localized: "settings.logs.level.error")
        }
    }

    private func logStageTitle(for stage: BrowserSwitchLogEntry.Stage) -> String {
        switch stage {
        case .refresh:
            return String(localized: "settings.logs.stage.refresh")
        case .switching:
            return String(localized: "settings.logs.stage.switch")
        case .verification:
            return String(localized: "settings.logs.stage.verification")
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
