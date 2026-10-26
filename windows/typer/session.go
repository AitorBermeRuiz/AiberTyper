package typer

import (
	"encoding/json"
	"math/rand/v2"
	"os"
	"path/filepath"
	"slices"
	"time"
	"unicode"
)

// Settings is the Windows counterpart of the app's UserDefaults keys, saved as JSON next to history.json.
// A missing or unreadable file means defaults.
type Settings struct {
	path           string
	Lang           Lang     `json:"lang,omitempty"`
	Pack           string   `json:"pack,omitempty"`
	Favorites      []string `json:"favorites,omitempty"`
	HotKey         *HotKey  `json:"hotKey,omitempty"`
	HideImportHelp bool     `json:"hideImportHelp,omitempty"`
}

func LoadSettings(path string) *Settings {
	s := &Settings{}
	if data, err := os.ReadFile(path); err == nil && json.Unmarshal(data, s) != nil {
		s = &Settings{}
	}
	s.path = path
	return s
}

func (s *Settings) Save() error {
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	return writeAtomic(s.path, data)
}

// SavedHotKey is the saved shortcut, or the default when none is saved or the recorder would refuse it.
func (s *Settings) SavedHotKey() HotKey {
	if s.HotKey != nil && HotKeyAllowed(s.HotKey.Mods, s.HotKey.VK) {
		return *s.HotKey
	}
	return StandardHotKey
}

// Session is the app state: the current round, its saved result and record, the collection picker, favorites and history.
type Session struct {
	Lang       Lang
	Collection Collection
	// Collections are the built-in ones, then the ones in Folder; refreshed when the picker or the Colección menu
	// opens and after an import.
	Collections []Collection
	// Problems has one message per file in Folder that could not be used.
	Problems  []string
	Favorites map[string]bool
	Folder    string
	Round     Round
	Result    *RoundResult
	// AverageBefore is the recent WPM before the finished round; HasAverage is false on the first one.
	AverageBefore float64
	HasAverage    bool
	// IsRecord: the finished round beats every saved round (never true on the first one).
	IsRecord bool
	Note     string
	// RoundNumber counts rounds started.
	RoundNumber int
	// Visible: the panel is on screen; the live stats only tick while it is.
	Visible bool

	// Collection picker: a filterable list opened with Shift+Tab.
	Picking   bool
	Filter    string
	Selection int

	history  *History
	settings *Settings
}

func NewSession(history *History, folder string, settings *Settings) *Session {
	s := &Session{Collections: BuiltIn, Favorites: map[string]bool{}, Folder: folder, history: history, settings: settings, Lang: ES}
	for _, id := range settings.Favorites {
		s.Favorites[id] = true
	}
	if settings.Lang == EN {
		s.Lang = EN
	}
	s.Collection = General
	s.ReloadCollections() // switches to the saved collection when it loads
	if s.RoundNumber == 0 {
		s.NewRound()
	}
	return s
}

func (s *Session) save() { s.settings.Save() } // like UserDefaults, a failed write is not reported

func (s *Session) NewRound() {
	// First run has no history: assume an average typist (40 wpm).
	wpm, ok := s.history.RecentWPM()
	if !ok {
		wpm = 40
	}
	s.Round = NewRound(PickQuotes(s.Collection.Quotes(s.Lang), CharsFor(wpm, 30+rand.Float64()*30), CharsFor(wpm, 90)))
	s.Result = nil
	s.IsRecord = false
	s.Note = ""
	s.RoundNumber++
}

func (s *Session) ToggleLanguage() {
	s.Lang = s.Lang.Toggled()
	s.settings.Lang = s.Lang
	s.save()
	s.NewRound()
}

func (s *Session) Choose(c Collection) {
	s.Collection = c
	s.Picking = false
	s.settings.Pack = c.ID
	s.save()
	s.NewRound()
}

func (s *Session) find(id string) (Collection, bool) {
	for _, c := range s.Collections {
		if c.ID == id {
			return c, true
		}
	}
	return Collection{}, false
}

// ReloadCollections rereads Folder. A chosen collection whose file is gone falls back to General in memory only:
// the saved pack is kept and comes back once its file loads again.
func (s *Session) ReloadCollections() {
	loaded, problems := Load(s.Folder)
	s.Collections = append(slices.Clone(BuiltIn), loaded...)
	s.Problems = problems
	saved := s.settings.Pack
	if wanted, ok := s.find(saved); saved != s.Collection.ID && ok {
		s.Collection = wanted
		s.NewRound()
	} else if fresh, ok := s.find(s.Collection.ID); ok {
		s.Collection = fresh
	} else {
		s.Collection = General
		s.NewRound()
	}
}

// SortedCollections lists favorites first, each group in its original order.
func (s *Session) SortedCollections() []Collection {
	var favs, rest []Collection
	for _, c := range s.Collections {
		if s.Favorites[c.ID] {
			favs = append(favs, c)
		} else {
			rest = append(rest, c)
		}
	}
	return append(favs, rest...)
}

func (s *Session) Matches() []Collection {
	if s.Filter == "" {
		return s.SortedCollections()
	}
	var m []Collection
	for _, c := range s.SortedCollections() {
		if Contains(c.Name, s.Filter) {
			m = append(m, c)
		}
	}
	return m
}

func (s *Session) OpenPicker() {
	s.ReloadCollections()
	s.Filter = ""
	s.Selection = max(0, slices.IndexFunc(s.Matches(), func(c Collection) bool { return c.ID == s.Collection.ID }))
	s.Picking = true
}

// ToggleFavoritePicked stars or unstars the selected collection, keeping it selected as it moves.
func (s *Session) ToggleFavoritePicked() {
	matches := s.Matches()
	if s.Selection < 0 || s.Selection >= len(matches) {
		return
	}
	picked := matches[s.Selection]
	if s.Favorites[picked.ID] {
		delete(s.Favorites, picked.ID)
	} else {
		s.Favorites[picked.ID] = true
	}
	s.settings.Favorites = nil
	for id := range s.Favorites {
		s.settings.Favorites = append(s.settings.Favorites, id)
	}
	slices.Sort(s.settings.Favorites)
	s.save()
	s.Selection = max(0, slices.IndexFunc(s.Matches(), func(c Collection) bool { return c.ID == picked.ID }))
}

func (s *Session) ClosePicker() { s.Picking = false }

func (s *Session) MovePicker(step int) {
	s.Selection = max(0, min(s.Selection+step, len(s.Matches())-1))
}

// TypeInPicker adds printable characters to the filter; newlines, control and private-use characters are dropped.
func (s *Session) TypeInPicker(chars string) {
	printable := []rune{}
	for _, r := range chars {
		if !unicode.Is(unicode.Cc, r) && !unicode.Is(unicode.Co, r) && r != ' ' && r != ' ' {
			printable = append(printable, r)
		}
	}
	if len(printable) == 0 {
		return
	}
	s.Filter += string(printable)
	s.Selection = 0
}

func (s *Session) DeleteInPicker() {
	if s.Filter == "" {
		return
	}
	r := []rune(s.Filter)
	s.Filter = string(r[:len(r)-1])
	s.Selection = 0
}

func (s *Session) ChoosePicked() { s.ChooseMatch(s.Selection) }

// ChooseMatch chooses the row at index, as a mouse click on it does.
func (s *Session) ChooseMatch(index int) {
	matches := s.Matches()
	if index < 0 || index >= len(matches) {
		return
	}
	s.Choose(matches[index])
}

// Type types into the round and, on the keystroke that completes it, saves the result to the history.
func (s *Session) Type(text string, now time.Time) {
	score, done := s.Round.Type(text, now)
	if !done {
		return
	}
	result := RoundResult{Date: now, Lang: s.Lang, WPM: score.WPM, Accuracy: score.Accuracy, Seconds: score.Seconds}
	s.AverageBefore, s.HasAverage = s.history.RecentWPM()
	s.IsRecord = len(s.history.Rounds) > 0
	for _, r := range s.history.Rounds {
		if r.WPM >= score.WPM {
			s.IsRecord = false
		}
	}
	if err := s.history.Add(result); err != nil {
		s.Note = "No se pudo guardar el historial: " + err.Error()
	}
	s.Result = &result
}

// RecentWPMs are the WPM of the last 20 saved rounds, oldest first; after a round it ends with that round.
func (s *Session) RecentWPMs() []float64 {
	rounds := s.history.Rounds[max(0, len(s.history.Rounds)-20):]
	w := make([]float64, len(rounds))
	for i, r := range rounds {
		w[i] = r.WPM
	}
	return w
}
