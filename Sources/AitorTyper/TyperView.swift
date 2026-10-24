import SwiftUI

struct TyperView: View {
    let session: Session
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(session.lang.label).font(.caption.bold())
                Spacer()
                Text("Tab idioma · Enter otro texto · Esc cerrar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(rendered)
                .font(.system(size: 20, design: .monospaced))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let r = session.result {
                results(r)
            } else {
                // Redraw twice a second so WPM keeps moving while you pause.
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    liveStats(session.live(now: context.date))
                }
            }
            // Hidden field: it receives the keystrokes so accents and ñ compose like in any text field.
            TextField("", text: Binding(get: { session.typed }, set: { session.type($0) }))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .padding(24)
        .frame(width: 640)
        .onAppear { focused = true }
        .onChange(of: session.round) { focused = true }
    }

    private var rendered: AttributedString {
        let typed = Array(session.typed)
        var out = AttributedString()
        for (i, c) in session.target.enumerated() {
            var a = AttributedString(String(c))
            if i < typed.count {
                let ok = typed[i] == c
                a.foregroundColor = ok ? .green : .red
                if !ok { a.backgroundColor = .red.opacity(0.25) }
            } else {
                a.foregroundColor = .secondary
                if i == typed.count { a.underlineStyle = .single }
            }
            out += a
        }
        return out
    }

    private func liveStats(_ stats: (wpm: Double, accuracy: Double)?) -> some View {
        HStack(spacing: 20) {
            Text(stats.map { "\(Int($0.wpm.rounded())) ppm" } ?? "— ppm").font(.title2.bold())
            Text(stats.map { "\(Int(($0.accuracy * 100).rounded()))% precisión" } ?? "—% precisión")
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func results(_ r: RoundResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 20) {
                Text("\(Int(r.wpm.rounded())) ppm").font(.title2.bold())
                Text("\(Int((r.accuracy * 100).rounded()))% precisión")
                if let avg = session.averageBefore {
                    let delta = Int((r.wpm - avg).rounded())
                    Text("media \(Int(avg.rounded())) ppm (\(delta >= 0 ? "+" : "")\(delta))")
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(r.seconds.rounded())) s").foregroundStyle(.secondary)
            }
            if !session.note.isEmpty {
                Text(session.note).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
