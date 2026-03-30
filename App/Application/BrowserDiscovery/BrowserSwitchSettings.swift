import Combine
import Foundation

final class BrowserSwitchSettings: ObservableObject {
    private enum Keys {
        static let switchMode = "browserSwitchMode"
    }

    private let userDefaults: UserDefaults

    @Published var switchMode: BrowserSwitchMode {
        didSet {
            guard switchMode != oldValue else {
                return
            }

            userDefaults.set(switchMode.rawValue, forKey: Keys.switchMode)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let rawValue = userDefaults.string(forKey: Keys.switchMode),
           let persistedMode = BrowserSwitchMode(rawValue: rawValue) {
            switchMode = persistedMode
        } else {
            switchMode = .launchServicesDirect
        }
    }
}
