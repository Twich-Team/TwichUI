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
  if [ $ok -eq 0 ] && echo "$out" | grep -q "PASSED\|OK"; then pass=$((pass+1)); echo "ok   $t"
  else fail=$((fail+1)); echo "FAIL $t"; echo "$out" | tail -5; fi
done
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
