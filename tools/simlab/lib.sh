#!/usr/bin/env bash
# Shared by smoke.sh and interact.sh (docs/simulator-lab.md); sourced, never run. Sets SIMLAB_DIR, REPO, LAB and ROOT.
#
#   simlab_stage       empties the lab's addon root and copies the working tree in again, so the simulator never sees
#                      the repository and a file left by an earlier run (the shim, a test) can't change the result
#   simlab_disclose    what any result from this lab must be read with
# Under zsh BASH_SOURCE is empty and every path below would resolve against the current directory, which once created a
# lab folder in the wrong place. Refuse instead of guessing.
[ -n "${BASH_SOURCE[0]:-}" ] || { echo "simlab: lib.sh must be sourced from bash (BASH_SOURCE is empty here); run the scripts with bash" >&2; return 2 2>/dev/null || exit 2; }
SIMLAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SIMLAB_DIR/../.." && pwd)"
LAB="${WOWSIM_LAB:-$(dirname "$REPO")/wow-ui-sim-lab}"
ROOT="$LAB/roots/twichui"
SIMLAB_MARKER=".simlab-lab"                       # setup.sh writes it; its presence is what says a folder is a lab
SIMLAB_MARKER_TEXT="twichui-simlab-lab 1"
SIMLAB_KNOWN="downloads release deps home artifacts fixtures roots wtf xdg env.sh"   # what setup.sh makes (env.sh: an early lab had one)

_simlab_within() { [ "$1" = "$2" ] || case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac; }

# simlab_check_lab use|adopt: refuses (status 2) unless LAB is a folder this tooling may touch, then sets LAB and ROOT to
# its resolved path. "use" (every runner) needs the marker. "adopt" (setup.sh only) also accepts a folder that does not
# exist, is empty, or holds nothing but the folders setup.sh makes. Nothing is created or deleted here.
simlab_check_lab() {
  local mode="${1:-use}" canon wow home entry
  wow="$(realpath -m -- "${SIMLAB_WOW:-/mnt/c/Program Files (x86)/World of Warcraft}")" || return 2
  home=""
  [ -z "${HOME:-}" ] || home="$(realpath -m -- "$HOME")" || return 2
  [ -n "${LAB:-}" ] || { echo "simlab: the lab path is empty" >&2; return 2; }
  case "$LAB" in /*) ;; *) echo "simlab: the lab path must be absolute: $LAB" >&2; return 2 ;; esac
  canon="$(realpath -m -- "$LAB")" || return 2
  if [ "$canon" = "/" ] || [ "$canon" = "$home" ] || _simlab_within "$canon" "$REPO" || _simlab_within "$REPO" "$canon" \
     || { [ -z "$home" ] || _simlab_within "$home" "$canon"; } || _simlab_within "$canon" "$wow" || _simlab_within "$wow" "$canon"; then
    echo "simlab: refusing $canon (filesystem root, home, the repository or the game install, or a folder holding one)" >&2
    return 2
  fi
  if [ -f "$canon/$SIMLAB_MARKER" ] && [ ! -L "$canon/$SIMLAB_MARKER" ] && [ "$(cat -- "$canon/$SIMLAB_MARKER")" = "$SIMLAB_MARKER_TEXT" ]; then
    :
  elif [ "$mode" = "adopt" ]; then
    if [ -e "$canon" ]; then
      [ -d "$canon" ] || { echo "simlab: $canon is not a folder" >&2; return 2; }
      for entry in "$canon"/* "$canon"/.[!.]* "$canon"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        case " $SIMLAB_KNOWN " in *" $(basename -- "$entry") "*) ;; *)
          echo "simlab: $canon holds $(basename -- "$entry") and no $SIMLAB_MARKER, so it is not a lab; use another WOWSIM_LAB" >&2; return 2 ;;
        esac
      done
    fi
  else
    echo "simlab: $canon has no $SIMLAB_MARKER; it is not a lab (run tools/simlab/setup.sh, or check WOWSIM_LAB)" >&2
    return 2
  fi
  LAB="$canon"
  ROOT="$LAB/roots/twichui"
}

# setup.sh sets SIMLAB_LIB_DEFER=1 and adopts the folder itself; everything else is checked before it can create anything.
if [ "${SIMLAB_LIB_DEFER:-0}" != "1" ]; then
  simlab_check_lab use || { return 2 2>/dev/null || exit 2; }
fi

simlab_stage() {
  simlab_check_lab use || return 2
  # The one deletion below: only the root's own folder, a real folder inside the lab's own roots folder.
  [ "$ROOT" = "$LAB/roots/twichui" ] && [ -d "$LAB/roots" ] && [ ! -L "$LAB/roots" ] && [ ! -L "$ROOT" ] \
    || { echo "simlab: $ROOT is not the lab's own root folder" >&2; return 2; }
  mkdir -p "$ROOT" "$LAB/fixtures" "$LAB/wtf"
  # Every run passes --no-saved-vars; an empty lab WTF folder means nothing else could be read either.
  if [ -n "$(find "$LAB/wtf" -type f -print -quit)" ]; then
    echo "simlab: $LAB/wtf holds files, so a run would not start as a new install; empty it" >&2
    return 2
  fi
  # Only what a page needs: the core and its load-on-demand settings window.
  local copy=("$REPO/!!!TwichUI" "$REPO/TwichUI_Settings")
  [ "${SIMLAB_SHIM:-1}" = "1" ] && copy+=("$SIMLAB_DIR/shim/!!!!SimLabShims")
  rm -rf -- "${ROOT:?}"   # rsync --delete would leave a folder from an earlier run, such as the shim, in place
  mkdir -p "$ROOT"
  rsync -a --exclude='*:Zone.Identifier' "${copy[@]}" "$ROOT/"
  if [ "${SIMLAB_SHIM:-1}" = "1" ]; then
    [ -d "$ROOT/!!!!SimLabShims" ] || { echo "simlab: the shim was asked for and is not in the root" >&2; return 2; }
  else
    [ ! -e "$ROOT/!!!!SimLabShims" ] || { echo "simlab: the shim is in the root though SIMLAB_SHIM=0" >&2; return 2; }
  fi
}

simlab_disclose() {
  echo "Read this result with:"
  if [ "${SIMLAB_SHIM:-1}" = "1" ]; then
    echo "  - SHIMMED API: C_ChatInfo.RegisterAddonMessagePrefix and IsAddonMessagePrefixRegistered are lab stand-ins that only remember names. Nothing about addon messaging is tested."
  else
    echo "  - NO SHIM: this run is the unshimmed control; the two messaging APIs are missing, as in the simulator's own Forever profile."
  fi
  echo "  - VERSION MISMATCH: the simulator's Blizzard UI is Forever 1.60.1.70532; the installed game is newer (art comes from it). Not the client's real UI code."
  echo "  - FONTS: the simulator (v0.1.37) loads only the game's own fonts; every addon font path, TwichUI's Cinzel included, is measured and drawn in Friz Quadrata (docs/simulator-lab.md \"Fonts\"). Screenshots are STRUCTURAL, not a visual or wrapping validation."
  echo "  - NOT THE CLIENT: combat lockdown, taint, secure actions, addon messages, saved data surviving a reload and other addons are not covered. Real-client testing is still required."
}
