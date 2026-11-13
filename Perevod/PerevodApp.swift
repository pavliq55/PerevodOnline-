import SwiftUI
import AVFoundation

/// Приложение Tapny (альфа, рабочее название): родная оболочка вокруг переводчика perevod.molly-trade.workers.dev.
/// Страница грузится с сервера — улучшения приходят без пересборки. Родное здесь то, чего не даёт Safari:
/// вибрация, голос сразу в громкий динамик, озвучка без «разблокировки» касанием.
@main
struct PerevodApp: App {
    init() { Audio.setup() }
    var body: some Scene {
        WindowGroup {
            Root()
                // perevod://listen и perevod://conv — для «Команд» и кнопки действия через «Открыть URL»
                .onOpenURL { u in if let h = u.host, ["listen", "conv"].contains(h) { PendingAction.request(h) } }
        }
    }
}

/// Сначала согласие (один раз), потом переводчик.
struct Root: View {
    @AppStorage("consent_v1") private var agreed = false
    @StateObject private var net = Net()
    @State private var prep = false
    // только отладка: запуск с «-demoOffline YES» (снимки экрана в облачной сборке) — показать офлайн-экран
    @State private var demoOffline = UserDefaults.standard.bool(forKey: "demoOffline")
    private let preview = UserDefaults.standard.integer(forKey: "auraPreview")   // запуск с «-auraPreview N» — родной экран «Ауры»
    var body: some View {
        if preview > 0 { AuraPreview(f: .variant(preview)) }
        else if agreed {
            ZStack {
                // родной интерфейс (18.10); старый веб — запуск с «-webUI YES»
                if UserDefaults.standard.bool(forKey: "webUI") { WebScreen().ignoresSafeArea() } else { NativeRoot() }
                if !net.online || demoOffline { OfflineView().transition(.opacity) }     // связь пропала — перевод на самом айфоне
            }
            .animation(.easeInOut(duration: 0.2), value: net.online)
            .sheet(isPresented: $prep) { OfflinePrepView().presentationDetents([.medium]) }
            .onReceive(NotificationCenter.default.publisher(for: .offlinePrep)) { _ in prep = true }
        } else { ConsentView { agreed = true } }
    }
}

extension Notification.Name { static let offlinePrep = Notification.Name("offlinePrep") }

enum Audio {
    /// Запись и голос в одном режиме: микрофон включается без задержки, голос — в громкий динамик
    /// (в Safari после записи он шёл в верхний «разговорный»), наушники и AirPods тоже работают.
    /// «Куда звучит» в настройках: 0 — сам (наушники, если подключены, иначе громкий динамик), 1 — всегда громкий динамик, 2 — к уху.
    static var out = Shared.defaults.integer(forKey: "output")
    private static var forced = false
    static func setup() {
        let s = AVAudioSession.sharedInstance()
        var o: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if out != 2 { o.insert(.defaultToSpeaker) }
        try? s.setCategory(.playAndRecord, mode: .default, options: o)
        try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)   // иначе при включённом микрофоне айфон глушит всю вибрацию
        try? s.setActive(true)
        if out == 1 { if s.currentRoute.outputs.first?.portType != .builtInSpeaker { try? s.overrideOutputAudioPort(.speaker) }; forced = true }
        else if forced { try? s.overrideOutputAudioPort(.none); forced = false }
    }
}
