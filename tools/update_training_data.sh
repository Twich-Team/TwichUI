#!/usr/bin/env bash
# Regenerates modules/TrainingData.lua from the newest What's Training? source.
#
#   ./tools/update_training_data.sh
#
# Fetches the head of the upstream `forever` branch (the branch that carries Classes/Camelot, the
# WoW: Forever data) into a temporary directory, pins it to the commit it resolved, runs
# tools/training_data.lua on it, validates the result with tools/validate_training_data.lua and only
# then replaces modules/TrainingData.lua. Any failure leaves the current file untouched and exits
# nonzero. Needs git and lua5.1. Run from anywhere; it works on the repository this script is in.
#
# Overrides, for testing: WT_UPSTREAM_URL, WT_UPSTREAM_BRANCH.
set -euo pipefail

UPSTREAM_URL="${WT_UPSTREAM_URL:-https://github.com/fusionpit/WhatsTraining.git}"
UPSTREAM_BRANCH="${WT_UPSTREAM_BRANCH:-forever}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$root/modules/TrainingData.lua"
notice="$root/licenses/MIT-whatstraining.txt"

fail() { echo "update_training_data: $*" >&2; exit 1; }

for tool in git lua5.1; do
    command -v "$tool" >/dev/null || fail "$tool is required"
done

work="$(mktemp -d)"
staged=""
cleanup() {
    rm -rf "$work"
    [ -z "$staged" ] || rm -f "$staged"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Resolve the branch to a commit first, then fetch exactly that commit, so the run is tied to one revision.
echo "Upstream: $UPSTREAM_URL ($UPSTREAM_BRANCH)"
ref="$(git ls-remote "$UPSTREAM_URL" "refs/heads/$UPSTREAM_BRANCH")" || fail "could not reach $UPSTREAM_URL"
sha="${ref%%[[:space:]]*}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "branch $UPSTREAM_BRANCH not found at $UPSTREAM_URL"

src="$work/source"
git init -q "$src"
git -C "$src" fetch -q --depth 1 "$UPSTREAM_URL" "$sha" || fail "could not fetch $sha"
git -C "$src" checkout -q --detach FETCH_HEAD
[ "$(git -C "$src" rev-parse HEAD)" = "$sha" ] || fail "checked out the wrong commit"
date="$(git -C "$src" show -s --format=%cs HEAD)"
label="${UPSTREAM_BRANCH} @ ${sha:0:12} (${date})"
echo "Upstream commit: $sha ($date)"

# The bundled notice reproduces upstream's MIT license; stop if upstream's license is no longer that.
[ -f "$src/LICENSE" ] || fail "upstream has no LICENSE file"
head -n 1 "$src/LICENSE" | grep -q '^MIT License' || fail "upstream license is no longer MIT; review licenses/MIT-whatstraining.txt"
copyright="$(grep -m1 '^Copyright' "$src/LICENSE" | tr -d '\r')"
grep -qxF "$copyright" "$notice" || fail "upstream copyright line changed ($copyright); review $notice"
[ -d "$src/Classes/Camelot" ] || fail "upstream has no Classes/Camelot"

generated="$work/TrainingData.lua"
WT_SOURCE_VERSION="$label" lua5.1 "$root/tools/training_data.lua" "$src" > "$generated" || fail "generation failed"

echo "Validating:"
lua5.1 "$root/tools/validate_training_data.lua" "$generated" "$output" || fail "validation failed; $output left unchanged"

if cmp -s "$generated" "$output"; then
    echo "modules/TrainingData.lua is already up to date."
else
    staged="$(mktemp "$output.XXXXXX")"
    cp "$generated" "$staged"
    mv "$staged" "$output"
    staged=""
    echo "Updated modules/TrainingData.lua"
fi
echo "Source: What's Training? $label"
echo "Output: modules/TrainingData.lua"
