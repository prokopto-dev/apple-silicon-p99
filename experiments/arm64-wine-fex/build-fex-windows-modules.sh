#!/bin/bash
# Cross-build FEX's PE-side WoW64 and ARM64EC modules. This requires the
# ARM64EC-capable llvm-mingw tools on PATH; doctor.sh lists what is missing.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=common.sh
source ./common.sh

assert_arm64_macos
need cmake
need ninja
verify_checkout "$SOURCE_DIR/fex" "$FEX_COMMIT"

for triple in aarch64-w64-mingw32 arm64ec-w64-mingw32; do
  for suffix in clang clang++ windres dlltool ar; do need "$triple-$suffix"; done
done

build_module() {
  local label=$1 triple=$2 dir
  dir=$BUILD_DIR/$label
  say "Configuring FEX $label module"
  cmake -S "$SOURCE_DIR/fex" -B "$dir" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$SOURCE_DIR/fex/Data/CMake/toolchain_mingw.cmake" \
    -DCMAKE_INSTALL_PREFIX="$STAGE_DIR/fex-windows" \
    -DCMAKE_INSTALL_LIBDIR=lib/wine/aarch64-windows \
    -DMINGW_TRIPLE="$triple" \
    -DTUNE_CPU=none \
    -DENABLE_LTO=False \
    -DBUILD_TESTING=False \
    -DENABLE_JEMALLOC_GLIBC_ALLOC=False \
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=True \
    -DCMAKE_DISABLE_FIND_PACKAGE_range-v3=True \
    -DCMAKE_DISABLE_FIND_PACKAGE_unordered_dense=True
  cmake --build "$dir" --parallel
  cmake --install "$dir"
}

mkdir -p "$BUILD_DIR" "$STAGE_DIR/fex-windows"
build_module fex-wow64 aarch64-w64-mingw32
build_module fex-arm64ec arm64ec-w64-mingw32

say "Built PE-side FEX modules"
find "$STAGE_DIR/fex-windows" -maxdepth 5 -type f -print
