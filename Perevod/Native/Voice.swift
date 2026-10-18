import Foundation
import AVFoundation

/// Озвучка: голос с сервера (Google / Deepgram / Piper / Gemini), очередь для автоозвучки, кэш последних.
@MainActor final class Voice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingId: UUID?
    @Published private(set) var loadingId: UUID?
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]
    private var order: [String] = []
    private var queue: [(UUID, String, String)] = []
    var blocked: () -> Bool = { false }      // идёт запись — не говорить

    private func key(_ t: String, _ l: String) -> String { l + "|" + t }

    func has(_ text: String, _ lang: String) -> Bool { cache[key(text, lang)] != nil }
    func put(_ data: Data, text: String, lang: String) {
        let k = key(text, lang); cache[k] = data; order.append(k)
        if order.count > 12 { cache[order.removeFirst()] = nil }
    }

    func prefetch(_ text: String, lang: String) {
        guard cache[key(text, lang)] == nil else { return }
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
        player?.stop(); player = nil; playingId = nil; loadingId = nil
    }

    private func play(_ id: UUID, _ text: String, _ lang: String) {
        if let d = cache[key(text, lang)] { start(id, d); return }
        loadingId = id
        Task {
            do {
                let d = try await Api.voice(text, lang: lang)
                put(d, text: text, lang: lang)
                if loadingId == id { loadingId = nil; start(id, d) }
            } catch { if loadingId == id { loadingId = nil; drain() } }
        }
    }

    private func start(_ id: UUID, _ d: Data) {
        Audio.setup()
        guard let p = try? AVAudioPlayer(data: d) else { drain(); return }
        p.delegate = self; p.enableRate = true; p.rate = 1.12
        player = p; playingId = id
        p.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingId = nil; self.player = nil; self.drain() }
    }
}
