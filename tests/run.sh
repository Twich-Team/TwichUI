#!/usr/bin/env bash
# Runs TwichUI's offline tests with plain Lua 5.1 (+ luabitop).
# ROOT is the core addon's folder (!!!TwichUI/, where Core.lua and the .toc are) and REPO the repository root;
# TwichUI_Settings is a sibling of the core folder, so tests reach it as ROOT .. "../TwichUI_Settings/...".
# These simulate the WoW API closely enough to exercise sharing, routing,
# applying, restore points and the window code paths. Not a substitute for
# testing in game: WoW's Lua differs (e.g. division by zero is an error).
set -e
cd "$(dirname "$0")"
pass=0; fail=0
for t in test_*.lua; do
  out=$(lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' "$t" 2>&1) && ok=$? || ok=$?
  # "ERROR:" is what the harness prints for errors the addon catches and hands to the error handler.
  if [ $ok -eq 0 ] && echo "$out" | grep -q "PASSED\|OK" && ! echo "$out" | grep -q "ERROR:"; then pass=$((pass+1)); echo "ok   $t"
  else fail=$((fail+1)); echo "FAIL $t"; echo "$out" | tail -5; fi
done
# tools/sv_inspect.py (runs outside the game) has Python tests.
if command -v python3 >/dev/null; then
  if python3 -B -m unittest -q test_sv_inspect >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_sv_inspect.py"
  else fail=$((fail+1)); echo "FAIL test_sv_inspect.py"; python3 -B -m unittest test_sv_inspect 2>&1 | tail -5; fi
  # tools/release.py (versions, release notes, package checks, publishing) needs git too.
  if python3 -B -m unittest -q test_release_tools >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_release_tools.py"
  else fail=$((fail+1)); echo "FAIL test_release_tools.py"; python3 -B -m unittest test_release_tools 2>&1 | tail -5; fi
  # the layout wizard's artwork is a reproducible build of the sources in assets/
  if python3 -B -m unittest -q test_wizard_art >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_wizard_art.py"
  else fail=$((fail+1)); echo "FAIL test_wizard_art.py"; python3 -B -m unittest test_wizard_art 2>&1 | tail -5; fi
  # the Reminders artwork library is a reproducible build of the two painted sheets in docs/reminders-revision/
  if python3 -B -m unittest -q test_reminder_gallery >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_reminder_gallery.py"
  else fail=$((fail+1)); echo "FAIL test_reminder_gallery.py"; python3 -B -m unittest test_reminder_gallery 2>&1 | tail -5; fi
  # tools/mutate.py (the Workshop mutation runner): only the runner's own harness tests run here, on a tiny fake repository (a few
  # seconds). A mutation campaign itself is run by hand (bash tools/mutate.sh --help); it is never part of this suite.
  if python3 -B -m unittest -q test_mutate >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_mutate.py"
  else fail=$((fail+1)); echo "FAIL test_mutate.py"; python3 -B -m unittest test_mutate 2>&1 | tail -5; fi
else
  echo "skip test_sv_inspect.py, test_release_tools.py, test_wizard_art.py, test_reminder_gallery.py, test_mutate.py (no python3)"
fi
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
