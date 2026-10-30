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

# the repository and home are the real ones for the names below only where REPO is concerned (the check reads REPO from lib.sh)
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

# unsupported shell: a runner started by zsh must stop before it creates anything
if command -v zsh >/dev/null 2>&1; then
  out=$(cd "$T" && WOWSIM_LAB="$T/zshlab" zsh "$HERE/../smoke.sh" 2>&1); st=$?
  if [ "$st" != 0 ] && [ ! -e "$T/zshlab" ] && [ ! -e "$T/artifacts" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL zsh run (status $st): $out"; fi
else echo "note: zsh not installed; the zsh check was skipped"; fi

echo "lab guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
