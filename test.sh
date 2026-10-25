#!/bin/bash
# Compiles the logic files with the self-check and runs it (asserts stay on: no -O).
set -euo pipefail
cd "$(dirname "$0")"
# @State compiles in CI (Xcode) but not with Command Line Tools; use @StateObject.
if grep -rn '@State\b' Sources; then echo "error: use @StateObject instead of @State (see AGENTS.md)" >&2; exit 1; fi
out=$(mktemp -d)/selfcheck
swiftc Sources/AiberTyper/{Typing,Session,HotKey,Keys}.swift Sources/AiberTyper/Texts*.swift Tests/main.swift -o "$out"
"$out"
