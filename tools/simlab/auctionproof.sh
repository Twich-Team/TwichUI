#!/usr/bin/env bash
# AH-1a: real Host and simulator frames over synthetic auctioneer boundaries.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/auctionproof-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_EXTRA="TwichUI_Workshop"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
fixture() {
  { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/auctionproof.lua"; } > "$LAB/fixtures/auctionproof-$1.lua"
}
fixture unloaded '{}'
fixture replay '{}'
fixture loaded '{ loaded = true }'
fixture wrong '{ wrongAt = "explicit activation parks" }'
repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
for name in unloaded replay loaded wrong; do
  simlab_stage
  set +e
  timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/auctionproof-$name.lua" dump-tree \
    > "$RUN/$name.stdout" 2> "$RUN/$name.stderr"
  code=$?
  set -e
  echo "simulator exit status: $name $code"
  [ "$code" -eq 0 ] || status="$code"
done
echo "artifacts: $RUN"
leak=0
[ "$repo_before" = "$(git -C "$REPO" status --porcelain --ignored)" ] || { echo 'simlab: repository status changed during run' >&2; leak=1; }
if find "$ROOT" -name '*.png' -o -name '*.stderr' -o -name '*.stdout' | grep -q .; then
  echo 'simlab: artifacts inside addon root' >&2; leak=1
fi
simlab_disclose
[ "$status" -eq 0 ] || exit "$status"
python3 -I "$SIMLAB_DIR/auctionproof_verdict.py" "$RUN"
[ "$leak" -eq 0 ]
