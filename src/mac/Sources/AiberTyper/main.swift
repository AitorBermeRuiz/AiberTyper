import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `--bench`: bench.sh drives this instance through stdin, with a temporary history and settings, never the user's.
let bench = CommandLine.arguments.contains("--bench")
let benchDir = FileManager.default.temporaryDirectory.appendingPathComponent("aiber-bench-\(UUID().uuidString)")

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let session: Session = {
        guard bench else { return Session() }
        UserDefaults.standard.removePersistentDomain(forName: "aiber-bench")
        return Session(history: History(url: benchDir.appendingPathComponent("history.json")), folder: benchDir.appendingPathComponent("Colecciones"),
                       defaults: UserDefaults(suiteName: "aiber-bench")!)
    }()
    var panel: NSPanel!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var practice: NSMenuItem!
    var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        // The SwiftUI card draws its own rounded background; the theme is dark-only.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingController(rootView: TyperView(session: session, onImport: { [weak self] in self?.importCollections() }, onClose: { [weak self] in self?.hide() },
                                                           onSettings: { [weak self] in self?.hide(); self?.showSettings() }))
        host.sizingOptions = [.preferredContentSize]
        // Under the transparent titlebar, safe-area changes on every resize loop the layout and AppKit aborts.
        host.safeAreaRegions = []
        panel.contentViewController = host


        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        practice = NSMenuItem(title: "Practicar", action: #selector(show), keyEquivalent: "")
        practice.target = self
        menu.addItem(practice)
        menu.addItem(withTitle: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",").target = self
        apply(HotKey.saved)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch PanelKey(event: event, picking: self.session.picking) {
            case .pass: return event
            case .ignore: break
            case .hide: self.hide()
            case .openPicker: self.session.openPicker()
            case .toggleLanguage: self.session.toggleLanguage()
            case .newRound: self.session.newRound()
            case .settings: self.hide(); self.showSettings()
            case .closePicker: self.session.closePicker()
            case .choose: self.session.choosePicked()
            case .delete: self.session.deleteInPicker()
            case .favorite: self.session.toggleFavoritePicked()
            case .importCollections: self.importCollections()
            case .move(let step): self.session.movePicker(step)
            case .filter(let chars): self.session.typeInPicker(chars)
            }
            return nil
        }
        if bench { readBenchCommands() }
    }

    /// One command per line: `show`, `hide`, `type <wpm>`. Each answers one line when done; end of input quits.
    func readBenchCommands() {
        setlinebuf(stdout)
        print("ready \(benchDir.path)")
        Thread.detachNewThread {
            while let line = readLine() {
                DispatchQueue.main.async { self.runBench(line.split(separator: " ").map(String.init)) }
            }
            DispatchQueue.main.async {
                // The benchmark's rounds and settings never outlive the run.
                try? FileManager.default.removeItem(at: benchDir)
                UserDefaults.standard.removePersistentDomain(forName: "aiber-bench")
                NSApp.terminate(nil)
            }
        }
    }

    func runBench(_ command: [String]) {
        switch command.first {
        case "show": show(); print("shown")
        case "hide": hide(); print("hidden")
        case "type":
            // Real key events through the app's queue: the key monitor, the hidden field and session.type, as when typing.
            let gap = 60 / ((Double(command.last!) ?? 80) * 5)
            let chars = Array(session.round.target)
            for (i, c) in chars.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + gap * Double(i)) { [self] in
                    NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: panel.windowNumber, context: nil, characters: String(c),
                                                     charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: 0)!, atStart: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gap * Double(chars.count) + 0.5) { [self] in
                let r = session.result
                print("typed chars=\(chars.count) wpm=\(Int(r?.wpm ?? 0)) accuracy=\(Int((r?.accuracy ?? 0) * 100)) finished=\(r != nil)")
            }
        default: print("unknown")
        }
    }

    /// Covers every way the panel leaves the screen, including hidesOnDeactivate, which skips hide().
    func windowDidChangeOcclusionState(_ notification: Notification) {
        session.visible = panel.occlusionState.contains(.visible)
    }

    /// Settings window with the Ajustes, Colecciones and Historial tabs; created on first use.
    @objc func showSettings() {
        session.reloadCollections() // imported files and edits made in the folder show up
        if settings == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Ajustes"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0x1B / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1)
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: settingsView())
            host.sizingOptions = [.preferredContentSize]
            // Same as the panel: under the transparent titlebar, safe-area changes loop the layout.
            host.safeAreaRegions = []
            window.contentViewController = host
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    private func settingsView() -> SettingsView {
        SettingsView(session: session, hotKey: HotKey.saved.label,
                     onChangeHotKey: { [weak self] in self?.changeHotKey() },
                     onImport: { [weak self] in self?.importCollections() },
                     onOpenFolder: { [weak self] in self?.openFolder() })
    }

    /// Validates each file before copying it into the folder, so a broken file never lands there.
    @objc func importCollections() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.allowsMultipleSelection = true
        // The floating panel would cover the open panel; bring it back if nothing gets imported.
        let wasVisible = panel.isVisible
        // From the settings window, an import stays there instead of opening the panel.
        let fromSettings = settings?.isKeyWindow == true
        panel.orderOut(nil)
        // Accessory apps are not frontmost; without this the panel opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        guard showImportHelp(), open.runModal() == .OK else {
            if wasVisible { panel.makeKeyAndOrderFront(nil) }
            return
        }
        var imported: String?
        for url in open.urls {
            do {
                imported = try Collection.install(url, into: session.folder)
            } catch {
                let alert = NSAlert()
                alert.messageText = "No se pudo importar \(url.lastPathComponent)"
                alert.informativeText = error.localizedDescription + "\n\nFormato esperado:\n" + Self.formatExample
                alert.runModal()
            }
        }
        session.reloadCollections()
        guard let imported, let collection = session.collections.first(where: { $0.id == imported }) else {
            if wasVisible { panel.makeKeyAndOrderFront(nil) }
            return
        }
        session.choose(collection)
        fromSettings ? settings?.makeKeyAndOrderFront(nil) : show()
    }

    /// Explains the file format before the first import; false if the user cancels.
    func showImportHelp() -> Bool {
        guard !UserDefaults.standard.bool(forKey: "hideImportHelp") else { return true }
        let alert = NSAlert()
        alert.messageText = "Importar colección"
        alert.informativeText = "Elige un archivo .json con este formato:"
        alert.icon = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))
        alert.accessoryView = importHelpView()
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "No volver a mostrar este mensaje nunca más"
        let accepted = alert.runModal() == .alertFirstButtonReturn
        // Only an accepted dialog is remembered, so cancelling never hides the help by accident.
        if accepted, alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "hideImportHelp") }
        return accepted
    }

    /// The collection file format, shown in the import help and in import errors.
    static let formatExample = """
        {
          "name": "Programación",
          "quotes": [
            { "text": "Una frase.", "source": "Autor" },
            { "text": "Una frase sin fuente." }
          ]
        }
        """

    /// The format example as an indented code block, followed by the field rules.
    private func importHelpView() -> NSView {
        let code = NSTextField(labelWithString: Self.formatExample)
        code.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        code.isSelectable = true
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        box.layer?.cornerRadius = 8
        code.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(code)
        NSLayoutConstraint.activate([
            code.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            code.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
            code.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            code.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        let rules = NSTextField(wrappingLabelWithString: """
            • name y text son obligatorios.
            • source es opcional.
            • Se descartan las frases de más de \(Collection.maxChars) caracteres y las que tienen emojis o caracteres anchos (chino, japonés, coreano).
            """)
        rules.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        rules.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [box, rules])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.frame.size = NSSize(width: 300, height: stack.fittingSize.height)
        stack.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.layoutSubtreeIfNeeded()
        stack.frame.size = stack.fittingSize
        return stack
    }

    /// Registers `hotKey` and shows it in the menu; false if another app already owns it.
    @discardableResult
    func apply(_ hotKey: HotKey) -> Bool {
        let ok = registerHotKey(hotKey) { [weak self] in
            guard let self else { return }
            panel.isKeyWindow ? hide() : show()
        }
        practice.title = ok ? "Practicar  \(hotKey.label)" : "Practicar (\(hotKey.label) ocupado)"
        return ok
    }

    /// Records a new global shortcut: the next key pressed with ⌘, ⌥ or ⌃ while the dialog is open.
    @objc func changeHotKey() {
        let old = HotKey.saved
        var recorded: HotKey?
        let shown = NSTextField(labelWithString: old.label)
        shown.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        shown.alignment = .center
        shown.frame.size = NSSize(width: 260, height: 32)
        let alert = NSAlert()
        alert.messageText = "Cambiar atajo"
        alert.informativeText = "Pulsa la nueva combinación. Tiene que incluir ⌘, ⌥ o ⌃. No se permiten ⌘+letra (atajos de las apps) ni ⌥ con una tecla que escribe algo, como ⌥+letra o ⌥+signo (acentos y símbolos)."
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))
        alert.accessoryView = shown
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Restablecer \(HotKey.standard.label)")
        // Free the current shortcut so pressing it again records it instead of opening the panel.
        unregisterHotKey()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let hotKey = HotKey(event: event) else { return event }
            recorded = hotKey
            shown.stringValue = hotKey.label
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        monitor.map(NSEvent.removeMonitor)
        let chosen = answer == .alertFirstButtonReturn ? recorded ?? old : answer == .alertThirdButtonReturn ? .standard : old
        if apply(chosen) {
            HotKey.saved = chosen
        } else if chosen != old { // a busy old shortcut is already flagged in the menu
            let restored = apply(old)
            let busy = NSAlert()
            busy.messageText = "\(chosen.label) ya lo usa otra app"
            busy.informativeText = restored ? "Se mantiene \(old.label). Prueba otra combinación." : "Ningún atajo activo: \(old.label) también está ocupado."
            busy.runModal()
        }
        (settings?.contentViewController as? NSHostingController<SettingsView>)?.rootView = settingsView()
    }

    @objc func openFolder() {
        try? FileManager.default.createDirectory(at: session.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(session.folder)
    }

    @objc func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front != .current { previousApp = front }
        session.closePicker()
        session.newRound()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.center()
    }

    /// Official Aiber Logo 1B drawn as a monochrome template image for the macOS menu bar.
    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let w = rect.width, h = rect.height, s = min(w, h)
            let stroke = s * 0.135
            NSColor.black.set()
            let chevron = NSBezierPath()
            chevron.lineWidth = stroke
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.move(to: NSPoint(x: w * 0.18, y: h * 0.77))
            chevron.line(to: NSPoint(x: w * 0.48, y: h * 0.21))
            chevron.line(to: NSPoint(x: w * 0.65, y: h * 0.53))
            chevron.stroke()
            let barY = h * 0.77 + stroke * 0.5 - stroke
            let cursor = NSRect(x: w * 0.56, y: barY, width: w * 0.30, height: stroke)
            NSBezierPath(roundedRect: cursor, xRadius: stroke * 0.48, yRadius: stroke * 0.48).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AiberTyper"
        return image
    }

    func hide() {
        panel.orderOut(nil)
        previousApp?.activate()
    }
}

let app = NSApplication.shared
// Before AppDelegate creates the Session, which reads these settings.
// A benchmark run never writes the user's settings.
if !bench { migrateDefaults(from: UserDefaults(suiteName: "com.aitor.AitorTyper")) }
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
