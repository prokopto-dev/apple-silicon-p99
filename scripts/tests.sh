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

echo
if [ "$FAIL" -eq 0 ]; then
  echo "OK — $PASS script-layer assertions passed"
else
  echo "FAILED — $FAIL of $((PASS + FAIL)) assertions failed"
  exit 1
fi
