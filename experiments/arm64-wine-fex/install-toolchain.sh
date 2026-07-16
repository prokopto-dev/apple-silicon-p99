#!/bin/bash
# Download FEX's ARM64EC-capable llvm-mingw build for macOS into the ignored
# experiment cache. Nothing is installed system-wide.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need curl
ARCHIVE=$FEX_EXPERIMENT_CACHE/$TOOLCHAIN_ARCHIVE
UNPACK=$FEX_EXPERIMENT_CACHE/toolchain-unpack

if [ -x "$TOOLCHAIN_DIR/bin/arm64ec-w64-mingw32-clang" ]; then
  say "ARM64EC toolchain already installed in experiment cache"
  exit 0
fi

mkdir -p "$FEX_EXPERIMENT_CACHE"
say "Downloading $TOOLCHAIN_ARCHIVE"
curl -fL --progress-bar -o "$ARCHIVE" "$TOOLCHAIN_URL"
ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
[ "$ACTUAL" = "$TOOLCHAIN_SHA256" ] || die "toolchain checksum mismatch: $ACTUAL"

case "$UNPACK" in "$FEX_EXPERIMENT_CACHE"/*) ;; *) die "unsafe unpack path: $UNPACK" ;; esac
rm -rf "$UNPACK"
mkdir -p "$UNPACK"
say "Extracting verified toolchain"
tar -xf "$ARCHIVE" -C "$UNPACK"
ROOT=$(find "$UNPACK" -mindepth 1 -maxdepth 1 -type d | head -1)
[ -n "$ROOT" ] || die "toolchain archive had no top-level directory"
rm -rf "$TOOLCHAIN_DIR"
mv "$ROOT" "$TOOLCHAIN_DIR"
rm -rf "$UNPACK"

[ -x "$TOOLCHAIN_DIR/bin/arm64ec-w64-mingw32-clang" ] \
  || die "verified archive lacks the ARM64EC compiler"
say "Toolchain ready at $TOOLCHAIN_DIR"
