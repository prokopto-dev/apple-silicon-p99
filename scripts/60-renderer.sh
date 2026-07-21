#!/bin/bash
# 60-renderer.sh — switch the Direct3D renderer the game uses. OPT-IN and fully
# reversible: switching back to wined3d restores the exact stock state and leaves
# everything else (prefix, eqclient.ini, keybinds) untouched.
#
#   ./60-renderer.sh                 # show the active renderer
#   P99_RENDERER=d9vk    ./60-renderer.sh   # D3D9 -> Vulkan -> MoltenVK -> Metal
#   P99_RENDERER=wined3d ./60-renderer.sh   # back to the stock renderer
#   ./60-renderer.sh d9vk            # (renderer may also be given as an argument)
#
# Why: the stock wined3d path is D3D9 -> OpenGL -> Apple's deprecated GL-on-Metal
# shim, the biggest source of stutter on newer Apple Silicon. D9VK skips OpenGL.
# See docs/PERFORMANCE.md.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

renderer="${1:-${P99_RENDERER:-}}"

# No renderer given: report the current one and how to change it.
if [ -z "$renderer" ]; then
  say "Active renderer: $(active_renderer)"
  echo "  change with:  P99_RENDERER=d9vk ./60-renderer.sh   (or wined3d to revert)"
  exit 0
fi

check_engine || die "wrapper not built — run 10-build-wrapper.sh first"
check_prefix || die "wine prefix not initialized — run 10-build-wrapper.sh first"
# Editing the prefix while the game is running corrupts it (same reason the INI
# must be edited game-closed).
if pgrep -qf "eqgame.exe"; then die "close EverQuest first, then re-run this"; fi

STOCK_BAK="$SYSWOW64/d3d9.dll.wined3d.bak"   # stock d3d9.dll, saved on first swap
STOCK_ABSENT="$SYSWOW64/.d3d9-was-absent"    # marker: stock used wine's builtin (no file)

# Return the D3D9 DLL + wine override to the exact stock state. Idempotent — a
# no-op when already stock (no backup/marker present).
revert_d3d9_to_stock() {
  if [ -f "$STOCK_BAK" ]; then
    mv -f "$STOCK_BAK" "$SYSWOW64/d3d9.dll"
  elif [ -f "$STOCK_ABSENT" ]; then
    rm -f "$SYSWOW64/d3d9.dll"   # stock had no file; wine loads builtin d3d9
  fi
  rm -f "$STOCK_ABSENT"
  wine_env "$WINE" reg delete 'HKCU\Software\Wine\DllOverrides' /v d3d9 /f >/dev/null 2>&1 || true
}

reset_renderer_plist() {
  remove_plist_flag D9VK
  remove_plist_flag DXMT
  remove_plist_flag D3DMETAL
}

# Swap in a bundled native d3d9.dll (d9vk) and tell wine to prefer it. Backs up
# the stock state exactly once so the revert above is lossless.
apply_native_d3d9() { # apply_native_d3d9 <renderer-name>
  local src="$RENDERER_DIR/$1/wine/i386-windows/d3d9.dll"
  [ -f "$src" ] || die "$1 renderer d3d9.dll not found at $src (bundled: $(ls "$RENDERER_DIR" 2>/dev/null | tr '\n' ' ' || echo none))"
  mkdir -p "$SYSWOW64"
  if [ ! -f "$STOCK_BAK" ] && [ ! -f "$STOCK_ABSENT" ]; then
    if [ -f "$SYSWOW64/d3d9.dll" ]; then cp "$SYSWOW64/d3d9.dll" "$STOCK_BAK"
    else : > "$STOCK_ABSENT"; fi
  fi
  cp -f "$src" "$SYSWOW64/d3d9.dll"
  wine_env "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v d3d9 /d native,builtin /f >/dev/null
}

# Always start from clean stock, then apply exactly the requested renderer — makes
# every transition (and re-runs) idempotent and lossless.
revert_d3d9_to_stock
reset_renderer_plist

case "$renderer" in
  wined3d)
    rm -f "$RENDERER_MARKER"   # absent marker => active_renderer() reports wined3d
    say "Renderer set to wined3d (stock). Restored the original d3d9.dll."
    ;;
  d9vk)
    apply_native_d3d9 d9vk
    set_plist_flag D9VK 1      # belt-and-suspenders; harmless if the launcher ignores it
    echo d9vk > "$RENDERER_MARKER"
    say "Renderer set to d9vk (D3D9 -> Vulkan -> MoltenVK -> Metal). Revert: P99_RENDERER=wined3d ./60-renderer.sh"
    ;;
  d3dmetal|dxmt)
    flag=$([ "$renderer" = d3dmetal ] && echo D3DMETAL || echo DXMT)
    set_plist_flag "$flag" 1
    echo "$renderer" > "$RENDERER_MARKER"
    warn "$renderer targets Direct3D 11/12; EQ uses Direct3D 9, so this may have no effect — D9VK is the one to try. Set via Info.plist toggle only."
    say "Renderer set to $renderer (experimental)."
    ;;
  *)
    die "unknown renderer '$renderer' — use one of: wined3d d9vk d3dmetal dxmt"
    ;;
esac
