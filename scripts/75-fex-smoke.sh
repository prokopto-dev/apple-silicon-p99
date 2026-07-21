#!/bin/bash
# 75-fex-smoke.sh — smoke-test the experimental FEX stack's engine. Read-only
# apart from a scratch registry key and the pass/fail marker in the FEX prefix.
#
#   ./75-fex-smoke.sh                              # tier-1 checks (offline)
#   P99_FEX_SMOKE_EXES=/path/to/dir ./75-fex-smoke.sh   # + run your test .exes
#
# What this proves (tier 1, always run):
#   - the engine's wine binary carries a native arm64 slice (else it still
#     needs Rosetta and defeats the point — reported as a WARNING, not a
#     failure, so prototype x86_64 engines can still be exercised)
#   - the prefix boots (wineboot)
#   - a real 32-bit PE (cmd.exe) executes through the emulation module and
#     produces output — the minimal end-to-end x86-translation smoke
#   - the registry round-trips (reg add / reg query)
#
# What this deliberately does NOT prove yet: structured exceptions,
# memory-protection changes, and self-modifying code — the hard cases P99's
# Themida-packed anti-cheat exercises (see the Post-Rosetta section of
# docs/HOW-IT-WORKS.md). Those need purpose-built 32-bit test binaries this
# repo cannot bundle today (no Windows build toolchain in the pipeline, and
# nothing to pin). The intended future source is a pinned `fex-smoke-1`
# release asset, fetched like every other component. Until then, tier 2 runs
# whatever *.exe files you supply via P99_FEX_SMOKE_EXES (each must exit 0).
#
# Result: writes pass|fail to the marker status.sh reports as `fex_smoke`,
# and exits nonzero on failure.
set -euo pipefail
cd "$(dirname "$0")"

# This script is inherently FEX-targeted: anchor config's overlay to the FEX
# stack so $WINE/$PREFIX/wine_env all mean the FEX wrapper regardless of the
# recorded marker or caller environment.
P99_STACK=fex
source ./config.sh

check_fex_engine || die "FEX wrapper not built — run: P99_STACK=fex ./10-build-wrapper.sh"
if pgrep -qf "eqgame.exe"; then die "close EverQuest first, then re-run this"; fi

FAILED=""
fail_check() { warn "FAILED: $1"; FAILED=1; }

# 1. Architecture: an engine that only ships x86_64 code still needs Rosetta.
#    Darwin-only (lipo); skipped elsewhere so the offline test suite can run.
if [ "$(uname)" = Darwin ]; then
  ARCHES=$(lipo -archs "$WINE" 2>/dev/null || echo unknown)
  say "Engine wine binary architectures: $ARCHES"
  case "$ARCHES" in
    *arm64*) say "  native arm64 slice present" ;;
    *) warn "no arm64 slice — this engine still depends on Rosetta (ok for prototyping, not post-Rosetta)" ;;
  esac
fi

# 2. Prefix boots.
say "Smoke 1/3: wineboot"
wine_env "$WINE" wineboot -u >/dev/null 2>&1 || fail_check "wineboot did not complete"

# 3. 32-bit PE end-to-end: cmd.exe is a real 32-bit Windows binary under
#    WoW64, so producing this echo means x86 code was fetched, translated,
#    and executed with working console output.
say "Smoke 2/3: 32-bit cmd.exe echo"
TOKEN="p99-fex-smoke-ok"
OUT=$(wine_env "$WINE" cmd /c "echo $TOKEN" 2>/dev/null || true)
case "$OUT" in
  *"$TOKEN"*) : ;;
  *) fail_check "cmd.exe echo produced no output (got: ${OUT:-<empty>})" ;;
esac

# 4. Registry round-trip (scratch key; removed afterwards).
say "Smoke 3/3: registry round-trip"
SMOKE_KEY='HKCU\Software\P99FexSmoke'
wine_env "$WINE" reg add "$SMOKE_KEY" /v ping /d pong /f >/dev/null 2>&1 \
  || fail_check "reg add failed"
Q=$(wine_env "$WINE" reg query "$SMOKE_KEY" /v ping 2>/dev/null || true)
case "$Q" in
  *pong*) : ;;
  *) fail_check "reg query did not return the value written" ;;
esac
wine_env "$WINE" reg delete "$SMOKE_KEY" /f >/dev/null 2>&1 || true

# Tier 2: user-supplied 32-bit test binaries (SEH, mprotect, self-modifying
# code, ...). Every *.exe in the directory must exit 0.
if [ -n "${P99_FEX_SMOKE_EXES:-}" ]; then
  [ -d "$P99_FEX_SMOKE_EXES" ] || die "P99_FEX_SMOKE_EXES is not a directory: $P99_FEX_SMOKE_EXES"
  found=""
  for exe in "$P99_FEX_SMOKE_EXES"/*.exe; do
    [ -e "$exe" ] || continue
    found=1
    say "Tier 2: $(basename "$exe")"
    if wine_env "$WINE" "$exe" >/dev/null 2>&1; then
      say "  exit 0"
    else
      fail_check "$(basename "$exe") exited nonzero"
    fi
  done
  [ -n "$found" ] || warn "no *.exe files in $P99_FEX_SMOKE_EXES"
fi

mkdir -p "$(dirname "$FEX_SMOKE_MARKER")"
if [ -n "$FAILED" ]; then
  echo fail > "$FEX_SMOKE_MARKER"
  die "FEX smoke tests FAILED — the engine is not ready for the game. See warnings above."
else
  echo pass > "$FEX_SMOKE_MARKER"
  say "FEX smoke tests passed. Switch with ./70-stack.sh fex — and remember: only the"
  say "Rosetta stack is supported; expect the anti-cheat to be the real boss fight."
fi
