//go:build windows

package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"aibertyper/typer"
)

// --bench: windows/bench drives this instance through stdin, with a temporary history and settings, never the
// user's (runBench in main.swift). Commands, one per line, each answered with one line:
//
//	show, hide              like the shortcut and Esc
//	type <wpm> [chars]      types the round's next characters (all by default) as WM_CHAR messages
//	key <name>              performs a panel key: tab, shift+tab, esc, enter, back, down, ctrl+f
//	char <text>             types text as WM_CHAR messages
//	shot <file.png>         saves the last frame, transparent shadow included
//	state                   visible, picking, result, foreground, window position…
//	stats                   CPU time and memory of this process
//	scale <n>               draws at n× from now on, whatever the monitor (screenshots of high-DPI rendering)
//	where <id>              screen pixel at the middle of a clickable area (ids in view.go: new, close, es, en, rowN…)
//	import, hotkey          run the import or Cambiar atajo… flow; they answer once its dialogs close
//
// End of input deletes the temporary folder and quits.
type bench struct {
	dir   string
	app   *app
	mu    sync.Mutex
	queue []func()
	out   *bufio.Writer
}

func newBench() *bench {
	dir, err := os.MkdirTemp("", "aiber-bench-")
	if err != nil {
		panic(err)
	}
	return &bench{dir: dir, out: bufio.NewWriter(os.Stdout)}
}

func (b *bench) reply(format string, args ...any) {
	fmt.Fprintf(b.out, format+"\n", args...)
	b.out.Flush()
}

// post runs f on the main thread.
func (b *bench) post(f func()) {
	b.mu.Lock()
	b.queue = append(b.queue, f)
	b.mu.Unlock()
	pPostMessageW.Call(b.app.owner, wmAppRun, 0, 0)
}

func (b *bench) run() {
	b.mu.Lock()
	queue := b.queue
	b.queue = nil
	b.mu.Unlock()
	for _, f := range queue {
		f()
	}
}

func (b *bench) start(a *app) {
	b.app = a
	b.reply("ready %s", b.dir)
	go func() {
		in := bufio.NewScanner(os.Stdin)
		for in.Scan() {
			fields := strings.Fields(in.Text())
			if len(fields) == 0 {
				continue
			}
			done := make(chan struct{})
			b.post(func() { b.command(fields, done) })
			<-done
		}
		b.post(func() {
			// The benchmark's rounds and settings never outlive the run.
			os.RemoveAll(b.dir)
			pPostQuitMessage.Call(0)
		})
	}()
}

func (b *bench) command(f []string, done chan struct{}) {
	a, p := b.app, b.app.panel
	reply := func(format string, args ...any) {
		b.reply(format, args...)
		close(done)
	}
	switch f[0] {
	case "show":
		a.show()
		reply("shown")
	case "hide":
		a.hide(true)
		reply("hidden")
	case "type":
		wpm, _ := strconv.ParseFloat(arg(f, 1, "80"), 64)
		target := a.session.Round.Target
		from := len(a.session.Round.Typed())
		n, _ := strconv.Atoi(arg(f, 2, strconv.Itoa(len(target)-from)))
		chars := target[from:min(len(target), from+n)]
		gap := time.Duration(float64(time.Minute) / (wpm * 5))
		go func() {
			// Real messages through the panel's queue: the same path as a key press after TranslateMessage.
			for _, r := range chars {
				pPostMessageW.Call(p.hwnd, wmChar, uintptr(r), 0)
				time.Sleep(gap)
			}
			time.Sleep(300 * time.Millisecond)
			b.post(func() {
				s := a.session
				wpm, acc := 0, 0
				if s.Result != nil {
					wpm, acc = int(s.Result.WPM), int(s.Result.Accuracy*100)
				}
				reply("typed chars=%d wpm=%d accuracy=%d finished=%v", len(chars), wpm, acc, s.Result != nil)
			})
		}()
	case "char":
		for _, r := range strings.Join(f[1:], " ") {
			pPostMessageW.Call(p.hwnd, wmChar, uintptr(r), 0)
		}
		b.post(func() { reply("typed") })
	case "key":
		vk, ctrl, shift := map[string]int{"tab": typer.VKTab, "shift+tab": typer.VKTab, "esc": typer.VKEscape, "enter": typer.VKReturn,
			"back": typer.VKBack, "down": typer.VKDown, "ctrl+f": 'F'}[arg(f, 1, "")], strings.HasPrefix(arg(f, 1, ""), "ctrl+"), strings.HasPrefix(arg(f, 1, ""), "shift+")
		a.session.Visible = p.visible()
		act := typer.PanelKey(vk, ctrl, shift, false, a.session.Picking)
		if act.Kind == typer.Pass && vk == typer.VKBack {
			p.char(0x08)
		} else {
			b.key(act)
		}
		p.render()
		reply("key")
	case "shot":
		p.render()
		path, _ := filepath.Abs(arg(f, 1, "shot.png"))
		if err := savePNG(p.frame.bmp, path); err != nil {
			reply("error %v", err)
			return
		}
		reply("shot %s", path)
	case "scale":
		n, _ := strconv.ParseFloat(arg(f, 1, "0"), 32)
		p.scaleOverride = float32(n)
		p.render()
		reply("scale %v", n)
	case "state":
		fg, _, _ := pGetForegroundWindow.Call()
		reply("visible=%v picking=%v result=%v foreground=%v hotkey=%v chars=%d lang=%s collection=%s pos=%d,%d scale=%v", p.visible(),
			a.session.Picking, a.session.Result != nil, fg == p.hwnd, a.hotKeyOK, len(a.session.Round.Target), a.session.Lang,
			a.session.Collection.ID, p.x, p.y, p.scale)
	case "where":
		for _, h := range p.hits {
			if h.id == arg(f, 1, "") {
				reply("at %d %d", p.x+int32((h.x+h.w/2)*p.scale), p.y+int32((h.y+h.h/2)*p.scale))
				return
			}
		}
		reply("none")
	case "import":
		a.importCollections()
		reply("imported collection=%s visible=%v", a.session.Collection.ID, p.visible())
	case "hotkey":
		a.changeHotKey()
		reply("hotkey %s ok=%v", a.hotKey.Label(), a.hotKeyOK)
	case "stats":
		var created, exited, kernel, user [8]byte
		self, _ := syscallCurrentProcess()
		kernel32.NewProc("GetProcessTimes").Call(self, uintptr(unsafe.Pointer(&created)), uintptr(unsafe.Pointer(&exited)),
			uintptr(unsafe.Pointer(&kernel)), uintptr(unsafe.Pointer(&user)))
		mem := memoryCounters{}
		mem.CB = uint32(unsafe.Sizeof(mem))
		pGetProcessMemoryInfo.Call(self, uintptr(unsafe.Pointer(&mem)), uintptr(mem.CB))
		cpu := (*(*uint64)(unsafe.Pointer(&kernel)) + *(*uint64)(unsafe.Pointer(&user))) / 10_000 // 100 ns units to ms
		reply("stats cpu_ms=%d ws_kb=%d peak_ws_kb=%d private_kb=%d", cpu, mem.WorkingSetSize/1024, mem.PeakWorkingSetSize/1024, mem.PrivateUsage/1024)
	default:
		reply("unknown")
	}
}

// key performs a panel action the way panel.key does.
func (b *bench) key(act typer.PanelAction) {
	a, s := b.app, b.app.session
	switch act.Kind {
	case typer.Hide:
		a.hide(true)
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
	case typer.Favorite:
		s.ToggleFavoritePicked()
	case typer.Move:
		s.MovePicker(act.Step)
	case typer.Delete:
		s.DeleteInPicker()
	}
}

func arg(f []string, i int, fallback string) string {
	if i < len(f) {
		return f[i]
	}
	return fallback
}

func syscallCurrentProcess() (uintptr, error) {
	h, _, _ := kernel32.NewProc("GetCurrentProcess").Call()
	return h, nil
}
