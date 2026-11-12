#!/usr/bin/env bash
# The Test Lab window scenario (docs/testlab.md "The window", docs/simulator-lab.md): loads TwichUI_TestLab the way the game does and hands the
# window SYNTHETIC recorded results (scenarios/testlab.lua says exactly what is real and what is fake), one launch per state, each ending in
# a screenshot. Writes to $WOWSIM_LAB/artifacts/testlab-<time>/.
#
#   idle        nothing has run: dashes on the cards, the empty table, the placeholder report
#   running     part way through a run (the scenario makes the runner read as active; no case runs)
#   allpass     a finished run in which everything passed
#   mixed       a finished run with one failure: the failure chosen, its details, the report
#   failfilter  the same with the Failed filter on
#   problems    a failure, a skipped case, an error and a timeout, each with its chip
#   long        300 recorded cases: pooled rows, scrolled
#   guided      a guided request: the window has stepped aside and only the prompt shows
#   small       the mixed state on a 1000x700 screen
#
#   SIMLAB_ONLY="mixed idle"  run only the named launches (a quick look while working; the full run is the evidence)
#   SIMLAB_ASSETS=0  hide the game install (logic only; the screenshots are worthless then)
#
# Evidence: handler-level state read from the drawn frames, the emulated hit test (Reach.lua) and screenshots. Not real input, not the real
# client, not how anything looks in the game (addon fonts are drawn in Friz Quadrata here).
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/testlab-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"

export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_EXTRA="TwichUI_TestLab"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"

fixture() {  # name params
  # The Lab addon is loaded by the scenario with LoadAddOn; that also makes R.TestLab.Reach, the emulated hit test the scenario uses.
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua"; cat "$SIMLAB_DIR/scenarios/testlab.lua"; } > "$LAB/fixtures/testlab-$1.lua"
}
for v in idle running allpass mixed failfilter problems long guided small; do
  case "$v" in small) view=mixed ;; *) view="$v" ;; esac
  fixture "$v" "{ view = \"$view\" }"
done

repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
launch() {  # name command...
  local name="$1"; shift
  case " ${SIMLAB_ONLY:-$name} " in *" $name "*) ;; *) return 0 ;; esac
  simlab_stage
  [ -d "$ROOT/TwichUI_TestLab" ] || { echo "simlab: TwichUI_TestLab is not in the root" >&2; exit 2; }
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/testlab-$name.lua" "$@" \
    > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  local code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
}

launch idle screenshot --png -o "$RUN/idle.png" --width 1600 --height 1200
launch running screenshot --png -o "$RUN/running.png" --width 1600 --height 1200
launch allpass screenshot --png -o "$RUN/allpass.png" --width 1600 --height 1200
launch mixed screenshot --png -o "$RUN/mixed.png" --width 1600 --height 1200
launch failfilter screenshot --png -o "$RUN/failfilter.png" --width 1600 --height 1200
launch problems screenshot --png -o "$RUN/problems.png" --width 1600 --height 1200
launch long screenshot --png -o "$RUN/long.png" --width 1600 --height 1200
launch guided screenshot --png -o "$RUN/guided.png" --width 1600 --height 1200
launch small screenshot --png -o "$RUN/small.png" --width 1000 --height 700

echo "artifacts: $RUN"
repo_after="$(git -C "$REPO" status --porcelain --ignored)"
leak=0
[ "$repo_before" = "$repo_after" ] || { echo "simlab: the repository's status changed during the run" >&2; leak=1; }
find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q . && { echo "simlab: artifacts found inside the addon root" >&2; leak=1; }
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/testlab_verdict.py" "$RUN" "$SIMLAB_ASSETS" || exit 1
[ "$leak" -eq 0 ] || exit 1
