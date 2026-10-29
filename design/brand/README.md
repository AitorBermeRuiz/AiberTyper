# Aiber Brand & Design System

Official brand identity for **Aiber** (Aitor Bermejo Ruiz) and its first product, **Aiber Typer**.
This directory contains the canonical logo and color specifications, kept separate from historical UI explorations in `design/mockups/`.

## Brand Architecture

- **Umbrella brand**: `Aiber` (`Ai`tor `Ber`mejo)
- **Product naming**: `Aiber <Product>` (e.g., `Aiber Typer`, bundle executable `AiberTyper`, bundle ID `com.aiber.AiberTyper`)
- **UI header signature**: Logo mark + `AIBER TYPER` (SF Mono, 12 pt, tracking +2, uppercase; UI text in SF Pro Rounded)

## Color Palette — *Aiber Bermejo*

Inspired by high-contrast dark terminal aesthetics, rotated into the **Bermejo** (crimson / coral-vermilion, ~349°) spectrum.

| Token | Role | Hex | RGB |
|-------|------|-----|-----|
| `bg` | Window & icon background (obsidian wine) | `#1B1113` | `27, 17, 19` |
| `fg` | Primary typed text (warm off-white) | `#F6EEF0` | `246, 238, 240` |
| `pink` / `soft` | Soft coral accent (caret block, primary pill, header, stats) | `#F497A9` | `244, 151, 169` |
| `neon` | Vivid bermejo crimson (active state, errors, logo cursor bar) | `#E83A59` | `232, 58, 89` |
| `muted` | Secondary / pending text (standard contrast) | `#AA989C` | `170, 152, 156` |
| `muted (high)` | Secondary / pending text (increased contrast) | `#D9CCD0` | `217, 204, 208` |
| `border` | Card border, dividers, keycaps (standard contrast) | `#3C262B` | `60, 38, 43` |
| `border (high)` | Card border, dividers, keycaps (increased contrast) | `#7C5E66` | `124, 94, 102` |
| `yellow` | Record badge (`NUEVO RÉCORD`) | `#F5D547` | `245, 213, 71` |

### Background Glow

- Base fill: `#1B1113`
- Top-leading radial gradient: `#F497A9` at `22%` opacity (`startRadius: 0`, `endRadius: 420` in window; `32%` soft + `12%` neon in the app icon) fading to transparent.

## Logo Mark — *Chevron + Base Cursor (1B)*

The **Aiber** mark combines an ascending chevron (`^`, representing both the `A` of *Aiber* and a keyboard control symbol) with a horizontal block cursor (`_`) that completes the right leg on the baseline, separated by a clean optical gap so the two elements never overlap.

### Canonical Geometry (normalized `0…1` square)

- **Stroke width**: `0.135` (`lineCap: .round`, `lineJoin: .round`)
- **Chevron (`#F497A9`)**:
  - Left foot: `(0.18, 0.77)`
  - Apex: `(0.48, 0.21)`
  - Shortened right leg end: `(0.65, 0.53)`
- **Cursor bar (`#E83A59`)**:
  - Rect: `x = 0.56`, `y = 0.7025`, `width = 0.30`, `height = 0.135`, `cornerRadius = 0.065`
  - Bottom edge aligns at `y = 0.8375` with the bottom cap of the left foot (`0.77 + 0.135 / 2`).

## Files in `design/brand/`

| File | Purpose |
|------|---------|
| `README.md` | This specification (palette tokens, geometry, brand naming). |
| `logo.svg` | Full-color vector app icon (`1024×1024`) with `#1B1113` squircle background, radial glow, and Logo 1B. |
| `menubar-template.svg` | Monochrome vector mark (`18×18`) for the macOS menu bar template icon. |
| `icon-1024.png` | Master `1024×1024` PNG icon used by `src/mac/build.sh` (via `sips` + `iconutil`) to build `AppIcon.icns`, and by `src/windows/build.sh` for the `.exe` icon. |
| `brand-sheet.png` | Official visual reference sheet showing the Aiber Bermejo palette, Logo 1B, and UI preview. |
