#!/usr/bin/env bash
# Settings modernization captures and handler checks. Uses the existing isolated lab, never the simulator engine.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="$LAB/artifacts/settings-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
simlab_stage
pose="${SIMLAB_SETTINGS_POSE:-wide}"
capture() {
    local key="$1" narrow=false
    [ "$pose" != narrow ] || narrow=true
    { printf 'SIMLAB_PARAMS = { page = "%s", narrow = %s, search = %s, filled = %s, task = %s, editor = %s, categories = %s }\n' "$key" "$narrow" "${SIMLAB_SETTINGS_SEARCH:-false}" "${SIMLAB_SETTINGS_FILLED:-false}" "${SIMLAB_SETTINGS_TASK:-nil}" "${SIMLAB_SETTINGS_EDITOR:-false}" "${SIMLAB_SETTINGS_CATEGORIES:-false}"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/settings.lua"; } > "$LAB/fixtures/settings.lua"
    timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/settings.lua" \
        screenshot --png -o "$RUN/$key.png" --width 1600 --height 1200 \
        > "$RUN/$key.stdout" 2> "$RUN/$key.stderr"
    python3 -B - "$RUN" "$key" "$SIMLAB_DIR" <<'PY'
import sys,re
from pathlib import Path
sys.path.insert(0,sys.argv[3])
import known_failures as kf
from verdict import read_rgba
run,key=Path(sys.argv[1]),sys.argv[2]
text='\n'.join((run/(key+'.'+s)).read_text(errors='replace') for s in ('stdout','stderr'))
errors=kf.classify(text,allow=('voice-settings-unsupplied',))
good=bool(re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false',text)) and not errors['unknown'] and not errors['unexpected']
checks=len(re.findall(r'^SIMLAB check PASS ',text,re.M))
w,h,_=read_rgba(run/(key+'.png'))
good=good and checks>=8 and (w,h)==(1600,1200)
print(key, 'PASS' if good else 'FAIL', checks, 'handler/state checks',flush=True)
if not good:
    print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line))
sys.exit(0 if good else 1)
PY
}
echo "artifacts: $RUN"
capture overview
if [ "$#" -eq 0 ]; then
    mapfile -t pages < <(sed -n 's/^SIMLAB inventory \([^ ]*\) .*/\1/p' "$RUN/overview.stderr")
else
    pages=("$@")
fi
for key in "${pages[@]}"; do [ "$key" = overview ] || capture "$key"; done
simlab_disclose
