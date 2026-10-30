# Roadmap

Known limits and work planned for later. Nothing here is scheduled.

- Themes: only the Aiber Bermejo style is implemented. Others are mockups in `design/mockups/`.
- Picker: no scroll, no mouse wheel handling for long lists.
- Shortcut recorder inside the picker.
- Distribution through the gentle-shell installer.
- Windows: code signing. Unsigned, SmartScreen warns on browser downloads and Smart App Control (Windows 11) blocks the app. `release.yml` signs through SignPath once the project is accepted (README "Code signing policy").
- Windows: a start-at-sign-in option, a native arm64 build (needs GDI+ calls without float arguments), winget.
- Windows: the panel is drawn by hand and exposes nothing to screen readers (the Mac app labels every element for VoiceOver); it needs a UI Automation provider.
- Windows: the UI is checked through the CI `windows` job (`SendInput`, screenshots and `src/windows/bench`), not on a physical Windows PC.
- Windows: the import help shows the JSON example in the task dialog's proportional font.
- Windows: a history read that fails once (antivirus or OneDrive holding the file) makes the history read-only until the app restarts, the same rule as the Mac but likelier on Windows. A short retry before giving up would cover it.
- Windows: the Go port counts runes where Swift counts characters (grapheme clusters). Text is NFC-normalized, so this only shows with combining sequences that have no precomposed form: such a quote counts one extra character, and Backspace in the picker filter removes one code point.
