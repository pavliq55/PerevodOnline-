import Foundation
import AVFoundation

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
        send(json: ["pin": key, "to": to, "enc": "mulaw"])
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
    var running: Bool { engine.isRunning }

    func start() throws {
        pcm = Data(); frames = 0
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFmt, to: out)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { [weak self] buf, _ in self?.process(buf) }
        engine.prepare()
        try engine.start()
    }

    func stop() {
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
        DispatchQueue.main.async {
            self.frames += 1
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
