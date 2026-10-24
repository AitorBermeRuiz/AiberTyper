#!/bin/bash
# Builds build/AitorTyper.app (menu bar app, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=build/AitorTyper.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/AitorTyper "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.aitor.AitorTyper</string>
    <key>CFBundleName</key><string>AitorTyper</string>
    <key>CFBundleExecutable</key><string>AitorTyper</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "Built $app. Copy it to /Applications to keep it."
