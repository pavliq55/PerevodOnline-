import SwiftUI
import UIKit

/// Одна реплика разговора.
struct Item: Identifiable, Codable, Equatable {
    var id = UUID()
    var mine: Bool
    var src: String            // язык оригинала
    var to: String             // язык перевода
    var text: String           // что сказали
    var out: String            // перевод
    var date = Date()
    var photo = false
    var draft = false          // черновой перевод, пока говорят
}

/// Состояние приложения: история, язык собеседника, запись, онлайн-распознавание, перевод, озвучка.
@MainActor final class AppModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var to: String = Shared.partner { didSet { Shared.partner = to; spare?.close(); spare = nil; warm() } }
    @Published var recording = false
    @Published var arming = false              // микрофон включается
    @Published var busy = false                // ждём перевод
    @Published var liveText = ""
    @Published var liveDraft = ""
    @Published var hint = "Нажмите и говорите" {
        didSet {   // всё, что не обычная подсказка, — сбой, который увидел человек: в журнал
            guard hint != oldValue, !["Нажмите и говорите", "Перевожу…", "Читаю текст на фото…"].contains(hint), !hint.hasPrefix("Говорите…") else { return }
            Log.send("hint", ["msg": hint])
        }
    }
    @Published var loggedIn = Shared.token != nil
    @Published var autoSpeak = Shared.defaults.object(forKey: "autoSpeak") as? Bool ?? true { didSet { Shared.defaults.set(autoSpeak, forKey: "autoSpeak") } }
    @Published var recStart = Date()
    @Published var toggleMode = false
    @Published var weakNet = false

    let voice = Voice()
    private let mic = Mic()
    private var session: LiveSession?
    private var spare: LiveSession?
    private var liveLang = ""
    private var finalWait: CheckedContinuation<[String: Any]?, Never>?
    private var draftTask: Task<Void, Never>?
    private var draftText = ""
    private var expectVoice: (text: String, lang: String)?   // голос, который сервер пришлёт следом за переводом
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init() {
        load()
        // только для снимков в облачной сборке: «-demoUI YES» (пример разговора), «-demoRec YES» (идёт запись)
        let ud = UserDefaults.standard
        if ud.bool(forKey: "demoUI") || ud.bool(forKey: "demoRec") {
            loggedIn = true
            items = [Item(mine: true, src: "ru", to: "id", text: "Здравствуйте, сколько стоит аренда байка на неделю?", out: "Halo, berapa sewa motor seminggu?"),
                     Item(mine: false, src: "id", to: "ru", text: "Untuk seminggu 700 ribu, sudah termasuk helm.", out: "За неделю 700 тысяч, шлем включён."),
                     Item(mine: false, src: "id", to: "ru", text: "Bisa, jam delapan sudah buka.", out: "Да, в восемь мы уже открыты.")]
            if ud.bool(forKey: "demoRec") { recording = true; recStart = Date().addingTimeInterval(-4); liveText = "Можно забрать завтра утром"; liveDraft = "Bisa diambil besok pagi?" }
            return
        }
        voice.blocked = { [weak self] in self?.recording ?? false }
        warm()
        Log.launch()
    }

    var lang: Lang { Langs.byId(to) }

    // MARK: история
    private var file: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json") }
    private func load() { if let d = try? Data(contentsOf: file), let h = try? JSONDecoder().decode([Item].self, from: d) { items = h } }
    func save() { items = Array(items.suffix(60)); try? JSONEncoder().encode(items.filter { !$0.draft }).write(to: file) }
    func clear() { items = []; save() }
    func remove(_ it: Item) { items.removeAll { $0.id == it.id }; save() }

    // MARK: вход
    func login(pin: String) async throws {
        Shared.token = try await Api.login(pin: pin)
        loggedIn = true; warm()
    }
    func logout() { Shared.token = nil; loggedIn = false; spare?.close(); spare = nil }

    // MARK: запасная сессия — следующая фраза начинается мгновенно
    func warm() {
        guard loggedIn, let k = Shared.token else { return }
        if let s = spare, s.usable { return }
        spare?.close()
        spare = LiveSession(to: to, key: k)
    }

    // MARK: запись
    func startRec(toggle: Bool = false) {
        guard loggedIn, !recording, !arming, let k = Shared.token else { return }
        voice.stop()
        arming = true; toggleMode = toggle; weakNet = false
        liveText = ""; liveDraft = ""; draftText = ""; liveLang = ""
        let s: LiveSession
        if let sp = spare, sp.usable { s = sp } else { spare?.close(); s = LiveSession(to: to, key: k) }
        spare = nil
        session = s
        s.onEvent = { [weak self] e in self?.on(e, s) }
        mic.onChunk = { [weak self, weak s] d in
            guard let self, let s else { return }
            s.sendAudio(d)
            if !s.ready && Date().timeIntervalSince(self.recStart) > 3 { self.weakNet = true }
        }
        Audio.setup()
        do { try mic.start() } catch { arming = false; Log.send("err", ["at": "mic", "err": "\(error)"]); hint = "Микрофон не включился — разреши доступ в Настройках"; return }
        arming = false; recording = true; recStart = Date()
        haptic.impactOccurred()
        hint = toggle ? "Говорите… нажмите, чтобы закончить" : "Говорите… отпустите — переведу"
    }

    func stopRec() {
        guard recording else { return }
        recording = false
        haptic.impactOccurred(intensity: 0.6)
        let s = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in   // хвост последнего слова
            guard let self else { return }
            self.mic.stop()
            let dur = Date().timeIntervalSince(self.recStart)
            s?.stop(diag: ["frames": self.mic.frames, "ms": Int(dur * 1000), "ready": s?.ready ?? false, "native": true])
            Task { await self.finish(s, dur: dur) }
            self.warm()
        }
    }

    private func on(_ e: LiveSession.Event, _ s: LiveSession) {
        guard s === session else { return }
        switch e {
        case .live(let l, let t):
            liveLang = l; liveText = t
            scheduleDraft()
        case .final(let j):
            if let tr = j["tr"] as? [String: Any], let out = tr["out"] as? String, let vl = j["voice"] as? String { expectVoice = (out, vl) }
            finalWait?.resume(returning: j); finalWait = nil
        case .voice(let d):
            if let e = expectVoice, d.count > 500 { voice.put(d, text: e.text, lang: e.lang); voice.drain() }
            expectVoice = nil
        case .error(let err): Log.send("err", ["at": "live", "err": err]); finalWait?.resume(returning: nil); finalWait = nil
        case .closed: finalWait?.resume(returning: nil); finalWait = nil
        default: break
        }
    }

    /// Черновой перевод раз в ~0,9 с, пока человек говорит.
    private func scheduleDraft() {
        guard draftTask == nil, liveText.split(separator: " ").count >= 3, liveText != draftText else { return }
        let text = liveText, lang = liveLang
        draftText = text
        draftTask = Task {
            if let t = try? await Api.translate(text, to: to, force: lang == "ru" ? "out" : "ru", draft: true), recording || busy { liveDraft = t.out }
            try? await Task.sleep(nanoseconds: 900_000_000)
            draftTask = nil
            if recording, liveText != draftText { scheduleDraft() }
        }
    }

    private func finish(_ s: LiveSession?, dur: TimeInterval) async {
        guard dur > 0.5, mic.pcm.count > 3000 else { hint = "Слишком коротко — держите кнопку, пока говорите"; liveText = ""; return }
        busy = true; hint = "Перевожу…"
        defer { busy = false; liveText = ""; liveDraft = ""; voice.drain() }
        let t0 = Date(); var path = "final"
        // ждём итог: сервер может думать до ~6 с (Aqua + перевод); слабая связь — до 25 с
        let fin: [String: Any]? = await withCheckedContinuation { c in
            finalWait = c
            DispatchQueue.main.asyncAfter(deadline: .now() + ((s?.ready ?? false) ? 12 : 4)) { [weak self] in
                self?.finalWait?.resume(returning: nil); self?.finalWait = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { s?.close() }   // голос приходит следом по этому же соединению
        let text = (fin?["text"] as? String) ?? ""
        let flang = (fin?["lang"] as? String) ?? liveLang
        if let fin, text.isEmpty, mic.frames > 10 { _ = fin; hint = "Не расслышал — повторите"; return }   // тишина
        do {
            var tr = Api.parseTr(fin?["tr"] as? [String: Any])
            var heard = text
            if tr == nil, !heard.isEmpty { path = "tr"; tr = try await Api.translate(heard, to: to, force: flang == "ru" ? "out" : "ru") }
            if tr == nil {
                if !liveText.isEmpty, liveText.split(separator: " ").count >= 3 {
                    path = "live"; heard = liveText; tr = try await Api.translate(heard, to: to)
                } else {
                    path = "stt"
                    let r = try await Api.stt(wav: mic.wav(), to: to)
                    heard = r.text
                    if heard.isEmpty { hint = "Не расслышал — повторите"; return }
                    if let t = r.tr { tr = t } else { tr = try await Api.translate(heard, to: to) }
                }
            }
            guard let tr else { return }
            // сколько ждали перевод после отпускания и каким путём он пришёл (final — обычный; остальное — запасные)
            Log.send("phrase", ["recMs": Int(dur * 1000), "waitMs": Log.ms(since: t0), "path": path, "ready": s?.ready ?? false, "gotFinal": fin != nil])
            add(Item(mine: tr.mine, src: tr.mine ? "ru" : (tr.src.isEmpty ? flang : tr.src), to: tr.to, text: heard, out: tr.out))
        } catch {
            Log.send("err", ["at": "finish/" + path, "err": "\(error)", "waitMs": Log.ms(since: t0)])
            hint = (error as? Api.Fail)?.message == "pin" ? "Нужно войти заново" : "Нет связи — повторите"
            if (error as? Api.Fail)?.message == "pin" { logout() }
        }
    }

    func add(_ it: Item) {
        items.append(it); save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        hint = "Нажмите и говорите"
        if it.mine && autoSpeak { voice.auto(it.id, text: it.out, lang: it.to) }
        else { voice.prefetch(it.out, lang: it.mine ? it.to : "ru") }
    }

    // MARK: текст, фото, «наоборот»
    func translateTyped(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        busy = true; defer { busy = false }
        do { let r = try await Api.translate(t, to: to); add(Item(mine: r.mine, src: r.mine ? "ru" : r.src, to: r.to, text: t, out: r.out)) }
        catch { Log.send("err", ["at": "typed", "err": "\(error)"]); hint = "Не получилось перевести — повторите" }
    }

    func translatePhoto(_ img: UIImage) async {
        busy = true; hint = "Читаю текст на фото…"; defer { busy = false }
        let k = min(1, 1280 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = small.jpegData(compressionQuality: 0.75) else { return }
        do { let o = try await Api.photo(jpeg: jpg); add(Item(mine: false, src: "", to: "ru", text: "📷 Фото", out: o, photo: true)) }
        catch { Log.send("err", ["at": "photo", "err": "\(error)"]); hint = error.localizedDescription }
    }

    func flip(_ it: Item) async {
        busy = true; defer { busy = false }
        do {
            let r = try await Api.translate(it.text, to: it.mine ? to : (Langs.all.contains { $0.id == it.src } ? it.src : to), force: it.mine ? "ru" : "out")
            remove(it); add(Item(mine: r.mine, src: r.mine ? "ru" : r.src, to: r.to, text: it.text, out: r.out))
        } catch { Log.send("err", ["at": "flip", "err": "\(error)"]); hint = "Не получилось — повторите" }
    }

    // MARK: Siri / кнопка действия
    func handle(action: String) { if action == "listen" { startRec(toggle: true) } }
}
