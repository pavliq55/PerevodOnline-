import SwiftUI
import AVFoundation

/// Приложение «Перевод»: родная оболочка вокруг переводчика perevod.molly-trade.workers.dev.
/// Страница грузится с сервера — улучшения приходят без пересборки. Родное здесь то, чего не даёт Safari:
/// вибрация, голос сразу в громкий динамик, озвучка без «разблокировки» касанием.
@main
struct PerevodApp: App {
    init() { Audio.setup() }
    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea()
        }
    }
}

enum Audio {
    /// Запись и голос в одном режиме: микрофон включается без задержки, голос — в громкий динамик
    /// (в Safari после записи он шёл в верхний «разговорный»), наушники и AirPods тоже работают.
    static func setup() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default,
                           options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
    }
}
