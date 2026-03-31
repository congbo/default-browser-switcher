import AppKit
import SwiftUI

@main
struct DefaultBrowserSwitcherApp: App {
    static let menuBarTitle = "Default Browser Switcher"
    static let settingsTitle = "Settings"
    static let settingsWindowIdentifier = "DefaultBrowserSwitcher.settingsWindow"
    static let launchSwitchTargetPathEnvironmentKey = "DEFAULT_BROWSER_SWITCHER_SWITCH_TARGET_PATH"

    @StateObject private var store: BrowserDiscoveryStore
    @StateObject private var iconProvider: BrowserIconProvider
    @StateObject private var launchAtLoginService: LaunchAtLoginService
    @StateObject private var switchSettings: BrowserSwitchSettings

    private let launchSwitchTargetPath: String?
    private let usesAutomationShell: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        let switchSettings = BrowserSwitchSettings()
        let systemService = SystemBrowserDiscoveryService(environment: environment)
        let launchServicesDirectService = LaunchServicesDirectBrowserDiscoveryService(environment: environment)
        let store = BrowserDiscoveryStore(
            service: SwitchModeBrowserDiscoveryService(
                snapshotService: systemService,
                launchServicesDirectService: launchServicesDirectService,
                systemPromptService: systemService,
                settings: switchSettings
            ),
            environment: environment
        )
        let requestedLaunchSwitchTargetPath = Self.requestedLaunchSwitchTargetPath(from: environment)
        _store = StateObject(wrappedValue: store)
        _iconProvider = StateObject(wrappedValue: BrowserIconProvider.shared)
        _launchAtLoginService = StateObject(wrappedValue: LaunchAtLoginService())
        _switchSettings = StateObject(wrappedValue: switchSettings)
        launchSwitchTargetPath = requestedLaunchSwitchTargetPath
        usesAutomationShell = requestedLaunchSwitchTargetPath != nil || Self.requestedSnapshotOutputPath(from: environment) != nil

        Task { @MainActor in
            await store.bootstrapIfNeeded()

            if let requestedLaunchSwitchTargetPath {
                _ = await store.switchToBrowser(matchingNormalizedApplicationPath: requestedLaunchSwitchTargetPath)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(iconProvider)
        } label: {
            StatusItemLabel(
                presentation: store.presentation,
                usesAutomationShell: usesAutomationShell
            )
            .environmentObject(iconProvider)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(iconProvider)
                .environmentObject(launchAtLoginService)
                .environmentObject(switchSettings)
        }
    }

    private static func requestedLaunchSwitchTargetPath(from environment: [String: String]) -> String? {
        guard let rawValue = environment[launchSwitchTargetPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: rawValue).standardizedFileURL.path
    }

    private static func requestedSnapshotOutputPath(from environment: [String: String]) -> String? {
        guard let rawValue = environment["DEFAULT_BROWSER_SWITCHER_SNAPSHOT_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return nil
        }

        return rawValue
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let windowIdentifier = NSUserInterfaceItemIdentifier(DefaultBrowserSwitcherApp.settingsWindowIdentifier)
    private let activateApplication: (Bool) -> Void
    private weak var settingsWindow: NSWindow?

    init(
        activateApplication: @escaping (Bool) -> Void = { ignoresOtherApps in
            NSApp.activate(ignoringOtherApps: ignoresOtherApps)
        }
    ) {
        self.activateApplication = activateApplication
    }

    @discardableResult
    func register(window: NSWindow) -> Bool {
        let isNewWindow = settingsWindow !== window
        settingsWindow = window
        configure(window, isNewWindow: isNewWindow)
        return isNewWindow
    }

    func activate(window: NSWindow) {
        bringToFront(window)
    }

    private func configure(_ window: NSWindow, isNewWindow: Bool = false) {
        window.identifier = windowIdentifier
        window.tabbingMode = .disallowed
        window.minSize = NSSize(
            width: SettingsLayoutMetrics.minWindowWidth,
            height: SettingsLayoutMetrics.minWindowHeight
        )

        if isNewWindow {
            window.setContentSize(
                NSSize(
                    width: SettingsLayoutMetrics.minWindowWidth,
                    height: SettingsLayoutMetrics.minWindowHeight
                )
            )
        }
    }

    private func bringToFront(_ window: NSWindow) {
        configure(window)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        activateApplication(true)
    }
}

private struct StatusItemLabel: View {
    @EnvironmentObject private var iconProvider: BrowserIconProvider

    let presentation: BrowserPresentation
    let usesAutomationShell: Bool

    var body: some View {
        Group {
            if usesAutomationShell {
                Image(systemName: "globe")
            } else {
                switch presentation.statusItem.iconSource {
                case let .browser(applicationURL):
                    BrowserAppIconView(
                        image: iconProvider.icon(for: applicationURL, size: 18),
                        size: 18,
                        cornerRadius: 4
                    )
                case .neutral:
                    BrowserAppIconView(
                        image: iconProvider.neutralIcon(size: 18),
                        size: 18,
                        cornerRadius: 4
                    )
                }
            }
        }
        .accessibilityLabel(Text(verbatim: presentation.statusItem.accessibilityLabel))
        .help(presentation.statusItem.tooltip)
    }
}
