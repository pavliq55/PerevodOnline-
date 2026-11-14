import SwiftUI
import AVFoundation

/// Приложение Tapny (альфа, рабочее название): родная оболочка вокруг переводчика perevod.molly-trade.workers.dev.
/// Страница грузится с сервера — улучшения приходят без пересборки. Родное здесь то, чего не даёт Safari:
/// вибрация, голос сразу в громкий динамик, озвучка без «разблокировки» касанием.
@main
struct PerevodApp: App {
    // запуск без экрана (команда Siri «скажи») звук не трогает: Siri в этот момент ещё слушает
    init() { DispatchQueue.main.async { if UIApplication.shared.applicationState != .background { Audio.setup() } } }
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
    /// «Куда звучит» в настройках: 0 — сам (наушники, если подключены, иначе громкий динамик), 1 — всегда громкий динамик, 2 — к уху,
    /// 3 — перевод для меня в наушники, перевод для собеседника — из громкого динамика.
    static var out = Shared.defaults.integer(forKey: "output")
    private static var forced = false
    private static var ownMic = false
    /// toMe — кому сейчас прозвучит голос: мне (true) или собеседнику (false); nil — голоса нет (запись, запуск).
    /// Ответ — включился ли звук (без экрана, из команды Siri, может и не включиться).
    @discardableResult static func setup(toMe: Bool? = nil) -> Bool {
        let s = AVAudioSession.sharedInstance()
        var o: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
        if out != 2 { o.insert(.defaultToSpeaker) }
        // режим ставим, только если он другой: повторная установка сбрасывает «в динамик», и при «Мне — в наушники»
        // звук перед каждой фразой заново шёл наушники → динамик (1,5 с до голоса вместо 0,65 — журнал 14.11.2026)
        if s.category != .playAndRecord || s.categoryOptions != o { try? s.setCategory(.playAndRecord, mode: .default, options: o) }
        try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)   // иначе при включённом микрофоне айфон глушит всю вибрацию
        var ok = true
        do { try s.setActive(true) } catch { ok = false }
        // «мне — в наушники»: айфон лежит между нами — слушает его микрофон, а не гарнитура
        if out == 3 {
            if s.preferredInput?.portType != .builtInMic, let m = s.availableInputs?.first(where: { $0.portType == .builtInMic }) { try? s.setPreferredInput(m) }
            ownMic = true
        } else if ownMic { try? s.setPreferredInput(nil); ownMic = false }
        if out == 1 || (out == 3 && toMe == false) { if s.currentRoute.outputs.first?.portType != .builtInSpeaker { try? s.overrideOutputAudioPort(.speaker) }; forced = true }
        // при «мне — в наушники» запись звук не трогает: слушает всё равно микрофон айфона, а лишнее переключение — это задержка
        else if forced, out != 3 || toMe == true { try? s.overrideOutputAudioPort(.none); forced = false }
        return ok
    }

    /// Что сейчас со звуком — в журнал, когда микрофон не включился.
    static var state: String {
        let s = AVAudioSession.sharedInstance()
        let i = s.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: "+")
        let o = s.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: "+")
        return "in=\(i) out=\(o) sr=\(Int(s.sampleRate)) other=\(s.isOtherAudioPlaying) mode=\(out)"
    }
}
