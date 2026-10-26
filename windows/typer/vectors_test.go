package typer

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// The vectors are what the Swift code returns for each input (scripts/export-shared.sh). A failure here means the
// Go port no longer behaves like the Mac app.
type pair struct{ Lower, Upper int }

func (p pair) span() Span { return Span{p.Lower, p.Upper} }

type score struct {
	WPM      float64  `json:"wpm"`
	Accuracy float64  `json:"accuracy"`
	Seconds  *float64 `json:"seconds"`
}

type vectors struct {
	MaxChars int
	CharsFor []struct {
		WPM, Seconds float64
		Out          int
	}
	WrapLines []struct {
		Text  string
		Width int
		Out   []pair
	}
	LineWindow []struct {
		Lines         []pair
		Cursor        int
		Before, After *int
		Focus         pair
	}
	MarkRuns []struct {
		Target, Typed string
		Range         pair
		Out           []struct {
			Range pair
			Mark  string
		}
	}
	Rounds []struct {
		Name   string
		Quotes []Quote
		Steps  []struct {
			Text            string
			T               float64
			Result, Live    *score
			Typed           string
			Errors, Correct int
			Source          *string
		}
	}
	Parse []struct {
		JSON    string
		Name    *string
		Quotes  []Quote
		Skipped *int
		Error   *string
	}
	Contains []struct {
		Hay, Needle string
		Out         bool
	}
}

func loadVectors(t *testing.T) vectors {
	data, err := os.ReadFile(filepath.Join("..", "shared", "vectors.json"))
	if err != nil {
		t.Fatal(err)
	}
	var v vectors
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func orNone(p *int) int {
	if p == nil {
		return -1
	}
	return *p
}

// Swift's Date keeps seconds since 2001 in a Double, so times off t0 carry about 1e-7 of rounding.
func near(a, b float64) bool { return math.Abs(a-b) <= 1e-6*max(1, math.Abs(b)) }

func TestVectors(t *testing.T) {
	v := loadVectors(t)
	if v.MaxChars != MaxChars {
		t.Errorf("MaxChars %d, Swift %d", MaxChars, v.MaxChars)
	}
	for _, c := range v.CharsFor {
		if got := CharsFor(c.WPM, c.Seconds); got != c.Out {
			t.Errorf("CharsFor(%v, %v) = %d, Swift %d", c.WPM, c.Seconds, got, c.Out)
		}
	}
	for _, c := range v.WrapLines {
		got := WrapLines([]rune(c.Text), c.Width)
		if len(got) != len(c.Out) {
			t.Errorf("WrapLines(%q, %d) = %v, Swift %v", c.Text, c.Width, got, c.Out)
			continue
		}
		for i := range got {
			if got[i] != c.Out[i].span() {
				t.Errorf("WrapLines(%q, %d) line %d = %v, Swift %v", c.Text, c.Width, i, got[i], c.Out[i])
			}
		}
	}
	for _, c := range v.LineWindow {
		lines := make([]Span, len(c.Lines))
		for i, l := range c.Lines {
			lines[i] = l.span()
		}
		want := Window{orNone(c.Before), c.Focus.span(), orNone(c.After)}
		if got := LineWindow(lines, c.Cursor, 3); got != want {
			t.Errorf("LineWindow(%v, %d) = %v, Swift %v", lines, c.Cursor, got, want)
		}
	}
	for _, c := range v.MarkRuns {
		got := MarkRuns([]rune(c.Target), []rune(c.Typed), c.Range.span())
		ok := len(got) == len(c.Out)
		for i := 0; ok && i < len(got); i++ {
			ok = got[i].Span == c.Out[i].Range.span() && got[i].Mark.String() == c.Out[i].Mark
		}
		if !ok {
			t.Errorf("MarkRuns(%q, %q, %v) = %v, Swift %v", c.Target, c.Typed, c.Range, got, c.Out)
		}
	}
	t0 := time.Unix(1_800_000_000, 0)
	for _, c := range v.Rounds {
		r := NewRound(c.Quotes)
		for i, step := range c.Steps {
			now := t0.Add(time.Duration(step.T * float64(time.Second)))
			result, done := r.Type(step.Text, now)
			live, started := r.Live(now)
			source, hasSource := r.Source()
			bad := string(r.Typed()) != step.Typed || r.Errors != step.Errors || r.Correct() != step.Correct ||
				done != (step.Result != nil) || started != (step.Live != nil) || hasSource != (step.Source != nil) ||
				hasSource && source != *step.Source
			if step.Result != nil && done {
				bad = bad || !near(result.WPM, step.Result.WPM) || !near(result.Accuracy, step.Result.Accuracy) ||
					!near(result.Seconds, *step.Result.Seconds)
			}
			if step.Live != nil && started {
				bad = bad || !near(live.WPM, step.Live.WPM) || !near(live.Accuracy, step.Live.Accuracy)
			}
			if bad {
				t.Fatalf("round %q step %d (%q): typed %q errors %d correct %d result %v/%v live %v source %q; Swift %+v",
					c.Name, i, step.Text, string(r.Typed()), r.Errors, r.Correct(), result, done, live, source, step)
			}
		}
	}
	for _, c := range v.Parse {
		got, skipped, err := Parse([]byte(c.JSON), "file:x.json")
		switch {
		case c.Error != nil:
			if err == nil || err.Error() != *c.Error {
				t.Errorf("Parse(%q) error %v, Swift %q", c.JSON, err, *c.Error)
			}
		case err != nil:
			t.Errorf("Parse(%q) error %v, Swift accepts it", c.JSON, err)
		default:
			ok := got.Name == *c.Name && skipped == *c.Skipped && len(got.ES) == len(c.Quotes)
			for i := 0; ok && i < len(got.ES); i++ {
				ok = got.ES[i].Equal(c.Quotes[i])
			}
			if !ok {
				t.Errorf("Parse(%q) = %q %v skipped %d, Swift %q %v skipped %d", c.JSON, got.Name, got.ES, skipped, *c.Name, c.Quotes, *c.Skipped)
			}
		}
	}
	for _, c := range v.Contains {
		if got := Contains(c.Hay, c.Needle); got != c.Out {
			t.Errorf("Contains(%q, %q) = %v, Swift %v", c.Hay, c.Needle, got, c.Out)
		}
	}
}
