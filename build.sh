#!/bin/bash
# Builds build/AitorTyper.app (menu bar app, no Dock icon).
# Optional environment (used by the release workflow):
#   VERSION=1.2.3          version written to Info.plist (default 0.1)
#   UNIVERSAL=1            build for Apple Silicon and Intel
#   SIGN_IDENTITY="Developer ID Application: …"  sign for distribution (hardened runtime) instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

version=${VERSION:-0.1}
archs=()
[[ "${UNIVERSAL:-}" == 1 ]] && archs=(--arch arm64 --arch x86_64)

swift build -c release ${archs[@]+"${archs[@]}"}
bin=$(swift build -c release ${archs[@]+"${archs[@]}"} --show-bin-path)
app=build/AitorTyper.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/AitorTyper" "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.aitor.AitorTyper</string>
    <key>CFBundleName</key><string>AitorTyper</string>
    <key>CFBundleExecutable</key><string>AitorTyper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
    # Ad-hoc signing is for local use; downloaded copies are blocked by Gatekeeper.
    codesign --force --sign - "$app"
fi
echo "Built $app ($version). Copy it to /Applications to keep it."
