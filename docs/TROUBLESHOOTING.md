# Troubleshooting

Every entry below is a failure mode we actually hit and diagnosed, with the
log signature to match against. Get a trace with:

```bash
cd scripts && ./40-launch.sh --debug     # writes ~/p99-debug-<timestamp>.log
```

The game's own boot log is `~/Games/EverQuest/Logs/dbg.txt` (note: in `Logs/`,
not the game root). If it exists and ends with `CRender::InitDevice completed
successfully`, the hard parts worked and your problem is past the boot stage.

## First, the thing that isn't a bug

**Launch shows nothing for 1–2 minutes while a process burns 100% CPU.**
Normal. Themida (the anti-cheat packer) decrypts the P99 patch DLL in memory on
*every* launch, and it's slow under Rosetta. Don't force-quit; the window
appears when it finishes.

## Symptom → cause → fix

### macOS: "'Setup.command' cannot be opened because it is from an unidentified developer"
**Cause:** Gatekeeper flags anything downloaded from the internet; this repo's
scripts aren't code-signed (they're plain shell scripts you can read).
**Fix:** right-click (or Control-click) `Setup.command` → **Open** → **Open**.
Only needed once. If your Mac is managed/locked down, run it from Terminal
instead: `cd` into the folder and run `./setup.sh` (terminal execution isn't
subject to the same prompt).

### macOS dialog: *"a program on your system has crashed…"* immediately-ish after launch
Trace shows:
```
dispatch_exception code=c0000005 addr=00000000 ip=00000000
```
**Cause:** the broken V61+/V62 `dsetup.dll` (Themida jumps to NULL during
unpack on modern macOS). This is the #1 killer and looks deceptively like a
wine bug — it isn't.
**Fix:** `./30-apply-mac-fixes.sh` (installs P99's sanctioned V58 DLL).

### Trace: `DSETUP.dll failed to initialize, aborting` / `status c0000142`
**Cause:** same broken dsetup.dll, as seen on older wine engines.
**Fix:** same — `./30-apply-mac-fixes.sh`.

### Dialog: *"An internal exception occurred. (Address: 0x…)"*
Two known causes:
1. **On Linux / case-sensitive filesystems:** Titanium's `DSETUP.dll` and
   P99's `dsetup.dll` coexist as two different files and the wrong one loads.
   (Mac default APFS is case-insensitive, so usually not this — but the fix
   script normalizes the name anyway.)
2. **Wine engine too old.** On wine 6.x-era engines Themida gets ~90 s in, then
   dies writing to `0xfffffffc` right after these fixmes:
   ```
   fixme:seh:get_thread_times not implemented on this platform
   fixme:toolhelp:CreateToolhelp32Snapshot Unimplemented: heap list snapshot
   ```
   Themida needs APIs those old builds never implemented on macOS.
   **Fix:** use the pinned engine (`WS12WineCX24.0.7_6`) — don't downgrade.

### Silent exit, no dialog, no dbg.txt; trace shows dpvs.dll then unload
```
Loaded ...\dpvs.dll (native)
Loaded ...\EQGraphicsDX9.DLL (native)
dispatch_exception code=c0000005 addr=<dpvs.dll+0x31A14> reading 60c60400
Unloaded module ...\EQGraphicsDX9.DLL
```
**Cause:** UPX-packed `dpvs.dll` — its decompression stub crashes under
wine-on-Rosetta during graphics init. The game eats the crash and exits
without a word.
**Fix:** `upx -d dpvs.dll` (done by `./30-apply-mac-fixes.sh`). Verify with
`head -c 4096 dpvs.dll | grep -c UPX` → should print `0`.

### Instant exit (~1 s), empty log, wine exit code 53
```
err:module:process_init L"C:\\windows\\system32\\eqgame.exe" not found
```
**Cause:** launched with a unix `cd` into the (symlinked) game folder. Wine
resolves the physical path, which is outside `drive_c`, falls back to
`system32` as the working directory, and can't find `eqgame.exe`.
**Fix:** set the *Windows* CWD:
`wine cmd /c 'cd /d C:\Program Files\EverQuest && eqgame.exe patchme'`
(`40-launch.sh --debug` does this correctly.)

### `wine: created the configuration directory ... but WINEARCH set to win32 ... is a 64-bit installation`
**Cause:** trying to force a 32-bit prefix on a WoW64-only engine. All current
Sikarugir/Kegworks `WS12*` engines are WoW64-only; that's fine — WoW64 is the
supported path in this repo. (The only true 32-on-64 engines on the release
page, `WS11WineCX32Bit*`, are wine 4–6 era and fail the Themida stage; don't
bother.)
**Fix:** don't set `WINEARCH`.

### Launcher error `WineAppInitializationError error 1` / `wineFolderNotFound`
**Cause:** engine extracted to the wrong place inside the wrapper.
**Fix:** the engine's `wswine.bundle` contents must be at
`P99.app/Contents/SharedSupport/wine` (so `.../wine/bin/wine` exists) — *not*
`Contents/Frameworks/wswine.bundle`. `10-build-wrapper.sh` does this.

### `dyld: Library not loaded` / FreeType or libinotify errors on CLI runs
**Cause:** missing `DYLD_FALLBACK_LIBRARY_PATH`.
**Fix:** include `P99.app/Contents/Frameworks` in it (the scripts' `wine_env`
helper and the app launcher both do).

### `dyld: Library not loaded: @rpath/libinotify.0.dylib` from **wineserver**
**Cause:** the engine's binaries look for their dylibs at
`Contents/SharedSupport/` (their `@rpath` is `bin/../../`), but the template
ships them in `Contents/Frameworks/` — and `DYLD_FALLBACK_LIBRARY_PATH` does
not survive into wine's child processes like `wineserver`.
**Fix:** `10-build-wrapper.sh` symlinks every `Frameworks/*.dylib` into
`SharedSupport/`. Re-run it if you see this.

### `missing LC_LOAD_DYLIB (must link with at least libSystem.dylib)` + `Abort trap: 6` at wineboot or launch
**Cause:** macOS 26 (Tahoe) dyld refuses executables built against SDK ≥ 26
that link no dylibs — and some engine builds ship exactly such a
`wine-preloader` (it's deliberately freestanding: its job is reserving the
low 32-bit address range before wine starts). Upstream report:
[Sikarugir#130](https://github.com/Sikarugir-App/Sikarugir/issues/130).
Do **not** just delete the preloader: wine then boots, but `eqgame.exe`
fails with `err:virtual:map_fixed_area out of memory for 0x400000` /
`status c0000018` (nothing reserved its fixed load address).
**Fix:** rewrite the preloader's SDK stamp to pre-26 so dyld treats it as a
legacy binary — `10-build-wrapper.sh` now detects and patches this
automatically (`vtool -set-version-min macos 10.7 15.0` + ad-hoc re-sign).
Re-run it if you hit this on an existing wrapper.

### Worked yesterday; today it crashes at launch or the server rejects me
**Cause:** P99 released a patch (check the
[Patch Notes forum](https://www.project1999.com/forums/forumdisplay.php?f=10)).
Mandatory patches make the server reject old files — and the new zip re-ships
the broken `dsetup.dll` and a re-packed `dpvs.dll`, silently undoing the Mac
fixes.
**Fix:** `./50-update.sh` (fetches newest files, re-applies fixes).
**Exception:** if the patch notes announce a *new dsetup.dll/DLL update* that
supersedes the V58 workaround, keep P99's new DLL instead:
`SKIP_DSETUP_FIX=1 ./50-update.sh`. If that new DLL then crashes on macOS the
old way, V58 will no longer be accepted by the server either — check the Mac
thread on the forums, because the fix will have to come from P99 at that point.

### Game boots but login fails / hangs at server select
- Check `eqhost.txt` contains `Host=login.eqemulator.net:5998` (yes,
  `eqemulator.net` — that IS P99's login server).
- You need a **login-server account** created on the P99 website; forum
  credentials alone don't work.
- P99 allows one account per person; a shared IP (family) can trip this.

### Everything looks washed out / too bright
**Cause:** the fresh `eqclient.ini` let EQ regenerate its default `Gamma=11`,
which is brighter than most players' tuned setting (and wine may not apply
hardware gamma ramps in windowed mode the way a real fullscreen PC install
did).
**Fix:** lower `Gamma=` in `~/Games/EverQuest/eqclient.ini` (`8` is a common
player value; edit while the game is closed — EQ rewrites the file on exit),
or use the in-game Options → Display gamma slider. If the slider visibly does
nothing, that's the windowed-mode gamma-ramp limitation — set `Gamma=` in the
file instead, which EQ applies at render time.

### My keybinds / camera / UI settings from my old install are gone
**Cause:** keybindings (`[KeyMaps]`), camera and gameplay prefs (`[Options]`),
and text colors all live in `eqclient.ini` — which fix 3 replaces to get a
known-good graphics config.
**Fix:** current versions of `30-apply-mac-fixes.sh` automatically restore
those sections (plus your gamma) from `eqclient.ini.pre-mac.bak` after writing
the fresh file. If you applied an older version of the script, your original
is still at `~/Games/EverQuest/eqclient.ini.pre-mac.bak` — copy the
`[KeyMaps]`/`[Options]`/`[TextColors]`/`[HitsMode]` sections back in (game
closed), keeping the new `[Defaults]` and `[VideoMode]`.

### Some UI text is fuzzy/smeared while other text is sharp
**Cause:** missing Microsoft core fonts. EQ rasterizes UI text via Windows
font APIs; elements whose requested font (usually Arial) is missing get wine's
substitute, which renders visibly softer — so the UI ends up a mix of crisp
and fuzzy depending on which font each element asked for. Low-contrast chat
colors show the blur worst.
**Fix:** current `10-build-wrapper.sh` installs the core fonts. On an existing
wrapper, re-run it (idempotent), or drop the corefonts `.TTF` files into
`P99.app/Contents/SharedSupport/prefix/drive_c/windows/Fonts/` — wine loads
that folder automatically. Restart the game afterward (fonts load at startup).
Note: `winetricks corefonts` itself **fails on macOS** ("`%AppData%` returned
empty string") because SIP strips `DYLD_*` variables through its `/bin/sh` —
use the script instead.

### Red and green chat text is fuzzy/hard to read; white and yellow are sharp
**Cause:** not a rendering bug — physics. Saturated single-channel colors
(`255,0,0` red, `0,128,0` green) light only one LCD subpixel per pixel and
carry little luminance, so antialiased small text in them looks soft; white
and yellow light 2–3 subpixels at high luminance and look sharp. EQ's default
message colors include several of these dark saturated values.
**Fix:** brighten/desaturate the offenders in `[TextColors]` in
`eqclient.ini` (game closed — EQ rewrites the file on exit), e.g.
`0,128,0 → 90,220,90` and `255,0,0 → 255,90,90`; or adjust live in-game under
Options → Colors.

### In game, but textures missing / graphics glitches
Known residual on this stack (forum posters suspect bad installs rather than
wine). Dials to try, in order:
1. Make sure the MS core fonts are installed (see fuzzy-text entry above).
2. Renderer toggles in `P99.app/Contents/Info.plist` (`D9VK`, `DXMT`,
   `D3DMETAL` — set one to `1`). The template bundles the DLLs under
   `Contents/Frameworks/renderer/`. Note our testing found the launcher doesn't
   always copy them automatically; d9vk can be installed manually by copying
   `renderer/d9vk/wine/i386-windows/d3d9.dll` over
   `prefix/drive_c/windows/syswow64/d3d9.dll` (back it up first).
3. Verify game-file integrity against a known-good install.

### Game stutters or feels choppy (especially on newer Apple Silicon, e.g. M5)
**Cause:** two things compound. (1) The stock renderer is wine's `wined3d`, which
runs Direct3D 9 → OpenGL → Apple's *deprecated* GL-on-Metal shim — the slow path on
modern GPUs. (2) The wine msync scheduling flag was not reaching the double-click /
Play session: that launch is `open P99.app`, which LaunchServices runs detached and
does not inherit the `WINEESYNC/WINEMSYNC` that `wine_env()` sets, so thread hand-offs
ran unsynchronized (now fixed via the wrapper's `Info.plist` — see fix 2).
**Fix (in order of impact):**
1. Rebuild the wrapper once so msync reaches the game: `./10-build-wrapper.sh` (it
   skips the finished pieces and just refreshes the launch env). A routine
   `./50-update.sh` does **not** do this.
2. *Optionally* try the D9VK renderer (Direct3D 9 → Vulkan → MoltenVK → Metal):
   `P99_RENDERER=d9vk ./60-renderer.sh` (or the installer app's Performance
   panel). On some machines it's a real win; on others it is much **slower**
   (see the next entry). Fully reversible — `P99_RENDERER=wined3d
   ./60-renderer.sh` restores the stock renderer and touches nothing else.
3. Cap the frame rate and/or trim EQ's own load: `P99_APPLY_PERF=1
   P99_PERF_PROFILE=smoother EQ_FPS_CAP=60 ./35-perf-ini.sh` (game closed).
Full guide with tradeoffs and how to measure: [PERFORMANCE.md](PERFORMANCE.md).

### After switching to D9VK the game is much SLOWER (single-digit FPS)
**Cause:** a known outcome on some machines (reported on an M4 MacBook Pro), not
a broken install. Earlier versions of the switch compounded it by loading a
MoltenVK build years newer than the bundled DXVK 1.10 (with a slow
argument-buffer mode on by default) and by never enabling DXVK's async shader
compilation — both fixed by re-running the switch with the current scripts. What
remains is a stack limitation: a 32-bit game under wine's WoW64 pays a heavy
penalty on every GPU-memory map unless the Vulkan driver supports
`VK_EXT_map_memory_placed`, which the bundled MoltenVK builds do not — and a
2005 engine maps buffers every frame. On machines where that cost dominates,
D9VK will stay slow no matter what.
**Fix:** switch back — `P99_RENDERER=wined3d ./60-renderer.sh` (or Performance
panel → Stock → Apply). If you first installed d9vk before this fix existed,
re-applying it once (`P99_RENDERER=d9vk ./60-renderer.sh`) picks up the MoltenVK
pairing + tuning; it may be worth one retry before giving up on it.
**If reporting it:** re-apply with diagnostics —
`P99_RENDERER=d9vk P99_RENDERER_DEBUG=1 ./60-renderer.sh`, launch once, then
attach `~/Games/EverQuest/eqgame_d3d9.log`, the `[mvk-info]` MoltenVK
version/argument-buffer lines from a `./40-launch.sh --debug` trace, and the
`renderer` + `moltenvk` lines from `./status.sh`.

### Sound issues
Sound runs through the game's own Miles Sound System (`mss32.dll`), not
GStreamer — so ignore wine's GStreamer warnings; they're harmless here.

### Window is tiny (1024×768)
That's the known-good boot config. Once the game runs, edit
`~/Games/EverQuest/eqclient.ini` → set all of `Width`/`Height`/
`WidthWindowed`/`HeightWindowed`/`WindowedWidth`/`WindowedHeight` to your
preferred size (e.g. 1440×900). Keep `WindowedMode=TRUE`; alt-tab behavior
fullscreen under wine is rough. Bonus: if you migrated an old install, your
per-character `UI_*.ini` files store window positions in pixels — matching
your old resolution puts every chat/hotbar window back where you had it.

## Diagnostic reference: reading a wine trace

- `dispatch_exception code=c000008e` (float divide-by-zero) and
  `code=c0000096` (privileged instruction) with `eax=564d5868` ("VMXh") during
  the CPU-burn phase are **normal** — Themida raises exceptions on purpose as
  anti-debug/anti-VM checks and handles them itself.
- `code=c0000005` (access violation) that Themida/the game does **not** handle
  (followed by module unload, `failed to initialize`, or the crash-reporter
  dialog) is a real failure — match it against the table above.
- `Loaded ...EQGraphicsDX9.DLL` + no exception after it + `Logs/dbg.txt`
  updating = you've won; anything wrong after that point is game-config
  territory, not the translation stack.
