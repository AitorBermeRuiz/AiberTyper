//go:build windows

// AiberTyper for Windows: a tray app with a floating typing panel. The counterpart of Sources/AiberTyper/main.swift;
// the typing rules live in ../typer and are shared with the Mac app through the vectors in ../shared.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"

	"aibertyper/typer"
)

func init() { runtime.LockOSThread() } // every window and GDI+ call stays on the main thread

// app is the AppDelegate: tray icon and menu, global shortcut, show and hide, import and the shortcut dialog.
type app struct {
	session  *typer.Session
	settings *typer.Settings
	panel    *panel
	// owner is a hidden window that owns the tray icon, receives the shortcut and parents the dialogs.
	owner      uintptr
	hotKey     typer.HotKey
	hotKeyOK   bool
	previous   uintptr
	taskbarMsg uintptr
	trayIcon   uintptr
	bench      *bench
}

func supportDir() string {
	dir, err := os.UserConfigDir() // %APPDATA%
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "AiberTyper")
}

func main() {
	benchMode := len(os.Args) > 1 && os.Args[1] == "--bench"
	if r, _, _ := pSetProcessDpiAwarenessContext.Call(^uintptr(3)); r == 0 { // per-monitor v2; the manifest says so too
		user32.NewProc("SetProcessDPIAware").Call()
	}
	if !benchMode {
		// One instance: launching it again shows the panel of the running one.
		_, _, err := pCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(wstr("AiberTyper.SingleInstance"))))
		if err == syscall.Errno(errorAlreadyExists) {
			if w, _, _ := pFindWindowW.Call(uintptr(unsafe.Pointer(wstr("AiberTyperOwner"))), 0); w != 0 {
				pPostMessageW.Call(w, wmAppShow, 0, 0)
			}
			return
		}
	}
	typer.Normalize = normalizeNFC
	typer.MoveToTrash = moveToRecycleBin
	gdiplusStartup()
	stringFormat = newTypographic()
	measurer = newCanvas(newBitmap(1, 1, pixelFormat32bppPARGB, nil), 1)
	loadFonts()
	charsPerLine = max(10, int((584-2)/mono(textSize, false).advance))
	highContrast = isHighContrast()

	a := &app{}
	dir := supportDir()
	if benchMode {
		a.bench = newBench()
		dir = a.bench.dir
	}
	a.settings = typer.LoadSettings(filepath.Join(dir, "settings.json"))
	a.session = typer.NewSession(typer.NewHistory(filepath.Join(dir, "history.json")), filepath.Join(dir, "Colecciones"), a.settings)
	a.createOwner()
	a.panel = &panel{app: a}
	a.panel.create()
	a.addTrayIcon()
	a.apply(a.settings.SavedHotKey())
	if a.bench != nil {
		a.bench.start(a)
	} else {
		a.notify("Aiber Typer está en la bandeja", fmt.Sprintf("Pulsa %s para practicar.", a.hotKey.Label()))
	}

	var m msg
	for {
		r, _, _ := pGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		pTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		pDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
	a.removeTrayIcon()
}

func newTypographic() uintptr {
	var generic, f uintptr
	gdip("GdipStringFormatGetGenericTypographic", uintptr(unsafe.Pointer(&generic)))
	gdip("GdipCloneStringFormat", generic, uintptr(unsafe.Pointer(&f)))
	gdip("GdipSetStringFormatFlags", f, 0x800|0x1000|0x4000) // measure trailing spaces, no wrap, no clip
	return f
}

func isHighContrast() bool {
	hc := struct {
		Size, Flags uint32
		Scheme      uintptr
	}{}
	hc.Size = uint32(unsafe.Sizeof(hc))
	user32.NewProc("SystemParametersInfoW").Call(0x42, uintptr(hc.Size), uintptr(unsafe.Pointer(&hc)), 0) // SPI_GETHIGHCONTRAST
	return hc.Flags&1 != 0
}

func (a *app) createOwner() {
	class := wstr("AiberTyperOwner")
	instance, _, _ := pGetModuleHandleW.Call(0)
	wc := wndClassEx{WndProc: syscall.NewCallback(a.ownerProc), Instance: instance, ClassName: class}
	wc.Size = uint32(unsafe.Sizeof(wc))
	pRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
	a.owner, _, _ = pCreateWindowExW.Call(wsExToolWindow, uintptr(unsafe.Pointer(class)), uintptr(unsafe.Pointer(wstr("Aiber Typer"))), wsPopup,
		0, 0, 0, 0, 0, 0, instance, 0)
	a.taskbarMsg, _, _ = pRegisterWindowMessageW.Call(uintptr(unsafe.Pointer(wstr("TaskbarCreated"))))
}

func (a *app) ownerProc(hwnd, m, wparam, lparam uintptr) uintptr {
	switch {
	case m == wmHotKey:
		if fg, _, _ := pGetForegroundWindow.Call(); fg == a.panel.hwnd && a.panel.visible() {
			a.hide(true)
		} else {
			a.show()
		}
		return 0
	case m == wmAppTray:
		if e := lparam & 0xFFFF; e == wmLButtonUp || e == wmRButtonUp {
			a.showMenu()
		}
		return 0
	case m == wmAppShow:
		a.show()
		return 0
	case m == wmAppRun && a.bench != nil:
		a.bench.run()
		return 0
	case m == a.taskbarMsg && m != 0:
		a.addTrayIcon() // Explorer restarted
		return 0
	}
	r, _, _ := pDefWindowProcW.Call(hwnd, m, wparam, lparam)
	return r
}

// do runs a session change from a click and redraws.
func (a *app) do(change func()) {
	change()
	a.panel.invalidate()
}

func (a *app) show() {
	if fg, _, _ := pGetForegroundWindow.Call(); fg != a.panel.hwnd && fg != a.owner {
		a.previous = fg
	}
	a.session.ClosePicker()
	a.session.NewRound()
	a.present(true)
}

// present puts the panel on screen and gives it the keyboard; center moves it to the middle of the screen.
func (a *app) present(center bool) {
	p := a.panel
	a.session.Visible = true
	p.render()
	if center {
		p.center()
		p.present()
	}
	pShowWindow.Call(p.hwnd, swShow)
	focus(p.hwnd)
	if p.dpiScale() != p.scale { // centered on a monitor with another scale
		p.render()
	}
}

// focus brings hwnd to the front. The shortcut and the tray menu let this process take the foreground; when Windows
// still refuses, joining the foreground thread's input does it.
func focus(hwnd uintptr) {
	if r, _, _ := pSetForegroundWindow.Call(hwnd); r != 0 {
		return
	}
	fg, _, _ := pGetForegroundWindow.Call()
	other, _, _ := pGetWindowThreadProcessId.Call(fg, 0)
	self, _, _ := pGetCurrentThreadId.Call()
	pAttachThreadInput.Call(self, other, 1)
	pBringWindowToTop.Call(hwnd)
	pSetForegroundWindow.Call(hwnd)
	pSetFocus.Call(hwnd)
	pAttachThreadInput.Call(self, other, 0)
}

// hide takes the panel off screen; restore gives the keyboard back to the window that had it (Esc, Cerrar).
func (a *app) hide(restore bool) {
	a.session.Visible = false
	pShowWindow.Call(a.panel.hwnd, swHide)
	a.panel.hover = ""
	a.panel.updateTimer()
	if ok, _, _ := pIsWindow.Call(a.previous); restore && ok != 0 {
		pSetForegroundWindow.Call(a.previous)
	}
}

// apply registers hotKey; false if another app already owns it. The menu shows it either way.
func (a *app) apply(h typer.HotKey) bool {
	pUnregisterHotKey.Call(a.owner, 1)
	r, _, _ := pRegisterHotKey.Call(a.owner, 1, uintptr(h.Mods|modNoRepeat), uintptr(h.VK))
	a.hotKey, a.hotKeyOK = h, r != 0
	return a.hotKeyOK
}

const (
	cmdPractice = iota + 1
	cmdHotKey
	cmdImport
	cmdFolder
	cmdQuit
	cmdCollection = 100
)

// showMenu opens the tray menu; the collection list is rebuilt each time so imports and favorites show up.
func (a *app) showMenu() {
	s := a.session
	s.ReloadCollections()
	menu, _, _ := pCreatePopupMenu.Call()
	packs, _, _ := pCreatePopupMenu.Call()
	add := func(m uintptr, flags, id uintptr, title string) {
		pAppendMenuW.Call(m, flags, id, uintptr(unsafe.Pointer(wstr(title))))
	}
	practice := "Practicar\t" + a.hotKey.Label()
	if !a.hotKeyOK {
		practice = "Practicar (" + a.hotKey.Label() + " ocupado)"
	}
	add(menu, mfString, cmdPractice, practice)
	add(menu, mfString, cmdHotKey, "Cambiar atajo…")
	sorted := s.SortedCollections()
	for i, c := range sorted {
		title := c.Name
		if s.Favorites[c.ID] {
			title = "★ " + title
		}
		flags := uintptr(mfString)
		if c.ID == s.Collection.ID {
			flags |= mfChecked
		}
		add(packs, flags, uintptr(cmdCollection+i), title)
	}
	add(menu, mfPopup, packs, "Colección")
	add(menu, mfString, cmdImport, "Importar colección…")
	add(menu, mfString, cmdFolder, "Abrir carpeta de colecciones")
	pAppendMenuW.Call(menu, mfSeparator, 0, 0)
	add(menu, mfString, cmdQuit, "Salir")

	var pt point
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	// The owner must be foreground for the menu to close when clicking elsewhere.
	pSetForegroundWindow.Call(a.owner)
	cmd, _, _ := pTrackPopupMenu.Call(menu, tpmReturnCmd|tpmRightButton, uintptr(pt.X), uintptr(pt.Y), 0, a.owner, 0)
	pPostMessageW.Call(a.owner, wmNull, 0, 0)
	pDestroyMenu.Call(menu) // destroys the submenu too

	switch {
	case cmd == cmdPractice:
		a.show()
	case cmd == cmdHotKey:
		a.changeHotKey()
	case cmd == cmdImport:
		a.importCollections()
	case cmd == cmdFolder:
		os.MkdirAll(s.Folder, 0o755)
		pShellExecuteW.Call(0, uintptr(unsafe.Pointer(wstr("open"))), uintptr(unsafe.Pointer(wstr(s.Folder))), 0, 0, swShowNormal)
	case cmd == cmdQuit:
		pPostQuitMessage.Call(0)
	case cmd >= cmdCollection && int(cmd-cmdCollection) < len(sorted):
		s.Choose(sorted[cmd-cmdCollection])
		a.show()
	}
}

const (
	nimAdd     = 0
	nimModify  = 1
	nimDelete  = 2
	nifMessage = 0x1
	nifIcon    = 0x2
	nifTip     = 0x4
	nifInfo    = 0x10
)

func (a *app) trayData() notifyIconData {
	d := notifyIconData{Wnd: a.owner, ID: 1}
	d.Size = uint32(unsafe.Sizeof(d))
	return d
}

func (a *app) addTrayIcon() {
	if a.trayIcon == 0 {
		a.trayIcon = trayIcon()
	}
	d := a.trayData()
	d.Flags = nifMessage | nifIcon | nifTip
	d.CallbackMessage = wmAppTray
	d.Icon = a.trayIcon
	copy(d.Tip[:], syscall.StringToUTF16("Aiber Typer"))
	pShellNotifyIconW.Call(nimAdd, uintptr(unsafe.Pointer(&d)))
}

func (a *app) removeTrayIcon() {
	d := a.trayData()
	pShellNotifyIconW.Call(nimDelete, uintptr(unsafe.Pointer(&d)))
}

// notify shows a tray notification: on Windows the tray icon is often hidden in the overflow area.
func (a *app) notify(title, text string) {
	d := a.trayData()
	d.Flags = nifInfo
	copy(d.InfoTitle[:63], syscall.StringToUTF16(title))
	copy(d.Info[:255], syscall.StringToUTF16(text))
	pShellNotifyIconW.Call(nimModify, uintptr(unsafe.Pointer(&d)))
}

// trayIcon draws the Aiber logo at the tray's icon size.
func trayIcon() uintptr {
	dpi, _, _ := pGetDpiForSystem.Call()
	px, _, _ := pGetSystemMetricsForDpi.Call(smCxSmIcon, dpi)
	if px == 0 {
		px = 16
	}
	bmp := newBitmap(int(px), int(px), pixelFormat32bppARGB, nil)
	c := newCanvas(bmp, float32(px)/16)
	c.clear()
	logo(c, 0, 0, 16, rgb(gPink, 1), rgb(gNeon, 1))
	var icon uintptr
	gdip("GdipCreateHICONFromBitmap", bmp, uintptr(unsafe.Pointer(&icon)))
	c.close()
	return icon
}

// moveToRecycleBin replaces typer's delete when an import overwrites a collection with the same name.
func moveToRecycleBin(path string) error {
	op := shFileOp{Func: 3, From: wstrs(path), Flags: 0x40 | 0x10 | 0x4 | 0x400} // delete; allow undo, no confirmation, silent, no error UI
	if r, _, _ := pSHFileOperationW.Call(uintptr(unsafe.Pointer(&op))); r != 0 || op.Aborted != 0 {
		return fmt.Errorf("no se pudo mover %s a la papelera", filepath.Base(path))
	}
	return nil
}
