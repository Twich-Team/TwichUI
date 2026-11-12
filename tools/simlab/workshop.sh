#!/usr/bin/env bash
# The Workshop window scenario (docs/simulator-lab.md "The Workshop scenario", docs/workshop.md "Simulator coverage"): opens the real
# Workshop with /tui workshop and drives its Crafting, Opportunities and Shopping views over synthetic game data
# (scenarios/workshop.lua says exactly what is real and what is fake). Writes to $WOWSIM_LAB/artifacts/workshop-<time>/.
#
# Twelve launches, each from a freshly emptied root and a new empty install (no saved variables):
#   overview  the whole scenario, ending on the Overview (prices, opportunities, plan, professions, next steps), then a screenshot
#   craft     the same, ending on Crafting with a populated queue and a chosen craft's details, then a screenshot
#   opps      the same, ending on Opportunities with a recipe's details, then a screenshot
#   shop      the same, ending on Shopping (mixed sources, a Make row, the missing-price warning), then a screenshot
#   design    the same, ending on the settings window's Workshop page at the "What's it worth?" tooltip designer, then a screenshot
#   small     the same as opps on a 1000x700 screen (the window fits itself to the screen), then a screenshot
#   empty     the same, then the queue emptied and the saved prices taken away: the Overview's empty states, then a screenshot
#   history   the same as opps, with several observed days of price history for the chosen craft, then a screenshot
#   craftlong the same, ending on Crafting with every known recipe queued (a long queue), then a screenshot
#   shopmix   the same, ending on Shopping with Collect rows (a synthetic bank) beside Buy and Make rows, then a screenshot
#   shopcollect  the same, with everything stored: only Collect rows, then a screenshot
#   wrong   the whole scenario with one expectation made deliberately wrong: it must FAIL on that check and on no other
#
#   SIMLAB_ASSETS=0  hide the game install (logic only; the screenshots are worthless then)
#   SIMLAB_SHIM=0    leave the shim out
#
# Evidence: handler-level interaction (Button:Click(), game events fired by the simulator) and in-memory state over FAKE game data.
# Not real input, not the real client, not reload persistence, not how anything looks in the game (addon fonts fall back).
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/workshop-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
WRONG_AT="Peacebloom shared by two recipes: need/in bags/still needed"

export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_EXTRA="TwichUI_Workshop"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"

fixture() {  # name params
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/workshop.lua"; } > "$LAB/fixtures/workshop-$1.lua"
}
fixture overview '{ view = "overview" }'
fixture craft '{ view = "craft" }'
fixture opps '{ view = "opps" }'
fixture shop '{ view = "shop" }'
fixture design '{ view = "design" }'
fixture small '{ view = "opps" }'
fixture empty '{ view = "empty" }'
fixture history '{ view = "history" }'
fixture craftlong '{ view = "craftlong" }'
fixture shopmix '{ view = "shopmix" }'
fixture shopcollect '{ view = "shopcollect" }'
fixture wrong "{ view = \"craft\", wrongAt = \"$WRONG_AT\" }"

repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
launch() {  # name command...
  local name="$1"; shift
  simlab_stage
  [ -d "$ROOT/TwichUI_Workshop" ] || { echo "simlab: TwichUI_Workshop is not in the root" >&2; exit 2; }
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/workshop-$name.lua" "$@" \
    > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  local code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
}

launch overview screenshot --png -o "$RUN/overview.png" --width 1600 --height 1200
launch craft screenshot --png -o "$RUN/craft.png" --width 1600 --height 1200
launch opps screenshot --png -o "$RUN/opps.png" --width 1600 --height 1200
launch shop screenshot --png -o "$RUN/shop.png" --width 1600 --height 1200
launch design screenshot --png -o "$RUN/design.png" --width 1600 --height 1200
launch small screenshot --png -o "$RUN/small.png" --width 1000 --height 700
launch empty screenshot --png -o "$RUN/empty.png" --width 1600 --height 1200
launch history screenshot --png -o "$RUN/history.png" --width 1600 --height 1200
launch craftlong screenshot --png -o "$RUN/craftlong.png" --width 1600 --height 1200
launch shopmix screenshot --png -o "$RUN/shopmix.png" --width 1600 --height 1200
launch shopcollect screenshot --png -o "$RUN/shopcollect.png" --width 1600 --height 1200
launch wrong dump-tree --visible-only

echo "artifacts: $RUN"
repo_after="$(git -C "$REPO" status --porcelain --ignored)"
leak=0
[ "$repo_before" = "$repo_after" ] || { echo "simlab: the repository's status changed during the run" >&2; leak=1; }
find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q . && { echo "simlab: artifacts found inside the addon root" >&2; leak=1; }
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/workshop_verdict.py" "$RUN" "$WRONG_AT" "$SIMLAB_ASSETS" || exit 1
[ "$leak" -eq 0 ] || exit 1
