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
cd "$(dirname "$0")"
# Anchor to the rosetta stack: the primary keys below must always describe the
# supported install (the GUI's readiness checklist gates on them), regardless
# of which stack the marker currently points at. The FEX side is reported
# separately through the always-defined FEX_* paths.
P99_STACK=rosetta
source ./config.sh

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

# Active renderer name (informational — never gates readiness). "wined3d" is the
# stock path; 60-renderer.sh records anything else in the prefix.
if check_prefix; then printf 'renderer\t%s\n' "$(active_renderer)"; else printf 'renderer\tn/a\n'; fi

# Which MoltenVK build the engine's rpath symlink resolves (cx = CrossOver-patched,
# the one d9vk is paired with; stock = the template's newer build). Informational.
if check_wrapper; then printf 'moltenvk\t%s\n' "$(active_moltenvk)"; else printf 'moltenvk\tn/a\n'; fi

# Whether WINEDEBUG=-all reaches the play session (read back from the bundle's
# LSEnvironment — the only channel the detached launch sees). quiet|default;
# n/a without a wrapper or without plutil (Linux CI). Informational.
if check_wrapper; then printf 'winedebug\t%s\n' "$(active_winedebug)"; else printf 'winedebug\tn/a\n'; fi

# Display scaling (55-wrapper.sh): on = Retina forced, off = 1x forced,
# default = template's shipped behavior. Read from the live plist where
# possible, marker fallback elsewhere. Informational.
if check_prefix; then printf 'hidpi\t%s\n' "$(active_hidpi)"; else printf 'hidpi\tn/a\n'; fi

# Metal performance HUD (55-wrapper.sh): whether MTL_HUD_ENABLED is injected
# into the play session. Informational.
if check_prefix; then printf 'metal_hud\t%s\n' "$(active_metal_hud)"; else printf 'metal_hud\tn/a\n'; fi

# Whether the indirect-buffer-maps experiment conf is in place (d9vk knob).
if check_prefix; then
  printf 'dxvk_maps\t%s\n' "$([ -f "$DXVK_CONF" ] && echo indirect || echo default)"
else
  printf 'dxvk_maps\tn/a\n'
fi

# --- Experimental FEX stack (informational — never gates readiness) ----------
# stack: which wrapper Play launches (rosetta|fex, from 70-stack.sh's marker).
# fex_pinned: whether an engine tarball is pinned at all — the master gate.
# fex_smoke: last 75-fex-smoke.sh result (pass|fail), "never" if not yet run.
printf 'stack\t%s\n' "$(active_stack)"
stat_line fex_pinned  fex_engine_pinned
stat_line fex_wrapper check_fex_wrapper
stat_line fex_engine  check_fex_engine
stat_line fex_prefix  check_fex_prefix
if check_fex_prefix; then
  printf 'fex_smoke\t%s\n' "$(cat "$FEX_SMOKE_MARKER" 2>/dev/null || echo never)"
else
  printf 'fex_smoke\tn/a\n'
fi

if check_game; then
  V=$(p99files_version)
  if [ "$V" = "none" ]; then printf 'p99files\tnone\n'; else printf 'p99files\tV%s\n' "$V"; fi
  stat_line fix_dsetup check_fix_dsetup
  stat_line fix_dpvs   check_fix_dpvs
  stat_line fix_ini    check_fix_ini
  stat_line perf_ini   check_perf_ini
else
  printf 'p99files\tn/a\n'
  printf 'fix_dsetup\tn/a\n'
  printf 'fix_dpvs\tn/a\n'
  printf 'fix_ini\tn/a\n'
  printf 'perf_ini\tn/a\n'
fi
