#!/usr/bin/env bash
# Overlapse installer / updater for Steam Deck (and any Linux PC with Steam).
#
#   curl -fsSL https://raw.githubusercontent.com/mremad/overlapse-builds/main/installer/install.sh | bash
#
# - downloads the latest Overlapse build from this repo's GitHub releases
# - installs it to ~/Games/Overlapse (or updates an existing install in place)
# - adds it to Steam as a non-Steam game (once) with its library art, logo and icon
# Run it again any time to update. Saves and settings are never touched.

set -euo pipefail

REPO="mremad/overlapse-builds"
NAME="Overlapse"
RAW="https://raw.githubusercontent.com/$REPO/main/installer"
API="https://api.github.com/repos/$REPO/releases/latest"

say()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*"; exit 1; }

command -v curl >/dev/null || die "curl is needed"
command -v python3 >/dev/null || die "python3 is needed"

# where to install: keep an existing install (older ones lived in ~/Games/TimeSplit)
DIR="$HOME/Games/Overlapse"
EXE="$DIR/Overlapse.x86_64"
if [ -f "$HOME/Games/TimeSplit/TimeSplit.x86_64" ] && [ ! -f "$EXE" ]; then
    DIR="$HOME/Games/TimeSplit"
    EXE="$DIR/TimeSplit.x86_64"
fi
mkdir -p "$DIR"

say "Overlapse installer"
say "Checking the latest release..."
REL="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$API")" || die "Can't reach GitHub. Check the internet connection."
read -r BUILD URL SIZE SHA < <(python3 - "$REL" <<'PY'
import json, sys, urllib.request
rel = json.loads(sys.argv[1])
assets = {a["name"]: a["browser_download_url"] for a in rel.get("assets", [])}
man = json.load(urllib.request.urlopen(assets["manifest.json"]))
f = man["linux"]
print(man["build"], assets[f["file"]], f["size"], f["sha256"])
PY
) || die "The latest release has no Linux build."

HAVE=0
[ -f "$DIR/.build" ] && HAVE="$(cat "$DIR/.build" 2>/dev/null || echo 0)"
if [ -f "$EXE" ] && [ "$HAVE" = "$BUILD" ]; then
    ok "Overlapse build $BUILD is already installed."
else
    say "Downloading build $BUILD ($((SIZE / 1048576)) MB)..."
    curl -fL --progress-bar -o "$EXE.download" "$URL" || die "Download failed."
    GOT="$(sha256sum "$EXE.download" | cut -d' ' -f1)"
    [ "$GOT" = "$SHA" ] || { rm -f "$EXE.download"; die "Checksum mismatch, try again."; }
    [ -f "$EXE" ] && mv -f "$EXE" "$EXE.old"
    mv "$EXE.download" "$EXE"
    chmod +x "$EXE"
    echo "$BUILD" > "$DIR/.build"
    ok "Installed build $BUILD to $DIR"
fi

# ---------------------------------------------------------------- Steam library entry + art
ART="$DIR/art"
mkdir -p "$ART"
for f in capsule wide hero logo icon; do
    curl -fsSL -o "$ART/$f.png" "$RAW/art/$f.png" || warn "Couldn't fetch $f art"
done

STEAM=""
for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [ -d "$d/userdata" ] && STEAM="$d" && break
done
if [ -z "$STEAM" ]; then
    warn "Steam not found: the game is installed at $EXE, add it to Steam by hand."
    exit 0
fi

# Steam rewrites its shortcut list on exit, so it has to be closed while we edit it
if pgrep -x steam >/dev/null 2>&1 || pgrep -f "steamwebhelper" >/dev/null 2>&1; then
    say "Closing Steam to add the game to the library..."
    steam -shutdown >/dev/null 2>&1 || true
    for i in $(seq 1 30); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
    RESTART=1
else
    RESTART=0
fi

python3 - "$STEAM" "$EXE" "$DIR" "$ART" "$NAME" <<'PY'
import os, shutil, struct, sys, zlib, glob

steam, exe, start, art, name = sys.argv[1:6]

# --- Steam's binary VDF (shortcuts.vdf): 0x00 map, 0x01 string, 0x02 int32, 0x08 end
def read(b, i=0):
    out = {}
    while True:
        t = b[i]; i += 1
        if t == 8:
            return out, i
        j = b.index(0, i); k = b[i:j].decode("utf-8", "replace"); i = j + 1
        if t == 0:
            out[k], i = read(b, i)
        elif t == 1:
            j = b.index(0, i); out[k] = b[i:j].decode("utf-8", "replace"); i = j + 1
        elif t == 2:
            out[k] = struct.unpack("<i", b[i:i + 4])[0]; i += 4
        elif t == 7:
            out[k] = ("u64", struct.unpack("<Q", b[i:i + 8])[0]); i += 8
        else:
            raise ValueError("unknown vdf type %d" % t)

def write(d):
    o = bytearray()
    for k, v in d.items():
        kb = k.encode() + b"\0"
        if isinstance(v, dict):
            o += b"\x00" + kb + write(v)
        elif isinstance(v, tuple):
            o += b"\x07" + kb + struct.pack("<Q", v[1])
        elif isinstance(v, int):
            o += b"\x02" + kb + struct.pack("<i", v)
        else:
            o += b"\x01" + kb + str(v).encode() + b"\0"
    return bytes(o) + b"\x08"

quoted = '"%s"' % exe
appid = (zlib.crc32((quoted + name).encode()) & 0xFFFFFFFF) | 0x80000000
signed = struct.unpack("<i", struct.pack("<I", appid))[0]

users = [u for u in glob.glob(os.path.join(steam, "userdata", "*")) if os.path.basename(u).isdigit() and os.path.basename(u) != "0"]
for u in users:
    cfg = os.path.join(u, "config")
    os.makedirs(cfg, exist_ok=True)
    path = os.path.join(cfg, "shortcuts.vdf")
    root = {"shortcuts": {}}
    if os.path.exists(path) and os.path.getsize(path) > 0:
        try:
            b = open(path, "rb").read()
            root, _ = read(b, 0)
        except Exception as e:
            print("  could not read %s (%s), leaving it alone" % (path, e))
            continue
        shutil.copy(path, path + ".bak")
    sc = root.setdefault("shortcuts", {})
    found = None
    for k, s in sc.items():
        e = str(s.get("Exe", s.get("exe", ""))).strip('"')
        if e == exe or (s.get("AppName", s.get("appname")) in (name, "TimeSplit") and e.endswith(".x86_64")):
            found = s
            break
    if found is None:
        idx = str(max([int(k) for k in sc if k.isdigit()] + [-1]) + 1)
        found = sc[idx] = {"appid": signed, "AppName": name, "Exe": quoted, "StartDir": '"%s"' % start,
                           "icon": os.path.join(art, "icon.png"), "ShortcutPath": "", "LaunchOptions": "",
                           "IsHidden": 0, "AllowDesktopConfig": 1, "AllowOverlay": 1, "OpenVR": 0, "Devkit": 0,
                           "DevkitGameID": "", "DevkitOverrideAppID": 0, "LastPlayTime": 0, "FlatpakAppID": "",
                           "tags": {}}
        print("  added Overlapse to the Steam library (user %s)" % os.path.basename(u))
    else:
        found["AppName"] = name
        found["Exe"] = quoted
        found["StartDir"] = '"%s"' % start
        found["icon"] = os.path.join(art, "icon.png")
        if "appid" not in found:
            found["appid"] = signed
        print("  Overlapse is already in the Steam library (user %s): refreshed" % os.path.basename(u))
    open(path, "wb").write(b"\x00shortcuts\x00" + write(sc) + b"\x08")
    # library art: grid/<appid>p.png (capsule), <appid>.png (wide), _hero, _logo, _icon
    aid = found["appid"] & 0xFFFFFFFF
    grid = os.path.join(cfg, "grid")
    os.makedirs(grid, exist_ok=True)
    for src, suffix in [("capsule", "p"), ("wide", ""), ("hero", "_hero"), ("logo", "_logo"), ("icon", "_icon")]:
        f = os.path.join(art, src + ".png")
        if os.path.exists(f):
            shutil.copy(f, os.path.join(grid, "%d%s.png" % (aid, suffix)))
PY

if [ "$RESTART" = "1" ]; then
    say "Starting Steam again..."
    (nohup steam >/dev/null 2>&1 &) || true
fi
ok "Done! Overlapse is in your Steam library (on a Deck: return to Gaming Mode)."
ok "Updates: run this installer again, or in game: Settings > Updates > Check for updates online."
