# AitorTyper

Typing practice from the macOS menu bar. Press ⌥⇧T anywhere, type the sentences, see your words per minute and accuracy.

Build with `./build.sh` (creates `build/AitorTyper.app`); run the self-check with `./test.sh`.

## Shortcuts

| Key | Action |
|-----|--------|
| ⌥⇧T | Open / close (change it with **Cambiar atajo…** in the menu bar; it must include ⌘, ⌥ or ⌃, and ⌘+letter or ⌥+letter are refused because macOS uses them) |
| Tab | Switch language (Español / English) |
| Shift+Tab | Choose a collection |
| Enter | New round |
| Esc | Close |

In the collection picker: type to filter, Ctrl+J/K or ↑↓ to move, Ctrl+F to star a favorite (favorites are listed first, with ★), Ctrl+I or the **＋ Importar colección…** button to import, Enter to choose, Esc to go back.

The **Otra ronda** and **Cerrar** buttons, the language and collection pills and the picker rows can also be clicked.

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
- Whitespace runs (line breaks, tabs) become one space.
- Sentences with emoji or wide characters (Chinese, Japanese, Korean) are skipped.
- Files over 1 MB are ignored.
- Your collections have no language: the same sentences are used whatever tab selects.

Files live in `~/Library/Application Support/AitorTyper/Colecciones`. From the menu-bar icon:

- **Importar colección…** (also in the picker) first explains the format (with a "No volver a mostrar este mensaje nunca más" checkbox), then checks the files you pick and copies the valid ones into that folder. An existing file with the same name is moved to the Trash before the new one is written; re-importing a file from the folder itself is safe.
- **Abrir carpeta de colecciones** opens the folder, to edit or delete files by hand. Changes show up the next time you open the picker.

See [`Examples/Programming.json`](Examples/Programming.json) for a ready-to-import example.
