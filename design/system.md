# Aiber Typer design system

Captured from `design/brand/README.md` and `src/mac/Sources/AiberTyper/TyperView.swift`. Only values found there.

## Colors (Aiber Bermejo)

| Token | Value | Usage | Source |
|-------|-------|-------|--------|
| `bg` | `#1B1113` | Window background | `design/brand/README.md`, `TyperView.swift` (`G.bg`) |
| `fg` | `#F6EEF0` | Primary text | `design/brand/README.md`, `G.fg` |
| `pink` | `#F497A9` | Soft accent: header, primary pill, selection fill, stats | `design/brand/README.md`, `G.pink` |
| `neon` | `#E83A59` | Active state, errors, logo cursor bar | `design/brand/README.md`, `G.neon` |
| `muted` | `#AA989C` | Secondary text, captions, hints | `design/brand/README.md` |
| `muted-high` | `#D9CCD0` | Secondary text, increased contrast | `design/brand/README.md` |
| `border` | `#3C262B` | Card border, dividers, keycaps | `design/brand/README.md` |
| `border-high` | `#7C5E66` | Border, increased contrast | `design/brand/README.md` |
| `yellow` | `#F5D547` | NUEVO RÉCORD / NUEVO tags | `design/brand/README.md`, `G.yellow` |
| `glow` | `#F497A9` at 22 % | Top-leading radial gradient, radius 420 | `design/brand/README.md` |

## Typography

- Mono: SF Mono (`.system(design: .monospaced)`). Header signature 12 pt, tracking +2, uppercase, `pink`. Typing text 23 pt. Picker filter 16 pt. Source: `src/mac/Sources/AiberTyper/TyperView.swift` (`G.mono`, `G.textSize`).
- UI: SF Pro Rounded (`design: .rounded`). Captions 12, labels 13 medium, list rows 15, keycaps 10 semibold, big WPM 104 heavy tracking −3. Source: `src/mac/Sources/AiberTyper/TyperView.swift`.

## Spacing and radius

- Panel: width 640, padding 28–30, radius 14 continuous, 1 px `border` stroke. Source: `src/mac/Sources/AiberTyper/TyperView.swift:123-126`.
- Pill: padding 12×5. Picker row: 12×6, radius 6, selected fill `pink`, hover `pink` 15 %. Keycap: 5×1, radius 4, 1 px stroke at 70 %. Tag: 6×2, radius 3. Source: `src/mac/Sources/AiberTyper/TyperView.swift`.

## Components

- Header: Logo 1B (16×16) + `AIBER TYPER` mono signature.
- Pill: primary is `pink` fill with `bg` text; secondary is outline.
- Keycap hint: small outlined key + muted action text (footer hints).
- Selectable row: selected → `pink` fill, `bg` text, bold.
- Error / note text: 12 pt `neon`.
