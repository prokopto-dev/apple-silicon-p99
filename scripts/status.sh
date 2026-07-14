#!/bin/bash
# status.sh — report what's already installed, without changing anything.
#
#   ./status.sh
#
# Read-only, offline, fast. Prints one tab-separated "key<TAB>value" line per
# component: "ok", "missing", or "n/a" (game-dependent checks when no game is
# installed; rosetta on Intel). The GUI installer parses this output; it's the
# same idempotency probes (check_* in config.sh) the install scripts use to
# skip finished work. Always exits 0.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

stat_line() { # stat_line <key> <check-function>
  if "$2"; then printf '%s\tok\n' "$1"; else printf '%s\tmissing\n' "$1"; fi
}

stat_line clt      check_clt
if [ "$(uname -m)" = "arm64" ]; then
  stat_line rosetta check_rosetta
else
  printf 'rosetta\tn/a\n'
fi
stat_line brew     check_brew
stat_line tools    check_tools
stat_line wrapper  check_wrapper
stat_line engine   check_engine
stat_line prefix   check_prefix
stat_line fonts    check_fonts
stat_line game     check_game

if check_game; then
  V=$(p99files_version)
  if [ "$V" = "none" ]; then printf 'p99files\tnone\n'; else printf 'p99files\tV%s\n' "$V"; fi
  stat_line fix_dsetup check_fix_dsetup
  stat_line fix_dpvs   check_fix_dpvs
  stat_line fix_ini    check_fix_ini
else
  printf 'p99files\tn/a\n'
  printf 'fix_dsetup\tn/a\n'
  printf 'fix_dpvs\tn/a\n'
  printf 'fix_ini\tn/a\n'
fi
