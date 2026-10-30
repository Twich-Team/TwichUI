#!/usr/bin/env bash
# Shared by smoke.sh and interact.sh (docs/simulator-lab.md); sourced, never run. Sets SIMLAB_DIR, REPO, LAB and ROOT.
#
#   simlab_stage       empties the lab's addon root and copies the working tree in again, so the simulator never sees
#                      the repository and a file left by an earlier run (the shim, a test) can't change the result
#   simlab_disclose    what any result from this lab must be read with
SIMLAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SIMLAB_DIR/../.." && pwd)"
LAB="${WOWSIM_LAB:-$(dirname "$REPO")/wow-ui-sim-lab}"
ROOT="$LAB/roots/twichui"

simlab_stage() {
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
  echo "  - FONTS: TwichUI's own fonts (Cinzel and others) are not drawn; text is Friz Quadrata. No screenshot here is evidence of how text looks or wraps in the game."
  echo "  - NOT THE CLIENT: combat lockdown, taint, secure actions, addon messages, saved data surviving a reload and other addons are not covered. Real-client testing is still required."
}
