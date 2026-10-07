#!/usr/bin/env bash
# Runs TwichUI's offline tests with plain Lua 5.1 (+ luabitop).
# These simulate the WoW API closely enough to exercise sharing, routing,
# applying, restore points and the window code paths. Not a substitute for
# testing in game: WoW's Lua differs (e.g. division by zero is an error).
set -e
cd "$(dirname "$0")"
pass=0; fail=0
for t in test_*.lua; do
  out=$(lua5.1 -e 'require("bit"); ROOT="../"; TESTS="./"' "$t" 2>&1) && ok=$? || ok=$?
  # "ERROR:" is what the harness prints for errors the addon catches and hands to the error handler.
  if [ $ok -eq 0 ] && echo "$out" | grep -q "PASSED\|OK" && ! echo "$out" | grep -q "ERROR:"; then pass=$((pass+1)); echo "ok   $t"
  else fail=$((fail+1)); echo "FAIL $t"; echo "$out" | tail -5; fi
done
# tools/sv_inspect.py (runs outside the game) has Python tests.
if command -v python3 >/dev/null; then
  if python3 -B -m unittest -q test_sv_inspect >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   test_sv_inspect.py"
  else fail=$((fail+1)); echo "FAIL test_sv_inspect.py"; python3 -B -m unittest test_sv_inspect 2>&1 | tail -5; fi
else
  echo "skip test_sv_inspect.py (no python3)"
fi
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
