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
            VStack(spacing: 0) {
                topBar; Spacer()
                bottom.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY.rounded() } action: { pull.floor = $0 }
            }
            if PullUp.debug { PullDebug(pull: pull) }
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
                        // конец ленты в покое стоит на нижнем крае экрана (над полоской «домой»); выше — ленту тянут за край
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY.rounded() } action: { y in
                            pull.end = y
                            let v = pull.held && pull.fromEnd && !m.phrase && !m.items.isEmpty ? max(0, pull.floor - y) : 0
                            if v != pull.v { pull.v = v }
                            pull.note()
                        }
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
            .onScrollPhaseChange { was, now in
                let on = now == .interacting || now == .tracking
                if pull.held, !on {   // отпустили
                    if pull.v >= PullUp.arm, !m.phrase, let it = m.items.last { full = it }
                    pull.v = 0
                }
                if on, !pull.held { pull.fromEnd = pull.end - pull.floor < 12 }   // тянуть надо от самого конца ленты: обычная прокрутка вниз крупно не открывает
            pull.held = on; pull.phase = "\(now)"; pull.note()
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
    var held = false                           // ленту держит палец
    var fromEnd = false                        // палец лёг, когда лента уже стояла в самом конце
    var floor: CGFloat = 0                     // нижний край экрана над полоской «домой»
    var end: CGFloat = 0                       // где сейчас конец ленты
    static let arm: CGFloat = 60               // дотянули — отпустить, и перевод откроется крупно
    // «-dbgPull YES» — числа жеста на экране (для проверки на видео)
    static let debug = UserDefaults.standard.bool(forKey: "dbgPull")
    @Published var dbg = ""
    var phase = ""
    func note() { if Self.debug { dbg = "\(phase) floor \(Int(floor)) end \(Int(end)) v \(Int(v))" } }
}

private struct PullDebug: View {
    @ObservedObject var pull: PullUp
    var body: some View {
        VStack { Text(pull.dbg).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(.white).padding(6).background(.black).padding(.top, 60); Spacer() }
            .allowsHitTesting(false)
    }
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
    @State private var doneTick = 0            // перевод готов — от шара уходит одна волна
    @State private var failTick = 0            // не получилось — шар качнётся

    private var phase: OrbPhase {
        if m.recording { return m.toggleMode ? .locked : .listening }
        if m.phrase || m.busy { return .thinking }
        return pressed ? .pressed : .idle
    }

    var body: some View {
        let ph = phase
        ZStack { LiveOrb(meter: m.meter, phase: ph); OrbGlyph(phase: ph) }
        .overlay(OrbRim(phase: ph, start: m.recStart))   // внутри стекла: поверх стекла рисунок не виден
        .padding(8).glass(Circle(), clear: true)
        .background(OrbHalo(meter: m.meter, phase: ph, doneTick: doneTick))
        .modifier(Shake(t: CGFloat(failTick)))
        .onChange(of: m.big) { _, _ in if !m.recording { doneTick += 1 } }
        .onChange(of: m.hint) { _, h in
            if ["Не расслышал", "Слишком коротко", "Нет связи", "Не получилось", "Микрофон не включился"].contains(where: { h.hasPrefix($0) }) {
                withAnimation(.easeOut(duration: 0.45)) { failTick += 1 }
            }
        }
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

/// Состояние шара-микрофона. Слов и цифр в шаре нет: что происходит, показывают сам шар и свет вокруг него.
enum OrbPhase: Equatable { case idle, pressed, listening, locked, thinking }

/// Копит угол поворота заливки: скорость меняется на ходу, без рывка.
final class OrbClock {
    private var last: TimeInterval?
    private var speed = 8.0
    private var angle = 0.0
    func tick(_ date: Date, target: Double) -> Double {
        let now = date.timeIntervalSinceReferenceDate
        let dt = min(max(now - (last ?? now), 0), 0.1)
        last = now
        speed += (target - speed) * min(1, dt * 3)
        angle += speed * dt
        return angle
    }
}

/// Сам шар: в покое заливка едва вращается, пока слушает — вдавлен и «дышит» голосом, пока думает — сжат и крутится быстрее.
private struct LiveOrb: View {
    @ObservedObject var meter: Meter
    var phase: OrbPhase
    @State private var clock = OrbClock()
    @Environment(\.accessibilityReduceMotion) private var calm
    var body: some View {
        let rec = phase == .listening || phase == .locked
        let l = rec ? meter.level : 0
        let target = rec ? 36 + 150 * l : (phase == .thinking ? 110.0 : 8.0)
        TimelineView(.animation(minimumInterval: phase == .idle ? 1.0 / 30 : nil, paused: calm && phase == .idle)) { c in
            let breath = phase == .thinking ? 0.02 * sin(c.date.timeIntervalSinceReferenceDate * 3.6) : 0
            Orb(spin: .degrees(clock.tick(c.date, target: target)))
                .transaction { $0.animation = nil }
                .scaleEffect(CGFloat(1 + breath))
        }
        .frame(width: 86, height: 86)
        .scaleEffect(base + CGFloat(rec ? 0.09 * l : 0))
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: l)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: phase)
    }
    private var base: CGFloat {
        switch phase {
        case .idle: return 1
        case .pressed, .listening: return 0.93
        case .locked: return 0.98
        case .thinking: return 0.92
        }
    }
}

/// Значок в центре: микрофон; когда запись закреплена — мягкий квадрат «закончить». Один перетекает в другой.
private struct OrbGlyph: View {
    var phase: OrbPhase
    private let berry = Color(red: 0.42, green: 0.10, blue: 0.24)
    var body: some View {
        let stop = phase == .locked
        let think = phase == .thinking
        ZStack {
            // тёмная «линза» под значком: белое читается и на жёлтом краю шара
            Circle().fill(RadialGradient(colors: [berry.opacity(0.24), berry.opacity(0)], center: .center, startRadius: 0, endRadius: 34))
            Group {
                Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold))
                    .scaleEffect(stop ? 0.5 : think ? 0.86 : 1)
                    .opacity(stop ? 0 : think ? 0.5 : 1)
                    .blur(radius: stop ? 4 : 0)
                RoundedRectangle(cornerRadius: 8, style: .continuous).frame(width: 26, height: 26)
                    .scaleEffect(stop ? 1 : 0.5)
                    .opacity(stop ? 1 : 0)
                    .blur(radius: stop ? 0 : 4)
            }
            .foregroundStyle(.white)
            .shadow(color: berry.opacity(0.3), radius: 6, y: 1)
        }
        .frame(width: 86, height: 86)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: phase)
        .allowsHitTesting(false)
    }
}

/// Свет за стеклом: ореол в такт голосу, рябь, пока слушает, и одна волна, когда перевод готов.
private struct OrbHalo: View {
    @ObservedObject var meter: Meter
    var phase: OrbPhase
    var doneTick: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var calm
    private static let colors = [Color(red: 1, green: 0.79, blue: 0.24), Color(red: 1, green: 0.58, blue: 0.4), Color(red: 0.95, green: 0.55, blue: 0.72),
                                 Color(red: 0.72, green: 0.61, blue: 1), Color(red: 1, green: 0.79, blue: 0.24)]
    var body: some View {
        let rec = phase == .listening || phase == .locked
        let l = rec ? meter.level : 0
        let dark = scheme == .dark
        // на светлом персиковом фоне цветной свет не виден — там он белый; в тёмной теме — цвета шара
        let light: AnyShapeStyle = dark ? AnyShapeStyle(AngularGradient(colors: Self.colors, center: .center)) : AnyShapeStyle(Color.white)
        ZStack {
            Circle().fill(light).frame(width: 102, height: 102).blur(radius: 18)
                .scaleEffect(CGFloat(rec ? 1.04 + 0.3 * l : (phase == .thinking ? 0.9 : 1.0)))
                .opacity(rec ? 0.4 + 0.5 * l : (dark && phase != .thinking ? 0.36 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: l)
                .animation(.easeInOut(duration: 0.45), value: phase)
            TimelineView(.animation(paused: !rec || calm)) { c in
                Canvas { ctx, size in
                    let t = c.date.timeIntervalSinceReferenceDate
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    let ink: GraphicsContext.Shading = dark ? .conicGradient(Gradient(colors: Self.colors), center: mid) : .color(.white)
                    for i in 0..<2 {
                        let p = (t / 2.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)   // жизнь волны 0…1
                        let r = CGFloat(51 + 28 * p)                                             // от кромки стекла наружу
                        ctx.opacity = sin(p * .pi) * (1 - p) * 1.2                               // рождается и гаснет прозрачной
                        ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)),
                                   with: ink, lineWidth: CGFloat(2 - 1.2 * p))
                    }
                }
            }
            .frame(width: 164, height: 164)
            .opacity(rec ? 1 : 0).animation(.easeInOut(duration: 0.4), value: rec)
            Circle().strokeBorder(light, lineWidth: 2).frame(width: 102, height: 102)
                .phaseAnimator([0, 1, 2], trigger: doneTick) { v, p in
                    v.scaleEffect(p == 2 ? 1.45 : 1).opacity(p == 1 ? 0.9 : 0)
                } animation: { p in
                    p == 1 ? Animation.easeOut(duration: 0.1) : p == 2 ? Animation.easeOut(duration: 0.65) : Animation.linear(duration: 0.01)
                }
        }
        .allowsHitTesting(false)
    }
}

/// По ободку стекла: тонкая дуга времени, когда запись закреплена (круг — минута), и «комета», пока ждём перевод.
private struct OrbRim: View {
    var phase: OrbPhase
    var start: Date
    private static let comet = Gradient(stops: [
        .init(color: T.they.opacity(0), location: 0), .init(color: T.they.opacity(0.6), location: 0.12),
        .init(color: T.me, location: 0.26), .init(color: T.me, location: 0.32),
        .init(color: T.me.opacity(0), location: 0.33), .init(color: T.me.opacity(0), location: 1)])
    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: phase != .locked)) { c in
                let s = max(0, c.date.timeIntervalSince(start))
                ZStack {
                    Circle().stroke(T.ink.opacity(s >= 60 ? 0.22 : 0), lineWidth: 2.5)
                    Circle().trim(from: 0, to: CGFloat(s.truncatingRemainder(dividingBy: 60) / 60))
                        .stroke(T.ink.opacity(0.72), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .opacity(phase == .locked ? 1 : 0)
            TimelineView(.animation(paused: phase != .thinking)) { c in
                Circle().trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(gradient: Self.comet, center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees((c.date.timeIntervalSinceReferenceDate * 260).truncatingRemainder(dividingBy: 360)))
            }
            .opacity(phase == .thinking ? 1 : 0)
        }
        .frame(width: 94, height: 94)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .allowsHitTesting(false)
    }
}

/// Шар качнулся из стороны в сторону — «не получилось».
private struct Shake: GeometryEffect {
    var t: CGFloat
    var animatableData: CGFloat { get { t } set { t = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(t * .pi * 3), y: 0))
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
