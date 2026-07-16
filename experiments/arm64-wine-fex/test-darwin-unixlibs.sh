#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need clang++
OUT=$STAGE_DIR/darwin-unixlibs
TEST=$BUILD_DIR/darwin-unixlibs-test
[ -f "$OUT/libwow64fex.so" ] || die "run ./build-darwin-unixlibs.sh first"

say "Building Darwin unixlib runtime probe"
clang++ -std=c++20 -O2 -arch arm64 ./test-darwin-unixlibs.cpp -o "$TEST"
[ "$(lipo -archs "$TEST")" = arm64 ] || die "runtime probe is not ARM64-only"

for library in "$OUT/libwow64fex.so" "$OUT/libarm64ecfex.so"; do
  say "Testing $(basename "$library")"
  "$TEST" "$library"
done
