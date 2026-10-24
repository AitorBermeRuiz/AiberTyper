# AitorTyper

Typing practice from the macOS menu bar. Press ⌥⇧T anywhere, type the sentences, see your words per minute and accuracy.

Build with `./build.sh` (creates `build/AitorTyper.app`); run the self-check with `./test.sh`.

## Shortcuts

| Key | Action |
|-----|--------|
| ⌥⇧T | Open / close (change it with **Cambiar atajo…** in the menu bar; it must include ⌘, ⌥ or ⌃) |
| tab | Switch language (Español / English) |
| ⇧tab | Choose a collection |
| ⏎ | New round |
| esc | Close |

In the collection picker: type to filter, ⌃j/⌃k or ↑↓ to move, ⌃f to star a favorite (favorites are listed first, with ★), ⌃i or the **＋ Importar colección…** button to import, ⏎ to choose, esc to go back.

## Your own collections

A collection is a JSON file:

```json
{
  "name": "Programación",
  "quotes": [
    {"text": "Simplicity is prerequisite for reliability.", "source": "Edsger W. Dijkstra"},
    {"text": "Una frase sin fuente."}
  ]
}
```

- `name` is required; it is what the picker shows.
- Each quote needs `text`; `source` is optional and shown under the text.
- Sentences over 300 characters (90 s at 40 wpm) or empty are skipped.
- Your collections have no language: the same sentences are used whatever tab selects.

Files live in `~/Library/Application Support/AitorTyper/Colecciones`. From the menu-bar icon:

- **Importar colección…** (also in the picker) first explains the format (with a "No volver a mostrar este mensaje nunca más" checkbox), then checks the files you pick and copies the valid ones into that folder (a file with the same name is replaced).
- **Abrir carpeta de colecciones** opens the folder, to edit or delete files by hand. Changes show up the next time you open the picker.

See [`Examples/Programming.json`](Examples/Programming.json) for a ready-to-import example.
