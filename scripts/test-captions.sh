#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/Gonavi.app/Contents/MacOS/Gonavi
SOURCE=.build/whisper/whisper.cpp-371b5a7561823ab2bb32142d2751e35e7534727b
"$APP" --caption-smoke-test dist/smoke/captions-en "$SOURCE/samples/jfk.wav" en
# Turkish system speech is a deterministic integration fixture, not human-speech WER evidence.
if say -v '?' | grep -q '^Yelda '; then
  say -v Yelda -r 145 -o dist/turkish.aiff 'Merhaba. Bugün Türkçe bir video hazırlıyoruz. Otomatik altyazı ile çalışmak çok kolay.'
  "$APP" --caption-smoke-test dist/smoke/captions-tr dist/turkish.aiff tr
else
  echo 'Turkish synthetic voice unavailable on this runner; Turkish ASR acceptance remains pending.' | tee dist/smoke/turkish-voice-unavailable.txt
fi
