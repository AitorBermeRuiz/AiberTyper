// Renders design mockups to PNG. Run design/mockups.sh; output goes to design/mockups/out (not in git).
// shortcut: materials and glass are faked with blurred shapes because ImageRenderer can't draw real
// NSVisualEffectView or .glassEffect; the chosen design uses the real APIs in the app.
import AppKit
import SwiftUI

// MARK: - Mock round

let sample = "El perro del vecino ladra cada vez que pasa la furgoneta del correo. El cocinero probó la salsa, añadió una pizca de sal y sonrió satisfecho."
let typedCount = 52
let wrongAt: Set<Int> = [17, 40]
let progress = Double(typedCount) / Double(sample.count)

enum R { // finished round
    static let wpm = 72, accuracy = 95, seconds = 34, correct = 152, wrong = 3, average = 64
    static let history: [Double] = [54, 58, 61, 57, 63, 66, 60, 68, 64, 72]
}

extension Color {
    init(_ hex: UInt32, _ opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct Ink {
    var ok: Color
    var bad: Color
    var badBg: Color = .clear
    var badStrike = false
    var pending: Color
    var cursorBg: Color? = nil
    var cursorFg: Color? = nil
    var cursorLine: Color? = nil
}

/// The sample text between `from` and `to`, colored as typed / wrong / cursor / pending.
func painted(_ ink: Ink, from: Int = 0, to: Int = sample.count) -> AttributedString {
    var out = AttributedString()
    for (i, c) in sample.enumerated() where i >= from && i < to {
        var a = AttributedString(String(c))
        if i < typedCount {
            if wrongAt.contains(i) {
                a.foregroundColor = ink.bad
                a.backgroundColor = ink.badBg
                if ink.badStrike { a.strikethroughStyle = Text.LineStyle(pattern: .solid, color: ink.bad) }
            } else {
                a.foregroundColor = ink.ok
            }
        } else {
            a.foregroundColor = ink.pending
            if i == typedCount {
                if let bg = ink.cursorBg { a.backgroundColor = bg; a.foregroundColor = ink.cursorFg ?? ink.pending }
                if let line = ink.cursorLine { a.underlineStyle = Text.LineStyle(pattern: .solid, color: line) }
            }
        }
        out += a
    }
    return out
}

// MARK: - Backdrops and helpers

struct Wall: View {
    var base: [Color]
    var blobs: [Color]
    var body: some View {
        ZStack {
            LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                ForEach(blobs.indices, id: \.self) { i in
                    Circle().fill(blobs[i])
                        .frame(width: g.size.width * 0.6)
                        .position(x: g.size.width * [0.15, 0.85, 0.5, 0.2][i % 4], y: g.size.height * [0.2, 0.3, 0.95, 0.85][i % 4])
                }
            }
            .blur(radius: 70)
        }
    }
}

let dusk = Wall(base: [Color(0x1B2340), Color(0x3A2350)], blobs: [Color(0x4F6BFF, 0.7), Color(0xFF7A59, 0.6), Color(0xB052FF, 0.6)])
let vivid = Wall(base: [Color(0x2B6CFF), Color(0xFF4FA3)], blobs: [Color(0x00E0FF), Color(0xFFB800), Color(0x7A2BFF), Color(0x00FFA3)])
let plum = Wall(base: [Color(0x120B10), Color(0x2A1422)], blobs: [Color(0xE8418C, 0.45), Color(0x7A2B5C, 0.6), Color(0xF19AC8, 0.3)])
let daylight = Wall(base: [Color(0xBFD7FF), Color(0xF6D6E8)], blobs: [Color(0x7FB2FF, 0.8), Color(0xFFC08A, 0.8), Color(0xC9A7FF, 0.8)])

/// A design as it would float over the desktop.
struct Framed<V: View>: View {
    var wall: Wall
    @ViewBuilder var content: V
    var body: some View {
        content
            .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
            .padding(48)
            .background(wall)
    }
}

/// Frosted panel: a blurred copy of the wallpaper plus a tint and a light edge.
struct FakeGlass: ViewModifier {
    var wall: Wall
    var radius: CGFloat
    var tint: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background { ZStack { wall.blur(radius: 30); tint } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
    }
}

extension View {
    func glass(_ wall: Wall, radius: CGFloat, tint: Color = .white.opacity(0.14)) -> some View {
        modifier(FakeGlass(wall: wall, radius: radius, tint: tint))
    }
}

struct Bars: View {
    var color: Color
    var last: Color
    var width: CGFloat = 8
    var height: CGFloat = 44
    var body: some View {
        let top = R.history.max()!, low = R.history.min()! - 10
        HStack(alignment: .bottom, spacing: width / 2) {
            ForEach(R.history.indices, id: \.self) { i in
                Capsule()
                    .fill(i == R.history.count - 1 ? last : color)
                    .frame(width: width, height: height * (R.history[i] - low) / (top - low))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { Circle().fill(Color($0)).frame(width: 12, height: 12) }
        }
    }
}

struct Keycap: View {
    var key: String
    var label: String
    var body: some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.15)))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.black.opacity(0.55))
    }
}

/// Ring progress, also used as a gauge.
struct Ring: View {
    var value: Double
    var color: Color
    var track: Color
    var line: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: line)
            Circle().trim(from: 0, to: value).stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            for y in stride(from: 0, to: size.height, by: 3) {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.28)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Palettes

enum G { // Gentleman Programming, taken from the Gentle-AI site
    static let bg = Color(0x1A1217), fg = Color(0xF5EEF2), pink = Color(0xF19AC8), neon = Color(0xE8418C)
    static let muted = Color(0xA99AA3), border = Color(0x3A2A33), yellow = Color(0xF5D547)
    static let font = "IosevkaTerm Nerd Font"

    /// Plum background with the soft pink glow from the top-left corner.
    static var background: some View {
        ZStack {
            bg
            RadialGradient(colors: [pink.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
        }
    }

    static func label(_ s: String) -> some View {
        Text(s.uppercased()).font(.custom(font, size: 12)).tracking(2).foregroundStyle(pink)
    }
}

enum T { // terminal green
    static let green = Color(0x33FF66), bg = Color(0x050A06)
    static func glow<V: View>(_ v: V) -> some View { v.shadow(color: green.opacity(0.7), radius: 6) }
}

// MARK: - Typing window designs

struct T1Gentleman: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                G.label("Aiber typer")
                Spacer()
                Text("Español").font(.system(size: 12, weight: .bold)).foregroundStyle(G.bg)
                    .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(G.pink))
                Text("English").font(.system(size: 12, weight: .medium)).foregroundStyle(G.muted)
            }
            Text(painted(Ink(ok: G.fg, bad: G.neon, badBg: G.neon.opacity(0.2), pending: G.muted.opacity(0.5), cursorBg: G.pink, cursorFg: G.bg)))
                .font(.custom(G.font, size: 23)).lineSpacing(8)
            HStack(alignment: .bottom, spacing: 28) {
                stat("58", "ppm")
                stat("96%", "precisión")
                Spacer()
                Text("tab idioma · ⏎ otro · esc cerrar").font(.custom(G.font, size: 12)).foregroundStyle(G.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(G.border)
                    Capsule().fill(LinearGradient(colors: [G.pink, G.neon], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * progress)
                        .shadow(color: G.neon.opacity(0.8), radius: 6)
                }
            }
            .frame(height: 4)
        }
        .padding(28)
        .frame(width: 640)
        .background(G.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(G.border, lineWidth: 1))
    }

    func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.custom(G.font, size: 28).bold()).foregroundStyle(G.pink)
            Text(caption).font(.system(size: 12)).foregroundStyle(G.muted)
        }
    }
}

struct T2Glass: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                HStack(spacing: 0) {
                    Text("Español").padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.35)))
                    Text("English").padding(.horizontal, 14).padding(.vertical, 6).foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(3)
                .glass(vivid, radius: 20, tint: .white.opacity(0.12))
                Spacer()
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 30, height: 30).glass(vivid, radius: 15)
            }
            .foregroundStyle(.white)
            Text(painted(Ink(ok: .white, bad: .white, badBg: Color(0xFF2D6F, 0.8), pending: .white.opacity(0.42), cursorLine: .white)))
                .font(.system(size: 23, weight: .medium, design: .rounded)).lineSpacing(9)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            HStack(spacing: 10) {
                chip("58", "ppm", "speedometer")
                chip("96%", "precisión", "scope")
                Spacer()
                Ring(value: progress, color: .white, track: .white.opacity(0.2), line: 4).frame(width: 30, height: 30)
            }
        }
        .padding(26)
        .frame(width: 640)
        .glass(vivid, radius: 30)
    }

    func chip(_ value: String, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(vivid, radius: 18)
    }
}

struct T3Minimal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { g in Rectangle().fill(.black).frame(width: g.size.width * progress, height: 2) }.frame(height: 2)
            Text(painted(Ink(ok: Color(0x1A1A1A), bad: Color(0xE5484D), pending: Color(0xBDBDB6), cursorLine: Color(0x1A1A1A))))
                .font(.system(size: 22, weight: .light, design: .monospaced)).lineSpacing(10)
                .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 24)
            HStack {
                Text("es").foregroundStyle(Color(0xBDBDB6))
                Spacer()
                Text("58").foregroundStyle(Color(0x1A1A1A)) + Text("  ·  ").foregroundStyle(Color(0xBDBDB6)) + Text("96%").foregroundStyle(Color(0x1A1A1A))
            }
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .padding(.horizontal, 40).padding(.bottom, 28)
        }
        .frame(width: 640)
        .background(Color(0xFAFAF7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct T4Y2K: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("✦ AiberTyper 2000 ✦").font(.custom("Silom", size: 14)).foregroundStyle(.white).shadow(color: Color(0x6B2FBF), radius: 0, x: 1, y: 1)
                Spacer()
                ForEach(["_", "□", "×"], id: \.self) { s in
                    Text(s).font(.system(size: 11, weight: .black)).foregroundStyle(Color(0x6B2FBF))
                        .frame(width: 22, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [.white, Color(0xD9C8FF)], startPoint: .top, endPoint: .bottom)))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white, lineWidth: 1))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(LinearGradient(colors: [Color(0xFF7AD9), Color(0x9B6BFF), Color(0x48D6FF)], startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.45)).frame(height: 14) }

            VStack(alignment: .leading, spacing: 16) {
                Text(painted(Ink(ok: Color(0x5B22B0), bad: Color(0xFF2E88), badBg: Color(0xFFD1E8), pending: Color(0xB6A3DA), cursorBg: Color(0xFFE94D), cursorFg: Color(0x5B22B0))))
                    .font(.custom("Arial Rounded MT Bold", size: 21)).lineSpacing(7)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(0xC9B5FF), lineWidth: 2))
                HStack(spacing: 10) {
                    pill("★ 58 PPM", [Color(0xFFB3E6), Color(0xFF4FB8)])
                    pill("♥ 96%", [Color(0xB3F0FF), Color(0x2FB8FF)])
                    Spacer()
                    // XP-style block progress bar.
                    HStack(spacing: 2) {
                        ForEach(0..<14, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5).fill(Double(i) / 14 < progress ? Color(0x3BD16F) : .white.opacity(0.6)).frame(width: 9, height: 14)
                        }
                    }
                    .padding(3).background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.5)))
                }
            }
            .padding(18)
            .background(LinearGradient(colors: [Color(0xF3E9FF), Color(0xE3F6FF)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 640)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: 2))
    }

    func pill(_ s: String, _ colors: [Color]) -> some View {
        Text(s).font(.custom("Arial Rounded MT Bold", size: 15)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
            .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.45)).frame(height: 10).padding(.horizontal, 6).padding(.top, 2) }
            .shadow(color: colors[1].opacity(0.5), radius: 4, y: 2)
    }
}

struct T5Native: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TrafficLights()
                Spacer()
                HStack(spacing: 0) {
                    Text("Español").padding(.horizontal, 12).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white).shadow(color: .black.opacity(0.15), radius: 1, y: 0.5))
                    Text("English").padding(.horizontal, 12).padding(.vertical, 3)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.07)))
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 18) {
                Text(painted(Ink(ok: .black.opacity(0.85), bad: Color(0xFF3B30), badBg: Color(0xFF3B30, 0.12), pending: .black.opacity(0.3), cursorLine: Color(0x0A84FF))))
                    .font(.system(size: 20)).lineSpacing(7)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.08))
                        Capsule().fill(Color(0x0A84FF)).frame(width: g.size.width * progress)
                    }
                }
                .frame(height: 5)
                HStack(spacing: 18) {
                    Label("58 ppm", systemImage: "speedometer")
                    Label("96 %", systemImage: "scope")
                    Spacer()
                    Keycap(key: "tab", label: "Idioma")
                    Keycap(key: "⏎", label: "Otro")
                    Keycap(key: "esc", label: "Cerrar")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.7))
            }
            .padding(.horizontal, 24).padding(.bottom, 22).padding(.top, 6)
        }
        .frame(width: 640)
        .glass(daylight, radius: 20, tint: .white.opacity(0.78))
    }
}

struct T6Terminal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            T.glow(Text("aitor@typer ~ % ").foregroundStyle(T.green.opacity(0.6)) + Text("./practice --lang es").foregroundStyle(T.green))
            T.glow(Text(painted(Ink(ok: T.green, bad: Color(0xFF3B3B), badBg: Color(0xFF3B3B, 0.25), pending: T.green.opacity(0.32), cursorBg: T.green, cursorFg: T.bg)))
                .lineSpacing(7))
            T.glow(Text("[ wpm 058 ]  [ acc 96% ]  [" + String(repeating: "█", count: Int(progress * 20)) + String(repeating: "░", count: 20 - Int(progress * 20)) + "] \(Int(progress * 100))%")
                .foregroundStyle(T.green.opacity(0.85)))
        }
        .font(.custom("Menlo", size: 17))
        .padding(26)
        .frame(width: 640, alignment: .leading)
        .background(T.bg)
        .overlay(Scanlines())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.green.opacity(0.35), lineWidth: 1))
    }
}

struct T7Typewriter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("HOJA Nº 12 — ESPAÑOL").tracking(2)
                Spacer()
                Text("tab · ⏎ · esc")
            }
            .font(.custom("American Typewriter", size: 12)).foregroundStyle(Color(0x8A7F6A))
            Text(painted(Ink(ok: Color(0x2B2622), bad: Color(0xB3261E), badStrike: true, pending: Color(0x2B2622, 0.27), cursorLine: Color(0xB3261E))))
                .font(.custom("American Typewriter", size: 22)).lineSpacing(10)
            HStack {
                Spacer()
                Text("58 ppm · 96%")
                    .font(.custom("American Typewriter", size: 18).bold()).foregroundStyle(Color(0xB3261E, 0.85))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(0xB3261E, 0.85), lineWidth: 2.5))
                    .rotationEffect(.degrees(-4))
            }
        }
        .padding(.vertical, 28).padding(.leading, 56).padding(.trailing, 32)
        .frame(width: 640)
        .background(Color(0xF4ECD8))
        .overlay(alignment: .leading) { Rectangle().fill(Color(0xE08A8A)).frame(width: 1.5).padding(.leading, 40) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct T8Focus: View {
    // Line breaks of the sample; the cursor (index 52) sits on the second line.
    let lines = [(0, 39), (39, 69), (69, 97)]
    let amber = Color(0xFFB86B)
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(painted(Ink(ok: .white.opacity(0.35), bad: Color(0xFF7A8A, 0.6), pending: .white.opacity(0.35)), from: lines[0].0, to: lines[0].1))
                    .font(.system(size: 18, design: .rounded))
                Text(painted(Ink(ok: .white, bad: Color(0xFF7A8A), badBg: Color(0xFF7A8A, 0.2), pending: .white.opacity(0.4), cursorLine: amber), from: lines[1].0, to: lines[1].1))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(painted(Ink(ok: .white, bad: .white, pending: .white.opacity(0.25)), from: lines[2].0, to: lines[2].1))
                    .font(.system(size: 18, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                ZStack {
                    Ring(value: progress, color: amber, track: .white.opacity(0.1), line: 6)
                    VStack(spacing: 0) {
                        Text("58").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("ppm").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.6)
                    }
                }
                .frame(width: 84, height: 84)
                Text("96%").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(amber)
            }
            .foregroundStyle(.white)
        }
        .padding(30)
        .frame(width: 640)
        .background(LinearGradient(colors: [Color(0x15152B), Color(0x2C1B40)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Result window designs

struct R1Gentleman: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                G.label("Palabras por minuto")
                Text("\(R.wpm)").font(.system(size: 104, weight: .heavy)).tracking(-3)
                    .foregroundStyle(LinearGradient(colors: [G.fg, G.pink], startPoint: .top, endPoint: .bottom))
                HStack(spacing: 8) {
                    // The sample round is the best of the last ten, so it shows the record tag.
                    Text("NUEVO RÉCORD").font(.custom(G.font, size: 11).bold()).foregroundStyle(G.yellow)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(G.yellow.opacity(0.7)))
                    Text("+\(R.wpm - R.average) sobre tu media").font(.system(size: 13)).foregroundStyle(G.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(G.border).frame(width: 1).padding(.vertical, 6)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 22) {
                GridRow { cell("\(R.accuracy)%", "precisión"); cell("\(R.seconds)s", "tiempo") }
                GridRow { cell("\(R.correct)", "correctas"); cell("\(R.wrong)", "errores", G.neon) }
            }
            .padding(.leading, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(30)
        .frame(width: 640)
        .background(G.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(G.border, lineWidth: 1))
    }

    func cell(_ value: String, _ caption: String, _ color: Color = G.pink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.custom(G.font, size: 30).bold()).foregroundStyle(color)
            Text(caption).font(.system(size: 12)).foregroundStyle(G.muted)
        }
    }
}

struct R2Glass: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("¡Ronda completada!").font(.system(size: 14, weight: .semibold, design: .rounded)).opacity(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(R.wpm)").font(.system(size: 92, weight: .bold, design: .rounded))
                        Text("ppm").font(.system(size: 22, weight: .semibold, design: .rounded)).opacity(0.75)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Bars(color: .white.opacity(0.35), last: .white, width: 9, height: 56)
                    Text("+\(R.wpm - R.average) sobre tu media").font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            HStack(spacing: 10) {
                chip("\(R.accuracy)%", "precisión")
                chip("\(R.seconds) s", "tiempo")
                chip("\(R.wrong)", "errores")
                Spacer()
                Text("⏎ otra  ·  esc").font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .padding(26)
        .frame(width: 640)
        .glass(vivid, radius: 30)
    }

    func chip(_ value: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.75)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(vivid, radius: 18)
    }
}

struct R3Minimal: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("\(R.wpm)").font(.system(size: 120, weight: .ultraLight, design: .monospaced)).foregroundStyle(Color(0x1A1A1A))
            Text("ppm").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color(0x9A9A93))
            Text("\(R.accuracy)% precisión  ·  \(R.seconds) s  ·  +\(R.wpm - R.average) sobre tu media")
                .font(.system(size: 14, weight: .light, design: .monospaced)).foregroundStyle(Color(0x55554F))
                .padding(.top, 18)
            Text("⏎ otra    esc cerrar").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(0xBDBDB6)).padding(.top, 22)
        }
        .padding(.vertical, 40)
        .frame(width: 640)
        .background(Color(0xFAFAF7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct R4Terminal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            T.glow(Text("aitor@typer ~ % ").foregroundStyle(T.green.opacity(0.6)) + Text("./practice --report").foregroundStyle(T.green))
            T.glow(Text("─────────────────────────────────────────").foregroundStyle(T.green.opacity(0.4)))
            line("wpm", String(format: "%03d", R.wpm), "▲ +\(R.wpm - R.average)  (avg \(R.average))")
            line("accuracy", "\(R.accuracy)%", "")
            line("time", "\(R.seconds)s", "")
            line("chars", "\(R.correct)", "ok · \(R.wrong) err")
            HStack(spacing: 0) {
                T.glow(Text("history   ").foregroundStyle(T.green.opacity(0.6)))
                T.glow(Bars(color: T.green.opacity(0.45), last: T.green, width: 7, height: 20))
                T.glow(Text("   last 10").foregroundStyle(T.green.opacity(0.6)))
            }
            T.glow(Text("─────────────────────────────────────────").foregroundStyle(T.green.opacity(0.4)))
            T.glow(Text("[enter] again   [tab] lang   [esc] quit").foregroundStyle(T.green.opacity(0.7)))
        }
        .font(.custom("Menlo", size: 17))
        .padding(26)
        .frame(width: 640, alignment: .leading)
        .background(T.bg)
        .overlay(Scanlines())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.green.opacity(0.35), lineWidth: 1))
    }

    func line(_ key: String, _ value: String, _ note: String) -> some View {
        T.glow(Text(key.padding(toLength: 10, withPad: " ", startingAt: 0)).foregroundStyle(T.green.opacity(0.6))
            + Text(value.padding(toLength: 12, withPad: " ", startingAt: 0)).foregroundStyle(T.green).bold()
            + Text(note).foregroundStyle(T.green.opacity(0.6)))
    }
}

struct R5Native: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { TrafficLights(); Spacer() }.padding(.horizontal, 16).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 18) {
                Label { Text("Ronda completada").foregroundStyle(.black.opacity(0.85)) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(0x30D158)) }
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    card("Velocidad", "\(R.wpm)", "ppm", Double(R.wpm) / 120, Color(0x0A84FF), "+\(R.wpm - R.average) sobre tu media")
                    card("Precisión", "\(R.accuracy)", "%", Double(R.accuracy) / 100, Color(0x30D158), "\(R.wrong) errores")
                    card("Tiempo", "\(R.seconds)", "s", Double(R.seconds) / 60, Color(0xFF9F0A), "\(R.correct) caracteres")
                }
                HStack(spacing: 10) {
                    Spacer()
                    button("Cerrar", "esc", primary: false)
                    button("Otro texto", "⏎", primary: true)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 22)
        }
        .frame(width: 640)
        .glass(daylight, radius: 20, tint: .white.opacity(0.78))
    }

    func card(_ title: String, _ value: String, _ unit: String, _ gauge: Double, _ color: Color, _ note: String) -> some View {
        HStack(spacing: 12) {
            Ring(value: gauge, color: color, track: color.opacity(0.15), line: 5).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 24, weight: .semibold))
                    Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.5))
                }
                Text(note).font(.system(size: 10)).foregroundStyle(.black.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.06)))
    }

    func button(_ title: String, _ key: String, primary: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(key).opacity(0.6)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(primary ? .white : .black.opacity(0.8))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(primary ? Color(0x0A84FF) : .white))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(primary ? 0 : 0.12)))
    }
}

// MARK: - Render

@MainActor func save(_ view: some View, _ name: String, to dir: URL, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("FAILED \(name)")
        exit(1)
    }
    try! png.write(to: dir.appendingPathComponent(name + ".png"))
    print("wrote \(name).png")
}

struct Sheet: View {
    var title: String
    var items: [(String, AnyView)]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.fixed(736), alignment: .top), GridItem(.fixed(736), alignment: .top)], alignment: .leading, spacing: 28) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(items[i].0).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        items[i].1.clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(40)
        .background(Color(0x111114))
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "design/mockups/out")
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let typing: [(String, String, AnyView)] = [
        ("typing-1-gentleman", "1 · Gentleman Programming", AnyView(Framed(wall: plum) { T1Gentleman() })),
        ("typing-2-liquid-glass", "2 · Liquid Glass", AnyView(Framed(wall: vivid) { T2Glass() })),
        ("typing-3-minimal", "3 · Minimalista", AnyView(Framed(wall: daylight) { T3Minimal() })),
        ("typing-4-y2k", "4 · Retro / Y2K", AnyView(Framed(wall: daylight) { T4Y2K() })),
        ("typing-5-native", "5 · Nativo macOS", AnyView(Framed(wall: daylight) { T5Native() })),
        ("typing-6-terminal", "6 · Terminal / hacker", AnyView(Framed(wall: dusk) { T6Terminal() })),
        ("typing-7-typewriter", "7 · Máquina de escribir (inventado)", AnyView(Framed(wall: dusk) { T7Typewriter() })),
        ("typing-8-focus", "8 · Foco: una línea a la vez (inventado)", AnyView(Framed(wall: dusk) { T8Focus() })),
    ]
    let results: [(String, String, AnyView)] = [
        ("result-1-gentleman", "A · Gentleman, layout tipo Raycast", AnyView(Framed(wall: plum) { R1Gentleman() })),
        ("result-2-liquid-glass", "B · Liquid Glass con historial", AnyView(Framed(wall: vivid) { R2Glass() })),
        ("result-3-minimal", "C · Minimalista", AnyView(Framed(wall: daylight) { R3Minimal() })),
        ("result-4-terminal", "D · Terminal: reporte", AnyView(Framed(wall: dusk) { R4Terminal() })),
        ("result-5-native", "E · Nativo macOS con medidores", AnyView(Framed(wall: daylight) { R5Native() })),
    ]
    for (file, _, view) in typing + results { save(view, file, to: out) }
    save(Sheet(title: "AiberTyper · ventana de práctica", items: typing.map { ($0.1, $0.2) }), "overview-typing", to: out, scale: 1)
    save(Sheet(title: "AiberTyper · ventana de resultados", items: results.map { ($0.1, $0.2) }), "overview-results", to: out, scale: 1)
}
