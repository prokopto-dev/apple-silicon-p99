#!/bin/bash
# 35-perf-ini.sh — optionally set EQ's own performance keys in eqclient.ini, or
# revert them. Surgical and non-destructive: it changes ONLY the managed keys
# (perf_ini_managed_keys in config.sh) and leaves every other setting — resolution,
# keybinds, colors, gamma — intact. EQ ignores keys it doesn't know and regenerates
# unset ones at its own default, so both apply and revert are safe.
#
#   P99_APPLY_PERF=1 P99_PERF_PROFILE=smoother EQ_FPS_CAP=60 ./35-perf-ini.sh
#   P99_APPLY_PERF=0 ./35-perf-ini.sh     # remove those keys (EQ regenerates defaults)
#
# EQ rewrites eqclient.ini on exit, so run this with the game CLOSED.
# See docs/PERFORMANCE.md.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

check_game || die "no game files at $GAME_DIR — run 20-install-game.sh first"
INI="$GAME_DIR/eqclient.ini"
[ -f "$INI" ] || die "no eqclient.ini yet — run 30-apply-mac-fixes.sh (or launch once) first"
if pgrep -qf "eqgame.exe"; then die "close EverQuest first (it rewrites eqclient.ini on exit)"; fi

MODE="${P99_APPLY_PERF:-1}"      # 1 = apply, 0 = revert

# One-time whole-file safety backup (never auto-removed).
[ -f "$GAME_DIR/eqclient.ini.perf.bak" ] || cp "$INI" "$GAME_DIR/eqclient.ini.perf.bak"

if [ "$MODE" = "0" ]; then
  # Restore the managed keys to whatever they were before this project first
  # touched the file, rather than deleting them: they are all keys EQ owns and
  # the player may have set in-game. Legacy no-op keys are swept either way.
  PERF_SET="$(perf_ini_restore_lines "$GAME_DIR/eqclient.ini.perf.bak")"
  if [ -n "$PERF_SET" ]; then
    say "Reverting eqclient.ini performance keys to their pre-apply values:"
    printf '%s\n' "$PERF_SET" | sed 's/^/    /'
  else
    say "Reverting eqclient.ini performance keys to EQ defaults"
  fi
else
  REQUESTED="$(perf_ini_lines)"
  if [ -z "$REQUESTED" ]; then
    warn "no performance keys selected (set P99_PERF_PROFILE=smoother or an EQ_* var) — nothing to apply"
    exit 0
  fi
  say "Applying eqclient.ini performance keys:"
  printf '%s\n' "$REQUESTED" | sed 's/^/    /'
  # Managed keys this run does NOT set fall back to their pre-apply values
  # instead of being deleted — see perf_ini_effective_lines.
  PERF_SET="$(perf_ini_effective_lines "$GAME_DIR/eqclient.ini.perf.bak" "$REQUESTED")"
fi

# Delete every managed (and legacy) key from its own section, then — in apply
# mode — append the requested values to the sections they name. Revert mode
# passes no values, so it is the same sweep without the append. Both modes also
# clear the pre-v0.8.1 keys that were written to the wrong section or that this
# client has no code for at all (perf_ini_legacy_keys).
perf_ini_apply "$INI" "$PERF_SET"

if [ "$MODE" = "0" ]; then
  rm -f "$GAME_DIR/.p99-perf-applied"
  say "Done — restored the managed keys to their pre-apply values."
else
  # Record WHAT was applied, not just that something was. EQ rewrites
  # eqclient.ini on exit, so status has to compare against the live file to be
  # meaningful — see perf_ini_status.
  printf '%s\n' "$REQUESTED" > "$GAME_DIR/.p99-perf-applied"
  say "Done — launch P99 to see the change. Revert any time: P99_APPLY_PERF=0 ./35-perf-ini.sh"
fi
