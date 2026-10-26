package typer

import (
	"fmt"
	"strings"
)

// RegisterHotKey modifier flags.
const (
	ModAlt     = 0x1
	ModControl = 0x2
	ModShift   = 0x4
	ModWin     = 0x8
)

// HotKey is the system-wide shortcut that opens the panel (HotKey.swift): a virtual key, RegisterHotKey modifiers
// and the key cap shown in the label, e.g. "T".
type HotKey struct {
	VK   uint32 `json:"vk"`
	Mods uint32 `json:"mods"`
	Key  string `json:"key"`
}

var StandardHotKey = HotKey{VK: 'T', Mods: ModAlt | ModShift, Key: "T"}

// Labels of keys that type no character.
var keyNames = map[uint32]string{
	VKSpace: "Espacio", VKReturn: "Enter", VKTab: "Tab", VKBack: "Retroceso", VKDelete: "Supr", VKInsert: "Insert",
	VKLeft: "←", VKRight: "→", VKUp: "↑", VKDown: "↓", VKHome: "Inicio", VKEnd: "Fin", VKPrior: "RePág", VKNext: "AvPág",
}

// typesCharacter: letters, digits, the numeric keypad and the punctuation (OEM) keys type something.
func typesCharacter(vk uint32) bool {
	return vk >= '0' && vk <= '9' || vk >= 'A' && vk <= 'Z' || vk >= 0x60 && vk <= 0x6F || vk >= 0xBA && vk <= 0xC0 ||
		vk >= 0xDB && vk <= 0xDF || vk == 0xE2
}

// HotKeyAllowed needs Ctrl, Alt or Win: a plain or Shift-only key would steal normal typing in every app. It refuses
// Ctrl or Ctrl+Shift plus a letter or number (app shortcuts), Alt plus a key that types (menu access keys and Alt
// codes), and Ctrl+Alt plus a key that types: Ctrl+Alt is AltGr, which types @, € or # on a Spanish keyboard.
func HotKeyAllowed(mods, vk uint32) bool {
	if mods&(ModControl|ModAlt|ModWin) == 0 || isModifierKey(vk) {
		return false
	}
	letterOrDigit := vk >= '0' && vk <= '9' || vk >= 'A' && vk <= 'Z'
	plain := mods &^ ModShift
	switch {
	case plain == ModControl && letterOrDigit:
		return false
	case mods == ModAlt && typesCharacter(vk):
		return false
	case plain == ModControl|ModAlt && typesCharacter(vk):
		return false
	}
	return true
}

func isModifierKey(vk uint32) bool {
	return vk >= VKShift && vk <= VKMenu || vk == VKLWin || vk == VKRWin || vk >= 0xA0 && vk <= 0xA5
}

// NewHotKey records a key press; false when the combination is not allowed. char is what the key types on the
// current keyboard layout (0 if nothing), used for the label of punctuation keys.
func NewHotKey(vk, mods uint32, char rune) (HotKey, bool) {
	if !HotKeyAllowed(mods, vk) {
		return HotKey{}, false
	}
	key, ok := keyNames[vk]
	switch {
	case ok:
	case vk >= '0' && vk <= '9' || vk >= 'A' && vk <= 'Z':
		key = string(rune(vk))
	case vk >= VKF1 && vk <= VKF24:
		key = fmt.Sprintf("F%d", vk-VKF1+1)
	case char > ' ':
		key = strings.ToUpper(string(char))
	default:
		// shortcut: other keys show their virtual-key code; add names if users pick them.
		key = fmt.Sprintf("#%d", vk)
	}
	return HotKey{VK: vk, Mods: mods, Key: key}, true
}

// Label lists the modifiers in the order Windows uses: "Alt+Shift+T".
func (h HotKey) Label() string {
	var parts []string
	for _, m := range []struct {
		flag uint32
		name string
	}{{ModWin, "Win"}, {ModControl, "Ctrl"}, {ModAlt, "Alt"}, {ModShift, "Shift"}} {
		if h.Mods&m.flag != 0 {
			parts = append(parts, m.name)
		}
	}
	return strings.Join(append(parts, h.Key), "+")
}
