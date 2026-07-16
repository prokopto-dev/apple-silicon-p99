#!/bin/bash
# Build FEX 2607's two Wine unixlibs as native ARM64 Mach-O libraries.
# This is a platform-port proof, not yet a runnable Wine/FEX engine.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need clang++
need lipo
verify_checkout "$SOURCE_DIR/fex" "$FEX_COMMIT"

WORK=$BUILD_DIR/darwin-unixlibs
OUT=$STAGE_DIR/darwin-unixlibs
case "$WORK" in "$FEX_EXPERIMENT_CACHE"/*) ;; *) die "unsafe build path: $WORK" ;; esac
rm -rf "$WORK"
mkdir -p "$WORK/Source/Windows" "$OUT"
cp -R "$SOURCE_DIR/fex/Source/Windows/UnixLib" "$WORK/Source/Windows/UnixLib"
patch -s -p1 -d "$WORK" < "$EXPERIMENT_DIR/patches/fex-2607-darwin-unixlib.patch"

for name in wow64fex arm64ecfex; do
  say "Building lib$name.so (ARM64 Mach-O)"
  clang++ -std=c++20 -O2 -arch arm64 -dynamiclib \
    "$WORK/Source/Windows/UnixLib/FEXUnixLib.cpp" \
    -o "$OUT/lib$name.so"
  [ "$(lipo -archs "$OUT/lib$name.so")" = arm64 ] || die "$name output is not ARM64-only"
done

say "Built native unixlib proof artifacts"
file "$OUT"/*.so
