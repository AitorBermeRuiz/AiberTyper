import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = Session()
    var panel: NSPanel!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?

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

        let hotKeyOK = registerHotKey { [weak self] in self?.toggle() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "AitorTyper")
        let menu = NSMenu()
        let practice = NSMenuItem(title: hotKeyOK ? "Practicar  ⌥⇧T" : "Practicar (⌥⇧T ocupado)", action: #selector(show), keyEquivalent: "")
        practice.target = self
        menu.addItem(practice)
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

private var hotKeyAction: () -> Void = {}

/// Registers ⌥⇧T system-wide. Carbon hot keys need no Accessibility permission.
func registerHotKey(_ action: @escaping () -> Void) -> Bool {
    hotKeyAction = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        hotKeyAction()
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x4154_5950), id: 1) // "ATYP"
    return RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref) == noErr
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
