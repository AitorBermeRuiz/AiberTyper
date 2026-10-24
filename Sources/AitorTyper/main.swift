import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let session = Session()
    var panel: NSPanel!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var practice: NSMenuItem!

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
        let host = NSHostingController(rootView: TyperView(session: session, onImport: { [weak self] in self?.importCollections() }))
        host.sizingOptions = [.preferredContentSize]
        // Under the transparent titlebar, safe-area changes on every resize loop the layout and AppKit aborts.
        host.safeAreaRegions = []
        panel.contentViewController = host


        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "AitorTyper")
        let menu = NSMenu()
        practice = NSMenuItem(title: "Practicar", action: #selector(show), keyEquivalent: "")
        practice.target = self
        menu.addItem(practice)
        menu.addItem(withTitle: "Cambiar atajo…", action: #selector(changeHotKey), keyEquivalent: "").target = self
        apply(HotKey.saved)
        let packs = NSMenu()
        packs.delegate = self
        menu.addItem(withTitle: "Colección", action: nil, keyEquivalent: "").submenu = packs
        menu.addItem(withTitle: "Importar colección…", action: #selector(importCollections), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Abrir carpeta de colecciones", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if self.session.picking {
                self.pickerKey(event)
                return nil
            }
            switch Int(event.keyCode) {
            case kVK_Escape: self.hide()
            case kVK_Tab where event.modifierFlags.contains(.shift): self.session.openPicker()
            case kVK_Tab: self.session.toggleLanguage()
            case kVK_Return, kVK_ANSI_KeypadEnter: self.session.newRound()
            default: return event
            }
            return nil
        }
    }

    /// Covers every way the panel leaves the screen, including hidesOnDeactivate, which skips hide().
    func windowDidChangeOcclusionState(_ notification: Notification) {
        session.visible = panel.occlusionState.contains(.visible)
    }

    /// While the picker is open every key goes to it, never to the hidden text field.
    func pickerKey(_ event: NSEvent) {
        let control = event.modifierFlags.contains(.control)
        let key = event.charactersIgnoringModifiers ?? ""
        switch Int(event.keyCode) {
        case kVK_Escape, kVK_Tab: session.closePicker()
        case kVK_Return, kVK_ANSI_KeypadEnter: session.choosePicked()
        case kVK_DownArrow: session.movePicker(1)
        case kVK_UpArrow: session.movePicker(-1)
        case kVK_Delete: session.deleteInPicker()
        case _ where control && key == "j": session.movePicker(1)
        case _ where control && key == "k": session.movePicker(-1)
        case _ where control && key == "f": session.toggleFavoritePicked()
        case _ where control && key == "i": importCollections()
        default:
            if !control, !event.modifierFlags.contains(.command), let chars = event.characters, !chars.isEmpty,
               chars.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }) {
                session.typeInPicker(chars)
            }
        }
    }

    /// Rebuilt on every open so imported files and favorites show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        session.reloadCollections()
        menu.removeAllItems()
        for collection in session.sortedCollections {
            let title = (session.favorites.contains(collection.id) ? "★ " : "") + collection.name
            let item = NSMenuItem(title: title, action: #selector(choosePack(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = collection.id
            item.state = collection.id == session.collection.id ? .on : .off
            menu.addItem(item)
        }
    }

    @objc func choosePack(_ sender: NSMenuItem) {
        guard let collection = session.collections.first(where: { $0.id == sender.representedObject as? String }) else { return }
        session.choose(collection)
        show()
    }

    /// Validates each file before copying it into the folder, so a broken file never lands there.
    @objc func importCollections() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.allowsMultipleSelection = true
        // The floating panel would cover the open panel; bring it back if nothing gets imported.
        let wasVisible = panel.isVisible
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
                _ = try Collection.parse(Data(contentsOf: url), id: "file:" + url.lastPathComponent)
                try FileManager.default.createDirectory(at: session.folder, withIntermediateDirectories: true)
                let destination = session.folder.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: url, to: destination)
                imported = "file:" + url.lastPathComponent
            } catch {
                let alert = NSAlert()
                alert.messageText = "No se pudo importar \(url.lastPathComponent)"
                alert.informativeText = (error is DecodingError ? "JSON no válido" : error.localizedDescription) + """


                    Formato esperado:
                    {"name": "Programación", "quotes": [
                      {"text": "Una frase.", "source": "Autor"},
                      {"text": "Una frase sin fuente."}
                    ]}
                    """
                alert.runModal()
            }
        }
        session.reloadCollections()
        guard let imported, let collection = session.collections.first(where: { $0.id == imported }) else {
            if wasVisible { panel.makeKeyAndOrderFront(nil) }
            return
        }
        session.choose(collection)
        show()
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

    /// The format example as an indented code block, followed by the field rules.
    private func importHelpView() -> NSView {
        let code = NSTextField(labelWithString: """
            {
              "name": "Programación",
              "quotes": [
                { "text": "Una frase.", "source": "Autor" },
                { "text": "Una frase sin fuente." }
              ]
            }
            """)
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
            • Las frases de más de \(Collection.maxChars) caracteres se descartan.
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
        let ok = registerHotKey(hotKey) { [weak self] in self?.toggle() }
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
        alert.informativeText = "Pulsa la nueva combinación. Tiene que incluir ⌘, ⌥ o ⌃."
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
        } else {
            apply(old)
            let busy = NSAlert()
            busy.messageText = "\(chosen.label) ya lo usa otra app"
            busy.informativeText = "Se mantiene \(old.label). Prueba otra combinación."
            busy.runModal()
        }
    }

    @objc func openFolder() {
        try? FileManager.default.createDirectory(at: session.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(session.folder)
    }

    func toggle() {
        panel.isKeyWindow ? hide() : show()
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

    func hide() {
        panel.orderOut(nil)
        previousApp?.activate()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
