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

# --- Performance tuning (all opt-in) -----------------------------------------
# Every knob below defaults to "unset", so the proven config is byte-identical
# for anyone who does not opt in. Nothing here ever changes resolution. Full
# explanation of what each does — and what actually helps M-series stutter —
# lives in docs/PERFORMANCE.md.
#
# Renderer applied by 60-renderer.sh: wined3d (default) | d9vk | d3dmetal | dxmt.
P99_RENDERER="${P99_RENDERER:-}"
# EQ eqclient.ini graphics knobs, applied by 30-apply-mac-fixes.sh (fresh
# installs) and 35-perf-ini.sh (existing installs). Empty = leave EQ's default.
EQ_FARCLIP="${EQ_FARCLIP:-}"            # FarClipPlane: view distance (lower = smoother)
EQ_SPELL_PARTICLES="${EQ_SPELL_PARTICLES:-}"  # SpellParticleDensity (lower = fewer)
EQ_ENV_PARTICLES="${EQ_ENV_PARTICLES:-}"      # EnvironmentParticleDensity
EQ_FPS_CAP="${EQ_FPS_CAP:-}"           # MaxFPS/MaxBGFPS frame cap (steadier pacing)
# Convenience bundle of conservative values; individual EQ_* vars override it.
P99_PERF_PROFILE="${P99_PERF_PROFILE:-}"      # "smoother" or empty
# d9vk diagnostics + experiments, read by 60-renderer.sh when applying d9vk.
P99_RENDERER_DEBUG="${P99_RENDERER_DEBUG:-}"  # 1 = verbose DXVK/MoltenVK logs in-game
P99_DXVK_HUD="${P99_DXVK_HUD:-}"              # DXVK_HUD value, e.g. "fps,frametimes"
P99_DXVK_INDIRECT_MAPS="${P99_DXVK_INDIRECT_MAPS:-}"  # 1 = route buffer locks around the WoW64 map path

# --- Derived paths (don't edit) ----------------------------------------------
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
WINE="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
FRAMEWORKS="$WRAPPER/Contents/Frameworks"
GAME_LINK="$PREFIX/drive_c/Program Files/EverQuest"
RENDERER_DIR="$FRAMEWORKS/renderer"                 # bundled alt-renderer DLL sets
SYSWOW64="$PREFIX/drive_c/windows/syswow64"         # where the active d3d9.dll lives
RENDERER_MARKER="$PREFIX/.p99-renderer"             # records the active renderer name
# The engine's winevulkan resolves MoltenVK through the @rpath symlink that
# 10-build-wrapper.sh creates in SharedSupport. The template ships TWO builds:
# the stock one, and CodeWeavers' patched build (moltenvkcx/) — the only one the
# bundled DXVK 1.10 was ever built/tested against. 60-renderer.sh points the
# symlink at whichever matches the active renderer.
MOLTENVK_LINK="$WRAPPER/Contents/SharedSupport/libMoltenVK.dylib"
MOLTENVK_STOCK_REL="../Frameworks/libMoltenVK.dylib"
MOLTENVK_CX_REL="../Frameworks/moltenvkcx/libMoltenVK.dylib"
# The indirect-buffer-maps experiment's DXVK config file. It lives in the
# wrapper's drive_c (NOT the user's game dir) and is handed to the DLL via the
# DXVK_CONFIG_FILE env var as a Windows path, so this project never has to put
# state files next to the user's game.
DXVK_CONF="$PREFIX/drive_c/dxvk-p99.conf"
DXVK_CONF_WIN='C:\dxvk-p99.conf'

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

# --- Performance helpers ------------------------------------------------------
# The double-click / Play launch is `open "$WRAPPER"` (40-launch.sh), which
# LaunchServices runs DETACHED — it does not inherit the shell environment, so
# the WINEESYNC/WINEMSYNC that wine_env() sets never reach that gameplay session.
# `LSEnvironment` is Apple's documented Launch Services Info.plist key for exactly
# this: the vars it lists are placed in the bundle's environment when it is opened,
# and wine inherits them. That is how sync (and any must-reach-the-game env) is
# delivered to the real play path. See docs/PERFORMANCE.md.
plist_path() { echo "$WRAPPER/Contents/Info.plist"; }

# set_plist_env KEY VALUE — set one LSEnvironment var, preserving any others.
set_plist_env() {
  local p; p="$(plist_path)"
  [ -f "$p" ] || return 0
  # Create LSEnvironment only if absent — `json` output works for a dict (unlike
  # `raw`), so an existing dict is detected and never clobbered.
  plutil -extract LSEnvironment json -o - "$p" >/dev/null 2>&1 \
    || plutil -replace LSEnvironment -json '{}' "$p" >/dev/null 2>&1 || return 0
  plutil -replace "LSEnvironment.$1" -string "$2" "$p" >/dev/null 2>&1 || true
}

# remove_plist_env KEY — remove one LSEnvironment var, leaving the rest (and the
# dict itself) in place. Graceful no-op when the plist, dict, or key is absent.
remove_plist_env() {
  local p; p="$(plist_path)"
  [ -f "$p" ] && plutil -remove "LSEnvironment.$1" "$p" >/dev/null 2>&1 || true
}

# apply_wrapper_sync — make WINEESYNC/WINEMSYNC actually reach the open-launched
# game. WINEMSYNC (mach semaphores) is the macOS payload; WINEESYNC is Linux-native
# and effectively ignored on macOS but set for parity. WINEFSYNC is Linux-only and
# is deliberately NOT set. Idempotent.
apply_wrapper_sync() {
  set_plist_env WINEESYNC 1
  set_plist_env WINEMSYNC 1
}

# set_plist_flag / remove_plist_flag — top-level flags such as the Sikarugir
# renderer toggles (D9VK/DXMT/D3DMETAL). Written as -integer because that is the
# type the template ships (`D9VK = 0`, `MOLTENVKCX = 1`, …) and the launcher's
# typed Swift decode silently drops a string "1". Graceful no-op if unsupported.
set_plist_flag()    { local p; p="$(plist_path)"; [ -f "$p" ] && plutil -replace "$1" -integer "$2" "$p" >/dev/null 2>&1 || true; }
remove_plist_flag() { local p; p="$(plist_path)"; [ -f "$p" ] && plutil -remove  "$1"            "$p" >/dev/null 2>&1 || true; }

# Which renderer is active (recorded by 60-renderer.sh; default is the stock path).
active_renderer() { cat "$RENDERER_MARKER" 2>/dev/null || echo wined3d; }

# set_moltenvk cx|stock — retarget the SharedSupport @rpath symlink so the engine
# loads the chosen MoltenVK build. The CX build (moltenvkcx/) is the one the
# bundled DXVK 1.10 was built for; the stock build is years newer and defaults
# Metal argument buffers ON — a documented DXVK performance cliff. Keeps stock
# (with a warning) if the template has no CX build; the argument-buffer env in
# apply_d9vk_env still protects that case.
set_moltenvk() {
  [ -d "$WRAPPER/Contents/SharedSupport" ] || return 0
  local target="$MOLTENVK_STOCK_REL"
  if [ "$1" = cx ]; then
    if [ -f "$FRAMEWORKS/moltenvkcx/libMoltenVK.dylib" ]; then
      target="$MOLTENVK_CX_REL"
    else
      warn "CX-patched MoltenVK not found in this template — keeping stock (argument buffers still disabled via env)"
    fi
  fi
  ln -sf "$target" "$MOLTENVK_LINK"
}

# Which MoltenVK build the engine will load: cx | stock | n/a (status.sh, tests).
active_moltenvk() {
  [ -L "$MOLTENVK_LINK" ] || { echo n/a; return 0; }
  case "$(readlink "$MOLTENVK_LINK")" in *moltenvkcx*) echo cx ;; *) echo stock ;; esac
}

# sync_moltenvk_to_renderer — converge the symlink with the recorded renderer.
# Called by 60-renderer.sh on every switch AND by 10-build-wrapper.sh after its
# dylib-link loop, which would otherwise silently reset a d9vk install back to
# the stock MoltenVK on any rebuild.
sync_moltenvk_to_renderer() {
  if [ "$(active_renderer)" = d9vk ]; then set_moltenvk cx; else set_moltenvk stock; fi
}

# --- d9vk LSEnvironment bundle ------------------------------------------------
# Everything here rides the same LSEnvironment channel as apply_wrapper_sync so
# it reaches the real double-click session. WINEESYNC/WINEMSYNC are deliberately
# NOT in this list — they are renderer-independent and owned by apply_wrapper_sync.

# d9vk_env_keys — every LSEnvironment key this project may set for the d9vk
# renderer (tuning + diagnostics), one per line. Reverting removes exactly these,
# so apply and remove can never drift apart.
d9vk_env_keys() {
  cat <<'EOF'
MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS
MVK_CONFIG_FAST_MATH_ENABLED
MVK_CONFIG_RESUME_LOST_DEVICE
DXVK_ASYNC
DXVK_LOG_LEVEL
MVK_CONFIG_LOG_LEVEL
DXVK_HUD
DXVK_CONFIG_FILE
EOF
}

# apply_d9vk_env — tuning always; diagnostics only when opted in. The diagnostic
# keys are cleared on every renderer switch (60-renderer.sh starts from
# remove_d9vk_env), so re-running with/without P99_RENDERER_DEBUG / P99_DXVK_HUD
# is the toggle in both directions.
apply_d9vk_env() {
  # Newer stock MoltenVK (>= 1.2.11) turns Metal argument buffers on by default;
  # with DXVK that is a large, documented slowdown. Force off.
  set_plist_env MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS 0
  set_plist_env MVK_CONFIG_FAST_MATH_ENABLED 1
  set_plist_env MVK_CONFIG_RESUME_LOST_DEVICE 1
  # The bundled DLL is the dxvk-*async* build; without this switch the async
  # patch is dormant and every shader compiles on the render thread.
  set_plist_env DXVK_ASYNC 1
  if [ "${P99_RENDERER_DEBUG:-}" = 1 ]; then
    set_plist_env DXVK_LOG_LEVEL info
    set_plist_env MVK_CONFIG_LOG_LEVEL 2
  fi
  if [ -n "${P99_DXVK_HUD:-}" ] && [ "$P99_DXVK_HUD" != 0 ]; then
    set_plist_env DXVK_HUD "$P99_DXVK_HUD"
  fi
}

remove_d9vk_env() {
  local k
  for k in $(d9vk_env_keys); do remove_plist_env "$k"; done
}

# --- Indirect buffer maps (d9vk experiment) -----------------------------------
# Why this knob exists: a 32-bit game under wine's WoW64 pays a heavy toll on
# GPU-memory maps because the bundled MoltenVK lacks VK_EXT_map_memory_placed.
# DXVK's `d3d9.allowDirectBufferMapping = False` reroutes the game's buffer
# locks through DXVK-owned CPU memory instead of directly-mapped Vulkan memory —
# trading some CPU copying for staying off that expensive map path. Opt-in
# because on machines where the map path is cheap the copies are pure overhead.

# The first line doubles as the ownership marker: the remove path only deletes a
# file that carries it, so a hand-written conf at the same path is never clobbered.
DXVK_CONF_MARKER='# Managed by p99-mac (60-renderer.sh) — safe to delete; re-applying recreates it.'

apply_dxvk_conf() {
  if [ -f "$DXVK_CONF" ] && [ "$(head -1 "$DXVK_CONF")" != "$DXVK_CONF_MARKER" ]; then
    warn "$DXVK_CONF exists but isn't ours — leaving it alone (your settings win)"
  else
    cat > "$DXVK_CONF" <<EOF
$DXVK_CONF_MARKER
# Route D3D9 buffer locks through DXVK-owned memory instead of directly-mapped
# Vulkan memory: costs some CPU copying, avoids the WoW64 32-bit map path.
# See docs/PERFORMANCE.md ("Indirect buffer maps").
d3d9.allowDirectBufferMapping = False
EOF
  fi
  set_plist_env DXVK_CONFIG_FILE "$DXVK_CONF_WIN"
}

# Delete the conf only if we wrote it (marker check); the DXVK_CONFIG_FILE env
# key is removed separately by remove_d9vk_env, which owns the whole key list.
remove_dxvk_conf() {
  [ -f "$DXVK_CONF" ] || return 0
  if [ "$(head -1 "$DXVK_CONF")" = "$DXVK_CONF_MARKER" ]; then rm -f "$DXVK_CONF"; fi
}

# Whether the eqclient.ini performance keys are currently applied. Sentinel set by
# 35-perf-ini.sh on apply and removed on revert; separate from eqclient.ini.perf.bak
# (a permanent one-time safety copy) so status reflects the live state.
check_perf_ini()  { [ -f "$GAME_DIR/.p99-perf-applied" ]; }

# --- EQ eqclient.ini performance keys (shared by 30-apply-mac-fixes.sh and
# 35-perf-ini.sh) ------------------------------------------------------------
# All are [Defaults] keys. EQ silently ignores any key it doesn't recognize and
# regenerates unset keys at its own default, so applying and reverting these is
# safe and non-destructive. Resolution/window keys are intentionally absent —
# they are never touched. EQ's in-game Options window is the authoritative place
# to tune these; the keys give a repeatable scripted default.

# perf_ini_managed_keys — the exact keys this project may set, one per line.
# Reverting means deleting exactly these, leaving every other key untouched.
perf_ini_managed_keys() {
  cat <<'EOF'
FarClipPlane
SpellParticleDensity
EnvironmentParticleDensity
WaterSpecular
HeatShimmer
MaxFPS
MaxBGFPS
EOF
}

# perf_ini_lines — the KEY=VALUE lines to apply for the current env. No output
# means "apply nothing". The `smoother` profile supplies conservative defaults;
# any explicit EQ_* var overrides the profile value for that key.
perf_ini_lines() {
  local smoother="" spell="$EQ_SPELL_PARTICLES" env_p="$EQ_ENV_PARTICLES"
  [ "$P99_PERF_PROFILE" = "smoother" ] && smoother=1
  if [ -n "$smoother" ]; then
    [ -n "$spell" ] || spell=64
    [ -n "$env_p" ] || env_p=64
  fi
  [ -n "$EQ_FARCLIP" ] && printf 'FarClipPlane=%s\n' "$EQ_FARCLIP"
  [ -n "$spell" ]      && printf 'SpellParticleDensity=%s\n' "$spell"
  [ -n "$env_p" ]      && printf 'EnvironmentParticleDensity=%s\n' "$env_p"
  if [ -n "$smoother" ]; then
    printf 'WaterSpecular=FALSE\n'
    printf 'HeatShimmer=FALSE\n'
  fi
  if [ -n "$EQ_FPS_CAP" ]; then
    printf 'MaxFPS=%s\n'   "$EQ_FPS_CAP"
    printf 'MaxBGFPS=%s\n' "$EQ_FPS_CAP"
  fi
  return 0
}

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
