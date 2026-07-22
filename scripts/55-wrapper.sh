#!/bin/bash
# 55-wrapper.sh — wrapper-level knobs that sit ABOVE the renderer: display
# scaling (Retina/HiDPI) and Apple's Metal performance HUD. Because they live in
# the wrapper bundle rather than the D3D path, they apply on every renderer
# (wined3d and D9VK alike) and on both engine stacks. OPT-IN and fully
# reversible.
#
#   P99_HIDPI=off ./55-wrapper.sh      # render at 1x — the wined3d fill-rate win
#   P99_HIDPI=on  ./55-wrapper.sh      # force Retina-scale rendering
#   P99_METAL_HUD=1 ./55-wrapper.sh    # Apple's Metal HUD overlay (diagnostics)
#   ./55-wrapper.sh                    # no vars: restore the template defaults
#
# Like 60-renderer.sh this applies the FULL desired state on every run: any knob
# left unset is reverted, so re-running with exactly the vars you want is the
# toggle in both directions. Current state: ./status.sh (hidpi, metal_hud).
#
# Why display scaling matters here: on a Retina panel the wrapper can render at
# 2x linear scale — roughly four times the pixels per frame — and on the stock
# wined3d path every one of those pixels crosses Apple's deprecated GL-on-Metal
# shim, whose weakest axis is exactly fill rate. Rendering at 1x and letting
# macOS scale the window up is the single biggest fill-rate cut available
# without touching the game's own settings. Full tradeoffs: docs/PERFORMANCE.md.
#
# The knob has two halves that must move together (Wineskin lineage):
#   1. NSHighResolutionCapable (bundle Info.plist) — whether macOS gives the app
#      a Retina backing store at all, or renders at 1x and upscales.
#   2. HKCU\Software\Wine\Mac Driver\RetinaMode (wine registry) — whether
#      winemac.drv sizes its surfaces in physical pixels ("y") or points.
# The template's original plist value is captured once (.p99-hidpi-stock) before
# we first touch it, so "no vars" restores the exact shipped state — including
# templates that ship no key at all.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

check_wrapper || die "wrapper not built — run 10-build-wrapper.sh first"
check_prefix  || die "wine prefix not initialized — run 10-build-wrapper.sh first"
if pgrep -qf "eqgame.exe"; then die "close EverQuest first, then re-run this"; fi

# Validate before touching anything, so a typo dies immediately.
case "$P99_HIDPI" in
  ""|on|off) ;;
  *) die "P99_HIDPI must be on, off, or empty for the template default (got '$P99_HIDPI')" ;;
esac
case "$P99_METAL_HUD" in
  ""|0|1) ;;
  *) die "P99_METAL_HUD must be 1, 0, or empty (got '$P99_METAL_HUD')" ;;
esac

MAC_DRIVER_KEY='HKCU\Software\Wine\Mac Driver'

# --- Display scaling ----------------------------------------------------------
if [ -n "$P99_HIDPI" ]; then
  # Capture the template's shipped plist value exactly once, before the first
  # modification — the same backup-once contract as the renderer's d3d9 swap.
  [ -f "$HIDPI_STOCK" ] || hidpi_plist_value > "$HIDPI_STOCK"
  if [ "$P99_HIDPI" = on ]; then
    set_plist_bool NSHighResolutionCapable true
    wine_env "$WINE" reg add "$MAC_DRIVER_KEY" /v RetinaMode /d y /f >/dev/null
    echo on > "$HIDPI_MARKER"
    say "Display scaling: Retina (HiDPI) forced ON — winemac.drv renders in physical pixels."
    warn "the game's Width/Height now mean physical pixels, so the window will look half its previous size — raise them to compensate (docs/FAQ.md)"
  else
    set_plist_bool NSHighResolutionCapable false
    wine_env "$WINE" reg delete "$MAC_DRIVER_KEY" /v RetinaMode /f >/dev/null 2>&1 || true
    echo off > "$HIDPI_MARKER"
    say "Display scaling: rendering at 1x — macOS scales the window up (the wined3d fill-rate win)."
  fi
else
  # Revert to the exact shipped state: restore the captured plist value (or
  # remove the key if the template never had one) and drop our registry half.
  if [ -f "$HIDPI_STOCK" ]; then
    case "$(cat "$HIDPI_STOCK")" in
      true)  set_plist_bool NSHighResolutionCapable true ;;
      false) set_plist_bool NSHighResolutionCapable false ;;
      *)     remove_plist_flag NSHighResolutionCapable ;;
    esac
    rm -f "$HIDPI_STOCK"
    say "Display scaling: restored the template default."
  fi
  wine_env "$WINE" reg delete "$MAC_DRIVER_KEY" /v RetinaMode /f >/dev/null 2>&1 || true
  rm -f "$HIDPI_MARKER"
fi

# --- Metal performance HUD ----------------------------------------------------
# MTL_HUD_ENABLED works on any Metal-backed process (macOS 13+), which includes
# the GL-on-Metal shim wined3d renders through — giving the stock path the
# frametime overlay it never had (the DXVK HUD only exists under d9vk). Rides
# the same LSEnvironment channel as msync so it reaches the detached session.
if [ "$P99_METAL_HUD" = 1 ]; then
  set_plist_env MTL_HUD_ENABLED 1
  : > "$METAL_HUD_MARKER"
  say "Metal performance HUD ON (top-right overlay: FPS, frame times, GPU time)."
else
  remove_plist_env MTL_HUD_ENABLED
  rm -f "$METAL_HUD_MARKER"
fi

# Plist edits are done — poke LaunchServices so the next `open` sees them
# (it caches Info.plist; NSHighResolutionCapable especially needs the nudge).
refresh_launch_services

say "Wrapper knobs applied. Revert everything: ./55-wrapper.sh (no variables)."
