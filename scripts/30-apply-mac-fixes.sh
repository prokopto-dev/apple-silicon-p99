#!/bin/bash
# 30-apply-mac-fixes.sh — the three fixes that make P99 actually run on macOS.
# Each one is explained in docs/HOW-IT-WORKS.md; each backs up what it replaces.
# Idempotent: detects already-applied state and skips.
set -euo pipefail
cd "$(dirname "$0")"; source ./config.sh

check_game || die "no game files at $GAME_DIR — run 20-install-game.sh first"
cd "$GAME_DIR"

# ---------------------------------------------------------------------------
say "Fix 1/3: dsetup.dll -> official V58 build"
# The dsetup.dll in current P99Files zips (V61+) is packed with a Themida
# (anti-cheat) configuration that crashes on modern macOS before the game can
# start. P99's server admin (Rogean) hosts this older build as the sanctioned
# workaround and has confirmed the server accepts it.
# Known-good: md5 b02ab111c9b95c2ddad4e3bdbe9c53cd, 4,963,248 bytes.
#
# Escape hatch: when P99 eventually ships a NEW dsetup.dll that supersedes the
# V58 workaround (staff have said this will come with a Mac fix), skip this
# step with SKIP_DSETUP_FIX=1.
if [ "${SKIP_DSETUP_FIX:-0}" = "1" ]; then
  say "  SKIP_DSETUP_FIX=1 — keeping the dsetup.dll shipped by the P99 patch"
else
# GOOD_MD5 (the V58 build's checksum) is defined in config.sh, shared with
# the check_fix_dsetup probe.
current_md5() { md5 -q "$1" 2>/dev/null || true; }

# The file may exist as dsetup.dll and/or DSETUP.dll depending on source.
# Normalize to the uppercase name eqgame requests.
if [ -f dsetup.dll ] && [ ! -f DSETUP.dll ]; then mv dsetup.dll DSETUP.dll.tmp && mv DSETUP.dll.tmp DSETUP.dll; fi

if [ "$(current_md5 DSETUP.dll)" = "$GOOD_MD5" ]; then
  say "  already the V58 build — skipping"
else
  [ -f DSETUP.dll ] && cp DSETUP.dll "DSETUP.dll.orig.bak" && say "  backed up existing DLL as DSETUP.dll.orig.bak"
  curl -fL --progress-bar -o DSETUP.dll.download "$DSETUP_URL"
  [ "$(current_md5 DSETUP.dll.download)" = "$GOOD_MD5" ] \
    || warn "downloaded dsetup.dll has unexpected md5 ($(current_md5 DSETUP.dll.download)) — P99 may have updated it; proceeding anyway"
  mv DSETUP.dll.download DSETUP.dll
  say "  installed V58 DSETUP.dll"
fi
fi

# ---------------------------------------------------------------------------
say "Fix 2/3: unpack dpvs.dll (UPX)"
# dpvs.dll (Umbra visibility culling) ships UPX-compressed. Its in-memory
# self-decompression stub crashes under Wine-on-Rosetta during graphics init.
# Decompressing the file offline removes the stub entirely; the DLL is
# byte-identical in function.
if head -c 4096 dpvs.dll | grep -q UPX; then
  cp dpvs.dll dpvs.dll.upx.bak
  upx -d dpvs.dll
  say "  unpacked (original saved as dpvs.dll.upx.bak)"
else
  say "  already unpacked — skipping"
fi

# ---------------------------------------------------------------------------
say "Fix 3/3: known-good eqclient.ini"
# Minimal graphics config confirmed working on Apple Silicon (from the P99
# forums' Mac thread). EQ fills in every other setting on first boot.
# Bump WindowedWidth/WindowedHeight afterward if you want a bigger window.
# One-shot: once applied (backup marker exists), never clobber the evolving
# INI again. Delete eqclient.ini.pre-mac.bak to force a rewrite.
if [ -f eqclient.ini.pre-mac.bak ]; then
  say "  already applied (eqclient.ini.pre-mac.bak exists) — skipping"
else
  if [ -f eqclient.ini ]; then
    cp eqclient.ini eqclient.ini.pre-mac.bak
    say "  backed up existing eqclient.ini as eqclient.ini.pre-mac.bak"
  else
    touch eqclient.ini.pre-mac.bak
  fi
  # Optional performance keys (empty unless EQ_*/P99_PERF_PROFILE is set), appended
  # to the end of [Defaults]. With nothing opted in this file is byte-identical to
  # the proven config. Resolution keys below are never affected. See config.sh.
  PERF_LINES="$(perf_ini_lines)"
  {
    cat <<'EOF'
[Defaults]
Sound=TRUE
ShowForCard9.16.13.4052=0
TextureQuality=1
VertexShaders=TRUE
20PixelShaders=TRUE
14PixelShaders=TRUE
1xPixelShaders=TRUE
MultiPassLighting=FALSE
UseLitBatches=TRUE
WindowedModeXOffset=1
WindowedModeYOffset=1
WindowedMode=TRUE
EOF
    [ -n "$PERF_LINES" ] && printf '%s\n' "$PERF_LINES"
    cat <<'EOF'
[VideoMode]
Width=1024
Height=768
WidthWindowed=1024
HeightWindowed=768
WindowedWidth=1024
WindowedHeight=768
FullscreenBitsPerPixel=32
FullscreenRefreshRate=0
EOF
  } > eqclient.ini
  [ -n "$PERF_LINES" ] && touch "$GAME_DIR/.p99-perf-applied"
  say "  wrote eqclient.ini"

  # Carry the user's personal settings over from their original INI. The fresh
  # file above only needs to control graphics ([Defaults]/[VideoMode]); the
  # sections below are keybinds (WASD!), camera, colors, and UI prefs — losing
  # them is the #1 "my config disappeared" complaint. Gamma is restored too:
  # EQ's regenerated default (11) looks washed out vs. typical player settings.
  if [ -s eqclient.ini.pre-mac.bak ]; then
    python3 - <<'PYEOF'
import re

def parse(path):
    sections, order, cur = {}, [], None
    for line in open(path, encoding='latin-1'):
        line = line.rstrip('\r\n')
        m = re.match(r'\[(.+)\]\s*$', line)
        if m:
            cur = m.group(1)
            if cur not in sections:
                sections[cur] = []
                order.append(cur)
        elif cur is not None:
            sections[cur].append(line)
    return sections, order

cur_s, cur_o = parse('eqclient.ini')
old_s, _ = parse('eqclient.ini.pre-mac.bak')

for sec in ('KeyMaps', 'Options', 'TextColors', 'HitsMode', 'News'):
    if sec in old_s:
        if sec not in cur_s:
            cur_o.append(sec)
        cur_s[sec] = old_s[sec]

old_gamma = next((l for l in old_s.get('Defaults', []) if l.startswith('Gamma=')), None)
if old_gamma:
    d = [l for l in cur_s.get('Defaults', []) if not l.startswith('Gamma=')]
    d.append(old_gamma)
    cur_s['Defaults'] = d

with open('eqclient.ini', 'w', encoding='latin-1') as f:
    for sec in cur_o:
        f.write(f'[{sec}]\n')
        for l in cur_s[sec]:
            if l.strip():
                f.write(l + '\n')
print('  restored user sections (keybinds, camera, colors, gamma) from backup')
PYEOF
  fi
fi

say "All fixes applied. Next: ./40-launch.sh"
