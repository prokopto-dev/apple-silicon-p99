# What we change (and how to verify it)

This page is the complete inventory of every modification this project makes —
to your system, to the `P99.app` wrapper, to the wine prefix inside it, and to
your game folder. The goal is that nothing here is a mystery: you can see what
each change is, why it exists, how to undo it, and how to check it with your own
eyes. If you're diagnosing a problem or deciding which performance path to take,
this is the map.

Three rules apply to everything below:

1. **Baseline vs. opt-in.** Baseline changes are required for the game to run at
   all and happen during install. Opt-in changes (everything in
   [PERFORMANCE.md](PERFORMANCE.md)) happen only when you flip a switch, and
   your install is byte-identical to the proven baseline until you do.
2. **Everything is reversible**, and anything we replace is backed up first.
3. **Nothing touches your resolution, keybinds, or UI settings** — the one file
   that holds them (`eqclient.ini`) is edited surgically, with your personal
   sections carried over and backed up.

## Your system (install prerequisites)

| Change | What / why | Undo |
|---|---|---|
| Apple Command Line Tools | Apple's own installer, triggered once (~500 MB, not full Xcode). Needed by Homebrew and the `python3` the scripts use. | Standard Apple uninstall (`/Library/Developer/CommandLineTools`) |
| Rosetta 2 | Apple's x86→ARM translator; the 32-bit game cannot run without it. | Part of macOS once installed |
| Homebrew + `upx`, `cabextract` | Two small tools: `upx` unpacks a game DLL (below), `cabextract` unpacks Microsoft's font installers. | `brew uninstall upx cabextract` |

No kernel extensions, no daemons, no login items, nothing in `/usr/local` beyond
Homebrew's own management.

## The wrapper app (`/Applications/P99.app`)

Built by `10-build-wrapper.sh` from two pinned, checksum-verified downloads: the
open-source Sikarugir wrapper template and a community build of CodeWeavers'
LGPL CrossOver 24.0.7 wine. Deleting `P99.app` removes all of it.

| Change | What / why | Verify |
|---|---|---|
| Quarantine attributes stripped | Gatekeeper would refuse the unsigned wine engine. | `xattr -l /Applications/P99.app` |
| `wine-preloader` SDK stamp | macOS 26's dyld rejects the engine's freestanding preloader as shipped; we rewrite its version stamp so dyld accepts it (documented upstream, Sikarugir #130). | `otool -l .../wine/bin/wine-preloader` |
| `Info.plist`: program path | Tells the wrapper to run `eqgame.exe patchme` on double-click. | `plutil -p /Applications/P99.app/Contents/Info.plist` |
| `Info.plist`: `LSEnvironment` | The env-var table below. This is the only channel that reaches the real double-click game session (which inherits nothing from your shell). | same |
| `Info.plist`: renderer flags | `D9VK`/`DXMT`/`D3DMETAL` integers the Sikarugir launcher reads; set/cleared by the renderer switch. | same |
| Engine dylib symlinks | The engine finds its bundled libraries via relative paths into `Contents/SharedSupport/`; we link them there from `Contents/Frameworks/`. | `ls -l .../Contents/SharedSupport/*.dylib` |
| **MoltenVK pairing** (opt-in, d9vk) | The template ships two Vulkan→Metal translators: a recent stock MoltenVK and CodeWeavers' patched build (`moltenvkcx/`) that the bundled D9VK was made for. The `libMoltenVK.dylib` symlink points at stock normally, and at the CX build while d9vk is active. | `readlink .../Contents/SharedSupport/libMoltenVK.dylib`, or `./status.sh` → `moltenvk` |
| **`drive_c/dxvk-p99.conf`** (opt-in, d9vk experiment) | The "indirect buffer maps" setting, one DXVK option in a file we own (first line marks it as ours; a hand-written file at that path is never touched). Lives in the wrapper, not your game folder. | `cat .../drive_c/dxvk-p99.conf`, or `./status.sh` → `dxvk_maps` |

### Every environment variable we set (`LSEnvironment`)

| Variable | When | Why | Removed by |
|---|---|---|---|
| `WINEESYNC=1`, `WINEMSYNC=1` | always (baseline) | Wine's mach-semaphore thread scheduling; the fix that made "smoothness" settings real, because the double-click session never saw shell env. | uninstalling |
| `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0` | d9vk | Newer MoltenVK defaults this on; with DXVK it's a documented performance cliff. | switching to wined3d |
| `MVK_CONFIG_FAST_MATH_ENABLED=1` | d9vk | Cheaper shader math, safe for a 2005 title. | switching to wined3d |
| `MVK_CONFIG_RESUME_LOST_DEVICE=1` | d9vk | Resume instead of crashing on a lost GPU device. | switching to wined3d |
| `DXVK_ASYNC=1` | d9vk | Activates the async shader compilation the bundled DLL ships with (otherwise every shader compiles on the render thread). | switching to wined3d |
| `DXVK_CONFIG_FILE=C:\dxvk-p99.conf` | d9vk + indirect maps | Points DXVK at the one-option conf above. | re-applying without the knob |
| `DXVK_LOG_LEVEL=info`, `MVK_CONFIG_LOG_LEVEL=2` | d9vk + debug knob | Verbose renderer logs for bug reports. | re-applying without the knob |
| `DXVK_HUD=fps,frametimes` | d9vk + FPS overlay | On-screen frame counter for A/B comparisons. | re-applying without the knob |

## The wine prefix (inside `P99.app`)

| Change | What / why | Undo |
|---|---|---|
| Windows version = XP | Part of the proven recipe; EQ is a 2005 title. | `wine reg` (never needed) |
| MS core fonts installed | EQ renders UI text through Windows font APIs; without real Arial etc. the UI is fuzzy. | delete `drive_c/windows/Fonts` copies |
| **`d3d9.dll` swap** (opt-in, d9vk) | The renderer switch. Stock file is backed up once (`d3d9.dll.wined3d.bak`) and a wine DLL override is added; switching back restores the exact stock state and deletes the override. | `P99_RENDERER=wined3d ./60-renderer.sh` |
| `.p99-renderer` marker | One-word file recording the active renderer so `status.sh` and rebuilds stay truthful. | removed on revert |

## The experimental FEX stack (opt-in, gated)

Only exists if you opted into [the FEX experiment](EXPERIMENTAL-FEX.md) —
which additionally requires a pinned engine tarball that, as of this writing,
has not been published. For everyone else, nothing in this section is on disk.

| Change | What / why | Undo |
|---|---|---|
| `/Applications/P99 FEX.app` | A second, independent wrapper (own engine + prefix) for the post-Rosetta ARM64-wine + FEX experiment. The supported `P99.app` is never touched by it. | delete it, or the Uninstall screen's FEX toggle |
| `~/Library/Application Support/p99-mac/active-stack` | One-word marker recording which wrapper the Play button launches (`fex`; absent = rosetta). Written by `70-stack.sh`, removed on revert/uninstall; self-heals to rosetta if the FEX wrapper disappears. | `./70-stack.sh rosetta` |
| `.p99-fex-smoke` (inside the FEX prefix) | Last smoke-test result (`pass`/`fail`), shown by the installer and `status.sh`. | deleted with the wrapper |

Verify: `./status.sh` → the `stack`, `fex_pinned`, `fex_wrapper`, `fex_engine`,
`fex_prefix`, and `fex_smoke` lines.

## Your game folder (`~/Games/EverQuest`)

Your game files stay outside the app (they survive wrapper rebuilds). We change
exactly three things, all during install, all backed up:

| Change | What / why | Backup |
|---|---|---|
| `DSETUP.dll` → official V58 build | The copy in current P99 zips crashes on modern macOS before the game starts; P99's server admin hosts this older build as the sanctioned workaround. Skippable (`SKIP_DSETUP_FIX=1` / app toggle) for the day P99 ships its own fix. | `DSETUP.dll.orig.bak` |
| `dpvs.dll` unpacked | Ships UPX-compressed; the self-decompression stub crashes under Wine-on-Rosetta. Unpacking offline removes the stub; the DLL is functionally identical. | `dpvs.dll.upx.bak` |
| `eqclient.ini` known-good graphics block | A minimal `[Defaults]`/`[VideoMode]` config confirmed working on Apple Silicon — with your keybinds, camera, colors, and gamma carried over from your original file. One-shot: never rewritten once applied. | `eqclient.ini.pre-mac.bak` |

Opt-in on top of that (the **Smoother visuals** / **frame-rate cap** settings):
`35-perf-ini.sh` sets at most these seven `[Defaults]` keys — `FarClipPlane`,
`SpellParticleDensity`, `EnvironmentParticleDensity`, `WaterSpecular`,
`HeatShimmer`, `MaxFPS`, `MaxBGFPS` — and reverting deletes exactly those keys,
nothing else (EQ regenerates its own defaults). A one-time safety copy is kept
as `eqclient.ini.perf.bak`; the `.p99-perf-applied` sentinel is how `status.sh`
knows the profile is on.

## Verify it yourself

```bash
cd scripts && ./status.sh          # every probe above, one line each
plutil -p /Applications/P99.app/Contents/Info.plist        # flags + LSEnvironment
readlink /Applications/P99.app/Contents/SharedSupport/libMoltenVK.dylib
diff ~/Games/EverQuest/eqclient.ini ~/Games/EverQuest/eqclient.ini.perf.bak
```

Every one of these changes is made by a short shell script in `scripts/` — the
scripts are the authoritative documentation, and they're written to be read.
Where a change earns a deeper explanation, it links out:
[HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the baseline fixes,
[PERFORMANCE.md](PERFORMANCE.md) for every opt-in knob and its tradeoffs,
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for symptom → cause → fix.
