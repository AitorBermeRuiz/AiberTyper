import AppKit
import Carbon

/// The system-wide shortcut that opens the panel, as Carbon key code and modifiers.
struct HotKey: Codable, Equatable {
    var code: UInt32
    var mods: UInt32
    /// Key cap shown in the label, e.g. "T".
    var key: String

    static let standard = HotKey(code: UInt32(kVK_ANSI_T), mods: UInt32(optionKey | shiftKey), key: "T")

    /// Labels of keys that type no character.
    static let names = [kVK_Space: "Espacio", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
                        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]

    /// Needs ⌘, ⌥ or ⌃: a plain or ⇧-only key would steal normal typing in every app.
    /// Refuses ⌘ or ⌘⇧ plus a letter or number (app shortcuts) and ⌥ plus a letter, number or symbol
    /// (it types accents and symbols: ⌥+ is ] on a Spanish keyboard).
    static func allowed(mods: Int, key: String) -> Bool {
        guard mods & (cmdKey | optionKey | controlKey) != 0 else { return false }
        let single = key.count == 1 && key.allSatisfy { $0.isLetter || $0.isNumber }
        let symbol = isVisible(key) && !names.values.contains(key)
        return !(single && mods & ~shiftKey == cmdKey || symbol && mods == optionKey)
    }

    /// One character that shows on screen: not a control, function-key or space character.
    private static func isVisible(_ s: String) -> Bool {
        s.count == 1 && !s.unicodeScalars.contains { [.control, .privateUse, .spaceSeparator].contains($0.properties.generalCategory) }
    }

    /// nil when the shortcut is not `allowed`.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        let typed = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard Self.allowed(mods: mods, key: typed) else { return nil }
        // With ⌥ alone, also check what the key really types: a dead key has no characters here.
        if mods == optionKey, let chars = event.characters, chars.isEmpty || Self.isVisible(chars) { return nil }
        // shortcut: function keys and other unnamed keys show their key code, add names if users pick them.
        let key = Self.names[Int(event.keyCode)] ?? (typed.isEmpty || typed.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } ? "#\(event.keyCode)" : typed)
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
            return decoded.flatMap { allowed(mods: Int($0.mods), key: $0.key) ? $0 : nil } ?? .standard
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
