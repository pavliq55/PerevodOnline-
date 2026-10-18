import SwiftUI

/// Шрифты и цвета «Ауры»: SF Pro Expanded — крупный перевод и логотип, SF Pro — остальное (выбор Павла, №2).
enum T {
    static let ink = Color(red: 0.09, green: 0.086, blue: 0.11)
    static let dim = Color(red: 0.42, green: 0.41, blue: 0.46)
    static let me = Color(red: 1, green: 0.66, blue: 0.24)
    static let they = Color(red: 0.8, green: 0.55, blue: 0.85)
    static func big(_ n: Int) -> Font {                 // крупный перевод: короче — крупнее
        .system(size: n < 30 ? 34 : n < 70 ? 29 : n < 140 ? 24 : 20, weight: .semibold).width(.expanded)
    }
    static let mark = Font.system(size: 21, weight: .bold).width(.expanded)
    static let text = Font.system(size: 18, weight: .medium)
    static let small = Font.system(size: 14)
    static let label = Font.system(size: 13, weight: .medium)
    static let ui = Font.system(size: 15, weight: .medium)
    static let live = Font.system(size: 30, weight: .semibold).width(.expanded)
}
