#!/bin/bash
# Build and stage the already-configured native Wine tree.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need make
WINE_BUILD=$BUILD_DIR/wine-native
[ -f "$WINE_BUILD/Makefile" ] || die "run ./configure-wine.sh first"
JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || true)
JOBS=${JOBS:-4}

say "Building native ARM64 Wine"
make -C "$WINE_BUILD" -j"$JOBS"
say "Installing Wine into experiment stage"
make -C "$WINE_BUILD" install

WINE_BIN=$STAGE_DIR/wine-native/bin/wine
[ -x "$WINE_BIN" ] || die "Wine install did not produce $WINE_BIN"
[ "$(lipo -archs "$WINE_BIN")" = arm64 ] || die "Wine host is not ARM64-only"
say "Built native ARM64 Wine host"
file "$WINE_BIN"
