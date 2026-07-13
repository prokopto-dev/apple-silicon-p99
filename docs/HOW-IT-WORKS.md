# How this actually works

This page explains each layer of the stack and — more importantly — *why* each
of the three fixes is required. Everything here was established empirically by
instrumented wine runs (`WINEDEBUG=+seh,+loaddll`) during the original
debugging session, on an Apple M3 / macOS 26.5.

## The problem space

EverQuest Titanium (2005) is a **32-bit x86 Windows** program. A modern Mac is
**64-bit ARM** running macOS. Three translation layers bridge that gap:

| Layer | Translates | Provided by |
|---|---|---|
| Wine | Windows API calls → macOS | Sikarugir engine (open-source CrossOver 24 build) |
| WoW64 | 32-bit Windows code → 64-bit wine | wine's "new WoW64" mode |
| Rosetta 2 | x86_64 instructions → ARM | Apple (Apple Silicon only) |

Each layer is individually mature. The trouble is that P99 ships **anti-cheat
and copy-protection code that deliberately does weird low-level things** —
exactly the things translation layers handle worst.

### Why WoW64 and not a "true 32-bit" wine?

macOS dropped all 32-bit process support in Catalina (2019), and Rosetta 2 only
translates 64-bit binaries. So a 32-bit Windows game *must* run inside a 64-bit
host process. Wine's WoW64 mode does this the same way 64-bit Windows itself
runs 32-bit apps. (CodeWeavers' older "wine32on64" hack was the alternative;
the freely available builds of it are too old to matter now — see
TROUBLESHOOTING for the archaeology.)

## Fix 1: `DSETUP.dll` — the anti-cheat that couldn't

P99 distributes a custom `dsetup.dll` (~5 MB — the real DirectX helper it
impersonates is ~70 KB). It contains P99's client patches and anti-cheat, and
it is packed with **Themida**, a commercial anti-tamper system that encrypts
the real code and unpacks it in memory at load time, running hundreds of
anti-debugger/anti-VM checks as it goes (deliberate exceptions, timing checks,
`CPUID`/VMware-port probes, heap walks…).

**The `dsetup.dll` in recent P99 patch zips (V61+) crashes on modern macOS
during that unpacking phase, before the game ever starts.** This is
acknowledged at the top of the project: in the forum thread
["New patch breaks the game; the cause is dsetup.dll"](https://www.project1999.com/forums/showpost.php?p=3739673&postcount=5),
**Rogean (P99's server administrator)** posted the older build — colloquially
"V58" — at `https://www.project1999.com/files/dsetup.dll`, stating: *"We have
allowed this file to continue working on the server for now due to these
issues. At some point we will have a DLL Update that will supersede the
previous files … but I will get this issue resolved before we do that."*

So the workaround is officially sanctioned, and it comes with a documented
expiry condition: a future P99 DLL update will retire V58 (with the Mac issue
fixed first, per Rogean). The `SKIP_DSETUP_FIX=1` flag on the fix/update
scripts exists for that day.

Observed signatures with the broken V62 DLL (see TROUBLESHOOTING for full
log excerpts):

- On WoW64 engines: instant `EXCEPTION_ACCESS_VIOLATION` jumping to address
  `0x00000000`, → macOS crash-reporter dialog.
- On an old 32-on-64 engine: `DSETUP.dll failed to initialize, status c0000142`.

With V58 in place the Themida unpack completes (~1–2 min at 100% CPU — it does
this **on every launch**; it's decrypting megabytes of code under emulation)
and the game proceeds. This one file was, by a wide margin, the root cause of
the whole porting difficulty.

## Fix 2: `dpvs.dll` — the UPX stub vs. Rosetta

With Themida defeated, the game loads its graphics engine
(`EQGraphicsDX9.DLL`) which pulls in `dpvs.dll` — Umbra's dPVS visibility
culling middleware. That DLL ships **UPX-packed**: compressed on disk, with a
small stub that decompresses the real code into memory when the DLL loads.

Under wine-WoW64-on-Rosetta the stub crashes mid-decompression (read access
violation at `dpvs+0x31A14`, faulting on garbage addresses like `0x60c60400`).
The game catches the exception, unloads the graphics DLL, and silently exits —
no error dialog, no `dbg.txt`.

The fix is elegant: **decompress the file on disk ahead of time** with
`upx -d dpvs.dll`. UPX decompression exactly reconstructs the original
pre-packing DLL (160 KB packed → 311 KB unpacked), so the runtime stub never
executes because it no longer exists. Functionally identical, one command,
fully reversible.

## Fix 3: `eqclient.ini` + Windows XP mode

The last mile is conventional wine lore, from the P99 forums' Mac thread:

- A **minimal `eqclient.ini`** (1024×768 windowed, shaders enabled,
  `MultiPassLighting=FALSE`). EQ regenerates every unspecified setting on first
  boot. Old INIs carried over from PC installs reference display modes and
  card-specific settings that don't exist under wine's renderer.
- **Windows version = XP** in the wine prefix (registry
  `HKCU\Software\Wine\Version=winxp`) — EQ Titanium is a 2005 game; XP is what
  it expects to see.

Rendering runs through wine's built-in `wined3d` (Direct3D → OpenGL → Metal via
Apple's GL stack). It initializes with Shader Model 3.0 and is entirely
adequate for a 2005 engine. The Sikarugir template also bundles alternative
renderers (D9VK: D3D9→Vulkan→MoltenVK→Metal; DXMT: D3D10/11→Metal) — toggles
exist in `P99.app/Contents/Info.plist` if wined3d ever misbehaves, but the
proven config leaves them all off.

## Anatomy of the wrapper

`P99.app` is a **Sikarugir** wrapper (open-source successor of
Wineskin/Kegworks). Layout knowledge that cost real debugging time:

```
P99.app/Contents/
├── Info.plist            "Program Name and Path" + "Program Flags" = what to run
│                          (eqgame.exe MUST get the 'patchme' argument — that's
│                           how P99's dsetup patches are activated)
├── MacOS/launcher         entry point; runs the program via start.exe
├── Frameworks/            FreeType, gnutls, MoltenVK, SDL2… (wine dylib deps)
│   └── renderer/          optional renderer DLL sets (d9vk, dxmt, dxvk…)
├── SharedSupport/
│   ├── wine/              ← the engine (wswine.bundle contents) goes HERE,
│   │                        NOT in Frameworks/ (launcher errors otherwise)
│   └── prefix/            the wine prefix ("C: drive", registry, etc.)
│       └── drive_c/Program Files/EverQuest → symlink to ~/Games/EverQuest
└── drive_c → SharedSupport/prefix/drive_c
```

The game directory stays **outside** the app (symlinked in), so wrapper
rebuilds never touch your game files, characters, or UI settings.

Two non-obvious operational facts:

- **CLI launches must set the *Windows* working directory**, e.g.
  `wine cmd /c 'cd /d C:\Program Files\EverQuest && eqgame.exe patchme'`.
  A unix `cd` into the symlinked folder resolves to a physical path outside the
  prefix, wine falls back to `C:\windows\system32` as CWD, and eqgame silently
  fails to find its files.
- **Every direct wine invocation needs**
  `DYLD_FALLBACK_LIBRARY_PATH="P99.app/Contents/Frameworks:/usr/lib"` so the
  engine finds FreeType and friends. (The launcher does this for you.)

## The complete boot sequence, annotated

What a healthy launch looks like in a `+loaddll` trace:

```
eqgame.exe loaded at 00400000            ← the game (Themida-wrapped)
mss32.dll  loaded (native)               ← Miles Sound System (game's own audio)
DSETUP.dll loaded (native)               ← P99 anti-cheat; V58 = survives unpack
  ~1-2 min of 100% CPU                   ← Themida decrypting under Rosetta
  EXCEPTION_PRIV_INSTRUCTION eax=564d5868 ← "VMXh": VMware-detection probe;
                                            *supposed* to fault on real hardware
dpvs.dll   loaded (native)               ← Umbra culling; must be pre-unpacked
EQGraphicsDX9.DLL loaded (native)        ← the 3D engine
Logs/dbg.txt: "CRender::InitDevice completed successfully"
                                          ← past all three failure points; the
                                            login window is up
```

`~/Games/EverQuest/Logs/dbg.txt` is the game's own boot log — its *existence*
means all the hard parts succeeded. (Note it's in `Logs/`, not the game root.)
