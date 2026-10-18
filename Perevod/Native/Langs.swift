import Foundation

/// Языки собеседника — те же, что на сервере (LANGS в worker.js) и на сайте (LANG_LIST).
struct Lang: Identifiable, Hashable {
    let id: String, flag: String, native: String, ru: String, locale: String
    var title: String { ru.prefix(1).uppercased() + ru.dropFirst() }
}

enum Langs {
    static let all: [Lang] = [
        .init(id: "id", flag: "🇮🇩", native: "Indonesia", ru: "индонезийский", locale: "id-ID"),
        .init(id: "en", flag: "🇬🇧", native: "English", ru: "английский", locale: "en-US"),
        .init(id: "ar", flag: "🇸🇦", native: "العربية", ru: "арабский", locale: "ar-SA"),
        .init(id: "zh", flag: "🇨🇳", native: "中文", ru: "китайский", locale: "zh-CN"),
        .init(id: "fr", flag: "🇫🇷", native: "Français", ru: "французский", locale: "fr-FR"),
        .init(id: "es", flag: "🇪🇸", native: "Español", ru: "испанский", locale: "es-ES"),
        .init(id: "de", flag: "🇩🇪", native: "Deutsch", ru: "немецкий", locale: "de-DE"),
        .init(id: "it", flag: "🇮🇹", native: "Italiano", ru: "итальянский", locale: "it-IT"),
        .init(id: "tr", flag: "🇹🇷", native: "Türkçe", ru: "турецкий", locale: "tr-TR"),
        .init(id: "th", flag: "🇹🇭", native: "ไทย", ru: "тайский", locale: "th-TH"),
        .init(id: "vi", flag: "🇻🇳", native: "Tiếng Việt", ru: "вьетнамский", locale: "vi-VN"),
        .init(id: "ja", flag: "🇯🇵", native: "日本語", ru: "японский", locale: "ja-JP"),
        .init(id: "ko", flag: "🇰🇷", native: "한국어", ru: "корейский", locale: "ko-KR"),
        .init(id: "hi", flag: "🇮🇳", native: "हिन्दी", ru: "хинди", locale: "hi-IN"),
        .init(id: "ms", flag: "🇲🇾", native: "Melayu", ru: "малайский", locale: "ms-MY"),
        .init(id: "tl", flag: "🇵🇭", native: "Filipino", ru: "филиппинский", locale: "fil-PH"),
        .init(id: "pt", flag: "🇵🇹", native: "Português", ru: "португальский", locale: "pt-PT"),
        .init(id: "uz", flag: "🇺🇿", native: "Oʻzbekcha", ru: "узбекский", locale: "uz-UZ"),
    ]
    static func byId(_ id: String) -> Lang { all.first { $0.id == id } ?? all[0] }
    static let ru = Lang(id: "ru", flag: "🇷🇺", native: "Русский", ru: "русский", locale: "ru-RU")
}
