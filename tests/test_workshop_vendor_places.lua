-- Where Shopping's Show vendor points (TwichUI_Workshop/Vendor.lua: Sellers and Places, P2.1): a verified seller near the player beats the merchant
-- the price happened to be seen at. The reported problem: in Undercity, Show vendor chose a vendor in Orgrimmar (where the price was noted) although
-- a seller of the item was known in Undercity. Synthetic NPC collection and map geometry: this proves the ranking, not the game's map positions.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua" }

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.time = function() return 1000000 end
c.CreateFrame = function(kind) return MIFake(kind) end
c.GetRealmName = function() return "Realm" end
c.C_Timer = { After = function() end }
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local R = c.TwichUI
local V = R.Workshop.Vendor

-- the world: a map is on a continent at an offset (continent yards = offset + map coordinate * size)
local UC, TIRISFAL, ORG, TB, DUN = 1458, 1420, 1454, 1456, 1001   -- Undercity, Tirisfal Glades (both Eastern Kingdoms), Orgrimmar, Thunder Bluff (Kalimdor), an instance
local MAPS = { [UC] = { 0, 1000, 1000, 400 }, [TIRISFAL] = { 0, 600, 600, 2000 }, [ORG] = { 1, 5000, 5000, 600 }, [TB] = { 1, 2000, 7000, 600 } }
local here = { map = UC, x = 0.5, y = 0.5 }   -- where the player stands (map coordinates 0..1); cont is worked out from MAPS
local function World(m, x, y)
  local w = MAPS[m]
  if not w then return nil end
  return w[1], w[2] + x * w[4], w[3] + y * w[4]
end
R.NpcSearch = {
  Where = function()
    local spot = { map = here.map }
    if here.x then spot.cont, spot.x, spot.y = World(here.map, here.x, here.y) end
    return spot
  end,
  Distance = function(spot, m, x, y)
    if not (spot and spot.cont) then return nil end
    local cont, wx, wy = World(m, x, y)
    if cont ~= spot.cont then return nil end
    return math.sqrt((wx - spot.x) ^ 2 + (wy - spot.y) ^ 2)
  end,
}
local entries = {}
local mine = "H"
R.NpcStore = {
  COORD = 10000,
  Entries = function() return entries end,
  ValidMap = function(m) return m ~= nil and m ~= 0 end,
  MyFaction = function() return mine end,
  Usable = function(e, side) local f = e.f return f == nil or f == "N" or side == nil or f == side end,
}
R.Enabled = function() return true end

local THREAD = 2320
local function E(id, name, map, x, y, extra)
  local e = { id = id, n = name, m = map, x = x, y = y, s = { THREAD }, own = true, at = 999000 }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end
local function Names(list) local t = {} for i, e in ipairs(list) do t[i] = e.n end return table.concat(t, ",") end
local function Best(npc) return V.Places(V.Sellers({ [THREAD] = true })[THREAD], npc, 3) end

-- 1. the reported case: in Undercity, one verified seller in Undercity and the remembered one in Orgrimmar ----------------------------------------
entries = { E(3313, "Trak'gen", ORG, 5000, 5000), E(4580, "Lucille Castleton", UC, 6000, 5000) }
Same(Best(3313)[1].n, "Lucille Castleton", "in Undercity, the Undercity seller is shown, not the Orgrimmar merchant where the price was seen")
Same(Names(Best(3313)), "Lucille Castleton,Trak'gen", "the remembered merchant is still offered, after the local one")
Same(Best(nil)[1].n, "Lucille Castleton", "the same with no remembered merchant")

-- 2. no seller on this continent: the remembered merchant first (no distance is claimed for any), then by name ------------------------------------
entries = { E(9001, "Aelthalyste", TB, 5000, 5000), E(3313, "Trak'gen", ORG, 5000, 5000) }
Same(Names(Best(3313)), "Trak'gen,Aelthalyste", "nothing nearby: the merchant where the price was seen leads; nothing is called nearest")
Same(Names(Best(nil)), "Aelthalyste,Trak'gen", "without one, the order is by name, stable")

-- 3. several nearby: the nearest straight line first, wherever the price was seen -----------------------------------------------------------------
entries = { E(1, "Far", TIRISFAL, 9000, 9000), E(2, "Near", UC, 5200, 5000), E(3, "Middle", TIRISFAL, 2500, 2500) }
Same(Names(Best(1)), "Near,Middle,Far", "nearest first, even before the remembered merchant")

-- 4. no position (inside an instance or an unreadable one): a seller on the map you are on comes first; nothing gets a distance ------------------
here = { map = UC }
entries = { E(3313, "Trak'gen", ORG, 5000, 5000), E(4580, "Lucille Castleton", UC, 6000, 5000), E(7, "Tirisfal Vendor", TIRISFAL, 5000, 5000) }
Same(Best(3313)[1].n, "Lucille Castleton", "no coordinates for you, but the seller is on your map")
Same(Names(Best(3313)), "Lucille Castleton,Trak'gen,Tirisfal Vendor", "then the remembered merchant, then by name")
here = { map = DUN }
Same(Names(Best(3313)), "Trak'gen,Lucille Castleton,Tirisfal Vendor", "in an instance nothing is local: the remembered merchant, then by name")
here = { map = UC, x = 0.5, y = 0.5 }

-- 5. the other side's vendors are never offered ---------------------------------------------------------------------------------------------------
entries = { E(50, "Alliance Merchant", UC, 5000, 5000, { f = "A" }), E(51, "Neutral Goblin", ORG, 5000, 5000, { f = "N" }), E(52, "Unknown Side", ORG, 5100, 5000) }
Same(Names(Best(nil)), "Neutral Goblin,Unknown Side", "an Alliance merchant is not shown to a Horde character, however near")
mine = "A"
Same(Best(nil)[1].n, "Alliance Merchant", "and is to an Alliance one")
mine = "H"

-- 6. stale and reported observations: among equally near sellers, your own and the most recently seen first ----------------------------------------
entries = { E(60, "Old Visit", UC, 5500, 5000, { at = 100 }), E(61, "Reported Only", UC, 4500, 5000, { own = false }), E(62, "Fresh Visit", UC, 5000, 5500) }
Same(Names(Best(nil)), "Fresh Visit,Old Visit,Reported Only", "equal distances: seen by you first, then the newest; a report last")

-- 7. missing vendor evidence: a merchant whose stock wasn't seen to hold the item is not a seller ----------------------------------------------------
do
  local noStock, noCoords = E(71, "No Stock Seen", UC, 5000, 5000), E(72, "Bad Coords", UC, 5000, 5000)
  noStock.s, noCoords.x, noCoords.y = nil, nil, nil
  entries = { E(70, "Sells Other Things", UC, 5000, 5000, { s = { 159 } }), noStock, noCoords }
end
Same(V.Sellers({ [THREAD] = true })[THREAD], nil, "no seller of the item is known, so no place is made up")
Same(#V.Places(nil, nil), 0); Same(#V.Places({}, 1), 0)

-- 8. one NPC at several places: each place is its own result, the nearer first --------------------------------------------------------------------
entries = { E(80, "Wandering Vendor", TIRISFAL, 9500, 9500), E(80, "Wandering Vendor", UC, 5100, 5000) }
local two = Best(80)
Same(#two, 2); Same(two[1].m, UC, "the nearer place of the same merchant first"); Same(two[2].m, TIRISFAL)

-- 9. the reason, for the words Show vendor uses: whether the first place is known to be nearest, on your map, or neither -----------------------------
entries = { E(3313, "Trak'gen", ORG, 5000, 5000), E(4580, "Lucille Castleton", UC, 6000, 5000) }
local list, how = V.Places(V.Sellers({ [THREAD] = true })[THREAD], 3313, 3)
Same(how, "nearest", "a distance was compared"); Same(#list, 2)
here = { map = UC }
_, how = V.Places(V.Sellers({ [THREAD] = true })[THREAD], 3313, 3)
Same(how, "local", "only the map is known")
here = { map = DUN }
_, how = V.Places(V.Sellers({ [THREAD] = true })[THREAD], 3313, 3)
Same(how, "unknown", "neither: nothing is claimed")

print("PASSED test_workshop_vendor_places")
