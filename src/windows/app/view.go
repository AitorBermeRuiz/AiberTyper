//go:build windows

package main

import (
	"fmt"
	"math"
	"strings"
	"unsafe"

	"aibertyper/typer"
)

// The panel's three screens, drawn by hand: the Windows counterpart of TyperView.swift. Sizes are in DIPs and
// follow the SwiftUI layout (640 wide card, 28 padding, the same spacings and font sizes).

// Aiber Bermejo palette (design/brand/README.md), opaque.
const (
	gBg     = opaque | 0x1B1113
	gFg     = opaque | 0xF6EEF0
	gPink   = opaque | 0xF497A9
	gNeon   = opaque | 0xE83A59
	gYellow = opaque | 0xF5D547
)

const (
	cardWidth  = 640
	cardRadius = 14
	textSize   = 23
	// shadowMargin is the transparent border around the card that holds its shadow.
	shadowMargin = 28
)

// highContrast follows Windows' contrast themes, as the Mac app follows "Increase contrast".
var highContrast bool

func muted() color {
	if highContrast {
		return opaque | 0xD9CCD0
	}
	return opaque | 0xAA989C
}

func border() color {
	if highContrast {
		return opaque | 0x7C5E66
	}
	return opaque | 0x3C262B
}

// fonts: IosevkaTerm when installed (like the Mac app), else Cascadia Mono or Consolas; Segoe UI for the rest.
type fonts struct {
	mono, ui, uiSemibold, uiBlack, symbol uintptr
	cache                                 map[string]*font
}

var ff fonts

func loadFonts() {
	ff.mono, _ = fontFamily("IosevkaTerm Nerd Font", "IosevkaTerm NF", "Iosevka Term", "Cascadia Mono", "Consolas")
	ff.ui, _ = fontFamily("Segoe UI", "Tahoma")
	ff.uiSemibold, _ = fontFamily("Segoe UI Semibold", "Segoe UI")
	ff.uiBlack, _ = fontFamily("Segoe UI Black", "Segoe UI")
	ff.symbol, _ = fontFamily("Segoe UI Symbol", "Segoe UI")
	ff.cache = map[string]*font{}
}

func cached(key string, make func() *font) *font {
	if f, ok := ff.cache[key]; ok {
		return f
	}
	f := make()
	ff.cache[key] = f
	return f
}

func mono(size float32, bold bool) *font {
	style := fontRegular
	if bold {
		style = fontBold
	}
	return cached(fmt.Sprint("mono", size, bold), func() *font {
		f := newFont(ff.mono, size, style)
		f.advance = measurer.measure(strings.Repeat("M", 50), f) / 50
		return f
	})
}

// measurer measures text outside a frame (layout and charsPerLine).
var measurer *canvas

type weight int

const (
	regular weight = iota
	medium
	semibold
	bold
	heavy
)

func ui(size float32, w weight) *font {
	return cached(fmt.Sprint("ui", size, w), func() *font {
		switch w {
		case medium, semibold:
			return newFont(ff.uiSemibold, size, fontRegular)
		case bold:
			return newFont(ff.ui, size, fontBold)
		case heavy:
			return newFont(ff.uiBlack, size, fontRegular)
		}
		return newFont(ff.ui, size, fontRegular)
	})
}

func symbol(size float32) *font {
	return cached(fmt.Sprint("symbol", size), func() *font { return newFont(ff.symbol, size, fontRegular) })
}

// label is the small spaced-out uppercase heading in pink.
func label() *font {
	return cached("label", func() *font {
		f := newFont(ff.mono, 12, fontRegular)
		f.tracking = 2
		return f
	})
}

// charsPerLine counts how many monospaced characters fit the 584 DIP text column (640 card minus 28 padding per side).
var charsPerLine int

// hit is a clickable area, in DIPs from the window's top-left.
type hit struct {
	x, y, w, h float32
	id         string
	action     func()
}

// view draws one frame. With dry set it only lays out, to learn the card's height.
type view struct {
	c       *canvas
	dry     bool
	app     *app
	s       *typer.Session
	ox, oy  float32 // card origin
	hits    []hit
	hover   string
	pressed string
}

func (v *view) fillRound(x, y, w, h, r float32, col color) {
	if !v.dry {
		v.c.fillRound(v.ox+x, v.oy+y, w, h, r, col)
	}
}

func (v *view) strokeRound(x, y, w, h, r, width float32, col color) {
	if !v.dry {
		v.c.strokeRound(v.ox+x, v.oy+y, w, h, r, width, col)
	}
}

func (v *view) text(s string, f *font, x, y float32, col color) {
	if !v.dry {
		v.c.textColor(s, f, v.ox+x, v.oy+y, col)
	}
}

func (v *view) width(s string, f *font) float32 { return v.c.measure(s, f) }

func (v *view) wrap(s string, f *font, w float32) []string {
	return wrapWidth(s, w, func(s string) float32 { return v.width(s, f) })
}

// wrapWidth breaks s into lines no wider than w at spaces, like SwiftUI Text; a word wider than w (a path) breaks
// anywhere.
func wrapWidth(s string, w float32, width func(string) float32) []string {
	if width(s) <= w {
		return []string{s}
	}
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		if next := strings.TrimPrefix(line+" "+word, " "); width(next) <= w {
			line = next
			continue
		}
		if line != "" {
			lines = append(lines, line)
		}
		line = word
		for r := []rune(line); width(line) > w && len(r) > 1; r = []rune(line) {
			n := len(r) - 1
			for n > 1 && width(string(r[:n])) > w {
				n--
			}
			lines = append(lines, string(r[:n]))
			line = string(r[n:])
		}
	}
	return append(lines, line)
}

// paragraph draws s wrapped to w; returns its height.
func (v *view) paragraph(s string, f *font, x, y, w float32, col color) float32 {
	lines := v.wrap(s, f, w)
	for i, line := range lines {
		v.text(line, f, x, y+float32(i)*f.height, col)
	}
	return float32(len(lines)) * f.height
}

// fit cuts s with an ellipsis so it is no wider than w.
func (v *view) fit(s string, f *font, w float32) string {
	r := []rune(s)
	for len(r) > 0 && v.width(string(r)+"…", f) > w {
		r = r[:len(r)-1]
	}
	return string(r) + "…"
}

func (v *view) button(id string, x, y, w, h float32, action func()) bool {
	if v.dry {
		return false
	}
	v.hits = append(v.hits, hit{v.ox + x, v.oy + y, w, h, id, action})
	return v.hover == id
}

// draw lays out (and unless dry, draws) the current screen; returns the card height.
func (v *view) draw() float32 {
	switch {
	case v.s.Picking:
		return v.picker()
	case v.s.Result != nil:
		return v.results(*v.s.Result)
	}
	return v.typing()
}

// background draws the shadow and the card: plum fill, the pink glow from the top-left corner and the border.
func drawBackground(c *canvas, h float32) {
	x, y, w := float32(shadowMargin), float32(shadowMargin), float32(cardWidth)
	// A soft drop shadow, a little lower than the card: stacked translucent black rounded rectangles whose opacity grows
	// toward the card, so it fades out smoothly.
	for i := float32(shadowMargin) - 4; i > 0; i -= 2 {
		t := 1 - i/(shadowMargin-4)
		c.fillRound(x-i, y-i+8, w+2*i, h+2*i, cardRadius+i, opaque.times(0.05*float64(t*t)))
	}
	c.fillRound(x, y, w, h, cardRadius, gBg)
	glow := ellipse(x-420, y-420, 840, 840)
	var brush uintptr
	gdip("GdipCreatePathGradientFromPath", glow, uintptr(unsafe.Pointer(&brush)))
	gdip("GdipSetPathGradientCenterColor", brush, uintptr(gPink.times(0.22)))
	surround, count := gPink.times(0), int32(1)
	gdip("GdipSetPathGradientSurroundColorsWithCount", brush, uintptr(unsafe.Pointer(&surround)), uintptr(unsafe.Pointer(&count)))
	card := roundRect(x, y, w, h, cardRadius)
	c.clip(card)
	c.fillPath(glow, brush)
	c.unclip()
	deletePath(card)
	deletePath(glow)
	deleteBrush(brush)
	c.strokeRound(x, y, w, h, cardRadius, 1, border())
}

func ellipse(x, y, w, h float32) uintptr {
	var p uintptr
	gdip("GdipCreatePath", 0, uintptr(unsafe.Pointer(&p)))
	gdip("GdipAddPathEllipse", p, f32(x), f32(y), f32(w), f32(h))
	return p
}

// logo is the official Aiber Logo 1B: chevron A with a shortened right leg and the base cursor bar.
func logo(c *canvas, x, y, s float32, chevronColor, barColor color) {
	stroke := s * 0.135
	pts := []pointF{{x + s*0.18, y + s*0.77}, {x + s*0.48, y + s*0.21}, {x + s*0.65, y + s*0.53}}
	var pen uintptr
	gdip("GdipCreatePen1", uintptr(chevronColor), f32(stroke), unitPixel, uintptr(unsafe.Pointer(&pen)))
	gdip("GdipSetPenStartCap", pen, 2) // round
	gdip("GdipSetPenEndCap", pen, 2)
	gdip("GdipSetPenLineJoin", pen, 2)
	gdip("GdipDrawLines", c.g, pen, uintptr(unsafe.Pointer(&pts[0])), uintptr(len(pts)))
	gdip("GdipDeletePen", pen)
	barY := y + s*0.77 + stroke*0.5 - stroke
	c.fillRound(x+s*0.56, barY, s*0.30, stroke, stroke*0.48, barColor)
}

func (v *view) brand(x, y float32) {
	if !v.dry {
		logo(v.c, v.ox+x, v.oy+y, 16, gPink, gNeon)
	}
	v.text("AIBER TYPER", label(), x+24, y+8-label().height/2, gPink)
}

// keycap is a key name in a small rounded box; returns its width.
func (v *view) keycap(key string, x, cy float32, col color) float32 {
	f := ui(10, semibold)
	w := v.width(key, f) + 10
	h := f.height + 2
	v.strokeRound(x, cy-h/2, w, h, 4, 1, col.times(0.7))
	v.text(key, f, x+5, cy-f.height/2, col)
	return w
}

// keyHint is a keycap followed by what the key does; returns its width.
func (v *view) keyHint(key, action string, x, cy float32) float32 {
	w := v.keycap(key, x, cy, muted()) + 6
	f := ui(12, regular)
	v.text(action, f, x+w, cy-f.height/2, muted())
	return w + v.width(action, f)
}

func hintsWidth(v *view, hints [][2]string, spacing float32) float32 {
	saved := v.dry
	v.dry = true
	w := float32(0)
	for i, h := range hints {
		if i > 0 {
			w += spacing
		}
		w += v.keyHint(h[0], h[1], 0, 0)
	}
	v.dry = saved
	return w
}

func actionHeight() float32 { return ui(12, semibold).height + 10 }

// actionButton is "Otra ronda [Enter]" or "Cerrar [Esc]"; returns its width.
func (v *view) actionButton(id, title, key string, primary bool, x, y float32, action func()) float32 {
	f := ui(12, semibold)
	cap := v.width(key, ui(10, semibold)) + 10
	w := 12 + v.width(title, f) + 8 + cap + 12
	h := actionHeight()
	hovered := v.button(id, x, y, w, h, action)
	fg := muted()
	switch {
	case primary:
		fg = gBg
		fill := gPink
		if hovered {
			fill = gNeon
		}
		v.fillRound(x, y, w, h, h/2, fill)
	case hovered:
		fg = gPink
		v.strokeRound(x, y, w, h, h/2, 1, fg)
	default:
		v.strokeRound(x, y, w, h, h/2, 1, muted().times(0.6))
	}
	v.text(title, f, x+12, y+5, fg)
	v.keycap(key, x+12+v.width(title, f)+8, y+h/2, fg)
	return w
}

// roundActions draws "Otra ronda" and "Cerrar" ending at right; returns the row height.
func (v *view) roundActions(right, y float32) float32 { // returns its width
	saved := v.dry
	v.dry = true
	wClose := v.actionButton("", "Cerrar", "Esc", false, 0, 0, nil)
	wNew := v.actionButton("", "Otra ronda", "Enter", true, 0, 0, nil)
	v.dry = saved
	v.actionButton("new", "Otra ronda", "Enter", true, right-wClose-10-wNew, y, func() { v.app.do(v.s.NewRound) })
	v.actionButton("close", "Cerrar", "Esc", false, right-wClose, y, func() { v.app.hide(true) })
	return wNew + 10 + wClose
}

// pill is a capsule option: filled when selected; returns its width.
func (v *view) pill(id, text string, selected bool, x, cy float32, action func()) float32 {
	f := ui(12, medium)
	if selected {
		f = ui(12, bold)
	}
	arrow := strings.HasSuffix(text, " ▾")
	name := strings.TrimSuffix(text, " ▾")
	tw := v.width(name, f)
	if arrow {
		tw += v.width(" ", f) + v.width("▾", symbol(11))
	}
	pad := float32(0)
	if selected {
		pad = 10
	}
	w, h := tw+2*pad, f.height+6
	hovered := v.button(id, x, cy-h/2, w, h, action)
	fg := muted()
	switch {
	case selected:
		fg = gBg
		fill := gPink
		if hovered {
			fill = gNeon
		}
		v.fillRound(x, cy-h/2, w, h, h/2, fill)
	case hovered:
		fg = gFg
	}
	v.text(name, f, x+pad, cy-f.height/2, fg)
	if arrow {
		v.text("▾", symbol(11), x+pad+v.width(name+" ", f), cy-symbol(11).height/2+1, fg)
	}
	return w
}

func (v *view) typing() float32 {
	const pad, gap = 28, 20
	s := v.s
	y := float32(pad)

	// Header: brand on the left, collection and language pills on the right.
	headH := ui(12, bold).height + 6
	cy := y + headH/2
	v.brand(pad, cy-8)
	right := float32(cardWidth - pad)
	saved := v.dry
	v.dry = true
	wEN := v.pill("", typer.EN.Label(), s.Lang == typer.EN, 0, 0, nil)
	wES := v.pill("", typer.ES.Label(), s.Lang == typer.ES, 0, 0, nil)
	name := s.Collection.Name
	wCol := v.pill("", name+" ▾", true, 0, 0, nil)
	x := right - wEN - 10 - wES - 10 - wCol
	// A long collection name is cut so the pill stops short of the brand.
	if over := pad + 24 + v.width("AIBER TYPER", label()) + 10 - x; over > 0 {
		name = v.fit(name, ui(12, bold), v.width(name, ui(12, bold))-over)
		wCol = v.pill("", name+" ▾", true, 0, 0, nil)
		x = right - wEN - 10 - wES - 10 - wCol
	}
	v.dry = saved
	toggle := func() { v.app.do(s.ToggleLanguage) }
	v.pill("collection", name+" ▾", true, x, cy, func() { v.app.do(s.OpenPicker) })
	x += wCol + 10
	// Clicking the already selected language does nothing.
	v.pill("es", typer.ES.Label(), s.Lang == typer.ES, x, cy, ifNot(s.Lang == typer.ES, toggle))
	v.pill("en", typer.EN.Label(), s.Lang == typer.EN, x+wES+10, cy, ifNot(s.Lang == typer.EN, toggle))
	y += headH + gap

	y = v.textLines(pad, y) + gap

	if source, ok := s.Round.Source(); ok {
		y += v.paragraph("— "+source, ui(12, regular), pad, y, cardWidth-2*pad, muted()) + gap
	}

	live, started := s.Round.Live(now())
	y = v.liveStats(live, started, pad, y) + gap

	// Progress bar with a neon glow on the filled part.
	progress := float32(0)
	if len(s.Round.Target) > 0 {
		progress = float32(len(s.Round.Typed())) / float32(len(s.Round.Target))
	}
	barW := float32(cardWidth - 2*pad)
	v.fillRound(pad, y, barW, 4, 2, border())
	if progress > 0 && !v.dry {
		fw := barW * progress
		for i := float32(6); i >= 1; i-- {
			v.fillRound(pad-i, y-i, fw+2*i, 4+2*i, 2+i, gNeon.times(0.8*0.035))
		}
		b := linear(pointF{v.ox + pad - 1, 0}, pointF{v.ox + pad + fw + 1, 0}, gPink, gNeon)
		v.c.fillRoundBrush(v.ox+pad, v.oy+y, fw, 4, 2, b)
		deleteBrush(b)
	}
	y += 4 + gap

	// Footer: key hints on the left, the round actions on the right.
	rowH := actionHeight()
	x = pad
	x += v.keyHint("Tab", "idioma", x, y+rowH/2) + 16
	v.keyHint("Shift+Tab", "colección", x, y+rowH/2)
	v.roundActions(cardWidth-pad, y)
	return y + rowH + pad
}

func ifNot(cond bool, action func()) func() {
	if cond {
		return func() {}
	}
	return action
}

// textLines draws three sharp lines around the cursor, the line before and after blurred, the rest hidden.
func (v *view) textLines(x, y float32) float32 {
	r := &v.s.Round
	target, typed := r.Target, r.Typed()
	lines := typer.WrapLines(target, charsPerLine)
	w := typer.LineWindow(lines, len(typed), 3)
	f := mono(textSize, false)
	drawn := 0
	draw := func(i int, dimmed bool) {
		if !v.dry {
			v.line(target, typed, lines[i], x, y, dimmed)
		}
		y += f.height + 8
		drawn++
	}
	if w.Before >= 0 {
		draw(w.Before, true)
	}
	for i := w.Focus.Lo; i < w.Focus.Hi; i++ {
		draw(i, false)
	}
	if w.After >= 0 {
		draw(w.After, true)
	}
	if drawn == 0 {
		return y
	}
	return y - 8
}

// line draws one wrapped line: correct text bright, mistakes in crimson, the cursor as a pink block, the rest muted.
// blurredLines keeps the dimmed lines already blurred: they change only when the focus moves to another line, while
// each keystroke and stats tick redraws the whole frame.
var blurredLines = map[string]uintptr{}

func (v *view) line(target, typed []rune, span typer.Span, x, y float32, dimmed bool) {
	f := mono(textSize, false)
	opacity := 1.0
	c, ox, oy := v.c, v.ox+x, v.oy+y
	runs := typer.MarkRuns(target, typed, span)
	var tmp *canvas
	const margin = 6
	pw := int(float32(cardWidth-2*28+2*margin) * c.scale)
	ph := int((f.height + 2*margin) * c.scale)
	var key string
	if dimmed {
		key = fmt.Sprint(c.scale, runs, string(target[span.Lo:span.Hi]))
		if bmp, ok := blurredLines[key]; ok {
			v.c.image(bmp, v.ox+x-margin, v.oy+y-margin, pw, ph)
			return
		}
		opacity = 0.45
		if highContrast {
			opacity = 0.7
		}
		// Blurred like the Mac's .blur(radius: 1.5): drawn on a scratch bitmap, softened, then copied.
		tmp = newCanvas(newBitmap(pw, ph, pixelFormat32bppPARGB, nil), c.scale)
		c, ox, oy = tmp, margin, margin
	}
	for _, run := range runs {
		rx := ox + float32(run.Span.Lo-span.Lo)*f.advance
		rw := float32(run.Span.Hi-run.Span.Lo) * f.advance
		var fg color
		switch run.Mark {
		case typer.Correct:
			fg = gFg
		case typer.Wrong:
			fg = gNeon
			c.fillRect(rx, oy, rw, f.height, gNeon.times(0.2*opacity))
		case typer.Cursor:
			fg = gBg
			c.fillRect(rx, oy, rw, f.height, gPink.times(opacity))
		case typer.Pending:
			fg = muted().times(map[bool]float64{false: 0.5, true: 0.8}[highContrast])
		}
		c.textColor(string(target[run.Span.Lo:run.Span.Hi]), f, rx, oy, fg.times(opacity))
	}
	if tmp != nil {
		blur(tmp.bmp, 1.5*2.2*tmp.scale)
		gdip("GdipDeleteGraphics", tmp.g)
		v.c.image(tmp.bmp, v.ox+x-margin, v.oy+y-margin, pw, ph)
		if len(blurredLines) >= 4 { // the line before and after the focus, at one or two scales
			for k, bmp := range blurredLines {
				gdip("GdipDisposeImage", bmp)
				delete(blurredLines, k)
			}
		}
		blurredLines[key] = tmp.bmp
	}
}

// cell is a big value over a small caption; returns its width and height.
func (v *view) cell(value, caption string, size float32, col color, x, y float32) (float32, float32) {
	vf, cf := mono(size, true), ui(12, regular)
	v.text(value, vf, x, y, col)
	v.text(caption, cf, x, y+vf.height+2, muted())
	return max(v.width(value, vf), v.width(caption, cf)), vf.height + 2 + cf.height
}

func (v *view) liveStats(live typer.Score, started bool, x, y float32) float32 {
	wpm, acc := "—", "—"
	if started {
		wpm = fmt.Sprint(int(math.Round(live.WPM)))
		acc = fmt.Sprintf("%d%%", int(math.Round(live.Accuracy*100)))
	}
	w, h := v.cell(wpm, "ppm", 28, gPink, x, y)
	v.cell(acc, "precisión", 28, gPink, x+w+28, y)
	return y + h
}

// picker is the filterable list of collections; the keys are mapped by typer.PanelKey.
func (v *view) picker() float32 {
	const pad, gap = 28, 16
	s := v.s
	y := float32(pad)
	v.text("COLECCIÓN", label(), pad, y, gPink)
	y += label().height + gap
	ff := mono(16, false)
	if s.Filter == "" {
		v.text("escribe para filtrar", ff, pad, y, muted())
	} else {
		v.text(s.Filter, ff, pad, y, gPink)
	}
	y += ff.height + gap

	matches := s.Matches()
	if len(matches) == 0 {
		f := ui(14, regular)
		v.text("Sin resultados", f, pad, y, muted())
		y += f.height
	}
	for i, c := range matches {
		selected := i == s.Selection
		f := ui(15, regular)
		if selected {
			f = ui(15, bold)
		}
		rowW, rowH := float32(cardWidth-2*pad), f.height+12
		index := i
		hovered := v.button(fmt.Sprint("row", i), pad, y, rowW, rowH, func() { v.app.do(func() { s.ChooseMatch(index) }) })
		fg := gFg
		switch {
		case selected:
			v.fillRound(pad, y, rowW, rowH, 6, gPink)
			fg = gBg
		case hovered:
			v.fillRound(pad, y, rowW, rowH, 6, gPink.times(0.15))
		}
		x := float32(pad + 12)
		if s.Favorites[c.ID] {
			v.text("★", symbol(15), x, y+6, fg)
			x += v.width("★", symbol(15)) + 8
		}
		v.text(c.Name, f, x, y+6, fg)
		if c.ID == s.Collection.ID {
			v.text("✓", symbol(15), pad+rowW-12-v.width("✓", symbol(15)), y+6, gNeon)
		}
		y += rowH + 4
	}
	if len(matches) > 0 {
		y -= 4
	}
	y += gap
	for _, p := range s.Problems {
		y += v.paragraph(p, ui(12, regular), pad, y, cardWidth-2*pad, gNeon) + gap
	}
	f := ui(13, medium)
	title := "+ Importar colección…"
	importColor := gPink
	if v.button("import", pad, y, v.width(title, f), f.height, v.app.importCollections) {
		importColor = gNeon
	}
	v.text(title, f, pad, y, importColor)
	y += f.height + gap
	hints := [][2]string{{"Ctrl+J/K", "mover"}, {"Ctrl+F", "favorita"}, {"Ctrl+I", "importar"}, {"Enter", "elegir"}, {"Esc", "volver"}}
	x := cardWidth - pad - hintsWidth(v, hints, 12)
	rowH := ui(12, regular).height + 2
	for _, h := range hints {
		x += v.keyHint(h[0], h[1], x, y+rowH/2) + 12
	}
	return y + rowH + pad
}

func (v *view) results(r typer.RoundResult) float32 {
	const pad, gap = 30, 18
	s := v.s
	wpm := int(math.Round(r.WPM))
	accuracy := int(math.Round(r.Accuracy * 100))
	seconds := int(math.Round(r.Seconds))
	contentW := float32(cardWidth - 2*pad)
	half := (contentW - 1) / 2
	y := float32(pad)

	// Left: the WPM, big, with the record tag and the change against the average.
	big := ui(104, heavy)
	leftH := label().height + 6 + big.height*0.86 + 6 + mono(11, true).height + 4
	// Right: accuracy, time, correct characters and errors in a 2×2 grid.
	cellH := mono(30, true).height + 2 + ui(12, regular).height
	rightH := 2*cellH + 22
	topH := max(leftH, rightH)

	ly := y + (topH-leftH)/2
	v.text("PALABRAS POR MINUTO", label(), pad, ly, gPink)
	ly += label().height + 6
	if !v.dry {
		num := fmt.Sprint(wpm)
		// Tracking -3: drawn digit by digit.
		top := v.oy + ly - big.height*0.07
		b := linear(pointF{0, top + big.height*0.2}, pointF{0, top + big.height*0.85}, gFg, gPink)
		x := v.ox + pad
		for _, d := range num {
			v.c.text(string(d), big, x, top, b)
			x += v.c.measure(string(d), big) - 3
		}
		deleteBrush(b)
	}
	ly += big.height*0.86 + 6
	tagF := mono(11, true)
	x := float32(pad)
	if s.IsRecord {
		tw := v.width("NUEVO RÉCORD", tagF) + 12
		v.strokeRound(x, ly, tw, tagF.height+4, 3, 1, gYellow.times(0.7))
		v.text("NUEVO RÉCORD", tagF, x+6, ly+2, gYellow)
		x += tw + 8
	}
	if s.HasAverage {
		delta := int(math.Round(r.WPM - s.AverageBefore))
		sign := "+"
		if delta < 0 {
			sign, delta = "−", -delta
		}
		f := ui(13, regular)
		v.text(fmt.Sprintf("%s%d sobre tu media", sign, delta), f, x, ly+(tagF.height+4-f.height)/2, muted())
	}

	// Divider.
	v.fillRound(pad+half, y+6, 1, topH-12, 0, border())

	gx, gy := pad+half+1+36, y+(topH-rightH)/2
	// The grid's first column is as wide as its widest cell.
	colW := max(v.width(fmt.Sprintf("%d%%", accuracy), mono(30, true)), v.width(fmt.Sprint(s.Round.Correct()), mono(30, true)),
		v.width("precisión", ui(12, regular)), v.width("correctas", ui(12, regular)))
	v.cell(fmt.Sprintf("%d%%", accuracy), "precisión", 30, gPink, gx, gy)
	v.cell(fmt.Sprintf("%ds", seconds), "tiempo", 30, gPink, gx+colW+40, gy)
	v.cell(fmt.Sprint(s.Round.Correct()), "correctas", 30, gPink, gx, gy+cellH+22)
	v.cell(fmt.Sprint(s.Round.Errors), "errores", 30, gNeon, gx+colW+40, gy+cellH+22)
	y += topH + gap

	if wpms := s.RecentWPMs(); len(wpms) > 1 {
		y = v.historyChart(wpms, pad, y, contentW) + gap
	}

	// The note wraps in the room the buttons leave, and the row grows to fit it, as in the SwiftUI HStack.
	rowH := actionHeight()
	saved := v.dry
	v.dry = true
	actionsW := v.roundActions(0, 0)
	v.dry = saved
	if s.Note != "" {
		f := ui(12, regular)
		lines := v.wrap(s.Note, f, contentW-actionsW-8)
		rowH = max(rowH, float32(len(lines))*f.height)
		v.paragraph(s.Note, f, pad, y+(rowH-float32(len(lines))*f.height)/2, contentW-actionsW-8, gNeon)
	}
	v.roundActions(cardWidth-pad, y+(rowH-actionHeight())/2)
	return y + rowH + pad
}

// historyChart draws bars for recent rounds; the last one (this round) is highlighted.
func (v *view) historyChart(wpms []float64, x, y, w float32) float32 {
	v.fillRound(x, y, w, 1, 0, border())
	y += 14
	v.text("HISTORIAL", label(), x, y, gPink)
	f := ui(12, regular)
	caption := fmt.Sprintf("últimas %d rondas", len(wpms))
	v.text(caption, f, x+w-v.width(caption, f), y+(label().height-f.height)/2, muted())
	y += label().height + 10
	top, low := wpms[0], wpms[0]
	for _, w := range wpms {
		top, low = max(top, w), min(low, w)
	}
	low *= 0.7
	for i, wpm := range wpms {
		h := float32(48)
		if top > low {
			h = float32(6 + 42*(wpm-low)/(top-low))
		}
		bx, by := x+float32(i)*(22+5), y+48-h
		if i < len(wpms)-1 {
			v.fillRound(bx, by, 22, h, 3, gPink.times(0.3))
		} else if !v.dry {
			b := linear(pointF{0, v.oy + by - 1}, pointF{0, v.oy + by + h + 1}, gPink, gNeon)
			v.c.fillRoundBrush(v.ox+bx, v.oy+by, 22, h, 3, b)
			deleteBrush(b)
		}
	}
	return y + 48
}
