#!/bin/bash
# Builds the app, quits any running copy, and opens the new one.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
osascript -e 'tell application id "local.SoundViewer" to quit' 2>/dev/null || true
open "build/Sound Viewer.app"
