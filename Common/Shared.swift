import Foundation

/// Общее для приложения и расширения «Поделиться»: App Group с ключом этого айфона и языком собеседника.
enum Shared {
    /// При установке через SideStore (бесплатный Apple ID) группа получает хвост с номером команды:
    /// group.com.pavliq55.tapny.XXXXXXXXXX. Настоящее имя берём из профиля подписи внутри приложения.
    static let group: String = {
        let base = "group.com.pavliq55.tapny"
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let a = raw.range(of: Data("<?xml".utf8)),
              let b = raw.range(of: Data("</plist>".utf8), in: a.lowerBound..<raw.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: raw.subdata(in: a.lowerBound..<b.upperBound), format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String]
        else { return base }
        return groups.first { $0.hasPrefix(base) } ?? base
    }()
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
