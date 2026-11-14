#!/usr/bin/env bash
# The Workshop window scenario (docs/simulator-lab.md "The Workshop scenario", docs/workshop.md "Simulator coverage"): opens the real
# Workshop with /tui workshop and drives its Crafting, Opportunities and Shopping views over synthetic game data
# (scenarios/workshop.lua says exactly what is real and what is fake). Writes to $WOWSIM_LAB/artifacts/workshop-<time>/.
#
# Twenty-five launches, each from a freshly emptied root and a new empty install (no saved variables):
#   overview  the whole scenario, ending on the Overview (prices, opportunities, plan, professions, next steps), then a screenshot
#   craft     the same, ending on Crafting with a populated queue and a chosen craft's details, then a screenshot
#   opps      the same, ending on Opportunities with a recipe's details, then a screenshot
#   shop      the same, ending on Shopping (mixed sources, a Make row, the missing-price warning), then a screenshot
#   design    the same, ending on the settings window's Workshop page at the "What's it worth?" tooltip designer, then a screenshot
#   small     the same as opps on a 1000x700 screen (the window fits itself to the screen), then a screenshot
#   smallov   the same, ending on the Overview with four professions on a 1000x700 screen, then a screenshot
#   empty     the same, then the queue emptied and the saved prices taken away: the Overview's empty states, then a screenshot
#   history   the same as opps, with several observed days of price history for the chosen craft, then a screenshot
#   craftlong the same, ending on Crafting with every known recipe queued (a long queue), then a screenshot
#   shopmix   the same, ending on Shopping with Collect rows (a synthetic bank) beside Buy and Make rows, then a screenshot
#   shopcollect  the same, with everything stored: only Collect rows, then a screenshot
#   strategy  (P2) the same, ending on the full strategy of Copper Belt Buckle (Opportunities, View strategy), then a screenshot
#   confirm   (P2) the same, with the confirmation before the optimized plan is added open over it, then a screenshot
#   compact, compactcraft (P2.1) the compact view (Travel, Craft) in the window's place; tooltip (P2.1) an intermediate's item tooltip in the
#             strategy view; smallstrat (P2.1) the strategy view on a 1000x700 screen; shopafter (P2.1) Shopping after a material arrived;
#             notice (P2.1) the progress notice after the player's own Crafted one
#   stratlong (P2) the same, every known recipe queued, the strategy of the whole queue open (a long scrolling list), then a screenshot
#   planning  (P2) the same, the plan of the chosen recipe still being worked out (the job never finishes), then a screenshot
#   nodata    (P2) the same, a recipe whose materials aren't known chosen: no strategy and no invented figure, then a screenshot
#   override  (P2) the same, Shopping with the player's own source chosen for the made material, then a screenshot
#   wrong   the whole scenario with one expectation made deliberately wrong: it must FAIL on that check and on no other
#
#   SIMLAB_ONLY="opps craft"  run only the named launches (a quick look while working; the full run, with none named, is the evidence)
#   SIMLAB_ASSETS=0  hide the game install (logic only; the screenshots are worthless then)
#   SIMLAB_SHIM=0    leave the shim out
#
# Evidence: handler-level interaction (Button:Click(), game events fired by the simulator) and in-memory state over FAKE game data.
# Not real input, not the real client, not reload persistence, not how anything looks in the game (addon fonts fall back).
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
selection=()
read -r -a selection <<< "${SIMLAB_ONLY:-}"
for pose in "${selection[@]}"; do
  case " overview craft opps shop design small smallov empty history craftlong shopmix shopcollect strategy confirm stratlong planning nodata override compact compactcraft tooltip smallstrat shopafter notice wrong " in
    *" $pose "*) ;; *) echo "simlab: unknown Workshop pose: $pose" >&2; exit 2 ;;
  esac
done
if [[ " ${SIMLAB_ONLY:-} " == *" wrong "* ]] && [[ " ${SIMLAB_ONLY:-} " != *" craft "* ]]; then
  echo 'simlab: the wrong control requires the craft pose for comparison' >&2; exit 2
fi
RUN="${SIMLAB_RUN:-$LAB/artifacts/workshop-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
WRONG_AT="Peacebloom shared by two recipes: need/in bags/still needed"

export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_EXTRA="TwichUI_Workshop"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"

fixture() {  # name params
  # TwichUI_TestLab/Reach.lua is the reachability analysis the scenario's hit test and negative control use. It is wrapped in do..end so its
  # locals stay its own, and is read from the repository (the Lab addon is never loaded into the simulator).
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua"; printf 'do\n'; cat "$REPO/TwichUI_TestLab/Reach.lua"; printf '\nend\n'
    cat "$SIMLAB_DIR/scenarios/workshop.lua"; } > "$LAB/fixtures/workshop-$1.lua"
}
fixture overview '{ view = "overview" }'
fixture craft '{ view = "craft" }'
fixture opps '{ view = "opps" }'
fixture shop '{ view = "shop" }'
fixture design '{ view = "design" }'
fixture small '{ view = "opps" }'
fixture smallov '{ view = "smallov" }'
fixture empty '{ view = "empty" }'
fixture history '{ view = "history" }'
fixture craftlong '{ view = "craftlong" }'
fixture shopmix '{ view = "shopmix" }'
fixture shopcollect '{ view = "shopcollect" }'
fixture strategy '{ view = "strategy" }'
fixture confirm '{ view = "confirm" }'
fixture stratlong '{ view = "stratlong" }'
fixture planning '{ view = "planning" }'
fixture nodata '{ view = "nodata" }'
fixture override '{ view = "override" }'
fixture compact '{ view = "compact" }'
fixture compactcraft '{ view = "compactcraft" }'
fixture tooltip '{ view = "tooltip" }'
fixture smallstrat '{ view = "smallstrat" }'
fixture shopafter '{ view = "shopafter" }'
fixture notice '{ view = "notice" }'
fixture wrong "{ view = \"craft\", wrongAt = \"$WRONG_AT\" }"

repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
launch() {  # name command...
  local name="$1"; shift
  case " ${SIMLAB_ONLY:-$name} " in *" $name "*) ;; *) return 0 ;; esac
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
launch smallov screenshot --png -o "$RUN/smallov.png" --width 1000 --height 700
launch empty screenshot --png -o "$RUN/empty.png" --width 1600 --height 1200
launch history screenshot --png -o "$RUN/history.png" --width 1600 --height 1200
launch craftlong screenshot --png -o "$RUN/craftlong.png" --width 1600 --height 1200
launch shopmix screenshot --png -o "$RUN/shopmix.png" --width 1600 --height 1200
launch shopcollect screenshot --png -o "$RUN/shopcollect.png" --width 1600 --height 1200
launch strategy screenshot --png -o "$RUN/strategy.png" --width 1600 --height 1200
launch confirm screenshot --png -o "$RUN/confirm.png" --width 1600 --height 1200
launch stratlong screenshot --png -o "$RUN/stratlong.png" --width 1600 --height 1200
launch planning screenshot --png -o "$RUN/planning.png" --width 1600 --height 1200
launch nodata screenshot --png -o "$RUN/nodata.png" --width 1600 --height 1200
launch override screenshot --png -o "$RUN/override.png" --width 1600 --height 1200
launch compact screenshot --png -o "$RUN/compact.png" --width 1600 --height 1200
launch compactcraft screenshot --png -o "$RUN/compactcraft.png" --width 1600 --height 1200
launch tooltip screenshot --png -o "$RUN/tooltip.png" --width 1600 --height 1200
launch smallstrat screenshot --png -o "$RUN/smallstrat.png" --width 1000 --height 700
launch shopafter screenshot --png -o "$RUN/shopafter.png" --width 1600 --height 1200
launch notice screenshot --png -o "$RUN/notice.png" --width 1600 --height 1200
launch wrong dump-tree --visible-only

echo "artifacts: $RUN"
repo_after="$(git -C "$REPO" status --porcelain --ignored)"
leak=0
[ "$repo_before" = "$repo_after" ] || { echo "simlab: the repository's status changed during the run" >&2; leak=1; }
find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q . && { echo "simlab: artifacts found inside the addon root" >&2; leak=1; }
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/workshop_verdict.py" "$RUN" "$WRONG_AT" "$SIMLAB_ASSETS" "${selection[@]}" || exit 1
[ "$leak" -eq 0 ] || exit 1
