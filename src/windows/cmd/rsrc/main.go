// Command rsrc writes the Windows resources the Go linker embeds in AiberTyper.exe: the app icon (from
// design/brand/icon-1024.png) and the manifest (per-monitor DPI, Common Controls 6, GDI+ 1.1, no elevation).
//
//	go run ./cmd/rsrc <icon.png> <out.syso>
//
// A .syso file is a COFF object with a .rsrc section; build.sh runs this before go build.
package main

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/draw"
	"image/png"
	"os"
	"sort"
)

const manifest = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="Aiber.AiberTyper" version="1.0.0.0"/>
  <description>Aiber Typer</description>
  <dependency><dependentAssembly>
    <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
  </dependentAssembly></dependency>
  <dependency><dependentAssembly>
    <assemblyIdentity type="win32" name="Microsoft.Windows.GdiPlus" version="1.1.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
  </dependentAssembly></dependency>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/></application>
  </compatibility>
</assembly>
`

const (
	rtIcon      = 3
	rtGroupIcon = 14
	rtManifest  = 24
	langEnUS    = 0x0409
)

type resource struct {
	typ, id int
	data    []byte
}

func main() {
	if len(os.Args) != 3 {
		os.Stderr.WriteString("usage: rsrc <icon.png> <out.syso>\n")
		os.Exit(2)
	}
	f, err := os.Open(os.Args[1])
	check(err)
	src, err := png.Decode(f)
	check(err)
	f.Close()

	resources := []resource{{rtManifest, 1, []byte(manifest)}}
	group := new(bytes.Buffer)
	sizes := []int{16, 20, 24, 32, 40, 48, 64, 256}
	binary.Write(group, binary.LittleEndian, [3]uint16{0, 1, uint16(len(sizes))})
	for i, s := range sizes {
		img := scale(src, s)
		var data []byte
		if s == 256 {
			b := new(bytes.Buffer)
			check(png.Encode(b, img))
			data = b.Bytes()
		} else {
			data = dib(img)
		}
		id := i + 1
		resources = append(resources, resource{rtIcon, id, data})
		dim := byte(s)
		if s == 256 {
			dim = 0
		}
		group.Write([]byte{dim, dim, 0, 0})
		binary.Write(group, binary.LittleEndian, struct {
			Planes, BitCount uint16
			Bytes            uint32
			ID               uint16
		}{1, 32, uint32(len(data)), uint16(id)})
	}
	resources = append(resources, resource{rtGroupIcon, 1, group.Bytes()})
	check(os.WriteFile(os.Args[2], coff(resources), 0o644))
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

// scale shrinks src to s×s by averaging the source pixels each target pixel covers (premultiplied, so edges stay clean).
func scale(src image.Image, s int) *image.NRGBA {
	in := image.NewRGBA(src.Bounds())
	draw.Draw(in, in.Bounds(), src, src.Bounds().Min, draw.Src)
	w, h := in.Bounds().Dx(), in.Bounds().Dy()
	out := image.NewNRGBA(image.Rect(0, 0, s, s))
	for y := 0; y < s; y++ {
		for x := 0; x < s; x++ {
			x0, x1, y0, y1 := x*w/s, max((x+1)*w/s, x*w/s+1), y*h/s, max((y+1)*h/s, y*h/s+1)
			var r, g, b, a, n int
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					o := in.PixOffset(xx, yy)
					r, g, b, a = r+int(in.Pix[o]), g+int(in.Pix[o+1]), b+int(in.Pix[o+2]), a+int(in.Pix[o+3])
					n++
				}
			}
			o := out.PixOffset(x, y)
			if a > 0 {
				out.Pix[o], out.Pix[o+1], out.Pix[o+2] = byte(r*255/a), byte(g*255/a), byte(b*255/a)
			}
			out.Pix[o+3] = byte(a / n)
		}
	}
	return out
}

// dib is an icon image in BMP form: a 32-bit BGRA bitmap, bottom-up and twice as tall, then an all-zero AND mask.
func dib(img *image.NRGBA) []byte {
	s := img.Bounds().Dx()
	b := new(bytes.Buffer)
	binary.Write(b, binary.LittleEndian, struct {
		Size                  uint32
		Width, Height         int32
		Planes, BitCount      uint16
		Compression, Image    uint32
		XPels, YPels          int32
		ClrUsed, ClrImportant uint32
	}{Size: 40, Width: int32(s), Height: int32(2 * s), Planes: 1, BitCount: 32})
	for y := s - 1; y >= 0; y-- {
		for x := 0; x < s; x++ {
			o := img.PixOffset(x, y)
			b.Write([]byte{img.Pix[o+2], img.Pix[o+1], img.Pix[o], img.Pix[o+3]})
		}
	}
	b.Write(make([]byte, ((s+31)/32*4)*s))
	return b.Bytes()
}

// coff lays out the resource tree (type, then id, then language) in a .rsrc section, with one ADDR32NB
// relocation per data entry so the linker can turn section offsets into RVAs.
func coff(resources []resource) []byte {
	sort.Slice(resources, func(i, j int) bool {
		if resources[i].typ != resources[j].typ {
			return resources[i].typ < resources[j].typ
		}
		return resources[i].id < resources[j].id
	})
	var types []int
	byType := map[int][]int{}
	for i, r := range resources {
		if len(byType[r.typ]) == 0 {
			types = append(types, r.typ)
		}
		byType[r.typ] = append(byType[r.typ], i)
	}
	const dirSize, entrySize, dataEntrySize = 16, 8, 16
	// Offsets: root directory, one directory per type, one per resource (language level), then data entries, then data.
	off := dirSize + entrySize*len(types)
	typeDir := map[int]int{}
	for _, t := range types {
		typeDir[t] = off
		off += dirSize + entrySize*len(byType[t])
	}
	langDir := make([]int, len(resources))
	for i := range resources {
		langDir[i] = off
		off += dirSize + entrySize
	}
	dataEntry := make([]int, len(resources))
	for i := range resources {
		dataEntry[i] = off
		off += dataEntrySize
	}
	dataOff := make([]int, len(resources))
	for i, r := range resources {
		off = (off + 7) &^ 7
		dataOff[i] = off
		off += len(r.data)
	}
	sec := make([]byte, (off+7)&^7)
	le := binary.LittleEndian
	dir := func(at, ids int) { le.PutUint16(sec[at+14:], uint16(ids)) }
	entry := func(at, id, target int, subdir bool) {
		le.PutUint32(sec[at:], uint32(id))
		if subdir {
			target |= 0x80000000
		}
		le.PutUint32(sec[at+4:], uint32(target))
	}
	dir(0, len(types))
	for i, t := range types {
		entry(dirSize+entrySize*i, t, typeDir[t], true)
		dir(typeDir[t], len(byType[t]))
		for j, ri := range byType[t] {
			entry(typeDir[t]+dirSize+entrySize*j, resources[ri].id, langDir[ri], true)
		}
	}
	var relocs []int
	for i, r := range resources {
		dir(langDir[i], 1)
		entry(langDir[i]+dirSize, langEnUS, dataEntry[i], false)
		le.PutUint32(sec[dataEntry[i]:], uint32(dataOff[i])) // RVA once relocated
		le.PutUint32(sec[dataEntry[i]+4:], uint32(len(r.data)))
		relocs = append(relocs, dataEntry[i])
		copy(sec[dataOff[i]:], r.data)
	}

	out := new(bytes.Buffer)
	const headerSize, sectionHeaderSize, relocSize = 20, 40, 10
	rawPtr := headerSize + sectionHeaderSize
	relocPtr := rawPtr + len(sec)
	symPtr := relocPtr + relocSize*len(relocs)
	binary.Write(out, le, struct {
		Machine                         uint16
		Sections                        uint16
		Time, SymbolTable, Symbols      uint32
		OptionalHeader, Characteristics uint16
	}{0x8664, 1, 0, uint32(symPtr), 1, 0, 0})
	binary.Write(out, le, struct {
		Name                                [8]byte
		VirtualSize, VirtualAddress         uint32
		RawSize, RawPtr, RelocPtr, LinesPtr uint32
		Relocs, Lines                       uint16
		Characteristics                     uint32
	}{[8]byte{'.', 'r', 's', 'r', 'c'}, 0, 0, uint32(len(sec)), uint32(rawPtr), uint32(relocPtr), 0, uint16(len(relocs)), 0, 0x40000040})
	out.Write(sec)
	for _, r := range relocs {
		binary.Write(out, le, struct {
			Address, Symbol uint32
			Type            uint16
		}{uint32(r), 0, 3}) // IMAGE_REL_AMD64_ADDR32NB against the section symbol
	}
	binary.Write(out, le, struct {
		Name       [8]byte
		Value      uint32
		Section    int16
		Type       uint16
		Class, Aux uint8
	}{[8]byte{'.', 'r', 's', 'r', 'c'}, 0, 1, 0, 3, 0}) // static section symbol
	binary.Write(out, le, uint32(4)) // empty string table
	return out.Bytes()
}
