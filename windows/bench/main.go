//go:build windows

// Command bench launches AiberTyper.exe --bench and checks it end to end on a real Windows desktop: the global
// shortcut, keyboard focus, a typed round, the picker and closing with Esc. It saves screenshots of each screen and
// prints a Markdown table of CPU and memory per phase, failing over budget (the same budgets as scripts/bench.sh).
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
	"unsafe"
)

const (
	idleCPUBudget   = 1.0  // %
	typingCPUBudget = 20.0 // %
	ramBudgetMB     = 50.0
)

var (
	user32     = syscall.NewLazyDLL("user32.dll")
	pSendInput = user32.NewProc("SendInput")
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

type app struct {
	in  io.WriteCloser
	out *bufio.Scanner
}

func (a *app) send(cmd string) string {
	fmt.Fprintln(a.in, cmd)
	if !a.out.Scan() {
		fail("no answer to %q", cmd)
	}
	return a.out.Text()
}

// stat reads one number from the app's "stats" answer.
func (a *app) stat(name string) float64 {
	for _, f := range strings.Fields(a.send("stats")) {
		if v, ok := strings.CutPrefix(f, name+"="); ok {
			n, _ := strconv.ParseFloat(v, 64)
			return n
		}
	}
	return 0
}

func fail(format string, args ...any) {
	fmt.Printf("FAIL: "+format+"\n", args...)
	os.Exit(1)
}

type row struct {
	phase string
	cpu   float64
	limit float64
	note  string
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
	a := &app{in: in, out: bufio.NewScanner(outPipe)}
	if !a.out.Scan() || !strings.HasPrefix(a.out.Text(), "ready ") {
		fail("app did not start")
	}
	dir := strings.TrimPrefix(a.out.Text(), "ready ")
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
		cpu := (a.stat("cpu_ms") - start) / float64(time.Since(t0).Milliseconds()) * 100
		rows = append(rows, row{phase: phase, cpu: cpu, limit: limit})
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
	measure("Shown, round started (stats tick)", idleCPUBudget*2, idle(5*time.Second))
	typed := a.send("type 80")
	check(strings.Contains(typed, "finished=true") && strings.Contains(typed, "accuracy=100"), "the round finishes at 100%: "+typed)
	a.send("shot " + filepath.Join(shots, "results.png"))

	press(0x10, 0x09) // Shift+Tab: real keys reach the focused panel
	state = a.send("state")
	check(strings.Contains(state, "picking=true"), "Shift+Tab opens the picker: "+state)
	a.send("key down")
	a.send("key ctrl+f")
	a.send("shot " + filepath.Join(shots, "picker.png"))
	press(0x1B) // Esc closes the picker
	press(0x1B) // Esc hides
	state = a.send("state")
	check(strings.Contains(state, "visible=false"), "Esc twice hides the panel: "+state)
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

	fmt.Println("| Phase | CPU | Budget |")
	fmt.Println("|---|---:|---:|")
	for _, r := range rows {
		fmt.Printf("| %s | %.2f %% | ≤ %.0f %% |\n", r.phase, r.cpu, r.limit)
	}
	fmt.Printf("| Memory: private (commit) | %.1f MB | ≤ %.0f MB |\n", private, ramBudgetMB)
	fmt.Printf("| Memory: peak working set | %.1f MB | |\n", peak)
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
