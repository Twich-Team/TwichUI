#!/usr/bin/env bash
# Runs the wow-ui-sim Forever build inside a sandbox (docs/simulator-lab.md). Everything after the script name goes to
# wow-sim, for example: tools/simlab/sim.sh --no-addons --no-saved-vars lua-errors
#
# What the sandbox guarantees, whatever the simulator tries to do:
#   - the whole filesystem is read-only; only the lab's home, cache, data and artifacts folders can be written
#   - the real home folder (the repository and this machine's own settings) is not visible
#   - C: is not visible, unless SIMLAB_ASSETS=1, when only the game install appears, read-only
#   - there is no network
#
#   WOWSIM_LAB        the lab folder (default: wow-ui-sim-lab beside the repository)
#   SIMLAB_ASSETS=1   let the simulator read Blizzard's textures and fonts from the game install, read-only
#   SIMLAB_WOW        the game install SIMLAB_ASSETS shows
#   SIMLAB_FORWARD    extra NAME=VALUE pairs for the simulator, separated by spaces
#   SIMLAB_BIN        run this inside the sandbox instead of the simulator (to check what the sandbox allows)
[ -n "${BASH_VERSION:-}" ] || { echo "simlab: run this with bash" >&2; exit 2; }
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"   # sets REPO and LAB, and refuses a folder that is not a lab
RELEASE="wow-ui-sim-v0.1.37-forever-linux-x86_64"
BIN="${SIMLAB_BIN:-$LAB/release/$RELEASE/wow-sim}"
WOW="${SIMLAB_WOW:-/mnt/c/Program Files (x86)/World of Warcraft}"

[ -x "$BIN" ] || { echo "simlab: no simulator at $BIN (see docs/simulator-lab.md)" >&2; exit 2; }

args=(
  --ro-bind / /
  --dev /dev
  --proc /proc
  --tmpfs /tmp
  --tmpfs "$HOME"
  --tmpfs /mnt/c
  --ro-bind "$LAB/release" "$LAB/release"
  --ro-bind "$LAB/deps" "$LAB/deps"
  --bind "$LAB/home" "$LAB/home"
  --bind "$LAB/xdg" "$LAB/xdg"
  --bind "$LAB/artifacts" "$LAB/artifacts"
  --unshare-all
  --die-with-parent
  --new-session
  --clearenv
  --setenv PATH /usr/bin:/bin
  --setenv HOME "$LAB/home"
  --setenv LD_LIBRARY_PATH "$LAB/deps/lib"
  --setenv XDG_CACHE_HOME "$LAB/xdg/cache"
  --setenv XDG_DATA_HOME "$LAB/xdg/data"
  --setenv XDG_CONFIG_HOME "$LAB/xdg/config"
  --setenv XDG_STATE_HOME "$LAB/xdg/state"
  --setenv WOW_SIM_NO_SOUND 1
  --setenv WOW_SIM_WTF_PATH "$LAB/wtf"
)
[ -d "$LAB/roots" ] && args+=(--ro-bind "$LAB/roots" "$LAB/roots")
[ -d "$LAB/wtf" ] && args+=(--bind "$LAB/wtf" "$LAB/wtf")
[ -d "$LAB/fixtures" ] && args+=(--ro-bind "$LAB/fixtures" "$LAB/fixtures")

if [ "${SIMLAB_ASSETS:-0}" = "1" ]; then
  [ -d "$WOW" ] || { echo "simlab: no game install at $WOW (set SIMLAB_WOW)" >&2; exit 2; }
  args+=(--ro-bind "$WOW" "$WOW" --setenv WOW_INSTALL_PATH "$WOW")
else
  args+=(--setenv WOW_SIM_CASC 0)
fi

for pair in ${SIMLAB_FORWARD:-}; do
  args+=(--setenv "${pair%%=*}" "${pair#*=}")
done

exec bwrap "${args[@]}" -- "$BIN" "$@"
