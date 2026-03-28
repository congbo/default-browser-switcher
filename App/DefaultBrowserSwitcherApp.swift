import SwiftUI

@main
struct DefaultBrowserSwitcherApp: App {
    static let menuBarTitle = "Default Browser Switcher"
    static let settingsTitle = "Settings"
    static let launchSwitchTargetPathEnvironmentKey = "DEFAULT_BROWSER_SWITCHER_SWITCH_TARGET_PATH"

    @StateObject private var store: BrowserDiscoveryStore
    @StateObject private var iconProvider: BrowserIconProvider
    @StateObject private var launchAtLoginService: LaunchAtLoginService

    private let launchSwitchTargetPath: String?
    private let usesAutomationShell: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        let store = BrowserDiscoveryStore(
            service: SystemBrowserDiscoveryService(environment: environment),
            environment: environment
        )
        let requestedLaunchSwitchTargetPath = Self.requestedLaunchSwitchTargetPath(from: environment)
        _store = StateObject(wrappedValue: store)
        _iconProvider = StateObject(wrappedValue: BrowserIconProvider.shared)
        _launchAtLoginService = StateObject(wrappedValue: LaunchAtLoginService())
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

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(iconProvider)
                .environmentObject(launchAtLoginService)
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
                    Image(nsImage: iconProvider.icon(for: applicationURL))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                case .neutral:
                    Image(nsImage: iconProvider.neutralIcon())
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
        }
        .accessibilityLabel(Text(verbatim: presentation.statusItem.accessibilityLabel))
        .help(presentation.statusItem.tooltip)
    }
}
