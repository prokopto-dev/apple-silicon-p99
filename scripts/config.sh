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
# Each big component is pinned by sha256, with an automatic fallback to a
# byte-identical mirror in this project's own GitHub releases. Upstream has
# replaced release assets in-place before (same URL, different bits); the
# checksum catches that and the mirror takes over. When bumping to a new
# upstream version: update URL + sha256 here, upload the new tarball to a
# fresh engine-mirror-N release, and update the mirror URL.
MIRROR_BASE="${MIRROR_BASE:-https://github.com/prokopto-dev/apple-silicon-p99/releases/download/engine-mirror-1}"

# Sikarugir wrapper template (open-source Wineskin successor).
TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz}"
TEMPLATE_MIRROR_URL="${TEMPLATE_MIRROR_URL:-$MIRROR_BASE/Template-1.0.11.tar.xz}"
TEMPLATE_SHA256="${TEMPLATE_SHA256:-9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a}"

# Wine engine: community build of CodeWeavers' LGPL CrossOver 24.0.7 wine source.
# Runs 32-bit Windows apps on Apple Silicon via wine's WoW64 mode + Rosetta 2.
ENGINE_URL="${ENGINE_URL:-https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_6.tar.xz}"
ENGINE_MIRROR_URL="${ENGINE_MIRROR_URL:-$MIRROR_BASE/WS12WineCX24.0.7_6.tar.xz}"
ENGINE_SHA256="${ENGINE_SHA256:-cff03a9e86024464589383a9c1451bd1bb87c783d5753e0a4641fc3af0de8a12}"

# P99's officially-hosted older dsetup.dll (the "V58" build). The dsetup.dll
# shipped inside recent P99Files zips is broken on modern macOS; P99 staff host
# this one as the sanctioned replacement. See docs/HOW-IT-WORKS.md.
DSETUP_URL="${DSETUP_URL:-https://www.project1999.com/files/dsetup.dll}"

# P99 game-files zip. The version number climbs over time; 20-install-game.sh
# probes upward from this floor to find the newest one that exists.
P99FILES_BASE_URL="${P99FILES_BASE_URL:-https://www.project1999.com/files/P99FilesV}"
P99FILES_MIN_VERSION="${P99FILES_MIN_VERSION:-62}"

# md5 of the known-good "V58" dsetup.dll build (see 30-apply-mac-fixes.sh).
GOOD_MD5="${GOOD_MD5:-b02ab111c9b95c2ddad4e3bdbe9c53cd}"

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

# fetch_component <dest> <sha256> <url> [fallback-url ...]
# Downloads from the first source whose contents match the pinned sha256.
# Exists because upstream GitHub release assets have been replaced in-place
# before (same URL, different — broken — bits); the checksum catches that and
# the mirror in our own repo takes over automatically.
fetch_component() {
  local dest="$1" sha="$2" url
  shift 2
  for url in "$@"; do
    say "Downloading $(basename "$dest") from $url"
    if curl -fL --progress-bar -o "$dest" "$url"; then
      if [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sha" ]; then
        return 0
      fi
      warn "checksum mismatch from $url (file changed upstream?) — trying next source"
    else
      warn "download failed from $url — trying next source"
    fi
  done
  die "could not fetch a verified copy of $(basename "$dest") from any source"
}

# --- Idempotency probes -------------------------------------------------------
# One function per "is this piece already done?" check. The install scripts use
# these to skip finished work, and status.sh uses the same functions to report
# state — sharing them keeps the two from drifting.
check_clt()       { xcode-select -p >/dev/null 2>&1; }
check_rosetta()   { [ "$(uname -m)" != "arm64" ] || /usr/bin/pgrep -q oahd; }
check_brew()      { command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; }
check_tools()     { command -v upx >/dev/null 2>&1 && command -v cabextract >/dev/null 2>&1; }
check_wrapper()   { [ -d "$WRAPPER" ]; }
check_engine()    { [ -x "$WINE" ]; }
check_prefix()    { [ -f "$PREFIX/system.reg" ]; }
check_fonts()     { [ -f "$PREFIX/drive_c/windows/Fonts/Arial.TTF" ]; }
check_game()      { [ -f "$GAME_DIR/eqgame.exe" ]; }
p99files_version(){ cat "$GAME_DIR/.p99files-version" 2>/dev/null || echo "none"; }
check_fix_dsetup(){ [ "$(md5 -q "$GAME_DIR/DSETUP.dll" 2>/dev/null)" = "$GOOD_MD5" ]; }
check_fix_dpvs()  { [ -f "$GAME_DIR/dpvs.dll" ] && ! head -c 4096 "$GAME_DIR/dpvs.dll" | grep -q UPX; }
check_fix_ini()   { [ -f "$GAME_DIR/eqclient.ini.pre-mac.bak" ]; }

# Apple's Command Line Tools (~500 MB — NOT the full Xcode app). Needed by
# Homebrew and by the python3/git stubs macOS ships. Triggers Apple's own
# GUI installer and waits for the user to finish it.
ensure_clt() {
  check_clt && return 0
  say "Apple's Command Line Tools are needed (small download — not full Xcode)."
  say "macOS will show an install dialog: click 'Install' and let it finish."
  xcode-select --install 2>/dev/null || true
  until check_clt; do
    printf '.'
    sleep 5
  done
  printf '\n'
  say "Command Line Tools installed."
}
