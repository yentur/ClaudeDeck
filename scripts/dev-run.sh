#!/bin/bash
# Rebuilds and runs exactly one dev instance against a fake-session sandbox.
# Usage: scripts/dev-run.sh <sandbox dir created by fake-sessions.py>
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -f "ClaudeDeck.app/Contents/MacOS/ClaudeDeck" || true
./scripts/build-app.sh >/dev/null
source "$1/env.sh"
export CLAUDE_DECK_DEBUG=1
nohup "$PWD/dist/ClaudeDeck.app/Contents/MacOS/ClaudeDeck" > "$1/app.log" 2>&1 &
sleep 2
pgrep -lf "ClaudeDeck.app/Contents/MacOS/ClaudeDeck"
