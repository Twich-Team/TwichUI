#!/usr/bin/env bash
# The simulator smoke test (docs/simulator-lab.md): copies the addons out of the working tree into the lab, opens one
# real settings page in the sandbox, constructs every other page, and judges the result. Writes to
# $WOWSIM_LAB/artifacts/smoke-<time>/.
#
# Evidence: initialization and page construction only. No control is used, nothing is saved, nothing is looked at.
# tools/simlab/interact.sh is the one that uses controls.
#
#   SIMLAB_PAGE=qol                the settings page to open
#   SIMLAB_TITLE="Quality of life" that page's title, which must appear in the frame tree
#   SIMLAB_SHIM=0                  leave the shim out, to see what the simulator does without it
#   SIMLAB_ASSETS=0                hide the game install: the page's logic is still judged, its look is not (no
#                                  Blizzard textures, WHITE8x8 among them, and a fallback font that wraps differently)
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HERE="$SIMLAB_DIR"
PAGE="${SIMLAB_PAGE:-qol}"
TITLE="${SIMLAB_TITLE:-Quality of life}"
RUN="$LAB/artifacts/smoke-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"

simlab_stage
mkdir -p "$ROOT/!!!TwichUI/tests"
cp "$HERE/tests/settings_pages.lua" "$ROOT/!!!TwichUI/tests/"
{ printf 'SIMLAB_PAGE = "%s"\n' "$PAGE"; cat "$HERE/open_settings.lua"; } > "$LAB/fixtures/open_settings.lua"

export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1"
set +e
timeout 280 "$HERE/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/open_settings.lua" \
  screenshot --png -o "$RUN/settings.png" --width 1600 --height 1200 --dump-tree TwichUI \
  > "$RUN/run.stdout" 2> "$RUN/run.stderr"
status=$?
timeout 120 "$HERE/sim.sh" --no-saved-vars --addons-path "$ROOT" run-tests '!!!TwichUI' \
  > "$RUN/pages.stdout" 2> "$RUN/pages.stderr"
pages=$?
set -e
echo "simulator exit status: screenshot $status, run-tests $pages"
echo "artifacts: $RUN"
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
[ "$pages" -eq 0 ] || exit "$pages"
python3 -I "$HERE/verdict.py" "$RUN" "$PAGE" "$TITLE"
[ "$SIMLAB_ASSETS" = "1" ] || echo "note: no game assets, so this PASS covers logic only; the screenshot is not a visual result"
