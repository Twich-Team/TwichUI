-- Workshop remembered recipes (TwichUI_Workshop/Known.lua, Watch.lua, Session.lua): the player's own professions are remembered per
-- character and profession, restored in a fresh session without opening anything, merged (never erased by filtered, empty or foreign
-- views), and read while the addon is loaded even with the window hidden. A fake game stands in for C_TradeSkillUI; a seeded save and a
-- new client are NOT a real /reload (listed in docs/workshop.md).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Session.lua", "Watch.lua", "Bank.lua" }
local function Load(c, file)
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. file))
  setfenv(chunk, c)
  chunk("TwichUI_Workshop", {})
end

local function FakeGame(c, opts)
  opts = opts or {}
  local g = { calls = {}, opened = {}, bags = {}, names = {}, combat = false }
  g.prof = { professionID = 171, professionName = "Alchemy" }
  g.own = true
  g.recipes = {}   -- [id] = { name, learned, icon, diff, flags }
  g.schem = {}     -- [id] = schematic
  g.all, g.filtered = nil, nil
  local T = setmetatable({}, { __index = function(_, k)
    if tostring(k):match("^Set") or tostring(k):match("^Clear") or tostring(k):match("^Close") then
      error("the Workshop must not change the profession window: C_TradeSkillUI." .. tostring(k))
    end
  end })
  T.GetBaseProfessionInfo = function() g.calls.base = (g.calls.base or 0) + 1; return g.prof end
  T.IsDataSourceChanging = function() return g.changing == true end
  T.IsNPCCrafting = function() return g.npc == true end
  T.IsTradeSkillGuild = function() return g.guild == true end
  T.IsTradeSkillLinked = function() return g.linked == true, g.linked and "Someone" or nil end
  T.GetFilteredRecipeIDs = function() return g.filtered end
  T.GetRecipeInfo = function(id)
    local r = g.recipes[id]
    if not r then return nil end
    return { recipeID = id, name = r.name, learned = r.learned ~= false, icon = r.icon or 1000 + id, relativeDifficulty = r.diff,
      isRecraft = r.recraft, isDummyRecipe = r.dummy, isGatheringRecipe = r.gather }
  end
  T.GetRecipeSchematic = function(id)
    g.calls.schematic = (g.calls.schematic or 0) + 1
    return g.schem[id]
  end
  T.OpenRecipe = function(id) g.opened[#g.opened + 1] = id; if g.openFails then error("no") end end
  c.C_TradeSkillUI = T
  c.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } }
  g.hasAll = function() T.GetAllRecipeIDs = function() return g.all end end
  c.C_Item = {
    GetItemCount = function(id) return g.bags[id] end,
    GetItemInfoInstant = function(id) return id, "Trade Goods", "Herb", "", 5000 + id end,
    GetItemInfo = function(id) return g.names[id] end,
    RequestLoadItemDataByID = function(id) g.calls.requested = (g.calls.requested or 0) + 1 end,
  }
  c.InCombatLockdown = function() return g.combat end
  return g
end


local function Schematic(lo, hi, slots, outItem) return { quantityMin = lo, quantityMax = hi, outputItemID = outItem, reagentSlotSchematics = slots } end
local function Basic(item, qty) return { reagentType = 1, reagents = { { itemID = item } }, quantityRequired = qty, required = true } end

-- A new game session (client) on the saved data `db`: the addon files are loaded, then the profession interface says what is open.
local function Session(name, db, open)
  local c = MIClient(name or "Rich", { db = { modules = {} } })
  c.TwichUIDB = db or c.TwichUIDB or {}
  local timers, frames = {}, {}
  c.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  c.CreateFrame = function(kind) local fr = MIFake(kind); frames[#frames + 1] = fr; return fr end
  local g = FakeGame(c)
  c.GetRealmName = function() return "Realm" end
  g.prof = open and open.prof or nil
  g.recipes, g.schem = open and open.recipes or {}, open and open.schem or {}
  for _, f in ipairs(FILES) do Load(c, f) end
  local W = c.TwichUI.Workshop
  local s = { c = c, g = g, W = W, frame = frames[1] }
  function s.Flush() local n = 0 while #timers > 0 and n < 200 do local t = table.remove(timers, 1); t(); n = n + 1 end end
  function s.Fire(e) s.frame.scripts.OnEvent(s.frame, e) end
  function s.Saved(prof)
    local slot = c.TwichUIDB.workshop and c.TwichUIDB.workshop.chars and c.TwichUIDB.workshop.chars[W.Queue.CharKey()]
    return slot and slot.known and slot.known[prof]
  end
  return s
end

local function Recipes()
  local rec = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 }, [3] = { name = "Rage Potion" },
    [20] = { name = "Copper Bar" }, [21] = { name = "Bronze Bar" } }
  local sch = {
    [1] = Schematic(1, 1, { Basic(10, 2), Basic(11, 1) }, 501), [2] = Schematic(1, 2, { Basic(10, 3) }, 502), [3] = Schematic(1, 1, { Basic(12, 1) }, 503),
    [20] = Schematic(1, 1, { Basic(30, 1) }, 520), [21] = Schematic(1, 1, { Basic(30, 1), Basic(31, 1) }, 521),
  }
  return rec, sch
end
local ALCH, SMITH = { professionID = 171, professionName = "Alchemy" }, { professionID = 164, professionName = "Blacksmithing" }

-- Session 1: two professions are opened one after the other while the Workshop window is NOT shown; a queue and prices already exist
local rec, sch = Recipes()
local db = { workshop = { v = 1, chars = {}, prices = { v = 1, markets = {} } } }
local keepPrices = db.workshop.prices
local s1 = Session("Rich", db, { prof = ALCH, recipes = rec, schem = sch })
local key = s1.W.Queue.CharKey()
db.workshop.chars[key] = { queue = { { id = 1, name = "Healing Potion", crafts = 3, prof = 171, profName = "Alchemy", icon = 1, outItem = 501, outMin = 1, outMax = 1,
  mats = { { item = 10, qty = 2 } }, seen = 5 } } }
s1.g.filtered = { 1, 2, 3 }
Same(s1.W.Watch.Events(), 4, "the addon watches four events once loaded")
Same(s1.frame.events.TRADE_SKILL_LIST_UPDATE, true)
s1.Flush()   -- the start-up read: a profession already open when the addon loads
Check(s1.Saved(171) and #s1.Saved(171).r == 3, "an already-open profession is read at load, window never shown")
Same(s1.Saved(171).r[1][1] ~= nil, true)
s1.g.prof = SMITH; s1.g.filtered = { 20, 21 }
s1.Fire("TRADE_SKILL_SHOW"); s1.Fire("TRADE_SKILL_LIST_UPDATE")
Same(s1.Saved(164), nil, "a burst of events waits and becomes one read")
s1.Flush()
Check(s1.Saved(164) and #s1.Saved(164).r == 2, "the second profession is remembered too")
Check(s1.Saved(164).at and s1.Saved(164).at > 0, "with its observation time")
Same(s1.W.Session.Snapshot().professions, 0, "and the copy in memory is let go of once saved")
Check(s1.Saved(171).r[1][8] ~= nil, "materials are kept")
Same(db.workshop.prices, keepPrices, "prices untouched"); Same(#db.workshop.chars[key].queue, 1, "queue untouched"); Same(db.workshop.chars[key].queue[1].crafts, 3)

-- Session 2: a fresh client, no profession open. The remembered recipes work for Crafting, Opportunities, Shopping and the price scan.
local s2 = Session("Rich", db, nil)
s2.Flush()
local S2 = s2.W.Session
Same(#S2.Professions(), 2, "both professions come back"); Same(#S2.AllRecipes(), 5)
local want = S2.Wanted()
Check(want[501] and want[10] and want[521] and want[31], "outputs and materials are known before any profession is opened")
Check(S2.Notices()[1]:find("Remembered from", 1, true), S2.Notices()[1])
-- Opportunities from remembered recipes and a seeded price (the price lookup is the existing one)
local P = s2.W.Prices
local market = { realm = "Realm", side = "Alliance", at = s2.W.Queue.Now(), complete = true, read = 1, used = 1, n = 3, items = { [10] = { 100, 50, 5, 50 }, [11] = { 50, 50, 5, 50 }, [501] = { 1000, 5, 5, 5 } } }
db.workshop.prices.markets["Realm|Alliance"] = market
local v = S2.Opportunities()
Check(#v.rows >= 1, "Opportunities rows from remembered recipes")
local hp
for _, r in ipairs(v.rows) do if r.rec.id == 1 then hp = r end end
Same(hp.est.state, "ok", tostring(hp.est.why) .. " missing " .. tostring(hp.est.missing)); Same(hp.est.cost, 250)
s2.g.bags = { [10] = 2 }
local plan = S2.Shopping()
Same(#plan.rows, 1, "Shopping works from the saved queue and remembered data"); Same(plan.rows[1].item, 10); Same(plan.rows[1].short, 4)
Same(s2.g.calls.schematic, nil, "nothing was asked of the game")
Check(S2.Current() and not S2.Current().live, "remembered, not live")
db.workshop.prices.markets["Realm|Alliance"] = nil

-- A newly learned recipe merges in; the rest is kept
s2.g.prof = ALCH; s2.g.recipes[4] = { name = "Elixir of Wisdom" }; s2.g.schem[4] = Schematic(1, 1, { Basic(13, 1) }, 504)
s2.g.recipes, s2.g.schem = rec, sch
rec[4] = { name = "Elixir of Wisdom" }; sch[4] = Schematic(1, 1, { Basic(13, 1) }, 504)
s2.g.filtered = { 4 }   -- a filtered view showing only the new one
s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Same(#s2.Saved(171).r, 4, "the new recipe is added to the three already known")
local ids = {}
for _, r in ipairs(s2.Saved(171).r) do ids[r[1]] = true end
Check(ids[1] and ids[2] and ids[3] and ids[4], "none of the unseen recipes were dropped by the filtered view")
Same(#s2.Saved(164).r, 2, "the other profession is untouched")

-- Filtered, empty and foreign views change nothing
local function Dump(t)
  local out = {}
  for _, p in ipairs({ 171, 164 }) do
    local k = db.workshop.chars[key].known[p]
    local ids2 = {}
    for _, r in ipairs(k.r) do ids2[#ids2 + 1] = r[1] .. ":" .. (r[7] or "") end
    table.sort(ids2)
    out[#out + 1] = p .. "@" .. k.at .. "=" .. table.concat(ids2, ",")
  end
  return table.concat(out, ";")
end
local before = Dump()
s2.g.filtered = {}; s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Same(Dump(), before, "an empty list erases nothing")
s2.g.filtered = nil; s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Same(Dump(), before, "no list yet erases nothing")
s2.g.filtered = { 1 }
for _, why in ipairs({ "linked", "guild", "npc", "changing", "combat" }) do
  s2.g[why] = true
  s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
  Same(Dump(), before, why .. " view: not used")
  s2.g[why] = false
end
s2.g.prof = SMITH; s2.g.linked = true; s2.g.filtered = { 20, 21 }
s2.Fire("TRADE_SKILL_SHOW"); s2.Flush(); s2.g.linked = false
Same(Dump(), before, "someone else's profession cannot contaminate the saved one")
s2.g.prof = nil; s2.Fire("PLAYER_REGEN_ENABLED"); s2.Flush()
Same(Dump(), before, "nothing open: nothing changes")
-- only the game saying 'not learned' removes a remembered recipe
s2.g.prof = ALCH; s2.g.filtered = { 1, 2 }; rec[3].learned = false
s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Check(s2.Saved(171) and #s2.Saved(171).r == 4, "a recipe the list leaves out is still known")
s2.g.filtered = { 1, 2, 3 }
s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Same(#s2.Saved(171).r, 3, "listed as not learned: gone")
rec[3].learned = nil

-- The window being shown does its own reading: the watcher stays out of the way
local reads = s2.W.Watch.reads
s2.W.Window = { IsShown = function() return true end }
s2.g.filtered = { 1, 2 }; s2.Fire("TRADE_SKILL_LIST_UPDATE"); s2.Flush()
Same(s2.W.Watch.reads, reads, "no second read while the window is shown")
s2.W.Window = nil

-- Characters are separate
local s3 = Session("Alt", db, nil); s3.Flush()
Same(#s3.W.Session.Professions(), 0, "another character remembers nothing of these")
s3.g.prof = ALCH; s3.g.recipes, s3.g.schem = rec, sch; s3.g.filtered = { 1 }
s3.Fire("TRADE_SKILL_SHOW"); s3.Flush()
Same(#s3.Saved(171).r, 1, "the alt has its own record")
Same(#s2.Saved(171).r, 3, "and the first is unchanged")

-- Older saves and bad records: an old save with only a queue, and one with junk, both load; the queue survives
local old = { workshop = { v = 1, chars = { ["Rich - Realm"] = {} } } }
local s4 = Session("Rich", old, nil); s4.Flush()
local qk = s4.W.Queue.CharKey()
old.workshop.chars[qk] = { queue = { { id = 7, name = "Old entry", crafts = 2, seen = 1 } },
  known = { [171] = { name = "Alchemy", r = { { 1, "Healing", 0, 0, 0, 0, 0 }, "junk", { 2 } } }, [164] = "junk", [-1] = { name = "x", r = {} } } }
local s5 = Session("Rich", old, nil); s5.Flush()
Same(#s5.W.Session.Professions(), 1, "the readable profession loads, the junk is skipped")
Same(s5.W.Queue.Find(7) ~= nil, true, "the queue is intact")
Same(s5.W.Session.Professions()[1].count, 1)
-- a newer TwichUI's data is never written
old.workshop.v = 2
s5.g.prof = ALCH; s5.g.recipes, s5.g.schem = rec, sch; s5.g.filtered = { 1, 2, 3 }
s5.Fire("TRADE_SKILL_LIST_UPDATE"); s5.Flush()
Same(#old.workshop.chars[qk].known[171].r, 3, "held: nothing written")

-- Nothing is saved about what can be made now
local blob = {}
local function Walk(t, depth) if depth > 6 then return end for k, v2 in pairs(t) do blob[#blob + 1] = tostring(k) if type(v2) == "table" then Walk(v2, depth + 1) end end end
Walk(db.workshop.chars[key].known, 0)
local text = table.concat(blob, " ")
Check(not text:find("have", 1, true) and not text:find("short", 1, true) and not text:find("cooldown", 1, true) and not text:find("craftable", 1, true),
  "no bag counts, craftability or cooldowns in the saved records")

print("PASSED")
