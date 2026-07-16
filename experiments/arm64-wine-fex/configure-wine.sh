#!/bin/bash
# Configure the FEX-recommended Wine fork as a native ARM64 macOS host with
# ARM64EC and i386 PE support. This does not touch Homebrew's Wine install.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need clang
need make
need bison
need flex
verify_checkout "$SOURCE_DIR/wine" "$WINE_COMMIT"

WINE_BUILD=$BUILD_DIR/wine-native
WINE_STAGE=$STAGE_DIR/wine-native
mkdir -p "$WINE_BUILD" "$WINE_STAGE"

say "Configuring native ARM64 macOS Wine with ARM64EC + i386 support"
cd "$WINE_BUILD"
"$SOURCE_DIR/wine/configure" \
  --prefix="$WINE_STAGE" \
  --enable-archs=arm64ec,aarch64,i386 \
  --with-mingw=clang \
  --disable-tests

say "Wine configuration complete at $WINE_BUILD"
