# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tags
like `v0.1.4`, and each release's section below becomes its GitHub Release
notes automatically (see "Cutting a release" in the README).

## [Unreleased]

## [0.2.0] - 2026-07-14

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
