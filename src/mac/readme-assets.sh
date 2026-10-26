#!/bin/bash
# Renders the README banners, screenshots and demo GIFs (docs/assets) from the real views. Takes about two minutes
# (each demo round is typed in real time); `src/mac/readme-assets.sh banners` renders the banners only.
set -euo pipefail
cd "$(dirname "$0")"
bin=$(mktemp -d)/readme-assets
swiftc Sources/AiberTyper/{Typing,Round,Session,HotKey,Keys,TyperView}.swift Sources/AiberTyper/Texts*.swift \
    readme-assets/*.swift -o "$bin"
"$bin" ../../docs/assets "$@"
