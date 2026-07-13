#!/bin/bash
# 00-prereqs.sh — verify/install everything the later scripts need.
# Safe to re-run. Needs no sudo (Rosetta install may prompt for an admin password).
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

say "Checking macOS + architecture"
sw_vers
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  if ! /usr/bin/pgrep -q oahd; then
    say "Rosetta 2 not running — installing (Apple's x86_64 translation layer)"
    softwareupdate --install-rosetta --agree-to-license
  else
    say "Rosetta 2: OK"
  fi
else
  say "Intel Mac detected — Rosetta not needed"
fi

say "Checking Homebrew"
command -v brew >/dev/null 2>&1 || die "Homebrew is required (https://brew.sh) — used only for 'upx'"

say "Installing upx (used once, to unpack dpvs.dll — see docs/HOW-IT-WORKS.md)"
brew list upx >/dev/null 2>&1 || brew install upx

say "Installing cabextract (used once, to extract MS core fonts for crisp UI text)"
brew list cabextract >/dev/null 2>&1 || brew install cabextract

say "Checking free disk space (need ~2 GB for wrapper + engine, plus your game files)"
df -h /Applications | tail -1

say "All prerequisites satisfied."
