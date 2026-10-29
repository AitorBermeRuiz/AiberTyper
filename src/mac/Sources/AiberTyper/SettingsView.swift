import SwiftUI

/// The tab shown in the settings window. `@StateObject` works without the SwiftUI macro plugin missing from this toolchain.
final class SettingsTab: ObservableObject {
    enum Tab: String, CaseIterable { case ajustes = "Ajustes", colecciones = "Colecciones", historial = "Historial" }
    @Published var tab = Tab.ajustes
    /// Bar clicked in Historial, as an index into the last 20 rounds; nil means the latest one.
    @Published var bar: Int?
}

/// Settings window (design/settings-window/02): Ajustes, Colecciones and Historial tabs.
struct SettingsView: View {
    let session: Session
    let hotKey: String
    var onChangeHotKey: () -> Void
    var onImport: () -> Void
    var onOpenFolder: () -> Void
    @StateObject private var current = SettingsTab()
    @AppStorage("hideImportHelp") private var hideImportHelp = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var muted: Color { G.muted(contrast) }
    private var border: Color { G.border(contrast) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(border).frame(height: 1).accessibilityHidden(true)
            Group {
                switch current.tab {
                case .ajustes: ajustes
                case .colecciones: colecciones
                case .historial: historial
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 640, height: 560)
        .background(G.bg)
        .foregroundStyle(G.fg)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            // Same row as the traffic lights.
            HStack(spacing: 8) {
                G.logo
                G.label(current.tab.rawValue)
            }
            .frame(height: 28)
            HStack(spacing: 6) {
                tabButton(.ajustes, icon: "keyboard")
                tabButton(.colecciones, icon: "books.vertical")
                tabButton(.historial, icon: "chart.line.uptrend.xyaxis")
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(G.background.accessibilityHidden(true))
    }

    private func tabButton(_ tab: SettingsTab.Tab, icon: String) -> some View {
        let selected = current.tab == tab
        return HoverButton(action: { current.tab = tab }) { hovered in
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18)).frame(height: 22)
                Text(tab.rawValue).font(.system(size: 11, weight: selected ? .bold : .regular, design: .rounded))
            }
            .foregroundStyle(selected ? G.pink : G.muted(.increased))
            .frame(width: 84).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(G.pink.opacity(selected ? 0.18 : hovered ? 0.15 : 0)))
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Ajustes

    private var ajustes: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Atajo")
            line("Abrir el panel", "Funciona desde cualquier app.") {
                HStack(spacing: 10) {
                    Text(hotKey).font(G.mono(13).weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(muted.opacity(0.6), lineWidth: 1))
                        .accessibilityLabel("Atajo: \(hotKey)")
                    link("Cambiar", action: onChangeHotKey)
                }
            }
            section("Frases")
            line("Idioma", "Tab lo cambia en el panel.") {
                HStack(spacing: 0) {
                    ForEach([Lang.es, Lang.en], id: \.self) { lang in
                        let on = session.lang == lang
                        HoverButton(action: { if !on { session.toggleLanguage() } }) { hovered in
                            Text(lang.label)
                                .font(.system(size: 12, weight: on ? .bold : .regular, design: .rounded))
                                .foregroundStyle(on ? G.bg : hovered ? G.fg : G.muted(.increased))
                                .padding(.horizontal, 12).padding(.vertical, 3)
                                .background(Capsule().fill(on ? G.pink : .clear))
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(2)
                .overlay(Capsule().strokeBorder(muted.opacity(0.6), lineWidth: 1))
            }
            line("Colección activa", "Se elige en Colecciones o con Shift+Tab en el panel.") {
                link(session.collection.name + " ›") { current.tab = .colecciones }
            }
            section("Importar")
            HoverButton(action: { hideImportHelp.toggle() }) { _ in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(hideImportHelp ? .clear : G.bg)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4).fill(hideImportHelp ? .clear : G.pink))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(hideImportHelp ? muted : .clear, lineWidth: 1))
                    Text("Mostrar el formato al importar").font(.system(size: 13, design: .rounded))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(hideImportHelp ? [] : .isSelected)
            Spacer()
            HStack {
                Text("Aiber Typer")
                Spacer()
                Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"))
            }
            .font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(G.mono(11).weight(.semibold)).tracking(2).foregroundStyle(muted)
            .padding(.top, 22).padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }

    private func line<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium, design: .rounded))
                Text(detail).font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 1).accessibilityHidden(true) }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        HoverButton(action: action) { hovered in
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(hovered ? G.neon : G.pink)
        }
    }

    // MARK: Colecciones

    private var colecciones: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(session.sortedCollections, id: \.id) { collectionRow($0) }
                }
                .padding(6)
            }
            .frame(height: 280)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
            .padding(.top, 20)
            ForEach(session.problems, id: \.self) { Text($0).font(.system(size: 12, design: .rounded)).foregroundStyle(G.neon) }
            HStack(spacing: 10) {
                pillButton("Importar…", primary: true, action: onImport)
                pillButton("Abrir carpeta", primary: false, action: onOpenFolder)
                Spacer()
                Text("☆ marca una colección como favorita").font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
            }
        }
    }

    private func collectionRow(_ collection: Collection) -> some View {
        let active = collection.id == session.collection.id
        let favorite = session.favorites.contains(collection.id)
        return HoverButton(action: { session.choose(collection) }) { hovered in
            HStack(spacing: 10) {
                Color.clear.frame(width: 16, height: 1) // room for the star button on top
                Text(collection.name).font(.system(size: 15, weight: active ? .bold : .regular, design: .rounded))
                if collection.id.hasPrefix("file:") {
                    Text(collection.id.dropFirst(5)).font(G.mono(11))
                        .foregroundStyle(active ? G.bg : G.muted(.increased))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(active ? G.bg : muted.opacity(0.6), lineWidth: 1))
                }
                Spacer()
                Text("\(collection.quotes(session.lang).count) frases" + (active ? " · activa" : ""))
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(active ? G.bg : muted)
            }
            .foregroundStyle(active ? G.bg : G.fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? G.pink : hovered ? G.pink.opacity(0.15) : .clear))
        }
        .accessibilityAddTraits(active ? .isSelected : [])
        .overlay(alignment: .leading) {
            HoverButton(action: { session.toggleFavorite(collection) }) { hovered in
                Text(favorite ? "★" : "☆").font(.system(size: 14))
                    .foregroundStyle(active ? G.bg : favorite || hovered ? G.yellow : muted)
                    .frame(width: 16)
            }
            .padding(.leading, 12)
            .accessibilityLabel(favorite ? "Quitar \(collection.name) de favoritas" : "Marcar \(collection.name) como favorita")
        }
    }

    private func pillButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        HoverButton(action: action) { hovered in
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primary ? G.bg : hovered ? G.pink : G.fg)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(primary ? (hovered ? G.neon : G.pink) : .clear))
                .overlay(Capsule().strokeBorder(primary ? .clear : hovered ? G.pink : muted.opacity(0.6), lineWidth: 1))
                .contentShape(Capsule())
        }
    }

    // MARK: Historial

    private var historial: some View {
        let rounds = session.rounds, recent = session.recentWPMs
        return VStack(alignment: .leading, spacing: 0) {
            if rounds.isEmpty {
                Text("Todavía no hay rondas. Pulsa \(hotKey) para practicar.")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(muted).padding(.top, 22)
            } else {
                HStack(spacing: 34) {
                    stat("\(Int((recent.reduce(0, +) / Double(recent.count)).rounded()))", "media últimas \(recent.count)")
                    stat("\(Int(rounds.map(\.wpm).max()!.rounded()))", "récord")
                    stat("\(Int((rounds.map(\.accuracy).reduce(0, +) / Double(rounds.count) * 100).rounded()))%", "precisión media")
                    stat("\(rounds.count)", rounds.count == 1 ? "ronda" : "rondas")
                }
                .padding(.top, 22)
                if recent.count > 1 {
                    let selected = current.bar.flatMap { recent.indices.contains($0) ? $0 : nil } ?? recent.count - 1
                    WPMBars(wpms: recent, height: 90, selected: selected) { current.bar = $0 }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 1).allowsHitTesting(false) }
                    roundDetail(Array(rounds.suffix(recent.count))[selected], latest: selected == recent.count - 1,
                                average: recent.reduce(0, +) / Double(recent.count))
                }
                VStack(spacing: 0) {
                    ForEach(Array(rounds.suffix(3).reversed().enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(Self.when(r.date)).foregroundStyle(muted).frame(width: 120, alignment: .leading)
                            Text(r.lang.label)
                            Spacer()
                            Text("\(Int(r.wpm.rounded())) ppm").font(G.mono(13).weight(.semibold)).frame(width: 80, alignment: .trailing)
                            Text("\(Int((r.accuracy * 100).rounded()))%").font(G.mono(13).weight(.semibold)).frame(width: 60, alignment: .trailing)
                        }
                        .font(.system(size: 13, design: .rounded))
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 1).accessibilityHidden(true) }
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    /// The numbers of the round whose bar is selected.
    private func roundDetail(_ r: RoundResult, latest: Bool, average: Double) -> some View {
        let delta = Int((r.wpm - average).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Self.when(r.date) + " · " + r.lang.label).font(.system(size: 12, weight: .semibold, design: .rounded))
                if latest { Text("última ronda").font(.system(size: 12, design: .rounded)).foregroundStyle(muted) }
                Spacer()
                Text("Haz clic en una barra para ver esa ronda").font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
            }
            HStack(spacing: 34) {
                stat("\(Int(r.wpm.rounded()))", "ppm")
                stat("\(Int((r.accuracy * 100).rounded()))%", "precisión")
                stat("\(Int(r.seconds.rounded()))s", "tiempo")
                stat("\(delta >= 0 ? "+" : "−")\(abs(delta))", "sobre tu media")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(G.mono(26).bold()).foregroundStyle(G.pink)
            Text(caption).font(.system(size: 12, design: .rounded)).foregroundStyle(muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Hoy, 22:41", "Ayer, 19:05" or "3 oct, 18:20".
    private static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Hoy, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Ayer, \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es"))) + ", \(time)"
    }
}
