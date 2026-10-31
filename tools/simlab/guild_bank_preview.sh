#!/usr/bin/env bash
# One launch of the Magic Inventory guild bank arrangement scenario (scenarios/guild_bank_preview.lua) from a clean synthetic
# profile, then a screenshot of where it ends. Writes to $WOWSIM_LAB/artifacts/guildbank-<time>/.
#
#   tools/simlab/guild_bank_preview.sh <name> '<lua table of parameters>' [width height]
#   tools/simlab/guild_bank_preview.sh design-default '{ view = "design", script = "assign", size = "default" }' 1000 700
#
# Evidence: the real page and planner drawing SYNTHETIC data (see the scenario's header) and a screenshot for a person to
# look at. Not the real client, not real guild-bank answers, not input, and addon fonts fall back to a game font.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <name> '<lua parameter table>' [width height]" >&2; exit 2; }
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
NAME="$1"; PARAMS="$2"; WIDTH="${3:-1600}"; HEIGHT="${4:-1200}"
RUN="${SIMLAB_RUN:-$LAB/artifacts/guildbank-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN"
simlab_stage
{ printf 'SIMLAB_PARAMS = %s\n' "$PARAMS"; cat "$SIMLAB_DIR/scenarios/lib.lua" "$SIMLAB_DIR/scenarios/guild_bank_preview.lua"; } > "$LAB/fixtures/guildbank-$NAME.lua"
export SIMLAB_ASSETS="${SIMLAB_ASSETS:-1}"
export SIMLAB_FORWARD="WOW_SIM_SOFTWARE_RENDER=1 WOW_SIM_NO_PARTY=1"
set +e
timeout 280 "$SIMLAB_DIR/sim.sh" --no-saved-vars --addons-path "$ROOT" --exec-lua "@$LAB/fixtures/guildbank-$NAME.lua" \
  screenshot --png -o "$RUN/$NAME.png" --width "$WIDTH" --height "$HEIGHT" \
  > "$RUN/$NAME.stdout" 2> "$RUN/$NAME.stderr"
code=$?
set -e
echo "simulator exit status: $code"
echo "artifacts: $RUN/$NAME.png"
grep -E 'SIMLAB|Lua error' "$RUN/$NAME.stderr" | grep -v ' tick ' | head -40 || true
echo "Lua errors: $(grep -c 'Lua error' "$RUN/$NAME.stderr" || true)"
simlab_disclose >/dev/null
