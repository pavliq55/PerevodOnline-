import SwiftUI
import SafariServices

/// Согласие при первом запуске (правило Apple 5.1.2(i)): куда уходят голос, текст и фото — до первой отправки.
struct ConsentView: View {
    var onAgree: () -> Void
    @State private var showPolicy = false
    private let yellow = T.me

    var body: some View {
        ZStack { AuraBackground(veil: .center); ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Orb().frame(width: 64, height: 64)
                    .padding(.top, 40)
                Text("Перед началом").font(.system(size: 34, weight: .bold).width(.expanded))
                Text("Чтобы переводить, Tapny отправляет то, что вы сами даёте на перевод, на наш сервер и в сервисы распознавания и перевода.")
                    .font(.body)
                row("mic.fill", "Голос", "Только пока вы держите кнопку микрофона. → Deepgram, Groq — распознавание речи.")
                row("text.bubble.fill", "Текст", "Распознанный или введённый текст. → Groq — перевод; Google, Deepgram, Gemini — озвучка.")
                row("camera.fill", "Фото", "Только выбранное для перевода. → Groq — чтение текста на фото.")
                row("lock.fill", "Хранение", "Записи и фото не хранятся. Служебный журнал — до 24 часов. История переводов — только на вашем телефоне.")
                row("hand.raised.fill", "Без рекламы и слежки", "Данные не продаются и не используются для рекламы.")
                Button("Подробнее — политика приватности") { showPolicy = true }
                    .font(.callout).foregroundStyle(yellow)
                Button(action: onAgree) {
                    Text("Согласен, продолжить").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(T.warm).foregroundStyle(T.onWarm).clipShape(Capsule())
                }
                .padding(.top, 8)
                Text("Отозвать согласие можно, удалив приложение.").font(.footnote).foregroundStyle(T.dim)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24).foregroundStyle(T.ink)
        } }
        .sheet(isPresented: $showPolicy) { SafariView(url: URL(string: "https://perevod.molly-trade.workers.dev/privacy")!) }
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(yellow).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(T.dim)
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// Открыть ссылку внутри приложения (политика приватности из настроек переводчика).
@MainActor func presentSafari(_ url: URL) {
    guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
    var top = root; while let p = top.presentedViewController { top = p }
    top.present(SFSafariViewController(url: url), animated: true)
}
