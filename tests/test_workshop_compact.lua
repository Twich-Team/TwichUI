-- The compact companion (TwichUI_Workshop/Compact.lua, P2.1): Travel and Craft, what each shows, a burst of bag events is one redraw, Full view swaps
-- back and nothing is held when both views are closed. Also the progress layer (Progress.lua: the player's own "Crafted one", the game's evidence
-- switched off until verified, one credit per cast) and the notices (Notice.lua: verified progress only, nothing at the first look, gathered).
-- Recording stand-in frames (the world of test_workshop_strategy_ui.lua): this proves what is drawn and kept, not how the game draws it.
dofile(TESTS .. "mi_mock.lua")
local Press = dofile(TESTS .. "press.lua")   -- opt-in (M5): frames record the mouse state, and Press refuses a control that could not take a click

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
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

local loadStart, historyReads = os.clock(), 0
local actualHistoryRead
for _, f in ipairs({ "Data.lua", "BridgeCodec.lua", "BridgeSchema.lua", "BridgeValidate.lua", "Bridge.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Fees.lua", "Estimate.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "auction/AdvancedChart.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewStrategy.lua", "Progress.lua", "Compact.lua", "Notice.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  if f == "History2.lua" then
    actualHistoryRead = R.Workshop.History2.Read
    R.Workshop.History2.Read = function(...) historyReads = historyReads + 1; return actualHistoryRead(...) end
  end
end
local loadMS = (os.clock() - loadStart) * 1000
local W = R.Workshop
Check(W.ready and W.Open and W.Toggle, "the window file marks the addon ready")
local Win, S, Q = W.Window, W.Session, W.Queue
local St, UI = W.Strategy, W.UI
Check(not Win.Frame() and not W.Compact.IsShown(), "loading Workshop builds no window")
Same(St.Stats().started, 0, "loading starts no planning")
Check(not W.Scan.Busy() and W.Progress.auto == false, "loading neither scans nor enables unverified progress")
Same(historyReads, 0, "loading decodes no history")
R.Workshop.History2.Read = actualHistoryRead
print(("Workshop source initialization: %.3f ms; no windows, planning or history decoding (synthetic; excludes SavedVariables deserialization)"):format(loadMS))
Check(W.Compact.SetMode("craft"), "compact preference changes while hidden")
Same(S.CompactMode(), "craft"); Same(c.TwichUIDB.workshop.view.compactMode, "craft")
Check(not Win.Frame() and not W.Compact.IsShown(), "preference opens neither view")
Check(not W.Compact.SetMode("invalid")); Same(S.CompactMode(), "craft")
Check(W.Compact.SetMode("travel")); Same(S.CompactMode(), "travel")
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

-- progress (Progress.lua): the player's "Crafted one" always; the game's evidence only when switched on, once per cast --------------------------------
do
  local P, Nt = W.Progress, W.Notice
  Check(P.auto == false and not P.Listening(), "automatic counting is OFF and nothing is registered until the client run confirms the evidence")
  Same(select(2, P.OnSpellcast("player", "Cast-1", 500)), "off", "while off, the game's events change nothing")
  Same(Q.Find(500).crafts, 4)
  -- the player's own click, through the Crafting page
  Win.SetMode("craft"); Win.Render()
  local craft = Win.Craft()
  S.Select(500); Win.Render()
  local d = craft.detail
  Check(d.done and d.done:IsShown(), "the chosen craft offers Crafted one")
  d.done:GetScript("OnClick")(d.done)
  Same(Q.Find(500).crafts, 3, "one craft fewer")
  Check(f.note:GetText():find("Bar crafted: 3 crafts left.", 1, true), f.note:GetText())
  -- a mistaken click is taken back: Undo appears, counts the craft again and goes
  Check(d.undo:IsShown(), "Undo is offered after Crafted one")
  d.undo:GetScript("OnClick")(d.undo)
  Same(Q.Find(500).crafts, 4, "the craft is counted again"); Check(not d.undo:IsShown(), "and Undo goes")
  Check(f.note:GetText():find("Undone: Bar, 4 crafts left.", 1, true), f.note:GetText())
  Same(select(2, W.Progress.Undo()), "nothing", "only once")
  d.done:GetScript("OnClick")(d.done)
  Same(Q.Find(500).crafts, 3)
  -- the game's evidence, switched on here only to prove the rules (it is not on for players)
  P.auto = true
  Check(P.OnSpellcast("player", "Cast-2", 500), "a successful cast of a queued recipe is one craft")
  Same(Q.Find(500).crafts, 2)
  Same(select(2, P.OnSpellcast("player", "Cast-2", 500)), "duplicate", "the same cast twice is counted once"); Same(Q.Find(500).crafts, 2)
  Same(select(2, P.OnSpellcast("party1", "Cast-3", 500)), "other", "another unit's cast is not yours"); Same(Q.Find(500).crafts, 2)
  Same(select(2, P.OnSpellcast("player", "Cast-4", 777)), "notqueued", "a spell that is not a queued recipe changes nothing")
  Same(select(2, P.OnSpellcast("player", nil, 500)), "other", "no cast identity: not counted")
  Same(Q.Find(500).crafts, 2)
  P.auto = false
  -- the last craft removes the entry; the saved queue has the change (the queue's own save)
  S.SetCrafts(500, 1)
  local ok, info = P.Credit(500)
  Check(ok and info.done and not Q.Find(500), "the last craft removes the entry")
  Same(Nt.CreditText(info), "Bar completed.")
  local saved = false
  for _, slot in pairs(c.TwichUIDB.workshop.chars or {}) do
    for _, e in ipairs(slot.queue or {}) do if e.id == 500 then saved = true end end
  end
  Check(not saved, "and the saved queue no longer has it")
  Same(select(2, P.Credit(500)), "notqueued", "nothing to count twice")
  -- Undo after the last craft brings the entry back (at the end of the queue); not if it was queued again meanwhile
  Check(S.UndoCrafted() and Q.Find(500) and Q.Find(500).crafts == 1, "the removed entry is back, one craft")
  Check(P.Credit(500) and not Q.Find(500))
  Check(S.Add((function() for _, r in ipairs(S.AllRecipes()) do if r.name == "Bar" then return r end end end)()), "queued again by the player")
  Check(not S.UndoCrafted() and Q.Find(500).crafts == 1, "Undo refuses: the recipe was queued again, nothing doubles")
  S.Remove(500)
  Same(Nt.CreditText({ name = "Sword", left = 0, done = true, planDone = true }), "Crafting plan complete.")
  Same(Nt.CreditText({ name = "Sword", left = 1, done = false }), "Sword crafted: 1 craft left.")
  Check(S.Add((function() for _, r in ipairs(S.AllRecipes()) do if r.name == "Bar" then return r end end end)()), "Bar queued again")
end

-- the compact Craft view's Done: one craft counted from the row, Undo beside the note ---------------------------------------------------------------
do
  local Cm = W.Compact
  Cm.Show("craft"); Cm.Render()
  local cf = Cm.Frame()
  local row
  for _, r in ipairs(Win.Lists().compact.rows) do if r:IsShown() and r.data and r.data.done == 500 then row = r end end
  Check(row and row.map:IsShown() and row.map.text:GetText() == "Done", "each queued recipe has Done")
  local was = Q.Find(500).crafts
  row.map:GetScript("OnClick")(row.map)
  Same(Q.Find(500) and Q.Find(500).crafts or 0, was - 1, "one craft counted")
  Check(cf.undo:IsShown(), "Undo is offered")
  cf.undo:GetScript("OnClick")(cf.undo)
  Same(Q.Find(500).crafts, was, "and taken back")
  Cm.ShowFull()
end

-- notices (Notice.lua): what became ready since the last look; nothing at the first look; gathered; not repeated -------------------------------------
do
  local Nt = W.Notice
  Same(Nt.ReadyText({ "Bar" }, false), "All materials for Bar are ready.")
  Same(Nt.ReadyText({ "Bar", "Sword" }, false), "Materials ready for 2 recipes.")
  Same(Nt.ReadyText({ "Bar" }, true), "Everything for your crafting plan is in your bags.")
  Same(Nt.ReadyText({}, true), nil, "nothing became ready: nothing to say")
  Same(Nt.Gather({ "a", "b", "c" }), "c (and 2 more)"); Same(Nt.Gather({ "x", "Crafting plan complete." }), "Crafting plan complete.")
  g.bags[30] = 20   -- already ready when the window opens (a login): remembered, never announced
  Nt.Disarm()
  Same(Nt.BagsChanged(), nil, "a recipe that is ready at the first look is not announced")
  Same(Nt.BagsChanged(), nil, "nor later, while nothing changes")
  g.bags[30] = 0
  Nt.Disarm()
  Same(Nt.BagsChanged(), nil, "the first look is only remembered (a login or a first scan says nothing)")
  Same(Nt.BagsChanged(), nil, "nothing changed")
  g.bags[30] = 20   -- now the Bars' ore is in the bags
  Same(Nt.BagsChanged(), "All materials for Bar are ready.", "a recipe that became ready is said")
  Same(Nt.BagsChanged(), nil, "and only once")
  g.bags[30] = 0
  Same(Nt.BagsChanged(), nil, "losing materials says nothing")
  -- off: nothing is gathered
  Nt.SetOn(false); Check(not Nt.On() and c.TwichUIDB.workshop.view.notices == false, "off is saved")
  Check(not Nt.Say("x"), "notices off: nothing is said")
  Nt.SetOn(true); Check(Nt.On() and c.TwichUIDB.workshop.view.notices == nil, "on is the default and is not stored")
  -- the Crafting page's switch is the same choice
  Win.SetMode("craft"); Win.Render()
  local sw = Win.Craft().notices
  Check(sw and sw.on, "the switch shows on")
  sw:GetScript("OnClick")(sw); Win.Render()
  Check(not Nt.On() and not sw.on, "and turns notices off")
  sw:GetScript("OnClick")(sw); Win.Render()
  Check(Nt.On() and sw.on, "and on again")
end

-- notices reach TwichUI's own coordinator: one card for a burst, the same words not repeated, the coordinator's refusal respected ----------------------
do
  local Nt = W.Notice
  Nt.Flush()   -- what the earlier checks gathered (their timer was a no-op here; in the game it fires)
  local real = R.Notify
  local subs, kinds = {}, {}
  local refuse = nil
  R.Notify = { Register = function(kind, spec) kinds[kind] = spec end, Finished = function() end,
    Submit = function(req) if refuse then return false, refuse end subs[#subs + 1] = req return true end }
  local pending = {}
  local saved = c.C_Timer
  c.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
  local function Run() local list = pending pending = {} for _, fn in ipairs(list) do fn() end end
  Nt.Say("Bar crafted: 2 crafts left."); Nt.Say("Bar crafted: 1 craft left."); Nt.Say("Bar completed.")
  Same(#pending, 1, "three messages wait for one card")
  Run()
  Same(#subs, 1, "one card for the burst"); Same(subs[1].kind, "workshop"); Same(subs[1].payload.text, "Bar completed. (and 2 more)")
  Check(kinds.workshop and kinds.workshop.label == "Workshop progress", "the card kind is registered with the coordinator")
  Nt.Say("Bar completed. (and 2 more)"); Run()
  Same(#subs, 1, "the same words are not shown again straight away")
  refuse = "quiet"   -- the Quiet screen switch is the coordinator's rule
  Nt.Say("All materials for Sword are ready."); Run()
  Same(#subs, 1, "a refused notice is simply not shown"); Same(Nt.Stats().refused, 1)
  c.C_Timer = saved
  R.Notify = real
end

print("PASSED test_workshop_compact")
