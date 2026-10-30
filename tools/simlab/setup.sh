#!/usr/bin/env bash
# Builds the simulator lab (docs/simulator-lab.md) beside the repository: about 1 GB once used, no administrator rights,
# nothing installed system-wide, and nothing in the repository or the game changes. Safe to run again.
#
#   WOWSIM_LAB          where to build it (default: wow-ui-sim-lab beside the repository)
#   SIMLAB_UI_SOURCE    a clone of Gethe/wow-ui-source (default: wow-ui-source beside the repository); only read
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB="${WOWSIM_LAB:-$(dirname "$REPO")/wow-ui-sim-lab}"
UI_SOURCE="${SIMLAB_UI_SOURCE:-$(dirname "$REPO")/wow-ui-source}"

TAG="v0.1.37"
PACKAGE="wow-ui-sim-$TAG-forever-linux-x86_64"
PACKAGE_SHA256="66e9afa95b61619fb15af335c74a8e9e2b0cc645d9bbf078dca492ec8bf8dfae"   # GitHub's recorded asset digest
# The revision v0.1.37 pins in data/blizzard-ui-builds/wowforever.json.
UI_REVISION="ca8368f2f2380cbe696854f7f2646387c278a61b"
UI_VERSION="1.60.1.70532"
# The binary needs Ubuntu 24.04's ICU 74 and ALSA. Hashes are from noble's Packages index, checked against the
# InRelease file's signature with ubuntu-archive-keyring.
UBUNTU="https://archive.ubuntu.com/ubuntu/pool/main"
DEBS=(
  "i/icu/libicu74_74.2-1ubuntu3_amd64.deb d29c97a21a3e3254731cfac186e4d4e611e5e67d2c9a0430f6acfbd9acaefa2e"
  "a/alsa-lib/libasound2t64_1.2.11-1build2_amd64.deb c2f0caa30869876791ba349bef4907d5cfec47b8cfd1ae9889a05dce0feb7c39"
)

fetch() {  # url file sha256
  [ -f "$2" ] && echo "$3  $2" | sha256sum -c --quiet 2>/dev/null && return 0
  curl -fsSL --retry 3 -o "$2" "$1"
  echo "$3  $2" | sha256sum -c --quiet
}

mkdir -p "$LAB"/{downloads,release,deps/extracted,deps/lib,home,artifacts,fixtures,roots,wtf}
mkdir -p "$LAB"/xdg/{cache,data,config,state}

echo "simulator: $PACKAGE"
archive="$LAB/downloads/$PACKAGE.tar.gz"
fetch "https://github.com/Osso/wow-ui-sim/releases/download/$TAG/$PACKAGE.tar.gz" "$archive" "$PACKAGE_SHA256"
tar -xzf "$archive" -C "$LAB/release"

echo "libraries: ICU 74, ALSA"
for entry in "${DEBS[@]}"; do
  read -r path sha <<< "$entry"
  deb="$LAB/downloads/$(basename "$path")"
  fetch "$UBUNTU/$path" "$deb" "$sha"
  dpkg-deb -x "$deb" "$LAB/deps/extracted"
done
ln -sf "$LAB"/deps/extracted/usr/lib/x86_64-linux-gnu/* "$LAB/deps/lib/"

# The Forever release ships no Blizzard UI, and its own sync refuses when the installed game has moved past the
# revision it pins. This is what upstream's Dockerfile does for its image: Gethe's tree, checked against the compiled
# manifest, with the marker the simulator looks for. git archive reads objects only; the clone's checkout is untouched.
echo "Blizzard UI: $UI_VERSION from $UI_SOURCE"
[ "$(git -C "$UI_SOURCE" show "$UI_REVISION:version.txt" | tr -d '\r\n')" = "$UI_VERSION" ]
cache="$LAB/xdg/cache/wow-ui-sim/blizzard-ui/wowforever"
staging="$(mktemp -d "$LAB/downloads/ui.XXXXXX")"
trap 'chmod -R u+w "$staging" 2>/dev/null; rm -rf -- "$staging"' EXIT
git -C "$UI_SOURCE" archive "$UI_REVISION" Interface/AddOns | tar -x -C "$staging"
curl -fsSL --retry 3 -o "$staging/manifest.txt" \
  "https://raw.githubusercontent.com/Osso/wow-ui-sim/$TAG/data/blizzard-ui-files/wowforever.txt"
LC_ALL=C sort "$staging/manifest.txt" > "$staging/expected.txt"
(cd "$staging/Interface/AddOns" && find . -type f | sed 's#^\./##' | LC_ALL=C sort) > "$staging/actual.txt"
diff -u "$staging/expected.txt" "$staging/actual.txt"
mkdir -p "$cache/AddOns"
rsync -a --delete "$staging/Interface/AddOns/" "$cache/AddOns/"
manifest_sha256="$(sha256sum "$staging/manifest.txt" | cut -d' ' -f1)"
printf 'profile=wowforever\nversion=%s\nsource=gethe-local-mirror\ngethe_revision=%s\nmanifest_sha256=%s\nfallback=none\n' \
  "$UI_VERSION" "$UI_REVISION" "$manifest_sha256" > "$cache/AddOns/.wow-ui-sim-blizzard-ui-provenance"
touch "$cache/AddOns/.wow-ui-sim-blizzard-ui-complete"

echo "ready: $LAB"
