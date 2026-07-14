#!/bin/bash
# 15-install-from-media.sh — install EverQuest Titanium from your own ISOs or
# physical discs, using the wrapper's wine to run the original installer.
#
#   ./15-install-from-media.sh disc1.iso disc2.iso disc3.iso ...
#   ./15-install-from-media.sh /Volumes/EQ_DISC1 ...      # already-mounted discs
#   ./15-install-from-media.sh                            # interactive: drag each one in
#
# How it works: every disc's contents are merged into one staging folder
# (the classic trick that stops InstallShield asking for disc swaps), then the
# original Setup.exe runs inside the wrapper — a normal Windows installer
# window appears; click through it. Needs ~8 GB free temporarily.
#
# Requires the wrapper (10-build-wrapper.sh) to be built first.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

check_engine || die "wrapper not built yet — run ./10-build-wrapper.sh first"
if check_game; then
  die "game files already exist at $GAME_DIR — nothing to install (delete that folder first if you really want to reinstall)"
fi

# Staging lives inside the prefix's C: drive so the installer can see it at a
# plain Windows path (wine can't use a working directory outside drive_c).
STAGE="$PREFIX/drive_c/eq_install_media"
rm -rf "$STAGE"; mkdir -p "$STAGE"
MOUNTED=()
cleanup() {
  for m in ${MOUNTED[@]+"${MOUNTED[@]}"}; do hdiutil detach "$m" -quiet 2>/dev/null || true; done
  rm -rf "$STAGE"
}
trap cleanup EXIT

ingest() { # ingest <iso-file-or-mounted-volume>
  local src="$1" mnt=""
  if [ -f "$src" ]; then
    say "Mounting $(basename "$src")"
    mnt=$(hdiutil attach -nobrowse -readonly "$src" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
    [ -n "$mnt" ] || { warn "could not mount '$src' (if it's a .bin/.cue rip, convert it: brew install bchunk)"; return 1; }
    MOUNTED+=("$mnt")
    src="$mnt"
  fi
  [ -d "$src" ] || { warn "'$src' is neither an ISO file nor a folder/volume — skipped"; return 1; }
  say "Copying contents of $src (a few minutes per disc)"
  cp -Rf "$src/." "$STAGE/" 2>/dev/null || true   # CDs contain some unreadable metadata; that's fine
  chmod -R u+w "$STAGE"
  if [ -n "$mnt" ]; then hdiutil detach "$mnt" -quiet 2>/dev/null || true; fi
}

if [ $# -gt 0 ]; then
  for s in "$@"; do ingest "$s" || true; done
else
  echo "Add each Titanium disc, one at a time. For ISO files, drag the file into"
  echo "this window. For a physical disc, insert it and drag the disc's icon in"
  echo "(or type /Volumes/<its name>). Press return on an empty line when done."
  while :; do
    printf '\033[1;36m?\033[0m ISO file or disc volume (empty = done): ' > /dev/tty
    read -r SRC < /dev/tty
    [ -z "$SRC" ] && break
    ingest "${SRC/#\~/$HOME}" || true
  done
fi

SETUP=$(find "$STAGE" -maxdepth 2 -iname "setup.exe" | head -1)
[ -n "$SETUP" ] || die "no Setup.exe found on the media you provided — was disc 1 included?"

cat <<'EOF'

  The original EverQuest installer window is about to open. In it:
    * click through with the DEFAULT install location (C:\Program Files\Sony\EverQuest)
    * at the end, UNCHECK any "launch EverQuest / run LaunchPad" box —
      the official patcher must NEVER run (it would patch past what P99
      supports; P99's own patch files come in the next step)

EOF
say "Running the Titanium installer (click through the window that appears)"
wine_env "$WINE" cmd /c 'cd /d C:\eq_install_media && Setup.exe' || true
# Wait for any spawned installer children to finish before checking results.
wine_env "${WINE%/wine}/wineserver" -w 2>/dev/null || true

INSTALLED=$(find "$PREFIX/drive_c/Program Files" -maxdepth 3 -name eqgame.exe 2>/dev/null | head -1)
[ -n "$INSTALLED" ] || die "installer finished but no eqgame.exe found in the prefix — it may have been cancelled; run this script again"

SRC_DIR=$(dirname "$INSTALLED")
say "Installed to: $SRC_DIR"
say "Moving game to $GAME_DIR"
mkdir -p "$(dirname "$GAME_DIR")"
mv "$SRC_DIR" "$GAME_DIR"

say "Titanium installed. Next: ./20-install-game.sh (P99 files), then ./30-apply-mac-fixes.sh"
