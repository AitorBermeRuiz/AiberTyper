//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

// GDI+ flat API: antialiased shapes, gradients and text on a premultiplied ARGB bitmap, which UpdateLayeredWindow
// then puts on screen with per-pixel alpha (rounded corners and the shadow). Float arguments are passed in the
// integer slots; Go's amd64 syscalls copy them to the XMM registers, so this is amd64 only (see build.sh).

var (
	gdiplus = syscall.NewLazyDLL("gdiplus.dll")
	gp      = map[string]*syscall.LazyProc{}
)

// gdip calls a GDI+ function. Callers pass pointers as uintptr(unsafe.Pointer(…)); uintptrescapes keeps what they
// point to alive and in place until the call returns, as it does for LazyProc.Call.
//
//go:uintptrescapes
func gdip(name string, args ...uintptr) uintptr {
	p, ok := gp[name]
	if !ok {
		p = gdiplus.NewProc(name)
		gp[name] = p
	}
	r, _, _ := p.Call(args...)
	return r
}

func gdipAvailable(name string) bool { return gdiplus.NewProc(name).Find() == nil }

const (
	pixelFormat32bppARGB  = 0x26200A
	pixelFormat32bppPARGB = 0xE200B
	unitPixel             = 2
	fontRegular           = 0
	fontBold              = 1
)

type guid struct {
	Data1        uint32
	Data2, Data3 uint16
	Data4        [8]byte
}

var (
	clsidPNG       = guid{0x557CF406, 0x1A04, 0x11D3, [8]byte{0x9A, 0x73, 0x00, 0x00, 0xF8, 0x1E, 0xF3, 0x2E}}
	blurEffectGUID = guid{0x633C80A4, 0x1843, 0x482B, [8]byte{0x9E, 0xF2, 0xBE, 0x28, 0x34, 0xC5, 0xFD, 0xD4}}
)

func gdiplusStartup() {
	input := struct {
		Version                  uint32
		DebugEventCallback       uintptr
		SuppressBackgroundThread int32
		SuppressExternalCodecs   int32
	}{Version: 1}
	var token uintptr
	gdip("GdiplusStartup", uintptr(unsafe.Pointer(&token)), uintptr(unsafe.Pointer(&input)), 0)
}

// color is 0xAARRGGBB.
type color uint32

// opaque is the alpha byte of a palette color: or it with 0xRRGGBB, then scale it with times().
const opaque color = 0xFF000000

func (c color) times(opacity float64) color {
	return color(uint32(float64(c>>24)*opacity+0.5)<<24 | uint32(c)&0xFFFFFF)
}

type rectF struct{ X, Y, W, H float32 }
type pointF struct{ X, Y float32 }

// canvas draws in DIPs on a bitmap of scale × DIPs pixels.
type canvas struct {
	g, bmp uintptr
	scale  float32
}

func newBitmap(w, h int, format uintptr, bits unsafe.Pointer) uintptr {
	var bmp uintptr
	stride := 0
	if bits != nil {
		stride = w * 4
	}
	gdip("GdipCreateBitmapFromScan0", uintptr(w), uintptr(h), uintptr(stride), format, uintptr(bits), uintptr(unsafe.Pointer(&bmp)))
	return bmp
}

func newCanvas(bmp uintptr, scale float32) *canvas {
	c := &canvas{bmp: bmp, scale: scale}
	gdip("GdipGetImageGraphicsContext", bmp, uintptr(unsafe.Pointer(&c.g)))
	gdip("GdipSetSmoothingMode", c.g, 4)     // antialias
	gdip("GdipSetPixelOffsetMode", c.g, 4)   // half: shapes land on pixel edges
	gdip("GdipSetTextRenderingHint", c.g, 4) // antialias: ClearType needs an opaque target
	gdip("GdipSetInterpolationMode", c.g, 7) // high-quality bicubic
	gdip("GdipScaleWorldTransform", c.g, f32(scale), f32(scale), 0)
	return c
}

func (c *canvas) close() {
	gdip("GdipDeleteGraphics", c.g)
	gdip("GdipDisposeImage", c.bmp)
}

func (c *canvas) clear() { gdip("GdipGraphicsClear", c.g, 0) }

func solid(col color) uintptr {
	var b uintptr
	gdip("GdipCreateSolidFill", uintptr(col), uintptr(unsafe.Pointer(&b)))
	return b
}

func deleteBrush(b uintptr) { gdip("GdipDeleteBrush", b) }

// linear is a gradient from p1 (c1) to p2 (c2).
func linear(p1, p2 pointF, c1, c2 color) uintptr {
	var b uintptr
	gdip("GdipCreateLineBrush", uintptr(unsafe.Pointer(&p1)), uintptr(unsafe.Pointer(&p2)), uintptr(c1), uintptr(c2), 3, uintptr(unsafe.Pointer(&b))) // tile flip XY: no seam past the ends
	return b
}

func roundRect(x, y, w, h, r float32) uintptr {
	var p uintptr
	gdip("GdipCreatePath", 0, uintptr(unsafe.Pointer(&p)))
	r = min(r, w/2, h/2)
	d := 2 * r
	if r <= 0 {
		gdip("GdipAddPathRectangle", p, f32(x), f32(y), f32(w), f32(h))
		return p
	}
	gdip("GdipAddPathArc", p, f32(x), f32(y), f32(d), f32(d), f32(180), f32(90))
	gdip("GdipAddPathArc", p, f32(x+w-d), f32(y), f32(d), f32(d), f32(270), f32(90))
	gdip("GdipAddPathArc", p, f32(x+w-d), f32(y+h-d), f32(d), f32(d), f32(0), f32(90))
	gdip("GdipAddPathArc", p, f32(x), f32(y+h-d), f32(d), f32(d), f32(90), f32(90))
	gdip("GdipClosePathFigure", p)
	return p
}

func deletePath(p uintptr) { gdip("GdipDeletePath", p) }

func (c *canvas) fillPath(p, brush uintptr) { gdip("GdipFillPath", c.g, brush, p) }

func (c *canvas) fillRound(x, y, w, h, r float32, col color) {
	if col>>24 == 0 {
		return
	}
	p, b := roundRect(x, y, w, h, r), solid(col)
	c.fillPath(p, b)
	deleteBrush(b)
	deletePath(p)
}

func (c *canvas) fillRoundBrush(x, y, w, h, r float32, brush uintptr) {
	p := roundRect(x, y, w, h, r)
	c.fillPath(p, brush)
	deletePath(p)
}

// strokeRound draws a border inside the rectangle, like SwiftUI's strokeBorder.
func (c *canvas) strokeRound(x, y, w, h, r, width float32, col color) {
	if col>>24 == 0 {
		return
	}
	p := roundRect(x+width/2, y+width/2, w-width, h-width, r-width/2)
	var pen uintptr
	gdip("GdipCreatePen1", uintptr(col), f32(width), unitPixel, uintptr(unsafe.Pointer(&pen)))
	gdip("GdipDrawPath", c.g, pen, p)
	gdip("GdipDeletePen", pen)
	deletePath(p)
}

func (c *canvas) fillRect(x, y, w, h float32, col color) {
	b := solid(col)
	gdip("GdipFillRectangle", c.g, b, f32(x), f32(y), f32(w), f32(h))
	deleteBrush(b)
}

func (c *canvas) clip(p uintptr) { gdip("GdipSetClipPath", c.g, p, 0) }
func (c *canvas) unclip()        { gdip("GdipResetClip", c.g) }

// font is a GDI+ font with the metrics layout needs, in DIPs.
type font struct {
	handle         uintptr
	size           float32
	ascent, height float32
	advance        float32 // of "M", for monospaced fonts
	tracking       float32
}

// stringFormat is GDI+'s typographic format, without wrapping or clipping (newTypographic).
var stringFormat uintptr

// fontFamily returns the first installed family of names.
func fontFamily(names ...string) (uintptr, string) {
	for _, name := range names {
		var fam uintptr
		if gdip("GdipCreateFontFamilyFromName", uintptr(unsafe.Pointer(wstr(name))), 0, uintptr(unsafe.Pointer(&fam))) == 0 {
			return fam, name
		}
	}
	return 0, ""
}

func newFont(family uintptr, size float32, style int) *font {
	f := &font{size: size}
	gdip("GdipCreateFont", family, f32(size), uintptr(style), unitPixel, uintptr(unsafe.Pointer(&f.handle)))
	var em, ascent, spacing uint16
	gdip("GdipGetEmHeight", family, uintptr(style), uintptr(unsafe.Pointer(&em)))
	gdip("GdipGetCellAscent", family, uintptr(style), uintptr(unsafe.Pointer(&ascent)))
	gdip("GdipGetLineSpacing", family, uintptr(style), uintptr(unsafe.Pointer(&spacing)))
	if em > 0 {
		f.ascent = size * float32(ascent) / float32(em)
		f.height = size * float32(spacing) / float32(em)
	}
	return f
}

type measureKey struct {
	s     string
	f     *font
	scale float32
}

// measured caches GdipMeasureString: a frame measures about a hundred strings, most of them constant, in the dry
// layout and again in the real one. Cleared when the typed text's churn fills it.
var measured = map[measureKey]float32{}

func (c *canvas) measure(s string, f *font) float32 {
	if s == "" {
		return 0
	}
	key := measureKey{s, f, c.scale}
	if w, ok := measured[key]; ok {
		return w
	}
	u := utf16z(s)
	var bounds rectF
	layout := rectF{}
	gdip("GdipMeasureString", c.g, uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)-1), f.handle, uintptr(unsafe.Pointer(&layout)),
		stringFormat, uintptr(unsafe.Pointer(&bounds)), 0, 0)
	w := bounds.W + f.tracking*float32(len([]rune(s)))
	if len(measured) >= 2000 {
		clear(measured)
	}
	measured[key] = w
	return w
}

// text draws s with its top-left at (x, y); y is the top of the line, so the baseline is at y + f.ascent.
func (c *canvas) text(s string, f *font, x, y float32, brush uintptr) {
	if s == "" {
		return
	}
	if f.tracking != 0 {
		// GDI+ has no letter spacing: draw letter by letter.
		for _, r := range s {
			ch := string(r)
			c.text1(ch, f, x, y, brush)
			x += c.measure(ch, f)
		}
		return
	}
	c.text1(s, f, x, y, brush)
}

func (c *canvas) text1(s string, f *font, x, y float32, brush uintptr) {
	u := utf16z(s)
	layout := rectF{X: x, Y: y}
	gdip("GdipDrawString", c.g, uintptr(unsafe.Pointer(&u[0])), uintptr(len(u)-1), f.handle, uintptr(unsafe.Pointer(&layout)), stringFormat, brush)
}

func (c *canvas) textColor(s string, f *font, x, y float32, col color) {
	b := solid(col)
	c.text(s, f, x, y, b)
	deleteBrush(b)
}

// image draws bitmap img (in device pixels) at (x, y) DIPs, one pixel per pixel.
func (c *canvas) image(img uintptr, x, y float32, w, h int) {
	gdip("GdipDrawImageRect", c.g, img, f32(x), f32(y), f32(float32(w)/c.scale), f32(float32(h)/c.scale))
}

// blur softens img in place; a no-op where GDI+ 1.1 effects are missing.
func blur(img uintptr, radius float32) {
	if !gdipAvailable("GdipCreateEffect") {
		return
	}
	var effect uintptr
	if gdip("GdipCreateEffect", uintptr(unsafe.Pointer(&blurEffectGUID)), uintptr(unsafe.Pointer(&effect))) != 0 {
		return
	}
	params := struct {
		Radius     float32
		ExpandEdge int32
	}{radius, 0}
	gdip("GdipSetEffectParameters", effect, uintptr(unsafe.Pointer(&params)), unsafe.Sizeof(params))
	gdip("GdipBitmapApplyEffect", img, effect, 0, 0, 0, 0)
	gdip("GdipDeleteEffect", effect)
}

func savePNG(img uintptr, path string) error {
	if st := gdip("GdipSaveImageToFile", img, uintptr(unsafe.Pointer(wstr(path))), uintptr(unsafe.Pointer(&clsidPNG)), 0); st != 0 {
		return syscall.Errno(st)
	}
	return nil
}
