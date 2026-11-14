import AppIntents
import AVFoundation

/// «Привет, Siri, скажи через Тапни» → Siri спрашивает «Что сказать?» → фраза переводится на язык собеседника
/// и звучит из айфона. Приложение открывать не нужно, руки свободны. Фраза потом появляется в ленте.
struct SayIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Сказать фразу собеседнику"
    static var description = IntentDescription("Переводит вашу фразу на язык собеседника и говорит её вслух. Tapny открывать не нужно.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Фраза", requestValueDialog: IntentDialog("Что сказать?"))
    var text: String

    struct Fail: Error, CustomLocalizedStringResourceConvertible {
        let say: String
        var localizedStringResource: LocalizedStringResource { "\(say)" }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Shared.token != nil else { throw Fail(say: "Сначала откройте Tapny и войдите.") }
        guard !t.isEmpty else { throw Fail(say: "Фразу не слышно — повторите.") }
        // настройки перевода и голоса — те же, что в приложении (оно сейчас может быть не запущено)
        Api.tone = Pref.bool("casual", false) ? "casual" : ""
        Api.gl = Pref.words.map { [$0.a, $0.b] }
        Api.female = Pref.bool("voiceFemale", false)
        let t0 = Date()
        let r: Api.Tr
        do { r = try await Api.translate(t, to: Shared.partner) } catch {
            await Log.sendNow("err", ["at": "siri", "err": String("\(error)".prefix(300))])
            throw Fail(say: "Не получилось перевести. Проверьте интернет.")
        }
        let it = Item(mine: r.mine, src: r.mine ? "ru" : r.src, to: r.to, text: t, out: r.out)
        let trMs = Log.ms(since: t0)
        var ok = false, tries = 0, why = "голос не скачался"
        if let d = try? await Api.voice(it.out, lang: it.mine ? it.to : "ru") {
            why = "звук не включился"
            let rate = AppModel.rates[min(max(Pref.int("voiceSpeed", 1), 0), 2)]
            // Siri отдаёт звук не сразу — пробуем несколько раз
            while !ok && tries < 8 {
                tries += 1
                if Audio.setup(toMe: !it.mine), await OneShot.shared.play(d, rate: rate) { ok = true }
                else { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
        }
        Inbox.put(it, speak: !ok)
        await Log.sendNow("siri", ["ok": ok, "tries": tries, "trMs": trMs, "ms": Log.ms(since: t0), "why": ok ? "" : why, "stuck": OneShot.shared.stuck, "out": Audio.out])
        if !ok { throw Fail(say: "Перевод готов, но сказать вслух не получилось. Откройте Tapny — фраза прозвучит там.") }
        return .result()
    }
}

/// Один звук до конца — для команды Siri: ленты с её проигрывателем в этот момент может не быть.
@MainActor final class OneShot: NSObject, AVAudioPlayerDelegate {
    static let shared = OneShot()
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Bool, Never>?
    private(set) var stuck = false          // звук запустился, но конца не дождались (его могла перебить Siri)

    /// true — прозвучало до конца; false — звук не запустился.
    func play(_ d: Data, rate: Float) async -> Bool {
        finish(false)
        guard let p = try? AVAudioPlayer(data: d) else { return false }
        p.delegate = self; p.enableRate = true; p.rate = rate
        guard p.play() else { return false }
        player = p; stuck = false
        let limit = p.duration / Double(rate) + 3, who = ObjectIdentifier(p)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            done = c
            DispatchQueue.main.asyncAfter(deadline: .now() + limit) { [weak self] in
                guard let self, let cur = self.player, ObjectIdentifier(cur) == who else { return }
                self.stuck = true; self.finish(true)   // конец не сообщили — не держим Siri вечно
            }
        }
    }

    private func finish(_ ok: Bool) {
        player?.stop(); player = nil
        done?.resume(returning: ok); done = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let who = ObjectIdentifier(p)
        Task { @MainActor in
            guard let cur = self.player, ObjectIdentifier(cur) == who else { return }
            self.finish(true)
        }
    }
}

/// Фразы, переведённые без открытия приложения, ждут здесь, пока лента их заберёт.
enum Inbox {
    static let note = Notification.Name("tapnyInbox")
    private static var all: [Item] {
        get { Shared.defaults.data(forKey: "inbox").flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? [] }
        set { if let d = try? JSONEncoder().encode(newValue) { Shared.defaults.set(d, forKey: "inbox") } }
    }
    /// speak — вслух сказать не вышло: пусть прозвучит, когда откроют приложение.
    static func put(_ it: Item, speak: Bool) {
        all = Array((all + [it]).suffix(20))
        if speak { Shared.defaults.set(it.id.uuidString, forKey: "inboxSpeak") }
        NotificationCenter.default.post(name: note, object: nil)
    }
    static func take() -> (items: [Item], speak: UUID?) {
        let a = all
        guard !a.isEmpty else { return ([], nil) }
        let s = Shared.defaults.string(forKey: "inboxSpeak").flatMap { UUID(uuidString: $0) }
        Shared.defaults.removeObject(forKey: "inbox"); Shared.defaults.removeObject(forKey: "inboxSpeak")
        return (a, s)
    }
}
