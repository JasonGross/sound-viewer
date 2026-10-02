#!/bin/bash
# Builds "build/Sound Viewer.app" (release, ad-hoc signed). Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SoundViewer
BIN_DIR=$(swift build -c release --show-bin-path)

APP="build/Sound Viewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SoundViewer" "$APP/Contents/MacOS/SoundViewer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. macOS ties the audio-recording permission to the signature, so after a
# rebuild you may be asked to allow it again.
codesign --force --sign - --identifier local.SoundViewer "$APP"
echo "Built $APP"
