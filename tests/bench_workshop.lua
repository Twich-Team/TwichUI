-- The OFFLINE Workshop benchmarks (testing roadmap M7). NOT matched by run.sh (its name does not start with test_), so it never slows the suite.
-- It runs the very workloads the in-game Test Lab runs (TwichUI_TestLab/Workloads.lua) in plain Lua 5.1, with os.clock (CPU seconds of this
-- process) as the clock. These are figures of THIS machine and THIS interpreter: they say whether a change moved the numbers here, never what
-- the game will do (the game's Lua shares the interface's memory and is a different build).
--
--   (cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' bench_workshop.lua [options])
--
--   --list               the workloads and their sizes
--   --only <text>        only workloads whose id contains <text> (repeatable)
--   --reps <n>           timed repetitions (default 5, at most 25)
--   --xl                 also the 250,000-record house (offline only)
--   --smoke              2 repetitions of the small workloads: a quick check that everything runs and verifies
--   --host <name>        a label for this machine (baselines from different hosts are incomparable)
--   --out <file>         also write the result lines to <file> (default: test-output/bench-<host>.txt when --save is given)
--   --save               write test-output/bench-<host>.txt
--   --compare <file>     compare with the result lines in <file> (a baseline from this machine, taken earlier)
--   --paired             the baseline and this run were interleaved (A B A B ...): require the same direction in every pair
dofile(TESTS .. "mi_mock.lua")

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "Prices.lua", "Opportunities.lua",
    "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"

local opt = { only = {}, reps = 5 }
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--only" then i = i + 1 opt.only[#opt.only + 1] = arg[i]
    elseif a == "--reps" then i = i + 1 opt.reps = tonumber(arg[i]) or 5
    elseif a == "--host" then i = i + 1 opt.host = arg[i]
    elseif a == "--out" then i = i + 1 opt.out = arg[i]
    elseif a == "--compare" then i = i + 1 opt.compare = arg[i]
    elseif a == "--xl" then opt.xl = true
    elseif a == "--smoke" then opt.smoke = true
    elseif a == "--save" then opt.save = true
    elseif a == "--paired" then opt.paired = true
    elseif a == "--list" then opt.list = true
    else io.stderr:write("unknown option " .. tostring(a) .. "\n") os.exit(2) end
    i = i + 1
  end
end
local host = (opt.host or os.getenv("BENCH_HOST") or "unlabeled"):gsub("[^%w%-_]", "_")

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
for _, f in ipairs({ "Fixtures.lua", "Reference.lua", "Bench.lua", "Workloads.lua" }) do
  local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
end
local TL = c.TwichUI.TestLab
local BN, WL = TL.Bench, TL.Workloads
local W = c.TwichUI.Workshop

local function Wanted(w)
  if w.offline and not opt.xl and #opt.only == 0 then return false end
  if opt.smoke and (w.size and w.size > 1000 and w.unit == "records") then return false end
  if opt.smoke and w.id:find("large") then return false end
  if #opt.only == 0 then return true end
  for _, s in ipairs(opt.only) do if w.id:find(s, 1, true) then return true end end
  return false
end

if opt.list then
  for _, w in ipairs(WL.list) do print(("%-28s size %-7s %s%s"):format(w.id, tostring(w.size), w.unit or "", w.offline and "  (offline only)" or "")) end
  return
end

local baseline
if opt.compare then
  local f = assert(io.open(opt.compare, "r"))
  local text = f:read("*a") f:close()
  local bad
  baseline, bad = BN.DecodeAll(text)
  if bad > 0 then print(("note: %d lines of %s could not be read and were skipped"):format(bad, opt.compare)) end
end

print(("offline benchmark | %s | host %s | clock os.clock (CPU seconds) | %d repetitions + a warm-up | machine-specific, not the game's figures"):format(_VERSION, host, opt.smoke and 2 or opt.reps))
local lines, failed = {}, 0
for _, w in ipairs(WL.list) do
  if Wanted(w) then
    local res = BN.Measure(w, {
      clock = os.clock, mem = function() return collectgarbage("count") end, retained = true, reps = opt.smoke and 2 or opt.reps,
      env = "lua5.1-offline", host = host, clockName = "os.clock", lua = _VERSION, ctx = { W = W },
    })
    local line = BN.Encode(res)
    lines[#lines + 1] = line
    print(("%-26s %s"):format(w.id, BN.Summary(res)))
    if res.status ~= "ok" then failed = failed + 1 end
    if baseline and baseline[w.id] then
      local cmp = BN.Compare(baseline[w.id], BN.Decode(line) or res, { paired = opt.paired })
      print(("%-26s   vs baseline: %s (%s)"):format("", cmp.verdict, cmp.reason))
    elseif baseline then
      print(("%-26s   vs baseline: none recorded for this workload"):format(""))
    end
    collectgarbage() collectgarbage()
  end
end
local out = opt.out or (opt.save and ("test-output/bench-" .. host .. ".txt"))
if out then
  if out:find("^test%-output/") then os.execute("mkdir -p test-output") end
  local f = assert(io.open(out, "w"))
  f:write("# TwichUI Workshop offline benchmark, host " .. host .. ", " .. _VERSION .. "; machine-specific, not the game's figures\n")
  for _, l in ipairs(lines) do f:write(l, "\n") end
  f:close()
  print("wrote " .. out)
end
if failed > 0 then print(failed .. " workload(s) did not finish or did not verify") os.exit(1) end
