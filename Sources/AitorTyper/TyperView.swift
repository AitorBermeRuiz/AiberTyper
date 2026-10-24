import AppKit
import SwiftUI

/// Gentleman style: the Gentle-AI palette (see Designs/main.swift, T1Gentleman / R1Gentleman).
enum G {
    static let bg = Color(0x1A1217), fg = Color(0xF5EEF2), pink = Color(0xF19AC8), neon = Color(0xE8418C)
    static let yellow = Color(0xF5D547)
    static let fontName = "IosevkaTerm Nerd Font"

    static func muted(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? Color(0xD8CDD3) : Color(0xA99AA3) }
    static func border(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? Color(0x7A6170) : Color(0x3A2A33) }

    static let textSize: CGFloat = 23
    /// We wrap the text ourselves (to show only a few lines), so count how many monospaced characters fit
    /// the 584 pt text column (640 card minus 28 padding per side).
    static let charsPerLine: Int = {
        let font = NSFont(name: fontName, size: textSize) ?? .monospacedSystemFont(ofSize: textSize, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        return max(10, Int((584 - 2) / advance))
    }()

    /// Looked up once, like `charsPerLine`: installing the font while the app runs needs a restart.
    private static let hasFont = NSFont(name: fontName, size: textSize) != nil

    /// IosevkaTerm when installed, otherwise the system monospaced font.
    static func mono(_ size: CGFloat) -> Font {
        hasFont ? .custom(fontName, size: size) : .system(size: size, design: .monospaced)
    }

    /// Plum background with the soft pink glow from the top-left corner.
    static var background: some View {
        ZStack {
            bg
            RadialGradient(colors: [pink.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
        }
    }

    static func label(_ s: String) -> some View {
        Text(s.uppercased()).font(mono(12)).tracking(2).foregroundStyle(pink)
    }
}

extension Color {
    init(_ hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct TyperView: View {
    let session: Session
    var onImport: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var muted: Color { G.muted(contrast) }
    private var border: Color { G.border(contrast) }

    var body: some View {
        Group {
            if session.picking {
                picker
            } else if let r = session.result {
                results(r)
            } else {
                typing
            }
        }
        .frame(width: 640)
        .background(G.background.accessibilityHidden(true))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 1))
        .background(alignment: .topLeading) {
            // Hidden field: it receives the keystrokes so accents and ñ compose like in any text field.
            TextField("", text: Binding(get: { session.typed }, set: { session.type($0) }))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .onAppear { focused = true }
        .onChange(of: session.round) { focused = true }
    }

    private var typing: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                G.label("Gentle typer")
                Spacer()
                pills([session.collection.name + " ▾"], selected: session.collection.name + " ▾", spoken: "Colección")
                pills([Lang.es.label, Lang.en.label], selected: session.lang.label, spoken: "Idioma")
            }
            textLines
            if let source = session.source {
                Text("— \(source)").font(.system(size: 12)).foregroundStyle(muted)
            }
            // Redraw twice a second so WPM keeps moving while you pause; idle when hidden or not started.
            if session.visible, session.live() != nil {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    liveStats(session.live(now: context.date))
                }
            } else {
                liveStats(session.live())
            }
            progressBar
            Text("tab idioma · ⇧tab colección · ⏎ otra · esc cerrar").font(G.mono(12)).foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
    }

    /// Filterable list of collections; the keys are handled in AppDelegate.pickerKey.
    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            G.label("Colección")
            Text(session.filter.isEmpty ? "escribe para filtrar" : session.filter)
                .font(G.mono(16))
                .foregroundStyle(session.filter.isEmpty ? muted : G.pink)
                .accessibilityLabel("Filtro: \(session.filter)")
            VStack(alignment: .leading, spacing: 4) {
                if session.matches.isEmpty {
                    Text("Sin resultados").font(.system(size: 14)).foregroundStyle(muted)
                }
                ForEach(Array(session.matches.enumerated()), id: \.element.id) { i, collection in
                    let selected = i == session.selection
                    HStack {
                        if session.favorites.contains(collection.id) { Text("★").accessibilityLabel("favorita") }
                        Text(collection.name).font(.system(size: 15, weight: selected ? .bold : .regular))
                        Spacer()
                        if collection.id == session.collection.id { Text("✓").foregroundStyle(G.neon).accessibilityLabel("actual") }
                    }
                    .foregroundStyle(selected ? G.bg : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? G.pink : .clear))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            ForEach(session.problems, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(G.neon) }
            Button("＋ Importar colección…", action: onImport)
                .buttonStyle(.plain)
                .focusable(false)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(G.pink)
            Text("⌃j/⌃k ↑↓ mover · ⌃f favorita · ⌃i importar · ⏎ elegir · esc volver").font(G.mono(12)).foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
    }

    private func pills(_ labels: [String], selected: String, spoken: String) -> some View {
        HStack(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                if label == selected {
                    Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(G.bg)
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(G.pink))
                } else {
                    Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken): \(selected)")
    }

    /// Three sharp lines around the cursor, the line before and after blurred, the rest hidden.
    private var textLines: some View {
        let lines = wrapLines(session.target, width: G.charsPerLine)
        let window = lineWindow(lines, cursor: session.typed.count)
        return VStack(alignment: .leading, spacing: 8) {
            if let before = window.before { dimmed(lines[before]) }
            ForEach(window.focus, id: \.self) { text(lines[$0]) }
            if let after = window.after { dimmed(lines[after]) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ range: Range<Int>) -> some View {
        Text(rendered(range))
            .font(G.mono(G.textSize))
            .lineLimit(1)
            .fixedSize()
    }

    private func dimmed(_ range: Range<Int>) -> some View {
        text(range)
            .blur(radius: 1.5)
            .opacity(contrast == .increased ? 0.7 : 0.45)
            .accessibilityHidden(true)
    }

    private func rendered(_ range: Range<Int>) -> AttributedString {
        let typed = Array(session.typed)
        var out = AttributedString()
        for (i, c) in session.target.enumerated() where range.contains(i) {
            var a = AttributedString(String(c))
            if i < typed.count {
                if typed[i] == c {
                    a.foregroundColor = G.fg
                } else {
                    a.foregroundColor = G.neon
                    a.backgroundColor = G.neon.opacity(0.2)
                }
            } else if i == typed.count {
                a.foregroundColor = G.bg
                a.backgroundColor = G.pink
            } else {
                a.foregroundColor = muted.opacity(contrast == .increased ? 0.8 : 0.5)
            }
            out += a
        }
        return out
    }

    private func liveStats(_ stats: (wpm: Double, accuracy: Double)?) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            stat(stats.map { "\(Int($0.wpm.rounded()))" } ?? "—", "ppm",
                 spoken: stats.map { "\(Int($0.wpm.rounded())) palabras por minuto" } ?? "Palabras por minuto: sin datos")
            stat(stats.map { "\(Int(($0.accuracy * 100).rounded()))%" } ?? "—", "precisión",
                 spoken: stats.map { "\(Int(($0.accuracy * 100).rounded())) por ciento de precisión" } ?? "Precisión: sin datos")
            Spacer()
            Text("tab idioma · ⏎ otro · esc cerrar").font(G.mono(12)).foregroundStyle(muted)
        }
    }

    private var progressBar: some View {
        let progress = session.target.isEmpty ? 0 : Double(session.typed.count) / Double(session.target.count)
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(border)
                Capsule().fill(LinearGradient(colors: [G.pink, G.neon], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * progress)
                    .shadow(color: G.neon.opacity(0.8), radius: 6)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progreso")
        .accessibilityValue("\(Int((progress * 100).rounded())) por ciento")
    }

    private func stat(_ value: String, _ caption: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(G.mono(28).bold()).foregroundStyle(G.pink)
            Text(caption).font(.system(size: 12)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func results(_ r: RoundResult) -> some View {
        let wpm = Int(r.wpm.rounded())
        let accuracy = Int((r.accuracy * 100).rounded())
        let seconds = Int(r.seconds.rounded())
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    G.label("Palabras por minuto")
                    Text("\(wpm)").font(.system(size: 104, weight: .heavy)).tracking(-3)
                        .foregroundStyle(LinearGradient(colors: [G.fg, G.pink], startPoint: .top, endPoint: .bottom))
                        .accessibilityLabel("\(wpm) palabras por minuto")
                    HStack(spacing: 8) {
                        if session.isRecord {
                            Text("NUEVO RÉCORD").font(G.mono(11).bold()).foregroundStyle(G.yellow)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(G.yellow.opacity(0.7)))
                                .accessibilityLabel("Nuevo récord")
                        }
                        if let avg = session.averageBefore {
                            let delta = Int((r.wpm - avg).rounded())
                            Text("\(delta >= 0 ? "+" : "−")\(abs(delta)) sobre tu media").font(.system(size: 13)).foregroundStyle(muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(border).frame(width: 1).padding(.vertical, 6).accessibilityHidden(true)
                Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 22) {
                    GridRow {
                        cell("\(accuracy)%", "precisión", spoken: "\(accuracy) por ciento de precisión")
                        cell("\(seconds)s", "tiempo", spoken: "\(seconds) segundos")
                    }
                    GridRow {
                        cell("\(session.correct)", "correctas", spoken: "\(session.correct) correctas")
                        cell("\(session.errors)", "errores", G.neon, spoken: "\(session.errors) errores")
                    }
                }
                .padding(.leading, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.recentWPMs.count > 1 { historyChart(session.recentWPMs) }
            HStack {
                if !session.note.isEmpty {
                    Text(session.note).font(.system(size: 12)).foregroundStyle(G.neon)
                }
                Spacer()
                Text("⏎ otra · esc cerrar").font(G.mono(12)).foregroundStyle(muted)
            }
        }
        .padding(30)
    }

    /// Bars for recent rounds; the last one (this round) is highlighted.
    private func historyChart(_ wpms: [Double]) -> some View {
        let top = wpms.max()!, low = wpms.min()! * 0.7
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                G.label("Historial")
                Spacer()
                Text("últimas \(wpms.count) rondas").font(.system(size: 12)).foregroundStyle(muted)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(wpms.indices, id: \.self) { i in
                    let isLast = i == wpms.count - 1
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLast ? AnyShapeStyle(LinearGradient(colors: [G.pink, G.neon], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(G.pink.opacity(0.3)))
                        .frame(maxWidth: 22)
                        .frame(height: top > low ? 6 + 42 * (wpms[i] - low) / (top - low) : 48)
                }
            }
            .frame(height: 48, alignment: .bottom)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(border).frame(height: 1).accessibilityHidden(true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Historial de las últimas \(wpms.count) rondas: " + wpms.map { "\(Int($0.rounded()))" }.joined(separator: ", ") + " palabras por minuto")
    }

    private func cell(_ value: String, _ caption: String, _ color: Color = G.pink, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(G.mono(30).bold()).foregroundStyle(color)
            Text(caption).font(.system(size: 12)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
