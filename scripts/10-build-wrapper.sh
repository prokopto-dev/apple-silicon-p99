#!/bin/bash
# 10-build-wrapper.sh — assemble the P99.app wine wrapper from scratch:
# Sikarugir template + WineCX engine, then initialize the wine prefix.
# Idempotent: skips pieces that already exist; delete $WRAPPER to rebuild clean.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! check_wrapper; then
  fetch_component "$TMP/template.tar.xz" "$TEMPLATE_SHA256" "$TEMPLATE_URL" "$TEMPLATE_MIRROR_URL"
  say "Extracting template -> $WRAPPER"
  mkdir -p "$TMP/t" && tar -xf "$TMP/template.tar.xz" -C "$TMP/t"
  # The tarball contains a single .app bundle (name varies by template version).
  APP=$(find "$TMP/t" -maxdepth 2 -name "*.app" -type d | head -1)
  [ -n "$APP" ] || die "no .app found inside template tarball"
  mv "$APP" "$WRAPPER"
else
  say "Wrapper already exists at $WRAPPER — keeping it"
fi

if ! check_engine; then
  fetch_component "$TMP/engine.tar.xz" "$ENGINE_SHA256" "$ENGINE_URL" "$ENGINE_MIRROR_URL"
  say "Extracting engine -> Contents/SharedSupport/wine"
  mkdir -p "$TMP/e" && tar -xf "$TMP/engine.tar.xz" -C "$TMP/e"
  [ -d "$TMP/e/wswine.bundle" ] || die "engine tarball missing wswine.bundle"
  # IMPORTANT: engine must live at SharedSupport/wine, NOT Frameworks/wswine.bundle
  # (the launcher SDK throws WineAppInitializationError/wineFolderNotFound otherwise).
  rm -rf "$WRAPPER/Contents/SharedSupport/wine"
  mkdir -p "$WRAPPER/Contents/SharedSupport"
  mv "$TMP/e/wswine.bundle" "$WRAPPER/Contents/SharedSupport/wine"
else
  say "Engine already installed: $("$WINE" --version 2>/dev/null | head -1 || echo present)"
fi

say "Stripping macOS quarantine attributes (Gatekeeper would block the unsigned engine)"
xattr -dr com.apple.quarantine "$WRAPPER" 2>/dev/null || true

# macOS 26 (Tahoe) dyld refuses executables that were built against SDK >= 26
# yet link no dylibs: "missing LC_LOAD_DYLIB (must link with at least
# libSystem.dylib)", Abort trap: 6. Some engine builds ship exactly such a
# wine-preloader (it's deliberately freestanding — its whole job is reserving
# the low 32-bit address range before wine starts, and eqgame.exe cannot map
# at its fixed 0x400000 base without it, failing with STATUS c0000018).
# Rewriting the SDK stamp to pre-26 makes dyld accept it as a legacy binary.
# Upstream: https://github.com/Sikarugir-App/Sikarugir/issues/130
# Runs on every invocation; no-op once the stamp reads < 26.
PRELOADER="$WRAPPER/Contents/SharedSupport/wine/bin/wine-preloader"
preloader_sdk() {
  otool -l "$PRELOADER" 2>/dev/null \
    | awk '/LC_VERSION_MIN_MACOSX|LC_BUILD_VERSION/{f=1} f && $1=="sdk"{print $2; exit}'
}
if [ -f "$PRELOADER" ] \
   && ! otool -l "$PRELOADER" 2>/dev/null | grep -q 'LC_LOAD_DYLIB$' \
   && [ "$(preloader_sdk | cut -d. -f1)" -ge 26 ] 2>/dev/null; then
  say "Patching wine-preloader SDK stamp (macOS 26's dyld rejects it as shipped)"
  xcrun vtool -set-version-min macos 10.7 15.0 -replace -output "$PRELOADER" "$PRELOADER" 2>/dev/null
  codesign -f -s - "$PRELOADER" 2>/dev/null || true
fi

say "Configuring Info.plist (what to run when the app is double-clicked)"
plutil -replace "Program Name and Path" -string "/Program Files/EverQuest/eqgame.exe" "$WRAPPER/Contents/Info.plist"
plutil -replace "Program Flags" -string "patchme" "$WRAPPER/Contents/Info.plist"
plutil -replace CFBundleName -string "P99" "$WRAPPER/Contents/Info.plist" 2>/dev/null || true

# Make wine's msync scheduling actually reach the double-click / Play session.
# `open "$WRAPPER"` launches detached via LaunchServices and does NOT inherit the
# shell env, so the WINEESYNC/WINEMSYNC in wine_env() never touched the real game;
# LSEnvironment injects them into the bundle's launch environment instead. Cheap,
# reversible, idempotent. Full rationale in docs/PERFORMANCE.md.
say "Enabling wine msync for the game session (Info.plist LSEnvironment)"
apply_wrapper_sync

# The engine's binaries find their bundled dylibs via @rpath = bin/../../,
# which is Contents/SharedSupport/ after the engine move above — but the
# template ships the dylibs in Contents/Frameworks. Link them across, or
# wineserver dies with "Library not loaded: @rpath/libinotify.0.dylib"
# (DYLD_FALLBACK_LIBRARY_PATH does not survive into wine's child processes).
say "Linking engine libraries into SharedSupport (engine rpath expects them there)"
for lib in "$FRAMEWORKS"/*.dylib; do
  ln -sf "../Frameworks/$(basename "$lib")" "$WRAPPER/Contents/SharedSupport/$(basename "$lib")"
done

# The loop above just pointed libMoltenVK.dylib at the stock build. If this is a
# rebuild of a wrapper whose prefix already has d9vk applied (the prefix — and
# with it the renderer marker — survives rebuilds), re-pair it with the CX
# MoltenVK; on a fresh wrapper the marker is absent and this is a no-op.
sync_moltenvk_to_renderer

if ! check_prefix; then
  say "Initializing wine prefix (first run; takes a minute)"
  wine_env "$WINE" wineboot -i
else
  say "Wine prefix already initialized"
fi

say "Setting Windows version to XP (part of the working recipe)"
wine_env "$WINE" reg add 'HKCU\Software\Wine' /v Version /d winxp /f >/dev/null

# Microsoft core fonts (Arial etc.). EQ rasterizes its UI text through Windows
# font APIs; without the real fonts wine substitutes lookalikes and chunks of
# the UI render fuzzy. Done manually rather than via `winetricks corefonts`
# because macOS SIP strips DYLD_* env vars through winetricks' /bin/sh,
# breaking wine invocation inside it. Wine auto-loads everything in Fonts/.
FONTS_DIR="$PREFIX/drive_c/windows/Fonts"
if check_fonts; then
  say "MS core fonts already installed"
else
  say "Installing MS core fonts (crisp UI text)"
  mkdir -p "$FONTS_DIR" "$TMP/fonts"
  for f in arial32 arialb32 comic32 courie32 georgi32 impact32 times32 trebuc32 verdan32 webdin32; do
    curl -sfL -o "$TMP/fonts/$f.exe" "https://downloads.sourceforge.net/corefonts/$f.exe" \
      && (cd "$TMP/fonts" && cabextract -q "$f.exe" >/dev/null 2>&1) \
      || warn "could not fetch/extract $f — continuing"
  done
  cp "$TMP"/fonts/*.ttf "$TMP"/fonts/*.TTF "$FONTS_DIR/" 2>/dev/null || true
  say "  installed $(ls "$FONTS_DIR" | wc -l | tr -d ' ') font files"
fi

# Keep Contents/drive_c as a convenience symlink into the prefix, as the
# template expects.
if [ ! -e "$WRAPPER/Contents/drive_c" ]; then
  ln -s "SharedSupport/prefix/drive_c" "$WRAPPER/Contents/drive_c"
fi

say "Wrapper built. Next: ./20-install-game.sh /path/to/your/EverQuest-Titanium-install"
