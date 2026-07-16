# ARM64 Wine + FEX experiment

This directory is an isolated, unsupported build laboratory for a direct
macOS replacement for the current Wine-on-Rosetta runtime. It does not modify
`/Applications/P99.app`, the stable installer, or any game files.

## Current milestone

The first checked-in patch ports FEX 2607's small Wine **unixlib** boundary to
Darwin far enough to compile native ARM64 Mach-O libraries. Linux-only `prctl`
tuning operations return `STATUS_NOT_SUPPORTED`, leaving FEX's portable
software behavior in place; `madvise` and shared statistics remain available.
This is useful platform proof, but these libraries alone cannot run x86 code.

```bash
./fetch-sources.sh fex
./install-toolchain.sh
./doctor.sh
./build-darwin-unixlibs.sh
./test-darwin-unixlibs.sh
./build-fex-windows-modules.sh
./verify-artifacts.sh
```

The runtime probe loads each Mach-O library by path and exercises all six
unixlib calls. It expects Darwin to decline Linux-only hardware TSO, unaligned
atomic, and VMA-naming controls, while `madvise` and allocation/growth/deletion
of the shared statistics mapping must work.

Generated sources and artifacts stay under `.cache/` and are ignored by Git.
Set `FEX_EXPERIMENT_CACHE=/some/large/path` to build elsewhere.

## PE-side emulator modules

`build-fex-windows-modules.sh` successfully builds FEX's documented pair on
Apple Silicon macOS:

- `aarch64-w64-mingw32` produces the 32-bit x86/WoW64 emulator module needed
  by EverQuest.
- `arm64ec-w64-mingw32` produces the x86-64/ARM64EC emulator module.

`install-toolchain.sh` downloads the official macOS-universal llvm-mingw
archive linked by FEX's documentation, verifies its published SHA-256, and
extracts it only inside the ignored experiment cache. It does not install
anything system-wide. Run `doctor.sh` afterward to check CMake, Ninja, and all
required cross-compiler entry points.

`verify-artifacts.sh` rejects mixed or incorrect outputs. The expected set is
two ARM64 Mach-O unixlibs, a PE ARM64 WoW64 DLL, and a PE ARM64EC DLL.

## Remaining runtime boundary

These four FEX components now build, but they are not useful without a native
ARM64 macOS Wine host configured for `aarch64`, `arm64ec`, and `i386`. Building
and loading that host is the next milestone. The existing Sikarugir engine is
x86_64 and cannot be used for this test without reintroducing Rosetta.

The initial host build commands are:

```bash
./fetch-sources.sh wine
./configure-wine.sh
./build-wine.sh
```

They install only under `.cache/stage/wine-native`; they do not replace the
Homebrew Wine installation or the supported P99 wrapper.

## Handoff: July 16, 2026

This branch has crossed the first useful platform boundary. On an Apple
Silicon Mac, the pinned sources and checked-in Darwin patch currently produce
and verify all four FEX integration components:

| Component | Host format | Purpose | Status |
| --- | --- | --- | --- |
| `libwow64fex.so` | ARM64 Mach-O | Native unixlib for 32-bit x86 | Runtime probe passes |
| `libarm64ecfex.so` | ARM64 Mach-O | Native unixlib for x86-64 | Runtime probe passes |
| `libwow64fex.dll` | PE ARM64 | Translates 32-bit x86 guest code | Builds and verifies |
| `libarm64ecfex.dll` | PE ARM64EC | Translates x86-64 guest code | Builds and verifies |

The unixlib probe exercises all six exported operations and seven assertions,
including allocation, growth, and deletion of FEX's shared statistics mapping.
The Darwin implementation deliberately reports unsupported for Linux-only
hardware TSO, unaligned-atomic, and VMA-naming controls; it retains `madvise`
and uses FEX's portable software behavior.

The native Wine fork was fetched at the commit in `versions.lock` and
successfully configured on ARM64 macOS with:

```text
--enable-archs=arm64ec,aarch64,i386
--with-mingw=clang
--disable-tests
```

The generated Wine configuration uses `libwow64fex.dll` for x86 guests and
`libarm64ecfex.dll` for amd64 guests. A full three-architecture build was
started and progressed through a substantial portion of Wine, but was stopped
manually before completion to end the development session. This is not a
compiler failure. The build directory is intentionally cached and `make` is
incremental, so the next session can resume with:

```bash
./build-wine.sh
```

The configure probe found the native macOS driver, CoreAudio, FreeType,
GnuTLS, and SDL. Optional integrations including X11, Wayland, PulseAudio,
GStreamer, Vulkan/MoltenVK, USB, scanner, and camera support were absent. Those
warnings do not block the first console PE32 smoke test, but graphics support
must be revisited before attempting EverQuest.

### Next session

1. Resume `./build-wine.sh` and verify the installed `wine` host is ARM64-only.
2. Add a staging script that copies the two PE modules and two native unixlibs
   into the exact directories expected by the installed Wine tree.
3. Compile a tiny PE32 console program with `i686-w64-mingw32-clang` and run it
   in a fresh experiment-only prefix.
4. Confirm the Wine and FEX processes are ARM64 and that Rosetta is not used.
5. Only after hello-world succeeds, add exception, `VirtualProtect`, and
   self-modifying-code probes.

Do not expose a runtime selector in the beta installer yet. The separate beta
application is currently a safe distribution boundary, but it should continue
to use and clearly disclose the known Rosetta runtime until the PE32 smoke
gate above passes. The stable 0.3.1 build remains unchanged by this experiment.

## Source policy

`versions.lock` pins exact commits for FEX, the Wine fork recommended by FEX,
and its llvm-mingw fork. `fetch-sources.sh` verifies those commits. Large
upstream trees and generated binaries are never vendored; only narrow,
reviewable macOS patches belong in this repository.

## Promotion rules

Nothing from this experiment becomes selectable in `P99 FEX Beta.app` until:

1. The Wine unixlibs and PE modules build reproducibly as ARM64/ARM64EC.
2. A native ARM64 macOS Wine host loads them without starting Rosetta.
3. PE32 hello-world, exception, `VirtualProtect`, and self-modifying-code tests
   pass.
4. Selecting FEX fails closed if any component is absent or Intel-hosted.

Only then should P99's packed anti-cheat be introduced as a test workload.
