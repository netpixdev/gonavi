#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-whisper.sh
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Gonavi.app"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses" "$APP/Contents/Helpers"
cp .build/whisper/build/bin/whisper-cli "$APP/Contents/Helpers/whisper-cli"
cp .build/whisper/whisper.cpp-*/LICENSE "$APP/Contents/Resources/Licenses/whisper.cpp.txt"
cp packaging/WHISPER-NOTICE.txt "$APP/Contents/Resources/Licenses/NOTICE.txt"
codesign --force --sign - "$APP/Contents/Helpers/whisper-cli"
cp "$BIN_DIR/Gonavi" "$APP/Contents/MacOS/Gonavi"
chmod +x "$APP/Contents/MacOS/Gonavi"
cp packaging/Info.plist "$APP/Contents/Info.plist"
lipo "$APP/Contents/MacOS/Gonavi" -verify_arch "$ARCH"
lipo "$APP/Contents/Helpers/whisper-cli" -verify_arch "$ARCH"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Gonavi-macOS-$ARCH.zip"
shasum -a 256 "dist/Gonavi-macOS-$ARCH.zip" > "dist/SHA256SUMS.txt"
