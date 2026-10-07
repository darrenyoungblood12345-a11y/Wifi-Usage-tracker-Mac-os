#!/usr/bin/env bash
# Runs the core unit tests (build products kept outside the project folder; see env.sh).
set -euo pipefail
source "$(dirname "$0")/env.sh"
swift test --package-path "$PACKAGE" --scratch-path "$SCRATCH" "$@"
