# AitorTyper

Typing practice from the macOS menu bar. Press ⌥⇧T anywhere, type the sentences, see your words per minute and accuracy.

## Install

With [Homebrew](https://brew.sh) (macOS 14 Sonoma or later):

```sh
brew install --cask aitorbermeruiz/tap/aitortyper
```

Or download `AitorTyper-<version>.zip` from [Releases](https://github.com/AitorBermeRuiz/AitorTyper/releases), unzip it and move `AitorTyper.app` to Applications. Builds are not notarized by Apple yet, so a downloaded app needs `xattr -dr com.apple.quarantine /Applications/AitorTyper.app` once before it opens (Homebrew does this for you).

From source: `./build.sh` creates `build/AitorTyper.app`; `./test.sh` runs the self-check.

## Shortcuts

| Key | Action |
|-----|--------|
| ⌥⇧T | Open / close (change it with **Cambiar atajo…** in the menu bar; it must include ⌘, ⌥ or ⌃, and ⌘+letter or ⌘+number (with or without ⇧) is refused because apps use it, as is ⌥ plus any key that types a character, such as ⌥+letter or ⌥+ (`]` on a Spanish keyboard)) |
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
- Files over 1 MB are refused on import and ignored in the folder.
- Your collections have no language: the same sentences are used whatever tab selects.

Files live in `~/Library/Application Support/AitorTyper/Colecciones`. From the menu-bar icon:

- **Importar colección…** (also in the picker) first explains the format (with a "No volver a mostrar este mensaje nunca más" checkbox), then checks the files you pick and copies the valid ones into that folder. An existing file with the same name is moved to the Trash before the new one is written; re-importing a file from the folder itself is safe.
- **Abrir carpeta de colecciones** opens the folder, to edit or delete files by hand. Changes show up the next time you open the picker.

See [`Examples/Programming.json`](Examples/Programming.json) for a ready-to-import example.

## Releasing

Push a tag such as `v0.2.0`. The [release workflow](.github/workflows/release.yml) runs the self-check, builds a universal app, publishes `AitorTyper-0.2.0.zip` on GitHub Releases and updates the cask in [AitorBermeRuiz/homebrew-tap](https://github.com/AitorBermeRuiz/homebrew-tap).

Repository secrets it reads (all optional):

| Secret | Purpose |
|--------|---------|
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with *Contents: read and write* on `homebrew-tap`; without it the tap is not updated. |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY` | Developer ID Application certificate (base64 `.p12`), its password and its name. Without them the app is ad-hoc signed. |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | Apple ID, team id and app-specific password for notarization (needs the certificate secrets too; all three or none). Once set, the cask stops removing the quarantine flag. |

## License

[MIT](LICENSE). The agent skills under `.agents/skills/` keep their own MIT licenses.
