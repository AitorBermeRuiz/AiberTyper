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
    /// Also nil for ⌘ or ⌘⇧ plus a letter or number (app shortcuts) and ⌥ plus one (accents and symbols).
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
        if typed.count == 1, typed.allSatisfy({ $0.isLetter || $0.isNumber }), mods & ~shiftKey == cmdKey || mods == optionKey { return nil }
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
        get {
            let decoded = UserDefaults.standard.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) }
            return decoded.flatMap { Int($0.mods) & (cmdKey | optionKey | controlKey) != 0 ? $0 : nil } ?? .standard
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "hotKey") }
    }
}

private var hotKeyAction: () -> Void = {}
private var hotKeyRef: EventHotKeyRef?
private var handlerInstalled = false

/// Registers `hotKey` system-wide, replacing the previous one. Carbon hot keys need no Accessibility permission.
/// False when another app or a macOS shortcut (System Settings > Keyboard) already uses it.
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
    guard !isSystemHotKey(hotKey) else { return false }
    let id = EventHotKeyID(signature: OSType(0x4154_5950), id: 1) // "ATYP"
    return RegisterEventHotKey(hotKey.code, hotKey.mods, id, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKeyRef) == noErr
}

/// An enabled macOS symbolic hot key with the same key and modifiers. Their modifiers are Carbon flags,
/// sometimes with the fn bit set, so only ⌘⇧⌥⌃ are compared.
private func isSystemHotKey(_ hotKey: HotKey) -> Bool {
    var symbolic: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&symbolic) == noErr, let list = symbolic?.takeRetainedValue() as? [[String: Any]] else { return false }
    let mask = cmdKey | shiftKey | optionKey | controlKey
    return list.contains {
        ($0["kHISymbolicHotKeyEnabled"] as? Bool) == true && ($0["kHISymbolicHotKeyCode"] as? Int) == Int(hotKey.code)
            && (($0["kHISymbolicHotKeyModifiers"] as? Int) ?? 0) & mask == Int(hotKey.mods) & mask
    }
}

func unregisterHotKey() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
}
