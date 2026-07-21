# Performance tuning

Project 1999 is a 2005 game, so on a modern Mac the bottleneck is almost never
raw GPU or CPU power — it's the translation stack between the game and the metal.
This page collects the tunable knobs that actually move the needle on **stutter
and choppy frame pacing**, ordered by impact, with the tradeoffs stated honestly.

Everything here is **opt-in and reversible**. None of it changes your resolution
or your keybinds/UI, and every knob can be switched back to the stock config
without touching your other settings. If you don't opt in, your install behaves
exactly as before.

> **The one rule that bites people:** EQ rewrites `eqclient.ini` when it exits, so
> edit that file (or run the INI scripts below) only while the game is **closed**,
> or your changes are overwritten.

<!-- performance-panel.png and performance-apply.png are faithful rendered mockups
of the SwiftUI installer UI (generated without a Mac). To replace them with real
captures, screenshot P99 Installer.app on macOS at the same size. -->
![The installer app's Performance panel: a graphics-renderer picker (Stock wined3d or
D9VK) and a "Smoother visuals" toggle, both opt-in and reversible, with an Apply
button.](img/performance-panel.png)

## Why it stutters on this stack

Three costs stack up, and only the first two are tunable:

1. **The renderer path.** By default rendering runs through wine's built-in
   `wined3d`: Direct3D 9 → OpenGL → Apple's **deprecated** GL-on-Metal shim (see
   [HOW-IT-WORKS.md](HOW-IT-WORKS.md)). Apple has not optimized that OpenGL layer
   in years; on newer GPUs (M4/M5) it is the single biggest source of uneven frame
   times. The template bundles a faster renderer that skips it entirely (lever 1).
2. **Thread scheduling.** Wine's `msync` (mach-semaphore) fast path smooths the
   hand-offs between the game's threads. It was *set* but not *reaching* the real
   game session (lever 2 explains and fixes that).
3. **Rosetta translation.** x86 → ARM translation is a fixed cost of running a
   Windows game on Apple Silicon; the ~1–2 minutes at 100% CPU on every launch is
   the anti-cheat decrypting itself under Rosetta (normal — see
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md)). This is **not** tunable, and no
   CPU-affinity trick changes it (see "What doesn't help" below).

## Lever 1 — Switch the renderer to D9VK (biggest win)

**What it does:** replaces the Direct3D 9 → OpenGL → deprecated-shim path with
**D9VK: Direct3D 9 → Vulkan → MoltenVK → Metal**, which the bundled MoltenVK
maps straight onto Metal. For a Direct3D 9 game like EQ this is the most direct
route to the GPU and usually the largest smoothness improvement on M-series Macs.

```bash
cd scripts
P99_RENDERER=d9vk ./60-renderer.sh      # switch to D9VK
P99_RENDERER=wined3d ./60-renderer.sh   # switch back to the stock renderer
```

Or use the installer app's **Performance** panel (renderer picker → Apply).

**How it works / reversibility:** `60-renderer.sh` backs up the stock
`d3d9.dll` once as `d3d9.dll.wined3d.bak`, drops in the bundled D9VK `d3d9.dll`,
and adds a wine DLL override so wine loads it. Switching back restores the backup
and removes the override — nothing else in your prefix or `eqclient.ini` is
touched, so you can flip back and forth freely to compare. The active renderer
shows up in `./status.sh` (and the app checklist) as `renderer`.

**Tradeoffs / caveats:**
- D9VK is opt-in, not the default, precisely because the stock `wined3d` path is
  the one this project has verified across M1–M4. If D9VK misbehaves for you
  (missing textures, a crash on load), switch straight back with the `wined3d`
  command above.
- `d3dmetal` and `dxmt` are also accepted (`P99_RENDERER=d3dmetal`) but are
  **experimental for EQ**: they target Direct3D 11/12, which EQ doesn't use, so
  they may not change anything for this game. D9VK is the one to try first.

## Lever 2 — Wine msync actually reaching the game

**The bug this fixes:** the normal launch is `open P99.app`, which LaunchServices
runs **detached** — it does not inherit the shell environment. So the
`WINEESYNC=1 WINEMSYNC=1` that `wine_env()` sets reached the install steps and the
`--debug` launch, but **never the real double-click / Play session**. The wrapper
now injects them through the bundle's `Info.plist` (`LSEnvironment`), which
LaunchServices does apply to the launched app, so wine finally sees them in-game.

- `WINEMSYNC` (mach semaphores) is the macOS payload — this is the one that
  matters for scheduling smoothness.
- `WINEESYNC` is a Linux-native primitive, effectively ignored on macOS; it's set
  only for parity.
- `WINEFSYNC` is **Linux-only** and is deliberately not used here. If you read
  advice elsewhere to "enable fsync," it does not apply to macOS.

**How to get it:** rebuild the wrapper once — it skips the finished pieces and just
refreshes the launch environment:

```bash
cd scripts && ./10-build-wrapper.sh
```

Note a routine `./50-update.sh` (P99 patch day) only re-stages game files; it does
**not** rebuild the wrapper, so run `10-build-wrapper.sh` yourself if you installed
before this change.

## Lever 3 — EQ's own graphics load (view distance, particles, FPS cap)

EQ has its own graphics settings that trade visual richness for a steadier frame
rate. The **authoritative place to change these is the in-game Options window**
(Display / Particles) — it's live and safe. For a repeatable, scripted default,
the same settings map to `eqclient.ini` `[Defaults]` keys, which these scripts can
set for you. EQ silently ignores any key it doesn't recognize and regenerates
unset keys at its own default, so applying and reverting is non-destructive.

Apply to an existing install (game closed) with the surgical patcher — it changes
**only** the performance keys and leaves every other setting (resolution, keybinds,
colors, gamma) unchanged:

```bash
cd scripts
# A conservative bundle, plus a 60-FPS cap:
P99_APPLY_PERF=1 P99_PERF_PROFILE=smoother EQ_FPS_CAP=60 ./35-perf-ini.sh
# Revert just those keys (everything else untouched):
P99_APPLY_PERF=0 ./35-perf-ini.sh
```

Fresh installs pick up the same knobs automatically if the `EQ_*` vars are set
when `30-apply-mac-fixes.sh` runs.

| Env var | `eqclient.ini` key | Effect |
|---|---|---|
| `EQ_FARCLIP=<n>` | `FarClipPlane` | View distance — lower draws less, smoother in open zones |
| `EQ_SPELL_PARTICLES=<n>` | `SpellParticleDensity` | Spell particle density — lower in busy fights/raids |
| `EQ_ENV_PARTICLES=<n>` | `EnvironmentParticleDensity` | Ambient particle density |
| `EQ_FPS_CAP=<n>` | `MaxFPS` / `MaxBGFPS` | Frame cap — steadier pacing, less heat/fan (try 60) |
| `P99_PERF_PROFILE=smoother` | several | Bundle: lowers particle density, disables water-specular and heat-shimmer |

Explicit `EQ_*` vars override the `smoother` bundle for that key. Resolution is
**never** touched by any of this — change window size the usual way
([TROUBLESHOOTING.md → "Window is tiny"](TROUBLESHOOTING.md)); note that a smaller
window is itself a fill-rate win if you're GPU-bound.

## Applying from the installer app

Prefer buttons to the terminal? The installer's **Performance** panel (shown above)
sets the same things: pick a renderer, flip **Smoother visuals**, then press **Apply
Performance Settings** with the game closed. It runs `60-renderer.sh` and
`35-perf-ini.sh` for you and reports when it's done.

![The installer's "Applying performance settings" screen: both steps — set the
graphics renderer, apply EQ graphics settings — completed successfully.](img/performance-apply.png)

## Measuring

- **In-game FPS:** EVERQUEST's own frame counter, or just feel out a busy zone
  (e.g. the East Commonlands tunnel, a raid) before and after a change.
- **`~/Games/EverQuest/Logs/dbg.txt`** confirms the game reached the engine.
- **Activity Monitor → Window → GPU History** shows whether you're GPU-bound; if
  the GPU is pinned, lever 1 (renderer) and lever 3 (particles/FPS cap) help most.
- **`./status.sh`** reports the active `renderer` and whether the smoother INI
  profile is applied (`perf_ini`).

## What doesn't help (or we can't expose)

- **Pinning to performance cores.** The game launches detached via `open`, so the
  scripts never hold its process to `taskpolicy` it — and macOS already schedules
  the foreground GUI app on P-cores by default. `taskpolicy -b` would push it the
  *wrong* way (toward efficiency cores). There is no supported "force P-core" knob
  to offer, and it would not address the renderer/Rosetta costs that actually
  dominate. Keep P99 as the active foreground app and that's the best macOS gives.
- **`WINEFSYNC`.** Linux-only (see lever 2). Setting it on macOS does nothing.
- **`WINE_CPU_TOPOLOGY`.** Occasionally suggested when a game misreads core count;
  untested on this stack and not exposed — mentioned only so you don't chase it.
- **Disabling Rosetta / "native" tricks.** The current engine depends on
  general-purpose Rosetta; the post-Rosetta direction is research, not a knob (see
  [HOW-IT-WORKS.md](HOW-IT-WORKS.md#post-rosetta-direction)).
