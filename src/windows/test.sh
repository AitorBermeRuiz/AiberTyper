#!/bin/bash
# Runs the Go tests: the typing logic against the vectors exported from the Swift code, and the view checks.
set -euo pipefail
cd "$(dirname "$0")"
go test ./...
