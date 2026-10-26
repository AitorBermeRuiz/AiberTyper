#!/bin/bash
# Renders the design mockups in mockups/main.swift to mockups/out/*.png (not in git).
set -euo pipefail
cd "$(dirname "$0")"
bin=$(mktemp -d)/designs
swiftc mockups/main.swift -o "$bin"
"$bin" mockups/out
