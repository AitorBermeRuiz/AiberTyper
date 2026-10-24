#!/bin/bash
# Renders the design mockups in Designs/main.swift to Designs/out/*.png.
set -euo pipefail
cd "$(dirname "$0")"
bin=$(mktemp -d)/designs
swiftc Designs/main.swift -o "$bin"
"$bin" Designs/out
