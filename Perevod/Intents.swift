import AppIntents
import Foundation

/// Команды для Siri, кнопки действия и «Команд»: открыть «Перевод» и сразу слушать / режим разговора.
/// Кнопка действия: Настройки → Кнопка действия → Команда → «Перевод» → «Начать перевод».
enum PendingAction {
    static let note = Notification.Name("perevodAction")
    /// Действие ждёт, пока страница переводчика будет готова (приложение могло только запускаться).
    static func request(_ a: String) {
        UserDefaults.standard.set(a, forKey: "pendingAction")
        NotificationCenter.default.post(name: note, object: a)
    }
    static func take() -> String? {
        let a = UserDefaults.standard.string(forKey: "pendingAction")
        UserDefaults.standard.removeObject(forKey: "pendingAction")
        return a
    }
}

struct StartTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "Начать перевод"
    static var description = IntentDescription("Открывает «Перевод» и сразу слушает. Ещё одно касание кнопки — конец фразы.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        PendingAction.request("listen")
        return .result()
    }
}

struct ConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Режим разговора"
    static var description = IntentDescription("Открывает экран на двоих: верхняя половина — для собеседника.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        PendingAction.request("conv")
        return .result()
    }
}

struct PerevodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTranslateIntent(),
                    phrases: ["Переведи в \(.applicationName)", "Начать \(.applicationName)", "Включи \(.applicationName)", "\(.applicationName)"],
                    shortTitle: "Перевести", systemImageName: "mic.fill")
        AppShortcut(intent: ConversationIntent(),
                    phrases: ["Разговор в \(.applicationName)", "Режим разговора в \(.applicationName)"],
                    shortTitle: "Разговор", systemImageName: "person.2.fill")
    }
}
