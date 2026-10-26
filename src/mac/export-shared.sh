#!/bin/bash
# Regenerates windows/shared/ (built-in collections, Unicode tables, test vectors) from the Swift sources.
# Run it after changing Texts*.swift, Typing.swift or Round.swift, and commit the result. CI fails when it is stale.
set -euo pipefail
cd "$(dirname "$0")"
out=$(mktemp -d)/export
swiftc Sources/AiberTyper/{Typing,Round}.swift Sources/AiberTyper/Texts*.swift export/main.swift -o "$out"
mkdir -p ../../windows/shared
"$out" ../../windows/shared
