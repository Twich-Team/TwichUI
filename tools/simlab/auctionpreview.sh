#!/usr/bin/env bash
# Standalone AH preview, real addon UI, synthetic data, read-only installation.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/auctionpreview-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}" SIMLAB_EXTRA="TwichUI_Workshop"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
fixture() { { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua"; printf 'do\n'; cat "$REPO/TwichUI_TestLab/Reach.lua"; printf '\nend\n'; cat "$SIMLAB_DIR/scenarios/auctionpreview.lua"; } > "$LAB/fixtures/auctionpreview-$1.lua"; }
fixture shell '{}'
fixture replay '{}'
fixture empty '{ empty = true }'
fixture filtered '{ filtered = true }'
fixture resized '{ resized = true }'
fixture shopping '{ shopping = true }'
fixture shoppingsmall '{ shopping = true }'
fixture shoppingpurpose '{ shopping = true, purpose = true }'
fixture small '{}'
fixture scaled '{ scaled = true }'
fixture categories '{ categories = true }'
fixture sell '{ sell = true }'
fixture sellobserved '{ sell = true, savedCompetition = true }'
fixture loading '{ loading = true }'
fixture liveprepare '{ categories = true, livePrepare = true }'
fixture sellsmall '{ sell = true }'
fixture sellscaled '{ sell = true, scaled = true }'
fixture sellempty '{ sell = true, bagEmpty = true }'
fixture owned '{ owned = true }'
fixture ownedsmall '{ owned = true }'
fixture ownedempty '{ owned = true, ownedEmpty = true }'
fixture market '{ market = true }'
fixture marketsmall '{ market = true }'
fixture marketscaled '{ market = true, scaled = true }'
fixture marketsparse '{ market = true, marketSparse = true }'
fixture marketempty '{ market = true, marketEmpty = true }'
fixture marketrecent '{ market = true, marketRecent = true }'
fixture marketlong '{ market = true, marketLong = true }'
fixture markettracked '{ market = true, marketTracked = true }'
fixture marketlarge '{ market = true, marketLarge = true }'
fixture marketmetadata '{ market = true, marketMetadata = true }'
fixture marketstale '{ market = true, marketStale = true }'
fixture marketerror '{ market = true, marketError = true }'
# A data-only transport built from pinned, explicitly synthetic fixture bytes.
python3 - "$REPO/tests/fixtures/market_bridge_v1/source-canonical-generation.json" "$LAB/fixtures/bridge-payload.lua" <<'PYBRIDGE'
import json,sys
from pathlib import Path
g=json.loads(Path(sys.argv[1]).read_text());records=g.pop('records')
def raw(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=True)
def q(s):return '"'+''.join('\\%03d'%b for b in s.encode())+'"'
receipt=dict(schema_version=1,generation_id=g['generation_id'],desktop_build='synthetic-simulator',completed_at='2026-11-15T13:00:00Z')
Path(sys.argv[2]).write_text('SIMLAB_BRIDGE = {transport_version=1,manifest='+q(raw(g))+',records={'+','.join(q(raw(r)) for r in records)+'},receipt='+q(raw(receipt))+'}\n')
PYBRIDGE
fixture marketbridge '{ bridge = true }'
cat "$LAB/fixtures/bridge-payload.lua" "$LAB/fixtures/auctionpreview-marketbridge.lua" > "$LAB/fixtures/bridge-combined.lua"
mv "$LAB/fixtures/bridge-combined.lua" "$LAB/fixtures/auctionpreview-marketbridge.lua"
# Scoped fixtures use the unchanged authoritative mirror; no network or executable payload.
python3 - "$REPO/tests/fixtures/market_bridge_scoped_l1/fixtures" "$LAB/fixtures" <<'PYSCOPED'
import json,sys
from pathlib import Path
source,out=map(Path,sys.argv[1:])
for pose in ('priced','outside','absent','unknown','corrupt','future'):
    g=json.loads((source/('unknown-scoped.json' if pose=='unknown' else 'scoped.json')).read_text())
    if pose=='future': g['schema_version']=999
    records=g.pop('records')
    def raw(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=True)
    def q(s):return '"'+''.join('\\%03d'%b for b in s.encode())+'"'
    chunks=[raw(r) for r in records]
    if pose=='corrupt':chunks[0]+=' '
    receipt=dict(schema_version=1,generation_id=g['generation_id'],desktop_build='synthetic-simulator',completed_at='2026-11-16T23:59:59Z')
    (out/('bridge-'+pose+'.lua')).write_text('SIMLAB_BRIDGE = {transport_version=1,manifest='+q(raw(g))+',records={'+','.join(q(r) for r in chunks)+'},receipt='+q(raw(receipt))+'}\n')
PYSCOPED
for pose in priced outside absent unknown corrupt future; do
  fixture "scoped$pose" "{ bridge = true, scopedState = \"$pose\" }"
  cat "$LAB/fixtures/bridge-$pose.lua" "$LAB/fixtures/auctionpreview-scoped$pose.lua" > "$LAB/fixtures/bridge-combined.lua"
  mv "$LAB/fixtures/bridge-combined.lua" "$LAB/fixtures/auctionpreview-scoped$pose.lua"
done
fixture wrong '{ wrongAt = "Browse default" }'
repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
selection=()
read -r -a selection <<< "${SIMLAB_ONLY:-}"
# Validate before native launches; the verdict uses exactly this same catalog.
poses="$(python3 -B - "$SIMLAB_DIR" "${selection[@]}" <<'PYSELECT'
import sys
sys.path.insert(0, sys.argv[1])
from auctionpreview_verdict import select
print(' '.join(select(sys.argv[2:])))
PYSELECT
)"
for name in $poses; do
  simlab_stage
  width=1600; height=1200
  if [[ "$name" = small || "$name" = shoppingsmall || "$name" = sellsmall || "$name" = ownedsmall || "$name" = marketsmall ]]; then width=1000; height=700; fi
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/auctionpreview-$name.lua" screenshot --png -o "$RUN/$name.png" --width "$width" --height "$height" > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
done
echo "artifacts: $RUN"
[ "$repo_before" = "$(git -C "$REPO" status --porcelain --ignored)" ] || { echo 'simlab: repository status changed during run' >&2; exit 1; }
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -B -I "$SIMLAB_DIR/auctionpreview_verdict.py" "$RUN" "${selection[@]}"
