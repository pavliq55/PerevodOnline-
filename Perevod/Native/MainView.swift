import SwiftUI
import PhotosUI

struct MainView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var voice: Voice
    @State private var showLangs = false
    @State private var showSettings = false
    @State private var showType = false
    @State private var showConv = false
    @State private var full: Item?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoMenu = false
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            AuraBackground(rich: true)
            if m.recording || (m.busy && !m.liveText.isEmpty) { RecordingAura(active: m.recording).transition(.opacity) }
            feed
            VStack(spacing: 0) { topBar; Spacer(); bottom }
        }
        .animation(.easeInOut(duration: 0.25), value: m.recording)
        .sheet(isPresented: $showLangs) { LangPicker().environmentObject(m).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(m) }
        .sheet(isPresented: $showType) { TypeSheet().environmentObject(m).presentationDetents([.height(260)]) }
        .fullScreenCover(item: $full) { FullView(item: $0) }
        .fullScreenCover(isPresented: $showConv) { ConversationView(voice: voice).environmentObject(m) }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { img in Task { await m.translatePhoto(img) } }.ignoresSafeArea() }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, it in
            guard let it else { return }
            Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { await m.translatePhoto(img) }; photoItem = nil }
        }
        .confirmationDialog("Перевод фото", isPresented: $showPhotoMenu) {
            Button("Сфотографировать") { showCamera = true }
            Button("Из галереи") { showLibrary = true }
        }
    }

    // MARK: верх — две стеклянные капсулы, лента проходит под ними
    private var topBar: some View {
        HStack {
            HStack(spacing: 10) { Orb().frame(width: 28, height: 28); Text("Tapny").font(T.mark).foregroundStyle(T.ink) }
                .padding(.horizontal, 14).frame(height: 50).glass(Capsule(), clear: true)
            Spacer()
            GlassGroup { HStack(spacing: 4) {
                Button { showConv = true } label: { Image(systemName: "rectangle.split.1x2").frame(width: 46, height: 46) }
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 46, height: 46) }
            }.font(.system(size: 17, weight: .medium)).foregroundStyle(T.ink).padding(.horizontal, 4).frame(height: 50).glass(Capsule(), clear: true) }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    // MARK: лента
    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    Color.clear.frame(height: 66)
                    if m.items.isEmpty && !m.recording { empty }
                    ForEach(m.items.dropLast(m.items.isEmpty ? 0 : 1)) { it in row(it).contextMenu { menu(it) } }
                    if let last = m.items.last, !m.recording { latest(last).id("last") }
                    if m.recording || (m.busy && !m.liveText.isEmpty) { liveBlock.id("live") }
                    Color.clear.frame(height: 230).id("end")
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            .onChange(of: m.items.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: m.liveText) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Держите шар и говорите").font(T.big(20)).foregroundStyle(T.ink)
            Text("Вы — по-русски, собеседник — на своём. Кто говорит, Tapny поймёт сам.").font(T.text).foregroundStyle(T.dim)
        }.padding(.top, 40)
    }

    private func label(_ it: Item, latest: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(it.mine ? T.me : T.they).frame(width: 8, height: 8)
            Text((it.mine ? "Вы → \(Langs.byId(it.to).ru)" : it.photo ? "Фото → по-русски" : "Собеседник") + (latest ? " · только что" : ""))
                .font(T.label).foregroundStyle(T.dim)
        }
    }

    private func row(_ it: Item) -> some View {
        VStack(alignment: it.mine ? .trailing : .leading, spacing: 5) {
            label(it)
            Text(it.text).font(T.small).foregroundStyle(T.dim).multilineTextAlignment(it.mine ? .trailing : .leading).lineLimit(4)
            Text(it.out).font(T.text).foregroundStyle(T.ink).multilineTextAlignment(it.mine ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: it.mine ? .trailing : .leading)
        .contentShape(Rectangle()).onTapGesture { full = it }   // касание по переводу — на весь экран
        .contextMenu { menu(it) }
    }

    private func latest(_ it: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label(it, latest: true)
            Text(it.out).font(T.big(it.out.count)).foregroundStyle(T.ink).tracking(-0.5)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { full = it }
            if !it.photo { Text(it.text).font(T.small).foregroundStyle(T.dim) }
            HStack(spacing: 10) {
                chip("doc.on.doc") { UIPasteboard.general.string = it.out; UINotificationFeedbackGenerator().notificationOccurred(.success) }
                chip("arrow.up.left.and.arrow.down.right") { full = it }
                if !it.photo { chip("arrow.triangle.2.circlepath") { Task { await m.flip(it) } } }
                Spacer()
                Button { voice.say(it.id, text: it.out, lang: it.mine ? it.to : "ru") } label: {
                    Label(voice.playingId == it.id ? "Стоп" : voice.loadingId == it.id ? "Готовлю…" : "Озвучить",
                          systemImage: voice.playingId == it.id ? "stop.fill" : "speaker.wave.2.fill")
                        .font(T.ui).padding(.horizontal, 18).frame(height: 44)
                }
                .glass(Capsule(), tint: T.speakTint, clear: true)
            }
            .foregroundStyle(T.ink).padding(.top, 6)
        }
        .contextMenu { menu(it) }
    }

    @ViewBuilder private func menu(_ it: Item) -> some View {
        Button { UIPasteboard.general.string = it.out } label: { Label("Копировать перевод", systemImage: "doc.on.doc") }
        Button { UIPasteboard.general.string = it.text } label: { Label("Копировать оригинал", systemImage: "text.quote") }
        Button(role: .destructive) { m.remove(it) } label: { Label("Удалить", systemImage: "trash") }
    }

    private func chip(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44) }
            .glass(Circle(), clear: true)
    }

    // MARK: живой текст, пока говорят
    private var liveBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: m.recording).foregroundStyle(T.me)
                Text(m.recording ? (m.weakNet ? "Слабый интернет…" : "Слушаю") : "Перевожу…").font(T.ui)
                Spacer()
                if m.recording { TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(timeString(Date().timeIntervalSince(m.recStart))).font(T.ui.monospacedDigit()).foregroundStyle(T.dim) } }
            }
            .padding(.horizontal, 14).frame(height: 40).glass(Capsule(), clear: true)
            Text(m.liveText.isEmpty ? "…" : m.liveText).font(T.live).foregroundStyle(T.ink).tracking(-0.5)
                .animation(.easeOut(duration: 0.15), value: m.liveText)
            if !m.liveDraft.isEmpty { Text(m.liveDraft).font(T.text).foregroundStyle(T.dim) }
        }
    }

    private func timeString(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    // MARK: низ — языки, клавиатура · шар · камера
    private var bottom: some View {
        VStack(spacing: 14) {
            Text(m.hint).font(T.label).foregroundStyle(T.dim).frame(height: 18)
            Button { showLangs = true } label: {
                HStack(spacing: 12) {
                    Text("Русский"); Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.dim)
                    Text(m.lang.title)
                }.font(T.ui).foregroundStyle(T.ink).padding(.horizontal, 22).frame(height: 46)
            }.glass(Capsule(), clear: true)
            GlassGroup { HStack {
                Button { showType = true } label: { Image(systemName: "keyboard").font(.system(size: 19)).frame(width: 58, height: 58) }.glass(Circle(), clear: true)
                Spacer()
                MicOrb()
                Spacer()
                Button { showPhotoMenu = true } label: { Image(systemName: "camera").font(.system(size: 19)).frame(width: 58, height: 58) }.glass(Circle(), clear: true)
            }.foregroundStyle(T.ink).padding(.horizontal, 30) }
        }
        .padding(.bottom, 24)
    }
}

/// Шар-микрофон: держать — говорить, отпустить — перевод; короткое касание — «нажми ещё раз, чтобы закончить».
struct MicOrb: View {
    @EnvironmentObject var m: AppModel
    @State private var pressAt = Date()
    @State private var pressed = false
    @State private var ignoreEnd = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Orb(glow: true).frame(width: 86, height: 86)
                .scaleEffect(m.recording ? (pulse ? 1.1 : 0.96) : pressed ? 0.94 : 1)
                .animation(m.recording ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .spring(duration: 0.25), value: pulse)
            Image(systemName: m.recording ? "stop.fill" : m.busy ? "ellipsis" : "mic.fill")
                .font(.system(size: m.recording ? 24 : 28, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2)   // белый значок на жёлтом краю шара иначе теряется
                .symbolEffect(.pulse, isActive: m.busy)
        }
        .padding(8).glass(Circle(), clear: true)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !pressed else { return }
                pressed = true; pressAt = v.time   // время самого касания: если запуск записи задержится, касание не станет «удержанием»
                if m.recording { m.stopRec(); ignoreEnd = true } else { m.startRec() }
            }
            .onEnded { v in
                pressed = false
                if ignoreEnd { ignoreEnd = false; return }
                if v.time.timeIntervalSince(pressAt) < 0.35 { m.toggleMode = true; m.hint = "Говорите… нажмите, чтобы закончить" }
                else { m.stopRec() }
            })
        .onChange(of: m.recording) { _, r in pulse = r }
        .accessibilityLabel(m.recording ? "Закончить фразу" : "Говорить")
    }
}

/// Большая аура во время записи — живой свет за стеклом.
struct RecordingAura: View {
    var active: Bool
    @State private var t = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { g in
            ZStack {
                Circle().fill(AngularGradient(colors: [Color(red: 1, green: 0.79, blue: 0.24), Color(red: 1, green: 0.58, blue: 0.4),
                                                       Color(red: 0.95, green: 0.55, blue: 0.72), Color(red: 0.72, green: 0.61, blue: 1),
                                                       Color(red: 1, green: 0.79, blue: 0.24)], center: .center))
                    .frame(width: g.size.width * 1.1).blur(radius: 60).opacity(scheme == .dark ? 0.48 : 0.75)
                    .rotationEffect(.degrees(t ? 360 : 0))
                    .scaleEffect(t ? 1.06 : 0.94)
            }
            .position(x: g.size.width / 2, y: g.size.height * 0.78)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { t = true } }
    }
}
