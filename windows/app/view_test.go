//go:build windows

package main

import (
	"reflect"
	"testing"
)

func TestWrapWidth(t *testing.T) {
	runes := func(s string) float32 { return float32(len([]rune(s))) } // one unit per character
	for _, c := range []struct {
		s    string
		w    float32
		want []string
	}{
		{"corto", 10, []string{"corto"}},
		{"no se pudo guardar el historial", 12, []string{"no se pudo", "guardar el", "historial"}},
		{"rename C:\\Users\\aitor\\history.json", 10, []string{"rename", "C:\\Users\\a", "itor\\histo", "ry.json"}},
		{"ñññ", 1, []string{"ñ", "ñ", "ñ"}},
	} {
		if got := wrapWidth(c.s, c.w, runes); !reflect.DeepEqual(got, c.want) {
			t.Errorf("wrapWidth(%q, %v) = %q, want %q", c.s, c.w, got, c.want)
		}
	}
}
