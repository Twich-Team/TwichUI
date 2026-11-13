-- The Workshop (TwichUI_Workshop/ and WorkshopLauncher.lua): the pure arithmetic (crafts against output, combined materials), the
-- saved queue, the reading of the player's own profession window, the session that joins them, the launcher's load behavior and the
-- window's lifecycle. A fake game stands in for C_TradeSkillUI, the bags and the item cache, so this checks our logic, not the game:
-- the in-game checks are listed in docs/workshop.md.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local WORKSHOP_FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

local function Load(c, file)
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. file))
  setfenv(chunk, c)
  chunk("TwichUI_Workshop", {})
end

---------------------------------------------------------------------------
-- A fake profession interface, bags and item cache
---------------------------------------------------------------------------
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

local function Schematic(lo, hi, slots, outItem)
  return { quantityMin = lo, quantityMax = hi, outputItemID = outItem, reagentSlotSchematics = slots }
end
local function Basic(item, qty) return { reagentType = 1, reagents = { { itemID = item } }, quantityRequired = qty, required = true } end

local function Setup(name, db)
  local c = MIClient(name or "Rich", { db = { modules = {} } })
  c.TwichUIDB = db or c.TwichUIDB or {}
  local g = FakeGame(c)
  for _, f in ipairs(WORKSHOP_FILES) do Load(c, f) end
  return c, g, c.TwichUI.Workshop
end

---------------------------------------------------------------------------
-- Crafts and output
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  Same(W.PerCraft(2, 2), "2"); Same(W.PerCraft(2, 3), "2-3"); Same(W.PerCraft(nil, nil), nil, "unknown output stays unknown")
  Same(W.Expected(2, 3, 10), "20-30", "a range scales with crafts, both ends")
  Same(W.Expected(1, 1, 7), "7"); Same(W.Expected(nil, nil, 3), nil)
  Same(W.Int(3, 1, 5), 3); Same(W.Int(3.5, 1, 5), nil); Same(W.Int(0, 1, 5), nil); Same(W.Int("3", 1, 5), nil); Same(W.Int(0/0, 1, 5), nil)
  c.issecretvalue = function(v) return v == "SECRET" end
  Same(W.Int("SECRET", 1, 5), nil, "a secret is dropped"); Same(W.Text("SECRET", 10), nil)
  Same(W.Text("  a\tb \n", 10), "a b"); Same(#W.Text(("x"):rep(200), 80), 80)
  Same(W.Text("héllo", 2), "h", "a multi-byte letter is never cut in half")
end

---------------------------------------------------------------------------
-- Combined materials
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local M = W.Materials
  local entries = {
    { crafts = 3, mats = { { item = 10, qty = 2 }, { item = 11, qty = 1 } } },
    { crafts = 2, mats = { { item = 10, qty = 5 } } },   -- shares item 10 with the first
  }
  local have = { [10] = 12, [11] = 3 }
  local rows, s = M.Rows(entries, function(i) return have[i] end)
  Same(#rows, 2)
  local by = {}
  for _, r in ipairs(rows) do by[r.item] = r end
  Same(by[10].need, 16, "3x2 + 2x5 are added before the bags are applied")
  Same(by[10].have, 12); Same(by[10].short, 4, "12 owned once against 16 needed, not 12 against each recipe")
  Same(by[11].short, 0)
  Same(s.state, "short"); Same(s.shortItems, 1)
  Same(rows[1].item, 10, "what is short comes first")
  have[10] = 16
  rows, s = M.Rows(entries, function(i) return have[i] end)
  Same(s.state, "ready", "everything counted and in the bags")

  -- unknown is never zero and never ready
  rows, s = M.Rows(entries, function(i) if i == 11 then return nil end return have[i] end)
  Same(s.state, "partial"); Same(s.unknownItems, 1)
  for _, r in ipairs(rows) do if r.item == 11 then Check(r.have == nil and r.short == nil, "an unreadable count is unknown, not 0") end end
  local entries2 = { entries[1], { crafts = 4, mats = nil } }
  rows, s = M.Rows(entries2, function(i) return 100 end)
  Same(s.state, "partial", "a recipe with unknown materials stops the queue from being ready"); Same(s.unknown, 1)
  Same(#rows, 2, "its materials are not invented as zero rows")
  rows, s = M.Rows({}, function() return 0 end)
  Same(s.state, "empty")
  rows, s = M.Rows({ { crafts = 1, mats = {} } }, function() return 0 end)
  Same(s.state, "partial", "an empty list of materials is unknown, not 'needs nothing'")
  rows, s = M.Rows(entries, function() return -1 end)
  Same(s.state, "partial", "a nonsense count is unknown")
end

---------------------------------------------------------------------------
-- The saved queue
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local Q = W.Queue
  local rec = { id = 100, name = "Elixir", prof = 171, profName = "Alchemy", icon = 1100, outMin = 1, outMax = 2, mats = { { item = 10, qty = 2 }, { item = 10, qty = 1 } } }
  local e = assert(Q.Add(rec))
  Same(e.crafts, 1); Same(e.mats[1].qty, 3, "the same material twice is added together")
  Check(c.TwichUIDB.workshop.chars["Rich - Forever"].queue[1].id == 100, "saved under the character")
  Same(c.TwichUIDB.workshop.v, 1)
  Check(c.TwichUIDB.workshop.chars["Rich - Forever"].queue[1] ~= e, "the saved table is a copy")
  Same(select(2, Q.Add(rec)), "exists")
  Check(Q.SetCrafts(100, 5)); Same(Q.Find(100).crafts, 5)
  Check(not Q.SetCrafts(100, 0) and not Q.SetCrafts(100, 1000) and not Q.SetCrafts(100, 2.5), "crafts stay 1 to 999 whole")
  Same(Q.Find(100).crafts, 5)
  -- a reload: a fresh read of the saved data
  Q.Unload()
  local again = Q.Entries()
  Same(#again, 1); Same(again[1].crafts, 5); Same(again[1].name, "Elixir"); Same(again[1].outMax, 2); Same(again[1].profName, "Alchemy")
  -- unresolved entries are kept and flagged
  assert(Q.Add({ id = 101, name = "Mystery" }))
  Check(Q.Unresolved(Q.Find(101)), "no materials: unresolved")
  Check(not Q.Unresolved(Q.Find(100)))
  -- another character has its own queue
  c.UnitName = function() return "Alt" end
  Q.Unload()
  Same(#Q.Entries(), 0, "a queue belongs to one character")
  c.UnitName = function() return "Rich" end
  Q.Unload()
  Same(#Q.Entries(), 2)
  -- the limit
  local ok, why
  for i = 1, 40 do ok, why = Q.Add({ id = 1000 + i, name = "R" .. i }) end
  Same(why, "full"); Same(#Q.Entries(), W.MAX_QUEUE)
  -- bad saved entries are left out when read, good ones stay
  c.TwichUIDB.workshop.chars["Rich - Forever"].queue = { { id = "x", name = "Bad" }, { id = 5, name = "Good", crafts = 7 }, "junk", { id = 5, name = "Twice" }, { id = 6 } }
  Q.Unload()
  Same(#Q.Entries(), 1); Same(Q.Entries()[1].name, "Good"); Same(Q.Entries()[1].crafts, 7)
  -- a queue from a newer TwichUI is never changed
  c.TwichUIDB.workshop.v = 99
  Q.Unload()
  local before = c.TwichUIDB.workshop.chars["Rich - Forever"].queue
  Same(select(2, Q.Add({ id = 7, name = "New" })), "held"); Same(select(2, Q.SetCrafts(5, 2)), "held"); Same(select(2, Q.Remove(5)), "held")
  Check(c.TwichUIDB.workshop.chars["Rich - Forever"].queue == before and #before == 5, "nothing was written")
  c.TwichUIDB.workshop.v = 1
  Q.Unload()
  Check(Q.Remove(5)); Same(#Q.Entries(), 0)
  -- no saved variables yet (the game hasn't loaded them): nothing is lost silently
  local saved = c.TwichUIDB
  c.TwichUIDB = nil
  local e2, why2 = Q.Add({ id = 8, name = "Early" })
  Check(e2 == nil and why2 == "unsaved" and #Q.Entries() == 0, "an add that can't be saved says so and is not kept")
  c.TwichUIDB = saved
end

---------------------------------------------------------------------------
-- Refreshing from an observation
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local Q = W.Queue
  Q.Now = function() return 1000 end
  assert(Q.Add({ id = 100, name = "Old name", prof = 171, profName = "Alchemy", icon = 1, outMin = 1, outMax = 1, mats = { { item = 10, qty = 2 } } }))
  Q.SetCrafts(100, 4)
  Q.Now = function() return 2000 end
  Check(not Q.Refresh({ id = 100, name = "Old name", prof = 171, profName = "Alchemy", icon = 1, outMin = 1, outMax = 1, mats = { { item = 10, qty = 2 } } }),
    "nothing differs: nothing is written")
  Same(Q.Find(100).seen, 1000, "the time isn't touched without a change")
  Check(Q.Refresh({ id = 100, name = "New name", prof = 171, profName = "Alchemy", icon = 1, outMin = 2, outMax = 3, mats = { { item = 10, qty = 5 } } }))
  local e = Q.Find(100)
  Same(e.name, "New name"); Same(e.outMax, 3); Same(e.mats[1].qty, 5); Same(e.crafts, 4, "the wanted crafts stay"); Same(e.seen, 2000)
  Q.Unload()
  Same(Q.Entries()[1].mats[1].qty, 5, "and it was saved")
  -- unreadable materials or output never replace known ones
  Check(not Q.Refresh({ id = 100, name = "New name", prof = 171, profName = "Alchemy", icon = 1 }), "unreadable this time: what was known stays")
  Same(Q.Find(100).mats[1].qty, 5); Same(Q.Find(100).outMin, 2)
  -- an unresolved entry is resolved by a good observation
  assert(Q.Add({ id = 101, name = "Late" }))
  Check(Q.Unresolved(Q.Find(101)))
  Check(Q.Refresh({ id = 101, name = "Late", prof = 171, profName = "Alchemy", mats = { { item = 12, qty = 1 } } }))
  Check(not Q.Unresolved(Q.Find(101)))
  Check(not Q.Refresh({ id = 999, name = "Not queued" }), "only queued recipes are kept")
end

---------------------------------------------------------------------------
-- The character's professions and their skill (Observe.Skills: the Overview's progress bars)
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local O = W.Observe
  Check(select(2, O.Skills()) == "api", "this game version has no such call: unavailable, nothing invented")
  local info = { { "Tailoring", 1001, 125, 150 }, { "Fishing", 1002, 0, 75 }, { "Broken", 1003, 80, 50 }, { "Odd", 1004, "x", 10 }, { "", 1005, 5, 10 } }
  local calls = 0
  c.GetProfessions = function() return 1, nil, 2, 3, 4, 5, 1 end
  c.GetProfessionInfo = function(i) calls = calls + 1; local k = info[i] if k then return k[1], k[2], k[3], k[4] end end
  local list = assert(O.Skills())
  Same(#list, 4, "a name is needed (the empty one goes); a repeated index counts once; an empty slot is skipped")
  Same(list[1].name, "Tailoring"); Same(list[1].rank, 125); Same(list[1].max, 150); Same(list[1].icon, 1001)
  Same(list[2].name, "Fishing"); Same(list[2].rank, 0, "a real zero is kept"); Same(list[2].max, 75)
  Check(list[3].name == "Broken" and list[3].rank == nil and list[3].max == nil, "more than the maximum is not a pair: unavailable, not clamped")
  Check(list[4].name == "Odd" and list[4].rank == nil, "a rank that is not a number is unavailable")
  c.GetProfessions = function() return nil end
  Same(#assert(O.Skills()), 0, "a character with no professions: an empty list, not an error")
  c.GetProfessions = function() error("boom") end
  Same(select(2, O.Skills()), "api", "a failing call is unavailable")
  c.GetProfessions = function() return 1 end
  c.GetProfessionInfo = function() error("boom") end
  Same(#assert(O.Skills()), 0, "a failing info call skips that profession")
end

---------------------------------------------------------------------------
-- Reading the profession window
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local O = W.Observe
  g.recipes = { [1] = { name = "Zeta potion", diff = 1 }, [2] = { name = "alpha elixir", diff = 0 }, [3] = { name = "Unlearned", learned = false },
    [4] = { name = "Recraft thing", recraft = true }, [5] = { name = "Gathering", gather = true }, [6] = { name = "Beta" } }
  g.filtered = { 1, 2, 3, 4, 5, 6, 6, 99 }
  local r = assert(O.Read())
  Check(r.complete == false, "without GetAllRecipeIDs the list is the window's filtered one")
  Same(r.prof, 171); Same(r.profName, "Alchemy")
  Same(#r.recipes, 3, "only learned, ordinary recipes; a repeated or unknown id adds nothing")
  Same(r.recipes[1].name, "alpha elixir", "sorted by name, case aside"); Same(r.recipes[1].diff, 0)
  g.hasAll(); g.all = { 1, 2, 6 }
  r = assert(O.Read())
  Check(r.complete == true and #r.recipes == 3, "GetAllRecipeIDs gives a complete list")
  g.all = {}
  r = assert(O.Read())
  Check(r.complete == false, "an empty complete list falls back to the filtered one")

  -- own professions only
  g.linked = true; Same(select(2, O.Read()), "not-own")
  g.linked = false; g.guild = true; Same(select(2, O.Read()), "not-own")
  g.guild = false; g.npc = true; Same(select(2, O.Read()), "not-own")
  g.npc = false
  local T = c.C_TradeSkillUI
  local saved = T.IsTradeSkillLinked
  T.IsTradeSkillLinked = nil
  Same(select(2, O.Read()), "not-own", "a window the game can't confirm as the player's own is not used")
  T.IsTradeSkillLinked = saved
  g.changing = true; Same(select(2, O.Read()), "busy"); g.changing = false
  g.combat = true; Same(select(2, O.Read()), "combat"); g.combat = false
  g.prof = { professionID = 0, professionName = "" }; Same(select(2, O.Read()), "none")
  g.prof = { professionID = 171, professionName = "Alchemy" }
  g.filtered, g.all = {}, {}; Same(select(2, O.Read()), "empty")
  g.filtered, g.all = { 1 }, nil
  c.C_TradeSkillUI = nil; Same(select(2, O.Read()), "api"); c.C_TradeSkillUI = T
  Check(O.Read(), "and it reads again")
  -- C_TradeSkillUI calls that fail are survived
  T.GetRecipeInfo = function() error("boom") end
  local after = O.Read()
  Check(after and #after.recipes == 0, "an erroring recipe call leaves no recipes, not an error")
end

---------------------------------------------------------------------------
-- A recipe's output and materials
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local O = W.Observe
  local function Fill(schem)
    g.schem[1] = schem
    O.ClearCache()
    return O.Fill({ id = 1 })
  end
  local r = Fill(Schematic(1, 3, { Basic(10, 2), Basic(11, 1), { reagentType = 0, reagents = { { itemID = 99 } }, quantityRequired = 1, required = false } }, 500))
  Check(r.filled and r.outMin == 1 and r.outMax == 3 and r.outItem == 500 and #r.mats == 2 and r.why == nil, "an optional extra isn't a requirement")
  r = Fill(Schematic(2, nil, { Basic(10, 1) }))
  Check(r.outMin == 2 and r.outMax == 2, "one number is both ends")
  r = Fill(Schematic(5, 2, { Basic(10, 1) }))
  Check(r.outMin == nil and r.mats ~= nil, "an impossible range is unknown")
  r = Fill(Schematic(1, 1, { { reagentType = 1, reagents = { { itemID = 1 }, { itemID = 2 } }, quantityRequired = 1, required = true } }))
  Check(r.mats == nil and r.why == "unsupported", "a choice of materials isn't guessed at")
  r = Fill(Schematic(1, 1, { Basic(10, 1), { reagentType = 3, reagents = { { itemID = 3 } }, quantityRequired = 1, required = true } }))
  Check(r.mats == nil and r.why == "unsupported", "an automatic reagent is unsupported")
  r = Fill(Schematic(1, 1, { Basic(10, 1), { reagentType = 2, reagents = { { itemID = 3 } }, quantityRequired = 1, required = true } }))
  Check(r.mats == nil and r.why == "unsupported", "a required extra is unsupported")
  r = Fill(Schematic(1, 1, { { reagentType = 1, reagents = { { currencyID = 5 } }, quantityRequired = 1, required = true } }))
  Check(r.mats == nil and r.why == "unsupported", "a currency isn't a material")
  r = Fill(Schematic(1, 1, { { reagentType = 1, reagents = { { itemID = 3 } }, quantityRequired = 1, required = true, variableQuantities = { 1 } } }))
  Check(r.mats == nil and r.why == "unsupported", "variable quantities are unsupported")
  r = Fill(Schematic(1, 1, {}))
  Check(r.mats == nil and r.why == "unsupported", "no materials at all is unknown, never zero")
  r = Fill(Schematic(1, 1, { Basic(10, 0) }))
  Check(r.mats == nil, "a zero count is not a material")
  r = Fill(nil)
  Check(not r.filled and r.mats == nil, "a recipe the game can't describe yet is tried again later")
  g.schem[1] = Schematic(1, 1, { Basic(10, 1) })
  local before = g.calls.schematic
  r = O.Fill(r)
  Check(r.filled and r.mats, "and is filled when the game has it")
  O.Fill(r)
  Same(g.calls.schematic, before + 1, "asked for once")
  -- a secret anywhere is dropped
  c.issecretvalue = function(v) return v == "S" end
  r = Fill(Schematic("S", "S", { Basic(10, 1) }))
  Check(r.outMin == nil and r.mats ~= nil, "a secret output is unknown, not a crash")
end

---------------------------------------------------------------------------
-- The session
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local S, Q, O = W.Session, W.Queue, W.Observe
  g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 }, [3] = { name = "Anti-Venom" } }
  g.schem[1] = Schematic(1, 1, { Basic(10, 2), Basic(11, 1) })
  g.schem[2] = Schematic(1, 2, { Basic(10, 3) })
  g.schem[3] = Schematic(1, 1, { { reagentType = 1, reagents = { { itemID = 1 }, { itemID = 2 } }, quantityRequired = 1, required = true } })
  g.filtered = { 1, 2, 3 }
  Check(S.Notices()[1]:find("Open one of your professions", 1, true), "nothing read yet: an instruction, not an empty list")
  Check(S.Observe())
  Same(#S.Browse(), 3)
  Check(S.Notices()[1]:find("filters", 1, true) and S.Notices()[1]:find("may not show", 1, true), "a filtered list says so")
  Same(g.calls.schematic, nil, "browsing reads no schematics until rows are filled")
  S.SetFilter("potion"); Same(#S.Browse(), 2); S.SetFilter("  "); Same(#S.Browse(), 3)

  local rec = S.Browse()[1]
  Same(rec.name, "Anti-Venom")
  Check(S.Add(rec)); Check(Q.Unresolved(Q.Find(3)), "an unsupported recipe is queued as unresolved")
  Check(S.Note():find("aren't known", 1, true))
  Same(S.Add(rec), false); Check(S.Note():find("already", 1, true))
  for _, r in ipairs(S.Browse()) do if r.id == 1 or r.id == 2 then Check(S.Add(r)) end end
  Check(S.SetCrafts(1, 3)); Check(S.Change(2, 1)); Same(Q.Find(2).crafts, 2); Check(not S.Change(404, 1))
  Check(S.Change(1, -10)); Same(Q.Find(1).crafts, 1, "never below one craft")

  -- materials: shared item 10 added first; the bags counted once
  S.SetCrafts(1, 3)    -- 3 x (10x2, 11x1)
  S.SetCrafts(2, 2)    -- 2 x (10x3)
  g.bags = { [10] = 9, [11] = 3 }
  local rows, sum = S.Materials()
  local by = {}
  for _, r in ipairs(rows) do by[r.item] = r end
  Same(by[10].need, 12); Same(by[10].short, 3); Same(by[11].short, 0)
  Same(sum.state, "partial", "the unresolved recipe holds back 'ready'")
  Check(S.Headline(sum):find("can't be counted yet", 1, true) and S.Headline(sum):find("Open", 1, true))
  S.Remove(3)
  rows, sum = S.Materials(); Same(sum.state, "short")
  Same((S.Headline(sum)), "Still needed: 1 material.")
  g.bags[10] = 12
  rows, sum = S.Materials(); Same(sum.state, "ready")
  Same((S.Headline(sum)), "Ready to craft: all the materials are in your bags.")
  g.bags[10] = nil
  rows, sum = S.Materials(); Same(sum.state, "partial", "a bag count the game can't give is unknown, not zero")

  -- crafts and output in the queue rows
  local q = S.QueueRows()
  Same(q[1].perCraft, "1"); Same(q[1].expected, "3"); Same(q[2].perCraft, "1-2"); Same(q[2].expected, "2-4")

  -- switching professions keeps the queue and each profession's list
  g.prof = { professionID = 164, professionName = "Blacksmithing" }
  g.recipes[20] = { name = "Copper Bar" }; g.schem[20] = Schematic(1, 1, { Basic(30, 1) })
  g.filtered = { 20 }
  Check(S.Observe())
  Same(#S.Professions(), 2); Same(S.Current().profName, "Blacksmithing"); Same(#S.Browse(), 1)
  Same(#S.QueueRows(), 2, "the queue stays")
  S.Select(171); Same(S.Current().profName, "Alchemy"); Same(#S.Browse(), 3)
  -- a window that is not the player's own leaves what was read, and says so
  g.linked = true
  Check(not S.Observe()); Same(S.Why(), "not-own")
  Same(S.Current().profName, "Alchemy", "the earlier own list stays")
  Check(S.Notices()[#S.Notices()]:find("isn't one of your own", 1, true))
  g.linked = false

  -- an incomplete (filtered) list never removes or changes a queued recipe it leaves out
  g.prof = { professionID = 171, professionName = "Alchemy" }
  g.filtered = { 2 }
  g.recipes[2] = { name = "Mana Potion (renamed)", diff = 0 }
  Check(S.Observe())
  Same(#Q.Entries(), 2, "recipes the list omits are not forgotten")
  Same(Q.Find(1).name, "Healing Potion", "and are not changed")
  Same(Q.Find(2).name, "Mana Potion (renamed)", "while one it does show is refreshed")
  -- open recipe
  Check(S.OpenRecipe(2)); Same(g.opened[1], 2)
  g.openFails = true
  Check(not S.OpenRecipe(2)); Check(S.Note():find("Open Alchemy first", 1, true) or S.Note():find("Open its profession", 1, true))
  -- the Workshop never changed the profession window (any C_TradeSkillUI.Set*/Clear*/Close* call would have raised)
  -- hiding forgets what was read but not the queue
  S.Reset()
  Same(S.Snapshot().professions, 0, "nothing is held in memory"); Same(O.CacheSize(), 0); Same(#Q.Entries(), 2)
  Same(#S.Professions(), 2, "but what was read is remembered and comes back when it is needed")
end

---------------------------------------------------------------------------
-- Remembered recipes: kept between sessions, brought up to date by a read
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local S, Q, O, KN = W.Session, W.Queue, W.Observe, W.Known
  g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 }, [3] = { name = "Anti-Venom" } }
  g.schem[1] = Schematic(1, 1, { Basic(10, 2), Basic(11, 1) }, 501)
  g.schem[2] = Schematic(1, 2, { Basic(10, 3) }, 502)
  g.schem[3] = Schematic(1, 1, { { reagentType = 1, reagents = { { itemID = 1 }, { itemID = 2 } }, quantityRequired = 1, required = true } }, 503)
  g.all = nil; g.hasAll()
  g.all = { 1, 2, 3 }
  Same(#S.Professions(), 0, "a new character remembers nothing")
  Check(S.Observe())
  Same(S.FillSome(math.huge), 0)
  local key = Q.CharKey()
  local saved = c.TwichUIDB.workshop.chars[key].known[171]
  Check(saved and saved.name == "Alchemy" and saved.complete == true and #saved.r == 3, "the read profession is kept for this character")
  Same(saved.r[1][2], "Anti-Venom", "in the order shown"); Same(saved.r[1][7], 2, "an unsupported recipe is kept as such")
  Same(c.TwichUIDB.workshop.v, 1)
  Check(not saved.r[2].diff and #saved.r[2] == 11, "a flat record: difficulty is not kept; healing potion = 7 fields + 2 materials")

  -- "a reload": a new game session on the same saved data
  local c2, g2, W2 = Setup("Rich", c.TwichUIDB)
  g2.recipes, g2.schem = g.recipes, g.schem; g2.hasAll()
  local S2 = W2.Session
  local P = S2.Professions()
  Same(#P, 1); Same(P[1].name, "Alchemy"); Same(P[1].count, 3)
  Same(g2.calls.schematic, nil, "nothing is read from the game to know them")
  Same(#S2.AllRecipes(), 3)
  local want = S2.Wanted()
  Check(want[501] and want[502] and want[10] and want[11], "outputs and materials are known without opening the profession")
  Check(S2.Notices()[1]:find("Remembered from", 1, true) and S2.Notices()[1]:find("Open Alchemy to update it", 1, true), S2.Notices()[1])
  Same(S2.FillSome(math.huge), 0); Same(g2.calls.schematic, nil, "a remembered profession is not asked again while it isn't open")
  local rec
  for _, r in ipairs(S2.Browse()) do if r.id == 2 then rec = r end end
  Same(rec.outItem, 502); Same(rec.outMin, 1); Same(rec.outMax, 2); Same(rec.mats[1].qty, 3); Same(rec.diff, nil, "no difficulty for a remembered recipe")
  Check(S2.Add(rec), "a remembered recipe can be queued"); Same(W2.Queue.Find(2).mats[1].item, 10)

  -- opening the profession: new recipes are learned, changed ones updated, nothing is lost
  g2.recipes[4] = { name = "Elixir of Wisdom", diff = 2 }
  g2.schem[4] = Schematic(1, 1, { Basic(12, 1) }, 504)
  g2.schem[1] = Schematic(1, 1, { Basic(10, 5), Basic(11, 1) }, 501)   -- changed
  g2.all = { 1, 2, 3, 4 }
  Check(S2.Observe())
  Same(#S2.Browse(), 4)
  Check(S2.Current().live); Check(S2.Notices()[1] == nil, "read this session: no 'remembered' note")
  local r1
  for _, r in ipairs(S2.Browse()) do if r.id == 1 then r1 = r end end
  Same(r1.mats[1].qty, 2, "what was remembered is there at once"); Same(r1.diff, 1, "and the difficulty is the fresh one")
  Same(S2.FillSome(math.huge), 0)
  Same(r1.mats[1].qty, 5, "then brought up to date from the game")
  local saved2 = c.TwichUIDB.workshop.chars[key].known[171]
  Same(#saved2.r, 4, "the new recipe is kept")
  local found, fresh
  for _, r in ipairs(saved2.r) do if r[1] == 1 then found = r elseif r[1] == 4 then fresh = r end end
  Same(found[9], 5, "and the change"); Same(fresh[2], "Elixir of Wisdom"); Same(fresh[8], 12)

  -- a list that follows the window's filters keeps what it leaves out
  g2.all = nil; g2.filtered = { 4 }
  Check(S2.Observe())
  Same(#S2.Browse(), 1, "browsing follows the filters"); Same(#S2.AllRecipes(), 4, "but all four are still known")
  Same(#c.TwichUIDB.workshop.chars[key].known[171].r, 4, "and still kept")

  -- Reset (the window closed) saves, then forgets memory; the next use brings it back
  S2.Reset()
  Same(S2.Snapshot().professions, 0); Same(#S2.AllRecipes(), 4)

  -- another profession is added beside it; another character has its own
  g2.prof = { professionID = 164, professionName = "Blacksmithing" }
  g2.recipes[20] = { name = "Copper Bar" }; g2.schem[20] = Schematic(1, 1, { Basic(30, 1) }, 520)
  g2.filtered = { 20 }; g2.all = nil
  Check(S2.Observe())
  Same(#S2.Professions(), 2); Same(#S2.AllRecipes(), 5)
  local c3, g3, W3 = Setup("Alt", c.TwichUIDB)
  Same(#W3.Session.Professions(), 0, "another character remembers nothing of this one")

  -- a newer TwichUI's data is never written
  c.TwichUIDB.workshop.v = 2
  local before = #c.TwichUIDB.workshop.chars[key].known[171].r
  g2.recipes[5] = { name = "Another" }; g2.schem[5] = Schematic(1, 1, { Basic(31, 1) }, 505)
  g2.prof = { professionID = 171, professionName = "Alchemy" }; g2.all = { 1, 2, 3, 4, 5 }
  Check(S2.Observe()); Same(S2.FillSome(math.huge), 0)
  Same(#c.TwichUIDB.workshop.chars[key].known[171].r, before, "held: nothing written"); Same(#S2.Browse(), 5, "but it still works in memory")
  c.TwichUIDB.workshop.v = 1

  -- bad saved records are skipped, never used
  local db = { workshop = { v = 1, chars = { [key] = { known = {
    [171] = { name = "Alchemy", at = 5, complete = true, r = {
      { 1, "Good", 5, 501, 1, 1, 1, 10, 2 }, "junk", { "x" }, { 2, "Bad mats", 0, 0, 0, 0, 1, 10 }, { 3, "Zero qty", 0, 0, 0, 0, 1, 10, 0 },
      { 4, ("x"):rep(200), 0, 0, 0, 0, 0 }, { 1, "Duplicate", 0, 0, 0, 0, 0 },
    } },
    [-4] = { name = "Bad id", r = { { 1, "A", 0, 0, 0, 0, 0 } } },
    [164] = "junk", [165] = { name = "No list" },
  } } } } }
  local c4, g4, W4 = Setup("Rich", db)
  local P4 = W4.Session.Professions()
  Same(#P4, 1); Same(P4[1].name, "Alchemy")
  local names = {}
  for _, r in ipairs(W4.Session.AllRecipes()) do names[r.id] = r end
  Same(names[1].name, "Good"); Same(names[1].mats[1].qty, 2)
  Same(names[2] and names[2].mats, nil, "a record with a half pair of materials is not trusted for them")
  Same(names[3] and names[3].mats, nil, "a zero quantity is not a material")
  Same(#names[4].name, 80, "a long name is cut")

  -- the limits
  local db5 = { workshop = { v = 1, chars = {} } }
  local c5, g5, W5 = Setup("Rich", db5)
  local K5 = W5.Known
  local ckey = W5.Queue.CharKey()
  for i = 1, 7 do
    Check(K5.Store({ prof = 100 + i, profName = "P" .. i, at = i, complete = true, recipes = { { id = i, name = "R" .. i } } }))
  end
  local count = 0
  for k in pairs(db5.workshop.chars[ckey].known) do count = count + 1 end
  Same(count, K5.MAX_PROFS, "at most five professions")
  Check(db5.workshop.chars[ckey].known[107] and not db5.workshop.chars[ckey].known[101], "the one read longest ago goes")
  local many = {}
  for i = 1, K5.MAX_RECIPES + 50 do many[i] = { id = i, name = "R" .. i } end
  Check(K5.Store({ prof = 107, profName = "P7", at = 99, complete = true, recipes = many }))
  Same(#db5.workshop.chars[ckey].known[107].r, K5.MAX_RECIPES, "at most 600 recipes of a profession")
  Same(K5.Store({ prof = 1, profName = "x", recipes = {} }), false, "nothing to keep")
end

---------------------------------------------------------------------------
-- The launcher: not at login, plain failures, combat
---------------------------------------------------------------------------
do
  local c = MakeClient("Rich", { "!!!TwichUI" })
  c.print = function(s) c.said = c.said or {}; c.said[#c.said + 1] = tostring(s) end
  local loads, faults = 0, 0
  c.geterrorhandler = function() return function() faults = faults + 1 end end   -- the faults are expected here: count them
  c.C_AddOns.LoadAddOn = function() loads = loads + 1; return false, "DISABLED" end
  local chunk = assert(loadfile(ROOT .. "WorkshopLauncher.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  local R = c.TwichUI
  Check(R.WorkshopLauncher and not R.Workshop, "only the launcher exists at login")
  Same(loads, 0, "nothing loads at login")
  Check(not R.WorkshopLauncher.Loaded())
  -- combat: refused before asking the game
  c.InCombatLockdown = function() return true end
  local ok, why = R.WorkshopLauncher.Load()
  Check(ok == false and why == "COMBAT" and loads == 0, "not loaded in combat")
  R.WorkshopLauncher.Toggle()
  Check(c.said[#c.said]:find("not during combat", 1, true), c.said[#c.said])
  c.InCombatLockdown = function() return false end
  -- refusals are explained in plain words
  R.WorkshopLauncher.Toggle()
  Check(c.said[#c.said]:find("turned off in your AddOns list", 1, true), c.said[#c.said]); Same(loads, 1)
  c.C_AddOns.LoadAddOn = function() return false, "MISSING" end
  R.WorkshopLauncher.Open()
  Check(c.said[#c.said]:find("TwichUI_Workshop, is missing", 1, true), c.said[#c.said])
  c.C_AddOns.LoadAddOn = function() error("kaboom") end
  Check(not R.WorkshopLauncher.Open()); Check(c.said[#c.said]:find("ran into an error", 1, true))
  -- loaded but nothing started
  c.C_AddOns.LoadAddOn = function() return true end
  Same(select(2, R.WorkshopLauncher.Load()), "INCOMPLETE")
  Same(R.WorkshopLauncher.Snapshot().failed, "INCOMPLETE")
  -- loaded and ready: the window is asked, and an error in it is caught
  local shown = 0
  c.C_AddOns.LoadAddOn = function() R.Workshop = { ready = true, Open = function() shown = shown + 1 end, Toggle = function() shown = shown + 1 end }; return true end
  Check(R.WorkshopLauncher.Toggle()); Same(shown, 1)
  c.InCombatLockdown = function() return true end
  Check(R.WorkshopLauncher.Toggle(), "once loaded it still toggles in combat"); Same(shown, 2)
  R.Workshop.Toggle = function() error("bad window") end
  Check(not R.WorkshopLauncher.Toggle())
  Check(faults >= 2, "both failures were reported to the error handler, not swallowed")
  -- the command goes through the same place
  c.InCombatLockdown = function() return false end
  R.Workshop.Toggle = function() shown = shown + 1 end
  local n = shown
  c.SlashCmdList.TWICHUI("workshop")
  Same(shown, n + 1, "/tui workshop toggles")
end

---------------------------------------------------------------------------
-- Packaging: the sibling addon is what the launcher asks the game to load
---------------------------------------------------------------------------
do
  local function Read(path) local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return t end
  local core = Read(ROOT .. "!!!TwichUI.toc")
  Check(core:find("\nWorkshopLauncher.lua", 1, true), "the core TOC loads WorkshopLauncher.lua")
  local toc = Read(REPO .. "TwichUI_Workshop/TwichUI_Workshop.toc")
  Check(toc:find("## LoadOnDemand: 1", 1, true), "load on demand")
  Check(toc:find("## RequiredDeps: !!!TwichUI", 1, true), "needs the core")
  Check(toc:match("\n## SavedVariables: ([^\r\n]+)") == "TwichUIWorkshopDB", "the market data (and nothing else) has saved variables of its own")
  local last
  for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua$") and not line:match("^#") then
      local f = io.open(REPO .. "TwichUI_Workshop/" .. line, "rb")
      Check(f, "TOC file exists: " .. line); if f then f:close() end
      last = line
    end
  end
  Same(last, "Window.lua", "the window file is last (it marks the addon ready)")
  Check(Read(REPO .. ".pkgmeta"):find("TwichUI_Workshop: TwichUI_Workshop", 1, true), ".pkgmeta moves the folder beside the core")
  Same(toc:match("## Interface: (%d+)"), core:match("## Interface: (%d+)"), "same interface number as the core")
end

print("PASSED")
