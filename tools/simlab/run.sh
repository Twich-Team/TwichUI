#!/usr/bin/env bash
# Use the installed simulator read-only; all mutable state stays in TwichUI.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install="$(realpath -e -- "${WOWSIM_INSTALL:-$(dirname "$repo")/wow-ui-sim-lab}")"
case "${1:-}" in loot|smoke|interact|diagnose|auctionproof|auctionpreview|workshop|testlab|settings|reminders|mapdiag) scenario="$1"; shift ;;
  *) echo 'usage: bash tools/simlab/run.sh loot|smoke|interact|diagnose|auctionproof|auctionpreview|workshop|testlab|settings|reminders|mapdiag [scenario arguments]' >&2; exit 2 ;;
esac
[ -x "$install/release/wow-ui-sim-v0.1.37-forever-linux-x86_64/wow-sim" ] \
  && [ -d "$install/deps/lib" ] && [ -d "$install/xdg/cache/wow-ui-sim/blizzard-ui" ] \
  || { echo 'simlab: the read-only installation is incomplete; see docs/simulator-lab.md' >&2; exit 2; }
case "${SIMLAB_WORKER:-}" in
  '') state="$repo/test-output/simlab"; lock="$repo/test-output/simlab.lock" ;;
  1|2) state="$repo/test-output/simlab-workers/worker-$SIMLAB_WORKER"; lock="$repo/test-output/simlab-workers/worker-$SIMLAB_WORKER.lock" ;;
  *) echo 'simlab: worker must be 1 or 2' >&2; exit 2 ;;
esac
# Never follow an output-directory symlink out of the repository.
[ "$(realpath -m -- "$state")" = "$state" ] \
  || { echo 'simlab: refusing a symlinked workspace path' >&2; exit 2; }
mkdir -p "$(dirname "$state")"
[ ! -L "$lock" ] || { echo 'simlab: refusing symlinked lock' >&2; exit 2; }
exec 9> "$lock"
flock -n 9 || { echo 'simlab: another repository-local scenario is running; wait for it to finish' >&2; exit 2; }
for dir in "$state" "$state/home" "$state/artifacts" "$state/fixtures" "$state/roots" "$state/wtf" "$state/xdg" \
  "$state/xdg/cache" "$state/xdg/data" "$state/xdg/config" "$state/xdg/state"; do
  [ ! -L "$dir" ] || { echo "simlab: refusing symlinked state directory $dir" >&2; exit 2; }
  mkdir -p "$dir"
done
[ ! -L "$state/.simlab-lab" ] || { echo 'simlab: refusing symlinked marker' >&2; exit 2; }
printf 'twichui-simlab-lab 1\n' > "$state/.simlab-lab"
# Seed once into a disposable cache. Every subsequent write is local. No
# symlinks to the installation's mutable cache, home, fixtures or WTF.
if [ ! -d "$state/xdg/cache/wow-ui-sim" ]; then
  seed="$(mktemp -d "$state/xdg/cache/.seed-XXXXXXXX")"
  trap 'rm -rf -- "$seed"' EXIT
  cp -a --reflink=auto "$install/xdg/cache/wow-ui-sim" "$seed/"
  mv -- "$seed/wow-ui-sim" "$state/xdg/cache/wow-ui-sim"
  rmdir -- "$seed"
  trap - EXIT
fi
export WOWSIM_LAB="$state" SIMLAB_INSTALL="$install" SIMLAB_LOCAL=1
export SIMLAB_STAGE_ONCE="${SIMLAB_STAGE_ONCE:-1}"
# Avoid second-resolution artifact collisions and reusing stale partial logs.
export SIMLAB_RUN="$(mktemp -d "$state/artifacts/$scenario-XXXXXXXX")"
exec bash "$repo/tools/simlab/$scenario.sh" "$@"
