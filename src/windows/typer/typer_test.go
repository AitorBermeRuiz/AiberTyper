package typer

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
	"unicode/utf16"
)

// Ports of the Session, History, collection, key and shortcut checks in src/mac/Tests/main.swift. The pure functions are
// covered by the Swift vectors (vectors_test.go).

var t0 = time.Unix(1_800_000_000, 0)

func newSession(t *testing.T) *Session {
	dir := t.TempDir()
	return NewSession(NewHistory(filepath.Join(dir, "history.json")), filepath.Join(dir, "Colecciones"), LoadSettings(filepath.Join(dir, "settings.json")))
}

// practice starts a round whose text is exactly text: a one-quote collection always yields that quote.
func (s *Session) practice(text string) {
	s.Choose(Collection{ID: "test", Name: "Test", ES: []Quote{{Text: text}}, EN: []Quote{{Text: text}}})
}

func texts(qs []Quote) []string {
	out := make([]string, len(qs))
	for i, q := range qs {
		out[i] = q.Text
	}
	return out
}

func ids(cs []Collection) []string {
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.ID
	}
	return out
}

func TestPickQuotes(t *testing.T) {
	four := []Quote{{Text: "aaaa"}, {Text: "bbbb"}, {Text: "cccc"}}
	if got := strings.Join(texts(PickQuotes(four, 6, 1<<30)), " "); len(got) != 9 {
		t.Errorf("picked %q", got)
	}
	long := strings.Repeat("x", 20)
	for range 50 {
		capped := texts(PickQuotes(append(four, Quote{Text: long}), 12, 14))
		slices.Sort(capped)
		if !slices.Equal(capped, []string{"aaaa", "bbbb", "cccc"}) {
			t.Fatalf("capped %v", capped)
		}
	}
	if got := texts(PickQuotes([]Quote{{Text: long}}, 12, 14)); !slices.Equal(got, []string{long}) {
		t.Errorf("only long %v", got)
	}
}

func TestBuiltIn(t *testing.T) {
	if !slices.Equal(ids(BuiltIn), []string{"general", "stoic", "programming", "art-of-war", "cinema", "books"}) {
		t.Fatalf("built-in %v", ids(BuiltIn))
	}
	// Every built-in quote survives the Go parser, so both apps show the same texts.
	for _, c := range BuiltIn {
		for _, quotes := range [][]Quote{c.ES, c.EN} {
			data, _ := json.Marshal(map[string]any{"name": c.Name, "quotes": quotes})
			parsed, skipped, err := Parse(data, c.ID)
			if err != nil || skipped != 0 || !slices.EqualFunc(parsed.ES, quotes, Quote.Equal) {
				t.Errorf("%s: %v skipped %d", c.ID, err, skipped)
			}
		}
	}
}

func TestSessionSavesRounds(t *testing.T) {
	dir := t.TempDir()
	historyPath := filepath.Join(dir, "history.json")
	s := NewSession(NewHistory(historyPath), dir, LoadSettings(filepath.Join(dir, "settings.json")))
	s.practice("añ")
	s.Type("a", t0)
	s.Type("añ", t0.Add(time.Second))
	if s.Result == nil || s.Result.WPM != 24 || s.Result.Lang != s.Lang || s.IsRecord {
		t.Fatalf("result %+v record %v", s.Result, s.IsRecord)
	}
	if h := NewHistory(historyPath); len(h.Rounds) != 1 || h.Rounds[0].WPM != 24 {
		t.Fatalf("saved %+v", h.Rounds)
	}
	// A round is a record only when it beats every saved round (the first one was 24 wpm).
	finished := func(seconds float64) *Session {
		s := NewSession(NewHistory(historyPath), t.TempDir(), LoadSettings(filepath.Join(t.TempDir(), "s.json")))
		s.practice("ab")
		s.Type("a", t0)
		s.Type("ab", t0.Add(time.Duration(seconds*float64(time.Second))))
		return s
	}
	if !finished(0.5).IsRecord || finished(2).IsRecord {
		t.Error("record")
	}
	// The file keeps the Mac format: whole-second ISO 8601 dates and the same keys.
	data, _ := os.ReadFile(historyPath)
	if !strings.Contains(string(data), `"date": "2027-01-15T08:00:01Z"`) || !strings.Contains(string(data), `"lang": "es"`) {
		t.Errorf("format %s", data)
	}
}

func TestHistoryReadOnly(t *testing.T) {
	round := RoundResult{Date: t0, Lang: ES, WPM: 50, Accuracy: 1, Seconds: 40}
	// A history file corrupt at launch is read-only: Add fails (so the note shows) and the file stays as it is.
	dir := t.TempDir()
	corrupt := filepath.Join(dir, "history.json")
	os.WriteFile(corrupt, []byte("not json"), 0o644)
	h := NewHistory(corrupt)
	if err := h.Add(round); err == nil {
		t.Error("corrupt history accepted a round")
	}
	if data, _ := os.ReadFile(corrupt); string(data) != "not json" {
		t.Error("corrupt history overwritten")
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 1 {
		t.Errorf("extra files %v", entries)
	}
	// A history path that cannot be read (a folder) is read-only too.
	folder := t.TempDir()
	h = NewHistory(folder)
	if err := h.Add(round); err == nil || len(h.Rounds) != 1 {
		t.Error("unreadable history")
	}
	// A round missing a field makes the file unreadable, as in Swift.
	partial := filepath.Join(t.TempDir(), "history.json")
	os.WriteFile(partial, []byte(`[{"date": "2026-10-25T20:08:58Z", "lang": "es", "wpm": 50}]`), 0o644)
	if err := NewHistory(partial).Add(round); err == nil {
		t.Error("partial round accepted")
	}
	// "null" is not a list of rounds: read-only, as Swift's decoder refuses it, never overwritten as empty.
	null := filepath.Join(t.TempDir(), "history.json")
	os.WriteFile(null, []byte("null"), 0o644)
	if err := NewHistory(null).Add(round); err == nil {
		t.Error("null history accepted a round")
	}
	// A round with values the app never writes (1e300) is corrupt too: read-only and kept, as in Swift.
	huge := filepath.Join(t.TempDir(), "history.json")
	hugeJSON := `[{"date": "2026-10-25T20:08:58Z", "lang": "es", "wpm": 1e300, "accuracy": 1, "seconds": 30}]`
	os.WriteFile(huge, []byte(hugeJSON), 0o644)
	h = NewHistory(huge)
	if _, ok := h.RecentWPM(); ok || h.Add(round) == nil {
		t.Error("out-of-range history accepted")
	}
	if data, _ := os.ReadFile(huge); string(data) != hugeJSON {
		t.Error("out-of-range history overwritten")
	}
	// A file that turns corrupt while running is kept, not overwritten with the rounds in memory.
	later := filepath.Join(t.TempDir(), "history.json")
	h = NewHistory(later)
	h.Add(round)
	os.WriteFile(later, []byte("[ broken"), 0o644)
	if err := h.Add(round); err == nil {
		t.Error("later corrupt history accepted a round")
	}
	if data, _ := os.ReadFile(later); string(data) != "[ broken" {
		t.Error("later corrupt history overwritten")
	}
}

func TestHistoryShared(t *testing.T) {
	// Two app instances on one file keep each other's rounds.
	path := filepath.Join(t.TempDir(), "history.json")
	first, second := NewHistory(path), NewHistory(path)
	first.Add(RoundResult{Date: t0, Lang: ES, WPM: 30, Accuracy: 1, Seconds: 40})
	second.Add(RoundResult{Date: t0, Lang: EN, WPM: 40, Accuracy: 1, Seconds: 40})
	if n := len(NewHistory(path).Rounds); n != 2 {
		t.Errorf("shared %d", n)
	}
	// RecentWPM is the mean of the last 10 rounds.
	recent := NewHistory(filepath.Join(t.TempDir(), "history.json"))
	if _, ok := recent.RecentWPM(); ok {
		t.Error("recent WPM with no history")
	}
	recent.Add(RoundResult{Date: t0, Lang: ES, WPM: 0, Accuracy: 1, Seconds: 40})
	for range 10 {
		recent.Add(RoundResult{Date: t0, Lang: ES, WPM: 50, Accuracy: 1, Seconds: 40})
	}
	if w, _ := recent.RecentWPM(); w != 50 {
		t.Errorf("recent %v", w)
	}
	// A history written by the Mac app reads, fractional numbers and all.
	mac := filepath.Join(t.TempDir(), "history.json")
	os.WriteFile(mac, []byte(`[
  {
    "accuracy" : 0.98,
    "date" : "2026-10-25T20:08:58Z",
    "lang" : "en",
    "seconds" : 41.5,
    "wpm" : 70.25
  }
]`), 0o644)
	if r := NewHistory(mac).Rounds; len(r) != 1 || r[0].WPM != 70.25 || r[0].Lang != EN || !r[0].Date.Equal(time.Date(2026, 10, 25, 20, 8, 58, 0, time.UTC)) {
		t.Errorf("mac history %+v", r)
	}
}

func TestRecentWPMs(t *testing.T) {
	dir := t.TempDir()
	h := NewHistory(filepath.Join(dir, "history.json"))
	for i := range 25 {
		h.Add(RoundResult{Date: t0, Lang: ES, WPM: float64(i), Accuracy: 1, Seconds: 30})
	}
	s := NewSession(h, dir, LoadSettings(filepath.Join(dir, "settings.json")))
	s.practice("ab")
	s.Type("a", t0)
	s.Type("ab", t0.Add(6*time.Second))
	w := s.RecentWPMs()
	if len(w) != 20 || w[0] != 6 || w[19] != s.Result.WPM {
		t.Errorf("chart %v", w)
	}
}

func TestToggleLanguageAndRoundLength(t *testing.T) {
	s := newSession(t)
	before, number := s.Lang, s.RoundNumber
	s.Type("x", t0)
	s.ToggleLanguage()
	if s.Lang != before.Toggled() || s.RoundNumber != number+1 || len(s.Round.Typed()) != 0 {
		t.Error("toggle")
	}
	// A round never passes 90 seconds at the recent WPM.
	dir := t.TempDir()
	slowHistory := NewHistory(filepath.Join(dir, "history.json"))
	slowHistory.Add(RoundResult{Date: t0, Lang: ES, WPM: 20, Accuracy: 1, Seconds: 40})
	slow := NewSession(slowHistory, dir, LoadSettings(filepath.Join(dir, "settings.json")))
	for _, c := range BuiltIn {
		slow.Choose(c)
		for range 20 {
			slow.NewRound()
			if n := len(slow.Round.Target); n > CharsFor(20, 90) || n == 0 {
				t.Fatalf("round %s %d", c.ID, n)
			}
		}
	}
	// The language and collection are saved and restored.
	settings := filepath.Join(t.TempDir(), "settings.json")
	saved := NewSession(NewHistory(filepath.Join(dir, "h.json")), dir, LoadSettings(settings))
	saved.ToggleLanguage()
	saved.Choose(BuiltIn[2])
	again := NewSession(NewHistory(filepath.Join(dir, "h.json")), dir, LoadSettings(settings))
	if again.Lang != saved.Lang || again.Collection.ID != BuiltIn[2].ID {
		t.Errorf("restored %v %v", again.Lang, again.Collection.ID)
	}
}

func TestPicker(t *testing.T) {
	p := newSession(t)
	p.Choose(General)
	p.OpenPicker()
	if !p.Picking || p.Selection != 0 {
		t.Fatal("open")
	}
	p.MovePicker(-1)
	if p.Selection != 0 {
		t.Error("stops at the top")
	}
	for range len(BuiltIn) + 1 {
		p.MovePicker(1)
	}
	if p.Selection != len(BuiltIn)-1 {
		t.Error("stops at the bottom")
	}
	p.TypeInPicker("j")
	if p.Filter != "j" || p.Selection != 0 {
		t.Error("j types into the filter")
	}
	p.DeleteInPicker()
	p.TypeInPicker("E")
	p.TypeInPicker("s")
	p.TypeInPicker("t")
	if !slices.Equal(ids(p.Matches()), []string{"stoic"}) {
		t.Errorf("filter %v", ids(p.Matches()))
	}
	p.TypeInPicker("k")
	p.ChoosePicked()
	if p.Filter != "Estk" || len(p.Matches()) != 0 || !p.Picking || p.Collection.ID != "general" {
		t.Error("nothing to choose keeps the picker open")
	}
	p.DeleteInPicker()
	p.ChoosePicked()
	if p.Picking || p.Collection.ID != "stoic" {
		t.Error("chose stoic")
	}
	for _, q := range p.Round.Quotes {
		if q.Source == nil {
			t.Error("stoic quote without source")
		}
	}
	p.OpenPicker()
	if p.Selection != 1 {
		t.Error("opens on the current collection")
	}
	p.DeleteInPicker()
	p.TypeInPicker("\x08\n")
	if p.Selection != 1 || p.Filter != "" {
		t.Error("control and private-use characters are ignored")
	}
	p.TypeInPicker("node.js")
	if p.Filter != "node.js" {
		t.Error("the filter keeps punctuation")
	}
	for range 7 {
		p.DeleteInPicker()
	}
	p.TypeInPicker("GENERAL")
	if !slices.Equal(ids(p.Matches()), []string{"general"}) {
		t.Error("case-insensitive")
	}
	p.ClosePicker()
	if p.Picking || p.Collection.ID != "stoic" {
		t.Error("esc keeps the collection")
	}
	// Clicking a row chooses it and closes the picker.
	p.OpenPicker()
	second := p.Matches()[1]
	p.ChooseMatch(1)
	if p.Collection.ID != second.ID || p.Picking {
		t.Error("click")
	}
}

const valid = `{"name": " Programación ", "quotes": [{"text": " Talk is cheap. ", "source": "Linus Torvalds"}, {"text": "Sin fuente."}]}`

func TestLoadAndFavorites(t *testing.T) {
	folder := t.TempDir()
	os.WriteFile(filepath.Join(folder, "prog.json"), []byte(valid), 0o644)
	os.WriteFile(filepath.Join(folder, "bad.json"), []byte("not json"), 0o644)
	os.WriteFile(filepath.Join(folder, "empty.json"), []byte(`{"name": "Sin frases"}`), 0o644)
	os.WriteFile(filepath.Join(folder, "notes.txt"), []byte("ignored"), 0o644)
	loaded, problems := Load(folder)
	if !slices.Equal(ids(loaded), []string{"file:prog.json"}) || !slices.Equal(problems, []string{"bad.json: JSON no válido", "empty.json: JSON no válido"}) {
		t.Errorf("load %v %v", ids(loaded), problems)
	}
	odd := t.TempDir()
	os.WriteFile(filepath.Join(odd, "big.json"), make([]byte, MaxBytes+1), 0o644)
	os.Mkdir(filepath.Join(odd, "dir.json"), 0o755)
	if c, p := Load(odd); len(c) != 0 || !slices.Equal(p, []string{"big.json: más de 1 MB", "dir.json: no es un archivo normal"}) {
		t.Errorf("odd %v", p)
	}

	builtInIDs := ids(BuiltIn)
	settings := filepath.Join(t.TempDir(), "settings.json")
	user := NewSession(NewHistory(filepath.Join(t.TempDir(), "h.json")), folder, LoadSettings(settings))
	if !slices.Equal(ids(user.Collections), append(slices.Clone(builtInIDs), "file:prog.json")) || len(user.Problems) != 2 {
		t.Fatalf("collections %v", ids(user.Collections))
	}
	user.Choose(user.Collections[len(user.Collections)-1])
	if len(user.Round.Quotes) == 0 {
		t.Error("file quotes")
	}
	// Favorites come first; Ctrl+F keeps the same collection selected as it moves.
	user.OpenPicker()
	if user.Selection != len(builtInIDs) {
		t.Errorf("selection %d", user.Selection)
	}
	user.ToggleFavoritePicked()
	if ids(user.Matches())[0] != "file:prog.json" || user.Selection != 0 {
		t.Errorf("favorite first %v", ids(user.Matches()))
	}
	if again := NewSession(NewHistory(filepath.Join(t.TempDir(), "h.json")), folder, LoadSettings(settings)); !again.Favorites["file:prog.json"] {
		t.Error("favorites saved")
	}
	user.ToggleFavoritePicked()
	if !slices.Equal(ids(user.Matches()), append(slices.Clone(builtInIDs), "file:prog.json")) || user.Selection != len(builtInIDs) {
		t.Error("unfavorited")
	}
	user.ClosePicker()
	// A chosen file collection whose file is deleted falls back to General, in memory only.
	os.Remove(filepath.Join(folder, "prog.json"))
	user.ReloadCollections()
	if user.Collection.ID != "general" {
		t.Errorf("fallback %s", user.Collection.ID)
	}
	os.WriteFile(filepath.Join(folder, "prog.json"), []byte(valid), 0o644)
	user.ReloadCollections()
	relaunched := NewSession(NewHistory(filepath.Join(t.TempDir(), "h.json")), folder, LoadSettings(settings))
	if user.Collection.ID != "file:prog.json" || relaunched.Collection.ID != "file:prog.json" {
		t.Errorf("back %s %s", user.Collection.ID, relaunched.Collection.ID)
	}
}

func TestInstall(t *testing.T) {
	inbox, shelf := t.TempDir(), filepath.Join(t.TempDir(), "Colecciones")
	os.WriteFile(filepath.Join(inbox, "prog.json"), []byte(valid), 0o644)
	id, err := Install(filepath.Join(inbox, "prog.json"), shelf)
	if c, _ := Load(shelf); err != nil || id != "file:prog.json" || !slices.Equal(ids(c), []string{id}) {
		t.Fatalf("installed %v %v", id, err)
	}
	// A broken file is refused with the wording Load uses, and never lands in the folder.
	os.WriteFile(filepath.Join(inbox, "bad.json"), []byte("not json"), 0o644)
	if _, err := Install(filepath.Join(inbox, "bad.json"), shelf); err == nil || err.Error() != "JSON no válido" {
		t.Errorf("refused %v", err)
	}
	if _, err := os.Stat(filepath.Join(shelf, "bad.json")); err == nil {
		t.Error("bad file copied")
	}
	// Re-importing a file from the folder itself keeps it instead of trashing its own source.
	trashed := []string{}
	MoveToTrash = func(p string) error { trashed = append(trashed, p); return os.Remove(p) }
	defer func() { MoveToTrash = os.Remove }()
	if again, err := Install(filepath.Join(shelf, "prog.json"), shelf); err != nil || again != id || len(trashed) != 0 {
		t.Errorf("same file %v %v", err, trashed)
	}
	if data, _ := os.ReadFile(filepath.Join(shelf, "prog.json")); string(data) != valid {
		t.Error("same file changed")
	}
	// A different file with the same name goes to the trash.
	other := strings.Replace(valid, "Programación", "Otra", 1)
	os.WriteFile(filepath.Join(inbox, "prog.json"), []byte(other), 0o644)
	if _, err := Install(filepath.Join(inbox, "prog.json"), shelf); err != nil || len(trashed) != 1 {
		t.Errorf("replace %v %v", err, trashed)
	}
	// The documented example parses.
	data, _ := os.ReadFile(filepath.Join("..", "..", "..", "examples", "Programming.json"))
	if c, skipped, err := Parse(data, "file:Programming.json"); err != nil || skipped != 0 || len(c.ES) < 8 {
		t.Errorf("example %v", err)
	}
}

func TestPanelKey(t *testing.T) {
	key := func(vk int, ctrl, shift, alt, picking bool) PanelAction {
		return PanelKey(vk, ctrl, shift, alt, picking)
	}
	cases := []struct {
		got, want PanelAction
	}{
		{key(VKEscape, false, false, false, false), PanelAction{Kind: Hide}},
		{key(VKTab, false, false, false, false), PanelAction{Kind: ToggleLanguage}},
		{key(VKTab, false, true, false, false), PanelAction{Kind: OpenPicker}},
		{key(VKReturn, false, false, false, false), PanelAction{Kind: NewRoundKey}},
		{key('J', false, false, false, false), PanelAction{Kind: Pass}},
		{key(VKBack, false, false, false, false), PanelAction{Kind: Pass}},
		// Plain j/k filter in the picker; Ctrl+J/K and the arrows move.
		{key('J', false, false, false, true), PanelAction{Kind: Pass}},
		{key('J', true, false, false, true), PanelAction{Kind: Move, Step: 1}},
		{key('K', true, false, false, true), PanelAction{Kind: Move, Step: -1}},
		{key(VKDown, false, false, false, true), PanelAction{Kind: Move, Step: 1}},
		{key(VKUp, false, false, false, true), PanelAction{Kind: Move, Step: -1}},
		{key('F', true, false, false, true), PanelAction{Kind: Favorite}},
		{key('I', true, false, false, true), PanelAction{Kind: ImportCollections}},
		// AltGr (Ctrl+Alt) types into the filter instead.
		{key('F', true, false, true, true), PanelAction{Kind: Pass}},
		{key(VKEscape, false, false, false, true), PanelAction{Kind: ClosePicker}},
		{key(VKTab, false, true, false, true), PanelAction{Kind: ClosePicker}},
		{key(VKReturn, false, false, false, true), PanelAction{Kind: Choose}},
		{key(VKBack, false, false, false, true), PanelAction{Kind: Delete}},
	}
	for i, c := range cases {
		if c.got != c.want {
			t.Errorf("case %d: %+v, want %+v", i, c.got, c.want)
		}
	}
	// Keys that would move a caret are swallowed.
	for _, vk := range []int{VKLeft, VKRight, VKUp, VKDown, VKHome, VKEnd, VKPrior, VKNext, VKDelete} {
		if key(vk, false, false, false, false).Kind != Ignore {
			t.Errorf("swallowed %x", vk)
		}
	}
}

func TestHotKey(t *testing.T) {
	if h, ok := NewHotKey('T', ModAlt|ModShift, 't'); !ok || h != StandardHotKey || h.Label() != "Alt+Shift+T" {
		t.Errorf("standard %v", h)
	}
	refused := []struct {
		vk, mods uint32
		why      string
	}{
		{'T', 0, "no modifier"}, {'T', ModShift, "Shift only"}, {'C', ModControl, "Ctrl+letter"}, {'C', ModControl | ModShift, "Ctrl+Shift+letter"},
		{'5', ModControl, "Ctrl+number"}, {'E', ModAlt, "Alt+letter (menus)"}, {0xBB, ModAlt, "Alt+symbol"},
		{'Q', ModControl | ModAlt, "AltGr+Q types @"}, {'2', ModControl | ModAlt | ModShift, "AltGr+Shift"}, {0xBA, ModControl | ModAlt, "AltGr+symbol"},
		{VKShift, ModControl, "a modifier alone"},
		{VKTab, ModAlt, "Alt+Tab"}, {VKTab, ModAlt | ModShift, "Alt+Shift+Tab"}, {VKTab, ModControl, "Ctrl+Tab"},
		{VKEscape, ModAlt, "Alt+Esc"}, {VKEscape, ModControl | ModShift, "Ctrl+Shift+Esc"}, {VKF1 + 3, ModAlt, "Alt+F4"},
		{VKF1 + 3, ModControl, "Ctrl+F4"}, {VKSpace, ModAlt, "Alt+Space (window menu)"},
	}
	for _, r := range refused {
		if _, ok := NewHotKey(r.vk, r.mods, 0); ok {
			t.Errorf("%s accepted", r.why)
		}
	}
	allowed := []struct {
		vk, mods uint32
		char     rune
		label    string
	}{
		{VKSpace, ModControl | ModWin, ' ', "Win+Ctrl+Espacio"}, {VKLeft, ModAlt, 0, "Alt+←"}, {'T', ModWin | ModShift, 't', "Win+Shift+T"},
		{0x74, ModControl, 0, "Ctrl+F5"}, {0xBB, ModControl | ModShift, '+', "Ctrl+Shift++"}, {'T', ModControl | ModAlt | ModWin, 't', "Win+Ctrl+Alt+T"},
	}
	for _, a := range allowed {
		if h, ok := NewHotKey(a.vk, a.mods, a.char); !ok || h.Label() != a.label {
			t.Errorf("%s: %v %v", a.label, h.Label(), ok)
		}
	}
	// A saved shortcut the recorder would refuse falls back to the default.
	path := filepath.Join(t.TempDir(), "settings.json")
	s := LoadSettings(path)
	s.HotKey = &HotKey{VK: 'E', Mods: ModAlt, Key: "E"}
	s.Save()
	if LoadSettings(path).SavedHotKey() != StandardHotKey {
		t.Error("refused shortcut kept")
	}
	s.HotKey = &HotKey{VK: VKLeft, Mods: ModAlt, Key: "←"}
	s.Save()
	if LoadSettings(path).SavedHotKey() != *s.HotKey {
		t.Error("saved shortcut lost")
	}
	// A corrupt settings file means defaults.
	os.WriteFile(path, []byte("{"), 0o644)
	if LoadSettings(path).SavedHotKey() != StandardHotKey {
		t.Error("corrupt settings")
	}
}

// Notepad saves UTF-8 with a BOM and Windows PowerShell 5 saves UTF-16: Swift's JSONDecoder reads both, so must Parse.
func TestTextEncodings(t *testing.T) {
	utf16le := func(s string, bom []byte) []byte {
		out := slices.Clone(bom)
		for _, u := range utf16.Encode([]rune(s)) {
			out = append(out, byte(u), byte(u>>8))
		}
		return out
	}
	utf16be := func(s string) []byte {
		out := []byte{0xFE, 0xFF}
		for _, u := range utf16.Encode([]rune(s)) {
			out = append(out, byte(u>>8), byte(u))
		}
		return out
	}
	for name, data := range map[string][]byte{
		"utf-8 bom": append([]byte{0xEF, 0xBB, 0xBF}, valid...),
		"utf-16 le": utf16le(valid, []byte{0xFF, 0xFE}),
		"utf-16 be": utf16be(valid),
	} {
		if c, _, err := Parse(data, "file:x.json"); err != nil || c.Name != "Programación" {
			t.Errorf("%s: %v %q", name, err, c.Name)
		}
	}
	bom := filepath.Join(t.TempDir(), "history.json")
	os.WriteFile(bom, append([]byte{0xEF, 0xBB, 0xBF}, `[{"date": "2026-10-25T20:08:58Z", "lang": "es", "wpm": 50, "accuracy": 1, "seconds": 40}]`...), 0o644)
	if h := NewHistory(bom); len(h.Rounds) != 1 || h.Add(RoundResult{Date: t0, Lang: ES, WPM: 50, Accuracy: 1, Seconds: 40}) != nil {
		t.Error("history with a BOM")
	}
}

// Each setting is read on its own, like UserDefaults keys: one bad value never drops the others.
func TestSettingsPerKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	os.WriteFile(path, []byte(`{"lang": "fr", "pack": "stoic", "favorites": ["books"], "hotKey": 7, "hideImportHelp": true}`), 0o644)
	s := LoadSettings(path)
	if s.Lang != "" || s.CollectionID != "stoic" || !slices.Equal(s.Favorites, []string{"books"}) || s.HotKey != nil || !s.HideImportHelp {
		t.Errorf("settings %+v", s)
	}
	os.WriteFile(path, []byte("not json"), 0o644)
	if s := LoadSettings(path); s.CollectionID != "" {
		t.Errorf("corrupt settings %+v", s)
	}
}
