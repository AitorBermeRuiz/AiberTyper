#!/bin/bash
# Checks scripts/cask.sh: valid Ruby, release URL, quarantine step only when not notarized, bad input refused.
set -euo pipefail
cd "$(dirname "$0")/.."
z=$(printf '0%.0s' {1..64}); t=$(mktemp -d)
for n in 0 1; do scripts/cask.sh 1.2.3 "$z" $n > "$t/c$n.rb"; ruby -c "$t/c$n.rb" > /dev/null; done
grep -q 'releases/download/v#{version}/AitorTyper-#{version}.zip' "$t/c0.rb"
grep -q quarantine "$t/c0.rb"
grep -q quarantine "$t/c1.rb" && { echo "notarized cask strips quarantine"; exit 1; }
scripts/cask.sh v1.2.3 "$z" > /dev/null 2>&1 && { echo "accepted v1.2.3"; exit 1; }
scripts/cask.sh 1.2.3 ABC > /dev/null 2>&1 && { echo "accepted ABC"; exit 1; }
scripts/cask.sh > /dev/null 2>&1 && { echo "accepted no arguments"; exit 1; }
echo "cask-check OK"
