#!/usr/bin/env bash
# Bakes TwichUI_NavData from a local World of Warcraft: Forever installation. See README.md.
#
#   tools/navbake/bake.sh "/path/to/World of Warcraft" [maps...]      (default maps: 0 1)
#
# Steps per map: extract.py (client files -> per-tile collision, in the cache), navbuild (Recast -> per-tile polygons),
# pack.py (-> TwichUI_NavData/Data/Map<m>*.lua). Then the addon's .toc is written with every data file in it.
# The cache (NAVBAKE_CACHE, default ~/.cache/twichui-navbake) is outside the repository and can be deleted any time.
# Nothing is written into the game's folder.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
wow="${1:?usage: bake.sh <World of Warcraft folder> [maps...]}"
shift
maps=("$@")
[ ${#maps[@]} -gt 0 ] || maps=(0 1)
cache="${NAVBAKE_CACHE:-$HOME/.cache/twichui-navbake}"
out="$repo/TwichUI_NavData"
jobs="${NAVBAKE_JOBS:-$(nproc 2>/dev/null || echo 4)}"

[ -x "$here/.deps/recastnavigation/Recast/Include/Recast.h" ] || [ -f "$here/.deps/recastnavigation/Recast/Include/Recast.h" ] \
  || "$here/fetch_deps.sh"
make -C "$here" -s build/navbuild

client="$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import casc; print(casc.Storage(sys.argv[2]).version)" "$here" "$wow")"
echo "client $client"

for m in "${maps[@]}"; do
  echo "== map $m"
  python3 -I -u "$here/extract.py" --wow "$wow" --map "$m" --out "$cache"
  mkdir -p "$cache/${m}nm"
  find "$cache/$m" -name '*.tin' -printf '%f\n' | sed 's/\.tin$//' | sort \
    | xargs -P "$jobs" -n 12 "$here/build/navbuild" "$cache/$m" "$cache/${m}nm" > "$cache/build$m.log"
  python3 -I "$here/pack.py" --tnm "$cache/${m}nm" --map "$m" --out "$out" --client "$client"
done

python3 -I "$here/pack.py" --toc --out "$out" --client "$client"
echo "done: $out"
