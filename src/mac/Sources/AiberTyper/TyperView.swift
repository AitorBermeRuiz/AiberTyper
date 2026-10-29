import AppKit
import SwiftUI

/// Aiber Bermejo palette and brand mark (see design/brand/README.md).
enum G {
    static let bg = Color(0x1B1113), fg = Color(0xF6EEF0), pink = Color(0xF497A9), neon = Color(0xE83A59)
    static let yellow = Color(0xF5D547)

    static func muted(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? Color(0xD9CCD0) : Color(0xAA989C) }
    static func border(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? Color(0x7C5E66) : Color(0x3C262B) }

    static let textSize: CGFloat = 23
    /// We wrap the text ourselves (to show only a few lines), so count how many monospaced characters fit
    /// the 584 pt text column (640 card minus 28 padding per side).
    static let charsPerLine: Int = {
        let font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        return max(10, Int((584 - 2) / advance))
    }()

    /// SF Mono: typed text, header signature, numbers.
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

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

    /// Official Aiber Logo 1B (chevron A with shortened right leg + base cursor bar) and product header.
    static var brand: some View {
        HStack(spacing: 8) {
            logo
            label("Aiber typer")
        }
    }

    static var logo: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, s = min(w, h)
            let stroke = s * 0.135
            var chevron = Path()
            chevron.move(to: CGPoint(x: w * 0.18, y: h * 0.77))
            chevron.addLine(to: CGPoint(x: w * 0.48, y: h * 0.21))
            chevron.addLine(to: CGPoint(x: w * 0.65, y: h * 0.53))
            ctx.stroke(chevron, with: .color(pink), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            let barY = h * 0.77 + stroke * 0.5 - stroke
            let cursor = CGRect(x: w * 0.56, y: barY, width: w * 0.30, height: stroke)
            ctx.fill(Path(roundedRect: cursor, cornerRadius: stroke * 0.48), with: .color(neon))
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// One bar per round, oldest first; the selected one (the latest round by default) is highlighted.
/// With `onSelect`, each bar lights up on hover and a click selects it.
struct WPMBars: View {
    let wpms: [Double]
    var height: CGFloat = 48
    var selected: Int? = nil
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(wpms.indices, id: \.self) { i in
                if let onSelect {
                    HoverButton(action: { onSelect(i) }) { hovered in
                        bar(i, hovered: hovered)
                            .frame(maxWidth: 22, maxHeight: .infinity, alignment: .bottom)
                            .contentShape(Rectangle()) // the whole column is clickable, not only the bar
                    }
                    .accessibilityLabel("Ronda \(i + 1): \(Int(wpms[i].rounded())) palabras por minuto")
                    .accessibilityAddTraits(i == highlighted ? .isSelected : [])
                } else {
                    bar(i, hovered: false)
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private var highlighted: Int { selected ?? wpms.count - 1 }

    private func bar(_ i: Int, hovered: Bool) -> some View {
        let top = wpms.max() ?? 0, low = (wpms.min() ?? 0) * 0.7
        return RoundedRectangle(cornerRadius: 3)
            .fill(i == highlighted ? AnyShapeStyle(LinearGradient(colors: [G.pink, G.neon], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(G.pink.opacity(hovered ? 0.65 : 0.3)))
            .frame(maxWidth: 22)
            .frame(height: top > low ? 6 + (height - 6) * (wpms[i] - low) / (top - low) : height)
    }
}

extension Color {
    init(_ hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Plain button that reports hover (for a light highlight) and shows a pointing-hand cursor.
struct HoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: (_ hovered: Bool) -> Label
    @StateObject private var hover = HoverState()

    var body: some View {
        // A click can hide or replace this view without a mouse-exit event, so clear the hover first.
        Button { hover.on = false; NSCursor.arrow.set(); action() } label: { label(hover.on) }
            .buttonStyle(.plain)
            .onHover { inside in
                hover.on = inside
                // set(), not push/pop: a view removed while hovered never pops, and pushes would pile up.
                (inside ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
            .animation(.easeOut(duration: 0.15), value: hover.on)
            // Removed or backgrounded while hovered: no mouse-exit arrives, so reset here.
            .onDisappear { hover.on = false; NSCursor.arrow.set() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in hover.on = false }
    }
}

/// Observable hover flag. `@StateObject` works without the SwiftUI macro plugin missing from this toolchain.
final class HoverState: ObservableObject {
    @Published var on = false
}

struct TyperView: View {
    let session: Session
    var onImport: () -> Void
    var onClose: () -> Void
    var onSettings: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var muted: Color { G.muted(contrast) }
    private var border: Color { G.border(contrast) }

    /// A click does what its key does, then hands keystrokes back to the hidden field.
    private func act(_ action: () -> Void) {
        action()
        focused = true
    }

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
            TextField("", text: Binding(get: { session.round.typed }, set: { session.type($0) }))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .onAppear { focused = true }
        .onChange(of: session.roundNumber) { focused = true }
    }

    private var typing: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                G.brand
                Spacer()
                pills([session.collection.name + " ▾"], selected: session.collection.name + " ▾", spoken: "Colección") {
                    session.openPicker()
                }
                pills([Lang.es.label, Lang.en.label], selected: session.lang.label, spoken: "Idioma") {
                    session.toggleLanguage()
                }
                HoverButton(action: { act(onSettings) }) { hovered in
                    Image(systemName: "gearshape").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(hovered ? G.pink : muted)
                        .contentShape(Rectangle())
                }
                .focusable(false)
                .help("Ajustes (⌘,)")
                .accessibilityLabel("Ajustes")
            }
            textLines
            if let source = session.round.source {
                Text("— \(source)").font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
            }
            // Redraw twice a second so WPM keeps moving while you pause; idle when hidden or not started.
            if session.visible, session.round.live() != nil {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    liveStats(session.round.live(now: context.date))
                }
            } else {
                liveStats(session.round.live())
            }
            progressBar
            HStack(spacing: 16) {
                keyHint("Tab", "idioma")
                keyHint("Shift+Tab", "colección")
                Spacer()
                roundActions
            }
        }
        .padding(28)
    }

    /// Mouse equivalents of Enter and Esc; each button shows its key.
    private var roundActions: some View {
        HStack(spacing: 10) {
            actionButton("Otra ronda", key: "Enter", primary: true) { session.newRound() }
            actionButton("Cerrar", key: "Esc", primary: false, action: onClose)
        }
    }

    private func actionButton(_ title: String, key: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HoverButton(action: { act(action) }) { hovered in
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                keycap(key, color: primary ? G.bg : hovered ? G.pink : muted)
            }
            .foregroundStyle(primary ? G.bg : hovered ? G.pink : muted)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(primary ? (hovered ? G.neon : G.pink) : .clear))
            .overlay(Capsule().strokeBorder(primary ? .clear : hovered ? G.pink : muted.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
        }
    }

    /// A key name in a small keycap followed by what it does.
    private func keyHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 6) {
            keycap(key, color: muted)
            Text(action).font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key): \(action)")
    }

    private func keycap(_ key: String, color: Color) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.7), lineWidth: 1))
    }

    /// Filterable list of collections; the keys are mapped by PanelKey in Keys.swift.
    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            G.label("Colección")
            Text(session.filter.isEmpty ? "escribe para filtrar" : session.filter)
                .font(G.mono(16))
                .foregroundStyle(session.filter.isEmpty ? muted : G.pink)
                .accessibilityLabel("Filtro: \(session.filter)")
            VStack(alignment: .leading, spacing: 4) {
                if session.matches.isEmpty {
                    Text("Sin resultados").font(.system(size: 14, design: .rounded)).foregroundStyle(muted)
                }
                ForEach(Array(session.matches.enumerated()), id: \.element.id) { i, collection in
                    let selected = i == session.selection
                    HoverButton(action: { act { session.chooseMatch(at: i) } }) { hovered in
                        HStack {
                            if session.favorites.contains(collection.id) { Text("★").accessibilityLabel("favorita") }
                            Text(collection.name).font(.system(size: 15, weight: selected ? .bold : .regular, design: .rounded))
                            Spacer()
                            if collection.id == session.collection.id { Text("✓").foregroundStyle(G.neon).accessibilityLabel("actual") }
                        }
                        .foregroundStyle(selected ? G.bg : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? G.pink : hovered ? G.pink.opacity(0.15) : .clear))
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            ForEach(session.problems, id: \.self) { Text($0).font(.system(size: 12, design: .rounded)).foregroundStyle(G.neon) }
            HoverButton(action: { act(onImport) }) { hovered in
                Text("＋ Importar colección…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(hovered ? G.neon : G.pink)
            }
            .focusable(false)
            HStack(spacing: 12) {
                keyHint("Ctrl+J/K", "mover")
                keyHint("Ctrl+F", "favorita")
                keyHint("Ctrl+I", "importar")
                keyHint("Enter", "elegir")
                keyHint("Esc", "volver")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
    }

    private func pills(_ labels: [String], selected: String, spoken: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                let isSelected = label == selected
                // Each option is its own target, so hovering one never restyles the others.
                // Clicking the already selected option of a group does nothing.
                HoverButton(action: { if !isSelected || labels.count == 1 { act(action) } }) { hovered in
                    Text(label)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? G.bg : hovered ? G.fg : muted)
                        .padding(.horizontal, isSelected ? 10 : 0).padding(.vertical, isSelected ? 3 : 0)
                        .background(Capsule().fill(isSelected ? (hovered ? G.neon : G.pink) : .clear))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken): \(selected)")
        .accessibilityAction { act(action) }
        .accessibilityAddTraits(.isButton)
    }

    /// Three sharp lines around the cursor, the line before and after blurred, the rest hidden.
    private var textLines: some View {
        let target = Array(session.round.target), typed = Array(session.round.typed)
        let lines = wrapLines(session.round.target, width: G.charsPerLine)
        let window = lineWindow(lines, cursor: typed.count)
        return VStack(alignment: .leading, spacing: 8) {
            if let before = window.before { dimmed(rendered(target, typed, lines[before])) }
            ForEach(window.focus, id: \.self) { text(rendered(target, typed, lines[$0])) }
            if let after = window.after { dimmed(rendered(target, typed, lines[after])) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ line: AttributedString) -> some View {
        Text(line)
            .font(G.mono(G.textSize))
            .lineLimit(1)
            .fixedSize()
    }

    private func dimmed(_ line: AttributedString) -> some View {
        text(line)
            .blur(radius: 1.5)
            .opacity(contrast == .increased ? 0.7 : 0.45)
            .accessibilityHidden(true)
    }

    /// One styled string per run of characters drawn alike: building one per character cost most of a keystroke.
    private func rendered(_ target: [Character], _ typed: [Character], _ range: Range<Int>) -> AttributedString {
        var out = AttributedString()
        for run in markRuns(target, typed: typed, in: range) {
            var a = AttributedString(String(target[run.range]))
            switch run.mark {
            case .correct: a.foregroundColor = G.fg
            case .wrong:
                a.foregroundColor = G.neon
                a.backgroundColor = G.neon.opacity(0.2)
            case .cursor:
                a.foregroundColor = G.bg
                a.backgroundColor = G.pink
            case .pending: a.foregroundColor = muted.opacity(contrast == .increased ? 0.8 : 0.5)
            }
            out += a
        }
        return out
    }

    private func liveStats(_ stats: (wpm: Double, accuracy: Double)?) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            cell(stats.map { "\(Int($0.wpm.rounded()))" } ?? "—", "ppm", size: 28,
                 spoken: stats.map { "\(Int($0.wpm.rounded())) palabras por minuto" } ?? "Palabras por minuto: sin datos")
            cell(stats.map { "\(Int(($0.accuracy * 100).rounded()))%" } ?? "—", "precisión", size: 28,
                 spoken: stats.map { "\(Int(($0.accuracy * 100).rounded())) por ciento de precisión" } ?? "Precisión: sin datos")
        }
    }

    private var progressBar: some View {
        let progress = session.round.target.isEmpty ? 0 : Double(session.round.typed.count) / Double(session.round.target.count)
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

    private func results(_ r: RoundResult) -> some View {
        let wpm = Int(r.wpm.rounded())
        let accuracy = Int((r.accuracy * 100).rounded())
        let seconds = Int(r.seconds.rounded())
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    G.label("Palabras por minuto")
                    Text("\(wpm)").font(.system(size: 104, weight: .heavy, design: .rounded)).tracking(-3)
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
                            Text("\(delta >= 0 ? "+" : "−")\(abs(delta)) sobre tu media").font(.system(size: 13, design: .rounded)).foregroundStyle(muted)
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
                        cell("\(session.round.correct)", "correctas", spoken: "\(session.round.correct) correctas")
                        cell("\(session.round.errors)", "errores", G.neon, spoken: "\(session.round.errors) errores")
                    }
                }
                .padding(.leading, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.recentWPMs.count > 1 { historyChart(session.recentWPMs) }
            HStack {
                if !session.note.isEmpty {
                    Text(session.note).font(.system(size: 12, design: .rounded)).foregroundStyle(G.neon)
                }
                Spacer()
                roundActions
            }
        }
        .padding(30)
    }

    /// Bars for recent rounds; the last one (this round) is highlighted.
    private func historyChart(_ wpms: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                G.label("Historial")
                Spacer()
                Text("últimas \(wpms.count) rondas").font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
            }
            WPMBars(wpms: wpms)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(border).frame(height: 1).accessibilityHidden(true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Historial de las últimas \(wpms.count) rondas: " + wpms.map { "\(Int($0.rounded()))" }.joined(separator: ", ") + " palabras por minuto")
    }

    private func cell(_ value: String, _ caption: String, _ color: Color = G.pink, size: CGFloat = 30, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(G.mono(size).bold()).foregroundStyle(color)
            Text(caption).font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
