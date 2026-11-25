#!/usr/bin/env bash
# The Loot Rolls scenarios (docs/simulator-lab.md, docs/loot-rolls-implementation.md "Simulator evidence"): the real cards, model, rules and
# settings pages over SYNTHETIC rolls (scenarios/loot.lua says exactly what is real and what is fake). Handler-level checks plus a screenshot
# per view, written to $WOWSIM_LAB/artifacts/loot-<time>/. Run with bash.
#
#   views (default: all of them)   manual stack auto resolved waiting expired unavailable   rules builder cards narrow empty (settings pages)   place (the placement sample)   preview (the sample-roll preview, from both pages)
#   bash tools/simlab/loot.sh manual stack        just those
#
# Evidence: handler-level behaviour and in-memory state over FAKE game data. Not the real client (whether it sends these events, accepts
# these calls or shows other players' rolls is in docs/loot-rolls-implementation.md), not real input, not how anything looks in the game
# (addon fonts fall back). The screenshots are for comparing layout with the approved mockups.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/loot-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
if [ "$#" -eq 0 ]; then set -- manual stack auto resolved waiting expired unavailable rules builder cards narrow empty place preview; fi
for view in "$@"; do
    { printf 'SIMLAB_PARAMS = { view = "%s" }\n' "$view"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/loot.lua"; } > "$LAB/fixtures/loot-$view.lua"
    simlab_stage
    width=1600; height=900
    case "$view" in rules|builder|cards|empty) width=1600; height=1200 ;; esac
    case "$view" in *Narrow|narrow) width=1280; height=800 ;; esac
    timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/loot-$view.lua" \
        screenshot --png -o "$RUN/$view.png" --width "$width" --height "$height" --dump-tree TwichUI \
        > "$RUN/$view.stdout" 2> "$RUN/$view.stderr" || true
done
echo "artifacts: $RUN"
simlab_disclose
python3 -B - "$RUN" "$SIMLAB_DIR" "$@" <<'PY'
import sys, re
from pathlib import Path
sys.path.insert(0, sys.argv[2])
import known_failures as kf
run = Path(sys.argv[1]); failed = False
for name in sys.argv[3:]:
    text = '\n'.join((run / (name + '.' + s)).read_text(errors='replace') for s in ('stdout', 'stderr'))
    done = re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false', text)
    errors = kf.classify(text, allow=('voice-settings-unsupplied',))
    checks = re.findall(r'^SIMLAB check PASS ', text, re.M)
    good = bool(done and len(checks) >= 3 and not errors['unknown'] and not errors['unexpected'])
    print(name, 'PASS' if good else 'FAIL', len(checks), 'handler/state checks')
    if not good:
        print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line)[:3000])
    failed |= not good
sys.exit(1 if failed else 0)
PY
