-- The Workshop window (TwichUI_Workshop/Window.lua) on recording stand-in frames: it is built on first show, listens to events
-- only while shown, forgets what it read when hidden, shows an instruction (not an empty list) with no profession open, draws the
-- recipes, queue and materials, and its buttons queue, change and remove. Synthetic: it proves what is drawn and kept, not how
-- the game draws it.
dofile(TESTS .. "mi_mock.lua")

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
      fr.EnableMouse = function() end
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
      if name then cl[name] = fr end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    cl.UISpecialFrames = {}
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
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

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Session.lua", "AuctionButton.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
Check(W.ready and W.Open and W.Toggle, "the window file marks the addon ready")
local Win, S, Q = W.Window, W.Session, W.Queue

local function Fire(e, ...) local w = R.Workshop.Window.Frame(); if w.events[e] and w.scripts.OnEvent then w.scripts.OnEvent(w, e, ...) end end
local function Events(f) local n = 0 for _ in pairs(f.events) do n = n + 1 end return n end

-- with no profession open: an instruction, no events yet, no frame built until asked
Check(Win.Frame() == nil, "nothing is built until the window is asked for")
Same(W.Snapshot().built, false)
g.filtered = nil
Win.Show()
local f = Win.Frame()
Check(f and f:IsShown(), "shown")
Check(#f.points >= 1, "the window is anchored: an unanchored frame is shown but never drawn (the in-game failure)")
Check(f.points[1][1] == "CENTER", "centered on the screen")
Check(Events(f) > 0, "listens while shown"); Same(W.Snapshot().events, Events(f))
Check(S.Notices()[1]:find("Open one of your professions", 1, true), "an instruction, not an unexplained empty list")
Same(#Win.Lists().recipes.data, 0)
Check(Win.Lists().recipes.empty:GetText() == "No recipes yet.", "and the list says why it is empty")
Check(Win.Lists().mats.empty:GetText():find("Materials for the queue", 1, true))
Check(tContains == nil or true)
local escape = false
for _, n in ipairs(c.UISpecialFrames) do if n == "TwichUIWorkshop" then escape = true end end
Check(escape, "Esc closes it (UISpecialFrames, never the game menu's handler list)")

-- hiding drops every listener
f:Hide()
Same(Events(f), 0, "hidden: no events"); Same(W.Snapshot().events, 0)

-- a profession window of the player's own: recipes appear on show, with rows
g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 } }
g.schem[1] = { quantityMin = 1, quantityMax = 2, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 2, required = true } } }
g.schem[2] = { quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 1, required = true }, { reagentType = 1, reagents = { { itemID = 11 } }, quantityRequired = 1, required = true } } }
g.filtered = { 1, 2 }
f:Show()
Same(#Win.Lists().recipes.data, 2)
local rows = Win.Lists().recipes.rows
Check(#rows >= 2 and rows[1]:IsShown(), "recipe rows are made for what is shown")
Check(rows[1].name:GetText() == "Healing Potion" and rows[1].diff:GetText() == "Yellow", "the name and the difficulty in words")
Check(rows[1].sub:GetText() == "Makes 1-2", rows[1].sub:GetText())
Check(rows[2].diff:GetText() == "Orange")

-- queue it with the row's own button, then change and remove
rows[1].add:GetScript("OnClick")(rows[1].add)
Same(#Q.Entries(), 1); Same(Q.Entries()[1].name, "Healing Potion")
Check(rows[1].add.text:GetText() == "Queued" and rows[1].add.enabled == false, "a queued recipe says Queued and can't be added twice")
local qrow = Win.Lists().queue.rows[1]
Check(qrow:IsShown() and qrow.name:GetText():find("Healing Potion", 1, true) and qrow.name:GetText():find("Alchemy", 1, true))
Check(qrow.line:GetText() == "1 craft - makes 1-2", qrow.line:GetText())
Check(not qrow.stale:IsShown(), "known materials: no update line")
qrow.more:GetScript("OnClick")(qrow.more); qrow.more:GetScript("OnClick")(qrow.more)
Same(Q.Entries()[1].crafts, 3)
Check(qrow.line:GetText() == "3 crafts - makes 1-2 each, 3-6 in all", qrow.line:GetText())
Same(qrow.count:GetText(), "3")
c.IsShiftKeyDown = function() return true end
qrow.less:GetScript("OnClick")(qrow.less)
Same(Q.Entries()[1].crafts, 1, "Shift changes by five but never below one")
c.IsShiftKeyDown = function() return false end

-- materials against the bags (bags only), with the words
g.bags = { [10] = 1 }
qrow.more:GetScript("OnClick")(qrow.more)   -- 2 crafts: 4 Peacebloom
Win.Render()
local mrow = Win.Lists().mats.rows[1]
Check(mrow:IsShown() and mrow.name:GetText() == "Peacebloom" and mrow.need:GetText() == "4" and mrow.have:GetText() == "1" and mrow.short:GetText() == "3", "need, in bags, still needed")
Same(R.Workshop.Window.Frame().headline:GetText(), "Still needed: 1 material.")
g.bags = {}
Win.Render()
Check(Win.Lists().mats.rows[1].have:GetText() == "Unknown" and Win.Lists().mats.rows[1].short:GetText() == "Unknown", "an unreadable bag count is Unknown, never 0")
g.bags = { [10] = 4 }
Win.Render()
Same(f.headline:GetText(), "All the materials are in your bags.")

-- open recipe, remove
qrow.open:GetScript("OnClick")(qrow.open)
Same(g.opened[#g.opened], 1)
Check(qrow.open.text:GetText() == "Open recipe")
qrow.remove:GetScript("OnClick")(qrow.remove)
Same(#Q.Entries(), 0); Check(f.note:GetText():find("Removed", 1, true))

-- events: a burst of changes is one redraw, a stale one is dropped, hidden stops everything
rows[2].add:GetScript("OnClick")(rows[2].add)
local before = W.Snapshot().renders
Fire("BAG_UPDATE_DELAYED"); Fire("BAG_UPDATE_DELAYED"); Fire("GET_ITEM_INFO_RECEIVED")
Same(W.Snapshot().renders, before, "nothing is drawn until the burst settles")
FlushTimers()
Same(W.Snapshot().renders, before + 1, "one redraw for the burst")
Fire("BAG_UPDATE_DELAYED")
f:Hide()
FlushTimers()
Same(W.Snapshot().renders, before + 1, "a redraw scheduled before hiding is dropped")
Same(W.Snapshot().recipes, 0, "the recipe lists are forgotten when hidden")
Same(W.Snapshot().queue, 1, "the queue is not")
-- reopening reads fresh (bags changed while it was hidden)
g.bags = {}
f:Show()
Check(Win.Lists().mats.rows[1].have:GetText() == "Unknown", "reopened: drawn from a fresh read, never from before it was closed")
-- profession window events re-read
g.filtered = { 1 }
Fire("TRADE_SKILL_LIST_UPDATE")
FlushTimers()
Same(#Win.Lists().recipes.data, 1, "the profession window's changes are followed while shown")

-- the profession being someone else's
g.prof = { professionID = 164, professionName = "Blacksmithing" }
c.C_TradeSkillUI.IsTradeSkillLinked = function() return true end
Fire("TRADE_SKILL_SHOW"); FlushTimers()
Check(f.notice:GetText():find("isn't one of your own", 1, true), "said, with the earlier list kept")
Same(#S.Professions(), 1, "a linked profession is not added")
f:Hide()

---------------------------------------------------------------------------
-- Opportunities: the second view, the scan button, rows, sorting, the queue
---------------------------------------------------------------------------
do
  -- a virtual clock for the scan's waits, and a fake auction house
  local clock, timers = 0, {}
  c.GetTime = function() return clock end
  c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end }
  local function Advance(sec)
    local target = clock + sec
    while true do
      local best, bi
      for i, t in ipairs(timers) do if t.at <= target and (not best or t.at < best.at) then best, bi = t, i end end
      if not best then break end
      table.remove(timers, bi)
      if best.at > clock then clock = best.at end
      best.fn()
    end
    clock = target
  end
  local made = {}
  local baseCreate = c.CreateFrame
  c.CreateFrame = function(...) local fr = baseCreate(...); made[#made + 1] = fr; return fr end
  local function FireScan(event)
    for _, fr in ipairs(made) do if fr.events[event] and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, event) end end
  end
  local ah = { sent = 0, records = {} }
  c.C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    ReplicateItems = function() ah.sent = ah.sent + 1 end,
    GetNumReplicateItems = function() return #ah.records end,
    GetReplicateItemInfo = function(i) local r = ah.records[i + 1]; if not r then return end; return "n", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "o", "o", 0, r.item, true end,
  }
  c.AuctionHouseFrame = MIFake("Frame"); c.AuctionHouseFrame:Hide()
  Same(W.AuctionButton.Attached(), false, "no button before the auction house window exists")
  W.AuctionButton.Start()   -- (the real one is told by ADDON_LOADED / AUCTION_HOUSE_SHOW)
  Check(W.AuctionButton.Attached() and W.AuctionButton.Button(), "the Scan prices button is made on the auction house window")
  c.UnitFactionGroup = function() return "Alliance" end
  c.GetRealmName = function() return "Realm" end
  c.GetMoneyString = function(n) return n .. "c" end
  local tip = {}
  c.GameTooltip = MIFake("GameTooltip")
  c.GameTooltip.AddLine = function(_, text) tip[#tip + 1] = text end
  c.GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. " | " .. b end

  -- the recipes: Healing Potion makes 1-2 of item 501 from 2 x 10; Mana Potion makes 1 of 502 from 10 + 11
  g.prof = { professionID = 171, professionName = "Alchemy" }
  c.C_TradeSkillUI.IsTradeSkillLinked = function() return false end
  g.schem[1].outputItemID = 501
  g.schem[2].outputItemID = 502
  g.filtered = { 1, 2 }
  f:Show()
  Same(Win.Mode(), "craft", "it opens on Crafting")
  local opps = Win.Opps()
  Check(not opps:IsShown() and f.tabCraft.on ~= false)
  f.tabOpps:GetScript("OnClick")(f.tabOpps)
  Same(Win.Mode(), "opps"); Check(opps:IsShown(), "the Opportunities view is shown")
  Same(W.Snapshot().mode, "opps")
  FlushTimers(); Advance(1)
  local L_ = Win.Lists().opps
  -- no scan yet
  Check(L_.empty:GetText():find("No prices saved yet", 1, true), L_.empty:GetText())
  Check(opps.source:GetText():find("No saved prices for this realm", 1, true))
  Same(#L_.data, 2, "the list still has the rows: unknown ones are shown as unknown")
  Check(L_.rows[1].profit.a:GetText() == "Unknown" and L_.rows[1].cost.a:GetText() == "Unknown", "no scan: Unknown, never 0")

  -- scanning with the auction house closed says so and sends nothing
  opps.scan:GetScript("OnClick")(opps.scan)
  Check(opps.status:GetText():find("Open the auction house", 1, true), opps.status:GetText()); Same(ah.sent, 0)

  -- the auction house opens: Scan prices
  c.AuctionHouseFrame:Show()
  ah.records = {
    { item = 10, count = 1, buyout = 100 }, { item = 10, count = 4, buyout = 600 },   -- 100 and 150 each
    { item = 11, count = 1, buyout = 50 },
    { item = 501, count = 1, buyout = 1000 }, { item = 501, count = 2, buyout = 3000 },
    { item = 502, count = 1, buyout = 300 },
    { item = 502, count = 1, buyout = 0 },    -- bid only
    { item = 999, count = 1, buyout = 1 },    -- nothing to do with these recipes
  }
  local AB = W.AuctionButton
  local ahBtn, ahBar = AB.Button(), AB.Bar()
  Check(not ahBar:IsShown(), "no bar while nothing runs")
  opps.scan:GetScript("OnClick")(opps.scan)
  Same(ah.sent, 1, "one click, one request"); Same(opps.scan.text:GetText(), "Scanning..."); Check(opps.scan.enabled == false, "can't be pressed again meanwhile")
  opps.scan:GetScript("OnClick")(opps.scan)
  Same(ah.sent, 1, "a repeated click does nothing")
  Check(opps.status:GetText():find("Asking the auction house", 1, true))
  -- the overall progress bar, in the view and on the auction house window, and the auction house button follows the same scan
  FlushTimers()
  Check(opps.bar:IsShown() and ahBar:IsShown(), "a bar in both places while scanning")
  Check(opps.bar.text:GetText():find("Asking the auction house for its listings 3%", 1, true), opps.bar.text:GetText())
  Same(ahBtn.text:GetText(), "Scanning..."); Check(ahBtn.enabled == false, "the auction house button can't start a second scan")
  ahBtn:GetScript("OnClick")(ahBtn); Same(ah.sent, 1, "and a click on it does nothing meanwhile")
  FireScan("REPLICATE_ITEM_LIST_UPDATE")
  Same(W.Scan.phase, "settling"); Same(W.Scan.Progress(), 0.08, "listings are arriving: past the asking")
  Advance(7)
  Same(W.Scan.state, "done")
  Check(not ahBar:IsShown() and not opps.bar:IsShown(), "the bars go when the scan ends")
  Check(AB.Status():IsShown() and AB.Status():GetText():find("Prices found for 4 of your items", 1, true), "the auction house window says how it went")
  Same(ahBtn.text:GetText(), "Scan prices"); Check(ahBtn.enabled)
  Same(opps.scan.text:GetText(), "Scan prices"); Check(opps.scan.enabled)
  Check(opps.status:GetText():find("Prices found for 4 of your items", 1, true), opps.status:GetText())
  Check(opps.source:GetText():find("Alliance auction house on Realm, scanned just now", 1, true), opps.source:GetText())
  Same(#L_.data, 2)
  local r1, r2 = L_.rows[1], L_.rows[2]
  Same(r1.name:GetText(), "Healing Potion", "highest estimated profit first")
  Same(r1.cost.a:GetText(), "200c", "2 x 100: the materials in full")
  Same(r1.sell.a:GetText(), "1000c"); Same(r1.sell.b:GetText(), "to 2000c", "makes 1-2: a range, not the maximum")
  Same(r1.profit.a:GetText(), "800c"); Same(r1.profit.b:GetText(), "to 1800c")
  Check(r1.sub:GetText():find("Makes 1-2", 1, true) and r1.sub:GetText():find("Alchemy", 1, true), r1.sub:GetText())
  Same(r2.name:GetText(), "Mana Potion")
  Same(r2.cost.a:GetText(), "150c"); Same(r2.sell.a:GetText(), "300c"); Same(r2.profit.a:GetText(), "150c"); Check(not r2.profit.b:IsShown() and not r2.sell.b:IsShown(), "a single amount has no second line")
  Check(opps.summary:GetText():find("2 of 2 recipes priced, 2 profitable", 1, true), opps.summary:GetText())
  Check(opps.notes:GetText():find("cut isn't taken off", 1, true), "the unconfirmed cut is stated")
  Check(opps.notes:GetText():find("doesn't mean it will sell", 1, true), "a listing is not a sale")
  Check(opps.notes:GetText():find("Deposits", 1, true), "deposits are said to be left out")
  -- the basis on demand
  tip = {}
  r1:GetScript("OnEnter")(r1)
  local all = table.concat(tip, "\n")
  Check(all:find("Healing Potion", 1, true) and all:find("2 x Peacebloom | 100c each = 200c", 1, true), all)
  Check(all:find("Estimated profit | 800c to 1800c", 1, true), all)
  Check(all:find("scanned just now", 1, true))

  -- sorting by a column; unknown stays below
  local heads = Win.Heads()
  heads.cost:GetScript("OnClick")(heads.cost)
  Same(S.opp.sort, "cost"); Same(L_.rows[1].name:GetText(), "Mana Potion", "cheapest to make first"); Same(S.opp.desc, false)
  heads.cost:GetScript("OnClick")(heads.cost); Same(L_.rows[1].name:GetText(), "Healing Potion", "the same column again reverses it")
  heads.profit:GetScript("OnClick")(heads.profit)
  Same(S.opp.sort, "profit"); Same(L_.rows[1].name:GetText(), "Healing Potion")

  -- add to the existing queue (the same queue the Crafting view uses)
  local queued = #Q.Entries()
  local add1 = L_.rows[1].add
  Check(add1.text:GetText() == "Add" and add1.enabled)
  add1:GetScript("OnClick")(add1)
  Same(#Q.Entries(), queued + 1); Check(Q.Find(1), "Healing Potion is in the one queue")
  Same(L_.rows[1].add.text:GetText(), "Queued"); Check(L_.rows[1].add.enabled == false)
  Check(f.note:GetText():find("Added Healing Potion", 1, true))
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  Same(Win.Mode(), "craft"); Check(not opps:IsShown())
  Same(#Win.Lists().queue.data, #Q.Entries(), "and the Crafting view shows it")
  f.tabOpps:GetScript("OnClick")(f.tabOpps)

  -- a material with no price: the whole estimate is unknown, and below the known ones
  ah.records = {
    { item = 10, count = 2, buyout = 200 }, { item = 501, count = 1, buyout = 1000 }, { item = 502, count = 1, buyout = 300 },
  }
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE"); Advance(5)
  Same(W.Scan.state, "done")
  Same(L_.rows[1].name:GetText(), "Healing Potion")
  Same(L_.rows[2].name:GetText(), "Mana Potion")
  Same(L_.rows[2].profit.a:GetText(), "Unknown", "unknown, not zero"); Same(L_.rows[2].cost.a:GetText(), "Unknown")
  Same(L_.rows[2].sell.a:GetText(), "300c", "what is known is still shown")
  Same(L_.rows[2].sub:GetText(), "1 material has no price")
  Check(opps.summary:GetText():find("1 of 2 recipes priced", 1, true), opps.summary:GetText())

  -- a scan that fails keeps the usable one
  local before = W.Prices.Market("Realm|Alliance").at
  clock = clock + 400
  opps.scan:GetScript("OnClick")(opps.scan)
  Advance(100)
  Same(W.Scan.state, "failed")
  Check(opps.status:GetText():find("earlier prices were kept", 1, true), opps.status:GetText())
  Same(W.Prices.Market("Realm|Alliance").at, before, "the earlier scan is untouched")
  Same(L_.rows[1].name:GetText(), "Healing Potion"); Same(L_.rows[1].cost.a:GetText(), "200c", "and the list still uses it")
  Check(opps.source:GetText():find("scanned", 1, true))

  -- Profitable only
  opps.profitOnly:GetScript("OnClick")(opps.profitOnly)
  Same(#L_.data, 1, "only Healing Potion is both priced and profitable"); Same(L_.rows[1].name:GetText(), "Healing Potion")
  ah.records = { { item = 10, count = 2, buyout = 200 }, { item = 11, count = 1, buyout = 50 }, { item = 501, count = 1, buyout = 10 }, { item = 502, count = 1, buyout = 10 } }
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE"); Advance(5)
  Same(#L_.data, 0); Check(L_.empty:GetText():find("No profitable crafts", 1, true), L_.empty:GetText())
  opps.profitOnly:GetScript("OnClick")(opps.profitOnly)
  Same(#L_.data, 2, "off: they are all shown, losses included")
  Check(L_.rows[1].profit.a:GetText():sub(1, 1) == "-", "a loss shows its minus sign")

  -- prices exist but none of these recipes could be priced
  ah.records = { { item = 999, count = 1, buyout = 5 } }
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE"); Advance(5)
  Same(W.Scan.state, "done")
  Check(Win.Lists().opps.empty:IsShown() == false, "the rows are still listed (as unknown)")
  Check(L_.rows[1].profit.a:GetText() == "Unknown")
  Check(opps.summary:GetText():find("0 of 2 recipes priced", 1, true))
  Check(S.Opportunities().state == "noprices")

  -- closing the auction house mid-scan, then the window: nothing is left running
  ah.records = {}
  for i = 1, 900 do ah.records[i] = { item = 10, count = 1, buyout = 100 + i } end
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE")
  FireScan("AUCTION_HOUSE_CLOSED")
  Same(W.Scan.state, "interrupted")
  c.AuctionHouseFrame:Hide()
  f:Hide()
  Same(Events(f), 0, "hidden: no events"); Same(W.Snapshot().events, 0)
  Advance(200)
  Same(W.Scan.state, "interrupted", "nothing changes afterwards")
  -- the Opportunities view was left on; the window reopens on it and starts fresh
  f:Show()
  Same(Win.Mode(), "opps")
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  f:Hide()
end


---------------------------------------------------------------------------
-- The Shopping view: one row per missing material, a source, spending, and the actions (a fake vendor list and prices)
---------------------------------------------------------------------------
do
  c.GetMoneyString = function(n) return n .. "c" end
  g.names[12] = "Seed"
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [3] = { name = "Peacebloom Bundle", diff = 1 } }
  g.schem = {
    [1] = { quantityMin = 1, quantityMax = 1, outputItemID = 501, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 2, required = true } } },
    [3] = { quantityMin = 1, quantityMax = 1, outputItemID = 10, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 12 } }, quantityRequired = 1, required = true } } },
  }
  g.filtered = { 1, 3 }
  g.bags = { [10] = 0, [12] = 0 }
  c.TwichUIDB.workshop.prices = { v = 1, markets = { ["Realm|Alliance"] = { realm = "Realm", side = "Alliance", at = os.time() - 90000, complete = true, read = 1, used = 1, n = 2,
    items = { [10] = { 100, 9, 9, 9 }, [12] = { 10, 9, 9, 9 } } } } }
  f:Show()
  Check(S.Add(S.AllRecipes()[1]), "queued the potion")
  f.tabShop:GetScript("OnClick")(f.tabShop)
  Same(Win.Mode(), "shop"); local shop = Win.Shop(); Check(shop:IsShown() and not Win.Opps():IsShown(), "the Shopping view is shown")
  Check(f.events["MERCHANT_SHOW"] and f.events["MERCHANT_UPDATE"], "a merchant window is listened for while the window is shown")
  local SL = Win.Lists().shop
  Same(#SL.data, 2, "Peacebloom is short, and making it from Seed is cheaper than buying it, so Seed is bought")
  local function RowOf(item) for _, r in ipairs(SL.rows) do if r:IsShown() and r.item == item then return r end end end
  local make, seed = RowOf(10), RowOf(12)
  Check(make and seed, "both rows are drawn")
  Same(make.name:GetText(), "Peacebloom"); Same(make.need:GetText(), "2")
  Same(make.source.text:GetText(), "Make"); Check(make.detail:GetText():find("Make 2 x Peacebloom Bundle", 1, true), make.detail:GetText())
  Check(make.detail:GetText():find("Making this looks cheaper than buying at the auction house", 1, true), make.detail:GetText())
  Same(make.act.text:GetText(), "Add to queue"); Check(make.act:IsShown())
  Same(seed.name:GetText(), "Seed"); Same(seed.need:GetText(), "2"); Same(seed.spend.a:GetText(), "20c", "2 seeds at 10 each")
  Check(seed.detail:GetText():find("Needed to make Peacebloom Bundle", 1, true), seed.detail:GetText())
  Check(seed.spend.b:GetText():find("1 day ago", 1, true), "the price age is shown: " .. seed.spend.b:GetText())
  Check(not seed.act:IsShown(), "no action where none fits")
  Check(shop.total:GetText():find("Estimated spending: 20c", 1, true), shop.total:GetText())
  Check(shop.source:GetText():find("scanned 1 day ago", 1, true), shop.source:GetText())
  -- the basis tooltip says what is owned and what is not
  tip = nil
  local lines = {}
  c.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
  c.GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " | " .. b end
  make:GetScript("OnEnter")(make)
  local all = table.concat(lines, "\n")
  Check(all:find("Make | worth 20c", 1, true) and all:find("Cooldowns, tools and crafting stations aren't checked", 1, true), all)
  -- adding the made material to the queue: explicit, once; nothing is counted twice
  make.act:GetScript("OnClick")(make.act)
  Same(#Q.Entries(), 2, "the bundle is queued"); Same(Q.Find(3).crafts, 2)
  Same(#SL.data, 1, "Peacebloom is now made by the queue: one row left"); Same(SL.rows[1].item, 12)
  Same(SL.rows[1].need:GetText(), "2", "the seeds are counted once")
  Check(f.note:GetText():find("Queued 2 crafts of Peacebloom Bundle", 1, true), f.note:GetText())
  -- the Crafting view's Materials agree: the bundle's output is not "still needed"
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  local mrow
  for _, r in ipairs(Win.Lists().mats.rows) do if r:IsShown() and r.item == 10 then mrow = r end end
  Check(mrow and mrow.made == 2 and mrow.short:GetText() == "0", "the Materials list counts what the queue will make")
  f.tabShop:GetScript("OnClick")(f.tabShop)
  -- a bag update recalculates
  g.bags[12] = 5
  Fire("BAG_UPDATE_DELAYED"); Win.Render()
  Same(#SL.data, 0, "the seeds are in the bags: nothing to buy"); Check(SL.empty:GetText():find("Nothing to buy", 1, true), SL.empty:GetText())
  g.bags[12] = 0
  -- the source button changes the choice
  Win.Render()
  local sr = SL.rows[1]
  sr.source:GetScript("OnClick")(sr.source)
  Check(S.picks[12] == "auction" and SL.rows[1].source.text:GetText() == "Auction house", "the player's choice")
  sr.source:GetScript("OnClick")(sr.source)
  Check(S.picks[12] == nil, "and back to the suggestion")

  -- a vendor: the price is noted from the merchant window, and Show vendor needs a place the NPC list knows
  local pending = {}
  c.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
  f:Hide(); f:Show()   -- (a fresh start for the redraw flag)
  Check(W.Vendor.Entry(12) == nil, "no vendor price yet")
  c.GetMerchantNumItems = function() return 1 end
  c.GetMerchantItemID = function() return 12 end
  c.GetMerchantItemCostInfo = function() return 0 end
  c.C_MerchantFrame = { GetItemInfo = function() return { price = 4, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = false } end }
  c.UnitGUID = function() return "Creature-0-1-2-3-4567-0000" end
  pending = {}
  Fire("MERCHANT_SHOW")
  Check(#pending >= 1, "the event schedules one settled redraw")
  Fire("MERCHANT_UPDATE"); Same(#pending, 1, "a burst of merchant events is one redraw")
  for _, fn in ipairs(pending) do fn() end
  Check(W.Vendor.Entry(12) ~= nil, "the merchant window was read when the event settled")
  Same(W.Vendor.Entry(12).p, 4); Same(W.Vendor.Entry(12).npc, 4567)
  sr = SL.rows[1]
  Same(sr.source.text:GetText(), "Vendor", "4 each at the vendor against 10 at the auction house"); Same(sr.spend.a:GetText(), "8c")
  Check(not sr.act:IsShown(), "no place is known for the vendor, so no Show vendor")
  local located
  R.NpcStore = { Entries = function() return { { id = 4567, n = "Mira", m = 1, x = 5000, y = 5000, s = { 12 }, own = true } } end,
    ValidMap = function() return true end, Usable = function() return true end, MyFaction = function() return nil end, COORD = 10000 }
  R.NpcMap = { Locate = function(e) located = e; return true end }
  local enabled = R.Enabled
  R.Enabled = function(_, key) if key == "npcMap" then return true end return enabled(R, key) end
  Win.Render()
  sr = SL.rows[1]
  Check(sr.act:IsShown() and sr.act.text:GetText() == "Show vendor", "a seen place: Show vendor")
  sr.act:GetScript("OnClick")(sr.act)
  Check(located and located.n == "Mira", "the map is asked to show that vendor, nothing else")
  Check(f.note:GetText():find("Showing Mira on the map", 1, true), f.note:GetText())
  R.Enabled = enabled; R.NpcStore, R.NpcMap = nil, nil

  -- a material with no price: a known subtotal and a clear message, never a complete-looking total
  Q.Remove(3)
  g.bags[10] = 0
  c.TwichUIDB.workshop.prices.markets["Realm|Alliance"].items[12] = nil
  c.TwichUIDB.workshop.vendor = nil
  Win.Render()
  Same(#SL.data, 1); Same(SL.rows[1].name:GetText(), "Peacebloom"); Same(SL.rows[1].spend.a:GetText(), "200c")
  Check(shop.total:GetText():find("Estimated spending: 200c", 1, true) and not shop.total:GetText():find("missing", 1, true), shop.total:GetText())
  c.TwichUIDB.workshop.prices.markets["Realm|Alliance"].items[10] = nil
  Win.Render()
  Same(SL.rows[1].spend.a:GetText(), "Unknown", "unknown cost is not zero")
  Check(shop.total:GetText():find("Some prices missing", 1, true), shop.total:GetText())

  f:Hide()
  Same(Events(f), 0, "hidden: no events")
  Same(W.Snapshot().events, 0)
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
end

print("PASSED")
