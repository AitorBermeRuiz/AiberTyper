// Package typer is the Windows port of the Mac logic: Typing.swift, Round.swift, Session.swift, Keys.swift and the
// rules in HotKey.swift. Keep it in step with the Swift files of the same name; the vectors in windows/shared,
// generated from Swift, check that it does.
package typer

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf16"

	"aibertyper/shared"
)

type Lang string

const (
	ES Lang = "es"
	EN Lang = "en"
)

func (l Lang) Toggled() Lang {
	if l == ES {
		return EN
	}
	return ES
}

func (l Lang) Label() string {
	if l == ES {
		return "Español"
	}
	return "English"
}

func (l *Lang) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil || (s != "es" && s != "en") {
		return fmt.Errorf("lang %s", b)
	}
	*l = Lang(s)
	return nil
}

// Quote is a quote to type: one or more sentences typed in a single go; Source names the work it is quoted from.
type Quote struct {
	Text   string  `json:"text"`
	Source *string `json:"source,omitempty"`
}

func (q Quote) Equal(o Quote) bool {
	return q.Text == o.Text && (q.Source == nil) == (o.Source == nil) && (q.Source == nil || *q.Source == *o.Source)
}

// Collection is a set of quotes to practice with: built in, or loaded from a JSON file in the collections folder.
type Collection struct {
	ID   string  `json:"id"`
	Name string  `json:"name"`
	ES   []Quote `json:"es"`
	EN   []Quote `json:"en"`
}

func (c Collection) Quotes(lang Lang) []Quote {
	if lang == ES {
		return c.ES
	}
	return c.EN
}

// BuiltIn are the collections that ship with the app, generated from the Swift Texts files.
var BuiltIn = func() []Collection {
	var c []Collection
	if err := json.Unmarshal(shared.Collections, &c); err != nil {
		panic(err)
	}
	return c
}()

// General is the default collection, and the fallback when the chosen one is gone.
var General = BuiltIn[0]

var wide, whitespace = func() ([][2]rune, [][2]rune) {
	var t struct{ Wide, Whitespace [][2]rune }
	if err := json.Unmarshal(shared.Unicode, &t); err != nil {
		panic(err)
	}
	return t.Wide, t.Whitespace
}()

func inRanges(r rune, ranges [][2]rune) bool {
	i := sort.Search(len(ranges), func(i int) bool { return ranges[i][1] >= r })
	return i < len(ranges) && ranges[i][0] <= r
}

// IsWide: emoji and CJK, kana, Hangul or fullwidth characters take two monospaced cells and break the manual wrap.
func IsWide(r rune) bool { return inRanges(r, wide) }

// Normalize composes text (NFC) so one typed letter is one rune. The app sets it to the Windows API; tests keep text as is.
var Normalize = func(s string) string { return s }

const (
	MaxBytes = 1_000_000
)

// MaxChars is the longest quote kept from a file: 90 seconds at 40 wpm.
var MaxChars = CharsFor(40, 90)

type CollectionError string

func (e CollectionError) Error() string { return string(e) }

// jsonString decodes raw as a JSON string; null, numbers and the rest are refused, as Swift's Decodable does.
func jsonString(raw json.RawMessage) (string, bool) {
	var s string
	if len(raw) == 0 || raw[0] != '"' || json.Unmarshal(raw, &s) != nil {
		return "", false
	}
	return s, true
}

// unicodeText drops a byte order mark and turns UTF-16 into UTF-8, as JSONDecoder reads both: Notepad saves
// UTF-8 with a BOM and Windows PowerShell 5 saves UTF-16.
func unicodeText(data []byte) []byte {
	big := false
	switch {
	case bytes.HasPrefix(data, []byte{0xEF, 0xBB, 0xBF}):
		return data[3:]
	case bytes.HasPrefix(data, []byte{0xFE, 0xFF}):
		big = true
	case !bytes.HasPrefix(data, []byte{0xFF, 0xFE}):
		return data
	}
	units := make([]uint16, (len(data)-2)/2)
	for i := range units {
		lo, hi := data[2+2*i], data[3+2*i]
		if big {
			lo, hi = hi, lo
		}
		units[i] = uint16(lo) | uint16(hi)<<8
	}
	return []byte(string(utf16.Decode(units)))
}

// Parse reads the JSON format users write: {"name": "…", "quotes": [{"text": "…", "source": "…"}]}. Keys are
// matched exactly, like Swift. The quotes are used whatever language is selected. Returns how many were skipped.
func Parse(data []byte, id string) (Collection, int, error) {
	if len(data) > MaxBytes {
		return Collection{}, 0, CollectionError("más de 1 MB")
	}
	invalid := CollectionError("JSON no válido")
	var file map[string]json.RawMessage
	if json.Unmarshal(unicodeText(data), &file) != nil || file == nil {
		return Collection{}, 0, invalid
	}
	name, ok := jsonString(file["name"])
	var raws []map[string]json.RawMessage
	if !ok || len(file["quotes"]) == 0 || file["quotes"][0] != '[' || json.Unmarshal(file["quotes"], &raws) != nil {
		return Collection{}, 0, invalid
	}
	var quotes []Quote
	for _, raw := range raws {
		text, ok := jsonString(raw["text"])
		if raw == nil || !ok {
			return Collection{}, 0, invalid
		}
		q := Quote{Text: strings.Join(strings.FieldsFunc(Normalize(text), isWhitespace), " ")}
		if s, ok := raw["source"]; ok && string(s) != "null" {
			source, ok := jsonString(s)
			if !ok {
				return Collection{}, 0, invalid
			}
			q.Source = &source
		}
		if q.Text != "" && len([]rune(q.Text)) <= MaxChars && !strings.ContainsFunc(q.Text, IsWide) {
			quotes = append(quotes, q)
		}
	}
	name = strings.TrimFunc(name, isWhitespace)
	if name == "" {
		return Collection{}, 0, CollectionError(`falta "name"`)
	}
	if len(quotes) == 0 {
		return Collection{}, 0, CollectionError(fmt.Sprintf("no tiene frases de hasta %d caracteres", MaxChars))
	}
	return Collection{ID: id, Name: name, ES: quotes, EN: quotes}, len(raws) - len(quotes), nil
}

func isWhitespace(r rune) bool { return inRanges(r, whitespace) }

// Load reads every *.json in folder, by file name, plus one message per file that could not be used.
func Load(folder string) ([]Collection, []string) {
	entries, _ := os.ReadDir(folder)
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	var collections []Collection
	var problems []string
	for _, e := range entries {
		name := e.Name()
		if strings.ToLower(filepath.Ext(name)) != ".json" {
			continue
		}
		info, err := os.Stat(filepath.Join(folder, name))
		if err != nil || !info.Mode().IsRegular() {
			problems = append(problems, name+": no es un archivo normal")
			continue
		}
		if info.Size() > MaxBytes {
			problems = append(problems, name+": más de 1 MB")
			continue
		}
		data, err := os.ReadFile(filepath.Join(folder, name))
		if err != nil {
			problems = append(problems, name+": "+err.Error())
			continue
		}
		c, skipped, err := Parse(data, fileID(name))
		if err != nil {
			problems = append(problems, name+": "+err.Error())
			continue
		}
		collections = append(collections, c)
		if skipped > 0 {
			problems = append(problems, fmt.Sprintf("%s: %d frases vacías, con caracteres anchos o de más de %d caracteres", name, skipped, MaxChars))
		}
	}
	return collections, problems
}

// MoveToTrash removes a replaced collection file. The app sends it to the Recycle Bin instead.
var MoveToTrash = os.Remove

// Install validates the file at src and copies it into folder, so a broken file never lands there.
// A different file with the same name is moved to the trash. Returns the id the copy loads under.
func Install(src, folder string) (string, error) {
	// The validated bytes are the ones written, so the file cannot change in between.
	data, err := os.ReadFile(src)
	if err != nil {
		return "", err
	}
	id := fileID(filepath.Base(src))
	if _, _, err := Parse(data, id); err != nil {
		return "", err
	}
	if err := os.MkdirAll(folder, 0o755); err != nil {
		return "", err
	}
	dest := filepath.Join(folder, filepath.Base(src))
	srcInfo, _ := os.Stat(src)
	// Re-importing a file from the folder itself must not trash its own source.
	if destInfo, err := os.Stat(dest); err == nil && !os.SameFile(srcInfo, destInfo) {
		if err := MoveToTrash(dest); err != nil {
			return "", err
		}
	}
	return id, writeAtomic(dest, data)
}

func fileID(name string) string { return "file:" + name }

func writeAtomic(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	_, err = tmp.Write(data)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Rename(tmp.Name(), path)
	}
	if err != nil {
		os.Remove(tmp.Name())
	}
	return err
}

// RoundResult is one finished round in history.json. The format matches the Mac app's, so the file can move between them.
type RoundResult struct {
	Date     time.Time
	Lang     Lang
	WPM      float64
	Accuracy float64
	Seconds  float64
}

type roundJSON struct {
	Date     *string  `json:"date"`
	Lang     *Lang    `json:"lang"`
	WPM      *float64 `json:"wpm"`
	Accuracy *float64 `json:"accuracy"`
	Seconds  *float64 `json:"seconds"`
}

func (r RoundResult) MarshalJSON() ([]byte, error) {
	// Swift's .iso8601 strategy reads whole seconds only.
	date := r.Date.UTC().Format("2006-01-02T15:04:05Z")
	return json.Marshal(roundJSON{&date, &r.Lang, &r.WPM, &r.Accuracy, &r.Seconds})
}

// UnmarshalJSON needs every field, like Swift's Decodable: a round missing one makes the file unreadable.
func (r *RoundResult) UnmarshalJSON(b []byte) error {
	var j roundJSON
	if err := json.Unmarshal(b, &j); err != nil {
		return err
	}
	if j.Date == nil || j.Lang == nil || j.WPM == nil || j.Accuracy == nil || j.Seconds == nil {
		return errors.New("round with a missing field")
	}
	date, err := time.Parse(time.RFC3339, *j.Date)
	if err != nil {
		return err
	}
	*r = RoundResult{date, *j.Lang, *j.WPM, *j.Accuracy, *j.Seconds}
	return nil
}

// CharsFor is the number of characters a typist at wpm covers in seconds (a "word" is 5 characters).
func CharsFor(wpm, seconds float64) int { return int(wpm * 5 * seconds / 60) }

func runeCount(s string) int { return len([]rune(s)) }

// PickQuotes returns whole shuffled quotes whose space-joined text reaches chars characters without passing
// maxChars. Quotes that fit come first; an oversize one is taken only when none fits, so the round is never empty.
func PickQuotes(quotes []Quote, chars, maxChars int) []Quote {
	shuffled := append([]Quote(nil), quotes...)
	rand.Shuffle(len(shuffled), func(i, j int) { shuffled[i], shuffled[j] = shuffled[j], shuffled[i] })
	var fit, over []Quote
	for _, q := range shuffled {
		if runeCount(q.Text) <= maxChars {
			fit = append(fit, q)
		} else {
			over = append(over, q)
		}
	}
	var picked []Quote
	length := -1 // no separator before the first quote
	for _, next := range append(fit, over...) {
		if length >= chars {
			break
		}
		n := runeCount(next.Text)
		if len(picked) > 0 && length+1+n > maxChars {
			continue
		}
		picked = append(picked, next)
		length += 1 + n
	}
	return picked
}

// Span is a half-open range of rune indices, like Swift's Range<Int>.
type Span struct{ Lo, Hi int }

// WrapLines word-wraps text into lines of at most width characters. Each line keeps its trailing space,
// so the spans are contiguous and cover the whole text.
func WrapLines(text []rune, width int) []Span {
	var lines []Span
	start := 0
	for start < len(text) {
		if len(text)-start <= width {
			lines = append(lines, Span{start, len(text)})
			break
		}
		// A space right after width characters may hang at the end of the line.
		end := start + width
		for i := start + width; i >= start; i-- {
			if text[i] == ' ' {
				if i > start {
					end = i + 1
				}
				break
			}
		}
		lines = append(lines, Span{start, end})
		start = end
	}
	return lines
}

// Mark is how a character of the round is drawn.
type Mark int

const (
	Correct Mark = iota
	Wrong
	Cursor
	Pending
)

func (m Mark) String() string { return [...]string{"correct", "wrong", "cursor", "pending"}[m] }

type Run struct {
	Span Span
	Mark Mark
}

// MarkRuns splits span of target into runs of characters drawn alike, so a line is a few strings, not one per character.
func MarkRuns(target, typed []rune, span Span) []Run {
	var runs []Run
	for i := span.Lo; i < span.Hi; i++ {
		mark := Pending
		switch {
		case i < len(typed) && typed[i] == target[i]:
			mark = Correct
		case i < len(typed):
			mark = Wrong
		case i == len(typed):
			mark = Cursor
		}
		if n := len(runs); n > 0 && runs[n-1].Mark == mark {
			runs[n-1].Span.Hi = i + 1
		} else {
			runs = append(runs, Run{Span{i, i + 1}, mark})
		}
	}
	return runs
}

// Window lists the line indices to draw around the cursor: up to Focus sharp lines, plus one dimmed before and
// after (-1 when there is none).
type Window struct {
	Before int
	Focus  Span
	After  int
}

func LineWindow(lines []Span, cursor, focus int) Window {
	if len(lines) == 0 {
		return Window{-1, Span{}, -1}
	}
	current := 0
	for i := len(lines) - 1; i >= 0; i-- {
		if lines[i].Lo <= cursor {
			current = i
			break
		}
	}
	// Keep the line before the cursor in focus once you are past the first one.
	first := max(0, min(current-1, len(lines)-focus))
	end := min(first+focus, len(lines))
	w := Window{-1, Span{first, end}, -1}
	if first > 0 {
		w.Before = first - 1
	}
	if end < len(lines) {
		w.After = end
	}
	return w
}

// History is the saved rounds in history.json. Only a missing file means empty history: any other read or decode
// error makes it read-only, so the file is kept as is.
type History struct {
	Path     string
	Rounds   []RoundResult
	writable bool
}

func NewHistory(path string) *History {
	h := &History{Path: path, writable: true}
	h.read()
	return h
}

func (h *History) read() {
	data, err := os.ReadFile(h.Path)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	var rounds []RoundResult
	if err == nil {
		err = json.Unmarshal(unicodeText(data), &rounds)
	}
	if err == nil && rounds == nil {
		err = errors.New("history.json: null is not a list of rounds") // Swift refuses it too
	}
	if err != nil {
		h.writable = false
		return
	}
	h.Rounds = rounds
}

// RecentWPM is the mean of the last 10 rounds; false with no history.
func (h *History) RecentWPM() (float64, bool) {
	recent := h.Rounds[max(0, len(h.Rounds)-10):]
	if len(recent) == 0 {
		return 0, false
	}
	sum := 0.0
	for _, r := range recent {
		sum += r.WPM
	}
	return sum / float64(len(recent)), true
}

func (h *History) Add(round RoundResult) error {
	// Another running instance may have saved rounds since this one read the file.
	// A file that turned unreadable since then is kept: the history becomes read-only.
	if h.writable {
		h.read()
	}
	h.Rounds = append(h.Rounds, round)
	if !h.writable {
		return CollectionError(fmt.Sprintf("no se pudo leer %s, así que no se sobrescribe", filepath.Base(h.Path)))
	}
	if err := os.MkdirAll(filepath.Dir(h.Path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(h.Rounds, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(h.Path, data)
}

// Contains is Swift's localizedStandardContains for collection names: case and accent insensitive.
func Contains(hay, needle string) bool { return strings.Contains(fold(hay), fold(needle)) }

// shortcut: folds Latin letters only (Latin-1 and Latin Extended-A); use the Windows NLS API if other scripts show up.
var foldFrom, foldTo = []rune("àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżž"),
	[]rune("aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzz")

var foldMap = func() map[rune]rune {
	if len(foldFrom) != len(foldTo) {
		panic("fold tables differ in length")
	}
	m := map[rune]rune{}
	for i, r := range foldFrom {
		m[r] = foldTo[i]
	}
	return m
}()

func fold(s string) string {
	var b strings.Builder
	for _, r := range s {
		r = unicode.ToLower(r)
		switch {
		case r == 'ß':
			b.WriteString("ss")
		case unicode.Is(unicode.Mn, r): // combining accents, as in NFD text
		case foldMap[r] != 0:
			b.WriteRune(foldMap[r])
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
