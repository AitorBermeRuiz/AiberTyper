//go:build windows

package main

import (
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"

	"aibertyper/typer"
)

// panel is the floating window: a layered popup redrawn into a premultiplied bitmap on each change, with keyboard
// and mouse handling. The Windows counterpart of the NSPanel and the key monitor in main.swift.
type panel struct {
	app  *app
	hwnd uintptr

	// Frame: a DIB the size of the window, wrapped by a GDI+ canvas.
	dc, dib    uintptr
	bits       unsafe.Pointer
	w, h       int // pixels
	frame      *canvas
	background []byte // shadow and card, copied in before each frame
	bgKey      [3]int
	scale      float32
	// scaleOverride renders at a fixed scale (bench screenshots at 2x).
	scaleOverride float32
	x, y          int32 // window position, pixels

	hits           []hit
	hover, pressed string
	tracking       bool
	timer          bool
	highSurrogate  uint16
	dirty          bool
}

var now = time.Now

func (p *panel) create() {
	class := wstr("AiberTyperPanel")
	instance, _, _ := pGetModuleHandleW.Call(0)
	cursor, _, _ := pLoadCursorW.Call(0, idcArrow)
	wc := wndClassEx{WndProc: syscall.NewCallback(p.wndProc), Instance: instance, Cursor: cursor, ClassName: class}
	wc.Size = uint32(unsafe.Sizeof(wc))
	pRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
	p.hwnd, _, _ = pCreateWindowExW.Call(wsExLayered|wsExToolWindow|wsExTopmost, uintptr(unsafe.Pointer(class)),
		uintptr(unsafe.Pointer(wstr("Aiber Typer"))), wsPopup, 0, 0, 1, 1, 0, 0, instance, 0)
	screen, _, _ := pGetDC.Call(0)
	p.dc, _, _ = pCreateCompatibleDC.Call(screen)
	pReleaseDC.Call(0, screen)
}

func (p *panel) visible() bool {
	r, _, _ := pIsWindowVisible.Call(p.hwnd)
	return r != 0
}

func (p *panel) dpiScale() float32 {
	if p.scaleOverride > 0 {
		return p.scaleOverride
	}
	dpi, _, _ := pGetDpiForWindow.Call(p.hwnd)
	if dpi == 0 {
		dpi = 96
	}
	return float32(dpi) / 96
}

// invalidate asks for one redraw once the current message is handled, however many changes it made.
func (p *panel) invalidate() {
	if !p.dirty {
		p.dirty = true
		pPostMessageW.Call(p.hwnd, wmAppRender, 0, 0)
	}
}

// render lays out the current screen, resizes the window to the card and puts the new frame on screen.
func (p *panel) render() {
	p.dirty = false
	s := p.app.session
	p.scale = p.dpiScale()
	layout := &view{c: measurer, dry: true, app: p.app, s: s}
	cardH := layout.draw()
	w := int((cardWidth + 2*shadowMargin) * p.scale)
	h := int((cardH + 2*shadowMargin) * p.scale)
	if w != p.w || h != p.h {
		p.resize(w, h)
	}
	key := [3]int{w, h, int(p.scale * 100)}
	if p.bgKey != key || p.background == nil {
		p.frame.clear()
		drawBackground(p.frame, cardH)
		gdip("GdipFlush", p.frame.g, 1)
		p.background = append(p.background[:0], unsafe.Slice((*byte)(p.bits), w*h*4)...)
		p.bgKey = key
	} else {
		copy(unsafe.Slice((*byte)(p.bits), w*h*4), p.background)
	}
	v := &view{c: p.frame, app: p.app, s: s, ox: shadowMargin, oy: shadowMargin, hover: p.hover, pressed: p.pressed}
	v.draw()
	p.hits = v.hits
	gdip("GdipFlush", p.frame.g, 1)
	p.present()
	p.updateTimer()
}

func (p *panel) resize(w, h int) {
	if p.frame != nil {
		p.frame.close()
	}
	old := p.dib
	bi := bitmapInfoHeader{Width: int32(w), Height: -int32(h), Planes: 1, BitCount: 32}
	bi.Size = uint32(unsafe.Sizeof(bi))
	var bits unsafe.Pointer
	p.dib, _, _ = pCreateDIBSection.Call(p.dc, uintptr(unsafe.Pointer(&bi)), 0, uintptr(unsafe.Pointer(&bits)), 0, 0)
	pSelectObject.Call(p.dc, p.dib)
	if old != 0 {
		pDeleteObject.Call(old) // only once deselected: DeleteObject refuses a bitmap selected into a DC
	}
	p.bits, p.w, p.h = bits, w, h
	p.frame = newCanvas(newBitmap(w, h, pixelFormat32bppPARGB, bits), p.scale)
	p.background = nil
}

func (p *panel) present() {
	pos := point{p.x, p.y}
	sz := size{int32(p.w), int32(p.h)}
	src := point{}
	blend := blendFunction{AlphaFormat: 1, SourceConstantAlpha: 255} // AC_SRC_ALPHA
	pUpdateLayeredWindow.Call(p.hwnd, 0, uintptr(unsafe.Pointer(&pos)), uintptr(unsafe.Pointer(&sz)), p.dc,
		uintptr(unsafe.Pointer(&src)), 0, uintptr(unsafe.Pointer(&blend)), ulwAlpha)
}

// center places the window on the monitor under the mouse, a little above the middle like NSWindow.center().
func (p *panel) center() {
	var pt point
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	mon, _, _ := pMonitorFromPoint.Call(uintptr(*(*uint64)(unsafe.Pointer(&pt))), 2) // nearest
	mi := monitorInfo{}
	mi.Size = uint32(unsafe.Sizeof(mi))
	pGetMonitorInfoW.Call(mon, uintptr(unsafe.Pointer(&mi)))
	work := mi.Work
	p.x = work.Left + (work.Right-work.Left-int32(p.w))/2
	p.y = work.Top + (work.Bottom-work.Top-int32(p.h))*2/5
}

// updateTimer ticks twice a second only while the stats can change on screen: visible, round started, not finished.
func (p *panel) updateTimer() {
	s := p.app.session
	_, started := s.Round.Live(now())
	want := s.Visible && started && s.Result == nil && !s.Picking
	switch {
	case want && !p.timer:
		pSetTimer.Call(p.hwnd, 1, 500, 0)
	case !want && p.timer:
		pKillTimer.Call(p.hwnd, 1)
	}
	p.timer = want
}

func (p *panel) hitAt(lparam uintptr, screen bool) (hit, bool) {
	x, y := float32(loword(lparam)), float32(hiword(lparam))
	if screen {
		x, y = x-float32(p.x), y-float32(p.y)
	}
	x, y = x/p.scale, y/p.scale
	for i := len(p.hits) - 1; i >= 0; i-- {
		h := p.hits[i]
		if x >= h.x && x < h.x+h.w && y >= h.y && y < h.y+h.h {
			return h, true
		}
	}
	return hit{}, false
}

func (p *panel) setHover(id string) {
	if p.hover != id {
		p.hover = id
		p.invalidate()
	}
}

func (p *panel) wndProc(hwnd, m, wparam, lparam uintptr) uintptr {
	switch m {
	case wmAppRender:
		if p.visible() { // a hidden panel draws again when it is shown
			p.render()
		}
		return 0
	case wmTimer:
		p.render()
		return 0
	case wmNCHitTest:
		if _, ok := p.hitAt(lparam, true); ok {
			return htClient
		}
		// The card's background drags the panel, like isMovableByWindowBackground.
		return htCaption
	case wmSetCursor:
		cursor := uintptr(idcArrow)
		if loword(lparam) == htClient && p.hover != "" {
			cursor = idcHand
		}
		c, _, _ := pLoadCursorW.Call(0, cursor)
		pSetCursor.Call(c)
		return 1
	case wmMouseMove:
		if !p.tracking {
			tme := trackMouseEvent{Flags: tmeLeave, Track: hwnd}
			tme.Size = uint32(unsafe.Sizeof(tme))
			pTrackMouseEvent.Call(uintptr(unsafe.Pointer(&tme)))
			p.tracking = true
		}
		h, _ := p.hitAt(lparam, false)
		p.setHover(h.id)
		return 0
	case wmMouseLeave:
		p.tracking = false
		p.setHover("")
		return 0
	case wmLButtonDown:
		h, _ := p.hitAt(lparam, false)
		p.pressed = h.id
		return 0
	case wmLButtonUp:
		h, ok := p.hitAt(lparam, false)
		if ok && h.id == p.pressed && h.action != nil {
			// A click can replace the button under the mouse: clear the hover before acting.
			p.hover = ""
			h.action()
			p.invalidate()
		}
		p.pressed = ""
		return 0
	case wmKeyDown, wmSysKeyDown:
		if p.key(int(wparam)) {
			return 0
		}
	case wmChar:
		p.char(uint16(wparam))
		return 0
	case wmSysChar:
		return 0 // Alt+key types nothing, and must not beep
	case wmActivate:
		// Hides when another window becomes active, like hidesOnDeactivate.
		if wparam&0xFFFF == waInactive && p.visible() {
			p.app.hide(false)
		}
		return 0
	case wmClose:
		p.app.hide(true) // Alt+F4
		return 0
	case wmDpiChanged:
		p.render()
		return 0
	case wmMove:
		// Dragged by the card's background: later frames go where the user left the panel.
		p.x, p.y = loword(lparam), hiword(lparam)
		return 0
	}
	r, _, _ := pDefWindowProcW.Call(hwnd, m, wparam, lparam)
	return r
}

// key performs what typer.PanelKey maps vk to; false lets the key through to WM_CHAR.
func (p *panel) key(vk int) bool {
	s := p.app.session
	a := typer.PanelKey(vk, keyDown(typer.VKControl), keyDown(typer.VKShift), keyDown(typer.VKMenu), s.Picking)
	if a.Kind == typer.Pass {
		return false
	}
	p.perform(a)
	return true
}

// perform does a panel action and redraws; the bench drives its key steps through it too.
func (p *panel) perform(a typer.PanelAction) {
	s := p.app.session
	switch a.Kind {
	case typer.Ignore:
	case typer.Hide:
		p.app.hide(true)
	case typer.OpenPicker:
		s.OpenPicker()
	case typer.ToggleLanguage:
		s.ToggleLanguage()
	case typer.NewRoundKey:
		s.NewRound()
	case typer.ClosePicker:
		s.ClosePicker()
	case typer.Choose:
		s.ChoosePicked()
	case typer.Delete:
		s.DeleteInPicker()
	case typer.Favorite:
		s.ToggleFavoritePicked()
	case typer.ImportCollections:
		p.app.importCollections()
	case typer.Move:
		s.MovePicker(a.Step)
	}
	p.invalidate()
}

// char types one UTF-16 unit from WM_CHAR. Dead keys arrive already composed (´ then a gives á).
func (p *panel) char(u uint16) {
	if utf16.IsSurrogate(rune(u)) && u < 0xDC00 {
		p.highSurrogate = u
		return
	}
	r := rune(u)
	if p.highSurrogate != 0 {
		r = utf16.DecodeRune(rune(p.highSurrogate), r)
		p.highSurrogate = 0
	}
	s := p.app.session
	if s.Picking {
		s.TypeInPicker(string(r)) // Backspace is handled as a key
		p.invalidate()
		return
	}
	typed := s.Round.Typed()
	switch {
	case r == 0x08: // Backspace
		if len(typed) > 0 {
			s.Type(string(typed[:len(typed)-1]), now())
		}
	case r == 0x7F: // Ctrl+Backspace deletes the word before the cursor, as in a text field
		end := len(typed)
		for end > 0 && typed[end-1] == ' ' {
			end--
		}
		for end > 0 && typed[end-1] != ' ' {
			end--
		}
		s.Type(string(typed[:end]), now())
	case r < 0x20:
		return
	default:
		s.Type(string(typed)+string(r), now())
	}
	p.invalidate()
}
