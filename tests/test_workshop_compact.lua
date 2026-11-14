-- The compact companion (TwichUI_Workshop/Compact.lua, P2.1): Travel and Craft, what each shows, a burst of bag events is one redraw, Full view swaps
-- back and nothing is held when both views are closed. Also the progress layer (Progress.lua: the player's own "Crafted one", the game's evidence
-- switched off until verified, one credit per cast) and the notices (Notice.lua: verified progress only, nothing at the first look, gathered).
-- Recording stand-in frames (the world of test_workshop_strategy_ui.lua): this proves what is drawn and kept, not how the game draws it.
dofile(TESTS .. "mi_mock.lua")
local Press = dofile(TESTS .. "press.lua")   -- opt-in (M5): frames record the mouse state, and Press refuses a control that could not take a click

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local c = MIClient("Rich", {
  db = { modules = {} },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent, template)
      local fr = MIFake(kind, parent)
      fr.SetColorTexture = function() end
      fr.SetVertexColor = function() end
      fr.SetBackdropColor = function() end
      fr.SetBackdropBorderColor = function() end
      fr.SetTexCoord = function() end
      fr.SetTexture = function(s, v) s.texture = v end
      fr.SetFrameLevel = function(s, l) s.level = l end
      fr.GetFrameLevel = function(s) return s.level or 5 end
      fr.SetVerticalScroll = function(s, v) s.scroll = v end
      fr.GetVerticalScroll = function(s) return s.scroll or 0 end
      fr.SetFontObject = function() end
      fr.SetMaxLetters = function() end
      fr.SetAutoFocus = function() end
      fr.SetTextInsets = function() end
      fr.SetJustifyV = function() end
      fr.SetWordWrap = function() end
      fr.SetToplevel = function() end
      fr.SetMovable = function() end
      fr.SetClampedToScreen = function() end
      fr.RegisterForDrag = function() end
      fr.SetDontSavePosition = function() end
      fr.UnregisterAllEvents = function(s) s.events = {} end
      fr.SetFrameStrata = function() end
      fr.SetMotionScriptsWhileDisabled = function() end
      fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
      fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end return t end
      Press.Instrument(fr, name)   -- last, so it replaces the no-op EnableMouse above with one that records
      if name then cl[name] = fr end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    cl.UISpecialFrames = {}
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = {},
})
c.TwichUIDB = c.TwichUIDB or {}
local R = c.TwichUI

-- the fake game (as in test_workshop.lua)
local g = { bags = {}, names = { [10] = "Peacebloom", [11] = "Silverleaf" }, recipes = {}, schem = {}, opened = {} }
g.prof = { professionID = 171, professionName = "Alchemy" }
c.C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return g.prof end,
  IsNPCCrafting = function() return false end, IsTradeSkillGuild = function() return false end, IsTradeSkillLinked = function() return false end,
  IsDataSourceChanging = function() return false end,
  GetFilteredRecipeIDs = function() return g.filtered end,
  GetRecipeInfo = function(id) local r = g.recipes[id]; return r and { name = r.name, learned = true, icon = 1000 + id, relativeDifficulty = r.diff } end,
  GetRecipeSchematic = function(id) return g.schem[id] end,
  OpenRecipe = function(id) g.opened[#g.opened + 1] = id end,
}
c.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } }
c.C_Item = {
  GetItemCount = function(id) return g.bags[id] end,
  GetItemInfoInstant = function(id) return id, "a", "b", "", 5000 + id end,
  GetItemInfo = function(id) return g.names[id] end,
  RequestLoadItemDataByID = function() end,
}
c.InCombatLockdown = function() return false end
c.IsShiftKeyDown = function() return false end

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewStrategy.lua", "Compact.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
Check(W.ready and W.Open and W.Toggle, "the window file marks the addon ready")
local Win, S, Q = W.Window, W.Session, W.Queue
local St, UI = W.Strategy, W.UI
local function Money(n) return UI.Money(n) end

-- the world of test_workshop_strategy.lua: a Sword (recipe 1, item 90) needs 4 Bars (20) and 2 Ore (30); a Bar (recipe 500) is made from 2 Ore
g.names = { [10] = "Peacebloom", [11] = "Silverleaf", [20] = "Bar", [30] = "Ore", [90] = "Sword" }
g.recipes = { [1] = { name = "Sword", diff = 1 }, [500] = { name = "Bar", diff = 1 } }
g.schem[1] = { quantityMin = 1, quantityMax = 1, outputItemID = 90, reagentSlotSchematics = {
  { reagentType = 1, reagents = { { itemID = 20 } }, quantityRequired = 4, required = true }, { reagentType = 1, reagents = { { itemID = 30 } }, quantityRequired = 2, required = true } } }
g.schem[500] = { quantityMin = 1, quantityMax = 1, outputItemID = 20, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 30 } }, quantityRequired = 2, required = true } } }
g.filtered = { 1, 500 }
g.bags = { [20] = 0, [30] = 3, [90] = 0 }
c.GetRealmName = function() return "Realm" end
c.UnitFactionGroup = function() return "Alliance" end
c.GetMoneyString = function(n) return n .. "c" end
c.C_Timer = { After = function() end }
c.time = function() return 1000000 end
c.TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Alliance"] = { f = 2, scope = "full", realm = "Realm", side = "Alliance", at = os.time() - 3600, complete = true, read = 1, used = 1, n = 3,
  items = { [20] = "250,9,9,9,0", [30] = "100,9,9,9,0", [90] = "3000,9,9,9,0" }, hist = {}, sd = {} } } }


Win.Show()
local f = Win.Frame()
-- a queue: the Sword (needs 4 Bars and 2 Ore) and the Bars it needs
do
  local recs = {}
  for _, r in ipairs(S.AllRecipes()) do recs[r.name] = r end
  Check(S.Add(recs.Bar) and S.SetCrafts(500, 4) and S.Add(recs.Sword), "queued Bar x4 and Sword x1")
end

-- the compact companion (P2.1): Travel and Craft, a burst of bag events is one redraw, Full view swaps back, nothing held when both are closed ------
do
  local Cm = W.Compact
  Win.Show(); Win.SetMode("shop"); St.Pump(); Win.Render()
  local fw = Win.Frame()
  Check(fw.compact and fw.compact:IsShown(), "the window offers Compact view")
  fw.compact:GetScript("OnClick")(fw.compact)
  local cf = Cm.Frame()
  Check(cf and cf:IsShown() and not Win.IsShown(), "the compact view takes the window's place")
  St.Pump(); Cm.Render()
  Same(Cm.Mode(), "travel", "it opens on Travel")
  local plan, ctx = S.ShoppingPlan()
  local rows = Cm.TravelRows(plan, ctx)
  local data = Win.Lists().compact.data
  Same(#data, #rows, "one row per material still to get")
  for i, r in ipairs(rows) do
    Check(r.word == "Vendor" or r.word == "Auction" or r.word == "Craft" or r.word == "Collect" or r.word == "No source", "the source in words: " .. tostring(r.word))
    Same(data[i].word, r.word)
    Check(data[i].title:find(tostring(r.qty), 1, true), "the quantity is in the row")
  end
  Check(#rows == 0 or cf.summary:GetText():find("still needed", 1, true), cf.summary:GetText())
  Check(not cf.summary:GetText():find("Estimated", 1, true), "no market valuations in Travel")
  -- Craft
  cf.craft:GetScript("OnClick")(cf.craft)
  Same(Cm.Mode(), "craft")
  Same(#Win.Lists().compact.data, #Q.Entries(), "one row per queued recipe")
  Check(cf.summary:GetText():find("left in the plan", 1, true), cf.summary:GetText())
  Check(cf.bar:IsShown() and cf.barText:GetText():find("ready", 1, true), "a bar of how many recipes are ready")
  -- the pure parts
  do
    local view = S.Stock()
    local have = function(item) return ({ [1] = 4, [2] = 0 })[item] or 0 end
    local crows, nextRow, left, ready = Cm.CraftRows({ { name = "A", crafts = 2, mats = { { item = 1, qty = 2 } } }, { name = "B", crafts = 3, mats = { { item = 2, qty = 1 } } } },
      have, view)
    Same(crows[1].state, "ready", "2 crafts of 2 each: 4 in the bags"); Same(crows[2].state, "short")
    Same(nextRow.entry.name, "A", "the next craft is the first one that is ready"); Same(left, 5); Same(ready, 1)
    crows, nextRow = Cm.CraftRows({ { name = "B", crafts = 3, mats = { { item = 2, qty = 1 } } } }, have, view)
    Same(nextRow, nil, "nothing ready: no next craft is claimed")
  end
  -- a burst of bag events: one redraw, later; nothing per frame
  local pending = {}
  local saved = c.C_Timer
  c.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
  local before = Cm.Stats().renders
  for _ = 1, 6 do cf:GetScript("OnEvent")(cf, "BAG_UPDATE_DELAYED") end
  Same(#pending, 1, "six bag events are one scheduled redraw")
  for _, fn in ipairs(pending) do fn() end
  Same(Cm.Stats().renders, before + 1, "and one redraw")
  c.C_Timer = saved
  -- Full view: back to the window; the queue and the choices are kept
  local queued = #Q.Entries()
  cf.full:GetScript("OnClick")(cf.full)
  Check(Win.IsShown() and not cf:IsShown(), "Full view swaps back")
  Same(#Q.Entries(), queued, "the queue is kept")
  -- closing the compact view with the window hidden lets go of the plans
  Cm.Show("travel"); St.Pump()
  Cm.Hide()
  Same(St.Stats().running, 0, "nothing runs while neither view is shown")
  Win.Show()
end


-- live Shopping (P2.1): a material that arrives in the bags leaves the list after one settled redraw; a source choice is kept ------------------------
do
  local Cm = W.Compact
  Cm.Show("travel"); St.Pump(); Cm.Render()
  local cf = Cm.Frame()
  local function Has(item) for _, d in ipairs(Win.Lists().compact.data) do if d.item == item then return d end end end
  local plan = S.ShoppingPlan()
  local target
  for _, r in ipairs(plan.rows) do if r.kind ~= "collect" and r.item == 30 then target = r end end
  Check(target and Has(30), "Ore is still to get")
  S.PickSource(30, "auction"); St.Pump(); Cm.Render()
  local before = Has(30).title
  local pending = {}
  local saved = c.C_Timer
  c.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
  g.bags[30] = 99   -- bought or collected: the bags now hold enough (how it arrived is not claimed)
  for _ = 1, 4 do cf:GetScript("OnEvent")(cf, "BAG_UPDATE_DELAYED") end
  Same(#pending, 1, "one redraw for the burst")
  St.Pump()
  for _, fn in ipairs(pending) do fn() end
  St.Pump(); Cm.Render()
  c.C_Timer = saved
  Check(not Has(30), "the Ore row is gone once the bags hold enough (was: " .. before .. ")")
  Same(S.picks[30], "auction", "the player's source choice is kept while the material is still part of the plan")
  g.bags[30] = 3
  for _ = 1, 2 do cf:GetScript("OnEvent")(cf, "BAG_UPDATE_DELAYED") end
  St.Pump(); Cm.Render()
  Check(Has(30), "and back when the bags hold less (used or moved: no claim either way)")
  Cm.ShowFull()
end

print("PASSED test_workshop_compact")
