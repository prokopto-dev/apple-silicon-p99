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

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK — $PASS script-layer assertions passed"
else
  echo "FAILED — $FAIL of $((PASS + FAIL)) assertions failed"
  exit 1
fi
