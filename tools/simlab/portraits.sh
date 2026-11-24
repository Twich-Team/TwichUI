#!/usr/bin/env bash
# Structural captures: synthetic verified-shape portrait frames, actual addon renderers/art.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/portraits-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-0}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
simlab_stage
echo "artifacts: $RUN"
poses=("$@")
[ "${#poses[@]}" -gt 0 ] || poses=(boss elite rare compact tall legacy modern-settings legacy-settings player)
for pose in "${poses[@]}"; do
    case "$pose" in boss|elite|rare|compact|tall|legacy|modern-settings|legacy-settings|player) ;; *) echo "unknown pose: $pose" >&2; exit 2 ;; esac
    { printf 'SIMLAB_PARAMS = { pose = "%s" }\n' "$pose"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/portraits.lua"; } > "$LAB/fixtures/portrait-$pose.lua"
    timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/portrait-$pose.lua" \
        screenshot --png -o "$RUN/$pose.png" --width 1600 --height 1200 > "$RUN/$pose.stdout" 2> "$RUN/$pose.stderr"
    python3 -B - "$RUN" "$pose" "$SIMLAB_DIR" <<'PY'
import sys,re
from pathlib import Path
sys.path.insert(0,sys.argv[3])
import known_failures as kf
from verdict import read_rgba
run,pose=Path(sys.argv[1]),sys.argv[2]
text='\n'.join((run/(pose+'.'+s)).read_text(errors='replace') for s in ('stdout','stderr'))
errors=kf.classify(text,allow=('voice-settings-unsupplied',))
good=bool(re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false',text)) and not errors['unknown'] and not errors['unexpected']
w,h,_=read_rgba(run/(pose+'.png'))
good=good and (w,h)==(1600,1200)
print(pose, 'PASS' if good else 'FAIL', 'synthetic controller/construction checks; screenshot review still required',flush=True)
if not good: print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line))
sys.exit(0 if good else 1)
PY
done
simlab_disclose
echo 'Portraits are colored square stand-ins, not native models. Captures require inspection; no native EllesmereUI visual acceptance is claimed.'
