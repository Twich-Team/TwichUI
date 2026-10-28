#!/usr/bin/env bash
# Updates the layout package TwichUI ships (Classic and Compact Adventure) from your own saved settings.
# docs/layouts/updating-the-bundled-layout.md explains every step; run with --help for the options.
#
# What it does, in order:
#   1. copies your EllesmereUI.lua and !!!TwichUI.lua saved files to a temporary folder (the originals are only read)
#   2. captures Classic Adventure into TwichUI_Layouts/ClassicData.lua, then Compact Adventure into CompactData.lua
#      (tools/layout_capture.lua; Compact keeps only what differs from Classic)
#   3. points any font from another addon's folder at TwichUI's own copy of that font, when TwichUI ships one
#   4. raises the package revision in TwichUI_Layouts/Classic.lua, so players who have the layout get it as an update
#   5. runs the offline tests
# If a capture fails, the files it would have replaced are put back. Nothing is committed, deployed or released.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

WOW="/mnt/c/Program Files (x86)/World of Warcraft"
CLIENT="forever"
ACCOUNT=""
SV_DIR=""
CLASSIC_PROFILE="TwichUI - Classic Adventure"
COMPACT_PROFILE="TwichUI - Minimal Adventure"
TWICHUI_PROFILE="Default"
BUMP=1
TESTS=1

usage() {
    cat <<EOF
Usage: tools/update_bundled_layout.sh [options]

  --client forever|retail    which game client's saved files to read (default: forever)
  --account NAME             the WTF account folder (default: the only one there is)
  --sv DIR                   read EllesmereUI.lua and !!!TwichUI.lua from this folder instead
  --wow DIR                  the World of Warcraft folder (default: $WOW)
  --classic-profile NAME     EllesmereUI profile for Classic Adventure (default: "$CLASSIC_PROFILE")
  --compact-profile NAME     EllesmereUI profile for Compact Adventure (default: "$COMPACT_PROFILE")
  --twichui-profile NAME     TwichUI profile both layouts share (default: "$TWICHUI_PROFILE")
  --no-bump                  leave the package revision as it is
  --no-tests                 don't run the offline tests afterwards
  -h, --help                 this text

Log out of the game first: it writes your settings to disk only when you log out or reload.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --client) CLIENT="$2"; shift 2 ;;
        --account) ACCOUNT="$2"; shift 2 ;;
        --sv) SV_DIR="$2"; shift 2 ;;
        --wow) WOW="$2"; shift 2 ;;
        --classic-profile) CLASSIC_PROFILE="$2"; shift 2 ;;
        --compact-profile) COMPACT_PROFILE="$2"; shift 2 ;;
        --twichui-profile) TWICHUI_PROFILE="$2"; shift 2 ;;
        --no-bump) BUMP=0; shift ;;
        --no-tests) TESTS=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mStopped:\033[0m %s\n' "$*" >&2; exit 1; }

case "$CLIENT" in forever|retail) ;; *) die "--client must be forever or retail" ;; esac
command -v lua5.1 >/dev/null || die "lua5.1 isn't installed (sudo apt install lua5.1 lua-bitop)"
lua5.1 -e 'require("bit")' 2>/dev/null || die "lua5.1 can't load luabitop (sudo apt install lua-bitop)"
command -v python3 >/dev/null || die "python3 isn't installed (it fixes font paths and the revision)"

# --- 1. find the saved files and copy them ------------------------------------------------------------------------
if [ -z "$SV_DIR" ]; then
    ACCOUNTS="$WOW/_${CLIENT}_/WTF/Account"
    [ -d "$ACCOUNTS" ] || die "no saved settings for $CLIENT at $ACCOUNTS (use --wow, --client or --sv)"
    if [ -z "$ACCOUNT" ]; then
        mapfile -t found < <(find "$ACCOUNTS" -mindepth 1 -maxdepth 1 -type d ! -name SavedVariables -printf '%f\n')
        [ "${#found[@]}" -eq 1 ] || die "more than one account folder in $ACCOUNTS (${found[*]}): pick one with --account"
        ACCOUNT="${found[0]}"
    fi
    SV_DIR="$ACCOUNTS/$ACCOUNT/SavedVariables"
fi
EUI_SV="$SV_DIR/EllesmereUI.lua"
TW_SV="$SV_DIR/!!!TwichUI.lua"
HINT=""
[ "$CLIENT" = "forever" ] && HINT=" (no settings saved from WoW: Forever yet? --client retail reads Retail's)"
[ -f "$EUI_SV" ] || die "no EllesmereUI.lua in $SV_DIR$HINT"
[ -f "$TW_SV" ] || die "no !!!TwichUI.lua in $SV_DIR$HINT"

if command -v tasklist.exe >/dev/null 2>&1 && tasklist.exe 2>/dev/null | grep -qi '^wow'; then
    warn "World of Warcraft looks like it is running. The files on disk are from your last logout or reload."
fi

WORK="$(mktemp -d)"
BACKUP="$WORK/backup"
mkdir -p "$BACKUP"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
cp "$EUI_SV" "$WORK/EllesmereUI.lua"
cp "$TW_SV" "$WORK/TwichUI.lua"
say "Reading copies of:"
echo "  $EUI_SV  (changed $(date -r "$EUI_SV" '+%Y-%m-%d %H:%M'))"
echo "  $TW_SV  (changed $(date -r "$TW_SV" '+%Y-%m-%d %H:%M'))"

FILES=(TwichUI_Layouts/ClassicData.lua TwichUI_Layouts/CompactData.lua TwichUI_Layouts/Classic.lua
       docs/layouts/capture-classic-adventure.md docs/layouts/capture-compact-adventure.md)
for f in "${FILES[@]}"; do cp "$f" "$BACKUP/$(basename "$f")"; done
restore() {
    for f in "${FILES[@]}"; do cp "$BACKUP/$(basename "$f")" "$f"; done
    echo "The files it would have replaced are back as they were."
}

# --- 2. capture both layouts ----------------------------------------------------------------------------------------
TODAY="$(date '+%Y-%m-%d')"
say "Capturing Classic Adventure from \"$CLASSIC_PROFILE\" (TwichUI: \"$TWICHUI_PROFILE\")"
if ! lua5.1 tools/layout_capture.lua --eui "$WORK/EllesmereUI.lua" --twichui "$WORK/TwichUI.lua" \
        --eui-profile "$CLASSIC_PROFILE" --twichui-profile "$TWICHUI_PROFILE" \
        --out TwichUI_Layouts/ClassicData.lua --report docs/layouts/capture-classic-adventure.md \
        --name CLASSIC_CAPTURE --title "Classic Adventure" --client "$CLIENT" --made "$TODAY"; then
    restore
    die "the Classic capture failed (its message is above)"
fi

say "Capturing Compact Adventure from \"$COMPACT_PROFILE\" (only what differs from Classic)"
if ! lua5.1 tools/layout_capture.lua --eui "$WORK/EllesmereUI.lua" --twichui "$WORK/TwichUI.lua" \
        --eui-profile "$COMPACT_PROFILE" \
        --out TwichUI_Layouts/CompactData.lua --report docs/layouts/capture-compact-adventure.md \
        --name COMPACT_CAPTURE --title "Compact Adventure" --client "$CLIENT" --made "$TODAY" \
        --shared-with TwichUI_Layouts/ClassicData.lua --shared-name CLASSIC_CAPTURE; then
    restore
    die "the Compact capture failed (its message is above)"
fi

# --- 3. fonts from another addon's folder (not TwichUI's, not the EllesmereUI suite's) ------------------------------------------------------------------------------
say "Checking font paths"
python3 - <<'PY'
import os, re
fonts = set(os.listdir("!!!TwichUI/media/fonts"))
pat = re.compile(r'"(Interface\\\\AddOns\\\\([^\\"]+)\\\\[^"]*?\\\\?([^\\"]+\.(?:ttf|otf)))"', re.I)
fixed, left = [], []
for path in ("TwichUI_Layouts/ClassicData.lua", "TwichUI_Layouts/CompactData.lua"):
    text = open(path, encoding="utf-8").read()
    def swap(m):
        addon, name = m.group(2), m.group(3)
        if addon.lower() == "!!!twichui" or addon.lower().startswith("ellesmereui"):
            return m.group(0)   # TwichUI's own, or the EllesmereUI suite's (every player of the layout has those)
        match = next((f for f in fonts if f.lower() == name.lower()), None)
        if match is None:
            left.append((path, m.group(1)))
            return m.group(0)
        fixed.append((path, m.group(1), match))
        return '"Interface\\\\AddOns\\\\!!!TwichUI\\\\media\\\\fonts\\\\%s"' % match
    new = pat.sub(swap, text)
    if new != text:
        open(path, "w", encoding="utf-8").write(new)
for path, old, name in fixed:
    print("  %s: %s -> TwichUI's own %s" % (path, old.replace("\\\\", "\\"), name))
for path, old in left:
    print("  WARNING %s: %s is in another addon's folder and TwichUI has no copy of it." % (path, old.replace("\\\\", "\\")))
    print("           Players won't have it. Pick one of TwichUI's fonts for it in EllesmereUI and run this again.")
if not fixed and not left:
    print("  every font is TwichUI's, EllesmereUI's or the game's own")
PY

# --- 4. the package revision -----------------------------------------------------------------------------------------------
if [ "$BUMP" -eq 1 ]; then
    say "Raising the package revision"
    python3 - <<'PY'
import re
path = "TwichUI_Layouts/Classic.lua"
text = open(path, encoding="utf-8").read()
pat = re.compile(r'(id = "twichui-adventure", revision = )(\d+)')
found = pat.findall(text)
if len(found) != 1:
    raise SystemExit("  couldn't find the one revision line in %s; change it by hand" % path)
old = int(found[0][1])
open(path, "w", encoding="utf-8").write(pat.sub(lambda m: m.group(1) + str(old + 1), text))
print("  revision %d -> %d (%s)" % (old, old + 1, path))
PY
else
    say "Leaving the package revision as it is (--no-bump)"
fi

# --- 5. tests ---------------------------------------------------------------------------------------------------------
STATUS=0
if [ "$TESTS" -eq 1 ]; then
    say "Running the offline tests (a few minutes)"
    if ./tests/run.sh > "$WORK/tests.log" 2>&1; then
        tail -1 "$WORK/tests.log"
    else
        STATUS=1
        grep -A5 '^FAIL' "$WORK/tests.log" || true
        tail -1 "$WORK/tests.log"
        warn "some tests failed. If you moved things, tests that check the captured layout exactly need updating"
        warn "(docs/layouts/updating-the-bundled-layout.md, \"When tests fail\"). The new files are kept."
    fi
fi

# --- what changed, and what is next -------------------------------------------------------------------------------------
say "What changed"
git --no-pager diff --stat -- "${FILES[@]}" || true
cat <<EOF

Next:
  - read docs/layouts/capture-classic-adventure.md and capture-compact-adventure.md (what was kept and left out)
  - try it in game: tools/deploy.sh, then /tui layout
  - commit the files above, then release as RELEASING.md says
To throw this run away: git checkout -- ${FILES[*]}
EOF
exit $STATUS
