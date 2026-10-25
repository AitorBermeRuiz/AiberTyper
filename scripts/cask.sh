#!/bin/bash
# Prints the Homebrew cask for a release: scripts/cask.sh <version> <sha256> <notarized: 0|1>
# The release workflow writes it to Casks/aibertyper.rb in AitorBermeRuiz/homebrew-tap.
set -euo pipefail
version=${1:-} sha=${2:-} notarized=${3:-0}
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ && "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "usage: $0 <version> <sha256> [0|1]" >&2; exit 1; }

cat <<EOF
cask "aibertyper" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/AitorBermeRuiz/AitorTyper/releases/download/v#{version}/AiberTyper-#{version}.zip"
  name "AiberTyper"
  desc "Typing practice from the menu bar"
  homepage "https://github.com/AitorBermeRuiz/AitorTyper"

  depends_on macos: :sonoma

  app "AiberTyper.app"
EOF

if [[ "$notarized" != 1 ]]; then
cat <<'EOF'

  # Not notarized by Apple yet: without this, Gatekeeper refuses to open the downloaded app.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/AiberTyper.app"]
  end

  caveats <<~TEXT
    AiberTyper is not notarized by Apple yet, so this cask removes the
    download quarantine flag from the app after installing it.
  TEXT
EOF
fi

cat <<'EOF'

  zap trash: [
    "~/Library/Application Support/AiberTyper",
    "~/Library/Preferences/com.aiber.AiberTyper.plist",
  ]
end
EOF
