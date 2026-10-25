# AGENTS.md

Guide for AI agents working on AitorTyper. Read it before changing code.

## What this is

AitorTyper is a macOS menu bar app for typing practice. The user presses a global shortcut (default ⌥⇧T), types sentences from a collection, and sees live words per minute (WPM) and accuracy. It replaces the Raycast typer the owner used before. Future distribution through the gentle-shell installer is possible, but not decided.

- Language: Swift 5.10 (SwiftPM), SwiftUI + AppKit, macOS 14+.
- No dependencies. No Dock icon (`LSUIElement`).
- The UI copy is in Spanish. Code, comments, identifiers and commit messages are in English.

## Layout

| Path | Role |
|------|------|
| `Sources/AitorTyper/main.swift` | `AppDelegate`: status item and menu, the floating `NSPanel`, the local key monitor (`pickerKey`), the import flow, the shortcut dialog. |
| `Sources/AitorTyper/Session.swift` | `@Observable` state: round, typed text, live stats, result, collection picker, favorites, history. |
| `Sources/AitorTyper/TyperView.swift` | SwiftUI views: typing, picker, results. Palette `G` lives here. |
| `Sources/AitorTyper/Typing.swift` | Pure logic: `Lang`, `Quote`, `Collection` (JSON parse and load), `History`, `score`, `wrapLines`, `lineWindow`, `pickSentences`, `charsFor`. |
| `Sources/AitorTyper/HotKey.swift` | `HotKey` model, Carbon hot key registration. |
| `Sources/AitorTyper/Texts.swift`, `Texts+Stoic.swift` | Built-in sentences. General (es/en) and Stoicism (es/en, each with its source). |
| `Tests/main.swift` | Self-check with `assert`s. No XCTest. |
| `Examples/Programming.json` | Example collection for users. |
| `Designs/main.swift` | Design mockups rendered to `Designs/out/` by `designs.sh`. Reference only, not shipped. |
| `README.md` | User-facing docs: shortcuts, collection format. Keep it in sync with behavior. |

## Commands

- `./test.sh`: compiles `Typing`, `Session`, `HotKey`, `Texts*` and `Tests/main.swift` with `swiftc` and runs the self-check. Must print `self-check OK`.
- `./build.sh`: `swift build -c release` and assembles `build/AitorTyper.app` (ad-hoc signed).
- `./designs.sh`: renders the mockups.
- `swift test` does not work here. Command Line Tools lack the swift-testing macro plugin. Do not add XCTest or `@Test` without checking that first.

`test.sh` lists its sources explicitly. A new logic file (no UI or AppKit dependency that breaks `swiftc`) must be added there, or its tests will not compile.

## Running the app after a change (read this)

`swift build` does **not** update the app the user runs. The running app is `build/AitorTyper.app`. After any source change:

1. `./test.sh` and `./build.sh`.
2. Quit the running instance: `pkill -f AitorTyper.app/Contents/MacOS/AitorTyper`.
3. `open build/AitorTyper.app`.
4. Check that one process runs and that its binary is the new one (`ps -o pid,lstart,command -p <pid>` against `ls -l build/AitorTyper.app/Contents/MacOS/AitorTyper`).

Say in the report that the app was restarted and with which build. The user has asked "¿has reiniciado la app?" several times when it was still running the old binary. Never claim a UI change works until it runs in the rebuilt app.

## Architecture notes

- **Keys**: `AppDelegate` installs a local `keyDown` monitor that only handles events from the panel. Escape, Tab, ⇧Tab and Return are handled there. Arrows, Home/End and PageUp/PageDown are swallowed there so they never reach the hidden field. When the picker is open, every key goes to `pickerKey`.
- **Text input**: a hidden `TextField` (1×1, opacity 0.01) receives the keystrokes so accents and ñ compose like a normal field. The text is `session.typed`.
- **Focus rule**: every click handler goes through `act()` in `TyperView`, which hands focus back to the hidden field. A button that skips `act()` breaks typing until the panel reopens.
- **Picker**: state lives in `Session` (`picking`, `filter`, `selection`, `matches`). `matches` is the filtered list with favorites first. Filtering uses `localizedStandardContains` (case and accent insensitive).
- **Live stats**: `TimelineView` ticks twice a second only while the panel is visible and a round has started. Keep that cost; do not add timers.
- **Manual wrap**: text is wrapped by hand, using the monospaced advance of the Iosevka font (fallback: system monospaced). `G.charsPerLine` is computed once. A proportional font would need real text layout measurement.
- **Score**: WPM counts correct characters only. Accuracy counts every keystroke, including corrected mistakes.
- **Round length**: sentences are picked to fill 30–60 s at the user's recent WPM (`History.recentWPM`, default 40), capped at 90 s.

## Persistence (do not break these)

- `UserDefaults`: `lang`, `pack` (collection id), `favorites`, `hotKey` (JSON; a saved shortcut the recorder would refuse falls back to ⌥⇧T), `hideImportHelp`.
- `~/Library/Application Support/AitorTyper/history.json`: finished rounds. Only a missing file means empty history. Any other read or decode error, at launch or when `add()` re-reads the file later, makes the history read-only: rounds are not saved, the file is kept as is and a note is shown. `add()` re-reads the file before appending, so two instances do not erase each other's rounds.
- `~/Library/Application Support/AitorTyper/Colecciones/*.json`: user collections. Format: `{"name": "...", "quotes": [{"text": "...", "source": "..."}]}`. `name` and `text` are required. Quotes over `Collection.maxChars` (300 characters, 90 s at 40 wpm) or empty are skipped. Files over `Collection.maxBytes` (1 MB) are refused by `parse` (import) and `load`.
- Collection ids: built-in `general` and `stoic`; files are `file:<name>.json`. A selected collection whose file disappears or fails to load falls back to `general` in memory only; the saved `pack` is kept, so it comes back when the file loads again.

## Rules for changes

- **Hotkeys**: must include ⌘, ⌥ or ⌃. Plain or ⇧-only keys would steal normal typing in every app. ⌘+letter/number (with or without ⇧) and ⌥+letter are refused too: macOS and apps use them, and ⌥+letter types dead keys.
- **Picker keys**: every plain letter goes to the filter; plain j/k never move. ⌃j/⌃k and the arrows move.
- **View state**: the `@State` macro does not compile here (the SwiftUI macro plugin is missing). Use `@StateObject` with an `ObservableObject` for view-local state, like `HoverState`.
- **Stoic and new quotes**: each quote needs a verifiable source and must fit 90 s at 40 wpm (≤300 characters). Do not add unattributed or misattributed quotes.
- **New collections**: one file per collection (like `Texts+Stoic.swift`), registered in `Collection`. Keep `test.sh` in sync.
- **Themes**: the owner plans to switch between several styles later. The Gentleman style is the Gentle-AI site palette: plum background `#1A1217`, pink `#F19AC8`, neon `#E8418C`, muted `#A99AA3`, border `#3A2A33`, yellow `#F5D547` for NEW tags. Do not use the Kanagawa/gold palette; the owner rejected it. Other mockups are in `Designs/`.
- **Window**: `safeAreaRegions = []` on the hosting controller is required. Without it, resizing the transparent titlebar panel crashes AppKit (constraint loop). Do not remove it.
- **Import**: validate every file before copying it into the folder. Show the format help once, with "No volver a mostrar este mensaje nunca más".
- **Strings**: UI copy in Spanish, with the same register as existing strings (voseo is not used in UI). Keep keyboard hints in the footers in sync with the real keys.
- **Docs**: when a shortcut, option or message changes, update `README.md` and the footer hints in `TyperView`.

## Testing and verification

- New logic: write the assert in `Tests/main.swift` first, see it fail, then implement. Test through public functions, never internal storage.
- UI behavior (clicks, focus, key handling, layout) is not covered by the self-check. Verify it in the rebuilt app and say clearly what was and was not checked.
- Known untested areas: mouse interaction of the picker and buttons, hover highlight and pointing-hand cursor reset (when a button disappears or the panel loses key), and very long collection lists (the picker has no scroll).

## Git

- Branch: `master`, local only so far. No remote is configured in this repo.
- Commit style: Conventional Commits (`feat:`, `fix:`, `perf:`, `chore:`, `feat(texts):`).
- Do not commit, push or create branches unless the user asks. When the user does ask for commits, split them by phase (see the history: one commit per feature, tests with the code).
- Do not commit `build/` or `.build/` (both ignored). Do not commit scratch files.

## Known limits and next steps

- Themes: only the Gentleman style is implemented. Others are mockups in `Designs/`.
- Picker: no scroll, no mouse wheel handling for long lists.
- Possible later work: a programming collection, a shortcut recorder inside the picker, distribution through gentle-shell.

## Memory

Engram project name: `aitortyper` (lowercase). Decisions and gotchas from earlier sessions are stored there. Search it before re-deciding a design or behavior.
