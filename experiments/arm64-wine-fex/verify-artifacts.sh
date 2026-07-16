#!/bin/bash
# Fail closed unless all four FEX/Wine boundary artifacts have the intended
# host/PE architecture and the native unixlibs export Wine's call table.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need lipo
need nm
need llvm-readobj

UNIX=$STAGE_DIR/darwin-unixlibs
WINDOWS=$STAGE_DIR/fex-windows/lib/wine/aarch64-windows

for name in wow64fex arm64ecfex; do
  library=$UNIX/lib$name.so
  [ -f "$library" ] || die "missing $library"
  [ "$(lipo -archs "$library")" = arm64 ] || die "$library is not ARM64-only"
  nm -gU "$library" | grep -q '___wine_unix_call_funcs$' \
    || die "$library does not export __wine_unix_call_funcs"
  say "verified native ARM64 lib$name.so"
done

machine() {
  llvm-readobj --file-headers "$1" | awk '/Machine:/{print $2; exit}'
}

[ "$(machine "$WINDOWS/libwow64fex.dll")" = IMAGE_FILE_MACHINE_ARM64 ] \
  || die "libwow64fex.dll has the wrong PE machine"
[ "$(machine "$WINDOWS/libarm64ecfex.dll")" = IMAGE_FILE_MACHINE_ARM64EC ] \
  || die "libarm64ecfex.dll has the wrong PE machine"
say "verified PE ARM64 libwow64fex.dll"
say "verified PE ARM64EC libarm64ecfex.dll"

shasum -a 256 \
  "$UNIX/libwow64fex.so" "$UNIX/libarm64ecfex.so" \
  "$WINDOWS/libwow64fex.dll" "$WINDOWS/libarm64ecfex.dll"
