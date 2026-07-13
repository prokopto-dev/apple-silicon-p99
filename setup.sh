#!/bin/bash
# setup.sh — guided, beginner-friendly installer for Project 1999 on a Mac.
#
#   ./setup.sh
#
# Walks through the whole process interactively: checks (and offers to
# install) Homebrew, builds the wine wrapper, asks where your EverQuest
# Titanium files are, applies the P99 patch files and Mac fixes, and offers
# to launch the game. Every step is idempotent — if anything fails or you
# quit halfway, just run ./setup.sh again and it resumes where it left off.
#
# Prefer doing things by hand? The numbered scripts in scripts/ are the same
# steps individually; see README.md.
set -euo pipefail
cd "$(dirname "$0")/scripts"
source ./config.sh

# Read from the terminal even if stdin is a pipe.
ask() {  # ask "question" -> REPLY
  local q="$1"
  printf '\033[1;36m?\033[0m %s ' "$q" > /dev/tty
  read -r REPLY < /dev/tty
}
confirm() {  # confirm "question" -> returns 0 for yes
  ask "$1 [Y/n]"
  case "${REPLY:-y}" in [Yy]*|"") return 0 ;; *) return 1 ;; esac
}

cat <<'EOF'

  Project 1999 on Apple Silicon — guided setup
  =============================================
  This will:
    1. check the basics (Rosetta, Homebrew, two small helper tools)
    2. build a self-contained wine app at /Applications/P99.app
    3. stage your EverQuest Titanium files + newest P99 patch
    4. apply the three fixes that make it run on macOS
    5. launch the game

  You need:  your own EverQuest Titanium install folder (proprietary — not
             downloadable here), a P99 login-server account, and ~8 GB free
             (~10 GB to be comfortable; less if you already have Homebrew).

  Nothing here needs sudo except (optionally) installing Homebrew/Rosetta,
  which use Apple's and Homebrew's own installers.

EOF
confirm "Ready to begin?" || { echo "Bye — run ./setup.sh whenever you're ready."; exit 0; }

# --- Step 1: Homebrew (offer to install) + prereqs ---------------------------
say "Step 1/5: prerequisites"

# Command Line Tools first — Homebrew's installer needs them, and doing it
# here (with Apple's own dialog) is clearer than letting brew's wall of text
# handle it.
ensure_clt

if ! command -v brew >/dev/null 2>&1; then
  # Homebrew may be installed but not on PATH in this shell (fresh installs).
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew (https://brew.sh) is not installed. It's the standard macOS"
  echo "package manager; this project uses it for two small tools (upx,"
  echo "cabextract). Its installer will ask for your macOS password."
  if confirm "Install Homebrew now?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
    command -v brew >/dev/null 2>&1 || die "Homebrew install didn't complete — install it manually from https://brew.sh and re-run"
  else
    die "Homebrew is required. Install it from https://brew.sh and re-run ./setup.sh"
  fi
fi
./00-prereqs.sh

# --- Step 2: build the wrapper ------------------------------------------------
say "Step 2/5: building the wine wrapper (downloads ~350 MB on first run)"
./10-build-wrapper.sh

# --- Step 3: game files -------------------------------------------------------
say "Step 3/5: your EverQuest Titanium files"
if [ -f "$GAME_DIR/eqgame.exe" ]; then
  echo "Found existing game files at: $GAME_DIR"
  ./20-install-game.sh
else
  echo "Point me at your EverQuest Titanium install folder — the one that"
  echo "contains eqgame.exe. (Copied from an old PC, external drive, etc.)"
  while :; do
    ask "Path to your Titanium folder:"
    SRC="${REPLY/#\~/$HOME}"
    if [ -f "$SRC/eqgame.exe" ]; then break; fi
    echo "  '$SRC' has no eqgame.exe — try again (drag the folder into this window to paste its path)."
  done
  ./20-install-game.sh "$SRC"
fi

# --- Step 4: the Mac fixes ----------------------------------------------------
say "Step 4/5: applying the macOS fixes (see docs/HOW-IT-WORKS.md for what these are)"
./30-apply-mac-fixes.sh

# --- Step 5: launch -------------------------------------------------------------
say "Step 5/5: done!"
cat <<'EOF'

  Setup complete. Reminders for first launch:
    * The screen stays BLACK/EMPTY for 1-2 minutes at 100% CPU while the
      anti-cheat unpacks. Every launch. Don't force-quit it.
    * Log in with your P99 LOGIN-SERVER account (created on project1999.com;
      forum credentials alone won't work).
    * Later launches: just double-click /Applications/P99.app.
    * After P99 releases a patch: run scripts/50-update.sh.
    * Problems? docs/TROUBLESHOOTING.md matches symptoms to fixes.

EOF
if confirm "Launch Project 1999 now?"; then
  ./40-launch.sh
fi
