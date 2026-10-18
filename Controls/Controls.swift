import WidgetKit
import SwiftUI
import AppIntents

/// Кнопки в Пункте управления, на экране блокировки и для кнопки действия (iOS 18+).
@main
struct TapnyControls: WidgetBundle {
    var body: some Widget {
        StartControl()
        ConversationControl()
    }
}

struct StartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.pavliq55.tapny.start") {
            ControlWidgetButton(action: StartTranslateIntent()) {
                Label("Перевести", systemImage: "waveform")
            }
        }
        .displayName("Tapny: перевести")
        .description("Открыть Tapny и сразу слушать.")
    }
}

struct ConversationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.pavliq55.tapny.conv") {
            ControlWidgetButton(action: ConversationIntent()) {
                Label("Разговор", systemImage: "person.2.wave.2")
            }
        }
        .displayName("Tapny: разговор")
        .description("Экран на двоих для собеседника.")
    }
}
