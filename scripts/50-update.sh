#!/bin/bash
# 50-update.sh — bring an existing install up to date after P99 releases a patch.
#
#   ./50-update.sh
#
# P99 does not auto-patch. New "P99FilesVxx.zip" releases are announced in the
# forums (Patch Notes: https://www.project1999.com/forums/forumdisplay.php?f=10)
# and are usually mandatory — the server rejects old clients afterward. When
# that happens, run this. It:
#   1. finds and overlays the newest P99 files zip (skips if already current)
#   2. re-applies the Mac fixes, because the fresh zip re-ships the broken
#      dsetup.dll and a re-packed dpvs.dll, clobbering fixes 1 and 2
#      (your eqclient.ini is NOT touched — that fix is one-shot by design)
#
# THE DAY P99 SHIPS A DSETUP.DLL THAT SUPERSEDES V58: staff have said a future
# DLL update will replace the V58 workaround (and that they'll fix the Mac
# issue before doing so). When that patch lands, the V58 swap must be SKIPPED
# or the server will reject you:
#   SKIP_DSETUP_FIX=1 ./50-update.sh
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

[ -f "$GAME_DIR/eqgame.exe" ] || die "no existing install at $GAME_DIR — run 20-install-game.sh first"

BEFORE=$(cat "$GAME_DIR/.p99files-version" 2>/dev/null || echo "unknown")
say "Currently applied P99 files version: V$BEFORE"

./20-install-game.sh
./30-apply-mac-fixes.sh

AFTER=$(cat "$GAME_DIR/.p99files-version" 2>/dev/null || echo "unknown")
if [ "$AFTER" != "$BEFORE" ]; then
  say "Updated V$BEFORE -> V$AFTER and re-applied Mac fixes. Launch and verify you can log in."
  say "If login/zoning fails after a patch, read the patch notes — if P99 shipped a"
  say "new working dsetup.dll, redo the update with: SKIP_DSETUP_FIX=1 ./50-update.sh"
else
  say "Already current (V$AFTER); fixes verified."
fi
