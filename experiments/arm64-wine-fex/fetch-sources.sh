#!/bin/bash
# Fetch pinned source revisions without vendoring large, fast-moving projects.
# Usage: ./fetch-sources.sh [fex|wine|toolchain|all] (default: fex)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

fetch_one() {
  local name=$1 repo=$2 ref=$3 commit=$4 dest=$SOURCE_DIR/$1 actual
  if [ ! -d "$dest/.git" ]; then
    say "Initializing $name source cache"
    mkdir -p "$dest"
    git -C "$dest" init -q
    git -C "$dest" remote add origin "$repo"
  fi

  say "Fetching $name $ref ($commit)"
  git -C "$dest" fetch --depth=1 origin "$commit"
  git -C "$dest" checkout -q --detach FETCH_HEAD
  actual=$(git -C "$dest" rev-parse HEAD)
  [ "$actual" = "$commit" ] || die "$name resolved to $actual, expected $commit"
  say "$name pinned revision verified"
}

fetch_fex_dependencies() {
  say "Fetching FEX build dependencies (excluding tests and Linux graphics)"
  git -C "$SOURCE_DIR/fex" submodule update --init --depth=1 -- \
    External/rpmalloc \
    External/unordered_dense \
    External/xxhash \
    External/fmt \
    External/range-v3 \
    Source/Common/cpp-optparse
}

mkdir -p "$SOURCE_DIR"
case "${1:-fex}" in
  fex)
    fetch_one fex "$FEX_REPO" "$FEX_REF" "$FEX_COMMIT"
    fetch_fex_dependencies
    ;;
  wine)      fetch_one wine "$WINE_REPO" "$WINE_REF" "$WINE_COMMIT" ;;
  toolchain) fetch_one llvm-mingw "$TOOLCHAIN_REPO" "$TOOLCHAIN_REF" "$TOOLCHAIN_COMMIT" ;;
  all)
    fetch_one fex "$FEX_REPO" "$FEX_REF" "$FEX_COMMIT"
    fetch_fex_dependencies
    fetch_one wine "$WINE_REPO" "$WINE_REF" "$WINE_COMMIT"
    fetch_one llvm-mingw "$TOOLCHAIN_REPO" "$TOOLCHAIN_REF" "$TOOLCHAIN_COMMIT"
    ;;
  *) die "usage: $0 [fex|wine|toolchain|all]" ;;
esac
