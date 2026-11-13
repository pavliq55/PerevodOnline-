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
                .padding(16).background(T.field, in: RoundedRectangle(cornerRadius: 20))
            Button {
                let t = text; text = ""; dismiss()
                Task { await m.translateTyped(t) }
            } label: { Text("Перевести").font(T.ui.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 52) }
            .glass(Capsule(), tint: T.goTint, clear: true)
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
            AuraBackground(rich: true, veil: .center)
            Text(item.out).font(.system(size: 56, weight: .semibold).width(.expanded)).minimumScaleFactor(0.3)
                .multilineTextAlignment(.center).foregroundStyle(T.ink).padding(28)
                .rotationEffect(.degrees(flipped ? 180 : 0)).animation(.spring, value: flipped)
            VStack { Spacer(); GlassGroup { HStack(spacing: 14) {
                Button { flipped.toggle() } label: { Label("Перевернуть", systemImage: "arrow.uturn.down").font(T.ui).padding(.horizontal, 20).frame(height: 50) }.glass(Capsule(), clear: true)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 50, height: 50) }.glass(Circle(), clear: true)
            }.foregroundStyle(T.ink) }.padding(.bottom, 30) }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.height > 90 { dismiss() } })   // смахнуть вниз — закрыть
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
            AuraBackground(rich: true, veil: .center)
            VStack(spacing: 0) {
                half(text: last.map { $0.mine ? $0.out : $0.text } ?? "Говорите — я переведу", sub: last.map { $0.mine ? "Перевод" : "Вы сказали" } ?? m.lang.native)
                    .rotationEffect(.degrees(180))
                GlassGroup { HStack(spacing: 22) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 54, height: 54) }.glass(Circle(), clear: true)
                    MicOrb()
                    Button { if let l = last { voice.say(l.id, text: l.out, lang: l.mine ? l.to : "ru") } } label: {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 54, height: 54) }.glass(Circle(), clear: true)
                }.font(.system(size: 18, weight: .semibold)).foregroundStyle(T.ink) }.padding(.vertical, 10)
                half(text: m.phrase ? (m.liveText.isEmpty ? (m.recording ? "Слушаю…" : "Перевожу…") : m.liveText) : last.map { $0.mine ? $0.text : $0.out } ?? "Держите шар и говорите",
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

/// Настройки. Всё применяется сразу и хранится на айфоне; тон, «Мои слова» и женский голос уходят на сервер с каждой фразой.
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var prep = false
    // «-demoSettings 1…3» — снимки в облачной сборке: верх списка, низ списка, «Мои слова»
    private let demo = UserDefaults.standard.integer(forKey: "demoSettings")
    @State private var demoWords = UserDefaults.standard.integer(forKey: "demoSettings") == 3

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    sound
                    orb
                    screen
                    translation
                    history
                    Section {
                        Link("Политика приватности", destination: URL(string: "https://perevod.molly-trade.workers.dev/privacy")!)
                        Button("Выйти", role: .destructive) { m.logout(); dismiss() }.id("end")
                    } footer: {
                        Text("Tapny · альфа \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                    }
                }
                .onAppear { if demo == 2 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo("end", anchor: .bottom) } } }
            }
            .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .navigationDestination(isPresented: $demoWords) { WordsView() }
            .sheet(isPresented: $prep) { OfflinePrepView().presentationDetents([.medium]) }
        }
    }

    private var sound: some View {
        Section {
            Toggle("Сразу озвучивать мои фразы", isOn: $m.autoSpeak)
            Toggle("Озвучивать собеседника", isOn: $m.speakThem)
            Picker("Скорость голоса", selection: $m.voiceSpeed) { Text("Медленнее").tag(0); Text("Обычно").tag(1); Text("Быстрее").tag(2) }
            Picker("Голос", selection: $m.voiceFemale) { Text("Мужской").tag(false); Text("Женский").tag(true) }
            Picker("Куда звучит", selection: $m.output) { Text("Авто").tag(0); Text("Динамик").tag(1); Text("К уху").tag(2) }
        } header: { Text("Голос и звук") } footer: {
            Text("Авто — в наушники, если они подключены, иначе в громкий динамик. «Динамик» — всегда вслух, даже с наушниками. «К уху» — тихо, как при звонке.")
        }
    }

    private var orb: some View {
        Section {
            Picker("Шар", selection: $m.orbMode) { Text("Держать или нажать").tag(0); Text("Только держать").tag(1); Text("Только нажать").tag(2) }
            Toggle("Заканчивать по тишине", isOn: $m.autoStop)
            Toggle("Вибрация", isOn: $m.haptics)
        } header: { Text("Шар и запись") } footer: {
            Text("По тишине: запись закреплена (нажали шар или потянули его вверх), вы замолчали на 2 секунды — фраза сама уходит на перевод.")
        }
    }

    private var screen: some View {
        Section {
            Picker("Размер текста", selection: $m.textBig) { Text("Обычный").tag(false); Text("Крупный").tag(true) }
            Picker("Тема", selection: $m.theme) { Text("Как в айфоне").tag(0); Text("Светлая").tag(1); Text("Тёмная").tag(2) }
            Toggle("Не гасить экран", isOn: $m.keepAwake)
            Toggle("Черновой перевод, пока говорю", isOn: $m.showDraft)
        } header: { Text("Экран") }
    }

    private var translation: some View {
        Section {
            Picker("Тон", selection: $m.casual) { Text("Вежливо").tag(false); Text("По-простому").tag(true) }
            NavigationLink { WordsView() } label: { LabeledContent("Мои слова", value: m.words.isEmpty ? "нет" : "\(m.words.count)") }
            Button("Скачать перевод без интернета") { prep = true }
        } header: { Text("Перевод") } footer: {
            Text("Тон — как обращаться к собеседнику: на «вы» или по-дружески. Мои слова — имена и названия, которые надо переводить по-вашему. Без интернета — пакеты Apple для русского и языка собеседника.")
        }
    }

    private var history: some View {
        Section {
            Picker("Хранить", selection: $m.keep) { Text("60 фраз").tag(60); Text("300 фраз").tag(300); Text("Не хранить").tag(0) }
            ShareLink(item: m.exportText) { Text("Выгрузить разговор") }.disabled(m.items.isEmpty)
            Button("Очистить разговор", role: .destructive) { m.clear() }
        } header: { Text("История") } footer: {
            Text("«Не хранить» — разговор виден, пока приложение открыто, и на айфон не записывается.")
        }
    }
}

/// «Мои слова»: имена, названия и слова, которые надо переводить по-своему. Уходят на сервер с каждой фразой.
struct WordsView: View {
    @EnvironmentObject var m: AppModel
    @State private var list: [Word] = []
    private static let demo = UserDefaults.standard.integer(forKey: "demoSettings") == 3

    var body: some View {
        Form {
            Section {
                ForEach($list) { $w in
                    HStack(spacing: 10) {
                        TextField("Слово", text: $w.a)
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.dim)
                        TextField("Как переводить", text: $w.b)
                    }
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                .onDelete { list.remove(atOffsets: $0) }
                if list.count < 40 { Button { list.append(Word()) } label: { Label("Добавить слово", systemImage: "plus") } }
            } footer: {
                Text("Слева — как вы говорите, справа — как переводить. Например: «Маша → Mbak Masha», «Чангу → Canggu». Правое поле пустое — слово останется как есть. Убрать строку — смахните её влево.")
            }
        }
        .navigationTitle("Мои слова").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            list = m.words
            if Self.demo, list.isEmpty { list = [Word(a: "Маша", b: "Mbak Masha"), Word(a: "Чангу", b: "Canggu"), Word(a: "Tapny", b: "")] }
        }
        .onDisappear {
            func clean(_ x: String) -> String { x.trimmingCharacters(in: .whitespacesAndNewlines) }
            let new = list.map { Word(id: $0.id, a: clean($0.a), b: clean($0.b)) }.filter { !$0.a.isEmpty }
            if !Self.demo, new != m.words { m.words = new }
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
            AuraBackground(rich: true, veil: .none)
            VStack(alignment: .leading, spacing: 18) {
                Orb().frame(width: 64, height: 64)
                Text("Tapny").font(.system(size: 40, weight: .bold).width(.expanded)).foregroundStyle(T.ink)
                Text("Введите PIN, чтобы начать").font(T.text).foregroundStyle(T.dim)
                SecureField("PIN", text: $pin).keyboardType(.numberPad).textContentType(.password).font(.system(size: 22, weight: .medium))
                    .padding(.horizontal, 20).frame(height: 58).glass(Capsule(), clear: true)
                if !err.isEmpty { Text(err).font(T.small).foregroundStyle(T.err) }
                Button {
                    busy = true; err = ""
                    Task {
                        do { try await m.login(pin: pin) } catch { err = (error as? Api.Fail)?.message == "pin" ? "Неверный PIN" : error.localizedDescription }
                        busy = false
                    }
                } label: { Text(busy ? "Вхожу…" : "Войти").font(T.ui.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 56) }
                .glass(Capsule(), tint: T.goTint, clear: true).disabled(pin.count < 4 || busy)
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
        .onAppear {
            if let a = PendingAction.take() { m.handle(action: a) }
            // тема из настроек; «-demoTheme N» — только для снимка в облачной сборке
            let demo = UserDefaults.standard.integer(forKey: "demoTheme")
            let th = demo > 0 ? demo : m.theme
            Look.apply(th); DispatchQueue.main.async { Look.apply(th) }
        }
    }
}
