#!/bin/bash
# 70-stack.sh — switch which engine stack the game launches with. OPT-IN and
# fully reversible: both stacks stay installed side by side (each with its own
# wrapper app + wine prefix; the game directory is shared), and switching only
# rewrites a marker file — nothing inside either wrapper is touched.
#
#   ./70-stack.sh                  # show the active stack
#   ./70-stack.sh fex              # launch via the experimental FEX wrapper
#   ./70-stack.sh rosetta          # back to the supported Rosetta stack
#   P99_STACK=fex ./70-stack.sh    # (stack may also be given via environment)
#
# Why: Apple retires general-purpose Rosetta 2 after macOS 27; the FEX stack
# (native ARM64 wine + FEX x86 emulation) is the post-Rosetta direction. It is
# EXPERIMENTAL and gated on a published engine tarball — see
# docs/EXPERIMENTAL-FEX.md. Build it first with:
#   P99_STACK=fex ./10-build-wrapper.sh && P99_STACK=fex ./20-install-game.sh
set -euo pipefail
cd "$(dirname "$0")"

# Capture the requested stack BEFORE config.sh consumes P99_STACK for its path
# overlay — this script manages the marker and must see the raw request. Then
# source config anchored to rosetta: marker management only needs the
# stack-independent STACK_MARKER/FEX_* paths, and this keeps $WRAPPER meaning
# the supported wrapper in the messages below.
requested="${1:-${P99_STACK:-}}"
P99_STACK=rosetta
source ./config.sh

# No stack given: report the current one and how to change it.
if [ -z "$requested" ]; then
  say "Active stack: $(active_stack)"
  echo "  change with:  ./70-stack.sh fex   (or rosetta to revert)"
  exit 0
fi

# Switching mid-game would make Play point somewhere else while the running
# session still holds the old prefix open — confusing at best.
if pgrep -qf "eqgame.exe"; then die "close EverQuest first, then re-run this"; fi

case "$requested" in
  rosetta)
    rm -f "$STACK_MARKER"
    say "Stack set to rosetta (supported). Play launches $WRAPPER again."
    ;;
  fex)
    fex_engine_pinned \
      || die "FEX engine not yet available — no engine tarball has been published. Watch the project releases, or set FEX_ENGINE_URL + FEX_ENGINE_SHA256 to your own dev tarball to experiment (docs/EXPERIMENTAL-FEX.md)."
    check_fex_engine \
      || die "FEX wrapper not built — run: P99_STACK=fex ./10-build-wrapper.sh && P99_STACK=fex ./20-install-game.sh"
    mkdir -p "$(dirname "$STACK_MARKER")"
    echo fex > "$STACK_MARKER"
    say "Stack set to fex (experimental). Play launches $FEX_WRAPPER."
    say "Verify the engine with ./75-fex-smoke.sh — revert any time with: ./70-stack.sh rosetta"
    ;;
  *)
    die "unknown stack '$requested' — use one of: rosetta fex"
    ;;
esac
