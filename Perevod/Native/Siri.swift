import AppIntents
import AVFoundation
import UIKit

/// «Привет, Siri, скажи через Тапни» → Siri спрашивает «Что сказать?» → фраза переводится на язык собеседника
/// и звучит из айфона, как только Siri уйдёт с экрана. Приложение открывать не нужно, руки свободны. Фраза потом появляется в ленте.
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
            await Log.sendNow("err", ["at": "siri", "err": String(Log.brief(error).prefix(300))])
            throw Fail(say: "Не получилось перевести. Проверьте интернет.")
        }
        let it = Item(mine: r.mine, src: r.mine ? "ru" : r.src, to: r.to, text: t, out: r.out)
        let trMs = Log.ms(since: t0)
        guard let d = try? await Api.voice(it.out, lang: it.mine ? it.to : "ru") else {
            Inbox.put(it, speak: true)
            await Log.sendNow("siri", ["ok": false, "trMs": trMs, "ms": Log.ms(since: t0), "why": "голос не скачался"])
            throw Fail(say: "Перевод готов, но сказать вслух не получилось. Откройте Tapny — фраза прозвучит там.")
        }
        // Пока Siri на экране, айфон глушит чужой звук: голос «играл» в тишину (журнал 14.11.2026: ok, а Павел ничего не слышал).
        // Поэтому команду заканчиваем сразу, а говорим, когда Siri уйдёт.
        OneShot.shared.later(d, rate: AppModel.rates[min(max(Pref.int("voiceSpeed", 1), 0), 2)], item: it, trMs: trMs, t0: t0)
        return .result()
    }
}

/// Один звук до конца — для команды Siri: ленты с её проигрывателем в этот момент может не быть.
@MainActor final class OneShot: NSObject, AVAudioPlayerDelegate {
    static let shared = OneShot()
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Bool, Never>?
    private(set) var stuck = false          // звук запустился, но конца не дождались (его могла перебить Siri)
    private var held = false                // звук сейчас забрали (Siri, звонок)
    private var intr = 0, cuts = 0          // сколько раз забирали всего и посреди нашей фразы — в журнал
    private var bg = UIBackgroundTaskIdentifier.invalid

    private var watching = false

    private func watch() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let began = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in OneShot.shared.interrupted(began) }
        }
    }

    private func interrupted(_ began: Bool) {
        held = began
        if began { intr += 1; if player != nil { cuts += 1 } }
        else if let p = player, cuts > 0 {      // фразу перебили — говорим её с начала
            try? AVAudioSession.sharedInstance().setActive(true)
            p.currentTime = 0; p.play()
        }
    }

    private func endBg() {
        guard bg != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bg); bg = .invalid
    }

    /// Сказать фразу после того, как Siri уйдёт с экрана. Приложение при этом может быть не открыто.
    func later(_ d: Data, rate: Float, item it: Item, trMs: Int, t0: Date) {
        watch(); endBg()
        bg = UIApplication.shared.beginBackgroundTask(withName: "say") { Task { @MainActor in OneShot.shared.endBg() } }
        stuck = false; intr = 0; cuts = 0
        let toMe = !it.mine
        let pre = Audio.setup(toMe: toMe)       // пока команда ещё выполняется, звук разрешают включить и без экрана
        Task { @MainActor in
            let s = AVAudioSession.sharedInstance()
            let flags0 = "\(s.secondaryAudioShouldBeSilencedHint ? 1 : 0)\(s.isOtherAudioPlaying ? 1 : 0)\(self.held ? 1 : 0)"
            let w0 = Date()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            // Siri ещё держит звук — ждём, но не дольше 4 с
            while (self.held || s.secondaryAudioShouldBeSilencedHint) && Date().timeIntervalSince(w0) < 4 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            let wait = Log.ms(since: w0)
            let flags1 = "\(s.secondaryAudioShouldBeSilencedHint ? 1 : 0)\(s.isOtherAudioPlaying ? 1 : 0)\(self.held ? 1 : 0)"
            var ok = false, tries = 0
            let p0 = Date()
            while !ok && tries < 8 {
                tries += 1
                if Audio.setup(toMe: toMe), await self.play(d, rate: rate) { ok = true }
                else { try? await Task.sleep(nanoseconds: 400_000_000) }
            }
            let playMs = Log.ms(since: p0), route = Audio.state, vol = Int(s.outputVolume * 100)
            let back = UIApplication.shared.applicationState == .background
            // приложение не на экране — звук отдаём обратно: музыка или подкаст продолжат играть
            if back { try? s.setActive(false, options: .notifyOthersOnDeactivation) }
            Inbox.put(it, speak: !ok)
            await Log.sendNow("siri", ["ok": ok, "tries": tries, "trMs": trMs, "ms": Log.ms(since: t0), "why": ok ? "" : "звук не включился",
                                       "stuck": self.stuck, "mode": Audio.out, "pre": pre, "wait": wait, "flags": flags0 + ">" + flags1,
                                       "intr": self.intr, "cuts": self.cuts, "playMs": playMs, "route": route, "vol": vol, "back": back])
            self.endBg()
        }
    }

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
                self.stuck = true; self.finish(!self.held)   // конец не сообщили — не ждём вечно; звук так и не вернули — попробуем ещё раз
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
