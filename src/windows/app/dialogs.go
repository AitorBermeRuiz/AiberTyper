//go:build windows

package main

import (
	"encoding/binary"
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"aibertyper/typer"
)

// System dialogs, as the Mac app uses NSAlert and NSOpenPanel: the import help and errors, the file picker and the
// shortcut recorder. Task dialogs need Common Controls 6, which the manifest (cmd/rsrc) asks for.

type tdButton struct {
	id   int32
	text string
}

type taskDialog struct {
	instruction, content, verification string
	buttons                            []tdButton
	icon                               uintptr // a TD_*_ICON value
	callback                           uintptr
}

const (
	idOK           = 1
	idCancel       = 2
	tdInfoIcon     = 0xFFFD // TD_INFORMATION_ICON
	tdWarningIcon  = 0xFFFF // TD_WARNING_ICON
	tdmSetElement  = wmUser + 108
	tdeInstruction = 3
	tdnCreated     = 0
	tdnDestroyed   = 5
)

// show runs the dialog; returns the button pressed and the verification checkbox. TASKDIALOGCONFIG is packed to
// one byte (pshpack1.h), so it is written byte by byte. Falls back to a message box without Common Controls 6.
func (d taskDialog) show(owner uintptr) (int, bool) {
	if pTaskDialogIndirect.Find() != nil {
		r := messageBox(owner, d.instruction+"\n\n"+d.content, "Aiber Typer", 0x1) // OK/Cancel
		return r, false
	}
	var keep []any
	ptr := func(s string) uint64 {
		if s == "" {
			return 0
		}
		p := wstr(s)
		keep = append(keep, p)
		return uint64(uintptr(unsafe.Pointer(p)))
	}
	buttons := make([]byte, 12*len(d.buttons))
	for i, b := range d.buttons {
		binary.LittleEndian.PutUint32(buttons[12*i:], uint32(b.id))
		binary.LittleEndian.PutUint64(buttons[12*i+4:], ptr(b.text))
	}
	cfg := make([]byte, 160)
	put32 := func(off int, v uint32) { binary.LittleEndian.PutUint32(cfg[off:], v) }
	put64 := func(off int, v uint64) { binary.LittleEndian.PutUint64(cfg[off:], v) }
	instance, _, _ := pGetModuleHandleW.Call(0)
	put32(0, 160)
	put64(4, uint64(owner))
	put64(12, uint64(instance))
	put32(20, 0x8|0x1000000) // allow Esc to cancel, size to content
	put64(28, ptr("Aiber Typer"))
	put64(36, uint64(d.icon))
	put64(44, ptr(d.instruction))
	put64(52, ptr(d.content))
	put32(60, uint32(len(d.buttons)))
	if len(d.buttons) > 0 {
		put64(64, uint64(uintptr(unsafe.Pointer(&buttons[0]))))
		put32(72, uint32(d.buttons[0].id))
	}
	put64(92, ptr(d.verification))
	put64(140, uint64(d.callback))
	var button, radio, verified int32
	pTaskDialogIndirect.Call(uintptr(unsafe.Pointer(&cfg[0])), uintptr(unsafe.Pointer(&button)), uintptr(unsafe.Pointer(&radio)),
		uintptr(unsafe.Pointer(&verified)))
	runtime.KeepAlive(keep)
	runtime.KeepAlive(buttons)
	return int(button), verified != 0
}

func alert(owner uintptr, instruction, content string) {
	taskDialog{instruction: instruction, content: content, icon: tdWarningIcon, buttons: []tdButton{{idOK, "Aceptar"}}}.show(owner)
}

// formatExample is the collection file format, shown in the import help and in import errors.
const formatExample = `{
  "name": "Programación",
  "quotes": [
    { "text": "Una frase.", "source": "Autor" },
    { "text": "Una frase sin fuente." }
  ]
}`

// showImportHelp explains the file format before the first import; false if the user cancels.
func (a *app) showImportHelp() bool {
	if a.settings.HideImportHelp {
		return true
	}
	button, verified := taskDialog{
		instruction: "Importar colección",
		content: "Elige un archivo .json con este formato:\n\n" + formatExample + "\n\n" +
			"• name y text son obligatorios.\n• source es opcional.\n" +
			fmt.Sprintf("• Se descartan las frases de más de %d caracteres y las que tienen emojis o caracteres anchos (chino, japonés, coreano).", typer.MaxChars),
		verification: "No volver a mostrar este mensaje nunca más",
		icon:         tdInfoIcon,
		buttons:      []tdButton{{idOK, "Aceptar"}, {idCancel, "Cancelar"}},
	}.show(a.owner)
	// Only an accepted dialog is remembered, so cancelling never hides the help by accident.
	if button == idOK && verified {
		a.settings.HideImportHelp = true
		a.settings.Save()
	}
	return button == idOK
}

// openFiles asks for JSON files; nil when cancelled.
func (a *app) openFiles() []string {
	buf := make([]uint16, 64*1024)
	ofn := openFileName{
		Owner:   a.owner,
		Filter:  wstrs("Colecciones (*.json)", "*.json"),
		File:    &buf[0],
		MaxFile: uint32(len(buf)),
		Title:   wstr("Importar colección"),
		Flags:   0x200 | 0x80000 | 0x1000 | 0x800 | 0x8, // multiple, explorer, file and path must exist, keep the current folder
	}
	ofn.StructSize = uint32(unsafe.Sizeof(ofn))
	if r, _, _ := pGetOpenFileNameW.Call(uintptr(unsafe.Pointer(&ofn))); r == 0 {
		return nil
	}
	// One file: its full path. Several: the folder, then each name; all null-separated.
	var parts []string
	for start, i := 0, 0; i < len(buf); i++ {
		if buf[i] == 0 {
			if i == start {
				break
			}
			parts = append(parts, syscall.UTF16ToString(buf[start:i]))
			start = i + 1
		}
	}
	if len(parts) <= 1 {
		return parts
	}
	files := make([]string, 0, len(parts)-1)
	for _, name := range parts[1:] {
		files = append(files, parts[0]+`\`+name)
	}
	return files
}

// importCollections validates each file before copying it into the folder, so a broken file never lands there.
func (a *app) importCollections() {
	a.inDialog = true
	defer func() { a.inDialog = false }()
	s := a.session
	// The topmost panel would cover the dialogs; bring it back if nothing gets imported.
	wasVisible := a.panel.visible()
	a.hide(false)
	pSetForegroundWindow.Call(a.owner)
	var files []string
	if a.showImportHelp() {
		files = a.openFiles()
	}
	imported := ""
	for _, f := range files {
		// The file filter is only a hint, and the folder loads *.json files only.
		if !strings.EqualFold(filepath.Ext(f), ".json") {
			alert(a.owner, "No se pudo importar "+baseName(f), "El archivo debe terminar en .json.")
			continue
		}
		id, err := typer.Install(f, s.Folder)
		if err != nil {
			alert(a.owner, "No se pudo importar "+baseName(f), err.Error()+"\n\nFormato esperado:\n"+formatExample)
			continue
		}
		imported = id
	}
	s.ReloadCollections()
	for _, c := range s.Collections {
		if imported != "" && c.ID == imported {
			s.Choose(c)
			a.show()
			return
		}
	}
	if wasVisible {
		a.present(false)
	}
}

func baseName(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == '\\' || path[i] == '/' {
			return path[i+1:]
		}
	}
	return path
}

// recorder is the state of the open shortcut dialog, reached from the keyboard hook and the dialog callback.
var recorder struct {
	dialog   uintptr
	recorded *typer.HotKey
}

// Callbacks are made once: Go never frees them and allows about 2000 per process.
var (
	recordKeyCallback  = syscall.NewCallback(recordKey)
	recorderDialogProc = syscall.NewCallback(func(hwnd, n, w, l, data uintptr) uintptr {
		switch n {
		case tdnCreated:
			recorder.dialog = hwnd
		case tdnDestroyed:
			recorder.dialog = 0
		}
		return 0
	})
)

// changeHotKey records a new global shortcut: the next key pressed with Ctrl, Alt or Win while the dialog is open.
func (a *app) changeHotKey() {
	a.inDialog = true
	defer func() { a.inDialog = false }()
	old := a.settings.SavedHotKey()
	recorder.recorded = nil
	// Free the current shortcut so pressing it again records it instead of opening the panel.
	pUnregisterHotKey.Call(a.owner, 1)
	hook, _, _ := pSetWindowsHookExW.Call(whKeyboardLL, recordKeyCallback, 0, 0)
	pSetForegroundWindow.Call(a.owner)
	button, _ := taskDialog{
		instruction: old.Label(),
		content: "Pulsa la nueva combinación. Tiene que incluir Ctrl, Alt o Win. No se permiten Ctrl+letra o Ctrl+número " +
			"(atajos de las apps), Alt con una tecla que escribe algo (menús) ni Ctrl+Alt con una tecla que escribe algo " +
			"(es AltGr: @, €, #).",
		buttons:  []tdButton{{idOK, "Guardar"}, {idCancel, "Cancelar"}, {100, "Restablecer " + typer.StandardHotKey.Label()}},
		callback: recorderDialogProc,
	}.show(a.owner)
	pUnhookWindowsHookEx.Call(hook)
	chosen := old
	switch {
	case button == idOK && recorder.recorded != nil:
		chosen = *recorder.recorded
	case button == 100:
		chosen = typer.StandardHotKey
	}
	if a.apply(chosen) {
		a.settings.HotKey = &chosen
		a.settings.Save()
	} else if chosen != old { // a busy old shortcut is already flagged in the menu
		restored := a.apply(old)
		content := "Ningún atajo activo: " + old.Label() + " también está ocupado."
		if restored {
			content = "Se mantiene " + old.Label() + ". Prueba otra combinación."
		}
		alert(a.owner, chosen.Label()+" ya lo usa otra app", content)
	}
}

// recordKey is a low-level keyboard hook: while the shortcut dialog is in front, an allowed combination is
// recorded and shown instead of reaching the dialog.
func recordKey(code, wparam, lparam uintptr) uintptr {
	fg, _, _ := pGetForegroundWindow.Call()
	if int32(code) == 0 && (wparam == wmKeyDown || wparam == wmSysKeyDown) && recorder.dialog != 0 && fg == recorder.dialog {
		k := (*kbdLLHook)(unsafe.Pointer(lparam))
		mods := uint32(0)
		for _, m := range []struct {
			vk   []int
			flag uint32
		}{{[]int{typer.VKControl}, typer.ModControl}, {[]int{typer.VKMenu}, typer.ModAlt}, {[]int{typer.VKShift}, typer.ModShift},
			{[]int{typer.VKLWin, typer.VKRWin}, typer.ModWin}} {
			for _, vk := range m.vk {
				if asyncKeyDown(vk) {
					mods |= m.flag
				}
			}
		}
		char, _, _ := pMapVirtualKeyW.Call(uintptr(k.VK), 2) // MAPVK_VK_TO_CHAR; dead keys set the top bit
		if h, ok := typer.NewHotKey(k.VK, mods, rune(char&0x7FFFFFFF)); ok && k.VK != vkDummy {
			recorder.recorded = &h
			pSendMessageW.Call(recorder.dialog, tdmSetElement, tdeInstruction, uintptr(unsafe.Pointer(wstr(h.Label()))))
			if mods&typer.ModWin != 0 {
				// The shell saw Win go down and up alone and would open Start: show it another key in between.
				pKeybdEvent.Call(vkDummy, 0, 0, 0)
				pKeybdEvent.Call(vkDummy, 0, keyeventfKeyUp, 0)
			}
			return 1
		}
	}
	r, _, _ := pCallNextHookEx.Call(0, code, wparam, lparam)
	return r
}
