# FAQ

Quick answers for things that aren't setup problems (those live in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md)) or deep explanations (those live in
[HOW-IT-WORKS.md](HOW-IT-WORKS.md)).

---

## Does this cost anything?

No. Every component is free and open source (or officially free, like the P99
patch files). The only thing money ever bought is your original EverQuest
Titanium copy.

## Will this get me banned? Is the modified dsetup.dll allowed?

The stack itself is just wine — the same way P99's own wiki documents playing
on Linux. The older `dsetup.dll` this project installs is hosted on
project1999.com and was posted by P99's server administrator, who stated the
server intentionally accepts it. The `upx -d` unpack of `dpvs.dll` changes how
the file is stored on disk, not what the code does.

What *will* get you banned is the usual list: multiple simultaneous
characters (P99 is strictly one-at-a-time), automation, and cheat tools. Wine
doesn't exempt you from any of that.

## Does this work on Intel Macs?

It should — the stack is x86_64 already, so Intel Macs simply skip the Rosetta
layer. It's been verified on Apple Silicon (M3); reports welcome.

## I don't have an EverQuest Titanium install — where do I get one?

Legally, you need a copy of EverQuest Titanium Edition (2005). It hasn't been
sold digitally in years, so the usual routes are: an old PC or backup drive
where you once installed it, a friend's install folder (the whole folder
copies cleanly — no installer needed on the Mac side), or a second-hand
physical copy (eBay etc. — Titanium is the 10-disc/DVD "all-in-one" release).
The [P99 Getting Started guide](https://wiki.project1999.com/Players:Getting_Started)
covers what's acceptable in more detail. This project can't and won't download
game files for you.

## I have the install discs / ISOs, not an installed folder — can I use those?

Yes — `setup.sh` asks which you have, or run `scripts/15-install-from-media.sh`
directly. It merges all discs into one folder (so the installer never asks you
to swap discs), then runs the original Windows installer inside the wrapper —
you click through it like it's 2005. Notes:

- Works with `.iso` files **or** physical discs in a drive (add them one at a
  time when prompted). `.bin`/`.cue` rips need converting first
  (`brew install bchunk`, then `bchunk file.bin file.cue out`).
- Use the **default install location** the installer suggests, and at the end
  **uncheck "launch EverQuest"** — the official patcher must never run
  (it would patch past what P99 supports; P99's own files come next).
- Temporarily needs ~8 GB free (staged discs + the install) on top of the
  usual requirements.

## How do I uninstall?

Run `scripts/90-uninstall.sh` — it asks before deleting the wrapper and
(separately) the game folder, and reminds you the game folder contains your
keybinds/UI layouts. Manual version: delete `/Applications/P99.app` and
`~/Games/EverQuest`; the two Homebrew tools go with
`brew uninstall upx cabextract`.

---

## How do I set up nParse (map overlay / timers)?

[nParse](https://github.com/nomns/nparse) gives you a live map with your
position, spell timers, and trigger alerts by reading the game's chat log. Two
things make it pleasant on this stack:

- **It runs natively on macOS** — it's a Python app, so don't put it in wine.
- EQ only feeds it if **chat logging is on**, and Titanium writes logs to
  `~/Games/EverQuest/Logs/`.

Setup:

```bash
# 1. Get nParse (Python 3.10+ required; macOS ships python3)
git clone https://github.com/nomns/nparse.git && cd nparse
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 2. Run it once from its own directory (it reads/writes its config in CWD)
PYTHONPATH="$PWD/src" .venv/bin/python nparse.py
```

Then wire it to the game:

1. In nParse's settings, set the EverQuest **log directory** to
   `~/Games/EverQuest/Logs` (or edit `eq_log_dir` in `nparse.config.json` in
   the nparse folder).
2. Turn on chat logging in EQ. Either type `/log on` every session, or make it
   permanent: with the game closed, set `Log=TRUE` in the `[Defaults]` section
   of `~/Games/EverQuest/eqclient.ini`.
3. The map tracks you via `/loc` — nParse updates your position whenever a
   `/loc` result appears in the log. Most players bind a hotbutton/social that
   spams `/loc` while moving.

A convenient launch script (adjust the path to where you cloned it):

```bash
#!/bin/zsh
cd ~/nparse
export PYTHONPATH="$PWD/src"
exec .venv/bin/python nparse.py "$@"
```

**Is nParse allowed on P99?** It's a passive log reader — it only parses the
text file EQ itself writes, which is the category of tool P99 has historically
permitted. Policies can change; the P99 forums are the authority.

---

## How do I install a custom UI?

EQ UIs are just folders of XML + texture files. The stock UI works, but most
players use a custom one (more visible windows, better inventory, etc.).

1. Get a UI made for the **Titanium client / P99**. Good sources: the
   [P99 wiki's User Interfaces page](https://wiki.project1999.com/User_Interfaces)
   and [EQInterface](https://www.eqinterface.com/) (filter for
   Titanium-compatible; popular P99 choices include DuxaUI and QQUI). UIs
   built for the modern live-EQ client will *not* work.
2. Unzip it into the game's `uifiles` folder, one folder per UI:
   ```
   ~/Games/EverQuest/uifiles/duxaui/
   ```
3. In game, load it with:
   ```
   /loadskin duxaui 1
   ```
   (the trailing `1` keeps your current window positions). Or use Options →
   Display → UI Skin.

Your choice is saved per character in `UI_<charname>_<server>.ini` in the game
folder, so it survives patches and relaunches.

**If a UI breaks the game or renders black windows:** load back to stock with
`/loadskin default 1` — or, if you can't get in game at all, delete the
`UI_<charname>_*.ini` file for that character and EQ falls back to the default
skin. Partial UIs are normal: anything a custom UI doesn't override falls
through to the `default` folder.

---

## Where are my screenshots / logs / character settings?

All under `~/Games/EverQuest/`:

| What | Where |
|---|---|
| Chat logs (nParse reads these) | `Logs/eqlog_<Charname>_project1999.txt` |
| Boot/diagnostic log | `Logs/dbg.txt` |
| Keybinds, colors, graphics | `eqclient.ini` |
| Per-character UI layout + skin choice | `UI_<charname>_<server>.ini` |
| Per-character socials/macros | `<charname>_<server>.ini` |

## Can I make the window bigger?

Yes — edit `eqclient.ini` (game closed) and set all six `Width`/`Height`/
`WidthWindowed`/`HeightWindowed`/`WindowedWidth`/`WindowedHeight` keys to your
size (e.g. 1440×900). Details and a caveat about UI window positions are in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#window-is-tiny-1024768).
