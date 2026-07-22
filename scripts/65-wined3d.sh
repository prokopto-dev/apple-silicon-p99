#!/bin/bash
# 65-wined3d.sh — fine-tune wine's built-in wined3d renderer (the stock,
# verified path) via its HKCU\Software\Wine\Direct3D registry values. OPT-IN
# and fully reversible: a bare run deletes every value this project manages and
# wined3d falls back to its own defaults.
#
#   P99_WINED3D_CSMT=off ./65-wined3d.sh       # disable the multithreaded command stream
#   P99_WINED3D_MAXGL=2.1 ./65-wined3d.sh      # cap the GL context version (2.1 = legacy)
#   P99_WINED3D_VRAM=512 ./65-wined3d.sh       # report 512 MB of VRAM to the game
#   P99_WINED3D_RENDERER=vulkan ./65-wined3d.sh  # UNVERIFIED escape hatch (see below)
#   ./65-wined3d.sh                            # no vars: back to wine defaults
#
# Like 60-renderer.sh this applies the FULL desired state on every run: any
# knob left unset is reverted. Current state: ./status.sh (wined3d_*), read
# from the prefix's user.reg — the same file the game session's wine loads, so
# what status reports is what the game gets (both the double-click Play launch
# and the --debug run share this prefix; nothing here needs LSEnvironment).
#
# Value semantics verified against the wine-9.0 source (the CrossOver 24
# base); see the wined3d block in config.sh. Two honesty notes:
#   - csmt is ON by default in this wine — the experiment worth running is
#     `off`, which trades peak throughput for pacing on a single-threaded 2005
#     client. `serialize` is a debug mode, not a performance setting.
#   - renderer=vulkan is wined3d's own Vulkan backend (distinct from D9VK). It
#     exists in this wine but has never been verified against the bundled
#     MoltenVK — expect it to fail; it's exposed only so nobody has to patch
#     scripts to test it. renderer=no3d/gdi disable 3D outright and are refused.
#
# These values only matter while wined3d is the active renderer: under d9vk the
# entire wined3d DLL is replaced, so rather than shipping switches that
# silently do nothing there, this script refuses to SET values under d9vk (a
# bare reset run is always allowed, so the GUI's apply-everything pass can
# clean up regardless of renderer).
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

check_engine || die "wrapper not built — run 10-build-wrapper.sh first"
check_prefix || die "wine prefix not initialized — run 10-build-wrapper.sh first"
if pgrep -qf "eqgame.exe"; then die "close EverQuest first, then re-run this"; fi

D3D_KEY='HKCU\Software\Wine\Direct3D'

# Validate every value before touching anything, so a typo dies immediately.
case "$P99_WINED3D_CSMT" in
  ""|on|off|serialize) ;;
  *) die "P99_WINED3D_CSMT must be on, off, serialize, or empty for the wine default (got '$P99_WINED3D_CSMT')" ;;
esac
if [ -n "$P99_WINED3D_MAXGL" ]; then
  case "$P99_WINED3D_MAXGL" in
    [1-9].[0-9]|[1-9].[0-9][0-9]) ;;
    *) die "P99_WINED3D_MAXGL must be a GL version like 2.1 or 4.1 (got '$P99_WINED3D_MAXGL')" ;;
  esac
fi
if [ -n "$P99_WINED3D_VRAM" ]; then
  case "$P99_WINED3D_VRAM" in
    *[!0-9]*) die "P99_WINED3D_VRAM must be a whole number of megabytes (got '$P99_WINED3D_VRAM')" ;;
  esac
fi
case "$P99_WINED3D_RENDERER" in
  ""|gl|vulkan) ;;
  no3d|gdi) die "P99_WINED3D_RENDERER=$P99_WINED3D_RENDERER disables 3D rendering entirely — refusing" ;;
  *) die "P99_WINED3D_RENDERER must be gl or vulkan (got '$P99_WINED3D_RENDERER')" ;;
esac

# Refuse to set values that the active renderer would silently ignore. A bare
# run (nothing requested) still proceeds: it only sweeps our values away.
requested="$P99_WINED3D_CSMT$P99_WINED3D_MAXGL$P99_WINED3D_VRAM$P99_WINED3D_RENDERER"
if [ -n "$requested" ] && [ "$(active_renderer)" != wined3d ]; then
  die "wined3d registry values have no effect under the $(active_renderer) renderer — switch back first: P99_RENDERER=wined3d ./60-renderer.sh"
fi

# Always start from clean wine defaults, then apply exactly what was requested —
# the same reset-then-apply shape as 60-renderer.sh, over the same managed key
# list the tests pin, so apply and revert can never drift apart.
for v in $(wined3d_reg_keys); do
  wine_env "$WINE" reg delete "$D3D_KEY" /v "$v" /f >/dev/null 2>&1 || true
done

if [ -n "$P99_WINED3D_CSMT" ]; then
  case "$P99_WINED3D_CSMT" in
    off)       dw=0 ;;
    on)        dw=1 ;;
    serialize) dw=3 ;;
  esac
  wine_env "$WINE" reg add "$D3D_KEY" /v csmt /t REG_DWORD /d "$dw" /f >/dev/null
  say "wined3d csmt: $P99_WINED3D_CSMT (dword $dw)"
fi

if [ -n "$P99_WINED3D_MAXGL" ]; then
  maj="${P99_WINED3D_MAXGL%%.*}"
  min="${P99_WINED3D_MAXGL#*.}"
  # wine encodes the cap as (major << 16) | minor — GL 4.1 is 0x00040001.
  dw=$(( (maj << 16) | min ))
  wine_env "$WINE" reg add "$D3D_KEY" /v MaxVersionGL /t REG_DWORD /d "$dw" /f >/dev/null
  say "wined3d MaxVersionGL: cap at GL $P99_WINED3D_MAXGL (dword $dw)"
fi

if [ -n "$P99_WINED3D_VRAM" ]; then
  wine_env "$WINE" reg add "$D3D_KEY" /v VideoMemorySize /t REG_SZ /d "$P99_WINED3D_VRAM" /f >/dev/null
  say "wined3d VideoMemorySize: reporting $P99_WINED3D_VRAM MB to the game"
fi

if [ -n "$P99_WINED3D_RENDERER" ]; then
  if [ "$P99_WINED3D_RENDERER" = vulkan ]; then
    warn "renderer=vulkan is UNVERIFIED on this engine's MoltenVK — if the game fails to start, revert with a bare ./65-wined3d.sh"
  fi
  wine_env "$WINE" reg add "$D3D_KEY" /v renderer /t REG_SZ /d "$P99_WINED3D_RENDERER" /f >/dev/null
  say "wined3d renderer backend: $P99_WINED3D_RENDERER"
fi

if [ -n "$requested" ]; then
  say "wined3d tuning applied. Revert everything: ./65-wined3d.sh (no variables). Check: ./status.sh"
else
  say "wined3d tuning reset to wine defaults."
fi
