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

check_engine || die "wrapper not built — run 10-build-wrapper.sh"
[ -e "$GAME_LINK" ] || die "game not linked into prefix — run 20-install-game.sh"

if [ "${1:-}" = "--debug" ]; then
  LOG="$HOME/p99-debug-$(date +%Y%m%d-%H%M%S).log"
  say "Debug launch; wine trace -> $LOG"
  # 'cmd /c cd /d' sets the WINDOWS working directory. A plain unix `cd`
  # through the symlinked game dir does NOT work on all engines (wine maps the
  # resolved physical path, which lies outside drive_c, and then can't find
  # eqgame.exe — the symptom is an instant exit with an empty log).
  # DXVK/MoltenVK info logging costs nothing under wined3d (those libraries never
  # load) and under d9vk makes the trace name WHICH MoltenVK build initialized
  # and whether Metal argument buffers are active — the two facts a slow-d9vk
  # report needs.
  wine_env env WINEDEBUG=+seh,+loaddll \
    DXVK_LOG_LEVEL=info MVK_CONFIG_LOG_LEVEL=2 \
    "$WINE" cmd /c 'cd /d C:\Program Files\EverQuest && eqgame.exe patchme' \
    2>&1 | tee "$LOG" || true
  say "Game exited. Log: $LOG   (see docs/TROUBLESHOOTING.md for signatures)"
  if [ "$(active_renderer)" = d9vk ]; then
    say "d9vk debug: grep -iE 'moltenvk|argument buffer|dxvk' $LOG"
    say "           DXVK also writes its own log next to the game: $GAME_DIR/eqgame_d3d9.log"
  fi
else
  say "Launching P99 (window appears after the ~1-2 min anti-cheat unpack)"
  REF=$(stat -f %m "$GAME_DIR/Logs/dbg.txt" 2>/dev/null || echo 0)
  open "$WRAPPER"
  printf 'Anti-cheat is unpacking (100%% CPU is normal — do NOT force-quit) '
  ok=""
  for i in $(seq 1 60); do
    sleep 5
    NOW=$(stat -f %m "$GAME_DIR/Logs/dbg.txt" 2>/dev/null || echo 0)
    if [ "$NOW" != "$REF" ]; then ok=1; break; fi
    # Give the game ~30 s to appear in the process list before death-checking.
    if [ "$i" -gt 6 ] && ! pgrep -qf "eqgame.exe"; then break; fi
    printf '.'
  done
  printf '\n'
  if [ -n "$ok" ]; then
    say "Engine is up — the EverQuest window should be showing now. Have fun!"
  elif pgrep -qf "eqgame.exe"; then
    warn "still unpacking after 5 min — unusual but not fatal; give it a little longer"
  else
    warn "the game exited before reaching the engine. Run ./40-launch.sh --debug"
    warn "and match the log against docs/TROUBLESHOOTING.md"
  fi
fi
