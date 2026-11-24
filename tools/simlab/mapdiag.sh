#!/usr/bin/env bash
# Optional map support workflow; leaves the default full simulator catalog intact.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/mapdiag-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_EXTRA=TwichUI_Diagnostics
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-0}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
simlab_stage
cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/mapdiag.lua" > "$LAB/fixtures/mapdiag.lua"
timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/mapdiag.lua" \
    screenshot --png -o "$RUN/mapdiag.png" --width 1200 --height 900 --dump-tree TwichUI \
    > "$RUN/run.stdout" 2> "$RUN/run.stderr"
echo "artifacts: $RUN"
simlab_disclose
python3 -B - "$RUN" "$SIMLAB_DIR" <<'PY'
import re, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
import known_failures
from verdict import read_rgba
run = Path(sys.argv[1])
text = '\n'.join((run / ('run.' + ext)).read_text(errors='replace') for ext in ('stdout', 'stderr'))
checks = re.findall(r'^SIMLAB check PASS ', text, re.M)
errors = known_failures.classify(text, allow=('voice-settings-unsupplied',))
good = bool(re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false', text)
            and len(checks) >= 17 and not errors['unknown'] and not errors['unexpected'])
w, h, _ = read_rgba(run / 'mapdiag.png')
good &= (w, h) == (1200, 900)
print('MAP DIAGNOSTICS SIMULATOR', 'PASS' if good else 'FAIL', len(checks), 'handler checks')
if not good:
    print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line))
sys.exit(0 if good else 1)
PY
