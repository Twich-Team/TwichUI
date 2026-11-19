#!/usr/bin/env bash
# Rejection and acceptance paths of lib.sh's lab check (docs/simulator-lab.md "Cleanup safety"). Every folder it makes is a
# disposable one under mktemp; the protected places (/, home, the repository, the game install) are only NAMED to the check,
# which refuses before touching anything, and the stand-ins for home and the game install are temporary folders too.
set -uo pipefail
[ -n "${BASH_VERSION:-}" ] || { echo "run with bash" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf -- "$T"' EXIT
pass=0; fail=0
SIMLAB_LIB_DEFER=1
# shellcheck source=../lib.sh
. "$HERE/../lib.sh"
actual_repo="$REPO"
# The runner gives every child a private TMPDIR, which can itself be inside the
# checkout. Use a stand-in repository, just as for home and the game install,
# so marked temporary labs remain outside the repository being tested.
REPO="$T/source-repository"
mkdir -p "$REPO"

try() {  # name expect(0|2) mode lab -- the check runs in a subshell with home and the game install replaced by temp folders
  local name="$1" want="$2" mode="$3" lab="$4" got
  got=$( HOME="$T/home" SIMLAB_WOW="$T/wow" LAB="$lab"; simlab_check_lab "$mode" >/dev/null 2>&1; echo $? )
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $name: wanted $want, got $got"; fi
}
mkdir -p "$T/home/dev" "$T/wow/Data" "$T/good" "$T/foreign" "$T/legacy/roots" "$T/legacy/deps" "$T/home/lab"
printf '%s\n' "$SIMLAB_MARKER_TEXT" > "$T/good/$SIMLAB_MARKER"
touch "$T/foreign/notes.txt"
printf 'wrong\n' > "$T/foreign/$SIMLAB_MARKER"
ln -s "$T/good" "$T/linktogood"

# Protected paths are stand-ins; also check the actual checkout read-only.
REPO="$actual_repo" try "actual repository" 2 use "$actual_repo"
REPO="$actual_repo" try "actual repository child" 2 use "$actual_repo/tools"
try "empty path"            2 use   ""
try "relative path"         2 use   "lab"
try "filesystem root"       2 use   "/"
try "root via dotdot"       2 use   "$T/good/../../.."
try "home"                  2 use   "$T/home"
try "home, trailing slash"  2 use   "$T/home/"
try "parent of home"        2 use   "$T"
try "repository"            2 use   "$REPO"
try "inside repository"     2 use   "$REPO/tools"
try "parent of repository"  2 use   "$(dirname "$REPO")"
try "game install"          2 use   "$T/wow"
try "inside game install"   2 use   "$T/wow/Data"
try "no marker (use)"       2 use   "$T/foreign/../home/lab"
try "foreign marker text"   2 use   "$T/foreign"
try "missing folder (use)"  2 use   "$T/nothing"
try "marked lab"            0 use   "$T/good"
try "marked lab via link"   0 use   "$T/linktogood"
try "marked lab, odd path"  0 use   "$T/good/./../good/"
try "adopt: new folder"     0 adopt "$T/new"
try "adopt: empty folder"   0 adopt "$T/home/lab"
try "adopt: legacy layout"  0 adopt "$T/legacy"
try "adopt: foreign files"  2 adopt "$T/foreign/.."
try "adopt: home"           2 adopt "$T/home"
try "adopt: root"           2 adopt "/"
try "adopt: repository"     2 adopt "$REPO"

# the deletion in simlab_stage: nothing outside roots/twichui may go, and an unmarked lab is not touched at all
stage() {  # lab -> status; runs simlab_stage with a throwaway working tree standing in for nothing: it must stop before copying
  ( HOME="$T/home" SIMLAB_WOW="$T/wow" LAB="$1" ROOT="$1/roots/twichui"; simlab_stage >/dev/null 2>&1; echo $? )
}
mkdir -p "$T/unmarked/roots/twichui" && touch "$T/unmarked/roots/twichui/keep"
[ "$(stage "$T/unmarked")" = 2 ] && [ -e "$T/unmarked/roots/twichui/keep" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL unmarked lab was touched"; }
mkdir -p "$T/good/roots" "$T/elsewhere" && touch "$T/elsewhere/keep"
ln -s "$T/elsewhere" "$T/good/roots/twichui"
[ "$(stage "$T/good")" = 2 ] && [ -e "$T/elsewhere/keep" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL symlinked root was followed"; }
rm -f "$T/good/roots/twichui"

# The local launcher has one narrow exception: use an already-marked ignored
# workspace, never adopt the repository or allow arbitrary children/siblings.
original_repo="$REPO"
REPO="$T/checkout"
mkdir -p "$REPO/test-output/simlab" "$REPO/test-output/other"
printf '%s\n' "$SIMLAB_MARKER_TEXT" > "$REPO/test-output/simlab/$SIMLAB_MARKER"
SIMLAB_LOCAL=1 try 'local workspace: marked use' 0 use "$REPO/test-output/simlab"
SIMLAB_LOCAL=0 try 'local workspace: requires opt-in' 2 use "$REPO/test-output/simlab"
SIMLAB_LOCAL=1 try 'local workspace: never adopt' 2 adopt "$REPO/test-output/simlab"
SIMLAB_LOCAL=1 try 'local workspace: sibling refused' 2 use "$REPO/test-output/other"
SIMLAB_LOCAL=1 try 'local workspace: child refused' 2 use "$REPO/test-output/simlab/child"
REPO="$original_repo"

# Reuse only this invocation's immutable snapshot, not a previous invocation's
# stale root, a changed addon selection, or nonempty saved-variable storage.
(
  REPO="$T/stage-source" LAB="$T/good" ROOT="$T/good/roots/twichui"
  HOME="$T/home" SIMLAB_WOW="$T/wow" SIMLAB_STAGE_ONCE=1 SIMLAB_SHIM=0
  unset _SIMLAB_STAGED_KEY
  mkdir -p "$REPO/!!!TwichUI" "$REPO/TwichUI_Settings" "$REPO/TwichUI_Extra"
  printf 'first\n' > "$REPO/!!!TwichUI/snapshot.txt"
  simlab_stage || exit 1
  touch "$ROOT/old-extra"
  printf 'second\n' > "$REPO/!!!TwichUI/snapshot.txt"
  simlab_stage || exit 1
  [ "$(cat "$ROOT/!!!TwichUI/snapshot.txt")" = first ] || exit 1
  # A new script has no cache key and must replace all previous staged files.
  unset _SIMLAB_STAGED_KEY
  simlab_stage || exit 1
  [ "$(cat "$ROOT/!!!TwichUI/snapshot.txt")" = second ] && [ ! -e "$ROOT/old-extra" ] || exit 1
  SIMLAB_EXTRA=TwichUI_Extra
  simlab_stage || exit 1
  [ -d "$ROOT/TwichUI_Extra" ] || exit 1
  SIMLAB_SHIM=1
  simlab_stage || exit 1
  [ -d "$ROOT/!!!!SimLabShims" ] || exit 1
  touch "$LAB/wtf/unsafe"
  simlab_stage >/dev/null 2>&1 && exit 1
  rm "$LAB/wtf/unsafe"
) && pass=$((pass+1)) || { fail=$((fail+1)); echo 'FAIL stage snapshot isolation'; }

# unsupported shell: a runner started by zsh must stop before it creates anything
if command -v zsh >/dev/null 2>&1; then
  out=$(cd "$T" && WOWSIM_LAB="$T/zshlab" zsh "$HERE/../smoke.sh" 2>&1); st=$?
  if [ "$st" != 0 ] && [ ! -e "$T/zshlab" ] && [ ! -e "$T/artifacts" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL zsh run (status $st): $out"; fi
else echo "note: zsh not installed; the zsh check was skipped"; fi

echo "lab guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
