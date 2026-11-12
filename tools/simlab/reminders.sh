#!/usr/bin/env bash
# Narrow Reminders scenario: handler interaction + screenshots, using the existing isolated lab.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="$LAB/artifacts/reminders-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
if [ "$#" -eq 0 ]; then set -- editor editorTall catalog when nested drag dirty error narrow empty hover palette situation details actions menu scale wellfed conditions conditionsEditor conditionsPalette conditionsNarrow conditionsDrop conditionsDropHint appearance appearanceImage appearanceText appearanceLegacy picker pickerSearch pickerGame pickerGameApply pickerNarrow pickerEquipment pickerCharacter pickerRender; fi
for view in "$@"; do
    { printf 'SIMLAB_PARAMS = { view = "%s" }\n' "$view"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/reminders.lua"; } > "$LAB/fixtures/reminders-$view.lua"
    simlab_stage
    width=1600; height=1200
    if [ "$view" = narrow ] || [ "$view" = conditionsNarrow ] || [ "$view" = pickerNarrow ]; then width=1280; height=800; fi
    if [ "$view" = conditionAudit ]; then width=1600; height=1200; fi
    timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/reminders-$view.lua" \
        screenshot --png -o "$RUN/$view.png" --width "$width" --height "$height" --dump-tree TwichUI \
        > "$RUN/$view.stdout" 2> "$RUN/$view.stderr"
done
echo "artifacts: $RUN"
simlab_disclose
python3 -B - "$RUN" "$SIMLAB_DIR" "$@" <<'PY'
import sys,re
from pathlib import Path
sys.path.insert(0,sys.argv[2])
import known_failures as kf
from verdict import read_rgba
run=Path(sys.argv[1]); failed=False
for name in sys.argv[3:]:
    text='\n'.join((run/(name+'.'+s)).read_text(errors='replace') for s in ('stdout','stderr'))
    done=re.search(r'SIMLAB done .*failed=0 aborted=false stopped=false',text)
    errors=kf.classify(text,allow=('voice-settings-unsupplied',))
    checks=re.findall(r'^SIMLAB check PASS ',text,re.M)
    good=bool(done and len(checks)>=15 and not errors['unknown'] and not errors['unexpected'])
    print(name, 'PASS' if good else 'FAIL', len(checks), 'handler/state checks')
    if not good:
        print('\n'.join(line for line in text.splitlines() if 'FAIL' in line or 'Lua error:' in line))
    failed |= not good
    w,h,_=read_rgba(run/(name+'.png'))
    expected=(1280,800) if name in ('narrow','conditionsNarrow','pickerNarrow') else (1600,1200)
    if (w,h)!=expected: failed=True
sys.exit(1 if failed else 0)
PY
