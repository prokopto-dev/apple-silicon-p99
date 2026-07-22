#!/bin/bash
# tests.sh — fast, offline checks for the script layer: the check_* probes
# behind status.sh, and the non-interactive uninstall flags the GUI uses.
# Touches nothing outside a temp dir. Exits nonzero on any failure.
#
#   ./tests.sh
set -euo pipefail
cd "$(dirname "$0")"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected '$2', got '$3'"; }
assert_eq() { [ "$2" = "$3" ] && ok || bad "$1" "$2" "$3"; }

field() { awk -F'\t' -v k="$2" '$1==k{print $2}' <<<"$1"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- status.sh: nothing installed --------------------------------------------
OUT=$(WRAPPER="$T/none.app" GAME_DIR="$T/nogame" ./status.sh)
assert_eq "empty: wrapper missing"   "missing" "$(field "$OUT" wrapper)"
assert_eq "empty: engine missing"    "missing" "$(field "$OUT" engine)"
assert_eq "empty: game missing"      "missing" "$(field "$OUT" game)"
assert_eq "empty: p99files n/a"      "n/a"     "$(field "$OUT" p99files)"
assert_eq "empty: fix_dsetup n/a"    "n/a"     "$(field "$OUT" fix_dsetup)"
assert_eq "empty: fix_ini n/a"       "n/a"     "$(field "$OUT" fix_ini)"
assert_eq "empty: moltenvk n/a"      "n/a"     "$(field "$OUT" moltenvk)"
assert_eq "empty: dxvk_maps n/a"     "n/a"     "$(field "$OUT" dxvk_maps)"
assert_eq "empty: winedebug n/a"     "n/a"     "$(field "$OUT" winedebug)"
assert_eq "empty: hidpi n/a"         "n/a"     "$(field "$OUT" hidpi)"
assert_eq "empty: metal_hud n/a"     "n/a"     "$(field "$OUT" metal_hud)"
assert_eq "empty: wined3d_csmt n/a"  "n/a"     "$(field "$OUT" wined3d_csmt)"
assert_eq "empty: wined3d_maxgl n/a" "n/a"     "$(field "$OUT" wined3d_maxgl)"

# --- status.sh: faked install ------------------------------------------------
W="$T/w.app"; G="$T/game"
mkdir -p "$W/Contents/SharedSupport/wine/bin" \
         "$W/Contents/SharedSupport/prefix/drive_c/windows/Fonts" "$G"
printf '#!/bin/sh\n' > "$W/Contents/SharedSupport/wine/bin/wine"
chmod +x "$W/Contents/SharedSupport/wine/bin/wine"
touch "$W/Contents/SharedSupport/prefix/system.reg" \
      "$W/Contents/SharedSupport/prefix/drive_c/windows/Fonts/Arial.TTF" \
      "$G/eqgame.exe" "$G/eqclient.ini.pre-mac.bak"
echo "62" > "$G/.p99files-version"
echo "not the real dll" > "$G/DSETUP.dll"     # wrong md5 -> missing
echo "plain dll, no upx marker" > "$G/dpvs.dll"  # no UPX header -> ok

OUT=$(WRAPPER="$W" GAME_DIR="$G" ./status.sh)
assert_eq "fake: wrapper ok"        "ok"      "$(field "$OUT" wrapper)"
assert_eq "fake: engine ok"         "ok"      "$(field "$OUT" engine)"
assert_eq "fake: prefix ok"         "ok"      "$(field "$OUT" prefix)"
assert_eq "fake: fonts ok"          "ok"      "$(field "$OUT" fonts)"
assert_eq "fake: game ok"           "ok"      "$(field "$OUT" game)"
assert_eq "fake: p99files version"  "V62"     "$(field "$OUT" p99files)"
assert_eq "fake: wrong-md5 dsetup"  "missing" "$(field "$OUT" fix_dsetup)"
assert_eq "fake: unpacked dpvs ok"  "ok"      "$(field "$OUT" fix_dpvs)"
assert_eq "fake: ini marker ok"     "ok"      "$(field "$OUT" fix_ini)"
# The fake wrapper has no Info.plist (and Linux has no plutil), so the WINEDEBUG
# readback must degrade to n/a rather than claiming quiet or default.
assert_eq "fake: winedebug degrades to n/a" "n/a" "$(field "$OUT" winedebug)"

# UPX-marked dpvs.dll must read as missing (= still packed).
printf 'MZ....UPX!....' > "$G/dpvs.dll"
OUT=$(WRAPPER="$W" GAME_DIR="$G" ./status.sh)
assert_eq "fake: packed dpvs missing" "missing" "$(field "$OUT" fix_dpvs)"

# Game present but no version marker -> "none", never "Vnone".
rm "$G/.p99files-version"
OUT=$(WRAPPER="$W" GAME_DIR="$G" ./status.sh)
assert_eq "fake: no marker reads none" "none" "$(field "$OUT" p99files)"

# --- fetch_component: checksum pin + mirror fallback (offline via file://) ----
source ./config.sh
GOOD="$T/good.bin"; BAD="$T/bad.bin"; OUT="$T/fetched.bin"
echo "known good payload" > "$GOOD"
echo "tampered payload"   > "$BAD"
GOOD_SHA=$(shasum -a 256 "$GOOD" | cut -d' ' -f1)

# primary healthy -> served from primary
fetch_component "$OUT" "$GOOD_SHA" "file://$GOOD" "file://$T/never-used" >/dev/null 2>&1
assert_eq "fetch: healthy primary" "$(cat "$GOOD")" "$(cat "$OUT")"

# primary tampered (checksum mismatch) -> mirror takes over
rm -f "$OUT"
fetch_component "$OUT" "$GOOD_SHA" "file://$BAD" "file://$GOOD" >/dev/null 2>&1
assert_eq "fetch: tampered primary falls back to mirror" "$(cat "$GOOD")" "$(cat "$OUT")"

# primary missing (download error) -> mirror takes over
rm -f "$OUT"
fetch_component "$OUT" "$GOOD_SHA" "file://$T/does-not-exist" "file://$GOOD" >/dev/null 2>&1
assert_eq "fetch: dead primary falls back to mirror" "$(cat "$GOOD")" "$(cat "$OUT")"

# every source bad -> nonzero exit, nothing usable
rm -f "$OUT"
if (fetch_component "$OUT" "$GOOD_SHA" "file://$BAD" "file://$T/does-not-exist") >/dev/null 2>&1; then
  bad "fetch: all sources bad must fail" "nonzero exit" "exit 0"
else
  ok
fi

# --- 90-uninstall.sh: non-interactive flags -----------------------------------
run_uninstall() { # run_uninstall <wrapper-flag> <game-flag>
  WRAPPER="$W" GAME_DIR="$G" P99_NONINTERACTIVE=1 \
    P99_REMOVE_WRAPPER="$1" P99_REMOVE_GAMEDIR="$2" ./90-uninstall.sh >/dev/null
}

run_uninstall 0 0
assert_eq "uninstall 0/0 keeps wrapper" "yes" "$([ -d "$W" ] && echo yes || echo no)"
assert_eq "uninstall 0/0 keeps game"    "yes" "$([ -d "$G" ] && echo yes || echo no)"

run_uninstall 1 0
assert_eq "uninstall 1/0 removes wrapper" "no"  "$([ -d "$W" ] && echo yes || echo no)"
assert_eq "uninstall 1/0 keeps game"      "yes" "$([ -d "$G" ] && echo yes || echo no)"

run_uninstall 0 1
assert_eq "uninstall 0/1 removes game" "no" "$([ -d "$G" ] && echo yes || echo no)"

# --- Performance: status probes, eqclient.ini patcher, renderer swap ----------
# Uses a self-contained fake wrapper + game dir; a stub `wine` makes reg add/delete
# a no-op, and plutil-dependent effects are deliberately not asserted so this runs
# the same on Linux and macOS.
PW="$T/perf.app"; PG="$T/perfgame"
PSW="$PW/Contents/SharedSupport/prefix/drive_c/windows/syswow64"
mkdir -p "$PW/Contents/SharedSupport/wine/bin" "$PSW" "$PG" \
         "$PW/Contents/Frameworks/renderer/d9vk/wine/i386-windows" \
         "$PW/Contents/Frameworks/moltenvkcx"
printf '#!/bin/sh\nexit 0\n' > "$PW/Contents/SharedSupport/wine/bin/wine"
chmod +x "$PW/Contents/SharedSupport/wine/bin/wine"
touch "$PW/Contents/SharedSupport/prefix/system.reg" "$PG/eqgame.exe" \
      "$PW/Contents/Frameworks/libMoltenVK.dylib" \
      "$PW/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
# The symlink 10-build-wrapper.sh's dylib link loop would create (stock build).
ln -sf ../Frameworks/libMoltenVK.dylib "$PW/Contents/SharedSupport/libMoltenVK.dylib"

# status.sh: fresh install -> stock renderer, perf not applied.
OUT=$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)
assert_eq "perf: renderer defaults wined3d" "wined3d" "$(field "$OUT" renderer)"
assert_eq "perf: perf_ini missing"          "missing" "$(field "$OUT" perf_ini)"

# 35-perf-ini.sh: surgical apply touches only the managed keys.
cat > "$PG/eqclient.ini" <<'INI'
[Defaults]
Sound=TRUE
TextureQuality=1
Gamma=8
[VideoMode]
Width=1440
WindowedWidth=1440
[KeyMaps]
Ke_Forward=W
INI
WRAPPER="$PW" GAME_DIR="$PG" P99_APPLY_PERF=1 P99_PERF_PROFILE=smoother EQ_FPS_CAP=60 ./35-perf-ini.sh >/dev/null 2>&1
assert_eq "perf: MaxFPS applied"       "MaxFPS=60"    "$(grep '^MaxFPS=' "$PG/eqclient.ini")"
assert_eq "perf: resolution untouched" "Width=1440"   "$(grep '^Width=' "$PG/eqclient.ini")"
assert_eq "perf: gamma untouched"      "Gamma=8"      "$(grep '^Gamma=' "$PG/eqclient.ini")"
assert_eq "perf: keybind untouched"    "Ke_Forward=W" "$(grep '^Ke_Forward=' "$PG/eqclient.ini")"
assert_eq "perf: sentinel -> status ok" "ok" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" perf_ini)"

# Re-apply is idempotent (no duplicate keys).
WRAPPER="$PW" GAME_DIR="$PG" P99_APPLY_PERF=1 P99_PERF_PROFILE=smoother EQ_FPS_CAP=60 ./35-perf-ini.sh >/dev/null 2>&1
assert_eq "perf: idempotent single MaxFPS" "1" "$(grep -c '^MaxFPS=' "$PG/eqclient.ini")"

# Revert removes only the managed keys; everything else survives.
WRAPPER="$PW" GAME_DIR="$PG" P99_APPLY_PERF=0 ./35-perf-ini.sh >/dev/null 2>&1
assert_eq "perf: revert clears MaxFPS" "0"       "$(grep -c '^MaxFPS=' "$PG/eqclient.ini")"
assert_eq "perf: revert keeps gamma"   "Gamma=8" "$(grep '^Gamma=' "$PG/eqclient.ini")"
assert_eq "perf: revert -> status missing" "missing" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" perf_ini)"

# 60-renderer.sh: lossless round-trip (stock d3d9.dll present).
printf 'STOCK' > "$PSW/d3d9.dll"
printf 'D9VK'  > "$PW/Contents/Frameworks/renderer/d9vk/wine/i386-windows/d3d9.dll"
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: d9vk swapped in"    "D9VK"  "$(cat "$PSW/d3d9.dll")"
assert_eq "perf: stock backed up"    "STOCK" "$(cat "$PSW/d3d9.dll.wined3d.bak" 2>/dev/null)"
assert_eq "perf: renderer status d9vk" "d9vk" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" renderer)"
# d9vk must be paired with the CrossOver-patched MoltenVK (the build the bundled
# DXVK was made for), visible both on the symlink and in status.sh.
case "$(readlink "$PW/Contents/SharedSupport/libMoltenVK.dylib")" in
  *moltenvkcx*) ok ;;
  *) bad "perf: d9vk pairs cx MoltenVK" "*moltenvkcx*" "$(readlink "$PW/Contents/SharedSupport/libMoltenVK.dylib")" ;;
esac
assert_eq "perf: moltenvk status cx" "cx" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" moltenvk)"
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=wined3d ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: revert restores stock d3d9" "STOCK" "$(cat "$PSW/d3d9.dll")"
assert_eq "perf: backup consumed on revert"  "no" "$([ -f "$PSW/d3d9.dll.wined3d.bak" ] && echo yes || echo no)"
assert_eq "perf: renderer status back to wined3d" "wined3d" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" renderer)"
assert_eq "perf: revert restores stock MoltenVK" "stock" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" moltenvk)"

# A wrapper rebuild resets the symlink to stock (10-build-wrapper.sh's link loop);
# sync_moltenvk_to_renderer must re-converge it while the marker says d9vk.
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1
ln -sf ../Frameworks/libMoltenVK.dylib "$PW/Contents/SharedSupport/libMoltenVK.dylib"
(WRAPPER="$PW" GAME_DIR="$PG" bash -c 'source ./config.sh; sync_moltenvk_to_renderer') >/dev/null 2>&1
assert_eq "perf: rebuild re-pairs cx MoltenVK" "cx" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" moltenvk)"

# A template without the CX build must not fail the switch: keep stock MoltenVK
# (the argument-buffer env still protects) and still record the d9vk renderer.
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=wined3d ./60-renderer.sh >/dev/null 2>&1
rm "$PW/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
if WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1; then ok; else
  bad "perf: d9vk without cx build succeeds" "exit 0" "nonzero exit"
fi
assert_eq "perf: missing cx keeps stock MoltenVK" "stock" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" moltenvk)"
assert_eq "perf: missing cx still records d9vk"   "d9vk"  "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" renderer)"

# Apply and revert consume the same key list — pin it so they can't drift apart.
assert_eq "perf: d9vk env key count" "8" "$(d9vk_env_keys | wc -l | tr -d ' ')"
assert_eq "perf: env list has async switch"    "1" "$(d9vk_env_keys | grep -c '^DXVK_ASYNC$')"
assert_eq "perf: env list has argbuf override" "1" "$(d9vk_env_keys | grep -c '^MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS$')"
assert_eq "perf: env list has conf pointer"    "1" "$(d9vk_env_keys | grep -c '^DXVK_CONFIG_FILE$')"

# Indirect buffer maps (dxvk-p99.conf lifecycle). Restore the cx dylib first so
# these runs exercise the normal path.
touch "$PW/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
PCONF="$PW/Contents/SharedSupport/prefix/drive_c/dxvk-p99.conf"
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk P99_DXVK_INDIRECT_MAPS=1 ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: indirect maps writes conf" "1" "$(grep -c 'allowDirectBufferMapping = False' "$PCONF" 2>/dev/null)"
assert_eq "perf: dxvk_maps status indirect" "indirect" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" dxvk_maps)"
# Re-applying d9vk WITHOUT the knob removes the conf (the knob is the toggle).
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: re-apply without knob removes conf" "no" "$([ -f "$PCONF" ] && echo yes || echo no)"
assert_eq "perf: dxvk_maps status default" "default" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" dxvk_maps)"
# Revert to wined3d also removes it.
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk P99_DXVK_INDIRECT_MAPS=1 ./60-renderer.sh >/dev/null 2>&1
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=wined3d ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: revert removes conf" "no" "$([ -f "$PCONF" ] && echo yes || echo no)"
# A hand-written conf at the same path is never clobbered or deleted.
echo "my own settings" > "$PCONF"
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk P99_DXVK_INDIRECT_MAPS=1 ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: foreign conf preserved on apply" "my own settings" "$(head -1 "$PCONF")"
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=wined3d ./60-renderer.sh >/dev/null 2>&1
assert_eq "perf: foreign conf preserved on revert" "my own settings" "$(head -1 "$PCONF")"
rm -f "$PCONF"

# --- 55-wrapper.sh: display scaling + Metal HUD -------------------------------
# Swap the perf wrapper's mute wine stub for a recording one so the registry
# half of each knob (reg add/delete argv) is assertable on Linux; the plist
# half is plutil-only and, per the convention above, not asserted here.
REGLOG="$T/reg.log"
cat > "$PW/Contents/SharedSupport/wine/bin/wine" <<STUB
#!/bin/sh
[ "\$1" = reg ] && printf '%s\n' "\$*" >> "$REGLOG"
exit 0
STUB
chmod +x "$PW/Contents/SharedSupport/wine/bin/wine"
PPFX="$PW/Contents/SharedSupport/prefix"

# Untouched install: no forced scaling, no HUD.
OUT=$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)
assert_eq "wrapper: hidpi defaults default" "default" "$(field "$OUT" hidpi)"
assert_eq "wrapper: metal_hud defaults off" "off"     "$(field "$OUT" metal_hud)"

# hidpi off: marker + one-time stock capture + registry half removed.
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=off ./55-wrapper.sh >/dev/null 2>&1
assert_eq "wrapper: hidpi off marker"      "off" "$(cat "$PPFX/.p99-hidpi" 2>/dev/null)"
assert_eq "wrapper: stock captured once"   "yes" "$([ -f "$PPFX/.p99-hidpi-stock" ] && echo yes || echo no)"
assert_eq "wrapper: off deletes RetinaMode" "1" "$(grep -c 'reg delete.*RetinaMode' "$REGLOG")"
assert_eq "wrapper: hidpi status off" "off" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" hidpi)"

# hidpi on: marker flips, RetinaMode=y written.
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=on ./55-wrapper.sh >/dev/null 2>&1
assert_eq "wrapper: hidpi on marker"    "on" "$(cat "$PPFX/.p99-hidpi" 2>/dev/null)"
assert_eq "wrapper: on adds RetinaMode y" "1" "$(grep -c 'reg add.*RetinaMode.*y' "$REGLOG")"
assert_eq "wrapper: hidpi status on" "on" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" hidpi)"

# Full-state semantics: HUD on + scaling kept, then a run without the HUD var
# reverts the HUD but keeps the scaling choice that WAS passed.
WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=on P99_METAL_HUD=1 ./55-wrapper.sh >/dev/null 2>&1
assert_eq "wrapper: hud marker set" "yes" "$([ -f "$PPFX/.p99-metal-hud" ] && echo yes || echo no)"
assert_eq "wrapper: metal_hud status on" "on" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" metal_hud)"
WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=on ./55-wrapper.sh >/dev/null 2>&1
assert_eq "wrapper: hud reverted without var" "off" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" metal_hud)"
assert_eq "wrapper: scaling survives hud revert" "on" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" hidpi)"

# Bare run restores the template default: markers gone, stock consumed,
# registry half removed.
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" ./55-wrapper.sh >/dev/null 2>&1
assert_eq "wrapper: bare run clears marker" "no" "$([ -f "$PPFX/.p99-hidpi" ] && echo yes || echo no)"
assert_eq "wrapper: bare run consumes stock" "no" "$([ -f "$PPFX/.p99-hidpi-stock" ] && echo yes || echo no)"
assert_eq "wrapper: bare run deletes RetinaMode" "1" "$(grep -c 'reg delete.*RetinaMode' "$REGLOG")"
assert_eq "wrapper: hidpi status back to default" "default" "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" hidpi)"

# A rebuild re-converges the plist from the markers (plutil effects are not
# assertable here; assert the hook runs cleanly and never destroys the state
# it re-converges from — the same contract sync_moltenvk_to_renderer has).
WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=off P99_METAL_HUD=1 ./55-wrapper.sh >/dev/null 2>&1
if (WRAPPER="$PW" GAME_DIR="$PG" bash -c 'source ./config.sh; sync_wrapper_to_markers') >/dev/null 2>&1; then ok; else
  bad "wrapper: sync_wrapper_to_markers runs clean" "exit 0" "nonzero exit"
fi
assert_eq "wrapper: sync keeps hidpi marker" "off" "$(cat "$PPFX/.p99-hidpi" 2>/dev/null)"
assert_eq "wrapper: sync keeps hud marker" "yes" "$([ -f "$PPFX/.p99-metal-hud" ] && echo yes || echo no)"
WRAPPER="$PW" GAME_DIR="$PG" ./55-wrapper.sh >/dev/null 2>&1

# A bogus value dies naming the knob, before touching anything.
if ERR=$(WRAPPER="$PW" GAME_DIR="$PG" P99_HIDPI=bogus ./55-wrapper.sh 2>&1); then
  bad "wrapper: bogus hidpi must fail" "nonzero exit" "exit 0"
else
  ok
fi
case "$ERR" in
  *P99_HIDPI*) ok ;;
  *) bad "wrapper: error names the knob" "*P99_HIDPI*" "$ERR" ;;
esac

# --- 65-wined3d.sh: wined3d registry tuning -----------------------------------
# Apply and revert consume the same value list — pin it like the d9vk env list.
assert_eq "wined3d: managed value count" "4" "$(wined3d_reg_keys | wc -l | tr -d ' ')"

# Bare run: reset sweep only — one delete per managed value, no adds.
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" ./65-wined3d.sh >/dev/null 2>&1
assert_eq "wined3d: bare run sweeps all values" "4" "$(grep -c '^reg delete' "$REGLOG")"
assert_eq "wined3d: bare run adds nothing"      "0" "$(grep -c '^reg add' "$REGLOG")"

# Apply: sweep first, then exact adds with the wine-9.0-verified types and
# encodings (csmt dword; MaxVersionGL (major<<16)|minor, so 2.1 = 131073;
# VideoMemorySize REG_SZ in MB).
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_CSMT=off P99_WINED3D_MAXGL=2.1 \
  P99_WINED3D_VRAM=512 ./65-wined3d.sh >/dev/null 2>&1
assert_eq "wined3d: csmt off is dword 0"     "1" "$(grep -c 'csmt /t REG_DWORD /d 0 /f' "$REGLOG")"
assert_eq "wined3d: 2.1 encodes to 131073"   "1" "$(grep -c 'MaxVersionGL /t REG_DWORD /d 131073 /f' "$REGLOG")"
assert_eq "wined3d: vram is REG_SZ 512"      "1" "$(grep -c 'VideoMemorySize /t REG_SZ /d 512 /f' "$REGLOG")"
assert_eq "wined3d: unrequested renderer not set" "0" "$(grep -c 'reg add.*Direct3D /v renderer' "$REGLOG")"

# 4.1 must encode to 0x00040001 = 262145 (the wine-9.0 format, NOT 0x40100).
: > "$REGLOG"
WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_MAXGL=4.1 ./65-wined3d.sh >/dev/null 2>&1
assert_eq "wined3d: 4.1 encodes to 262145" "1" "$(grep -c 'MaxVersionGL /t REG_DWORD /d 262145 /f' "$REGLOG")"

# renderer=vulkan applies (escape hatch) but warns it's unverified.
: > "$REGLOG"
if ERR=$(WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_RENDERER=vulkan ./65-wined3d.sh 2>&1); then ok; else
  bad "wined3d: vulkan escape hatch applies" "exit 0" "nonzero exit"
fi
assert_eq "wined3d: vulkan written REG_SZ" "1" "$(grep -c 'renderer /t REG_SZ /d vulkan /f' "$REGLOG")"
case "$ERR" in
  *UNVERIFIED*) ok ;;
  *) bad "wined3d: vulkan warns unverified" "*UNVERIFIED*" "$ERR" ;;
esac

# no3d/gdi disable 3D outright — refused before any registry work.
: > "$REGLOG"
if WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_RENDERER=no3d ./65-wined3d.sh >/dev/null 2>&1; then
  bad "wined3d: no3d must be refused" "nonzero exit" "exit 0"
else
  ok
fi
assert_eq "wined3d: refusal touched nothing" "0" "$(wc -l < "$REGLOG" | tr -d ' ')"

# A bogus GL version dies naming the knob.
if ERR=$(WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_MAXGL=banana ./65-wined3d.sh 2>&1); then
  bad "wined3d: bogus maxgl must fail" "nonzero exit" "exit 0"
else
  ok
fi
case "$ERR" in
  *P99_WINED3D_MAXGL*) ok ;;
  *) bad "wined3d: error names the knob" "*P99_WINED3D_MAXGL*" "$ERR" ;;
esac

# Matrix guard: setting values under d9vk is refused (they'd silently do
# nothing there), but a bare reset run still works so the GUI's
# apply-everything pass can clean up under any renderer.
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1
if ERR=$(WRAPPER="$PW" GAME_DIR="$PG" P99_WINED3D_CSMT=off ./65-wined3d.sh 2>&1); then
  bad "wined3d: set under d9vk must be refused" "nonzero exit" "exit 0"
else
  ok
fi
case "$ERR" in
  *wined3d*) ok ;;
  *) bad "wined3d: refusal names the fix" "*wined3d*" "$ERR" ;;
esac
if WRAPPER="$PW" GAME_DIR="$PG" ./65-wined3d.sh >/dev/null 2>&1; then ok; else
  bad "wined3d: bare reset allowed under d9vk" "exit 0" "nonzero exit"
fi
WRAPPER="$PW" GAME_DIR="$PG" P99_RENDERER=wined3d ./60-renderer.sh >/dev/null 2>&1

# Status probes parse the real user.reg text-registry format (escaped
# backslashes, timestamped section headers, quoted names, lowercase hex).
cat > "$PPFX/user.reg" <<'REG'
WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

[Software\\Wine\\Direct3D] 1700000000
#time=1da12345678abcd
"MaxVersionGL"=dword:00020001
"VideoMemorySize"="512"
"csmt"=dword:00000000
"renderer"="gl"

[Software\\Wine\\DirectInput] 1700000000
"MouseWarpOverride"="force"
REG
OUT=$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)
assert_eq "wined3d: status csmt off"     "off" "$(field "$OUT" wined3d_csmt)"
assert_eq "wined3d: status maxgl 2.1"    "2.1" "$(field "$OUT" wined3d_maxgl)"
assert_eq "wined3d: status vram 512"     "512" "$(field "$OUT" wined3d_vram)"
assert_eq "wined3d: status renderer gl"  "gl"  "$(field "$OUT" wined3d_renderer)"
# A value from another section must never bleed in.
assert_eq "wined3d: other sections ignored" "" "$(WRAPPER="$PW" GAME_DIR="$PG" bash -c 'source ./config.sh; wined3d_reg_value MouseWarpOverride')"
# Unset values read as wine defaults.
rm -f "$PPFX/user.reg"
OUT=$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)
assert_eq "wined3d: status csmt default"  "default" "$(field "$OUT" wined3d_csmt)"
assert_eq "wined3d: status maxgl default" "default" "$(field "$OUT" wined3d_maxgl)"

# --- Engine stack: overlay, switcher, gating, smoke tests ---------------------
# Fake FEX wrapper mirroring the earlier fakes, plus a wine stub smart enough
# for 75-fex-smoke.sh (echoes the cmd token, answers reg query).
FX="$T/fex.app"; SM="$T/active-stack"
FXP="$FX/Contents/SharedSupport/prefix"
mkdir -p "$FX/Contents/SharedSupport/wine/bin" "$FXP/drive_c/windows/syswow64" \
         "$FX/Contents/Frameworks/renderer/d9vk/wine/i386-windows" \
         "$FX/Contents/Frameworks/moltenvkcx"
cat > "$FX/Contents/SharedSupport/wine/bin/wine" <<'STUB'
#!/bin/sh
case "$1 ${2:-}" in
  "cmd /c")    echo p99-fex-smoke-ok ;;
  "reg query") echo "    ping    REG_SZ    pong" ;;
esac
exit 0
STUB
chmod +x "$FX/Contents/SharedSupport/wine/bin/wine"
touch "$FXP/system.reg" \
      "$FX/Contents/Frameworks/libMoltenVK.dylib" \
      "$FX/Contents/Frameworks/moltenvkcx/libMoltenVK.dylib"
printf 'D9VK' > "$FX/Contents/Frameworks/renderer/d9vk/wine/i386-windows/d3d9.dll"
ln -sf ../Frameworks/libMoltenVK.dylib "$FX/Contents/SharedSupport/libMoltenVK.dylib"

# Every stack invocation pins STACK_MARKER + FEX_WRAPPER into the temp dir.
stack_env() { env STACK_MARKER="$SM" FEX_WRAPPER="$FX" "$@"; }

# status.sh: FEX side absent -> everything missing/n-a, stack rosetta, unpinned.
OUT=$(WRAPPER="$T/none.app" GAME_DIR="$T/nogame" STACK_MARKER="$SM" \
      FEX_WRAPPER="$T/nofex.app" FEX_ENGINE_SHA256= ./status.sh)
assert_eq "stack: default rosetta"      "rosetta" "$(field "$OUT" stack)"
assert_eq "stack: unpinned by default"  "missing" "$(field "$OUT" fex_pinned)"
assert_eq "stack: fex wrapper missing"  "missing" "$(field "$OUT" fex_wrapper)"
assert_eq "stack: fex engine missing"   "missing" "$(field "$OUT" fex_engine)"
assert_eq "stack: fex smoke n/a"        "n/a"     "$(field "$OUT" fex_smoke)"

# Pinning a sha flips fex_pinned (the master gate for every FEX code path).
OUT=$(stack_env WRAPPER="$T/none.app" GAME_DIR="$T/nogame" FEX_ENGINE_SHA256=deadbeef ./status.sh)
assert_eq "stack: sha pins the slot" "ok" "$(field "$OUT" fex_pinned)"

# 10-build-wrapper.sh refuses a FEX build while unpinned — before any download.
if ERR=$(stack_env P99_STACK=fex FEX_ENGINE_SHA256= WRAPPER="$T/fx-build.app" ./10-build-wrapper.sh 2>&1); then
  bad "stack: unpinned fex build must fail" "nonzero exit" "exit 0"
else
  ok
fi
case "$ERR" in
  *"not yet available"*) ok ;;
  *) bad "stack: gate names the reason" "*not yet available*" "$ERR" ;;
esac
assert_eq "stack: gate fired before any build" "no" "$([ -d "$T/fx-build.app" ] && echo yes || echo no)"

# config overlay: P99_STACK=fex retargets WRAPPER (and the engine slot);
# an explicit WRAPPER in the environment still wins.
assert_eq "stack: overlay retargets WRAPPER" "$FX" \
  "$(stack_env P99_STACK=fex bash -c 'source ./config.sh; echo "$WRAPPER"')"
assert_eq "stack: explicit WRAPPER wins" "$T/custom.app" \
  "$(stack_env P99_STACK=fex WRAPPER="$T/custom.app" bash -c 'source ./config.sh; echo "$WRAPPER"')"
assert_eq "stack: overlay retargets engine sha" "deadbeef" \
  "$(stack_env P99_STACK=fex FEX_ENGINE_SHA256=deadbeef bash -c 'source ./config.sh; echo "$ENGINE_SHA256"')"

# 70-stack.sh: refuses while unpinned; switches once pinned + engine present;
# reverting removes the marker.
if stack_env FEX_ENGINE_SHA256= ./70-stack.sh fex >/dev/null 2>&1; then
  bad "stack: switch while unpinned must fail" "nonzero exit" "exit 0"
else
  ok
fi
stack_env FEX_ENGINE_SHA256=deadbeef ./70-stack.sh fex >/dev/null 2>&1
assert_eq "stack: marker written" "fex" "$(cat "$SM" 2>/dev/null)"
OUT=$(stack_env WRAPPER="$T/none.app" GAME_DIR="$T/nogame" ./status.sh)
assert_eq "stack: status reports fex" "fex" "$(field "$OUT" stack)"
stack_env ./70-stack.sh rosetta >/dev/null 2>&1
assert_eq "stack: revert removes marker" "no" "$([ -f "$SM" ] && echo yes || echo no)"

# Self-heal: marker says fex but the FEX engine is gone -> rosetta.
echo fex > "$SM"
OUT=$(WRAPPER="$T/none.app" GAME_DIR="$T/nogame" STACK_MARKER="$SM" \
      FEX_WRAPPER="$T/vanished.app" ./status.sh)
assert_eq "stack: self-heals to rosetta" "rosetta" "$(field "$OUT" stack)"
rm -f "$SM"

# Renderer state is per-stack: applying d9vk through the fex overlay touches
# only the FEX wrapper's prefix; the rosetta fake stays on wined3d.
stack_env P99_STACK=fex GAME_DIR="$PG" P99_RENDERER=d9vk ./60-renderer.sh >/dev/null 2>&1
assert_eq "stack: fex renderer d9vk" "d9vk" "$(cat "$FXP/.p99-renderer" 2>/dev/null)"
assert_eq "stack: rosetta renderer untouched" "wined3d" \
  "$(field "$(WRAPPER="$PW" GAME_DIR="$PG" ./status.sh)" renderer)"

# 75-fex-smoke.sh: the stub engine passes all tier-1 checks -> marker pass.
if stack_env GAME_DIR="$PG" ./75-fex-smoke.sh >/dev/null 2>&1; then ok; else
  bad "stack: smoke passes on healthy stub" "exit 0" "nonzero exit"
fi
assert_eq "stack: smoke marker pass" "pass" "$(cat "$FXP/.p99-fex-smoke" 2>/dev/null)"
OUT=$(stack_env WRAPPER="$T/none.app" GAME_DIR="$T/nogame" ./status.sh)
assert_eq "stack: status smoke pass" "pass" "$(field "$OUT" fex_smoke)"

# A mute engine (no cmd output, no reg answers) must fail and record it.
printf '#!/bin/sh\nexit 0\n' > "$FX/Contents/SharedSupport/wine/bin/wine"
if stack_env GAME_DIR="$PG" ./75-fex-smoke.sh >/dev/null 2>&1; then
  bad "stack: smoke fails on mute stub" "nonzero exit" "exit 0"
else
  ok
fi
assert_eq "stack: smoke marker fail" "fail" "$(cat "$FXP/.p99-fex-smoke" 2>/dev/null)"

# 90-uninstall.sh: the FEX flag removes only the FEX wrapper + stack marker.
KEEP="$T/keepme.app"; mkdir -p "$KEEP"
echo fex > "$SM"
stack_env WRAPPER="$KEEP" GAME_DIR="$T/nogame" P99_NONINTERACTIVE=1 \
  P99_REMOVE_WRAPPER=0 P99_REMOVE_GAMEDIR=0 P99_REMOVE_FEX_WRAPPER=1 \
  ./90-uninstall.sh >/dev/null
assert_eq "stack: uninstall removes fex wrapper" "no"  "$([ -d "$FX" ] && echo yes || echo no)"
assert_eq "stack: uninstall removes marker"      "no"  "$([ -f "$SM" ] && echo yes || echo no)"
assert_eq "stack: uninstall keeps rosetta app"   "yes" "$([ -d "$KEEP" ] && echo yes || echo no)"

# --- 95-selfupdate.sh: stage + swap (offline; python3 stands in for ditto) ----
SU="$T/selfupdate"
mkdir -p "$SU/src/Fake.app/Contents"
cat > "$SU/src/Fake.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>9.9.9</string>
</dict>
</plist>
PLIST
(cd "$SU/src" && python3 -m zipfile -c "$SU/fake.zip" Fake.app)

# stage: extracts, finds the app, reports its path + version as TSV.
OUT=$(./95-selfupdate.sh stage "$SU/fake.zip" "$SU/work")
assert_eq "selfupdate: staged version read" "9.9.9" "$(field "$OUT" VERSION)"
STAGED=$(field "$OUT" APP)
assert_eq "selfupdate: staged app on disk" "yes" "$([ -d "$STAGED" ] && echo yes || echo no)"

# stage: a zip without an .app must fail, not report garbage.
echo "not an app" > "$SU/junk.txt"
(cd "$SU" && python3 -m zipfile -c junk.zip junk.txt)
if ./95-selfupdate.sh stage "$SU/junk.zip" "$SU/work2" >/dev/null 2>&1; then
  bad "selfupdate: appless zip must fail" "nonzero exit" "exit 0"
else
  ok
fi

# swap: waits for the (already dead) pid, replaces the target bundle, and
# consumes the staged copy. `open`/`xattr` are absent on Linux — guarded.
TARGET="$SU/Installed.app"
mkdir -p "$TARGET/Contents"; echo old > "$TARGET/Contents/marker"
mkdir -p "$SU/staged.app/Contents"; echo new > "$SU/staged.app/Contents/marker"
bash -c 'exit 0' & DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
./95-selfupdate.sh swap "$SU/staged.app" "$TARGET" "$DEAD_PID"
assert_eq "selfupdate: new bundle swapped in" "new" "$(cat "$TARGET/Contents/marker" 2>/dev/null)"
assert_eq "selfupdate: staged copy consumed" "no" "$([ -d "$SU/staged.app" ] && echo yes || echo no)"

# --- mouse warp (MouseWarpOverride) ------------------------------------------
# The knob defaults to force; an env override flows through config.sh.
assert_eq "mouse: default force" "force" \
  "$(bash -c 'source ./config.sh; echo "$P99_MOUSE_WARP"')"
assert_eq "mouse: env override wins" "enable" \
  "$(P99_MOUSE_WARP=enable bash -c 'source ./config.sh; echo "$P99_MOUSE_WARP"')"

# 10-build-wrapper.sh rejects a bogus value — before any download or build.
if ERR=$(P99_MOUSE_WARP=bogus WRAPPER="$T/mw.app" ./10-build-wrapper.sh 2>&1); then
  bad "mouse: bogus value must fail" "nonzero exit" "exit 0"
else
  ok
fi
case "$ERR" in
  *P99_MOUSE_WARP*) ok ;;
  *) bad "mouse: error names the knob" "*P99_MOUSE_WARP*" "$ERR" ;;
esac
assert_eq "mouse: validation fired before any build" "no" "$([ -d "$T/mw.app" ] && echo yes || echo no)"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK — $PASS script-layer assertions passed"
else
  echo "FAILED — $FAIL of $((PASS + FAIL)) assertions failed"
  exit 1
fi
