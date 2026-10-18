import SwiftUI

/// Первый родной экран «Ауры» (18.10): настоящий Liquid Glass iOS 26 + варианты шрифтов Apple.
/// Пока только для просмотра: запуск с «-auraPreview N» (N = 1…6 — вариант шрифта). Потом станет главным экраном.
struct AuraFonts {
    let name: String
    let big: Font, text: Font, small: Font, mark: Font, ui: Font
    static func variant(_ n: Int) -> AuraFonts {
        switch n {
        case 2: return .init(name: "SF Pro Expanded + SF Pro",
                             big: .system(size: 31, weight: .semibold).width(.expanded),
                             text: .system(size: 18, weight: .medium), small: .system(size: 14),
                             mark: .system(size: 21, weight: .bold).width(.expanded), ui: .system(size: 15, weight: .medium))
        case 3: return .init(name: "SF Pro Rounded",
                             big: .system(size: 33, weight: .semibold, design: .rounded),
                             text: .system(size: 18, weight: .medium, design: .rounded), small: .system(size: 14, design: .rounded),
                             mark: .system(size: 21, weight: .bold, design: .rounded), ui: .system(size: 15, weight: .semibold, design: .rounded))
        case 4: return .init(name: "New York + SF Pro",
                             big: .system(size: 34, weight: .medium, design: .serif),
                             text: .system(size: 19, weight: .regular, design: .serif), small: .system(size: 14),
                             mark: .system(size: 23, weight: .semibold, design: .serif), ui: .system(size: 15, weight: .medium))
        case 5: return .init(name: "SF Pro Expanded везде",
                             big: .system(size: 29, weight: .medium).width(.expanded),
                             text: .system(size: 17, weight: .regular).width(.expanded), small: .system(size: 13).width(.expanded),
                             mark: .system(size: 20, weight: .heavy).width(.expanded), ui: .system(size: 14, weight: .medium).width(.expanded))
        case 6: return .init(name: "SF Pro Condensed + SF Pro",
                             big: .system(size: 38, weight: .semibold).width(.condensed),
                             text: .system(size: 18, weight: .medium), small: .system(size: 14),
                             mark: .system(size: 22, weight: .bold).width(.condensed), ui: .system(size: 15, weight: .medium))
        default: return .init(name: "SF Pro (системный)",
                              big: .system(size: 33, weight: .semibold),
                              text: .system(size: 18, weight: .medium), small: .system(size: 14),
                              mark: .system(size: 21, weight: .bold), ui: .system(size: 15, weight: .medium))
        }
    }
}

struct AuraPreview: View {
    let f: AuraFonts
    var glassMode = UserDefaults.standard.integer(forKey: "glassMode")   // 0 обычное, 1 прозрачное, 2 прозрачное + сочный свет
    private var clear: Bool { glassMode > 0 }
    private let ink = Color(red: 0.09, green: 0.086, blue: 0.11)
    private let dim = Color(red: 0.42, green: 0.41, blue: 0.46)

    var body: some View {
        ZStack {
            AuraBackground(rich: glassMode == 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Color.clear.frame(height: 4)   // лента начинается ПОД верхними кнопками — стеклу есть что преломлять
                    msg(me: true, src: "Здравствуйте, сколько стоит аренда байка на неделю?", out: "Halo, berapa sewa motor seminggu?")
                    msg(me: false, src: "Untuk seminggu 700 ribu, sudah termasuk helm.", out: "За неделю 700 тысяч, шлем включён.")
                    VStack(alignment: .leading, spacing: 10) {
                        label("Собеседник · только что", me: false)
                        Text("Да, в восемь мы уже открыты.").font(f.big).foregroundStyle(ink).tracking(-0.6)
                        Text("Bisa, jam delapan sudah buka.").font(f.small).foregroundStyle(dim)
                        actions
                    }
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            VStack { topBar; Spacer(); bottomBar }
            VStack { Spacer(); Text(f.name + " · " + ["обычное стекло", "прозрачное стекло", "прозрачное + сочный свет"][min(glassMode, 2)]).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.75), in: Capsule()).foregroundStyle(.white).padding(.bottom, 4) }
        }
    }

    private func label(_ t: String, me: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(me ? Color(red: 1, green: 0.66, blue: 0.24) : Color(red: 0.8, green: 0.55, blue: 0.85)).frame(width: 7, height: 7)
            Text(t).font(f.small.weight(.medium)).foregroundStyle(dim)
        }
    }

    private func msg(me: Bool, src: String, out: String) -> some View {
        VStack(alignment: me ? .trailing : .leading, spacing: 6) {
            label(me ? "Вы" : "Собеседник", me: me)
            Text(src).font(f.small).foregroundStyle(dim).multilineTextAlignment(me ? .trailing : .leading)
            Text(out).font(f.text).foregroundStyle(ink).multilineTextAlignment(me ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: me ? .trailing : .leading)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            ForEach(["doc.on.doc", "arrow.up.left.and.arrow.down.right", "arrow.triangle.2.circlepath"], id: \.self) { s in
                Image(systemName: s).font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44).glass(Circle(), clear: clear)
            }
            Spacer()
            Label("Озвучить", systemImage: "speaker.wave.2.fill").font(f.ui).padding(.horizontal, 18).frame(height: 44)
                .glass(Capsule(), tint: Color(red: 1, green: 0.6, blue: 0.4).opacity(0.35), clear: clear)
        }
        .foregroundStyle(ink).padding(.top, 6)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 10) {
                Orb().frame(width: 30, height: 30)
                Text("Tapny").font(f.mark).foregroundStyle(ink)
            }.padding(.horizontal, 14).frame(height: 50).glass(Capsule(), clear: clear)
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "rectangle.split.1x2"); Image(systemName: "slider.horizontal.3")
            }.font(.system(size: 17, weight: .medium)).foregroundStyle(ink).padding(.horizontal, 18).frame(height: 50).glass(Capsule(), clear: clear)
        }
        .padding(.horizontal, 16).padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("Русский"); Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(dim); Text("Индонезийский")
            }.font(f.ui).foregroundStyle(ink).padding(.horizontal, 22).frame(height: 46).glass(Capsule(), clear: clear)
            GlassGroup { HStack {
                Image(systemName: "keyboard").font(.system(size: 19)).frame(width: 58, height: 58).glass(Circle(), clear: clear)
                Spacer()
                ZStack { Orb().frame(width: 86, height: 86); Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white) }
                    .padding(8).glass(Circle(), clear: clear)
                Spacer()
                Image(systemName: "camera").font(.system(size: 19)).frame(width: 58, height: 58).glass(Circle(), clear: clear)
            }.foregroundStyle(ink).padding(.horizontal, 30) }
        }
        .padding(.bottom, 30)
    }
}

/// Тёплый живой шар (микрофон).
struct Orb: View {
    var body: some View {
        Circle().fill(AngularGradient(colors: [Color(red: 1, green: 0.79, blue: 0.24), Color(red: 1, green: 0.58, blue: 0.4),
                                               Color(red: 0.95, green: 0.55, blue: 0.72), Color(red: 0.72, green: 0.61, blue: 1),
                                               Color(red: 1, green: 0.79, blue: 0.24)], center: .center))
            .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 40)))
            .blur(radius: 0.5)
    }
}

/// Мягкие пятна света — стеклу есть что преломлять.
struct AuraBackground: View {
    var rich = false
    var body: some View {
        ZStack {
            Color(red: 0.99, green: 0.985, blue: 0.99)
            if rich {   // яркие ленты света под панелями управления — у стекла появляется линза и блики
                blob(Color(red: 1, green: 0.62, blue: 0.35), x: 0.2, y: 0.07, r: 170)
                blob(Color(red: 0.62, green: 0.5, blue: 1), x: 0.9, y: 0.05, r: 150)
                blob(Color(red: 1, green: 0.55, blue: 0.62), x: 0.15, y: 0.93, r: 190)
                blob(Color(red: 1, green: 0.78, blue: 0.2), x: 0.85, y: 0.9, r: 190)
            }
            blob(Color(red: 1, green: 0.8, blue: 0.62), x: 0.95, y: 0.12, r: 260)
            blob(Color(red: 0.8, green: 0.72, blue: 1), x: 0.0, y: 0.45, r: 280)
            blob(Color(red: 1, green: 0.88, blue: 0.5), x: 0.85, y: 0.62, r: 240)
            blob(Color(red: 1, green: 0.7, blue: 0.75), x: 0.4, y: 0.98, r: 300)
        }.ignoresSafeArea()
    }
    private func blob(_ c: Color, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        GeometryReader { g in Circle().fill(c.opacity(0.75)).frame(width: r * 2, height: r * 2).blur(radius: 70)
            .position(x: g.size.width * x, y: g.size.height * y) }
    }
}

/// Группа стекла Apple: соседние капли сливаются и перетекают друг в друга (iOS 26).
struct GlassGroup<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 24) { content } } else { content }
    }
}

extension View {
    /// Настоящее «жидкое стекло» iOS 26; на iOS 18 — матовое стекло.
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, clear: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let g: Glass = clear ? .clear : .regular
            if let tint { self.glassEffect(g.tint(tint).interactive(), in: shape) }
            else { self.glassEffect(g.interactive(), in: shape) }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
