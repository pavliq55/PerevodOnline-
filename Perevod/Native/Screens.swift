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

/// Перевод на весь экран — показать собеседнику. Текст всегда стоит НАД кнопками и занимает всё место:
/// пара слов — «плакатом» по центру; фраза — обычным начертанием от края (в строку входит больше — буквы крупнее);
/// совсем длинный текст листается. Размер подбирается сам: самый крупный, при котором всё помещается и слова не рвутся.
struct FullView: View {
    let item: Item
    @Environment(\.dismiss) var dismiss
    @State private var flipped = UserDefaults.standard.bool(forKey: "demoFlip")   // «-demoFlip YES» — снимок в облачной сборке
    var body: some View {
        ZStack {
            AuraBackground(rich: true, veil: .read)
            VStack(spacing: 14) {
                FitText(text: item.out, lang: item.mine ? item.to : "ru")
                    .rotationEffect(.degrees(flipped ? 180 : 0)).animation(.spring, value: flipped)
                    .padding(.horizontal, 22).padding(.top, 10)
                GlassGroup { HStack(spacing: 14) {
                    Button { flipped.toggle() } label: { Label("Перевернуть", systemImage: "arrow.uturn.down").font(T.ui).padding(.horizontal, 20).frame(height: 50) }.glass(Capsule(), clear: true)
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 50, height: 50) }.glass(Circle(), clear: true)
                }.foregroundStyle(T.ink) }.padding(.bottom, 14)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.height > 90 { dismiss() } })   // смахнуть вниз — закрыть
        // пока текст показывают человеку, экран не гаснет
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = Pref.bool("keepAwake", false) }
    }
}

/// Текст во всю отведённую область. Перебирает размеры от крупного к мелкому и берёт первый, с которым текст
/// помещается по высоте; ни один не подошёл — текст листается самым мелким из них (32 — всё ещё вдвое крупнее обычного).
struct FitText: View {
    let text: String
    let lang: String
    private let parts: [String]
    @Environment(\.colorScheme) private var scheme

    fileprivate struct Spec { var size: CGFloat; var poster = false; var split = false }
    private static let posterSizes: [CGFloat] = [96, 84, 72, 64, 56, 48]
    private static let readSizes: [CGFloat] = [72, 64, 58, 52, 48, 44, 40, 38, 36, 34, 32]
    private static let minSize: CGFloat = 32
    private static let rtl: Set<String> = ["ar", "he", "fa", "ur"]
    private static let noSpaces: Set<String> = ["zh", "ja", "th", "lo", "km", "my"]          // пишут без пробелов — строка рвётся где угодно
    private static let tall: Set<String> = ["th", "ar", "fa", "ur", "hi", "bn", "ta", "km", "lo", "my"]   // высокие знаки — строкам нужен воздух

    init(text: String, lang: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = t; self.lang = lang; self.parts = FitText.sentences(t)
    }

    private var code: String { String(lang.prefix(2)) }

    var body: some View {
        GeometryReader { g in
            let c = specs(g.size.width)
            ViewThatFits(in: .vertical) {
                page(c[0])
                page(c[1])
                page(c[2])
                page(c[3])
                page(c[4])
                page(c[5])
                page(c[6])
                page(c[7])
                ViewThatFits(in: .vertical) {
                    page(c[8])
                    page(c[9])
                    page(c[10])
                    page(c[11])
                    page(c[12])
                    page(c[13])
                    page(c[14])
                    page(c[15])
                    ViewThatFits(in: .vertical) {
                        page(c[16])
                        page(c[17])
                        page(c[18])
                        page(c[19])
                        page(c[20])
                        page(c[21])
                        page(c[22])
                        page(c[23])
                        LongText(step: c[24].size) { page(c[24]) }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .environment(\.layoutDirection, FitText.rtl.contains(code) ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private func page(_ s: Spec) -> some View {
        let air: CGFloat = FitText.tall.contains(code) ? 0.2 : 0
        if s.poster {
            Text(text).font(.system(size: s.size, weight: .semibold).width(.expanded)).lineSpacing(s.size * air)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6).frame(maxWidth: .infinity)
        } else {
            // в тёмной теме чуть тоньше: белое на чёрном «расплывается»
            let w: Font.Weight = scheme == .dark ? .medium : .semibold
            VStack(alignment: .leading, spacing: s.size * 0.4) {
                ForEach(Array((s.split ? parts : [text]).enumerated()), id: \.offset) { _, p in
                    Text(p).font(.system(size: s.size, weight: w)).lineSpacing(s.size * (air + 0.04))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 24 варианта «помещается целиком» по убыванию и 25-й — для прокрутки.
    private func specs(_ width: CGFloat) -> [Spec] {
        // самое широкое слово должно входить в строку целиком — иначе его разорвёт посередине
        let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(400).map(String.init)
        let free = FitText.noSpaces.contains(code) || words.isEmpty || words.contains(where: { $0.count > 26 })
        func cap(_ f: UIFont, _ room: CGFloat) -> CGFloat {
            if free { return 999 }
            var w: CGFloat = 1
            for x in words { w = max(w, (x as NSString).size(withAttributes: [.font: f]).width) }
            return (room / w * 100 * 0.97).rounded(.down)
        }
        let capP = cap(UIFont.systemFont(ofSize: 100, weight: .semibold, width: .expanded), width - 12)
        let capR = cap(UIFont.systemFont(ofSize: 100, weight: .semibold), width)
        let lo = FitText.minSize
        let r: [CGFloat] = FitText.readSizes.map { max(min($0, capR), lo) }
        var out: [Spec] = []
        if text.count <= 40 {
            // пара слов — «плакат»
            for s in FitText.posterSizes where min(s, capP) >= 48 { out.append(Spec(size: min(s, capP), poster: true)) }
            for s in r where s <= 44 { out.append(Spec(size: s)) }
        } else if parts.count < 2 {
            for s in r { out.append(Spec(size: s)) }
        } else {
            // каждое предложение с новой строки — если это стоит не больше одной ступени размера
            for i in r.indices {
                out.append(Spec(size: r[i], split: true))
                if i >= 1 { out.append(Spec(size: r[i - 1])) }
            }
            out.append(Spec(size: lo))
        }
        out = Array(out.prefix(24))
        while out.count < 24 { out.append(out.last ?? Spec(size: lo)) }
        out.append(Spec(size: lo, split: parts.count >= 2))
        return out
    }

    /// Предложения по отдельности; обрывок вроде «Да.» или «Saya…» остаётся на строке со следующим.
    private static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { (s: String?, _: Range<String.Index>, _: Range<String.Index>, _: inout Bool) in
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return }
            if let last = out.last, last.count < 16 { out[out.count - 1] = last + " " + t } else { out.append(t) }
        }
        return out.isEmpty ? [text] : out
    }
}

/// Длинный текст листается: край, за которым есть продолжение, тает, а внизу — стрелка «дальше» (листает на экран),
/// пока есть что читать: её поймёт и тот, кому телефон только что протянули.
private struct LongText<C: View>: View {
    let step: CGFloat                          // размер букв: при листании пара строк прежнего экрана остаётся видна
    @ViewBuilder var content: C
    @State private var pos = ScrollPosition(edge: .top)
    @State private var y: CGFloat = 0          // сколько прокручено
    @State private var rest: CGFloat = 100     // сколько текста ещё ниже экрана
    @State private var page: CGFloat = 400     // высота окна с текстом

    var body: some View {
        let more = rest > 6
        ScrollView { content.padding(.top, 4).padding(.bottom, 40) }
            .scrollPosition($pos)
            .scrollIndicators(.visible)
            .onScrollGeometryChange(for: [CGFloat].self) { g in
                [g.contentOffset.y.rounded(), (g.contentSize.height - g.containerSize.height - g.contentOffset.y).rounded(), g.containerSize.height.rounded()]
            } action: { _, v in
                y = v[0]; rest = v[1]; page = v[2]
            }
            // под стрелкой текста нет: строки тают выше неё
            .mask(VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(y > 6 ? 0 : 1), Color.black], startPoint: .top, endPoint: .bottom).frame(height: 36)
                Color.black
                LinearGradient(colors: [Color.black, Color.black.opacity(more ? 0 : 1)], startPoint: .top, endPoint: .bottom).frame(height: 64)
                Color.black.opacity(more ? 0 : 1).frame(height: 44)
            })
            .overlay(alignment: .bottom) {
                if more {
                    Button {
                        let to = y + min(rest, max(120, page - 108 - step * 1.3))
                        withAnimation(.smooth(duration: 0.45)) { pos.scrollTo(y: to) }
                    } label: {
                        Image(systemName: "chevron.down").font(.system(size: 19, weight: .bold)).frame(width: 50, height: 50)
                    }
                    .glass(Circle()).accessibilityLabel("Дальше").transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: more)
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
