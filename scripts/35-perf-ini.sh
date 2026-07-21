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
  PERF_SET=""
  say "Reverting eqclient.ini performance keys to EQ defaults"
else
  PERF_SET="$(perf_ini_lines)"
  if [ -z "$PERF_SET" ]; then
    warn "no performance keys selected (set P99_PERF_PROFILE=smoother or an EQ_* var) — nothing to apply"
    exit 0
  fi
  say "Applying eqclient.ini performance keys:"
  printf '%s\n' "$PERF_SET" | sed 's/^/    /'
fi

# Delete every managed key from [Defaults], then (apply mode) append the requested
# values. Reuses the section-preserving parse from 30-apply-mac-fixes.sh so no other
# key or section is disturbed.
PERF_KEYS="$(perf_ini_managed_keys)" PERF_SET="$PERF_SET" python3 - "$INI" <<'PYEOF'
import os, re, sys

path = sys.argv[1]
managed  = set(k.strip() for k in os.environ.get('PERF_KEYS', '').splitlines() if k.strip())
set_lines = [l for l in os.environ.get('PERF_SET', '').splitlines() if l.strip()]

sections, order, cur = {}, [], None
for line in open(path, encoding='latin-1'):
    line = line.rstrip('\r\n')
    m = re.match(r'\[(.+)\]\s*$', line)
    if m:
        cur = m.group(1)
        if cur not in sections:
            sections[cur] = []; order.append(cur)
    elif cur is not None:
        sections[cur].append(line)

if 'Defaults' not in sections:
    sections['Defaults'] = []; order.insert(0, 'Defaults')

def key_of(l):
    return l.split('=', 1)[0].strip() if '=' in l else None

sections['Defaults'] = [l for l in sections['Defaults'] if key_of(l) not in managed]
sections['Defaults'].extend(set_lines)

with open(path, 'w', encoding='latin-1') as f:
    for sec in order:
        f.write(f'[{sec}]\n')
        for l in sections[sec]:
            if l.strip():
                f.write(l + '\n')
PYEOF

if [ "$MODE" = "0" ]; then
  rm -f "$GAME_DIR/.p99-perf-applied"
  say "Done — removed the managed keys; EQ regenerates its defaults on next boot."
else
  touch "$GAME_DIR/.p99-perf-applied"
  say "Done — launch P99 to see the change. Revert any time: P99_APPLY_PERF=0 ./35-perf-ini.sh"
fi
