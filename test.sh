#!/bin/bash
# Compiles the logic files with the self-check and runs it (asserts stay on: no -O).
set -euo pipefail
cd "$(dirname "$0")"
out=$(mktemp -d)/selfcheck
swiftc Sources/AitorTyper/{Typing,Session,HotKey}.swift Sources/AitorTyper/Texts*.swift Tests/main.swift -o "$out"
"$out"
