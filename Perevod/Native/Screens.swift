import SwiftUI
import UIKit

struct LangPicker: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(Langs.all) { l in
                Button { m.to = l.id; dismiss() } label: {
                    HStack(spacing: 14) {
                        Text(l.flag).font(.title2)
                        VStack(alignment: .leading) { Text(l.title).font(T.ui).foregroundStyle(T.ink); Text(l.native).font(T.small).foregroundStyle(T.dim) }
                        Spacer()
                        if l.id == m.to { Image(systemName: "checkmark").foregroundStyle(T.me) }
                    }
                }
            }
            .navigationTitle("Язык собеседника").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TypeSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @FocusState private var focus: Bool
    var body: some View {
        VStack(spacing: 14) {
            TextField("Напишите на любом языке…", text: $text, axis: .vertical)
                .font(T.text).lineLimit(1...5).focused($focus)
                .padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            Button {
                let t = text; text = ""; dismiss()
                Task { await m.translateTyped(t) }
            } label: { Text("Перевести").font(T.ui.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 52) }
            .glass(Capsule(), tint: T.me.opacity(0.4), clear: true)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20).onAppear { focus = true }
    }
}

/// Перевод на весь экран — показать собеседнику; можно перевернуть к нему.
struct FullView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var flipped = false
    var body: some View {
        ZStack {
            AuraBackground(rich: true)
            Text(item.out).font(.system(size: 56, weight: .semibold).width(.expanded)).minimumScaleFactor(0.3)
                .multilineTextAlignment(.center).foregroundStyle(T.ink).padding(28)
                .rotationEffect(.degrees(flipped ? 180 : 0)).animation(.spring, value: flipped)
            VStack { Spacer(); GlassGroup { HStack(spacing: 14) {
                Button { flipped.toggle() } label: { Label("Перевернуть", systemImage: "arrow.uturn.down").font(T.ui).padding(.horizontal, 20).frame(height: 50) }.glass(Capsule(), clear: true)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 50, height: 50) }.glass(Circle(), clear: true)
            }.foregroundStyle(T.ink) }.padding(.bottom, 30) }
        }
    }
}

/// Разговор: телефон на столе между вами, верхняя половина — для собеседника (перевёрнута).
struct ConversationView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var voice: Voice
    @Environment(\.dismiss) var dismiss
    private var last: Item? { m.items.last }
    var body: some View {
        ZStack {
            AuraBackground(rich: true)
            VStack(spacing: 0) {
                half(text: last.map { $0.mine ? $0.out : $0.text } ?? "Говорите — я переведу", sub: last.map { $0.mine ? "Перевод" : "Вы сказали" } ?? m.lang.native)
                    .rotationEffect(.degrees(180))
                GlassGroup { HStack(spacing: 22) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 54, height: 54) }.glass(Circle(), clear: true)
                    MicOrb()
                    Button { if let l = last { voice.say(l.id, text: l.out, lang: l.mine ? l.to : "ru") } } label: {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 54, height: 54) }.glass(Circle(), clear: true)
                }.font(.system(size: 18, weight: .semibold)).foregroundStyle(T.ink) }.padding(.vertical, 10)
                half(text: m.recording ? (m.liveText.isEmpty ? "Слушаю…" : m.liveText) : last.map { $0.mine ? $0.text : $0.out } ?? "Держите шар и говорите",
                     sub: last.map { $0.mine ? "Вы сказали" : "Собеседник сказал" } ?? "Русский")
            }
        }
    }
    private func half(text: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sub).font(T.label).foregroundStyle(T.dim)
            Text(text).font(.system(size: 34, weight: .semibold).width(.expanded)).minimumScaleFactor(0.4).foregroundStyle(T.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24)
    }
}

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var prep = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Toggle("Сразу озвучивать мои фразы", isOn: $m.autoSpeak) } footer: { Text("Перевод звучит сам, без нажатия «Озвучить».") }
                Section {
                    Button("Скачать перевод без интернета") { prep = true }
                } footer: { Text("Пакеты Apple для русского и языка собеседника — потом перевод работает даже без связи.") }
                Section {
                    Button("Очистить разговор", role: .destructive) { m.clear() }
                    Link("Политика приватности", destination: URL(string: "https://perevod.molly-trade.workers.dev/privacy")!)
                }
                Section { Button("Выйти", role: .destructive) { m.logout(); dismiss() } } footer: {
                    Text("Tapny · альфа \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")") }
            }
            .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .sheet(isPresented: $prep) { OfflinePrepView().presentationDetents([.medium]) }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var m: AppModel
    @State private var pin = ""
    @State private var err = ""
    @State private var busy = false
    var body: some View {
        ZStack {
            AuraBackground(rich: true)
            VStack(alignment: .leading, spacing: 18) {
                Orb().frame(width: 64, height: 64)
                Text("Tapny").font(.system(size: 40, weight: .bold).width(.expanded)).foregroundStyle(T.ink)
                Text("Введите PIN, чтобы начать").font(T.text).foregroundStyle(T.dim)
                SecureField("PIN", text: $pin).keyboardType(.numberPad).textContentType(.password).font(.system(size: 22, weight: .medium))
                    .padding(.horizontal, 20).frame(height: 58).glass(Capsule(), clear: true)
                if !err.isEmpty { Text(err).font(T.small).foregroundStyle(.red) }
                Button {
                    busy = true; err = ""
                    Task {
                        do { try await m.login(pin: pin) } catch { err = (error as? Api.Fail)?.message == "pin" ? "Неверный PIN" : error.localizedDescription }
                        busy = false
                    }
                } label: { Text(busy ? "Вхожу…" : "Войти").font(T.ui.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 56) }
                .glass(Capsule(), tint: T.me.opacity(0.45), clear: true).disabled(pin.count < 4 || busy)
                Spacer()
            }
            .foregroundStyle(T.ink).padding(28).padding(.top, 60)
        }
    }
}

/// Камера для перевода фото.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    func makeCoordinator() -> Coord { Coord(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let i = info[.originalImage] as? UIImage { parent.onImage(i) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { parent.dismiss() }
    }
}

/// Корень родного приложения.
struct NativeRoot: View {
    @StateObject private var m = AppModel()
    var body: some View {
        Group {
            if m.loggedIn { MainView(voice: m.voice) } else { LoginView() }
        }
        .environmentObject(m)
        .onReceive(NotificationCenter.default.publisher(for: PendingAction.note)) { _ in
            if let a = PendingAction.take() { m.handle(action: a) }
        }
        .onAppear { if let a = PendingAction.take() { m.handle(action: a) } }
    }
}
