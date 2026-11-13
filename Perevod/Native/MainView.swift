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
    @State private var tail: UUID?             // последняя реплика, которую лента уже показала
    @State private var pull = PullUp()         // лента потянута вверх за нижний край

    var body: some View {
        ZStack {
            AuraBackground(rich: true)
            ZStack { if m.phrase { RecordingAura(active: m.recording).transition(.opacity) } }
                .animation(.easeInOut(duration: 0.3), value: m.phrase)
            feed
            VStack(spacing: 0) { topBar; Spacer(); bottom }
        }
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
    // Лента «стоит на нижнем крае»: новое появляется внизу на своём месте, старое плавно уходит вверх.
    // Прошлый перевод остаётся крупным, пока не готов новый, — экран меняется один раз за фразу.
    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 66)
                    if m.items.isEmpty && !m.phrase { empty }
                    ForEach(m.items) { it in
                        SwipeRow(onDelete: { withAnimation(.smooth(duration: 0.32)) { m.remove(it) } },
                                 onSpeak: { voice.say(it.id, text: it.out, lang: it.mine ? it.to : "ru") }) {
                            if it.id == m.big { latest(it) } else { row(it) }
                        }
                        .transition(.opacity)
                    }
                    if m.phrase { liveBlock.padding(.horizontal, 8).padding(.top, 10).transition(.asymmetric(insertion: .opacity, removal: .identity)) }   // уходит сразу: на его месте уже готовый перевод
                    Color.clear.frame(height: 230).overlay(alignment: .top) { PullHint(pull: pull) }.id("end")
                }
                .padding(.horizontal, 14)
                .animation(.smooth(duration: 0.35), value: m.phrase)
                .animation(.smooth(duration: 0.35), value: m.items.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .onChange(of: m.phrase) { _, on in if on { withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("end", anchor: .bottom) } } }
            // к нижнему краю ведём только за новой репликой; удаление и возврат реплики ленту не двигают
            .onChange(of: m.items.count) { was, now in
                if now > was, m.items.last?.id != tail { withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("end", anchor: .bottom) } }
                tail = m.items.last?.id
            }
            .onAppear { tail = m.items.last?.id }
            // потянуть ленту вверх за нижний край и отпустить — последний перевод на весь экран (смахнуть вниз — закрыть)
            .onScrollGeometryChange(for: CGFloat.self) { g in
                max(0, (g.contentOffset.y + g.containerSize.height - g.contentInsets.bottom - g.contentSize.height).rounded())
            } action: { _, v in
                pull.v = pull.held && !m.phrase && !m.items.isEmpty ? v : 0
            }
            .onScrollPhaseChange { was, now in
                pull.held = now == .interacting
                guard was == .interacting, now != .interacting else { return }
                if pull.v >= PullUp.arm, !m.phrase, let it = m.items.last { full = it }
                pull.v = 0
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Держите шар и говорите").font(T.big(20)).foregroundStyle(T.ink)
            Text("Вы — по-русски, собеседник — на своём. Кто говорит, Tapny поймёт сам.").font(T.text).foregroundStyle(T.dim)
        }.padding(.top, 40).padding(.horizontal, 8)
    }

    /// «Облако» реплики, как в мессенджере: мои — справа, собеседника — слева.
    private func bubble<V: View>(_ it: Item, side: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return content()
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background { ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(it.mine ? T.bubbleMe : T.bubbleThey)
                shape.strokeBorder(T.bubbleLine, lineWidth: 0.6)
            } }
            .contentShape(shape)
            .frame(maxWidth: .infinity, alignment: it.mine ? .trailing : .leading)
            .padding(it.mine ? .leading : .trailing, side)
    }

    private func label(_ it: Item, latest: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(it.mine ? T.me : T.they).frame(width: 8, height: 8)
            Text((it.mine ? "Вы → \(Langs.byId(it.to).ru)" : it.photo ? "Фото → по-русски" : "Собеседник") + (latest ? " · только что" : ""))
                .font(T.label).foregroundStyle(T.dim)
        }
    }

    private func row(_ it: Item) -> some View {
        bubble(it, side: 48) {
            VStack(alignment: .leading, spacing: 5) {
                label(it)
                Text(it.text).font(T.small).foregroundStyle(T.dim).lineLimit(4)
                Text(it.out).font(T.text).foregroundStyle(T.ink)
            }
        }
        .onTapGesture { full = it }   // касание по переводу — на весь экран
        .contextMenu { menu(it) }
        .transition(.opacity)
    }

    private func latest(_ it: Item) -> some View {
        bubble(it, side: 22) {
            VStack(alignment: .leading, spacing: 10) {
                label(it, latest: true)
                Text(it.out).font(T.big(it.out.count)).foregroundStyle(T.ink).tracking(-0.5)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { full = it }
                if !it.photo { Text(it.text).font(T.small).foregroundStyle(T.dim) }
                HStack(spacing: 8) {
                    chip("doc.on.doc") { UIPasteboard.general.string = it.out; UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    if !it.photo { chip("arrow.triangle.2.circlepath") { Task { await m.flip(it) } } }
                    Spacer()
                    Button { voice.say(it.id, text: it.out, lang: it.mine ? it.to : "ru") } label: {
                        Label(voice.playingId == it.id ? "Стоп" : voice.loadingId == it.id ? "Готовлю…" : "Озвучить",
                              systemImage: voice.playingId == it.id ? "stop.fill" : "speaker.wave.2.fill")
                            .font(T.ui).frame(minWidth: 104).padding(.horizontal, 16).frame(height: 42)   // ширина не прыгает при смене надписи
                            .background(Capsule().fill(T.speakTint))
                    }
                }
                .foregroundStyle(T.ink).padding(.top, 4)
            }
        }
        .contextMenu { menu(it) }
        .transition(.opacity)
    }

    @ViewBuilder private func menu(_ it: Item) -> some View {
        Button { UIPasteboard.general.string = it.out } label: { Label("Копировать перевод", systemImage: "doc.on.doc") }
        Button { UIPasteboard.general.string = it.text } label: { Label("Копировать оригинал", systemImage: "text.quote") }
        Button(role: .destructive) { m.remove(it) } label: { Label("Удалить", systemImage: "trash") }
    }

    private func chip(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 42, height: 42).background(Circle().fill(T.field)) }
    }

    // MARK: живой текст, пока говорят
    // Отдельной плашки «Слушаю» нет: состояние показывает сам шар — кольца в такт голосу и время внутри,
    // пока ждём перевод — бегущая дуга; слова — в строке подсказки над языками.
    private var liveBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            // место под три строки текста и черновик занято заранее: пока говорят, слова дописываются, а экран стоит
            Text(m.liveText.isEmpty ? "…" : m.liveText).font(T.live).foregroundStyle(T.ink).tracking(-0.5)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            Text(m.liveDraft.isEmpty ? " " : m.liveDraft).font(T.text).foregroundStyle(T.dim)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .transaction(value: m.liveText) { $0.animation = nil }
        .transaction(value: m.liveDraft) { $0.animation = nil }
    }

    // MARK: низ — языки, клавиатура · шар · камера
    private var bottom: some View {
        VStack(spacing: 14) {
            ZStack {
                if m.undo != nil {
                    Button { withAnimation(.smooth(duration: 0.32)) { m.restore() } } label: {
                        Label("Удалено · Вернуть", systemImage: "arrow.uturn.backward").font(T.label).foregroundStyle(T.ink).padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(T.field))
                    }.transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text(m.recording && m.weakNet ? "Слабый интернет…" : m.hint).font(T.label).foregroundStyle(T.dim).transition(.opacity)
                }
            }
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.22), value: m.undo != nil)
            Button { showLangs = true } label: {
                HStack(spacing: 12) {
                    Text("Русский"); Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.dim)
                    Text(m.lang.title).contentTransition(.opacity)
                }.font(T.ui).foregroundStyle(T.ink).padding(.horizontal, 22).frame(height: 46)
            }.glass(Capsule(), clear: true)
            // свайп по полоске — вернуть прошлый язык собеседника
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
                if abs(v.translation.width) > 40, abs(v.translation.width) > abs(v.translation.height) * 1.5 { withAnimation(.spring(duration: 0.3)) { m.swapLang() } }
            })
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

/// Насколько лента потянута вверх за нижний край, пока её держит палец.
/// Отдельный объект: за ним следит только подсказка, лента на каждый кадр не перерисовывается.
final class PullUp: ObservableObject {
    @Published var v: CGFloat = 0
    var held = false
    static let arm: CGFloat = 52               // дотянули — отпустить, и перевод откроется крупно
}

/// Подсказка под последней репликой: выезжает вместе с лентой, когда её тянут вверх за край.
private struct PullHint: View {
    @ObservedObject var pull: PullUp
    var body: some View {
        let armed = pull.v >= PullUp.arm
        Label("Показать крупно", systemImage: "arrow.up.left.and.arrow.down.right")
            .font(T.label).foregroundStyle(armed ? T.ink : T.dim).padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(T.field))
            .scaleEffect(armed ? 1.06 : 0.94).animation(.spring(duration: 0.25), value: armed)
            .opacity(Double(min(max(pull.v - 10, 0) / 30, 1))).animation(.easeOut(duration: 0.15), value: pull.v == 0)
            .padding(.top, 8)
            .onChange(of: armed) { _, a in if a { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Шар-микрофон: держать — говорить, отпустить — перевод; короткое касание — «нажми ещё раз, чтобы закончить».
struct MicOrb: View {
    @EnvironmentObject var m: AppModel
    @State private var pressAt = Date()
    @State private var pressed = false
    @State private var ignoreEnd = false
    @State private var locked = false          // потянули вверх — запись закреплена, палец можно убрать
    @State private var pull = CGSize.zero      // шар чуть тянется за пальцем

    var body: some View {
        ZStack {
            LiveOrb(meter: m.meter, on: m.recording, pressed: pressed)
            VStack(spacing: 3) {
                Image(systemName: m.recording ? "stop.fill" : m.busy || m.phrase ? "ellipsis" : "mic.fill")
                    .font(.system(size: m.recording ? 19 : 28, weight: .semibold))
                    .symbolEffect(.pulse, isActive: m.busy)
                if m.recording {   // время записи — прямо в шаре
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let t = Int(Date().timeIntervalSince(m.recStart))
                        Text(String(format: "%d:%02d", t / 60, t % 60)).font(.system(size: 14, weight: .semibold).monospacedDigit())
                    }
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 2)   // белое на жёлтом краю шара иначе теряется
        }
        .padding(8).glass(Circle(), clear: true)
        .background(MicRings(meter: m.meter, on: m.recording, busy: m.phrase && !m.recording))
        .offset(pull).animation(.spring(duration: 0.25), value: pull)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !pressed {
                    pressed = true; pressAt = v.time; locked = false   // время самого касания: если запуск записи задержится, касание не станет «удержанием»
                    if m.recording { m.stopRec(); ignoreEnd = true } else { m.startRec() }
                    return
                }
                // палец держит шар и ведёт: вверх — закрепить запись, в сторону — отменить фразу
                guard m.recording, !ignoreEnd, !locked else { return }
                let t = v.translation
                pull = CGSize(width: max(min(t.width, 70), -70) * 0.3, height: max(min(t.height, 0), -80) * 0.3)
                if t.height < -70, abs(t.width) < 60 {
                    locked = true; pull = .zero; m.toggleMode = true; m.hint = "Говорите… закреплено, нажмите, чтобы закончить"
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else if abs(t.width) > 100, t.height > -60 {
                    ignoreEnd = true; pull = .zero; m.cancelRec()
                }
            }
            .onEnded { v in
                pressed = false; pull = .zero
                if ignoreEnd { ignoreEnd = false; return }
                if locked { locked = false; return }
                if v.time.timeIntervalSince(pressAt) < 0.35 { m.toggleMode = true; m.hint = "Говорите… нажмите, чтобы закончить" }
                else { m.stopRec() }
            })
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

/// Шар «дышит» голосом: чем громче, тем крупнее.
private struct LiveOrb: View {
    @ObservedObject var meter: Meter
    var on: Bool
    var pressed: Bool
    var body: some View {
        Orb(glow: true).frame(width: 86, height: 86)
            .scaleEffect(on ? 0.96 + meter.level * 0.12 : pressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: meter.level)
            .animation(.spring(duration: 0.25), value: on)
            .animation(.spring(duration: 0.25), value: pressed)
    }
}

/// Кольца вокруг шара расходятся в такт громкости; каждое следующее чуть запаздывает — получается волна.
private struct MicRings: View {
    @ObservedObject var meter: Meter
    var on: Bool
    var busy = false                           // ждём перевод — по кольцу бежит дуга
    private let colors = [Color(red: 1, green: 0.79, blue: 0.24), Color(red: 1, green: 0.58, blue: 0.4), Color(red: 0.95, green: 0.55, blue: 0.72),
                          Color(red: 0.72, green: 0.61, blue: 1), Color(red: 1, green: 0.79, blue: 0.24)]
    var body: some View {
        let l = on ? meter.level : 0
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let k = Double(i)
                Circle().strokeBorder(AngularGradient(colors: colors, center: .center), lineWidth: 3.2 - k * 0.8)
                    .frame(width: 106, height: 106)
                    .scaleEffect(1 + l * (0.16 + 0.17 * k))
                    .opacity(on ? (0.9 - 0.25 * k) * (0.15 + 0.85 * l) : 0)
                    .animation(.spring(response: 0.16 + 0.09 * k, dampingFraction: 0.5), value: l)
            }
            TimelineView(.animation(paused: !busy)) { c in
                Circle().trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: colors, center: .center), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees((c.date.timeIntervalSinceReferenceDate * 320).truncatingRemainder(dividingBy: 360)))
            }
            .opacity(busy ? 1 : 0).animation(.easeInOut(duration: 0.25), value: busy)
        }
        .allowsHitTesting(false)
    }
}

/// Свайп по реплике: влево — удалить (можно вернуть), вправо — озвучить.
/// Реплика идёт за пальцем; при удалении сначала уезжает за край, потом соседние плавно смыкаются.
private struct SwipeRow<Content: View>: View {
    var onDelete: () -> Void
    var onSpeak: () -> Void
    @ViewBuilder var content: Content
    @State private var dx: CGFloat = 0
    @State private var gone = false
    private static var del: CGFloat { -84 }
    private static var say: CGFloat { 60 }

    var body: some View {
        let armed = dx <= Self.del || dx >= Self.say
        let show = Double(min(abs(dx), 56)) / 56.0
        content
            .offset(x: dx)
            .background(alignment: dx < 0 ? .trailing : .leading) {
                Image(systemName: dx < 0 ? "trash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(dx < 0 ? T.err : T.ink)
                    .scaleEffect(armed ? 1.2 : 0.9).opacity(gone ? 0 : show).padding(.horizontal, 14)
                    .animation(.spring(duration: 0.25), value: armed)
            }
            .gesture(SidePan(changed: { x in
                guard !gone else { return }
                dx = x < 0 ? max(x, -430) : min(x * 0.55, 92)   // вправо — с сопротивлением: это не удаление, а «кнопка»
            }, ended: { v in
                guard !gone else { return }
                if let v, dx <= Self.del || (dx < -20 && dx + v * 0.12 <= Self.del) {   // дотянул до корзины или смахнул быстрым движением
                    withAnimation(.easeOut(duration: 0.2)) { gone = true; dx = -520 } completion: { onDelete() }
                } else {
                    if v != nil, dx >= Self.say { onSpeak() }
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { dx = 0 }
                }
            }))
            .onChange(of: armed) { _, a in if a, !gone { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("bubble")
    }
}

/// Горизонтальное движение пальца по реплике. Родной распознаватель: начинается только при явно боковом
/// движении, а прокрутка ленты ждёт его отказа — лента и реплика никогда не едут одновременно.
private struct SidePan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat?) -> Void              // скорость по горизонтали; nil — жест прерван

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 1
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        switch g.state {
        case .began, .changed: changed(g.translation(in: g.view).x)
        case .ended: ended(g.velocity(in: g.view).x)
        case .cancelled, .failed: ended(nil)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return false }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y) * 1.3
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
