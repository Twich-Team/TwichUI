-- Where navigation's memory goes, on the real data, in plain Lua 5.1 (the table sizes are the game's: Lua 5.1 both).
--
--   cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' ../tools/navbake/memory_probe.lua
--
-- Kilobytes after a full collection at each step (the collection is this script's, to read steady sizes; the addon never
-- forces one). The game's C_EncodingUtil does the Base64, zlib and CBOR work natively, so only the resulting Lua tables are
-- comparable here; the transient strings are not.
dofile(TESTS .. "nav_codec.lua")
local DATA = REPO .. "TwichUI_NavData/"
local store = { graph = {}, tiles = {}, places = {} }
local env = setmetatable({}, { __index = _G })
env._G = env
env.TwichUI = { Fault = function(s, e) error(s .. tostring(e)) end, NavDataStore = store }
env.C_EncodingUtil, env.Enum = NAV_CODEC.C_EncodingUtil, NAV_CODEC.Enum
env.InCombatLockdown = function() return false end
env.debugprofilestop = function() return os.clock() * 1000 end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.UnitName = function() return "T" end
local loaded = false
env.C_AddOns = { DoesAddOnExist = function() return true end, GetAddOnEnableState = function() return 2 end,
  IsAddOnLoaded = function() return loaded end,
  LoadAddOn = function()
    for line in io.lines(DATA .. "TwichUI_NavData.toc") do
      if line:match("%.lua") then
        local c = assert(loadfile(DATA .. line:gsub("\\", "/"):gsub("%s+$", "")))
        setfenv(c, env)
        c()
      end
    end
    loaded = true
    return true
  end }
local function KB()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end
local base = KB()
local last = base
local function Step(label)
  local now = KB()
  print(("%-52s %8.1f MB   (+%.1f)"):format(label, now / 1024, (now - last) / 1024))
  last = now
end
Step("start")
for _, f in ipairs({ "nav/Data.lua", "nav/Route.lua", "nav/Journey.lua" }) do
  local chunk = assert(loadfile(ROOT .. f))
  setfenv(chunk, env)
  chunk()
end
Step("navigation's code")
local R = env.TwichUI
local ND, RT, J = R.NavData, R.NavRoute, R.NavJourney
assert(ND.Load())
Step("the data addon's files loaded (strings)")
ND.Transit()
Step("travel network decoded")
for _, m in ipairs({ 0, 1, 2991 }) do ND.Places(m) end
Step("every map's places and the walks between them")
local tr = ND.Transit()
local known = {}
for _, p in pairs(tr.place) do if p.node ~= 0 then known[p.node] = true end end
local function Plan(label, from, to)
  local j = assert(J.PlanNow({ start = from, goal = to, speed = 7, faction = 1, ships = true, flights = known }))
  Step(label)
  return j
end
-- a long trip on one continent: the planner passes through other maps' places only
Plan("a long trip on one continent planned (one crossing graph)", { cont = 0, x = -9464, y = 62 }, { cont = 0, x = -5605, y = -482 })
local j = Plan("then a trip to another continent (both crossing graphs)", { cont = 0, x = -8833, y = 629 }, { cont = 1, x = 6341, y = 557 })
for _, l in ipairs(j.legs) do
  if l.kind == "walk" then assert(RT.PlanNow(l.cont, l.fx, l.fy, l.tx, l.ty)) end
end
Step("its walks planned too")
print("tiles decoded", ND.Snapshot().decodedTiles, "graphs decoded", ND.Snapshot().graphs)
ND.Release()
Step("after Release (what the game keeps: the loaded strings)")
