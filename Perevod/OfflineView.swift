import SwiftUI
import Translation
import Speech
import AVFoundation
import Network

/// Есть ли интернет. Пропал — поверх переводчика открывается офлайн-перевод.
@MainActor final class Net: ObservableObject {
    @Published var online = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { p in Task { @MainActor in self.online = p.status == .satisfied } }
        monitor.start(queue: .main)
    }
}

/// Язык собеседника — тот же, что выбран в переводчике (страница сообщает {t:"lang"}).
enum PartnerLang {
    static var code: String { Shared.partner }
    static func set(_ c: String) { Shared.partner = c }
    static let names: [String: String] = ["id": "индонезийский", "en": "английский", "ar": "арабский", "zh": "китайский",
        "fr": "французский", "es": "испанский", "de": "немецкий", "it": "итальянский", "tr": "турецкий", "th": "тайский",
        "vi": "вьетнамский", "ja": "японский", "ko": "корейский", "hi": "хинди", "ms": "малайский", "tl": "филиппинский",
        "pt": "португальский", "uz": "узбекский"]
    static func locale(_ c: String) -> String {
        ["ru": "ru-RU", "id": "id-ID", "en": "en-US", "ar": "ar-SA", "zh": "zh-CN", "fr": "fr-FR", "es": "es-ES", "de": "de-DE",
         "it": "it-IT", "tr": "tr-TR", "th": "th-TH", "vi": "vi-VN", "ja": "ja-JP", "ko": "ko-KR", "hi": "hi-IN", "ms": "ms-MY",
         "pt": "pt-BR"][c] ?? c
    }
}

/// Офлайн-перевод: переводчик Apple на самом айфоне (без сервера), речь — распознавание на устройстве.
struct OfflineView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var mine = true                 // true: я (русский) → собеседник
    @State private var config: TranslationSession.Configuration?
    @State private var status = ""
    @StateObject private var mic = OfflineMic()
    private let speaker = AVSpeechSynthesizer()
    private let yellow = Color(red: 1, green: 0.8, blue: 0)
    private var partner: String { PartnerLang.code }
    private var from: String { mine ? "ru" : partner }
    private var to: String { mine ? partner : "ru" }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Нет интернета — перевод на айфоне", systemImage: "wifi.slash").font(.subheadline.bold())
                Spacer()
            }
            .padding(12).background(yellow.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))

            Button { mine.toggle(); output = "" } label: {
                HStack {
                    Text(mine ? "🇷🇺 Я → \(PartnerLang.names[partner] ?? partner)" : "\(PartnerLang.names[partner] ?? partner) → 🇷🇺")
                    Image(systemName: "arrow.left.arrow.right")
                }.font(.headline).frame(maxWidth: .infinity).padding(12)
                    .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
            }.foregroundStyle(.primary)

            TextEditor(text: $input).font(.title3).frame(minHeight: 90, maxHeight: 140)
                .padding(8).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty { Text("Напиши или надиктуй…").foregroundStyle(.secondary).padding(16).allowsHitTesting(false) }
                }

            ScrollView {
                Text(output.isEmpty ? status : output).font(.system(size: output.count < 60 ? 34 : 24, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button { mic.running ? mic.stop() : mic.start(locale: PartnerLang.locale(from)) { input = $0 } } label: {
                    Image(systemName: mic.running ? "stop.fill" : "mic.fill").font(.title).frame(width: 64, height: 64)
                        .background(mic.running ? Color.red : yellow).foregroundStyle(.black).clipShape(Circle())
                }
                Button { translate() } label: {
                    Text("Перевести").font(.headline).frame(maxWidth: .infinity).frame(height: 64)
                        .background(yellow).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 16))
                }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { speak() } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title2).frame(width: 64, height: 64)
                        .background(Color(.secondarySystemBackground)).clipShape(Circle())
                }.disabled(output.isEmpty).foregroundStyle(.primary)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .onChange(of: mic.running) { _, running in if !running && !input.isEmpty { translate() } }
        .translationTask(config) { session in
            do { output = try await session.translate(input).targetText; status = "" }
            catch { output = ""; status = "Нет офлайн-пакета языка. Скачай его, пока есть интернет: Настройки → Приложения → Перевод (Apple) → Языки." }
        }
    }

    private func translate() {
        mic.stop()
        status = "Перевожу…"
        let c = TranslationSession.Configuration(source: Locale.Language(identifier: from), target: Locale.Language(identifier: to))
        if config?.source == c.source && config?.target == c.target { config?.invalidate() } else { config = c }
    }

    private func speak() {
        let u = AVSpeechUtterance(string: output)
        u.voice = AVSpeechSynthesisVoice(language: PartnerLang.locale(to))
        speaker.stopSpeaking(at: .immediate); speaker.speak(u)
    }
}

/// Диктовка без интернета: распознавание речи на самом айфоне.
@MainActor final class OfflineMic: ObservableObject {
    @Published var running = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(locale: String, onText: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            Task { @MainActor in
                guard st == .authorized, let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)), rec.isAvailable else { return }
                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
                self.request = req
                let input = self.engine.inputNode
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { b, _ in req.append(b) }
                self.engine.prepare(); try? self.engine.start()
                self.running = true
                self.task = rec.recognitionTask(with: req) { r, e in
                    Task { @MainActor in
                        if let r { onText(r.bestTranscription.formattedString) }
                        if e != nil || (r?.isFinal ?? false) { self.stop() }
                    }
                }
            }
        }
    }

    func stop() {
        guard running else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.finish()
        request = nil; task = nil; running = false
    }
}

/// Заранее скачать офлайн-пакеты Apple для пары «русский ⇄ язык собеседника» (пока есть интернет).
struct OfflinePrepView: View {
    @State private var config: TranslationSession.Configuration?
    @State private var done = ""
    var body: some View {
        VStack(spacing: 14) {
            Text("Перевод без интернета").font(.title2.bold())
            Text("Скачаю пакеты Apple для русского и языка «\(PartnerLang.names[PartnerLang.code] ?? PartnerLang.code)». Потом перевод работает даже без связи.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Скачать") {
                config = TranslationSession.Configuration(source: Locale.Language(identifier: "ru"), target: Locale.Language(identifier: PartnerLang.code))
            }.buttonStyle(.borderedProminent).tint(Color(red: 1, green: 0.8, blue: 0)).foregroundStyle(.black)
            if !done.isEmpty { Text(done) }
        }
        .padding(24)
        .translationTask(config) { session in
            do { try await session.prepareTranslation(); done = "✓ Готово — офлайн-перевод включён" }
            catch { done = "Не получилось скачать — попробуй ещё раз" }
        }
    }
}
