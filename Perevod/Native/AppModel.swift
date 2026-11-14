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

/// Громкость голоса — отдельно от остального состояния: меняется ~20 раз в секунду и перерисовывает только шар.
@MainActor final class Meter: ObservableObject { @Published var level = 0.0 }

/// Состояние приложения: история, язык собеседника, запись, онлайн-распознавание, перевод, озвучка.
@MainActor final class AppModel: ObservableObject {
    @Published var items: [Item] = [] {
        didSet {   // крупной становится только что добавленная реплика; после удаления соседние не меняют размер
            if items.count > oldValue.count, let l = items.last, l.id != oldValue.last?.id { big = l.id }
        }
    }
    @Published var big: UUID?                  // реплика, показанная крупно
    @Published var to: String = Shared.partner {
        didSet {
            if oldValue != to { prevTo = oldValue; Shared.defaults.set(oldValue, forKey: "prevTo") }   // прошлый язык — для свайпа по полоске языков
            Shared.partner = to; spare?.close(); spare = nil; warm()
        }
    }
    private(set) var prevTo = Shared.defaults.string(forKey: "prevTo") ?? ""
    /// Свайп по полоске языков: вернуться к прошлому языку собеседника.
    func swapLang() {
        guard !recording, !prevTo.isEmpty, prevTo != to else { hint = "Выберите второй язык — потом меняйте свайпом"; return }
        to = prevTo
        Hap.impact()
        hint = "Нажмите и говорите"
    }
    @Published var recording = false
    @Published var arming = false              // микрофон включается
    @Published var busy = false                // ждём перевод
    @Published var phrase = false              // идёт голосовая фраза: от нажатия до готового перевода (экран в это время не перестраивается)
    @Published var liveText = ""
    @Published var typing = false              // пишут текстом: поле ввода стоит прямо в облаке
    @Published var typed = ""
    @Published var liveDraft = ""
    @Published var hint = "Нажмите и говорите" {
        didSet {   // всё, что не обычная подсказка, — сбой, который увидел человек: в журнал
            guard hint != oldValue, !["Нажмите и говорите", "Перевожу…", "Читаю текст на фото…"].contains(hint), !hint.hasPrefix("Говорите…") else { return }
            Log.send("hint", ["msg": hint])
        }
    }
    @Published var loggedIn = Shared.token != nil
    @Published var autoSpeak = Shared.defaults.object(forKey: "autoSpeak") as? Bool ?? true { didSet { Shared.defaults.set(autoSpeak, forKey: "autoSpeak") } }
    // настройки (экран «Настройки») — хранятся на айфоне
    @Published var speakThem = Pref.bool("speakThem", false) { didSet { Pref.set(speakThem, "speakThem") } }          // озвучивать и собеседника
    @Published var voiceSpeed = Pref.int("voiceSpeed", 1) { didSet { Pref.set(voiceSpeed, "voiceSpeed"); applyVoice() } }   // 0 медленнее · 1 обычно · 2 быстрее
    @Published var voiceFemale = Pref.bool("voiceFemale", false) { didSet { Pref.set(voiceFemale, "voiceFemale"); applyVoice(); voice.flush(); rewarm() } }
    @Published var output = Pref.int("output", 0) { didSet { Pref.set(output, "output"); Audio.out = output; Audio.setup() } }   // 0 сам · 1 динамик · 2 к уху
    @Published var orbMode = Pref.int("orbMode", 0) { didSet { Pref.set(orbMode, "orbMode") } }                       // 0 держать или нажать · 1 только держать · 2 только нажать
    @Published var autoStop = Pref.bool("autoStop", false) { didSet { Pref.set(autoStop, "autoStop") } }              // закреплённая запись сама заканчивается по тишине
    @Published var haptics = Pref.bool("haptics", true) { didSet { Pref.set(haptics, "haptics"); Hap.on = haptics } }
    @Published var textBig = Pref.bool("textBig", false) { didSet { Pref.set(textBig, "textBig"); T.scale = textBig ? AppModel.bigScale : 1 } }
    @Published var theme = Pref.int("theme", 0) { didSet { Pref.set(theme, "theme"); Look.apply(theme) } }           // 0 как в айфоне · 1 светлая · 2 тёмная
    @Published var keepAwake = Pref.bool("keepAwake", false) { didSet { Pref.set(keepAwake, "keepAwake"); UIApplication.shared.isIdleTimerDisabled = keepAwake } }
    @Published var showDraft = Pref.bool("showDraft", true) { didSet { Pref.set(showDraft, "showDraft"); if !showDraft { liveDraft = "" } } }
    @Published var casual = Pref.bool("casual", false) { didSet { Pref.set(casual, "casual"); applyTr(); rewarm() } } // тон: по-простому, на «ты»
    @Published var words: [Word] = Pref.words { didSet { Pref.words = words; applyTr(); rewarm() } }                  // «Мои слова»
    @Published var keep = Pref.int("keep", 60) { didSet { Pref.set(keep, "keep"); save() } }                          // сколько фраз хранить; 0 — не хранить
    static let bigScale: CGFloat = 1.22
    static let rates: [Float] = [0.95, 1.12, 1.3]
    private func applyVoice() { voice.rate = AppModel.rates[min(max(voiceSpeed, 0), 2)]; Api.female = voiceFemale }
    private func applyTr() { Api.tone = casual ? "casual" : ""; Api.gl = words.map { [$0.a, $0.b] } }
    /// Сменили тон, слова или голос — запасное соединение открываем заново, уже с ними.
    private func rewarm() { spare?.close(); spare = nil; warm() }

    @Published var recStart = Date()
    @Published var toggleMode = false { didSet { if toggleMode { lastLoud = Date(); lastWord = Date() } } }
    private var lastLoud = Date()              // когда последний раз был слышен голос
    private var lastWord = Date()              // когда последний раз дописались слова
    @Published var weakNet = false

    let voice = Voice()
    let meter = Meter()
    @Published var undo: Item?                 // только что удалённая реплика — можно вернуть
    private var undoAt = 0
    private var undoTask: Task<Void, Never>?
    private let mic = Mic()
    private var session: LiveSession?
    private var spare: LiveSession?
    @Published private(set) var liveLang = ""   // на каком языке говорят сейчас: пусто — ещё не понятно
    @Published private(set) var liveId = UUID() // номер «живого» облака; готовая реплика получает его же — облако остаётся на месте
    private var finalWait: CheckedContinuation<[String: Any]?, Never>?
    private var draftTask: Task<Void, Never>?
    private var draftText = ""
    private var expectVoice: (text: String, lang: String)?   // голос, который сервер пришлёт следом за переводом
    private let tapOn = UIImpactFeedbackGenerator(style: .medium)   // нажал шар
    private let tapOff = UIImpactFeedbackGenerator(style: .soft)    // отпустил — мягче, чтобы начало и конец различались рукой

    init() {
        load(); big = items.last?.id
        mic.onLevel = { [weak self] v in self?.heard(v) }
        Hap.on = haptics; T.scale = textBig ? AppModel.bigScale : 1; applyVoice(); applyTr()
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        // только для снимков в облачной сборке: «-demoUI YES» (пример разговора), «-demoRec YES» (идёт запись),
        // «-demoFlow YES» (три фразы «как вживую» — для видео, плавно ли перестраивается экран),
        // «-demoMany YES» (длинная лента — для проверки свайпов настоящими касаниями, см. UITests)
        let ud = UserDefaults.standard
        if ud.bool(forKey: "demoUI") || ud.bool(forKey: "demoRec") || ud.bool(forKey: "demoFlow") || ud.bool(forKey: "demoMany") || ud.bool(forKey: "demoBusy") || ud.bool(forKey: "demoLocked") {
            loggedIn = true; voice.demo = true
            if ud.bool(forKey: "demoBig") { T.scale = AppModel.bigScale }   // «-demoBig YES» — крупный текст на снимке
            items = [Item(mine: true, src: "ru", to: "id", text: "Здравствуйте, сколько стоит аренда байка на неделю?", out: "Halo, berapa sewa motor seminggu?"),
                     Item(mine: false, src: "id", to: "ru", text: "Untuk seminggu 700 ribu, sudah termasuk helm.", out: "За неделю 700 тысяч, шлем включён."),
                     Item(mine: false, src: "id", to: "ru", text: "Bisa, jam delapan sudah buka.", out: "Да, в восемь мы уже открыты.")]
            if ud.bool(forKey: "demoMany") {
                items += [Item(mine: true, src: "ru", to: "id", text: "А можно забрать завтра утром?", out: "Bisa diambil besok pagi?"),
                          Item(mine: false, src: "id", to: "ru", text: "Bisa, kami buka jam delapan.", out: "Можно, мы открываемся в восемь."),
                          Item(mine: true, src: "ru", to: "id", text: "Нужен ли залог или паспорт?", out: "Apakah perlu deposit atau paspor?"),
                          Item(mine: false, src: "id", to: "ru", text: "Cukup fotokopi paspor saja.", out: "Достаточно копии паспорта."),
                          Item(mine: true, src: "ru", to: "id", text: "Отлично, а шлем второй дадите?", out: "Bagus, bisa dapat helm kedua?"),
                          Item(mine: false, src: "id", to: "ru", text: "Tentu, helm kedua gratis.", out: "Конечно, второй шлем бесплатно."),
                          Item(mine: true, src: "ru", to: "id", text: "Хорошо, тогда до завтра", out: "Baik, sampai besok")]
            }
            big = items.last?.id
            if ud.bool(forKey: "demoType") { typing = true; typed = "Можно оплатить картой?" }   // «-demoType YES» — снимок: пишут текстом
            if ud.bool(forKey: "demoFlow") { Task { await demoFlow() } }
            if ud.bool(forKey: "demoBusy") { liveLang = "ru"; phrase = true; busy = true; hint = "Перевожу…"; liveText = "Можно забрать завтра утром"; liveDraft = "Bisa diambil besok pagi?" }
            if ud.bool(forKey: "demoLocked") { liveLang = "ru"; meter.level = 0.5; phrase = true; recording = true; toggleMode = true; recStart = Date().addingTimeInterval(-22); hint = "Говорите… нажмите, чтобы закончить"; liveText = "Можно забрать завтра утром"; liveDraft = "Bisa diambil besok pagi?" }
            if ud.bool(forKey: "demoRec") { liveLang = "ru"; meter.level = 0.8; phrase = true; recording = true; hint = "Говорите… отпустите · ↑ закрепить · ← отмена"; recStart = Date().addingTimeInterval(-4); liveText = "Можно забрать завтра утром"; liveDraft = "Bisa diambil besok pagi?" }
            return
        }
        voice.blocked = { [weak self] in self?.recording ?? false }
        warm()
        Log.launch()
        Log.send("prefs", ["speakThem": speakThem, "speed": voiceSpeed, "female": voiceFemale, "out": output, "orb": orbMode, "autoStop": autoStop,
                           "haptics": haptics, "big": textBig, "theme": theme, "awake": keepAwake, "draft": showDraft, "casual": casual, "words": words.count, "keep": keep])
        if loggedIn, UIApplication.shared.applicationState != .background { Audio.setup(); mic.warm() }   // не при запуске без экрана (Siri)
        takeInbox()
        // звук в фоне приложению разрешён (команда Siri «скажи») — запись сама не оборвётся, останавливаем её явно
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; if self.recording { self.cancelRec() }; self.mic.off() }
        }
        NotificationCenter.default.addObserver(forName: Inbox.note, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.takeInbox() } }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.loggedIn else { return }; Audio.setup(); self.mic.warm(); self.takeInbox() }
        }
    }

    private func demoFlow() async {
        func nap(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        let say = [(true, "Можно забрать байк завтра утром часов в восемь и вернуть через неделю", "Bisa ambil motornya besok pagi sekitar jam delapan dan kembalikan seminggu lagi?"),
                   (false, "Bisa, jam delapan sudah buka", "Да, в восемь мы уже открыты"),
                   (true, "Хорошо, спасибо", "Baik, terima kasih")]
        await nap(4)
        for (mine, text, out) in say {
            liveText = ""; liveDraft = ""; liveLang = ""; liveId = UUID(); phrase = true; recording = true; recStart = Date(); hint = "Говорите… отпустите · ↑ закрепить · ← отмена"
            var acc = ""
            for (i, w) in text.split(separator: " ").enumerated() {
                await nap(0.15); meter.level = Double.random(in: 0.2...1); await nap(0.15); meter.level = Double.random(in: 0.1...0.9); acc += (acc.isEmpty ? "" : " ") + w; liveText = acc; liveLang = mine ? "ru" : "id"
                if i == 4 { liveDraft = String(out.prefix(out.count / 2)) }
            }
            await nap(0.4); recording = false; meter.level = 0
            await nap(0.17); busy = true; hint = "Перевожу…"
            await nap(0.9)
            items.append(Item(id: liveId, mine: mine, src: mine ? "ru" : "id", to: mine ? "id" : "ru", text: text, out: out))
            hint = "Нажмите и говорите"; busy = false; phrase = false; liveText = ""; liveDraft = ""
            await nap(2.5)
        }
    }

    var lang: Lang { Langs.byId(to) }

    // MARK: история
    private var file: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json") }
    private func load() { if let d = try? Data(contentsOf: file), let h = try? JSONDecoder().decode([Item].self, from: d) { items = h } }
    func save() {
        let cap = keep == 0 ? 60 : keep
        if items.count > cap { items = Array(items.suffix(cap)) }
        if keep == 0 { try? FileManager.default.removeItem(at: file); return }   // «не хранить»: разговор живёт, пока открыто приложение
        try? JSONEncoder().encode(items.filter { !$0.draft }).write(to: file)
    }
    /// Весь разговор текстом — «Выгрузить разговор» в настройках.
    var exportText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMM, HH:mm"
        var s = "Разговор в Tapny\n"
        for it in items where !it.draft {
            let who = it.mine ? "Я" : it.photo ? "Фото" : "Собеседник"
            s += "\n" + f.string(from: it.date) + " · " + who + "\n" + (it.photo ? "" : it.text + "\n") + "→ " + it.out + "\n"
        }
        return s
    }
    func clear() { items = []; save() }
    func remove(_ it: Item) {
        guard let i = items.firstIndex(where: { $0.id == it.id }) else { return }
        if voice.playingId == it.id { voice.stop() }
        items.remove(at: i); save()
        undo = it; undoAt = i
        undoTask?.cancel()
        undoTask = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if !Task.isCancelled { undo = nil } }
    }
    func restore() {
        guard let it = undo else { return }
        undoTask?.cancel(); undo = nil
        items.insert(it, at: min(undoAt, items.count)); save()
    }

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
        if typing { cancelTyping() }
        let spoke = voice.playingId != nil   // только что звучал перевод — звук «до нажатия» не берём, там наш же голос
        voice.stop()
        if haptics { tapOn.impactOccurred(intensity: 0.9) }   // сразу на касание, не дожидаясь микрофона
        arming = true; toggleMode = toggle; weakNet = false
        liveText = ""; liveDraft = ""; draftText = ""; liveLang = ""; liveId = UUID()
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
        if !mic.running { Audio.setup() }
        do { try mic.start(preroll: !spoke) } catch { arming = false; Log.send("err", ["at": "mic", "err": "\(error)"]); hint = error is Mic.Busy ? "Микрофон занят звонком — напишите текстом" : "Микрофон не включился — разреши доступ в Настройках"; return }
        arming = false; phrase = true; recording = true; recStart = Date(); lastLoud = recStart; lastWord = recStart
        tapOff.prepare()
        hint = toggle ? "Говорите… нажмите, чтобы закончить" : "Говорите… отпустите · ↑ закрепить · ← отмена"
    }

    /// Смахнули шар в сторону: фразу бросаем, ничего не переводим.
    func cancelRec() {
        guard recording else { return }
        recording = false; phrase = false; toggleMode = false
        liveText = ""; liveDraft = ""
        mic.stop(); session?.close(); session = nil
        Hap.note(.warning)
        hint = "Нажмите и говорите"
        Log.send("cancel", ["recMs": Log.ms(since: recStart)])
        warm()
    }

    func stopRec() {
        guard recording else { return }
        recording = false
        if haptics { if toggleMode { tapOn.impactOccurred(intensity: 0.7) } else { tapOff.impactOccurred(intensity: 0.7) } }
        let s = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in   // хвост последнего слова
            guard let self else { return }
            self.mic.stop()
            let dur = Date().timeIntervalSince(self.recStart)
            s?.stop(diag: ["frames": self.mic.frames, "ms": Int(dur * 1000), "ready": s?.ready ?? false, "native": true,
                           "warm": self.mic.lastWarm, "startMs": self.mic.lastStartMs, "peak": (self.mic.level * 1000).rounded() / 1000])
            Task { await self.finish(s, dur: dur) }
            self.warm()
        }
    }

    private func on(_ e: LiveSession.Event, _ s: LiveSession) {
        guard s === session else { return }
        switch e {
        case .live(let l, let t):
            if t != liveText { lastWord = Date() }
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

    /// Громкость с микрофона: кольца вокруг шара и «закончить по тишине».
    /// Запись закреплена, слова уже есть, и 2 с тихо — фраза сама уходит на перевод. В шумном месте, где тихо
    /// не бывает, срабатывает запасное правило: слова не дописываются 5 с.
    private func heard(_ v: Double) {
        meter.level = v
        let now = Date()
        if v > 0.3 { lastLoud = now }
        guard autoStop, recording, toggleMode, !liveText.isEmpty else { return }
        let quiet = now.timeIntervalSince(lastLoud), still = now.timeIntervalSince(lastWord)
        if (quiet > 2 && still > 1.2) || still > 5 { Log.send("autostop", ["quietMs": Int(quiet * 1000), "stillMs": Int(still * 1000)]); stopRec() }
    }

    /// Черновой перевод раз в ~0,9 с, пока человек говорит.
    private func scheduleDraft() {
        guard showDraft, draftTask == nil, liveText.split(separator: " ").count >= 3, liveText != draftText else { return }
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
        // пока ждали перевод, человек мог начать следующую фразу — тогда её экран не трогаем
        guard dur > 0.5, mic.pcm.count > 3000 else {
            hint = "Слишком коротко — держите кнопку, пока говорите"
            if s === session { liveText = ""; phrase = false; busy = false }
            return
        }
        busy = true; hint = "Перевожу…"
        defer { if s === session { busy = false; phrase = false; liveText = ""; liveDraft = "" }; voice.drain() }
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
            add(Item(id: s === session ? liveId : UUID(), mine: tr.mine, src: tr.mine ? "ru" : (tr.src.isEmpty ? flang : tr.src), to: tr.to, text: heard, out: tr.out))
        } catch {
            Log.send("err", ["at": "finish/" + path, "err": "\(error)", "waitMs": Log.ms(since: t0)])
            hint = (error as? Api.Fail)?.message == "pin" ? "Нужно войти заново" : "Нет связи — повторите"
            if (error as? Api.Fail)?.message == "pin" { logout() }
        }
    }

    /// Фразы, сказанные через Siri без открытия приложения, — в ленту. Не прозвучавшую там — озвучить здесь.
    func takeInbox() {
        let (new, speak) = Inbox.take()
        guard !new.isEmpty else { return }
        items.append(contentsOf: new); save()
        if let it = new.last, it.id == speak { voice.auto(it.id, text: it.out, lang: it.mine ? it.to : "ru") }
    }

    func add(_ it: Item) {
        items.append(it); save()
        Hap.note(.success)
        hint = "Нажмите и говорите"
        let lang = it.mine ? it.to : "ru"
        if it.mine ? autoSpeak : (speakThem && !it.photo) { voice.auto(it.id, text: it.out, lang: lang) }
        else { voice.prefetch(it.out, lang: lang) }
    }

    // MARK: текст, фото, «наоборот»
    /// Пишут текстом: слова набираются прямо в облаке в конце ленты — в нём же потом встанет перевод.
    func startTyping() {
        guard loggedIn, !phrase, !busy, !recording, !arming else { return }
        voice.stop()
        typed = ""; liveText = ""; liveDraft = ""; liveLang = ""; liveId = UUID(); typing = true
    }

    func cancelTyping() { typing = false; typed = "" }

    func sendTyped() async {
        guard typing else { return }
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        typing = false; typed = ""
        guard !t.isEmpty else { return }
        let id = liveId
        liveText = t; liveDraft = ""; liveLang = ""; phrase = true; busy = true; hint = "Перевожу…"
        defer { busy = false; if liveId == id { phrase = false; liveText = "" } }
        if voice.demo {   // показ на видео: сети нет
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            add(Item(id: id, mine: true, src: "ru", to: to, text: t, out: "Bisa bayar pakai kartu?")); return
        }
        do {
            let r = try await Api.translate(t, to: to)
            add(Item(id: liveId == id ? id : UUID(), mine: r.mine, src: r.mine ? "ru" : r.src, to: r.to, text: t, out: r.out))
        } catch {
            Log.send("err", ["at": "typed", "err": "\(error)"]); hint = "Не получилось перевести — повторите"
            // написанное не теряется: облако снова с текстом, можно нажать «Перевести» ещё раз
            if liveId == id, !recording, !arming { phrase = false; liveText = ""; typed = t; typing = true }
        }
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
