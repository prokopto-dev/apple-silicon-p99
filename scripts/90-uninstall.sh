#!/bin/bash
# 90-uninstall.sh — guided removal. Asks before deleting anything.
set -euo pipefail
cd "$(dirname "$0")"
# Anchor to the rosetta stack so $WRAPPER below always means the supported
# P99.app; the experimental FEX wrapper is handled by its own block.
P99_STACK=rosetta
source ./config.sh

confirm() { # confirm <question> <ENVVAR>
  # Non-interactive mode (used by the GUI installer): P99_NONINTERACTIVE=1
  # answers each question from its env var (1 = yes, anything else = no).
  if [ -n "${P99_NONINTERACTIVE:-}" ]; then
    eval "[ \"\${$2:-0}\" = 1 ]"; return
  fi
  printf '\033[1;36m?\033[0m %s [y/N] ' "$1" > /dev/tty
  read -r REPLY < /dev/tty
  case "$REPLY" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

echo "This removes what the setup installed. Each step asks first."
echo

if [ -d "$WRAPPER" ]; then
  if confirm "Delete the wrapper app $WRAPPER (~1.1 GB)?" P99_REMOVE_WRAPPER; then
    rm -rf "$WRAPPER"
    say "removed $WRAPPER"
  fi
else
  say "no wrapper at $WRAPPER"
fi

if [ -d "$FEX_WRAPPER" ]; then
  if confirm "Delete the experimental FEX wrapper $FEX_WRAPPER?" P99_REMOVE_FEX_WRAPPER; then
    rm -rf "$FEX_WRAPPER"
    rm -f "$STACK_MARKER"
    say "removed $FEX_WRAPPER (active stack reverts to rosetta)"
  fi
fi

if [ -d "$GAME_DIR" ]; then
  echo
  echo "NOTE: $GAME_DIR contains your game files AND your characters' local"
  echo "settings (keybinds, UI layouts, chat logs). Only delete it if you're"
  echo "done with EverQuest on this Mac or have a copy elsewhere."
  if confirm "Delete the game folder $GAME_DIR (~4.5 GB)?" P99_REMOVE_GAMEDIR; then
    rm -rf "$GAME_DIR"
    say "removed $GAME_DIR"
  fi
else
  say "no game folder at $GAME_DIR"
fi

echo
say "Kept (shared system tools, useful beyond this project):"
echo "  - Homebrew, Apple Command Line Tools, Rosetta 2"
echo "  - upx + cabextract (remove with: brew uninstall upx cabextract)"
say "Uninstall finished."
