import UIKit
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// «Поделиться» → Tapny: текст или фото из любого приложения (WhatsApp, Telegram, Safari…).
/// Чужой язык → по-русски; мой русский → на язык собеседника (как выбран в приложении).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) })
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host); host.view.frame = view.bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view); host.didMove(toParent: self)
        Task { await model.load(extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }
}

@MainActor final class ShareModel: ObservableObject {
    @Published var source = ""
    @Published var out = ""
    @Published var state = "Перевожу…"
    @Published var mine = false
    private var to = "ru"
    private var player: AVAudioPlayer?
    let close: () -> Void
    init(close: @escaping () -> Void) { self.close = close }

    func load(_ items: [NSExtensionItem]) async {
        guard let token = Shared.token else { state = "Открой приложение Tapny и войди один раз — потом перевод будет работать и отсюда."; return }
        let providers = items.flatMap { $0.attachments ?? [] }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
           let img = await loadImage(p) {
            source = "📷 Фото"; state = "Читаю текст на фото…"
            await send(path: "/api/photo", token: token, body: jpeg(img), type: "image/jpeg") { d in (d["out"] as? String, "ru") }
            return
        }
        var text = ""
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
           let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { text = t }
        else if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
                let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { text = u.absoluteString }
        text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !text.isEmpty else { state = "Здесь нет текста для перевода"; return }
        source = text
        let body = try? JSONSerialization.data(withJSONObject: ["text": text, "to": Shared.partner])
        await send(path: "/api/tr", token: token, body: body, type: "application/json") { d in
            self.mine = (d["mine"] as? Bool) ?? false
            return (d["out"] as? String, (d["to"] as? String) ?? "ru")
        }
    }

    private func send(path: String, token: String, body: Data?, type: String, parse: ([String: Any]) -> (String?, String)) async {
        var r = URLRequest(url: Shared.base.appendingPathComponent(path)); r.httpMethod = "POST"; r.httpBody = body
        r.setValue(token, forHTTPHeaderField: "X-Pin"); r.setValue(type, forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 40
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            if (resp as? HTTPURLResponse)?.statusCode == 401 { state = "Ключ устарел (сменили PIN) — открой приложение Tapny и войди снова."; return }
            let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let (o, lang) = parse(d)
            if let o, !o.isEmpty { out = o; to = lang; state = "" } else { state = (d["error"] as? String) ?? "Не получилось перевести" }
        } catch { state = "Нет связи — попробуй ещё раз" }
    }

    func copy() { UIPasteboard.general.string = out; UINotificationFeedbackGenerator().notificationOccurred(.success) }

    func speak() {
        guard let token = Shared.token, !out.isEmpty else { return }
        var c = URLComponents(url: Shared.base.appendingPathComponent("/api/tts"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "l", value: to), URLQueryItem(name: "q", value: String(out.prefix(900)))]
        var r = URLRequest(url: c.url!); r.setValue(token, forHTTPHeaderField: "X-Pin")
        Task {
            guard let (data, _) = try? await URLSession.shared.data(for: r) else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: data); player?.play()
        }
    }

    private func loadImage(_ p: NSItemProvider) async -> UIImage? {
        guard let item = try? await p.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let i = item as? UIImage { return i }
        if let u = item as? URL, let d = try? Data(contentsOf: u) { return UIImage(data: d) }
        if let d = item as? Data { return UIImage(data: d) }
        return nil
    }

    private func jpeg(_ img: UIImage) -> Data? {
        let k = min(1, 1280 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1   // иначе снимок выходит втрое крупнее (экран ×3) — и втрое дольше уходит
        let small = UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.75)
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    private let yellow = Color(red: 1, green: 0.8, blue: 0)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.mine ? "Я → собеседнику" : "Перевод → 🇷🇺").font(.headline)
                Spacer()
                Button("Готово") { model.close() }.font(.headline).foregroundStyle(yellow)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.out.isEmpty {
                        Text(model.state).font(.title3).foregroundStyle(.secondary)
                    } else {
                        Text(model.out).font(.system(size: model.out.count < 80 ? 30 : 22, weight: .bold)).textSelection(.enabled)
                    }
                    if !model.source.isEmpty { Text(model.source).font(.callout).foregroundStyle(.secondary).lineLimit(6) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.out.isEmpty {
                HStack(spacing: 12) {
                    Button { model.copy() } label: { Label("Копировать", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 14) }
                        .background(yellow).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 14))
                    Button { model.speak() } label: { Label("Озвучить", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity).padding(.vertical, 14) }
                        .background(Color(.secondarySystemBackground)).foregroundStyle(.primary).clipShape(RoundedRectangle(cornerRadius: 14))
                }.font(.headline)
            }
        }
        .padding(20)
    }
}
