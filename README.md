# Project 1999 on Apple Silicon Macs

Scripts and documentation to run **[Project 1999](https://www.project1999.com/)**
(the classic EverQuest emulator) natively-ish on a modern Mac — Apple Silicon or
Intel — using an entirely **free and open-source** stack. No CrossOver license,
no virtual machine, no Windows install.

Verified working: Apple M3, macOS 26.5, P99 Green, sound + video.

```
EverQuest (32-bit Windows, 2005)
  └─ Wine WoW64  (community build of CodeWeavers' open-source CrossOver 24 wine)
      └─ Rosetta 2  (Apple's x86_64 → ARM translation; Intel Macs skip this)
          └─ macOS
```

## System requirements

| | Requirement | Notes |
|---|---|---|
| 💻 | **Mac** — Apple Silicon (M1–M4) or Intel | Verified on M3 / macOS 26.5; Rosetta 2 is set up automatically on Apple Silicon |
| 🍎 | **macOS 11 (Big Sur) or newer** | Older versions may work but are untested |
| 💾 | **~8 GB free disk** (10 GB to be comfortable) | Fresh-Mac worst case, everything included — see [Disk space breakdown](#disk-space-breakdown) |
| 🎮 | **Your own EverQuest Titanium install** | The 2005 game files are proprietary — *not* included or downloaded here. An installed folder from an old PC works, and so do your original **discs/ISOs** (the setup can run the original installer for you). P99 requires the Titanium client specifically ([P99 install guide](https://wiki.project1999.com/Players:Getting_Started)) |
| 🔑 | **Free [P99 account](https://www.project1999.com/account/)** | Forum account **plus** a login-server account |
| 🌐 | **Internet during setup** | Wrapper template, wine engine, P99 patch files, fixed anti-cheat DLL, and fonts are all fetched from their official sources |
| 🛠 | **Nothing else** | Homebrew and Apple's Command Line Tools are offered/installed automatically by `setup.sh` if missing — no Xcode, no developer knowledge |

Any terminal app works for running the setup — the built-in Terminal, iTerm2,
Warp, whatever you prefer. The quick start uses macOS's built-in Terminal only
because everyone has it.

### Disk space breakdown

Measured on a real install (sizes will vary slightly by version):

| Component | On disk | One-time system dependency? |
|---|---|---|
| Your EverQuest game folder (`~/Games/EverQuest`) | ~4.5 GB | no — this is the game |
| `P99.app` wrapper (template + wine engine + prefix) | ~1.1 GB | no — this is the port |
| Apple Command Line Tools | ~1.8 GB | yes — shared by all developer tooling; you may already have it |
| Homebrew (fresh install) | ~0.5 GB | yes — shared package manager; already-installed Homebrew adds nothing |
| `upx` + `cabextract` (via Homebrew) | ~5 MB | yes |
| Rosetta 2 (Apple Silicon only) | negligible | yes — system component |
| Setup downloads (template 81 MB, engine 164 MB, P99 files 32 MB, fonts+DLL ~10 MB) | ~290 MB, **transient** | deleted after extraction |

**Totals:** ~5.6 GB if you already have Homebrew and the Command Line Tools
(most people who've installed *any* dev tool do); **~8 GB worst case** on a
completely fresh Mac. Uninstalling the game later frees the top two rows
(~5.6 GB); the system dependencies are useful beyond this project and safe to
keep.

## Quick start

**Never used a terminal? You don't need to.**

1. Download this repo as a ZIP (green **Code** button above → *Download ZIP*)
   and unzip it (double-click the ZIP in your Downloads folder).
2. In the unzipped folder, **right-click `Setup.command` → Open → Open**.
   (The right-click dance is only needed the first time — macOS is cautious
   about downloaded scripts from unregistered developers. After that, a plain
   double-click works.)
3. A window opens and walks you through everything with yes/no questions.
   When it asks for your EverQuest folder, **drag the folder into the window**
   and press return.

Prefer a terminal? Same thing by hand (built-in Terminal lives in
Applications → Utilities → Terminal):

```bash
cd ~/Downloads/apple-silicon-p99-main
./setup.sh
```

(Or, if you're comfortable with git: `git clone https://github.com/prokopto-dev/apple-silicon-p99.git && cd apple-silicon-p99 && ./setup.sh`.)

`setup.sh` walks you through everything interactively. It takes care of the
plumbing a fresh Mac is missing: Apple's Command Line Tools (~500 MB — *not*
the giant Xcode app; macOS shows its own install dialog), Homebrew if you
don't have it, then Rosetta and two small helper tools. After that it asks
where your Titanium folder is and handles the rest. If it fails or you quit
partway, just run it again; it resumes where it left off.

<details>
<summary>Prefer to run the steps manually?</summary>

```bash
cd scripts
./00-prereqs.sh                                  # Rosetta, Homebrew tools
./10-build-wrapper.sh                            # builds /Applications/P99.app
./20-install-game.sh /path/to/EverQuest-Titanium # stages game + latest P99 files
./30-apply-mac-fixes.sh                          # the 3 fixes that make it work (required)
./40-launch.sh                                   # go
```
</details>

Then log in with your P99 **login-server** account. After the first successful
run you can just double-click `/Applications/P99.app`.

> **Patience on launch:** the anti-cheat spends **1–2 minutes at 100% CPU with
> no window** every single launch before anything appears. This is normal.

Defaults (override via environment variables — see `scripts/config.sh`):
game files at `~/Games/EverQuest`, wrapper at `/Applications/P99.app`.

## What the fixes actually are

Three independent bugs stand between a stock P99 install and a working game on
macOS. Short version (long version with evidence: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)):

1. **`DSETUP.dll` → V58.** P99's anti-cheat DLL (Themida-packed) from recent
   patch zips crashes on modern macOS before the game can boot. P99 staff host
   an older, sanctioned build that works.
2. **`dpvs.dll` unpacked.** This graphics-culling DLL ships UPX-compressed, and
   its self-decompression stub crashes under wine + Rosetta. `upx -d` removes
   the stub offline.
3. **Fresh `eqclient.ini` + Windows XP mode** — a minimal known-good graphics
   config for this stack.

When something goes wrong, [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
maps every crash signature we encountered to its cause and fix — including
several dead ends that *look* like wine problems but aren't.

Beyond setup, [docs/FAQ.md](docs/FAQ.md) covers quality-of-life topics:
setting up **nParse** (map overlay/timers — it runs natively on macOS, no
wine needed), installing **custom UIs** (DuxaUI etc.), where logs and
character settings live, resizing the window, and the "will this get me
banned?" question.

**Is the V58 DLL legit?** Yes — it's hosted on project1999.com and was posted
by **Rogean, P99's server administrator**, who stated the server deliberately
continues to accept it because of these compatibility issues, and that the Mac
problem will be resolved before any future DLL update supersedes it. It is the
officially sanctioned workaround, not a community hack.

## Staying updated when P99 patches

P99 does **not** auto-patch. New `P99FilesVxx.zip` releases are announced in
the [Patch Notes forum](https://www.project1999.com/forums/forumdisplay.php?f=10)
(typically a few times a year) and are usually mandatory — the server rejects
outdated clients. When a patch lands:

```bash
cd scripts && ./50-update.sh
```

That downloads the newest files zip and **re-applies the Mac fixes** — a fresh
patch zip re-ships the broken `dsetup.dll` and a re-packed `dpvs.dll`, undoing
fixes 1 and 2 (your evolving `eqclient.ini` is left alone). `20-install-game.sh`
discovers new versions automatically by probing upward from the last known
number, so the scripts don't go stale when V63 appears.

⚠️ **One future event to watch for:** P99 staff plan an eventual DLL update
that will *supersede* the V58 workaround (with a proper Mac fix included).
When those patch notes appear, keep the new DLL instead:
`SKIP_DSETUP_FIX=1 ./50-update.sh`.

## Repo layout

```
Setup.command            double-clickable installer (opens Terminal for you)
setup.sh                 guided interactive installer (calls the scripts below)
scripts/
  config.sh              shared settings + pinned component URLs
  00-prereqs.sh          Rosetta / Homebrew / upx
  10-build-wrapper.sh    assemble P99.app (template + wine engine + prefix)
  15-install-from-media.sh  install Titanium from your ISOs/discs via the wrapper
  20-install-game.sh     stage Titanium files, overlay newest P99FilesV*.zip
  30-apply-mac-fixes.sh  the three required fixes (all reversible; .bak files)
  40-launch.sh           launch normally, or --debug for a full wine trace
  50-update.sh           after a P99 patch: fetch newest files + re-apply fixes
  90-uninstall.sh        guided removal (asks before deleting anything)
docs/
  HOW-IT-WORKS.md        what each layer does and why each fix is needed
  TROUBLESHOOTING.md     symptom → cause → fix, with real log signatures
  FAQ.md                 nParse, custom UIs, file locations, rules questions
```

## Roadmap

Ideas we'd like help with (PRs welcome):

- **A real GUI installer.** Today's `setup.sh` already uses native macOS
  dialogs for folder picking, but the goal is a single signed
  `P99 Installer.app`: drag-and-drop your Titanium source, watch a progress
  bar, get a Play button. The plan: wrap the existing scripts (they're the
  tested logic and stay the source of truth) in a SwiftUI shell or
  [Platypus](https://sveinbjorn.org/platypus), then code-sign + notarize so
  Gatekeeper stops requiring the right-click dance. Signing needs an Apple
  Developer ID ($99/yr) — the main reason this isn't done yet.
- **Intel Mac verification.** The stack should work unchanged (it's x86_64
  end-to-end); needs someone with the hardware to confirm.
- **`.bin`/`.cue` handling** in the media installer, so ripped discs don't
  need a manual conversion step.

## Disclaimer — no warranty

This project is provided **as is, without warranty of any kind** (see
[LICENSE](LICENSE) for the full MIT terms). In plain language:

- It might not work on your machine, and it might stop working when macOS,
  wine, or P99 change. Nobody owes you a fix — though issues and PRs are
  welcome.
- The scripts modify files only in the documented locations
  (`/Applications/P99.app`, your game folder, Homebrew) and back up what they
  replace, but **you run them at your own risk**. Read them first if you
  like — they're short, plain shell scripts.
- Your P99 account is your responsibility. The workarounds here are based on
  what P99 staff have publicly sanctioned *today*; server policy can change,
  and this project makes no promises about your account's standing.
- This is a fan effort with **no affiliation** to Daybreak Game Company,
  the Project 1999 team, CodeWeavers, or the Sikarugir project. EverQuest is
  a trademark of Daybreak Game Company LLC.

## Credits & licensing

- [Project 1999](https://www.project1999.com/) — the server, the patch files,
  and the fixed `dsetup.dll` (all fetched from project1999.com).
- [Sikarugir](https://github.com/Sikarugir-App) — open-source wrapper template
  and wine engine builds (successor to Wineskin/Kegworks); engines are compiled
  from [CodeWeavers' LGPL wine sources](https://www.codeweavers.com/products/more-information/source).
- The P99 forums Mac thread, whose posters found the dsetup/ini recipe.
- [UPX](https://upx.github.io/) — used to unpack `dpvs.dll`.

This repo contains **no proprietary files** and must never have game files,
DLLs, or P99 zips committed to it (`.gitignore` enforces the obvious ones).
EverQuest is © Daybreak Game Company. Project 1999 is a fan server operated
with Daybreak's tolerance; play by their rules.
