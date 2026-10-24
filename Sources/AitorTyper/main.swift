import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingController(rootView: TyperView(session: session))
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape: self.hide()
            case kVK_Tab: self.session.toggleLanguage()
            case kVK_Return, kVK_ANSI_KeypadEnter: self.session.newRound()
            default: return event
            }
            return nil
        }
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

    func toggle() {
        panel.isKeyWindow ? hide() : show()
    }

    @objc func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front != .current { previousApp = front }
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
