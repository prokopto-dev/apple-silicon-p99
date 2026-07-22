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
captures, screenshot P99 Installer.app on macOS at the same size.
TODO: the mockups predate the Display scaling picker, the wined3d tuning group,
and the Diagnostics disclosure (levers 4-5) — refresh them when a Mac capture or
new mockup is available; the table under "Applying from the installer app" is
the current source of truth for the panel's controls. -->
![The installer app's Performance panel: a graphics-renderer picker (Stock wined3d or
D9VK) and a "Smoother visuals" toggle, both opt-in and reversible, with an Apply
button.](img/performance-panel.png)

## Why it stutters on this stack

Three costs stack up, and only the first two are tunable:

1. **The renderer path.** By default rendering runs through wine's built-in
   `wined3d`: Direct3D 9 → OpenGL → Apple's **deprecated** GL-on-Metal shim (see
   [HOW-IT-WORKS.md](HOW-IT-WORKS.md)). Apple has not optimized that OpenGL layer
   in years; on newer GPUs (M4/M5) it is a major source of uneven frame times.
   The template bundles an alternative renderer that skips it entirely (lever 1)
   — a big win on some machines, and much slower on others, so it stays opt-in.
2. **Thread scheduling.** Wine's `msync` (mach-semaphore) fast path smooths the
   hand-offs between the game's threads. It was *set* but not *reaching* the real
   game session (lever 2 explains and fixes that).
3. **Rosetta translation.** x86 → ARM translation is a fixed cost of running a
   Windows game on Apple Silicon; the ~1–2 minutes at 100% CPU on every launch is
   the anti-cheat decrypting itself under Rosetta (normal — see
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md)). This is **not** tunable, and no
   CPU-affinity trick changes it (see "What doesn't help" below).

## Lever 1 — Try the D9VK renderer (big win for some, much worse for others)

**What it does:** replaces the Direct3D 9 → OpenGL → deprecated-shim path with
**D9VK: Direct3D 9 → Vulkan → MoltenVK → Metal**. When it works, it is the most
direct route to the GPU and a real smoothness improvement. **When it doesn't, it
can be dramatically slower** — a single-digit-FPS slideshow has been reported on
an M4 MacBook Pro. That outcome is a known property of this stack, not user
error; the fix is simply to switch back (below). wined3d remains the safe,
verified default.

```bash
cd scripts
P99_RENDERER=d9vk ./60-renderer.sh      # switch to D9VK
P99_RENDERER=wined3d ./60-renderer.sh   # switch back to the stock renderer
```

Or use the installer app's **Performance** panel (renderer picker → Apply).

The renderer choice is **per engine stack** (it lives inside each wrapper's
prefix). Under the experimental [FEX stack](EXPERIMENTAL-FEX.md) the installer
locks the renderer to stock wined3d — the bundled D9VK/DXMT builds are only
proven against the Rosetta engine.

**Why D9VK can be slow, and what the script now does about it:**

1. **It was running on the wrong MoltenVK.** The wrapper template ships *two*
   MoltenVK builds: a recent stock build, and CodeWeavers' patched build
   (`moltenvkcx/`) — the one the bundled D9VK (DXVK 1.10) was actually built and
   tested against. The wrapper's library links pointed the engine at the stock
   build, which is years newer than that DXVK and turns on "Metal argument
   buffers" by default — a documented DXVK performance cliff. Switching to d9vk
   now re-points the engine at the CX build (and a wrapper rebuild preserves
   that; `./status.sh` reports it as `moltenvk cx`).
2. **Async shader compilation was never switched on.** The bundled DLL is the
   dxvk-*async* build, but the `DXVK_ASYNC=1` switch that activates it never
   reached the game, so every new shader compiled on the render thread.
   Switching to d9vk now injects it (plus `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0`
   as a belt-and-suspenders, fast-math, and device-loss resume) through the same
   `LSEnvironment` channel as lever 2. Switching back to wined3d removes all of it.
3. **One cost we cannot fix:** this is a 32-bit game running through wine's
   WoW64 mode, and without a Vulkan extension called `VK_EXT_map_memory_placed`
   (which neither bundled MoltenVK supports) every GPU-memory map by a 32-bit
   game takes an expensive fallback. A 2005 engine maps vertex buffers every
   frame. On some machines this cost dominates everything else. The *indirect
   buffer maps* experiment below attacks it from the other side; if that doesn't
   help either, wined3d is the answer.

**Diagnostics (optional, for reporting):**

```bash
P99_RENDERER=d9vk P99_RENDERER_DEBUG=1 ./60-renderer.sh   # verbose DXVK+MoltenVK logs
P99_RENDERER=d9vk P99_DXVK_HUD=fps,frametimes ./60-renderer.sh  # in-game FPS overlay
```

`P99_RENDERER_DEBUG=1` makes the game write `~/Games/EverQuest/eqgame_d3d9.log`
and makes a `./40-launch.sh --debug` trace include the MoltenVK version line —
which tells us exactly which build loaded and whether argument buffers are off.
Re-run the switch without the variable to turn either off.

**Experiment — indirect buffer maps (if D9VK is still slow):**

```bash
P99_RENDERER=d9vk P99_DXVK_INDIRECT_MAPS=1 ./60-renderer.sh   # on
P99_RENDERER=d9vk ./60-renderer.sh                            # off (re-apply without it)
```

This targets cost 3 above — the expensive 32-bit memory-map path — from the
other side: instead of making the maps cheap (we can't), it tells DXVK to stop
handing the game direct pointers into Vulkan-mapped memory
(`d3d9.allowDirectBufferMapping = False`). Buffer locks then land in DXVK-owned
CPU memory and DXVK manages the upload itself, which keeps the game's per-frame
geometry traffic off the one code path this stack makes expensive. The price is
extra CPU copying, so this is a measured experiment, not a default: try it with
the FPS overlay on and keep whichever is faster on *your* machine. The setting
lives in a single one-option file **inside the wrapper** (`drive_c/dxvk-p99.conf`
— your game folder is not touched), is handed to DXVK via `DXVK_CONFIG_FILE`,
and both disappear when you re-apply without the knob or revert to wined3d.
`./status.sh` reports it as `dxvk_maps` (`indirect` vs `default`).

**How it works / reversibility:** `60-renderer.sh` backs up the stock
`d3d9.dll` once as `d3d9.dll.wined3d.bak`, drops in the bundled D9VK `d3d9.dll`,
adds a wine DLL override so wine loads it, re-points the engine's MoltenVK link
at the CX build, and injects the `LSEnvironment` tuning above. Switching back
restores the backup and removes every one of those changes — nothing else in
your prefix or `eqclient.ini` is touched, so you can flip back and forth freely
to compare. The active renderer shows up in `./status.sh` (and the app
checklist) as `renderer`, the MoltenVK pairing as `moltenvk`.

**Tradeoffs / caveats:**
- D9VK is opt-in, not the default: the stock `wined3d` path is the one this
  project has verified on real hardware. If D9VK misbehaves for you (much lower
  FPS, missing textures, a crash on load), switch straight back with the
  `wined3d` command above — and see
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md#after-switching-to-d9vk-the-game-is-much-slower-single-digit-fps)
  if you want to report it usefully.
- `d3dmetal` and `dxmt` are also accepted (`P99_RENDERER=d3dmetal`) but are
  **experimental for EQ**: they target Direct3D 11/12, which EQ doesn't use, so
  they may not change anything for this game.

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

The same channel now also carries **`WINEDEBUG=-all`** as baseline. Wine's
default logging keeps the `err` and `fixme` channels on, and a 2005 game trips
fixmes on hot paths — each one formatted and written mid-frame. It had never
been silenced for the real play session (the same detached-launch reason as
msync). The `./40-launch.sh --debug` trace run is unaffected: it launches
directly, not through LSEnvironment, and sets its own verbose channels on
purpose. `./status.sh` reports this as `winedebug` (`quiet` once the wrapper
has been rebuilt).

**How to get it:** rebuild the wrapper once — it skips the finished pieces and just
refreshes the launch environment:

```bash
cd scripts && ./10-build-wrapper.sh
```

Note a routine `./50-update.sh` (P99 patch day) only re-stages game files; it does
**not** rebuild the wrapper, so run `10-build-wrapper.sh` yourself if you installed
before this change. (The installer app's **Update Game Files** button re-runs the
wrapper build for you.)

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

## Lever 4 — Display scaling: render at 1× (the big fill-rate lever)

```bash
cd scripts
P99_HIDPI=off ./55-wrapper.sh   # render at 1x, macOS scales the window up
P99_HIDPI=on  ./55-wrapper.sh   # force Retina-scale rendering
./55-wrapper.sh                 # restore the wrapper's shipped default
```

Or the installer's **Display scaling** picker. It's one switch and fully
reversible — the honest way to decide is to just try both for an evening each
and keep whichever you prefer. Everything below is only so you know what you're
looking at.

**What it actually changes — and what it doesn't.** On a Retina panel, macOS
can hand the wrapper a backing store at 2× linear scale, which means the game
is producing roughly **four times the pixels every frame**. Setting `off` makes
the game render one 1×-sized buffer and lets macOS scale it up to fill the same
window. That is the whole change. It does **not** change EQ's resolution
setting, does not change the window size, does not touch the UI scale, and goes
nowhere near your keybinds — `eqclient.ini` is not involved at all. The knob
lives in the wrapper (an `Info.plist` value plus a wine registry value, moved
together), which is also why it applies on **both renderers and both engine
stacks** — unlike most of lever 1, it sits above the renderer entirely.

**Why it helps so much on this stack specifically.** A modern Apple GPU
shrugs at four times the pixels of a 2005 game — raw GPU power was never the
bottleneck. The problem is *where* those pixels flow: on the stock wined3d
path, every one of them crosses Apple's deprecated, unoptimized GL-on-Metal
shim, and fill rate is precisely what that layer is worst at. Cutting the pixel
count by ~4× is the same reason a smaller window already helps GPU-bound
machines — just much bigger, without shrinking anything.

**What you will actually see.** Be prepared for it honestly: UI text and
window-edge lines get slightly softer, because that's where a Retina panel's
extra pixels genuinely show. The 3D world is close to indistinguishable at a
normal viewing distance — Titanium's textures are 2005-era, mostly 256 px or
smaller, so there is no extra detail at 2× for the world to lose. The UI is the
tradeoff; the world is nearly free.

**"But won't it look pixelated?"** This is the same rendering every Mac EQ
player had before Retina panels existed (2012). It is not a retro filter, not
nearest-neighbour chunkiness, and not the game running at a lower resolution —
the window stays exactly the same size, macOS's scaler is good, and you are
seeing the game the way it was drawn for two decades.

**Who should try `off` first:** anyone on a fanless MacBook Air, anyone
reporting stutter on M4/M5, anyone playing on battery or noticing heat and fan
noise. **Who probably shouldn't:** anyone on a large external display where UI
text legibility matters more than frame pacing, and anyone running a
high-resolution custom UI package where crisp text is the whole point.

**Interaction with window size:** a smaller window and 1× rendering compound —
both cut pixels through the same weak layer. If you only want one, try `off`
first: it removes more fill and shrinks nothing on screen.

Details worth knowing:

- "System default" (the bare `./55-wrapper.sh` run) restores the wrapper's
  exact shipped behavior — the script captures the template's original setting
  before first touching it, so the revert is faithful even if a future template
  ships a different default.
- With scaling `on` (Retina), winemac.drv counts in *physical* pixels, so EQ's
  `Width`/`Height` suddenly mean physical pixels and the window will look half
  its previous size — raise them to compensate ([FAQ](FAQ.md)). This is the
  main reason `on` is a niche choice on this game; `off` has no such surprise.
- `./status.sh` reports the live state as `hidpi` (`on`/`off`/`default`), read
  back from the wrapper's actual `Info.plist`, not from a variable.
- One honesty note: whether the `Info.plist` half reliably propagates to wine's
  child processes under this launcher is **awaiting confirmation on real
  hardware** — the knob ships both halves (plist + registry) precisely so
  either mechanism can carry it. If you try it and see no difference in the
  Metal HUD's numbers, that's worth a bug report.

<!-- TODO: side-by-side screenshots (docs/img/): a UI-heavy view (inventory +
chat) and a world view, each at scaling on vs off, captured on a real Retina
Mac. Not yet produced — this working copy was written without Mac hardware; do
not describe or link images that don't exist. -->

## Lever 5 — wined3d registry fine-tuning (stock renderer only)

The stock renderer has its own tuning values in the wine registry
(`HKCU\Software\Wine\Direct3D`), which this project never touched before. All
opt-in, all individually revertible, all **experimental** — wine's own defaults
are the verified baseline, so change one at a time and measure (Metal HUD,
below). Semantics below are verified against the wine 9.0 source that CrossOver
24 builds on; CodeWeavers' private patches on top were not reviewed.

```bash
cd scripts
P99_WINED3D_CSMT=off ./65-wined3d.sh                   # single knob
P99_WINED3D_CSMT=off P99_WINED3D_VRAM=512 ./65-wined3d.sh   # combinations
./65-wined3d.sh                                        # revert everything
```

Each run applies the full requested state (anything unset is reverted), the
same convention as the renderer switch. Under d9vk these values are inert —
the renderer switch replaces the whole wined3d DLL — so the script **refuses**
to set them there and the installer hides the controls, rather than shipping
switches that silently do nothing.

| Env var | Registry value | What it does |
|---|---|---|
| `P99_WINED3D_CSMT=off\|on\|serialize` | `csmt` (dword) | Command-stream multithreading. **On by default in this wine** — so the experiment worth running is `off`, which puts GL submission back on the game's thread: worse peak throughput in theory, but on a single-threaded 2005 client it may improve frame *pacing* and input latency. `serialize` is a debug mode, not a performance setting. |
| `P99_WINED3D_MAXGL=2.1`/`4.1` | `MaxVersionGL` (dword) | Caps the GL context version wined3d asks for. macOS tops out at 4.1 core / 2.1 legacy; capping changes which context and feature set the shim has to emulate. Could move things in either direction — measure. |
| `P99_WINED3D_VRAM=512` (MB) | `VideoMemorySize` (string) | What wined3d reports as VRAM. Wine frequently under-reports on unified memory; if EQ is evicting textures because it believes VRAM is tiny, this rules that out cheaply. No effect if the auto-detect was already sane. |

`./status.sh` reports the live values (`wined3d_csmt`, `wined3d_maxgl`,
`wined3d_vram`, `wined3d_renderer`), read back from the prefix's `user.reg` —
the same file the game's wine session loads, so what status shows is what the
game gets on both the Play and `--debug` launch paths.

One caution: wine also reads a `WINE_D3D_CONFIG` environment variable that
silently **overrides** these registry values. Nothing in this project sets it,
but if your experiments seem to change nothing, check `env | grep WINE_D3D`
(see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)).

## Applying from the installer app

Prefer buttons to the terminal? The installer's **Performance** panel (shown
above) is the same set of knobs with the same scripts behind them — every
control maps to a variable documented on this page, so the terminal and the app
always produce identical results:

| Panel control | Equivalent |
|---|---|
| Graphics renderer | `P99_RENDERER` (lever 1) |
| Indirect buffer maps *(shown for D9VK)* | `P99_DXVK_INDIRECT_MAPS=1` |
| Command stream (CSMT) *(shown for Stock)* | `P99_WINED3D_CSMT=off`/`serialize` (lever 5) |
| OpenGL version cap *(shown for Stock)* | `P99_WINED3D_MAXGL=2.1`/`4.1` (lever 5) |
| Reported video memory *(shown for Stock)* | `P99_WINED3D_VRAM=512`/`1024` (lever 5) |
| Display scaling | `P99_HIDPI=off`/`on` (lever 4) |
| Smoother visuals | `P99_APPLY_PERF=1 P99_PERF_PROFILE=smoother` (lever 3) |
| Frame-rate cap | `EQ_FPS_CAP=30`/`60` (lever 3) |
| Metal performance HUD *(Diagnostics)* | `P99_METAL_HUD=1` (Measuring) |
| Show DXVK FPS overlay *(Diagnostics, D9VK)* | `P99_DXVK_HUD=fps,frametimes` |
| Verbose renderer logs *(Diagnostics, D9VK)* | `P99_RENDERER_DEBUG=1` |

Set your choices, then press **Apply Performance Settings** with the game
closed. It runs `55-wrapper.sh`, `60-renderer.sh`, `65-wined3d.sh`, and
`35-perf-ini.sh` for you and reports when it's done; turning everything off and
applying reverts cleanly. The wined3d controls only appear while the Stock
renderer is selected — under D9VK those registry values do nothing, so instead
of showing dead switches the app hides them *and* the apply run sweeps any
previously set values away. One terminal-only extra exists:
`P99_WINED3D_RENDERER=vulkan` (see "What doesn't help" below) deliberately has
no panel control. A full audit of what each switch touches on disk lives in
[WHAT-WE-CHANGE.md](WHAT-WE-CHANGE.md).

![The installer's "Applying performance settings" screen: both steps — set the
graphics renderer, apply EQ graphics settings — completed successfully.](img/performance-apply.png)

## Measuring

- **In-game FPS:** EVERQUEST's own frame counter, or just feel out a busy zone
  (e.g. the East Commonlands tunnel, a raid) before and after a change. Under
  d9vk, `P99_DXVK_HUD=fps,frametimes` (lever 1 diagnostics) draws an overlay.
- **The Metal performance HUD** is the wined3d-path equivalent of the DXVK HUD
  — the stock renderer never had an overlay until now. `P99_METAL_HUD=1
  ./55-wrapper.sh` (or the panel's Diagnostics group) makes macOS draw its
  built-in top-right overlay — FPS, frame-time graph, GPU time — on the next
  launch. It's Apple's own instrumentation (macOS 13+), works on any
  Metal-backed process, and is a diagnostic, not a speedup. Honesty note: it
  *should* also appear over the GL-on-Metal shim, since that renders through
  Metal underneath — but this hasn't been confirmed on this stack yet; if it
  doesn't show for you, nothing else is affected, and the d9vk DXVK HUD remains
  the sure thing.
- **`sudo powermetrics --samplers gpu_power,cpu_power -i 1000 -n 10`** — built
  into macOS, no Xcode needed, and unlike Activity Monitor it shows **CPU
  frequency**, which is the number that separates "this stack is slow" from
  "this fanless Air is thermally throttling twenty minutes into a session."
  Worked example — run it during play and look at two things:
    - *P-core frequency over time.* Starts near max (~3–4 GHz) and stays there:
      you are not throttling; slowness is the translation stack, so work levers
      1/4/5. Starts high but sags hundreds of MHz after 15–20 minutes while
      package power falls too: thermal throttling — an FPS cap (lever 3), 1×
      scaling (lever 4), or literally a lap desk will do more than any renderer
      experiment. This is the most common story on fanless Airs.
    - *GPU residency/power.* GPU busy near 100 %: you're fill-bound — lever 4
      (and a smaller window) is the targeted fix. GPU mostly idle while one
      P-core is pinned: the bottleneck is CPU-side translation — GPU-side knobs
      won't help; try lever 1 or lever 5's `csmt=off` pacing experiment.
- **`~/Games/EverQuest/Logs/dbg.txt`** confirms the game reached the engine.
- **Activity Monitor → Window → GPU History** shows whether you're GPU-bound; if
  the GPU is pinned, lever 1 (renderer), lever 4 (scaling), and lever 3
  (particles/FPS cap) help most.
- **`./status.sh`** reports the active `renderer`, the MoltenVK pairing
  (`moltenvk`), display scaling (`hidpi`), the Metal HUD (`metal_hud`), quiet
  wine logging (`winedebug`), the wined3d registry values (`wined3d_*`), and
  whether the smoother INI profile is applied (`perf_ini`) — each read back
  from where the setting actually lands, so "status says on" means the game
  session sees it.

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
- **wined3d's own Vulkan backend (`renderer=vulkan`).** Modern wine's wined3d
  can target Vulkan instead of GL — on paper a third renderer path, distinct
  from D9VK. The registry value exists in this wine, and the engine's
  Vulkan→MoltenVK plumbing demonstrably works (D9VK uses it), but wined3d's
  Vulkan backend was never aimed at MoltenVK and has not been verified on this
  engine — expect a failed launch. It is deliberately **not** in the installer;
  a terminal escape hatch exists for the curious
  (`P99_WINED3D_RENDERER=vulkan ./65-wined3d.sh`, revert with a bare
  `./65-wined3d.sh`). If you get it rendering, that's genuinely interesting —
  open an issue. The `no3d`/`gdi` values disable 3D outright and the script
  refuses them.
- **Disabling Rosetta / "native" tricks.** The current engine depends on
  general-purpose Rosetta; the post-Rosetta direction is research, not a knob (see
  [HOW-IT-WORKS.md](HOW-IT-WORKS.md#post-rosetta-direction)).
