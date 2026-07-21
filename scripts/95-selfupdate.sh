#!/bin/bash
# 95-selfupdate.sh — helper for the installer app's in-app self-update
# (Views/AppUpdatesSheet.swift). Two modes:
#
#   stage <zip> <workdir>              extract a downloaded P99-Installer.zip,
#                                      sanity-check it, and print the staged
#                                      app's path + version as TSV (APP/VERSION)
#   swap <staged-app> <target-app> <pid>
#                                      wait for the running app (pid) to exit,
#                                      replace the bundle, clear quarantine,
#                                      and relaunch it
#
# swap runs from a COPY in the temp dir — the original lives inside the very
# bundle being replaced — so this script must stay standalone: no config.sh,
# no shared helpers. Extraction prefers ditto (always present on macOS,
# preserves permissions + signatures); the unzip/python fallbacks exist so
# tests.sh can exercise this file on Linux CI.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

mode="${1:-}"
case "$mode" in

stage)
  zip="${2:?usage: 95-selfupdate.sh stage <zip> <workdir>}"
  work="${3:?usage: 95-selfupdate.sh stage <zip> <workdir>}"
  [ -f "$zip" ] || die "no zip at $zip"
  rm -rf "$work" && mkdir -p "$work"
  if command -v ditto >/dev/null 2>&1; then
    ditto -x -k "$zip" "$work"
  elif command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip" -d "$work"
  else
    python3 -m zipfile -e "$zip" "$work"
  fi
  app=$(find "$work" -maxdepth 2 -name "*.app" -type d | head -1)
  [ -n "$app" ] || die "downloaded zip contains no .app bundle"
  plist="$app/Contents/Info.plist"
  [ -f "$plist" ] || die "staged app has no Info.plist"
  if command -v plutil >/dev/null 2>&1; then
    ver=$(plutil -extract CFBundleShortVersionString raw -o - "$plist")
  else
    ver=$(python3 - "$plist" <<'PY'
import plistlib, sys
print(plistlib.load(open(sys.argv[1], 'rb'))["CFBundleShortVersionString"])
PY
)
  fi
  [ -n "$ver" ] || die "staged app has no CFBundleShortVersionString"
  printf 'APP\t%s\nVERSION\t%s\n' "$app" "$ver"
  ;;

swap)
  staged="${2:?usage: 95-selfupdate.sh swap <staged-app> <target-app> <pid>}"
  target="${3:?usage: 95-selfupdate.sh swap <staged-app> <target-app> <pid>}"
  pid="${4:?usage: 95-selfupdate.sh swap <staged-app> <target-app> <pid>}"
  [ -d "$staged" ] || die "no staged app at $staged"
  # Wait (up to 30s) for the app to fully exit — replacing a still-running
  # bundle confuses LaunchServices and the relaunch.
  for _ in $(seq 1 300); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$pid" 2>/dev/null && die "app (pid $pid) never exited"
  old=$(mktemp -d "${TMPDIR:-/tmp}/p99-previous-app.XXXXXX")
  moved=0
  if [ -d "$target" ]; then
    mv "$target" "$old/previous.app"
    moved=1
  fi
  if ! mv "$staged" "$target"; then
    # Put the old version back rather than leaving the user with nothing.
    [ "$moved" = 1 ] && mv "$old/previous.app" "$target"
    die "could not install the new app at $target"
  fi
  rm -rf "$old"
  # The zip came off the network: without this, Gatekeeper can block the
  # relaunch as an unidentified download.
  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
  fi
  if command -v open >/dev/null 2>&1; then
    open "$target" || true
  fi
  ;;

*)
  die "usage: 95-selfupdate.sh stage|swap ..."
  ;;
esac
