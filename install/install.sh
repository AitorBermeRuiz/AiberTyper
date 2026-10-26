#!/bin/bash
# Installs the latest AiberTyper release into /Applications and opens it:
#   curl -fsSL https://raw.githubusercontent.com/AitorBermeRuiz/AitorTyper/main/install/install.sh | bash
# curl does not set com.apple.quarantine, so the app opens without the Gatekeeper prompt even when it is not notarized.
set -euo pipefail
repo=AitorBermeRuiz/AitorTyper
app=/Applications/AiberTyper.app

# releases/latest redirects to .../releases/tag/vX.Y.Z
tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
tag=${tag##*/}
version=${tag#v}
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "No AiberTyper release found on github.com/$repo" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading AiberTyper $version..."
curl -fL --progress-bar -o "$tmp/AiberTyper.zip" "https://github.com/$repo/releases/download/$tag/AiberTyper-$version.zip"
ditto -x -k "$tmp/AiberTyper.zip" "$tmp"
[ -d "$tmp/AiberTyper.app" ] || { echo "The download has no AiberTyper.app" >&2; exit 1; }

pkill -x AiberTyper || true # an open copy would keep running the old version
rm -rf "$app"
mv "$tmp/AiberTyper.app" "$app"
echo "Installed $app"
open "$app"
