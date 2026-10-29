import AppKit
import Carbon

/// What a key pressed in the panel does. AppDelegate performs it; the footer hints in TyperView list these keys.
enum PanelKey: Equatable {
    /// Typing view: the hidden field gets the key.
    case pass
    /// Swallowed: reaches neither the field nor the picker.
    case ignore
    case hide, openPicker, toggleLanguage, newRound
    /// ⌘, in both views, as in any Mac app.
    case settings
    // Picker: every key lands here, never in the hidden field.
    case closePicker, choose, delete, favorite, importCollections
    case move(Int)
    case filter(String)

    init(event: NSEvent, picking: Bool) {
        let code = Int(event.keyCode)
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            self = .settings
            return
        }
        guard picking else {
            switch code {
            case kVK_Escape: self = .hide
            case kVK_Tab where event.modifierFlags.contains(.shift): self = .openPicker
            case kVK_Tab: self = .toggleLanguage
            case kVK_Return, kVK_ANSI_KeypadEnter: self = .newRound
            // Moving the caret inside the hidden field would desync it from the cursor drawn on screen.
            case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete: self = .ignore
            default: self = .pass
            }
            return
        }
        // Plain letters, j and k included, always filter; only ⌃j/⌃k and the arrows move.
        let control = event.modifierFlags.contains(.control)
        let key = event.charactersIgnoringModifiers ?? ""
        switch code {
        case kVK_Escape, kVK_Tab: self = .closePicker
        case kVK_Return, kVK_ANSI_KeypadEnter: self = .choose
        case kVK_DownArrow: self = .move(1)
        case kVK_UpArrow: self = .move(-1)
        case kVK_Delete: self = .delete
        case _ where control && key == "j": self = .move(1)
        case _ where control && key == "k": self = .move(-1)
        case _ where control && key == "f": self = .favorite
        case _ where control && key == "i": self = .importCollections
        default:
            if !control, !event.modifierFlags.contains(.command), let chars = event.characters { self = .filter(chars) } else { self = .ignore }
        }
    }
}
