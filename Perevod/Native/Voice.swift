import Foundation
import AVFoundation

/// Готовый проигрыватель едет с рабочей очереди на главную.
private final class Box<T>: @unchecked Sendable { let v: T; init(_ v: T) { self.v = v } }

/// Озвучка: голос с сервера (Google / Deepgram / Piper / Gemini), очередь для автоозвучки, кэш последних.
@MainActor final class Voice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingId: UUID?
    @Published private(set) var loadingId: UUID?
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]
    private var order: [String] = []
    private var queue: [(UUID, String, String)] = []
    var blocked: () -> Bool = { false }      // идёт запись — не говорить
    var rate: Float = 1.12                   // скорость голоса («Скорость» в настройках)
    var demo = false                         // показ на видео: сети нет — голос «готовится» 1,2 с, потом звучит короткий тон
    private var seq = 0                      // номер запуска: пока звук готовился, могли нажать «стоп» или другую реплику
    private static let bg = DispatchQueue(label: "voice.start", qos: .userInitiated)

    private func key(_ t: String, _ l: String) -> String { l + "|" + t }

    func has(_ text: String, _ lang: String) -> Bool { cache[key(text, lang)] != nil }
    func put(_ data: Data, text: String, lang: String) {
        let k = key(text, lang); cache[k] = data; order.append(k)
        if order.count > 12 { cache[order.removeFirst()] = nil }
    }
    /// Сменили голос — скачанное прежним голосом больше не нужно.
    func flush() { cache = [:]; order = [] }

    func prefetch(_ text: String, lang: String) {
        guard !demo, cache[key(text, lang)] == nil else { return }
        Task { if let d = try? await Api.voice(text, lang: lang) { put(d, text: text, lang: lang) } }
    }

    /// Озвучить сейчас (кнопка). Повторное нажатие во время звучания — стоп.
    func say(_ id: UUID, text: String, lang: String) {
        if playingId == id { stop(); return }
        if loadingId == id { return }                // голос ещё готовится — нажатие его не отменяет
        stop()
        play(id, text, lang)
    }

    /// Автоозвучка: если уже звучит или идёт запись — в очередь, не теряется (старше 30 с — выкинуть).
    func auto(_ id: UUID, text: String, lang: String) {
        if blocked() || playingId != nil || loadingId != nil { queue.append((id, text, lang)); prefetch(text, lang: lang); return }
        if cache[key(text, lang)] != nil { play(id, text, lang); return }
        // голос обычно приходит с сервера следом за переводом (0,2–0,5 с) — ждём его, а не качаем второй раз
        queue.append((id, text, lang))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.drain() }
    }

    func drain() {
        guard !blocked(), playingId == nil, loadingId == nil, !queue.isEmpty else { return }
        let (id, t, l) = queue.removeFirst()
        play(id, t, l)
    }

    func stop() {
        seq += 1
        player?.stop(); player = nil; playingId = nil; loadingId = nil
    }

    private func play(_ id: UUID, _ text: String, _ lang: String) {
        if demo {
            loadingId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.loadingId == id else { return }
                self.loadingId = nil; self.start(id, Voice.tone)
            }
            return
        }
        if let d = cache[key(text, lang)] { start(id, d); Log.send("voice", ["src": "cache", "lang": lang, "kb": d.count / 1024]); return }
        loadingId = id
        let t0 = Date()
        Task {
            do {
                let d = try await Api.voice(text, lang: lang)
                put(d, text: text, lang: lang)
                Log.send("voice", ["src": "net", "lang": lang, "kb": d.count / 1024, "ms": Log.ms(since: t0), "played": loadingId == id])
                if loadingId == id { loadingId = nil; start(id, d) }
            } catch {
                Log.send("err", ["at": "voice", "lang": lang, "err": "\(error)", "ms": Log.ms(since: t0)])
                if loadingId == id { loadingId = nil; drain() }
            }
        }
    }

    /// Звук запускается не на главной очереди: включение звука айфона занимает до 0,3 с, и экран на это время
    /// замирал — реплика, которую смахнули вправо, оставалась сдвинутой. Кнопка сразу показывает «Стоп».
    private func start(_ id: UUID, _ d: Data) {
        seq += 1
        let n = seq, r = rate, t0 = Date()
        playingId = id
        Voice.bg.async { @Sendable in
            Audio.setup()
            let p = try? AVAudioPlayer(data: d)
            if let p { p.delegate = self; p.enableRate = true; p.rate = r; p.prepareToPlay() }
            let ok = p?.play() ?? false
            let box = Box(p), ms = Log.ms(since: t0)
            Task { @MainActor in
                guard n == self.seq else { box.v?.stop(); return }   // уже нажали «стоп» или другую реплику
                if ok { self.player = box.v; if ms > 250 { Log.send("voice", ["src": "start", "ms": ms]) }; return }
                Log.send("err", ["at": "player", "err": box.v == nil ? "не открылся звук" : "play вернул false", "kb": d.count / 1024])
                self.playingId = nil; self.drain()
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        if !flag { Log.send("err", ["at": "player", "err": "звук оборвался"]) }
        let done = ObjectIdentifier(p)
        Task { @MainActor in
            // звук, который уже остановили, новую реплику не трогает
            guard let cur = self.player, ObjectIdentifier(cur) == done else { return }
            self.playingId = nil; self.player = nil; self.drain()
        }
    }

    /// Короткий мягкий тон (WAV) — вместо голоса при показе на видео.
    private static let tone: Data = Voice.makeTone()
    nonisolated private static func makeTone() -> Data {
        let sr: Int = 16000
        let n: Int = sr * 2
        var d = Data()
        func u32(_ v: Int) { var x: UInt32 = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x: UInt16 = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(36 + n * 2); d.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(n * 2)
        let step: Double = 2.0 * Double.pi * 440.0 / Double(sr)
        for i in 0..<n {
            let v: Double = sin(Double(i) * step) * 2500.0
            var x: Int16 = Int16(v).littleEndian
            d.append(Data(bytes: &x, count: 2))
        }
        return d
    }
}
