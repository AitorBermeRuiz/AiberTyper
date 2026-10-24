import AppKit
import Carbon

/// The system-wide shortcut that opens the panel, as Carbon key code and modifiers.
struct HotKey: Codable, Equatable {
    var code: UInt32
    var mods: UInt32
    /// Key cap shown in the label, e.g. "T".
    var key: String

    static let standard = HotKey(code: UInt32(kVK_ANSI_T), mods: UInt32(optionKey | shiftKey), key: "T")

    /// nil unless ⌘, ⌥ or ⌃ is held: a plain or ⇧-only key would steal normal typing in every app.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        let names = [kVK_Space: "Espacio", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
                     kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        let typed = (event.charactersIgnoringModifiers ?? "").uppercased()
        // shortcut: function keys and other unnamed keys show their key code, add names if users pick them.
        let key = names[Int(event.keyCode)] ?? (typed.isEmpty || typed.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } ? "#\(event.keyCode)" : typed)
        self.init(code: UInt32(event.keyCode), mods: UInt32(mods), key: key)
    }

    init(code: UInt32, mods: UInt32, key: String) {
        self.code = code
        self.mods = mods
        self.key = key
    }

    var label: String {
        let m = Int(mods)
        return (m & controlKey != 0 ? "⌃" : "") + (m & optionKey != 0 ? "⌥" : "") + (m & shiftKey != 0 ? "⇧" : "")
            + (m & cmdKey != 0 ? "⌘" : "") + key
    }

    static var saved: HotKey {
        get { UserDefaults.standard.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) } ?? .standard }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "hotKey") }
    }
}

private var hotKeyAction: () -> Void = {}
private var hotKeyRef: EventHotKeyRef?
private var handlerInstalled = false

/// Registers `hotKey` system-wide, replacing the previous one. Carbon hot keys need no Accessibility permission.
func registerHotKey(_ hotKey: HotKey, action: @escaping () -> Void) -> Bool {
    hotKeyAction = action
    if !handlerInstalled {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            hotKeyAction()
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
    unregisterHotKey()
    let id = EventHotKeyID(signature: OSType(0x4154_5950), id: 1) // "ATYP"
    return RegisterEventHotKey(hotKey.code, hotKey.mods, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
}

func unregisterHotKey() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
}
