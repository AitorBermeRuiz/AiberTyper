//go:build windows

// Command bench launches AiberTyper.exe --bench and checks it end to end on a real Windows desktop: the global
// shortcut, keyboard focus, a typed round, the picker, mouse clicks, the shortcut recorder, importing a collection
// through the system dialogs and closing with Esc. It saves screenshots of each screen and
// prints a Markdown table of CPU and memory per phase, failing over budget (the same budgets as src/mac/bench.sh).
//
//	go run ./bench <AiberTyper.exe> <screenshots folder>
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

const (
	idleCPUBudget   = 1.0  // %
	typingCPUBudget = 20.0 // %
	ramBudgetMB     = 50.0
)

var (
	user32        = syscall.NewLazyDLL("user32.dll")
	pSendInput    = user32.NewProc("SendInput")
	pSetCursorPos = user32.NewProc("SetCursorPos")
	child         *exec.Cmd
)

type keyInput struct {
	Type  uint32
	_     uint32
	VK    uint16
	Scan  uint16
	Flags uint32
	Time  uint32
	_     uint32
	Extra uintptr
	_     [8]byte
}

// press sends real key events: modifiers down, the key, then everything up in reverse.
func press(vks ...uint16) {
	var in []keyInput
	for _, vk := range vks {
		in = append(in, keyInput{Type: 1, VK: vk})
	}
	for i := len(vks) - 1; i >= 0; i-- {
		in = append(in, keyInput{Type: 1, VK: vks[i], Flags: 2}) // KEYEVENTF_KEYUP
	}
	pSendInput.Call(uintptr(len(in)), uintptr(unsafe.Pointer(&in[0])), unsafe.Sizeof(in[0]))
	time.Sleep(700 * time.Millisecond)
}

// typeText sends text as Unicode key events, like typing into a file dialog.
func typeText(s string) {
	var in []keyInput
	for _, u := range utf16.Encode([]rune(s)) {
		in = append(in, keyInput{Type: 1, Scan: u, Flags: 4}, keyInput{Type: 1, Scan: u, Flags: 4 | 2}) // KEYEVENTF_UNICODE
	}
	pSendInput.Call(uintptr(len(in)), uintptr(unsafe.Pointer(&in[0])), unsafe.Sizeof(in[0]))
	time.Sleep(700 * time.Millisecond)
}

type mouseInput struct {
	Type   uint32
	_      uint32
	DX, DY int32
	Data   uint32
	Flags  uint32
	Time   uint32
	_      uint32
	Extra  uintptr
}

func mouseButton(flags uint32) {
	in := mouseInput{Flags: flags}
	pSendInput.Call(1, uintptr(unsafe.Pointer(&in)), unsafe.Sizeof(in))
	time.Sleep(100 * time.Millisecond)
}

// click moves the real pointer to x, y and presses the left button.
func click(x, y int) {
	pSetCursorPos.Call(uintptr(x), uintptr(y))
	time.Sleep(200 * time.Millisecond)
	mouseButton(2) // LEFTDOWN
	mouseButton(4) // LEFTUP
	time.Sleep(600 * time.Millisecond)
}

// drag holds the left button from x, y and moves the pointer by dx, dy in steps.
func drag(x, y, dx, dy int) {
	pSetCursorPos.Call(uintptr(x), uintptr(y))
	time.Sleep(200 * time.Millisecond)
	mouseButton(2)
	for i := 1; i <= 10; i++ {
		pSetCursorPos.Call(uintptr(x+dx*i/10), uintptr(y+dy*i/10))
		time.Sleep(50 * time.Millisecond)
	}
	mouseButton(4)
	time.Sleep(600 * time.Millisecond)
}

// field reads one value from an answer: "pos=10,20" gives "10,20".
func field(answer, name string) string {
	for _, f := range strings.Fields(answer) {
		if v, ok := strings.CutPrefix(f, name+"="); ok {
			return v
		}
	}
	return ""
}

type app struct {
	in    io.WriteCloser
	lines chan string
}

func (a *app) send(cmd string) string {
	a.write(cmd)
	return a.answer(cmd)
}

// write sends a command without waiting: the dialog commands answer only once the harness closes their dialogs.
func (a *app) write(cmd string) { fmt.Fprintln(a.in, cmd) }

func (a *app) answer(cmd string) string {
	select {
	case line, ok := <-a.lines:
		if !ok {
			fail("no answer to %q", cmd)
		}
		return line
	case <-time.After(60 * time.Second):
		fail("no answer to %q in 60 s (a dialog left open?)", cmd)
	}
	return ""
}

// clickOn clicks the middle of one of the panel's clickable areas.
func (a *app) clickOn(id string) bool {
	var x, y int
	if _, err := fmt.Sscanf(a.send("where "+id), "at %d %d", &x, &y); err != nil {
		return false
	}
	click(x, y)
	return true
}

// stats reads the numbers in the app's "stats" answer; the app resets its render counters on each read.
func (a *app) stats() map[string]float64 {
	m := map[string]float64{}
	for _, f := range strings.Fields(a.send("stats")) {
		if k, v, ok := strings.Cut(f, "="); ok {
			m[k], _ = strconv.ParseFloat(v, 64)
		}
	}
	return m
}

// stat reads one number from the app's "stats" answer.
func (a *app) stat(name string) float64 { return a.stats()[name] }

func fail(format string, args ...any) {
	fmt.Printf("FAIL: "+format+"\n", args...)
	if child != nil {
		child.Process.Kill()
	}
	os.Exit(1)
}

type row struct {
	phase  string
	cpu    float64
	limit  float64
	note   string
	render string // per-frame time, for the phases that draw
}

func main() {
	exe, shots := os.Args[1], os.Args[2]
	os.MkdirAll(shots, 0o755)
	cmd := exec.Command(exe, "--bench")
	in, _ := cmd.StdinPipe()
	outPipe, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		fail("start: %v", err)
	}
	child = cmd
	a := &app{in: in, lines: make(chan string)}
	go func() {
		out := bufio.NewScanner(outPipe)
		for out.Scan() {
			a.lines <- out.Text()
		}
		close(a.lines)
	}()
	ready := a.answer("launch")
	if !strings.HasPrefix(ready, "ready ") {
		fail("app did not start: %s", ready)
	}
	dir := strings.TrimPrefix(ready, "ready ")
	seedHistory(filepath.Join(dir, "history.json"))

	var rows []row
	failed := false
	check := func(ok bool, what string) {
		if !ok {
			failed = true
			fmt.Printf("FAIL: %s\n", what)
		}
	}
	measure := func(phase string, limit float64, during func()) {
		start, t0 := a.stat("cpu_ms"), time.Now()
		during()
		end := a.stats()
		cpu := (end["cpu_ms"] - start) / float64(time.Since(t0).Milliseconds()) * 100
		render := ""
		if n := end["render_n"]; n > 0 {
			render = fmt.Sprintf("%.1f ms avg, %.1f ms max, %.0f frames", end["render_avg_ms"], end["render_max_ms"], n)
		}
		rows = append(rows, row{phase: phase, cpu: cpu, limit: limit, render: render})
		check(cpu <= limit, fmt.Sprintf("%s CPU %.2f%% over %.0f%%", phase, cpu, limit))
	}
	idle := func(d time.Duration) func() { return func() { time.Sleep(d) } }

	time.Sleep(2 * time.Second) // launch settles
	measure("Idle, hidden", idleCPUBudget, idle(10*time.Second))

	press(0x12, 0x10, 'T') // Alt+Shift+T
	state := a.send("state")
	check(strings.Contains(state, "visible=true") && strings.Contains(state, "foreground=true"), "the shortcut shows and focuses the panel: "+state)
	if !strings.Contains(state, "visible=true") {
		a.send("show")
	}
	a.send("shot " + filepath.Join(shots, "typing-start.png"))
	measure("Idle, shown, not started", idleCPUBudget, idle(5*time.Second))

	measure("Typing at 80 wpm", typingCPUBudget, func() { a.send("type 80 140") })
	a.send("shot " + filepath.Join(shots, "typing.png"))
	measure("Shown, round started (stats tick)", idleCPUBudget*2, idle(15*time.Second)) // 15 s: CPU time comes in 15.6 ms ticks, too coarse over 5 s
	typed := a.send("type 80")
	check(strings.Contains(typed, "finished=true") && strings.Contains(typed, "accuracy=100"), "the round finishes at 100%: "+typed)
	// The record and the average compare with the rounds read before this one: a second, faster round shows them.
	press(0x0D) // Enter: new round
	a.send("type 400")
	a.send("shot " + filepath.Join(shots, "results.png"))
	a.send("scale 2")
	a.send("shot " + filepath.Join(shots, "results@2x.png"))
	a.send("key enter")
	a.send("type 80 60")
	a.send("shot " + filepath.Join(shots, "typing@2x.png"))
	a.send("scale 0")

	press(0x10, 0x09) // Shift+Tab: real keys reach the focused panel
	state = a.send("state")
	check(strings.Contains(state, "picking=true"), "Shift+Tab opens the picker: "+state)
	a.send("key down")
	a.send("key ctrl+f")
	a.send("shot " + filepath.Join(shots, "picker.png"))
	a.send("scale 2")
	a.send("shot " + filepath.Join(shots, "picker@2x.png"))
	a.send("scale 0")
	press(0x1B) // Esc closes the picker
	press(0x1B) // Esc hides
	state = a.send("state")
	check(strings.Contains(state, "visible=false"), "Esc twice hides the panel: "+state)
	beforeDialogs := a.stat("private_kb") / 1024

	// Mouse: the language pill that is not selected switches the language.
	a.send("show")
	other := "en"
	if strings.Contains(a.send("state"), "lang=en") {
		other = "es"
	}
	check(a.clickOn(other), "the "+other+" pill is clickable")
	state = a.send("state")
	check(strings.Contains(state, "lang="+other), "clicking the "+other+" pill switches the language: "+state)

	// Dragging the card's background moves the panel, and the next frame stays where it was dropped.
	var x, y int
	var scale float64
	fmt.Sscanf(field(state, "pos"), "%d,%d", &x, &y)
	fmt.Sscanf(field(state, "scale"), "%g", &scale)
	inset := int(40 * scale) // inside the card, past the shadow, clear of the buttons
	drag(x+inset, y+inset, 120, 80)
	a.send("scale 0") // redraws
	moved := field(a.send("state"), "pos")
	check(moved == fmt.Sprintf("%d,%d", x+120, y+80), fmt.Sprintf("dragging moves the panel from %d,%d by 120,80: %s", x, y, moved))
	a.send("hide")

	// Cambiar atajo…: the recorder takes Alt+Shift+Y, Enter saves it, and the new shortcut opens the panel.
	a.write("hotkey")
	time.Sleep(2 * time.Second)
	press(0x12, 0x10, 'Y')
	press(0x0D)
	recorded := a.answer("hotkey")
	check(strings.Contains(recorded, "hotkey Alt+Shift+Y ok=true"), "the recorder saves Alt+Shift+Y: "+recorded)
	press(0x12, 0x10, 'Y')
	state = a.send("state")
	check(strings.Contains(state, "visible=true"), "the new shortcut shows the panel: "+state)

	// Import: the format help (Enter accepts), then the file dialog takes a typed path; the panel shows the new collection.
	src, _ := os.MkdirTemp("", "aiber-import-")
	defer os.RemoveAll(src)
	file := filepath.Join(src, "Prueba.json")
	os.WriteFile(file, []byte(`{"name": "Prueba", "quotes": [{"text": "Una frase de prueba para importar."}]}`), 0o644)
	a.write("import")
	time.Sleep(2 * time.Second)
	press(0x0D)
	time.Sleep(time.Second)
	typeText(file)
	press(0x0D)
	imported := a.answer("import")
	check(strings.Contains(imported, "collection=file:Prueba.json visible=true"), "importing a file selects it: "+imported)
	a.send("hide")
	measure("Idle, hidden again", idleCPUBudget, idle(10*time.Second))

	peak, private := a.stat("peak_ws_kb")/1024, a.stat("private_kb")/1024
	check(private <= ramBudgetMB, fmt.Sprintf("private memory %.1f MB over %.0f MB", private, ramBudgetMB))

	in.Close()
	done := make(chan error)
	go func() { done <- cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		cmd.Process.Kill()
		check(false, "the app did not quit at end of input")
	}
	_, err := os.Stat(dir)
	check(os.IsNotExist(err), "the temporary folder is deleted")

	fmt.Println("| Phase | CPU | Budget | Render |")
	fmt.Println("|---|---:|---:|---|")
	for _, r := range rows {
		fmt.Printf("| %s | %.2f %% | ≤ %.0f %% | %s |\n", r.phase, r.cpu, r.limit, r.render)
	}
	fmt.Printf("| Memory: private, before any dialog | %.1f MB | | |\n", beforeDialogs)
	// The open-file dialog loads Explorer's shell into the process; that memory stays until quit.
	fmt.Printf("| Memory: private, after the import dialog | %.1f MB | ≤ %.0f MB | |\n", private, ramBudgetMB)
	fmt.Printf("| Memory: peak working set | %.1f MB | | |\n", peak)
	if failed {
		os.Exit(1)
	}
}

// seedHistory writes earlier rounds, so the results screen has a record and a chart.
func seedHistory(path string) {
	var rounds []map[string]any
	for i, wpm := range []float64{48, 52, 50, 55, 53, 58, 57, 60, 59, 62, 61, 64} {
		rounds = append(rounds, map[string]any{"date": time.Now().Add(time.Duration(i-20) * time.Hour).UTC().Format(time.RFC3339),
			"lang": "es", "wpm": wpm, "accuracy": 0.97, "seconds": 45})
	}
	data, _ := json.Marshal(rounds)
	os.WriteFile(path, data, 0o644)
}
