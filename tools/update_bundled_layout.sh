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
#   5. checks the package as players will get it (tools/check_bundled_layout.lua: valid, portable media), then the offline tests
# Two kinds of stop, never mixed up (RH-1):
#   * generating failed (a capture, the font fix, the revision, or anything unexpected): every file it touched is put back
#     exactly as it was, and it exits 1;
#   * the result failed a check (media players don't have, an invalid package, a failing test): the new files are kept so you
#     can look at them, the ones from before are saved to a folder it names, and it exits 1 saying the result is NOT ready.
# Only a run that generated and passed every check ends with "Done" and exit 0 (with --no-tests: "not tested").
# It never commits, deploys or releases, and touches no file but the five below.
#
# --from-published is the other way in (docs/layouts/presets.md): instead of recapturing profiles, it imports a package the author
# published in game, exactly (tools/import_published_layout.lua): its choices (the TwichUI presets) into ChoicesData.lua, its layers
# into the two data files when they differ, its revision into Classic.lua, and a report; then the same checks, with the round trip
# (the bundled package must resolve exactly as the published one). The profile recapture never writes ChoicesData.lua, so the
# presets an author approved in game are kept by every later recapture.
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
RETURNED=""
FROM_PUBLISHED=0
TEXT=""
PUB_REVISION=""
PUB_HASH=""
LIST=0

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
  --no-tests                 don't run the offline tests afterwards (the result is then "not tested")
  --returned reset|release|keep
                             what players who have the layout get for a TwichUI setting the last capture named and your
                             profile no longer has (usually put back to the default). Asked for only when there is one:
                             docs/layouts/updating-the-bundled-layout.md, "Settings you put back to the default"

  --from-published           import a package published in game instead of recapturing profiles (docs/layouts/presets.md):
                             from the published list in your saved !!!TwichUI.lua (found as above, or --sv DIR), or --text
    --text FILE              a file holding the text the workspace's "Export for bundling" shows
    --revision N             which published revision (needed when more than one is saved)
    --hash FINGERPRINT       and which one, when two share a revision
    --list                   list the published packages in the saved file and stop
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
        --returned) RETURNED="$2"; shift 2 ;;
        --from-published) FROM_PUBLISHED=1; shift ;;
        --text) TEXT="$2"; shift 2 ;;
        --revision) PUB_REVISION="$2"; shift 2 ;;
        --hash) PUB_HASH="$2"; shift 2 ;;
        --list) LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mStopped:\033[0m %s\n' "$*" >&2; exit 1; }

case "$CLIENT" in forever|retail) ;; *) die "--client must be forever or retail" ;; esac
case "$RETURNED" in ""|reset|release|keep) ;; *) die "--returned must be reset, release or keep" ;; esac
command -v lua5.1 >/dev/null || die "lua5.1 isn't installed (sudo apt install lua5.1 lua-bitop)"
lua5.1 -e 'require("bit")' 2>/dev/null || die "lua5.1 can't load luabitop (sudo apt install lua-bitop)"
command -v python3 >/dev/null || die "python3 isn't installed (it fixes font paths and the revision)"
if [ $FROM_PUBLISHED -eq 0 ] && { [ -n "$TEXT" ] || [ -n "$PUB_REVISION" ] || [ -n "$PUB_HASH" ] || [ $LIST -eq 1 ]; }; then
    die "--text, --revision, --hash and --list go with --from-published"
fi
if [ $FROM_PUBLISHED -eq 1 ] && [ -n "$RETURNED" ]; then die "--returned is for a profile recapture, not --from-published"; fi
case "$PUB_REVISION" in ""|*[!0-9]*) [ -z "$PUB_REVISION" ] || die "--revision is a whole number" ;; esac

# --- the other way in: a package published in game ------------------------------------------------------------------
if [ $FROM_PUBLISHED -eq 1 ]; then
    WORK="$(mktemp -d)"
    ARGS=()
    if [ -n "$TEXT" ]; then
        [ -f "$TEXT" ] || die "no file $TEXT"
        cp "$TEXT" "$WORK/export.txt"
        ARGS=(--text "$WORK/export.txt")
        SRC_DESC="the exported text in $TEXT (a copy is read)"
    else
        if [ -z "$SV_DIR" ]; then
            ACCOUNTS="$WOW/_${CLIENT}_/WTF/Account"
            [ -d "$ACCOUNTS" ] || { rm -rf "$WORK"; die "no saved settings for $CLIENT at $ACCOUNTS (use --wow, --client, --sv or --text)"; }
            if [ -z "$ACCOUNT" ]; then
                mapfile -t found < <(find "$ACCOUNTS" -mindepth 1 -maxdepth 1 -type d ! -name SavedVariables -printf '%f\n')
                [ "${#found[@]}" -eq 1 ] || { rm -rf "$WORK"; die "more than one account folder in $ACCOUNTS (${found[*]}): pick one with --account"; }
                ACCOUNT="${found[0]}"
            fi
            SV_DIR="$ACCOUNTS/$ACCOUNT/SavedVariables"
        fi
        [ -f "$SV_DIR/!!!TwichUI.lua" ] || { rm -rf "$WORK"; die "no !!!TwichUI.lua in $SV_DIR"; }
        cp "$SV_DIR/!!!TwichUI.lua" "$WORK/TwichUI.lua"
        ARGS=(--sv "$WORK/TwichUI.lua")
        SRC_DESC="the published list in $SV_DIR/!!!TwichUI.lua (changed $(date -r "$SV_DIR/!!!TwichUI.lua" '+%Y-%m-%d %H:%M'); a copy is read)"
    fi
    [ -n "$PUB_REVISION" ] && ARGS+=(--revision "$PUB_REVISION")
    [ -n "$PUB_HASH" ] && ARGS+=(--hash "$PUB_HASH")
    say "Source"
    echo "  $SRC_DESC"
    if [ $LIST -eq 1 ]; then
        lua5.1 tools/import_published_layout.lua "${ARGS[@]}" --list; rc=$?
        rm -rf "$WORK"; exit $rc
    fi
    FILES=(TwichUI_Layouts/ChoicesData.lua TwichUI_Layouts/ClassicData.lua TwichUI_Layouts/CompactData.lua TwichUI_Layouts/Classic.lua
           docs/layouts/import-published.md)
    BACKUP="$WORK/backup"
    mkdir -p "$BACKUP"
    for f in "${FILES[@]}"; do if [ -f "$f" ]; then cp "$f" "$BACKUP/$(basename "$f")"; fi; done
    restore() {
        for f in "${FILES[@]}"; do
            if [ -f "$BACKUP/$(basename "$f")" ]; then cp "$BACKUP/$(basename "$f")" "$f"; else rm -f "$f"; fi
        done
        echo "The files it would have replaced are back as they were."
    }
    PHASE="generate"
    on_exit_pub() {
        local status=$?
        if [ "$PHASE" = "generate" ] && [ $status -ne 0 ]; then
            printf '\033[31mStopped while importing.\033[0m ' >&2
            restore >&2
        elif [ "$PHASE" = "check" ] && [ $status -ne 0 ]; then
            KEPT="$(mktemp -d "${TMPDIR:-/tmp}/twichui-bundled-before.XXXXXX")"
            cp "$BACKUP"/* "$KEPT/" 2>/dev/null || true
            printf '\n\033[31mNOT READY:\033[0m the new files are kept so you can look at them, but they failed a check and must not be committed.\n' >&2
            echo "The files as they were before this run are saved in $KEPT" >&2
            echo "To put them back: git checkout -- ${FILES[*]} (or copy them from that folder)" >&2
        fi
        rm -rf "$WORK"
        exit $status
    }
    trap on_exit_pub EXIT
    say "Importing the published package"
    OUT="$WORK/import.log"
    if ! lua5.1 tools/import_published_layout.lua "${ARGS[@]}" 2>&1 | tee "$OUT"; then die "the import failed (its message is above)"; fi
    if grep -q "^Not imported" "$OUT"; then exit 1; fi
    if grep -q "^Already bundled" "$OUT"; then
        PHASE="done"
        say "Done: already bundled, nothing changed"
        exit 0
    fi
    PHASE="check"
    STATUS=0
    say "Checking the package as players will get it, and that it is the published one"
    if ! lua5.1 tools/check_bundled_layout.lua --published "${ARGS[@]:0:2}" ${PUB_REVISION:+--published-revision "$PUB_REVISION"} ${PUB_HASH:+--published-hash "$PUB_HASH"}; then
        STATUS=1
        warn "the package fails the check above"
    fi
    TESTED="not tested (--no-tests)"
    if [ "$TESTS" -eq 1 ]; then
        say "Running the offline tests (a few minutes)"
        if ./tests/run.sh > "$WORK/tests.log" 2>&1; then
            tail -1 "$WORK/tests.log"
            TESTED="tests passed"
        else
            STATUS=1
            TESTED="TESTS FAILED"
            grep -A5 '^FAIL' "$WORK/tests.log" || true
            tail -1 "$WORK/tests.log"
            warn "some tests failed (docs/layouts/updating-the-bundled-layout.md, \"When tests fail\")"
        fi
    fi
    say "What changed"
    git --no-pager diff --stat -- "${FILES[@]}" 2>/dev/null || ls -l "${FILES[@]}"
    if [ $STATUS -ne 0 ]; then exit $STATUS; fi
    PHASE="done"
    say "Done: imported, checked, $TESTED"
    cat <<EOF
Next:
  - read docs/layouts/import-published.md (where it came from, what changed, the presets it holds)
  - look at the diff: git diff -- ${FILES[*]}
  - try it in game: tools/deploy.sh, then /tui layout
  - commit the files above, then release as RELEASING.md says
To throw this run away: git checkout -- ${FILES[*]} (and remove docs/layouts/import-published.md if git doesn't know it yet)
EOF
    exit 0
fi

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
cp "$EUI_SV" "$WORK/EllesmereUI.lua"
cp "$TW_SV" "$WORK/TwichUI.lua"
say "Source"
echo "  client:            $CLIENT"
echo "  saved files:       $SV_DIR"
echo "  EllesmereUI.lua:   changed $(date -r "$EUI_SV" '+%Y-%m-%d %H:%M') (a copy is read; the original is not touched)"
echo "  !!!TwichUI.lua:    changed $(date -r "$TW_SV" '+%Y-%m-%d %H:%M')"
echo "  Classic Adventure: EllesmereUI \"$CLASSIC_PROFILE\", TwichUI \"$TWICHUI_PROFILE\""
echo "  Compact Adventure: EllesmereUI \"$COMPACT_PROFILE\" (TwichUI settings shared with Classic)"

FILES=(TwichUI_Layouts/ClassicData.lua TwichUI_Layouts/CompactData.lua TwichUI_Layouts/Classic.lua
       docs/layouts/capture-classic-adventure.md docs/layouts/capture-compact-adventure.md)
for f in "${FILES[@]}"; do cp "$f" "$BACKUP/$(basename "$f")"; done
restore() {
    for f in "${FILES[@]}"; do cp "$BACKUP/$(basename "$f")" "$f"; done
    echo "The files it would have replaced are back as they were."
}
# PHASE: "generate" (a failure puts everything back), "check" (a failure keeps the new files for a look), "done"
PHASE="generate"
KEPT=""
on_exit() {
    local status=$?
    if [ "$PHASE" = "generate" ] && [ $status -ne 0 ]; then
        printf '\033[31mStopped while generating.\033[0m ' >&2
        restore >&2
    elif [ "$PHASE" = "check" ] && [ $status -ne 0 ]; then
        KEPT="$(mktemp -d "${TMPDIR:-/tmp}/twichui-bundled-before.XXXXXX")"
        cp "$BACKUP"/* "$KEPT/"
        printf '\n\033[31mNOT READY:\033[0m the new files are kept so you can look at them, but they failed a check and must not be committed.\n' >&2
        echo "The files as they were before this run are saved in $KEPT" >&2
        echo "To put them back: for f in ${FILES[*]}; do cp \"$KEPT/\$(basename \$f)\" \"\$f\"; done" >&2
    fi
    rm -rf "$WORK"
    exit $status
}
trap on_exit EXIT

# --- 2. capture both layouts ----------------------------------------------------------------------------------------
TODAY="$(date '+%Y-%m-%d')"
say "Capturing Classic Adventure from \"$CLASSIC_PROFILE\" (TwichUI: \"$TWICHUI_PROFILE\")"
if ! lua5.1 tools/layout_capture.lua --eui "$WORK/EllesmereUI.lua" --twichui "$WORK/TwichUI.lua" \
        --eui-profile "$CLASSIC_PROFILE" --twichui-profile "$TWICHUI_PROFILE" \
        --out TwichUI_Layouts/ClassicData.lua --report docs/layouts/capture-classic-adventure.md \
        --name CLASSIC_CAPTURE --title "Classic Adventure" --client "$CLIENT" --made "$TODAY" \
        ${RETURNED:+--returned "$RETURNED"}; then
    die "the Classic capture failed (its message is above). If it lists settings you put back to the default, run again with --returned reset, release or keep"
fi

say "Capturing Compact Adventure from \"$COMPACT_PROFILE\" (only what differs from Classic)"
if ! lua5.1 tools/layout_capture.lua --eui "$WORK/EllesmereUI.lua" --twichui "$WORK/TwichUI.lua" \
        --eui-profile "$COMPACT_PROFILE" \
        --out TwichUI_Layouts/CompactData.lua --report docs/layouts/capture-compact-adventure.md \
        --name COMPACT_CAPTURE --title "Compact Adventure" --client "$CLIENT" --made "$TODAY" \
        --shared-with TwichUI_Layouts/ClassicData.lua --shared-name CLASSIC_CAPTURE; then
    die "the Compact capture failed (its message is above)"
fi

# --- 3. fonts from another addon's folder (not TwichUI's, not the EllesmereUI suite's) ------------------------------------------------------------------------------
say "Checking font paths"
FONTS_RC=0
python3 - <<'PY' || FONTS_RC=$?
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
if left:
    raise SystemExit(3)   # players don't have that file: the result fails its check (step 5)
PY
case "$FONTS_RC" in
    0|3) ;;
    *) die "fixing the font paths failed (its message is above)" ;;
esac

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

# --- 5. checks: the package as players get it, then the tests ---------------------------------------------------------------
PHASE="check"
STATUS=0
say "Checking the package as players will get it"
if [ "$FONTS_RC" -eq 3 ]; then
    STATUS=1
    warn "a font above is in another addon's folder and TwichUI has no copy of it: players don't have that file"
fi
if ! lua5.1 tools/check_bundled_layout.lua; then
    STATUS=1
    warn "the package fails the check above (it names files players don't have, or isn't a valid package)"
fi
TESTED="not tested (--no-tests)"
if [ "$TESTS" -eq 1 ]; then
    say "Running the offline tests (a few minutes)"
    if ./tests/run.sh > "$WORK/tests.log" 2>&1; then
        tail -1 "$WORK/tests.log"
        TESTED="tests passed"
    else
        STATUS=1
        TESTED="TESTS FAILED"
        grep -A5 '^FAIL' "$WORK/tests.log" || true
        tail -1 "$WORK/tests.log"
        warn "some tests failed. If you moved things on purpose, only the tests that check the captured layout exactly may be"
        warn "updated (docs/layouts/updating-the-bundled-layout.md, \"When tests fail\"); the others guard rules that never change"
        warn "to accept a capture."
    fi
fi

# --- what changed, and what is next -------------------------------------------------------------------------------------
say "What changed"
git --no-pager diff --stat -- "${FILES[@]}" 2>/dev/null || ls -l "${FILES[@]}"
if [ $STATUS -ne 0 ]; then exit $STATUS; fi   # NOT READY (on_exit says so and keeps a copy of the files from before)
PHASE="done"
say "Done: generated, checked, $TESTED"
cat <<EOF
Source: $CLIENT saved files in $SV_DIR; EllesmereUI "$CLASSIC_PROFILE" and "$COMPACT_PROFILE", TwichUI "$TWICHUI_PROFILE".

Next:
  - read docs/layouts/capture-classic-adventure.md and capture-compact-adventure.md (what was kept and left out)
  - try it in game: tools/deploy.sh, then /tui layout
  - commit the files above, then release as RELEASING.md says
To throw this run away: git checkout -- ${FILES[*]}
EOF
exit 0
