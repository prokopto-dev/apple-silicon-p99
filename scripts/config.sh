# shellcheck shell=bash
# Shared configuration for all p99-mac scripts. Override any value via environment.
#
# Everything here was verified working 2026-07-13 on an Apple M3, macOS 26.5.

# Where the finished wrapper app goes.
WRAPPER="${WRAPPER:-/Applications/P99.app}"

# Where your EverQuest game files live (the wrapper symlinks to this, so the
# game stays outside the .app and survives wrapper rebuilds).
GAME_DIR="${GAME_DIR:-$HOME/Games/EverQuest}"

# --- Pinned component versions (known-good together) -------------------------
# Sikarugir wrapper template (open-source Wineskin successor).
TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz}"

# Wine engine: community build of CodeWeavers' LGPL CrossOver 24.0.7 wine source.
# Runs 32-bit Windows apps on Apple Silicon via wine's WoW64 mode + Rosetta 2.
ENGINE_URL="${ENGINE_URL:-https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_6.tar.xz}"

# P99's officially-hosted older dsetup.dll (the "V58" build). The dsetup.dll
# shipped inside recent P99Files zips is broken on modern macOS; P99 staff host
# this one as the sanctioned replacement. See docs/HOW-IT-WORKS.md.
DSETUP_URL="${DSETUP_URL:-https://www.project1999.com/files/dsetup.dll}"

# P99 game-files zip. The version number climbs over time; 20-install-game.sh
# probes upward from this floor to find the newest one that exists.
P99FILES_BASE_URL="${P99FILES_BASE_URL:-https://www.project1999.com/files/P99FilesV}"
P99FILES_MIN_VERSION="${P99FILES_MIN_VERSION:-62}"

# --- Derived paths (don't edit) ----------------------------------------------
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
WINE="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
FRAMEWORKS="$WRAPPER/Contents/Frameworks"
GAME_LINK="$PREFIX/drive_c/Program Files/EverQuest"

# Env every direct wine invocation needs. DYLD_FALLBACK_LIBRARY_PATH lets the
# engine find FreeType/libinotify/etc. shipped inside the wrapper's Frameworks.
wine_env() {
  env WINEPREFIX="$PREFIX" \
      WINEESYNC=1 WINEMSYNC=1 \
      DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS:/usr/lib" \
      "$@"
}

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
