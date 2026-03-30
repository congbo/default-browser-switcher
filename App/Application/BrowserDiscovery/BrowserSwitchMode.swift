import Foundation

enum BrowserSwitchMode: String, Codable, CaseIterable, Identifiable {
    case launchServicesDirect
    case systemPrompt

    var id: String {
        rawValue
    }
}
