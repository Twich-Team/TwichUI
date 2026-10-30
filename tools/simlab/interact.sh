#!/usr/bin/env bash
# The simulator interaction scenario (docs/simulator-lab.md): drives the real "Notification appearance" settings page
# through its checkbox, drop-downs and slider from a clean synthetic profile, and judges what the page and the saved
# configuration did. Writes to $WOWSIM_LAB/artifacts/interact-<time>/.
#
# Four launches, each in the sandbox, each from a new empty install (the root is emptied and copied again first):
#   a      the whole scenario, then a screenshot of where it ends
#   a2     the same again, no screenshot: the saved result must be identical (reproducibility)
#   before the first step only, then a screenshot (the page as it opens)
#   wrong  the whole scenario with one expectation made deliberately wrong: it must FAIL on that check and no other
#
#   SIMLAB_WINDOW=12 simulated seconds the clock runs (default 12: past the group hello and two voice-settings ticks)
#   SIMLAB_SHIM=0   leave the shim out (the page does not need it; a run without it shows what the shim changes)
#   SIMLAB_ASSETS=0 hide the game install (logic only; no screenshot is worth looking at)
#
# Evidence: initialization, page construction, handler-level control interaction, in-memory state mutation. Not
# persistence across a reload, not the real client, not how anything looks (see interact_verdict.py's table).
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="$LAB/artifacts/interact-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
WRONG_AT="slider-clamp-max: typed 500 saved as"

WINDOW="${SIMLAB_WINDOW:-12}"   # simulated seconds the clock runs in the scenario (its last step); see docs/simulator-lab.md
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
# The simulator's own switch for a character that is never in a party (it otherwise adds one after PLAYER_ENTERING_WORLD).
# The scenario still calls Lab.Solo(), which then checks the state (and does nothing, having nothing to leave).
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"

# The scenario is read by the simulator from the lab's fixtures folder (read-only inside the sandbox).
fixture() {  # name params
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/notify_look.lua"; } \
    > "$LAB/fixtures/interact-$1.lua"
}
fixture a "{ window = $WINDOW }"
fixture a2 "{ window = $WINDOW }"
fixture before '{ stopAfter = "initial" }'
fixture wrong "{ wrongAt = \"$WRONG_AT\", window = $WINDOW }"

repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
launch() {  # name command...: the simulator from a freshly staged root; its exit status is kept, not fatal
  local name="$1"; shift
  simlab_stage
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/interact-$name.lua" "$@" \
    > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  local code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
}

launch a screenshot --png -o "$RUN/after.png" --width 1600 --height 1200 --dump-tree TwichUI
launch a2 dump-tree
launch before screenshot --png -o "$RUN/before.png" --width 1600 --height 1200 --dump-tree TwichUI
launch wrong dump-tree

echo "artifacts: $RUN"
repo_after="$(git -C "$REPO" status --porcelain --ignored)"
leak=0
[ "$repo_before" = "$repo_after" ] || { echo "simlab: the repository's status changed during the run" >&2; leak=1; }
find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q . && { echo "simlab: artifacts found inside the addon root" >&2; leak=1; }
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/interact_verdict.py" "$RUN" "$WRONG_AT" "$SIMLAB_ASSETS" "$WINDOW" || exit 1
[ "$leak" -eq 0 ] || exit 1
