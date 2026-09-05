#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Upstream b4938, pinned source and integrity. Models are downloaded separately.
REV=371b5a7561823ab2bb32142d2751e35e7534727b
HASH=89051d8fca516a3ad1f5c2f8f9d2fccb089afbaec338fca3f8731999babc6f81
ROOT="$PWD/.build/whisper"
SOURCE="$ROOT/whisper.cpp-$REV"
ARCH="$(uname -m)"
mkdir -p "$ROOT"
if [ ! -f "$SOURCE/CMakeLists.txt" ]; then
  curl --fail --location --retry 3 "https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/$REV" -o "$ROOT/source.tar.gz"
  echo "$HASH  $ROOT/source.tar.gz" | shasum -a 256 -c -
  tar -xzf "$ROOT/source.tar.gz" -C "$ROOT"
fi
METAL=OFF
if [ "$ARCH" = arm64 ]; then METAL=ON; fi
cmake -S "$SOURCE" -B "$ROOT/build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF \
  -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_AVX512=OFF -DGGML_FMA=ON -DGGML_F16C=ON \
  -DGGML_METAL="$METAL" -DGGML_METAL_EMBED_LIBRARY="$METAL" -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple -DWHISPER_CURL=OFF -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=OFF
cmake --build "$ROOT/build" --config Release --target whisper-cli -j 3
lipo "$ROOT/build/bin/whisper-cli" -verify_arch "$ARCH"
# Distribution must not rely on runner-specific Homebrew or build-tree libraries.
otool -L "$ROOT/build/bin/whisper-cli"
if otool -L "$ROOT/build/bin/whisper-cli" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then
  echo 'Unexpected non-system whisper-cli dependency' >&2
  exit 1
fi
