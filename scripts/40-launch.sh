#!/bin/bash
# 40-launch.sh — start Project 1999.
#
#   ./40-launch.sh          # normal launch (same as double-clicking P99.app)
#   ./40-launch.sh --debug  # foreground launch with a full wine trace log
#
# NOTE: on every launch the anti-cheat spends 1-2 minutes at 100% CPU with no
# window before anything appears. That is normal — don't force-quit it.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

[ -x "$WINE" ] || die "wrapper not built — run 10-build-wrapper.sh"
[ -e "$GAME_LINK" ] || die "game not linked into prefix — run 20-install-game.sh"

if [ "${1:-}" = "--debug" ]; then
  LOG="$HOME/p99-debug-$(date +%Y%m%d-%H%M%S).log"
  say "Debug launch; wine trace -> $LOG"
  # 'cmd /c cd /d' sets the WINDOWS working directory. A plain unix `cd`
  # through the symlinked game dir does NOT work on all engines (wine maps the
  # resolved physical path, which lies outside drive_c, and then can't find
  # eqgame.exe — the symptom is an instant exit with an empty log).
  wine_env env WINEDEBUG=+seh,+loaddll \
    "$WINE" cmd /c 'cd /d C:\Program Files\EverQuest && eqgame.exe patchme' \
    2>&1 | tee "$LOG" || true
  say "Game exited. Log: $LOG   (see docs/TROUBLESHOOTING.md for signatures)"
else
  say "Launching P99 (window appears after the ~1-2 min anti-cheat unpack)"
  open "$WRAPPER"
fi
