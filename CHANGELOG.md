# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tags
like `v0.1.4`, and each release's section below becomes its GitHub Release
notes automatically (see "Cutting a release" in the README).

## [Unreleased]

## [0.4.0] - 2026-07-21

### Added
- **Performance tuning** for stutter on newer Apple Silicon (M4/M5), all opt-in
  and reversible (`docs/PERFORMANCE.md`):
  - `60-renderer.sh` switches the Direct3D renderer between the stock `wined3d`
    (D3D9 → OpenGL → deprecated GL-on-Metal shim) and `d9vk` (D3D9 → Vulkan →
    MoltenVK → Metal). Switching back to `wined3d` restores the original
    `d3d9.dll` and DLL override exactly, so it can be toggled freely.
  - `35-perf-ini.sh` surgically applies or reverts EQ's own `eqclient.ini`
    performance keys (view distance, particle density, FPS cap) — changing only
    those keys and never touching resolution, keybinds, or other settings.
  - A **Performance** panel in the installer app (renderer picker + "smoother
    visuals" toggle + Apply) wired to the same scripts.
- Installer status now reports the active `renderer` and whether the performance
  profile is applied (`perf_ini`); neither gates play-readiness.
- Documented Apple's announced general-purpose Rosetta 2 horizon and the
  investigation into a native ARM64 Wine + FEX successor.
- Made the project's post-Rosetta constraint explicit: the intended solution
  remains a direct, free/open-source macOS runtime rather than a bundled Linux
  or Windows virtual machine.

### Fixed
- Wine's `msync` scheduling flag now actually reaches the running game. The
  double-click / Play launch is `open P99.app`, which LaunchServices runs
  detached (no inherited shell env), so the `WINEESYNC/WINEMSYNC` set in
  `wine_env()` never applied to the game session; the wrapper now injects them via
  the bundle's `Info.plist` (`LSEnvironment`). Re-run `10-build-wrapper.sh` to pick
  this up on an existing install.

## [0.3.1] - 2026-07-14

### Fixed
- Test-run hang diagnostics: `p99tests` output is line-buffered on CI and its
  watchdog now names the last completed assertion, so any recurrence of the
  coverage-step stall pinpoints itself instead of wedging silently.

## [0.3.0] - 2026-07-14 [UNPUBLISHED]

Tag's CI run hit the test-run stall before the diagnostics existed; no
artifacts. These changes first shipped in a release with 0.3.1.

### Added
- **Installer Updates window** ("Installer Updates…" on the status screen):
  checks GitHub for newer releases of this app and lists the changelog for
  every version between yours and the latest, with a download button. The
  app bundle now carries its real version (stamped from this changelog at
  build time), and the old "Check for Updates" button is renamed
  "Update Game Files" to keep the two kinds of update distinct.

### Fixed
- CI kept stalling in the coverage step: `ScriptRunner` relied on Foundation
  closing the parent's copy of the output pipe after spawning, which macOS 15
  runners don't do reliably — EOF never arrived and the test run hung. The
  write end is now closed explicitly, and `p99tests` gained a 3-minute
  watchdog so any future hang fails fast with a diagnostic instead of
  wedging the pipeline.

## [0.2.0] - 2026-07-14 [UNPUBLISHED]

Tag exists but its CI runs stalled in the coverage step (the ScriptRunner
pipe-EOF bug fixed in 0.3.0 — tag re-runs rebuild the tag's own code, so they
could never pick up the fix). No artifacts; these changes first shipped in
a release with 0.3.0.

### Added
- **Anti-cheat fix toggle** in the installer app (Settings on the status
  screen): the V58 `dsetup.dll` swap can now be turned off — for the day P99
  ships a DLL update that supersedes the workaround — without updating the
  installer. The choice is remembered between launches.
- Verified-hardware table in the README (now including MacBook Pro 13″ M1,
  8 GB) with a call for reports on other machines.
- This changelog, wired into CI: a release's notes now come from its section
  here instead of auto-generated commit lists.

## [0.1.4] - 2026-07-14 [UNPUBLISHED]

Tag exists but its CI run was cancelled mid-build; no artifacts. These
changes first shipped in a release with 0.2.0.

### Added
- The wrapper template and wine engine downloads are now **pinned by sha256**
  with an automatic fallback to a byte-identical
  [mirror](https://github.com/prokopto-dev/apple-silicon-p99/releases/tag/engine-mirror-1)
  hosted in this repo — upstream release assets have been replaced in-place
  before, and installs now survive that (or upstream vanishing entirely).

### Fixed
- The installer app could silently lose all output of very fast script steps
  (a pipe-reading race, caught by the test suite on CI's faster runners).
- The CI coverage-badge update failed on its second-ever run
  (per-worktree `FETCH_HEAD`).

## [0.1.3] - 2026-07-14 [YANKED]

Tag exists but CI failed before publishing; no artifacts. Its changes shipped
in 0.1.4.

## [0.1.2] - 2026-07-14

### Fixed
- **Fresh installs work on macOS 26 (Tahoe) again.** Two latent bugs:
  - The engine's `wine-preloader` (rebuilt upstream against SDK 26.1) is
    rejected outright by Tahoe's dyld ("missing LC_LOAD_DYLIB", Abort
    trap: 6). `10-build-wrapper.sh` now rewrites its SDK stamp with `vtool`
    and re-signs it. Deleting the preloader is *not* a fix — the game then
    can't map at its fixed 32-bit base (`status c0000018`). Upstream:
    [Sikarugir#130](https://github.com/Sikarugir-App/Sikarugir/issues/130).
  - `wineserver` couldn't find `libinotify.0.dylib`: the engine's rpath
    expects dylibs in `SharedSupport/`, the template ships them in
    `Frameworks/`. The script now links them across.
- Both crash signatures documented in `docs/TROUBLESHOOTING.md`.

## [0.1.1] - 2026-07-14

First release of **P99 Installer.app** — a native SwiftUI GUI over the
existing install scripts.

### Added
- Status screen showing what's already installed (per-component checklist);
  finished steps are detected and skipped.
- Guided install with live progress, real download percentages, and a
  collapsible log; safe to cancel and re-run.
- Native pickers for a Titanium folder or disc images/mounted discs.
- Homebrew handled safely: handed off to Terminal.app so the app never
  touches your password.
- Uninstall screen with per-component toggles and double confirmation.
- Play button (with anti-cheat-unpack patience notice) and Check for Updates.
- `scripts/status.sh` — machine-readable install status (powers the app,
  works standalone).
- CI: tests + build + packaged-app selftest on every push; version tags
  publish `P99-Installer.zip` to GitHub Releases.
- Test suite (`make test`): 55 Swift assertions + offline script-layer tests,
  and a coverage badge generated without external services.

### Notes
- 0.1.0 was tagged but its CI run failed; no release was published.
