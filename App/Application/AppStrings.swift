enum AppStrings {
    enum Menu {
        static let refresh = "Refresh"
        static let settings = "Settings..."
        static let quit = "Quit"
    }

    enum Settings {
        static let defaultBrowser = "Default web browser"
        static let launchAtLoginSection = "Launch at login"
        static let refreshSection = "Browser discovery"
        static let refreshDescription = "Re-read the current default browser and available browser list from the latest system discovery result."
        static let refresh = "Refresh browser discovery"
        static let logs = "Logs"
        static let logsEmpty = "No browser switch logs yet in this app session."
        static let switchModeLabel = "Switch implementation"
        static let switchModeSection = "Switch mode"
        static let switchModeDescription = "Choose how Default Browser Switcher updates the system default browser."
    }

    enum SwitchMode {
        static let launchServicesDirect = "LaunchServices Direct"
        static let systemPrompt = "System Prompt"
        static let launchServicesDirectDetail = "LaunchServices Direct rewrites the user browser handlers first. It is usually faster and avoids the confirmation dialog, but it is a lower-level compatibility path."
        static let systemPromptDetail = "System Prompt uses the official macOS API. It is the most conservative path, but macOS may ask you to confirm the browser change."
    }

    enum LaunchAtLogin {
        static let loading = "Checking login item status..."
        static let enabled = "Opens automatically when you sign in."
        static let disabled = "Off until you open the app yourself."
        static let unavailable = "This Mac can't enable launch at login right now."
        static let approvalRequired = "Allow this app in System Settings before it can launch at login."
        static let refresh = "Refresh launch-at-login status"
        static let retry = "Retry launch-at-login check"
    }

    enum Logs {
        static let info = "Info"
        static let warning = "Warning"
        static let error = "Error"
        static let refresh = "Refresh"
        static let switching = "Switch"
        static let verification = "Verification"
    }

    enum Verification {
        static let optimisticUnconfirmed = "The browser switch was submitted, but verification has not caught up yet."
    }
}
