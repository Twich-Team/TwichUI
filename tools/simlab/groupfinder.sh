#!/usr/bin/env bash
# Real Group Finder controls and event handlers, synthetic Forever result/party data.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/groupfinder-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
poses=("$@")
[ "${#poses[@]}" -gt 0 ] || poses=(groups players picker filters empty stale small)
simlab_stage
echo "artifacts: $RUN"
for pose in "${poses[@]}"; do
    case "$pose" in groups|players|picker|filters|empty|stale|small|default|before-groups|before-players) ;; *) echo "unknown Group Finder pose: $pose" >&2; exit 2 ;; esac
    { printf 'SIMLAB_PARAMS = { pose = "%s" }\n' "$pose"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/groupfinder.lua"; } > "$LAB/fixtures/groupfinder-$pose.lua"
    width=1626; height=968
    [ "$pose" != small ] || { width=1280; height=800; }
    timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/groupfinder-$pose.lua" \
        screenshot --png -o "$RUN/$pose.png" --width "$width" --height "$height" --dump-tree TwichUI \
        > "$RUN/$pose.stdout" 2> "$RUN/$pose.stderr"
    python3 -B - "$RUN" "$pose" "$SIMLAB_DIR" "$width" "$height" <<'PY'
import re,sys
from pathlib import Path
sys.path.insert(0,sys.argv[3])
import known_failures as kf
from verdict import read_rgba
run,pose=Path(sys.argv[1]),sys.argv[2]
text='\n'.join((run/(pose+'.'+ext)).read_text(errors='replace') for ext in ('stdout','stderr'))
errors=kf.classify(text,allow=('voice-settings-unsupplied',))
checks=re.findall(r'^SIMLAB check PASS ',text,re.M)
good=bool(re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false',text)) and len(checks)>=10 and not errors['unknown'] and not errors['unexpected']
w,h,_=read_rgba(run/(pose+'.png'))
good=good and (w,h)==(int(sys.argv[4]),int(sys.argv[5]))
print(pose,'PASS' if good else 'FAIL',len(checks),'synthetic handler/state checks; structural screenshot only',flush=True)
if not good: print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line))
sys.exit(0 if good else 1)
PY
done
simlab_disclose
echo 'Group Finder: result contents, query events, group roles and contact APIs are synthetic. No native search coverage, secure actions or reload persistence is claimed.'
