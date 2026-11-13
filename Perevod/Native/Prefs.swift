import SwiftUI
import UIKit

/// Строка «Моих слов»: слово и как его переводить.
struct Word: Identifiable, Codable, Equatable {
    var id = UUID()
    var a = ""                 // слово, как его говорят
    var b = ""                 // как переводить; пусто — оставить как есть
}

/// Настройки на этом айфоне — в общем хранилище приложения.
enum Pref {
    static func bool(_ k: String, _ d: Bool) -> Bool { Shared.defaults.object(forKey: k) as? Bool ?? d }
    static func int(_ k: String, _ d: Int) -> Int { Shared.defaults.object(forKey: k) as? Int ?? d }
    static func set(_ v: Any, _ k: String) { Shared.defaults.set(v, forKey: k) }
    static var words: [Word] {
        get { Shared.defaults.data(forKey: "words").flatMap { try? JSONDecoder().decode([Word].self, from: $0) } ?? [] }
        set { if let d = try? JSONEncoder().encode(newValue) { Shared.defaults.set(d, forKey: "words") } }
    }
}

/// Вибрация — в одном месте: её можно выключить в настройках.
@MainActor enum Hap {
    static var on = true
    static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle = .medium) { if on { UIImpactFeedbackGenerator(style: s).impactOccurred() } }
    static func note(_ t: UINotificationFeedbackGenerator.FeedbackType) { if on { UINotificationFeedbackGenerator().notificationOccurred(t) } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
}

/// Тема: как в айфоне / светлая / тёмная — сразу для всех окон и шторок приложения.
@MainActor enum Look {
    static func apply(_ t: Int) {
        let st: UIUserInterfaceStyle = t == 1 ? .light : t == 2 ? .dark : .unspecified
        for sc in UIApplication.shared.connectedScenes {
            guard let ws = sc as? UIWindowScene else { continue }
            for w in ws.windows where w.overrideUserInterfaceStyle != st { w.overrideUserInterfaceStyle = st }
        }
    }
}
