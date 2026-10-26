import SwiftUI

// README banners, 1280×400 pt: B (a quote typing itself, animated) is the header; A (icon and wordmark) is kept
// as an alternative.

private let muted = G.muted(.standard), edge = G.border(.standard)

/// Logo 1B at any size (G.brand draws it at 16 pt only). Geometry from Brand/README.md.
struct Mark: View {
    var size: CGFloat
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height, stroke = w * 0.135
            var p = Path()
            p.move(to: CGPoint(x: w * 0.18, y: h * 0.77))
            p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.21))
            p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.53))
            ctx.stroke(p, with: .color(G.pink), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.56, y: h * 0.7025, width: w * 0.30, height: stroke), cornerRadius: stroke * 0.48),
                     with: .color(G.neon))
        }
        .frame(width: size, height: size)
    }
}

struct Keycap: View {
    var key: String
    var size: CGFloat
    var body: some View {
        Text(key).font(.system(size: size, weight: .semibold)).foregroundStyle(G.fg)
            .frame(minWidth: size * 1.9, minHeight: size * 1.9)
            .background(RoundedRectangle(cornerRadius: size * 0.35).fill(Color(0x2A1A1E)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.35).strokeBorder(edge, lineWidth: 1.5))
            .background(RoundedRectangle(cornerRadius: size * 0.35).fill(Color(0x0C0607)).offset(y: size * 0.14))
    }
}

struct BannerBackground<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(width: 1280, height: 400)
            .background {
                ZStack {
                    Color(0x120A0C)
                    RadialGradient(colors: [G.pink.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
                    RadialGradient(colors: [G.neon.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 600)
                }
            }
    }
}

struct BannerCopy {
    let quote: String, source: String, tagline: String, wpm: String, accuracy: String, time: String

    static func of(_ lang: Lang) -> BannerCopy {
        lang == .es
            ? BannerCopy(quote: "No discutas más sobre cómo debe ser el hombre bueno, sino sé tú uno.",
                         source: "Marco Aurelio, Meditaciones, X.16", tagline: "Practica mecanografía desde la barra de menús",
                         wpm: "ppm", accuracy: "precisión", time: "tiempo")
            : BannerCopy(quote: "No longer talk at all about the kind of man that a good man ought to be, but be such.",
                         source: "Marcus Aurelius, Meditations, X.16 (tr. Long)", tagline: "Typing practice from your Mac's menu bar",
                         wpm: "wpm", accuracy: "accuracy", time: "time")
    }
}

/// Banner B at one moment: `typed` characters of the quote typed, the last one wrong when `typo`.
struct TypingBanner: View {
    let copy: BannerCopy
    let typed: Int
    var typo = false
    var caret = true
    var stats: (wpm: Int, accuracy: Int, seconds: Int)?

    var body: some View {
        let chars = Array(copy.quote)
        BannerBackground {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Mark(size: 40)
                    Text("AIBER TYPER").font(G.mono(26).bold()).tracking(5).foregroundStyle(G.pink)
                    Spacer()
                    HStack(spacing: 10) { Keycap(key: "⌥", size: 20); Keycap(key: "⇧", size: 20); Keycap(key: "T", size: 20) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(wrapLines(copy.quote, width: 54), id: \.self) { line in
                        HStack(spacing: 0) {
                            ForEach(Array(line), id: \.self) { i in
                                char(chars[i], at: i)
                            }
                        }
                    }
                }
                .font(G.mono(34))
                .fixedSize()
                .frame(height: 96, alignment: .top)
                Text("— " + copy.source).font(.system(size: 19)).foregroundStyle(muted)
                HStack(spacing: 40) {
                    stat(stats.map { "\($0.wpm)" } ?? "–", copy.wpm)
                    stat(stats.map { "\($0.accuracy)%" } ?? "–", copy.accuracy)
                    stat(stats.map { String(format: "0:%02d", $0.seconds) } ?? "–", copy.time)
                    Spacer()
                    Text(copy.tagline).font(G.mono(22)).foregroundStyle(muted)
                }
            }
            .padding(.horizontal, 80)
        }
    }

    private func char(_ c: Character, at i: Int) -> some View {
        let wrong = typo && i == typed - 1
        let atCaret = caret && i == typed
        return Text(String(c))
            .foregroundStyle(wrong ? G.neon : atCaret ? G.bg : i < typed ? G.fg : muted.opacity(0.55))
            .background(wrong ? G.neon.opacity(0.2) : atCaret ? G.pink : .clear)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(G.mono(44).bold()).foregroundStyle(G.pink)
            Text(label).font(G.mono(20)).foregroundStyle(muted)
        }
    }
}

/// Banner A: app icon, wordmark, tagline and the shortcut.
struct IconBanner: View {
    let copy: BannerCopy
    var body: some View {
        BannerBackground {
            HStack(spacing: 64) {
                ZStack {
                    RoundedRectangle(cornerRadius: 52, style: .continuous).fill(G.bg)
                    RoundedRectangle(cornerRadius: 52, style: .continuous)
                        .fill(RadialGradient(colors: [G.pink.opacity(0.32), G.neon.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 250))
                    RoundedRectangle(cornerRadius: 52, style: .continuous).strokeBorder(edge, lineWidth: 2)
                    Mark(size: 166)
                }
                .frame(width: 230, height: 230)
                .shadow(color: G.neon.opacity(0.35), radius: 40)
                VStack(alignment: .leading, spacing: 18) {
                    Text("AIBER TYPER").font(G.mono(84).weight(.heavy)).tracking(6).foregroundStyle(G.fg)
                    Text(copy.tagline).font(G.mono(28)).foregroundStyle(muted)
                    HStack(spacing: 14) {
                        Keycap(key: "⌥", size: 30); Keycap(key: "⇧", size: 30); Keycap(key: "T", size: 30)
                        Text("\(copy.wpm) · \(copy.accuracy)").font(G.mono(22)).foregroundStyle(G.pink).padding(.leading, 12)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

/// Banner B frames: the caret blinks, the quote types itself with one typo fixed by backspace, then holds.
func bannerFrames(_ copy: BannerCopy) -> [(view: TypingBanner, delay: Double)] {
    let count = copy.quote.count
    let typoAt = Int(Double(count) * 0.55)
    // The stats a 78 wpm typist would show; the animation itself runs faster than that.
    func stats(_ typed: Int, errors: Int) -> (wpm: Int, accuracy: Int, seconds: Int)? {
        guard typed > 0 else { return nil }
        let seconds = Double(typed) / (78 * 5 / 60)
        return (78, Int((Double(typed) / Double(typed + errors) * 100).rounded()), Int(seconds.rounded()))
    }
    var frames: [(view: TypingBanner, delay: Double)] = []
    for on in [true, false, true, false] { frames.append((TypingBanner(copy: copy, typed: 0, caret: on), 0.45)) }
    var errors = 0
    for typed in 1...count {
        if typed == typoAt + 1 {
            errors = 1
            frames.append((TypingBanner(copy: copy, typed: typed, typo: true, stats: stats(typed - 1, errors: 1)), 0.35))
            frames.append((TypingBanner(copy: copy, typed: typed - 1, stats: stats(typed - 1, errors: 1)), 0.2))
        }
        let pause = Array(copy.quote)[typed - 1] == " " ? 0.09 : 0.06
        frames.append((TypingBanner(copy: copy, typed: typed, caret: typed < count, stats: stats(typed, errors: errors)), pause))
    }
    frames[frames.count - 1].delay = 3.5
    return frames
}
