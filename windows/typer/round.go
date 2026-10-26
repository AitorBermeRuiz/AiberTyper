package typer

import (
	"strings"
	"time"
)

// Round is one attempt at a text: what was typed, every keystroke and the live score. Knows nothing of history or settings.
type Round struct {
	// Quotes make up Target, in order.
	Quotes []Quote
	Target []rune
	typed  []rune
	// Errors counts wrong keystrokes, including the ones corrected later.
	Errors     int
	keystrokes int
	start      time.Time
	started    bool
	finished   bool
}

// Score is a round's speed and accuracy; Seconds is set only on the final score.
type Score struct {
	WPM, Accuracy, Seconds float64
}

func NewRound(quotes []Quote) Round {
	texts := make([]string, len(quotes))
	for i, q := range quotes {
		texts[i] = q.Text
	}
	return Round{Quotes: quotes, Target: []rune(strings.Join(texts, " "))}
}

func (r *Round) Typed() []rune { return r.typed }

// Type takes the field's whole text. Returns the final score on the keystroke that completes the round, false on
// every other one; once complete, typing is ignored.
func (r *Round) Type(text string, now time.Time) (Score, bool) {
	if r.finished {
		return Score{}, false
	}
	goal := r.Target
	next := []rune(text)
	next = next[:min(len(next), len(goal))]
	old := r.typed
	if !r.started && len(next) > 0 {
		r.start, r.started = now, true
	}
	if len(next) > len(old) {
		for i := len(old); i < len(next); i++ {
			r.keystrokes++
			if next[i] != goal[i] {
				r.Errors++
			}
		}
	} else if i := len(next) - 1; len(next) == len(old) && i >= 0 && next[i] != old[i] {
		// A dead key composed in place (´ then á): re-score that keystroke.
		if old[i] != goal[i] {
			r.Errors--
		}
		if next[i] != goal[i] {
			r.Errors++
		}
	}
	r.typed = next
	pendingAccent := len(next) > 0 && strings.ContainsRune("´¨`^~ˆ˜", next[len(next)-1]) && next[len(next)-1] != goal[len(goal)-1]
	if len(next) != len(goal) || pendingAccent || !r.started {
		return Score{}, false
	}
	s, _ := r.Live(now)
	r.finished = true
	s.Seconds = now.Sub(r.start).Seconds()
	return s, true
}

// Live is the score so far; false until the first keystroke. WPM counts only correct characters; accuracy counts
// every keystroke, including corrected mistakes.
func (r *Round) Live(now time.Time) (Score, bool) {
	if !r.started {
		return Score{}, false
	}
	seconds := now.Sub(r.start).Seconds()
	s := Score{Accuracy: 1}
	if seconds > 0 {
		s.WPM = float64(r.Correct()) / 5 / (seconds / 60)
	}
	if r.keystrokes > 0 {
		s.Accuracy = float64(r.keystrokes-r.Errors) / float64(r.keystrokes)
	}
	return s, true
}

// Correct counts typed characters that match the target at the same position.
func (r *Round) Correct() int {
	n := 0
	for i, c := range r.typed {
		if c == r.Target[i] {
			n++
		}
	}
	return n
}

// Source of the quote under the cursor; false for unattributed quotes.
func (r *Round) Source() (string, bool) {
	end := 0
	for _, q := range r.Quotes {
		end += runeCount(q.Text) + 1
		if len(r.typed) < end {
			return deref(q.Source)
		}
	}
	if len(r.Quotes) > 0 {
		return deref(r.Quotes[len(r.Quotes)-1].Source)
	}
	return "", false
}

func deref(s *string) (string, bool) {
	if s == nil {
		return "", false
	}
	return *s, true
}
