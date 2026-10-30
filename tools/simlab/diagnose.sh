#!/usr/bin/env bash
# The delayed-failure diagnostics (docs/simulator-lab.md "Delayed failures"). Runs the simulated clock over a declared
# window (SIMLAB_WINDOW, default 12 simulated seconds) in five launches and judges each one's whole log. Writes to
# $WOWSIM_LAB/artifacts/diagnose-<time>/.
#
#   contract  NO addons    what C_ChatInfo.SendAddonMessage accepts (scenarios/message_contract.lua). Minimal reproduction.
#   baseline  NO addons    the clock over the window with only the simulator and Blizzard's UI (scenarios/group_timers.lua)
#   solo      TwichUI      the character leaves the sample party; the hello timer runs out; nothing may be sent
#   grouped   TwichUI      the sample party kept on purpose: the clock crosses the hello timer and the send is observed
#   login     TwichUI      as grouped, then the lab fires PLAYER_ENTERING_WORLD itself (synthetic) to reach the 6 s login hello
#
# Each launch is a new process from an emptied addon root, with no game assets mounted (logic only; nothing is drawn).
# Known errors are classified by what they are (known_failures.py), never by when they happen and never by hiding them.
#
#   SIMLAB_WINDOW=12   simulated seconds the clock runs in baseline, solo and grouped
#   SIMLAB_SHIM=0      leave the shim out (TwichUI then stops loading Share.lua, so grouped has nothing to send)
#
# Evidence: how the clock, a party and the simulator's addon-message call behave. NOT delivery, receipt, or what the game's
# own client does with the same bytes.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WINDOW="${SIMLAB_WINDOW:-12}"
RUN="$LAB/artifacts/diagnose-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"

export SIMLAB_ASSETS=0
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1"

fixture() {  # name params scenario
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/$3.lua"; } \
    > "$LAB/fixtures/diagnose-$1.lua"
}
fixture contract '{}' message_contract
fixture baseline "{ mode = \"baseline\", window = $WINDOW }" group_timers
fixture solo "{ mode = \"solo\", window = $WINDOW }" group_timers
fixture grouped "{ mode = \"grouped\", window = $WINDOW }" group_timers
fixture login "{ mode = \"login\", window = $WINDOW }" group_timers

repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
launch() {  # name addons(0|1): the simulator from a freshly staged root; its exit status is kept, not fatal
  local name="$1" addons="$2" load=(--no-addons)
  if [ "$addons" = "1" ]; then simlab_stage; load=(--addons-path "$ROOT"); fi
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars "${load[@]}" --exec-lua "@$LAB/fixtures/diagnose-$name.lua" dump-tree --visible-only \
    > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  local code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
}

launch contract 0
launch baseline 0
launch solo 1
launch grouped 1
launch login 1

echo "artifacts: $RUN"
repo_after="$(git -C "$REPO" status --porcelain --ignored)"
leak=0
[ "$repo_before" = "$repo_after" ] || { echo "simlab: the repository's status changed during the run" >&2; leak=1; }
find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q . && { echo "simlab: artifacts found inside the addon root" >&2; leak=1; }
simlab_disclose
echo "  - MESSAGING (this command): sends are watched by a pass-through observer that records the call and then makes it. The simulator's accept or refuse is what is reported; nothing is delivered, received or decoded by another client."
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/diagnose_verdict.py" "$RUN" "$WINDOW" || exit 1
[ "$leak" -eq 0 ] || exit 1
