import Foundation
import AVFoundation
import UIKit

/// Онлайн-распознавание: звук 16 кГц μ-law по WebSocket на /api/live (тот же протокол, что у сайта).
/// Сервер: Deepgram (живые слова) → по «стоп» Aqua (чистовой текст) → перевод → голос следом.
@MainActor final class LiveSession {
    enum Event { case ready, live(lang: String, text: String), stopping, final([String: Any]), voice(Data), error(String), closed }

    private var task: URLSessionWebSocketTask?
    private(set) var ready = false
    private var queue: [Data] = []
    private var stopRequested = false
    let born = Date()
    var lastSeen = Date()
    var dead = false
    var onEvent: ((Event) -> Void)?

    init(to: String, key: String) {
        var c = URLComponents(url: Shared.base.appendingPathComponent("/api/live"), resolvingAgainstBaseURL: false)!
        c.scheme = "wss"
        let t = URLSession.shared.webSocketTask(with: c.url!)
        task = t
        t.resume()
        var hello: [String: Any] = ["pin": key, "to": to, "enc": "mulaw", "v": Log.v]
        if !Api.tone.isEmpty { hello["tone"] = Api.tone }      // настройки: тон, «Мои слова», женский голос
        if !Api.gl.isEmpty { hello["gl"] = Api.gl }
        if Api.female { hello["vg"] = "f" }
        send(json: hello)
        receive()
    }

    /// Запасная сессия годится: готова и сервер недавно подавал голос (ka раз в 4 с) — или только что открыта.
    var usable: Bool {
        guard !dead else { return false }
        let age = Date().timeIntervalSince(born)
        return age < 35 && (ready ? Date().timeIntervalSince(lastSeen) < 10 : age < 3)
    }

    private func send(json: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: json), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    func sendAudio(_ d: Data) {
        if ready { task?.send(.data(d)) { _ in } } else { queue.append(d) }
    }

    func stop(diag: [String: Any]) {
        stopRequested = true
        if ready { send(json: ["t": "stop", "diag": diag]) }
    }

    func close() { dead = true; task?.cancel(with: .normalClosure, reason: nil); task = nil }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.dead = true; self.onEvent?(.closed)
                case .success(let m):
                    self.lastSeen = Date()
                    switch m {
                    case .data(let d): self.onEvent?(.voice(d))
                    case .string(let s): self.handle(s)
                    @unknown default: break
                    }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let d = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let t = j["t"] as? String else { return }
        switch t {
        case "ready":
            ready = true
            for q in queue { task?.send(.data(q)) { _ in } }
            queue.removeAll()
            if stopRequested { send(json: ["t": "stop"]) }
            onEvent?(.ready)
        case "live": onEvent?(.live(lang: j["lang"] as? String ?? "", text: j["text"] as? String ?? ""))
        case "stopping": onEvent?(.stopping)
        case "final": onEvent?(.final(j))
        case "error": dead = true; onEvent?(.error(j["err"] as? String ?? "error"))
        default: break
        }
    }
}

/// Микрофон: 16 кГц моно → μ-law (в сессию) + PCM16 (запасная запись WAV, если онлайн подведёт).
final class Mic {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private(set) var pcm = Data()
    private(set) var frames = 0
    var onChunk: ((Data) -> Void)?
    var onLevel: ((Double) -> Void)?   // громкость 0…1 во время записи — для колец вокруг шара
    private var shown = 0.0
    var running: Bool { engine.isRunning }
    // Микрофон «тёплый» (13.11.2026): холодный запуск занимал 0,3–0,5 с — съедал начало фразы, а короткое касание
    // из-за этой паузы считалось «подержал и отпустил». Теперь микрофон включается заранее (при открытии приложения
    // и на 45 с после каждой фразы), а запись начинается мгновенно и захватывает ещё 0,3 с до нажатия.
    // Пока запись не идёт, звук никуда не уходит и не хранится — только последние 0,3 с в памяти.
    private var capturing = false
    private var ring: [(raw: Data, ulaw: Data)] = []
    private var cool: DispatchWorkItem?
    private var peak: Int16 = 0
    private(set) var lastWarm = false
    private(set) var lastStartMs = 0
    var level: Double { Double(peak) / 32768 }   // громкость записи 0…1 — в журнал: тишина это или сервер не расслышал
    private static let keep: TimeInterval = 45

    init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.cooldown() }
    }

    /// Микрофон занят: идёт звонок (телефон, Telegram, WhatsApp) — айфон отдаёт микрофон только ему.
    struct Busy: Error {}

    private func run() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        // во время звонка у микрофона «пустой» формат (0 Гц) — с ним installTap роняет приложение прямо при открытии
        guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else { throw Busy() }
        converter = AVAudioConverter(from: inFmt, to: out)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { [weak self] buf, _ in self?.process(buf) }
        engine.prepare()
        try engine.start()
    }

    /// Включить микрофон заранее. Только если доступ уже разрешён — запрос доступа при открытии приложения не показываем.
    func warm() {
        guard !capturing, AVAudioApplication.shared.recordPermission == .granted else { return }
        try? run()
        sleepLater()
    }

    func start(preroll: Bool = true) throws {
        cool?.cancel()
        let t0 = Date()
        lastWarm = engine.isRunning
        pcm = Data(); frames = 0; peak = 0
        if !lastWarm { ring.removeAll(); try run() }
        lastStartMs = Int(Date().timeIntervalSince(t0) * 1000)
        capturing = true
        if preroll { for c in ring { frames += 1; pcm.append(c.raw); onChunk?(c.ulaw) } }
        ring.removeAll()
    }

    func stop() {
        capturing = false
        shown = 0; onLevel?(0)
        sleepLater()
    }

    private func sleepLater() {
        cool?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.cooldown() }
        cool = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Mic.keep, execute: w)
    }

    /// Ушли с экрана: микрофон выключить сразу, даже если шла запись.
    func off() { capturing = false; shown = 0; onLevel?(0); cooldown() }

    private func cooldown() {
        guard !capturing else { return }
        cool?.cancel(); ring.removeAll()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard let converter else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let o = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: o, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, o.frameLength > 0, let p = o.int16ChannelData?[0] else { return }
        let n = Int(o.frameLength)
        var ulaw = Data(count: n)
        ulaw.withUnsafeMutableBytes { (u: UnsafeMutableRawBufferPointer) in
            for i in 0..<n { u[i] = Mic.ulaw(p[i]) }
        }
        let raw = Data(bytes: p, count: n * 2)
        var mx: Int16 = 0
        for i in 0..<n { let a = p[i] == Int16.min ? Int16.max : abs(p[i]); if a > mx { mx = a } }
        DispatchQueue.main.async {
            guard self.capturing else {   // запись не идёт: держим только последние ~0,3 с (звук до нажатия)
                self.ring.append((raw, ulaw)); if self.ring.count > 3 { self.ring.removeFirst() }
                return
            }
            self.frames += 1
            if mx > self.peak { self.peak = mx }
            // шкала в децибелах (−50…−8 дБ → 0…1): тихая речь уже заметна; вверх — сразу, вниз — плавно
            let db = 20 * log10(max(Double(mx) / 32768, 0.0001))
            self.shown = max(min(max((db + 50) / 42, 0), 1), self.shown * 0.7)
            self.onLevel?(self.shown)
            if self.pcm.count < 16000 * 2 * 120 { self.pcm.append(raw) }
            self.onChunk?(ulaw)
        }
    }

    /// μ-law (G.711) — как на сайте: вдвое меньше данных, точность Deepgram та же.
    static func ulaw(_ sample: Int16) -> UInt8 {
        var s = Int32(sample)
        let sign: Int32 = s < 0 ? 0x80 : 0
        if s < 0 { s = -s }
        s = min(s, 32635) + 0x84
        var e: Int32 = 7
        var mask: Int32 = 0x4000
        while (s & mask) == 0 && e > 0 { e -= 1; mask >>= 1 }
        return UInt8(truncatingIfNeeded: ~(sign | (e << 4) | ((s >> (e + 3)) & 0x0F)) & 0xFF)
    }

    /// WAV из записанного PCM16 — для запасного распознавания (/api/stt).
    func wav() -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
