# Roadmap

Known limits and work planned for later. Nothing here is scheduled.

- Themes: only the Aiber Bermejo style is implemented. Others are mockups in `Designs/`.
- Picker: no scroll, no mouse wheel handling for long lists.
- Shortcut recorder inside the picker.
- Distribution through the gentle-shell installer.
- Windows: code signing (SmartScreen warns on browser downloads), a start-at-sign-in option, a native arm64 build (needs GDI+ calls without float arguments), winget.
- Windows: the panel is drawn by hand and exposes nothing to screen readers (the Mac app labels every element for VoiceOver); it needs a UI Automation provider.
- Windows: the import help shows the JSON example in the task dialog's proportional font.
