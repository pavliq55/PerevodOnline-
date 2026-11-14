import AppIntents

/// Фразы для Siri (только в приложении; сами команды — Common/Intents.swift).
struct PerevodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTranslateIntent(),
                    phrases: ["Переведи в \(.applicationName)", "Начать \(.applicationName)", "Включи \(.applicationName)", "\(.applicationName)"],
                    shortTitle: "Перевести", systemImageName: "mic.fill")
        AppShortcut(intent: SayIntent(),
                    phrases: ["Скажи через \(.applicationName)", "Скажи в \(.applicationName)", "Сказать через \(.applicationName)", "\(.applicationName) скажи"],
                    shortTitle: "Сказать фразу", systemImageName: "speaker.wave.2.fill")
        AppShortcut(intent: ConversationIntent(),
                    phrases: ["Разговор в \(.applicationName)", "Режим разговора в \(.applicationName)"],
                    shortTitle: "Разговор", systemImageName: "person.2.fill")
    }
}
