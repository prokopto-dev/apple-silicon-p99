#!/bin/bash
# 20-install-game.sh — stage your EverQuest Titanium files and lay the newest
# P99 patch files over them.
#
# Usage:
#   ./20-install-game.sh /path/to/your/EverQuest-Titanium-install
#   ./20-install-game.sh            # if $GAME_DIR is already populated
#
# You must provide your own EverQuest Titanium installation (it is proprietary
# and cannot be distributed here). Any complete Titanium folder works — copied
# from an old PC, an existing install, etc.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

SRC="${1:-}"

if [ -n "$SRC" ]; then
  [ -f "$SRC/eqgame.exe" ] || die "'$SRC' doesn't look like an EverQuest install (no eqgame.exe)"
  say "Copying Titanium install -> $GAME_DIR (~4.5 GB — this takes a few minutes; resumable)"
  mkdir -p "$GAME_DIR"
  # Plain -a only: stock macOS ships openrsync, which lacks GNU rsync's
  # fancier progress flags.
  rsync -a "$SRC/" "$GAME_DIR/"
elif [ -f "$GAME_DIR/eqgame.exe" ]; then
  say "Using existing game files at $GAME_DIR"
else
  die "no source given and $GAME_DIR has no eqgame.exe — run: $0 /path/to/titanium"
fi

say "Finding newest P99 files zip (probing upward from V$P99FILES_MIN_VERSION)"
V=$P99FILES_MIN_VERSION; LATEST=""
for try in $(seq "$P99FILES_MIN_VERSION" $((P99FILES_MIN_VERSION + 30))); do
  code=$(curl -sIL -o /dev/null -w "%{http_code}" "${P99FILES_BASE_URL}${try}.zip")
  [ "$code" = "200" ] && { LATEST=$try; continue; }
  [ -n "$LATEST" ] && break
done
[ -n "$LATEST" ] || die "could not find any P99FilesV*.zip — check ${P99FILES_BASE_URL}${P99FILES_MIN_VERSION}.zip manually"
say "Latest is V$LATEST"

MARKER="$GAME_DIR/.p99files-version"
if [ "$(cat "$MARKER" 2>/dev/null || true)" = "$LATEST" ]; then
  say "P99 files V$LATEST already applied — skipping"
else
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  say "Downloading P99FilesV${LATEST}.zip"
  curl -fL --progress-bar -o "$TMP/p99.zip" "${P99FILES_BASE_URL}${LATEST}.zip"
  say "Overlaying P99 files onto game directory"
  unzip -o -q "$TMP/p99.zip" -d "$GAME_DIR"
  echo "$LATEST" > "$MARKER"
fi

say "Verifying eqhost.txt points at the P99 login server"
grep -q "login.eqemulator.net" "$GAME_DIR/eqhost.txt" \
  || warn "eqhost.txt doesn't mention login.eqemulator.net — P99 login may fail"

say "Linking game directory into the wine prefix"
mkdir -p "$(dirname "$GAME_LINK")"
ln -sfn "$GAME_DIR" "$GAME_LINK"

say "Game staged. Next: ./30-apply-mac-fixes.sh  (REQUIRED — the game will not start without it)"
