# AGENTS.md

Guide for AI agents working on AiberTyper. Read it before changing code.

## What this is

AiberTyper is a macOS menu bar app for typing practice. The user presses a global shortcut (default ⌥⇧T), types sentences from a collection, and sees live words per minute (WPM) and accuracy. It replaces the Raycast typer the owner used before. Future distribution through the gentle-shell installer is possible, but not decided.

- Language: Swift 5.10 (SwiftPM), SwiftUI + AppKit, macOS 14+.
- No dependencies. No Dock icon (`LSUIElement`).
- The UI copy is in Spanish. Code, comments, identifiers and commit messages are in English.

## Layout

| Path | Role |
|------|------|
| `Sources/AiberTyper/main.swift` | `AppDelegate`: status item and menu, the floating `NSPanel`, the local key monitor (`pickerKey`), the import flow, the shortcut dialog. |
| `Sources/AiberTyper/Session.swift` | `@Observable` state: round, typed text, live stats, result, collection picker, favorites, history. |
| `Sources/AiberTyper/TyperView.swift` | SwiftUI views: typing, picker, results. Palette `G` lives here. |
| `Sources/AiberTyper/Typing.swift` | Pure logic: `Lang`, `Quote`, `Collection` (JSON parse and load), `History`, `score`, `wrapLines`, `lineWindow`, `pickSentences`, `charsFor`. |
| `Sources/AiberTyper/HotKey.swift` | `HotKey` model, Carbon hot key registration. |
| `Sources/AiberTyper/Texts.swift`, `Texts+*.swift` | Built-in sentences: General, Stoicism, Programming, The Art of War, Cinema and Cult Books (es/en, each themed quote with its source). |
| `Tests/main.swift` | Self-check with `assert`s. No XCTest. |
| `Examples/Programming.json` | Example collection for users. |
| `Brand/` | Official Aiber brand: `README.md` (palette, Logo 1B geometry), `logo.svg`, `menubar-template.svg`, `icon-1024.png` (source of `AppIcon.icns` in `build.sh`), `brand-sheet.png`. Keep it separate from `Designs/`. |
| `Designs/main.swift` | Design mockups rendered to `Designs/out/` by `designs.sh`. Reference only, not shipped. |
| `README.md` | User-facing docs: shortcuts, collection format. Keep it in sync with behavior. |

## Commands

- `./test.sh`: compiles `Typing`, `Session`, `HotKey`, `Texts*` and `Tests/main.swift` with `swiftc` and runs the self-check. Must print `self-check OK`.
- `./build.sh`: `swift build -c release` and assembles `build/AiberTyper.app` (ad-hoc signed). Optional env: `VERSION`, `UNIVERSAL=1` (arm64 + x86_64), `SIGN_IDENTITY` (Developer ID, hardened runtime).
- `scripts/cask.sh <version> <sha256> [notarized 0|1, default 0]`: prints the Homebrew cask; `scripts/test-cask.sh` checks it (run in CI). Unnotarized casks strip the quarantine flag in `postflight`.
- CI: `.github/workflows/ci.yml` (PRs and `main`: self-check, universal build, `scripts/test-cask.sh`). `.github/workflows/release.yml` (tags `v*`: build, optional sign and notarize, GitHub release, tap update). Secrets are listed in `README.md`.
- `./designs.sh`: renders the mockups.
- `swift test` does not work here. Command Line Tools lack the swift-testing macro plugin. Do not add XCTest or `@Test` without checking that first.

`test.sh` lists its sources explicitly. A new logic file (no UI or AppKit dependency that breaks `swiftc`) must be added there, or its tests will not compile.

## Running the app after a change (read this)

`swift build` does **not** update the app the user runs. The running app is `build/AiberTyper.app`. After any source change:

1. `./test.sh` and `./build.sh`.
2. Quit the running instance: `pkill -f AiberTyper.app/Contents/MacOS/AiberTyper`.
3. `open build/AiberTyper.app`.
4. Check that one process runs and that its binary is the new one (`ps -o pid,lstart,command -p <pid>` against `ls -l build/AiberTyper.app/Contents/MacOS/AiberTyper`).

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
- `~/Library/Application Support/AiberTyper/history.json`: finished rounds. Only a missing file means empty history. Any other read or decode error, at launch or when `add()` re-reads the file later, makes the history read-only: rounds are not saved, the file is kept as is and a note is shown. `add()` re-reads the file before appending, so two instances do not erase each other's rounds.
- `~/Library/Application Support/AiberTyper/Colecciones/*.json`: user collections. The format and what is skipped or refused are documented once, in `README.md` ("Your own collections"); the code is `Collection.parse` and `Collection.load`.
- Collection ids: built-in `general`, `stoic`, `programming`, `art-of-war`, `cinema` and `books`; files are `file:<name>.json`. A selected collection whose file disappears or fails to load falls back to `general` in memory only; the saved `pack` is kept, so it comes back when the file loads again.

## Rules for changes

- **Hotkeys**: a shortcut must leave normal typing alone in every app. The accepted and refused combinations are documented once, in `README.md` ("Shortcuts"); the code is `HotKey(event:)`.
- **Picker keys**: every plain letter goes to the filter; plain j/k never move. ⌃j/⌃k and the arrows move.
- **View state**: use `@StateObject` with an `ObservableObject` for view-local state, like `HoverState`. The `@State` macro does not compile with Command Line Tools (CI with Xcode does compile it), so `./test.sh` fails when `Sources/` uses it.
- **Built-in collections (standard)**:
  - File: one `Sources/AiberTyper/Texts+<Name>.swift` per collection (`extension Texts`), registered as a `static let` on `Collection` and appended to `Collection.builtIn` in `Sources/AiberTyper/Typing.swift`. `test.sh` compiles `Texts*.swift` automatically.
  - Size & uniqueness: at least **30 distinct quotes in Spanish (`es`) and 30 in English (`en`)**, paired 1-to-1 with the same count in both languages (`c.es.count == c.en.count` and `Set(texts).count == quotes.count`).
  - Length & duration: each quote must be **25–300 characters** (`Collection.maxChars`, 90 s at 40 wpm), single-spaced, with no newlines or wide/emoji characters (`Collection.parse` must accept all quotes with `skipped == 0`), and include enough quotes ≤150 chars so `pickSentences` always forms rounds of **30–90 s** (even at 20 wpm).
  - References: every quote in a themed collection (`id != "general"`) must have a non-empty, verifiable `source` (e.g. `"Author, Work"` or `"Author, Work, section"`). Do not add unattributed, paraphrased or misattributed quotes.
  - Self-check: `./test.sh` enforces all of the above automatically over every entry in `Collection.builtIn`.
- **Themes**: the owner plans to switch between several styles later. The current style is the Aiber Bermejo palette (`Brand/README.md`): background `#1B1113`, text `#F6EEF0`, pink `#F497A9`, neon `#E83A59`, muted `#AA989C`, border `#3C262B`, yellow `#F5D547` for NEW tags. Do not use the Kanagawa/gold palette; the owner rejected it. Other mockups are in `Designs/`.
- **Window**: `safeAreaRegions = []` on the hosting controller is required. Without it, resizing the transparent titlebar panel crashes AppKit (constraint loop). Do not remove it.
- **Import**: validate every file before copying it into the folder. Show the format help once, with "No volver a mostrar este mensaje nunca más".
- **Strings**: UI copy in Spanish, with the same register as existing strings (voseo is not used in UI). Keep keyboard hints in the footers in sync with the real keys.
- **Docs**: when a shortcut, option or message changes, update `README.md` and the footer hints in `TyperView`.

## Testing and verification

- New logic: write the assert in `Tests/main.swift` first, see it fail, then implement. Test through public functions, never internal storage.
- UI behavior (clicks, focus, key handling, layout) is not covered by the self-check. Verify it in the rebuilt app and say clearly what was and was not checked.
- Known untested areas: mouse interaction of the picker and buttons, hover highlight and pointing-hand cursor reset (when a button disappears or the panel loses key), and very long collection lists (the picker has no scroll).

## Git

- Remote: public `github.com/AitorBermeRuiz/AitorTyper`, default branch `main`. Work goes through branches and pull requests.
- Homebrew tap: `github.com/AitorBermeRuiz/homebrew-tap`, `Casks/aibertyper.rb` is written by the release workflow from `scripts/cask.sh`. To fix a published cask, change `scripts/cask.sh` and release a patch tag; the workflow rewrites the cask.
- License: MIT (`LICENSE`). Vendored skills in `.agents/skills/` keep their upstream MIT `LICENSE` files.
- Commit style: Conventional Commits (`feat:`, `fix:`, `perf:`, `chore:`, `feat(texts):`).
- Do not commit, push or create branches unless the user asks. When the user does ask for commits, split them by phase (see the history: one commit per feature, tests with the code).
- Do not commit `build/` or `.build/` (both ignored). Do not commit scratch files.

## Known limits and next steps

- Themes: only the Aiber Bermejo style is implemented. Others are mockups in `Designs/`.
- Picker: no scroll, no mouse wheel handling for long lists.
- Possible later work: a shortcut recorder inside the picker, distribution through gentle-shell.

## Memory

Engram project name: `aitortyper` (lowercase, kept from before the rebrand). Decisions and gotchas from earlier sessions are stored there. Search it before re-deciding a design or behavior.
