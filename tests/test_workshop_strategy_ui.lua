-- The strategy on the three pages and its views (P2): the compact Crafting Strategy of Opportunities beside the unchanged one-level estimate, the strip of
-- the Crafting Plan, the multilevel Shopping list and its fallback and updating states, the full strategy view and the confirmation (nothing is added
-- until it is accepted), jobs while the window is open, closed or the selection changes. Recording stand-in frames: this proves what is drawn and kept,
-- not how the game draws it (the simulator scenario and the real client do).
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

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewStrategy.lua", "Window.lua" }) do
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
Win.SetMode("opps"); Win.Render()
local opps = Win.Opps()
local OL = Win.Lists().opps
local function RowOf(list, pred) for _, r in ipairs(list.rows) do if r:IsShown() and pred(r) then return r end end end
local sword = RowOf(OL, function(r) return r.rec and r.rec.name == "Sword" end)
Check(sword, "the Sword is listed")
sword:GetScript("OnClick")(sword)
local d = opps.detail

-- Opportunities ------------------------------------------------------------------------------------------------------------------------------
Same(d.strat.status:GetText(), "Best verified plan", "a small plan is ready when the page is drawn")
Same(d.strat.headline:GetText(), "Craft 1 intermediate \194\183 Buy 1", "what to do, at a glance")
Same(d.strat.pairs[1].l:GetText(), "Estimated cost"); Same(d.strat.pairs[1].v:GetText(), Money(1000), "one planning figure: the optimized cost (exact here)")
Same(d.strat.pairs[2].l:GetText(), "Gold needed now"); Same(d.strat.pairs[2].v:GetText(), Money(700), "the cash needed now")
Check(d.strat.pairs[1].tip:find(Money(1200), 1, true), "buying the bars directly is in the cost's tooltip, not a box of its own")
Same(d.strat.save:GetText(), "Saves at least " .. Money(200), "a certain saving is said as such")
for _, p in ipairs(d.strat.pairs) do Check(not p.v:GetText():find(" to ", 1, true), "no inline range in the simple view") end
Same(d.cost:GetText(), Money(1200), "the existing one-level cost to make is unchanged and is not the optimized cost")
Check(d.view:IsEnabled(), "View strategy is available")
Check(d.chart and d.chart:IsShown() ~= nil and d.chartBox ~= nil, "the price history is still there, in a place of its own")
Check(d.facts[1] and d.mats[1], "the materials and market facts are still there")
Check(d.add:IsShown() and d.add.text:GetText() == "Add to crafting plan", "the existing Add button is unchanged")
Same(#Q.Entries(), 0, "looking changes nothing")

-- a recipe that can't be planned says so, with no figures
do
  local blank = RowOf(OL, function(r) return r.rec and r.rec.name == "Bar" end)
  blank:GetScript("OnClick")(blank)
  Same(d.strat.pairs[1].v:GetText(), Money(200), "the bar on its own: 2 ore, 100 each (3 in the bags: owned, counted at its value)")
  Same(d.strat.save:GetText(), W.Strategy.NO_SAVING, "nothing to craft on the way: buying directly is the best supported option")
  sword:GetScript("OnClick")(sword)
end

-- while a plan is computed: a quiet state, never another recipe's figures; a stale job never overwrites a newer selection
do
  local real = W.CraftPlanner.Job
  W.CraftPlanner.Job = function(inp, opt)
    local job = real(inp, opt)
    local inner, n = job.Step, 0
    job.Step = function(self, k) n = n + 1 if n < 8 then return false end return inner(self, k) end
    return job
  end
  St.Bump()
  Win.Render()
  Same(d.strat.status:GetText(), "Planning...", "planning is said, quietly")
  Check(not d.view:IsEnabled(), "and the strategy can't be opened yet")
  Check(d.strat.pairs[1].v:GetText() == "...", "no figures of another recipe")
  local bar = RowOf(OL, function(r) return r.rec and r.rec.name == "Bar" end)
  bar:GetScript("OnClick")(bar)
  Same(d.strat.status:GetText(), "Planning...", "the new selection plans its own")
  St.Pump()
  Win.Render()
  Same(d.strat.status:GetText(), "Best verified plan"); Same(d.strat.pairs[1].v:GetText(), Money(200), "the figures of the recipe shown, not of the one planned first")
  sword:GetScript("OnClick")(sword)
  St.Pump(); Win.Render()
  Same(d.strat.pairs[1].v:GetText(), Money(1000))
  W.CraftPlanner.Job = real
end

-- the full strategy and the confirmation -------------------------------------------------------------------------------------------------------
d.view:GetScript("OnClick")(d.view)
local sv, cd = W.StrategyView.Frames()
Check(sv:IsShown() and not cd:IsShown(), "the strategy view opens; the confirmation does not")
local SLst = Win.Lists().strategy
local titles = {}
for _, r in ipairs(SLst.data) do titles[#titles + 1] = (r.title or "") end
local all = table.concat(titles, "|")
Check(all:find("Craft|Craft 4 \195\151 Bar", 1, true), "the crafts first, the action as the title: " .. all)
Check(all:find("Buy from Auction House", 1, true) or all:find("Buy from vendor", 1, true), "buying says where: " .. all)
Check(not all:find("Good to know", 1, true), "the caveats are not paragraphs in the list")
Check(#sv.notes > 0 and table.concat(sv.notes, " "):find("aren't checked", 1, true), "they are behind the Notes control")
Same(sv.boxes[1].l:GetText(), "Estimated cost"); Same(sv.boxes[1].v:GetText(), Money(1000)); Same(sv.boxes[2].v:GetText(), Money(700))
Check(sv.boxes[1].tip:find(Money(1200), 1, true), "buying directly is in the tooltip")
Check(sv.boxes[3].v:GetText():find(Money(200), 1, true), "the saving")
do   -- every item row carries the item for its tooltip and the precise lines under it
  local step
  for _, r in ipairs(SLst.data) do if r.kind == "step" then step = r end end
  Check(step and step.item and step.tip and #step.tip > 0, "the craft row has an item tooltip and its numbers")
  local toggle
  for _, r in ipairs(SLst.data) do if r.kind == "toggle" then toggle = r end end
  if toggle then
    local n = #SLst.data
    Same(toggle.right, "Show"); W.StrategyView.ToggleAlternatives()
    Check(#SLst.data > n, "the other options open on demand")
    W.StrategyView.ToggleAlternatives()
    Same(#SLst.data, n, "and fold away again")
  end
  -- the presentation choice: ranges inline, everywhere, and saved
  Check(not W.Session.PriceDetail(), "Simple is the default")
  sv.detailed:GetScript("OnClick")(sv.detailed)
  Check(W.Session.PriceDetail() and W.Strategy.detailed, "Detailed is chosen")
  Same(c.TwichUIDB.workshop.view.prices, "detailed", "and saved")
  sv.detailed:GetScript("OnClick")(sv.detailed)
  Check(not W.Session.PriceDetail() and not W.Strategy.detailed and c.TwichUIDB.workshop.view.prices == nil, "and back")
end
sv.add:GetScript("OnClick")(sv.add)
Check(cd:IsShown(), "the confirmation is shown")
Same(#Q.Entries(), 0, "nothing is added by asking")
local ops = Win.Lists().confirm.data
Same(#ops, 2); Same(ops[1].name, "Bar"); Same(ops[1].crafts, 4); Same(ops[2].name, "Sword"); Check(ops[2].final)
Check(cd.text:GetText():find("2 recipes, 5 crafts", 1, true), "the confirmation says exactly what is added: " .. cd.text:GetText())
Check(not cd.plain:IsShown(), "no fallback while the optimized plan can be added")
Check(cd.ok:IsEnabled(), "it can be accepted")
cd.cancel:GetScript("OnClick")(cd.cancel)
Check(not cd:IsShown()); Same(#Q.Entries(), 0, "cancelled: nothing added")
sv.add:GetScript("OnClick")(sv.add)
-- the queue changes while the confirmation is open: the plan is checked again and the list changes with it
Check(S.Add(S.AllRecipes()[1] and (function() for _, r in ipairs(S.AllRecipes()) do if r.name == "Sword" then return r end end end)()), "the sword is queued by the player meanwhile")
Win.Render()
local ops2 = Win.Lists().confirm.data
Same(#ops2, 1, "now only the bars are missing"); Same(ops2[1].name, "Bar")
cd.ok:GetScript("OnClick")(cd.ok)
Same(#Q.Entries(), 2); Same(Q.Find(500).crafts, 4); Same(Q.Find(1).crafts, 1, "nothing counted twice")
Check(not cd:IsShown())
-- a stale key is refused even if the button were pressed
do
  local ok = S.ApplyOptimized("not the key of this plan", nil)
  Check(not ok, "an old key adds nothing"); Same(#Q.Entries(), 2)
end
sv:Hide()

-- the Crafting Plan -------------------------------------------------------------------------------------------------------------------------------
Win.SetMode("craft"); Win.Render()
local craft = Win.Craft()
Check(craft.strat.line1:GetText():find("Best verified plan", 1, true), craft.strat.line1:GetText())
Check(craft.strat.line1:GetText():find("Buy 1", 1, true) and not craft.strat.line1:GetText():find("Craft", 1, true), "the queue makes the bars itself: nothing more to craft: " .. craft.strat.line1:GetText())
Check(craft.strat.line2:GetText():find("Estimated cost", 1, true) and craft.strat.line2:GetText():find("Gold needed now", 1, true), craft.strat.line2:GetText())
craft.strat.view:GetScript("OnClick")(craft.strat.view)
Check(sv:IsShown(), "the strip opens the strategy of the whole queue"); sv:Hide()
-- every material row shows a note exactly when the plan gave one
local noted = 0
for _, mr in ipairs(Win.Lists().mats.rows) do
  if mr:IsShown() then
    Check(mr.note:IsShown() == (mr.row.note ~= nil))
    if mr.row.note then noted = noted + 1 end
  end
end
Check(noted >= 1, "the plan says how a material is got")

-- Shopping ---------------------------------------------------------------------------------------------------------------------------------------
Win.SetMode("shop"); Win.Render()
local shop = Win.Shop()
Check(shop.notes:GetText():find("Best verified plan", 1, true) and shop.notes:GetText():find("estimated cost", 1, true), shop.notes:GetText())
Check(shop.view:IsEnabled(), "View strategy on the Shopping page")
local SL = Win.Lists().shop
Same(#SL.data, 1, "only the ore is left to buy"); Same(SL.data[1].item, 30); Same(SL.data[1].multilevel, true)
Same(shop.total:GetText(), "Estimated spending: " .. Money(700))
-- the planner fails: the old list is shown and says so, never as the multilevel plan
do
  local real = W.CraftPlanner.Job
  W.CraftPlanner.Job = function() error("boom") end
  St.Bump(); Win.Render()
  Check(shop.notes:GetText():find("Basic list", 1, true), shop.notes:GetText())
  Check(not shop.notes:GetText():find("Best verified plan", 1, true), "a fallback never claims the multilevel plan")
  Check(not shop.view:IsEnabled(), "and offers no strategy")
  W.CraftPlanner.Job = real
  St.Bump(); Win.Render()
  Check(shop.notes:GetText():find("Best verified plan", 1, true))
end
-- while a new plan runs: the last list stays, said to be updating
do
  local real = W.CraftPlanner.Job
  W.CraftPlanner.Job = function(inp, opt)
    local job = real(inp, opt)
    local inner, n = job.Step, 0
    job.Step = function(self, k) n = n + 1 if n < 8 then return false end return inner(self, k) end
    return job
  end
  S.Change(1, 1); Win.Render()
  Same(shop.total:GetText(), "Updating the plan...", "the list shown is not claimed to be the plan of the new queue")
  St.Pump(); Win.Render()
  Check(shop.total:GetText():find("Estimated spending", 1, true))
  W.CraftPlanner.Job = real
end

-- closing the window drops every job and every kept plan
do
  local real = W.CraftPlanner.Job
  W.CraftPlanner.Job = function(inp, opt)
    local job = real(inp, opt)
    local inner = job.Step
    job.Step = function(self, k) return false end
    return job
  end
  S.Change(1, 1); Win.Render()
  Check(St.Stats().running >= 1, "a plan is running")
  f:Hide()
  Same(St.Stats().running, 0, "the window closed: nothing runs"); Same(St.Pump(), 0)
  W.CraftPlanner.Job = real
end
print("PASSED test_workshop_strategy_ui")
