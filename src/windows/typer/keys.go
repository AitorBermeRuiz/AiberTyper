package typer

// Windows virtual-key codes used by the panel and the shortcut rules.
const (
	VKBack    = 0x08
	VKTab     = 0x09
	VKReturn  = 0x0D
	VKShift   = 0x10
	VKControl = 0x11
	VKMenu    = 0x12 // Alt
	VKEscape  = 0x1B
	VKSpace   = 0x20
	VKPrior   = 0x21 // Page Up
	VKNext    = 0x22 // Page Down
	VKEnd     = 0x23
	VKHome    = 0x24
	VKLeft    = 0x25
	VKUp      = 0x26
	VKRight   = 0x27
	VKDown    = 0x28
	VKInsert  = 0x2D
	VKDelete  = 0x2E
	VKLWin    = 0x5B
	VKRWin    = 0x5C
	VKF1      = 0x70
	VKF24     = 0x87
)

// PanelAction is what a key pressed in the panel does (PanelKey in Keys.swift). The app performs it; the footer
// hints in the view list these keys. Characters arrive separately (WM_CHAR) and type into the round or the filter.
type PanelAction struct {
	Kind PanelKind
	Step int // for Move
}

type PanelKind int

const (
	// Pass lets the key through: its character, if any, types.
	Pass PanelKind = iota
	// Ignore swallows the key.
	Ignore
	Hide
	OpenPicker
	ToggleLanguage
	NewRoundKey
	// Picker: every key lands here, never in the round.
	ClosePicker
	Choose
	Delete
	Favorite
	ImportCollections
	Move
)

// PanelKey maps a key press (virtual key and modifiers) in the typing view or the picker.
func PanelKey(vk int, ctrl, shift, alt, picking bool) PanelAction {
	if !picking {
		switch vk {
		case VKEscape:
			return PanelAction{Kind: Hide}
		case VKTab:
			if shift {
				return PanelAction{Kind: OpenPicker}
			}
			return PanelAction{Kind: ToggleLanguage}
		case VKReturn:
			return PanelAction{Kind: NewRoundKey}
		// The typed text has no caret to move: the one on screen is always at the end.
		case VKLeft, VKRight, VKUp, VKDown, VKHome, VKEnd, VKPrior, VKNext, VKDelete:
			return PanelAction{Kind: Ignore}
		}
		return PanelAction{Kind: Pass}
	}
	// Plain letters, j and k included, always filter; only Ctrl+J/K and the arrows move. Ctrl+Alt is AltGr, which types.
	control := ctrl && !alt
	switch {
	case vk == VKEscape || vk == VKTab:
		return PanelAction{Kind: ClosePicker}
	case vk == VKReturn:
		return PanelAction{Kind: Choose}
	case vk == VKDown, control && vk == 'J':
		return PanelAction{Kind: Move, Step: 1}
	case vk == VKUp, control && vk == 'K':
		return PanelAction{Kind: Move, Step: -1}
	case vk == VKBack:
		return PanelAction{Kind: Delete}
	case control && vk == 'F':
		return PanelAction{Kind: Favorite}
	case control && vk == 'I':
		return PanelAction{Kind: ImportCollections}
	}
	return PanelAction{Kind: Pass}
}
