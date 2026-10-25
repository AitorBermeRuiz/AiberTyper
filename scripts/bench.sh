#!/bin/bash
# Builds the app and measures it end to end (about a minute): launch, idle, a typed round, idle again.
# Prints a Markdown table of CPU, RAM, wakeups, energy and GPU per phase and fails over budget. See AGENTS.md.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh > /dev/null
bin=$(mktemp -d)/bench
swiftc -O scripts/bench/main.swift -o "$bin"
"$bin" build/AiberTyper.app/Contents/MacOS/AiberTyper
