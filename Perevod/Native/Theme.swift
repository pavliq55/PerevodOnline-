import SwiftUI
import UIKit

extension Color {
    /// Цвет под оформление айфона: первый — для светлого, второй — для тёмного. Меняется сам, без перезапуска.
    static func dyn(_ l: (Double, Double, Double), _ d: (Double, Double, Double), la: Double = 1, da: Double = 1) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: d.0, green: d.1, blue: d.2, alpha: da)
                                                               : UIColor(red: l.0, green: l.1, blue: l.2, alpha: la) })
    }
}

/// Шрифты и цвета «Ауры»: SF Pro Expanded — крупный перевод и логотип, SF Pro — остальное (выбор Павла, №2).
enum T {
    // Две темы (13.11.2026, с дизайнером): светлая — как была, тёмная — почти чёрная основа с приглушённым светом.
    // Не чистые чёрный и белый: на OLED чёрный «тянется» при прокрутке, а белый ночью слепит.
    static let base = Color.dyn((0.99, 0.985, 0.99), (0.039, 0.035, 0.063))
    static let ink = Color.dyn((0.09, 0.086, 0.11), (0.96, 0.95, 0.98))
    static let dim = Color.dyn((0.32, 0.31, 0.37), (0.72, 0.70, 0.79))      // светлый стал темнее: прежний терялся на ярких пятнах
    static let me = Color.dyn((0.90, 0.45, 0.08), (1, 0.72, 0.30))          // точки и галочки: в светлой темнее, чтобы были видны на белом
    static let they = Color.dyn((0.62, 0.36, 0.78), (0.82, 0.66, 1))
    static let err = Color.dyn((0.70, 0.06, 0.12), (1, 0.52, 0.48))
    static let field = Color.dyn((0, 0, 0), (1, 1, 1), la: 0.05, da: 0.08)  // поле ввода
    static let speakTint = Color.dyn((1, 0.6, 0.4), (1, 0.55, 0.38), la: 0.35, da: 0.28)   // стекло кнопки «Озвучить»
    static let goTint = Color.dyn((1, 0.66, 0.24), (1, 0.66, 0.24), la: 0.42, da: 0.32)    // стекло «Перевести», «Войти»
    // «облака» реплик: полупрозрачные, мои — тёплые справа, собеседника — холодные слева
    static let bubbleMe = Color.dyn((1, 0.72, 0.35), (1, 0.62, 0.30), la: 0.24, da: 0.17)
    static let bubbleThey = Color.dyn((1, 1, 1), (0.75, 0.66, 1), la: 0.45, da: 0.11)
    static let bubbleLine = Color.dyn((1, 1, 1), (1, 1, 1), la: 0.65, da: 0.14)
    static let onWarm = Color(red: 0.16, green: 0.09, blue: 0.05)           // текст на тёплой плотной кнопке — в обеих темах
    static let warm = LinearGradient(colors: [Color(red: 1, green: 0.79, blue: 0.24), Color(red: 1, green: 0.58, blue: 0.4)], startPoint: .leading, endPoint: .trailing)
    static func big(_ n: Int) -> Font {                 // крупный перевод: короче — крупнее
        .system(size: n < 30 ? 34 : n < 70 ? 29 : n < 140 ? 24 : 20, weight: .semibold).width(.expanded)
    }
    static let mark = Font.system(size: 21, weight: .bold).width(.expanded)
    static let text = Font.system(size: 18, weight: .medium)
    static let small = Font.system(size: 14)
    static let label = Font.system(size: 13, weight: .medium)
    static let ui = Font.system(size: 15, weight: .medium)
    static let live = Font.system(size: 26, weight: .semibold).width(.expanded)
}
