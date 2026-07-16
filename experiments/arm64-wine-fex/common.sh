#!/bin/bash
set -euo pipefail

EXPERIMENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Keep all downloaded sources and generated binaries out of Git. Override this
# to put large builds on another disk without changing any script.
FEX_EXPERIMENT_CACHE=${FEX_EXPERIMENT_CACHE:-$EXPERIMENT_DIR/.cache}
SOURCE_DIR=$FEX_EXPERIMENT_CACHE/sources
BUILD_DIR=$FEX_EXPERIMENT_CACHE/build
STAGE_DIR=$FEX_EXPERIMENT_CACHE/stage
TOOLCHAIN_DIR=$FEX_EXPERIMENT_CACHE/toolchain

# shellcheck source=versions.lock
source "$EXPERIMENT_DIR/versions.lock"

if [ -d /opt/homebrew/opt/bison/bin ]; then
  PATH="/opt/homebrew/opt/bison/bin:$PATH"
fi
if [ -d "$TOOLCHAIN_DIR/bin" ]; then
  PATH="$TOOLCHAIN_DIR/bin:$PATH"
fi
export PATH

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

assert_arm64_macos() {
  [ "$(uname -s)" = Darwin ] || die "this experiment targets macOS hosts"
  [ "$(uname -m)" = arm64 ] || die "this experiment requires an Apple Silicon host"
}

verify_checkout() {
  local path=$1 expected=$2 actual
  [ -d "$path/.git" ] || die "source missing: run ./fetch-sources.sh first"
  actual=$(git -C "$path" rev-parse HEAD)
  [ "$actual" = "$expected" ] || die "$path is at $actual, expected $expected"
}
