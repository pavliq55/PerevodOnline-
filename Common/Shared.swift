import Foundation

/// Общее для приложения и расширения «Поделиться»: App Group с ключом этого айфона и языком собеседника.
enum Shared {
    static let group = "group.com.pavliq55.tapny"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var token: String? {
        get { defaults.string(forKey: "devToken") }
        set { defaults.set(newValue, forKey: "devToken") }
    }
    static var partner: String {
        get { defaults.string(forKey: "partnerLang") ?? "id" }
        set { defaults.set(newValue, forKey: "partnerLang") }
    }
    static let base = URL(string: "https://perevod.molly-trade.workers.dev")!
}
