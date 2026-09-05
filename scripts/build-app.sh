#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Gonavi.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Gonavi" "$APP/Contents/MacOS/Gonavi"
chmod +x "$APP/Contents/MacOS/Gonavi"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Gonavi-macOS-arm64.zip"
shasum -a 256 "dist/Gonavi-macOS-arm64.zip" > "dist/SHA256SUMS.txt"

