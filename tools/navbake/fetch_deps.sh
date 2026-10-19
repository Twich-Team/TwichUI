#!/usr/bin/env bash
# Fetches the bake's one third-party dependency, Recast (recastnavigation, zlib licence), at a pinned version into
# tools/navbake/.deps/ (git-ignored). It is used only to build tools/navbake/build/navbuild; nothing from it is shipped.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="$here/.deps/recastnavigation"
tag="v1.6.0"
commit="6dc1667f580357e8a2154c28b7867bea7e8ad3a7"
if [ ! -d "$dest" ]; then
  git clone --quiet --depth 1 --branch "$tag" https://github.com/recastnavigation/recastnavigation "$dest"
fi
got="$(git -C "$dest" rev-parse HEAD)"
if [ "$got" != "$commit" ]; then
  echo "recastnavigation at $got, expected $commit ($tag)" >&2
  exit 1
fi
echo "recastnavigation $tag ($commit)"
