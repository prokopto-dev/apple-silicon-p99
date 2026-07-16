#!/bin/bash
# Read-only inventory. Missing cross-build tools are reported, not installed.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

printf 'host_os\t%s\n' "$(uname -s)"
printf 'host_arch\t%s\n' "$(uname -m)"
printf 'macos\t%s\n' "$(sw_vers -productVersion 2>/dev/null || echo n/a)"

for tool in git clang++ cmake ninja \
  aarch64-w64-mingw32-clang arm64ec-w64-mingw32-clang \
  aarch64-w64-mingw32-windres arm64ec-w64-mingw32-windres; do
  if path=$(command -v "$tool" 2>/dev/null); then
    printf 'tool:%s\tok\t%s\n' "$tool" "$path"
  else
    printf 'tool:%s\tmissing\n' "$tool"
  fi
done

for entry in "fex:$FEX_COMMIT" "wine:$WINE_COMMIT" "llvm-mingw:$TOOLCHAIN_COMMIT"; do
  name=${entry%%:*}; expected=${entry#*:}; path=$SOURCE_DIR/$name
  if [ -d "$path/.git" ]; then
    actual=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo invalid)
    if [ "$actual" = "$expected" ]; then
      printf 'source:%s\tok\t%s\n' "$name" "$actual"
    else
      printf 'source:%s\tmismatch\t%s\n' "$name" "$actual"
    fi
  else
    printf 'source:%s\tmissing\n' "$name"
  fi
done
