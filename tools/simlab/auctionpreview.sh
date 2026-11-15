#!/usr/bin/env bash
# Standalone AH preview, real addon UI, synthetic data, read-only installation.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RUN="${SIMLAB_RUN:-$LAB/artifacts/auctionpreview-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}" SIMLAB_EXTRA="TwichUI_Workshop"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
fixture() { { printf 'SIMLAB_PARAMS = %s\n' "$2"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/auctionpreview.lua"; } > "$LAB/fixtures/auctionpreview-$1.lua"; }
fixture shell '{}'
fixture replay '{}'
fixture empty '{ empty = true }'
fixture filtered '{ filtered = true }'
fixture shopping '{ shopping = true }'
fixture shoppingsmall '{ shopping = true }'
fixture shoppingpurpose '{ shopping = true, purpose = true }'
fixture small '{}'
fixture scaled '{ scaled = true }'
fixture wrong '{ wrongAt = "Browse default" }'
repo_before="$(git -C "$REPO" status --porcelain --ignored)"
status=0
for name in shell replay small scaled empty filtered shopping shoppingsmall shoppingpurpose wrong; do
  simlab_stage
  width=1600; height=1200
  if [[ "$name" = small || "$name" = shoppingsmall ]]; then width=1000; height=700; fi
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
python3 -I "$SIMLAB_DIR/auctionpreview_verdict.py" "$RUN"
