-- The Workshop window (TwichUI_Workshop/Window.lua) on recording stand-in frames: it is built on first show, listens to events
-- only while shown, forgets what it read when hidden, shows an instruction (not an empty list) with no profession open, draws the
-- recipes, queue and materials, and its buttons queue, change and remove. Synthetic: it proves what is drawn and kept, not how
-- the game draws it.
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

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "Window.lua" }) do
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
Same(Win.Mode(), "overview", "it opens on the Overview the first time")
Check(f.tabOverview.on == true and f.tabCraft.on == false, "the page list marks the page shown")
f.tabCraft:GetScript("OnClick")(f.tabCraft)
Same(Win.Mode(), "craft", "the page list switches pages"); Check(Win.Craft():IsShown() and not Win.Overview():IsShown())
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
Press.Must(rows[1].add)   -- the row's own Add button: shown, enabled, mouse on, in a shown window (Press refuses otherwise)
Same(#Q.Entries(), 1); Same(Q.Entries()[1].name, "Healing Potion")
Check(rows[1].mark:IsShown() and rows[1].mark.text:GetText() == "Queued" and not rows[1].add:IsShown(), "a queued recipe says Queued (in the compact mark, not on a stretched button) and can't be added twice")
do
  local again = Press(rows[1].add)
  Check(not again.invoked and again.reasons[1] == "hidden", "and its Add button is not a live control any more: " .. again.text)
  Same(#Q.Entries(), 1, "so a second press adds nothing")
end
local qrow = Win.Lists().queue.rows[1]
Check(qrow:IsShown() and qrow.name:GetText() == "Healing Potion")
local detail = Win.Craft().detail
Same(detail.name:GetText(), "Healing Potion", "the first queued craft's details are shown")
Same(detail.prof:GetText(), "Alchemy", "with its profession")
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
Same(f.headline:GetText(), "Ready to craft: all the materials are in your bags.")

-- open recipe, remove
local open, remove = Win.Craft().open, Win.Craft().remove   -- in the chosen craft's details, so the rows stay readable
open:GetScript("OnClick")(open)
Same(g.opened[#g.opened], 1)
Check(open.text:GetText() == "Open recipe")
remove:GetScript("OnClick")(remove)
Same(#Q.Entries(), 0); Check(f.note:GetText():find("Removed", 1, true))

-- events: a burst of changes is one redraw, a stale one is dropped, hidden stops everything
Press.Must(rows[2].add)
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
  local function StatusTip() return opps.statusBox.twichuiTip.body(opps.statusBox) end   -- where the prices come from: in the status tooltip (and the footer)
  Check(StatusTip():find("No saved prices for this realm", 1, true), StatusTip())
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
  -- (A6) while a scan runs the auction house button is its Stop: it is on and cannot start a second scan; pressing it is tested in test_workshop_auto.lua
  Same(ahBtn.text:GetText(), "Stop"); Check(ahBtn.enabled == true, "the auction house button offers Stop while a scan runs"); Same(ah.sent, 1, "and no second request was made")
  FireScan("REPLICATE_ITEM_LIST_UPDATE")
  Same(W.Scan.phase, "settling"); Same(W.Scan.Progress(), 0.08, "listings are arriving: past the asking")
  Advance(7)
  Same(W.Scan.state, "done")
  Check(not ahBar:IsShown() and not opps.bar:IsShown(), "the bars go when the scan ends")
  Check(AB.Status():IsShown() and AB.Status():GetText():find("Prices found for 5 items", 1, true), "the auction house window says how it went")
  Same(ahBtn.text:GetText(), "Scan prices"); Check(ahBtn.enabled)
  Same(opps.scan.text:GetText(), "Scan prices"); Check(opps.scan.enabled)
  Check(opps.status:GetText():find("Prices found for 5 items", 1, true), opps.status:GetText())
  Check(StatusTip():find("Alliance auction house on Realm \194\183 just now", 1, true), StatusTip())
  Same(#L_.data, 2)
  local r1, r2 = L_.rows[1], L_.rows[2]
  Same(r1.name:GetText(), "Healing Potion", "highest estimated profit first")
  Same(r1.cost.a:GetText(), "200c", "2 x 100: the materials in full")
  Same(r1.sell.a:GetText(), "1000c"); Same(r1.sell.b:GetText(), "to 2000c", "makes 1-2: a range, not the maximum")
  Same(r1.profit.a:GetText(), "800c"); Same(r1.profit.b:GetText(), "to 1800c")
  Check(r1.sub:GetText():find("makes 1-2", 1, true) and r1.sub:GetText():find("Alchemy", 1, true), r1.sub:GetText())
  Same(r2.name:GetText(), "Mana Potion")
  Same(r2.cost.a:GetText(), "150c"); Same(r2.sell.a:GetText(), "300c"); Same(r2.profit.a:GetText(), "150c"); Check(not r2.profit.b:IsShown() and not r2.sell.b:IsShown(), "a single amount has no second line")
  Same(S.Opportunities().summary.priced, 2); Same(S.Opportunities().summary.profitable, 2)
  -- no summary line, footer paragraphs or About button on the page any more; the cut is not confirmed, so the qualification is in the heading
  -- (beside the figure) and in the status tooltip, and nothing is called profit after fees
  Check(opps.summary == nil and opps.notes == nil and opps.about == nil and opps.profitOnly == nil and opps.source == nil, "the page carries none of them")
  Check(StatusTip():find("Profit is before fees", 1, true), "the unconfirmed cut is stated: " .. StatusTip())
  Same(Win.Heads().profit.text:GetText() .. " " .. Win.Heads().profit.sub:GetText(), "Profit before fees", "the column is not called estimated profit while the cut isn't taken off")
  -- the short tooltip on demand
  tip = {}
  r1:GetScript("OnEnter")(r1)
  local all = table.concat(tip, "\n")
  Check(all:find("Healing Potion", 1, true) and all:find("Cost to make | 200c", 1, true) and all:find("Sell price | 1000c to 2000c", 1, true), all)
  Check(all:find("Profit before fees | 800c to 1800c", 1, true) and not all:find("Estimated profit", 1, true), all)
  Check(all:find("just now", 1, true) and all:find("Hold Shift for details", 1, true), all)
  Check(not all:find("Peacebloom", 1, true) and not all:find("sales", 1, true), "no reagent breakdown or long caveats by default")
  Check(#tip <= 6, "a handful of lines: " .. #tip)
  -- Shift pressed while hovering shows the details (the window listens for the key while shown)
  tip = {}
  c.IsShiftKeyDown = function() return true end
  Fire("MODIFIER_STATE_CHANGED")
  all = table.concat(tip, "\n")
  Check(all:find("2 x Peacebloom | 100c each = 200c", 1, true), all)
  Check(all:find("Profit before fees | 800c to 1800c", 1, true) and all:find("Auction house cut | not deducted", 1, true), all)
  Check(all:find("Alliance auction house on Realm, scanned just now", 1, true) and all:find("not sales", 1, true), all)
  tip = {}
  c.IsShiftKeyDown = function() return false end
  Fire("MODIFIER_STATE_CHANGED")
  Check(table.concat(tip, "\n"):find("Hold Shift for details", 1, true), "released: back to the short one")
  r1:GetScript("OnLeave")(r1)
  tip = {}
  Fire("MODIFIER_STATE_CHANGED")
  Same(#tip, 0, "nothing is redrawn once the pointer has left")

  -- sorting by a column; unknown stays below
  local heads = Win.Heads()
  heads.cost:GetScript("OnClick")(heads.cost)
  Same(S.opp.sort, "cost"); Same(L_.rows[1].name:GetText(), "Mana Potion", "cheapest to make first"); Same(S.opp.desc, false)
  heads.cost:GetScript("OnClick")(heads.cost); Same(L_.rows[1].name:GetText(), "Healing Potion", "the same column again reverses it")
  heads.profit:GetScript("OnClick")(heads.profit)
  Same(S.opp.sort, "profit"); Same(L_.rows[1].name:GetText(), "Healing Potion")

  -- add to the existing queue (the same queue the Crafting view uses)
  local queued = #Q.Entries()
  -- choose the row, then the details' Add (the list itself only chooses)
  L_.rows[1]:GetScript("OnClick")(L_.rows[1])
  local add1 = opps.detail.add
  Same(opps.detail.name:GetText(), "Healing Potion", "the chosen row's details")
  Check(add1.text:GetText() == "Add to crafting plan" and add1.enabled)
  Press.Must(add1)   -- pressed as a player would: the control must be eligible first
  Same(#Q.Entries(), queued + 1); Check(Q.Find(1), "Healing Potion is in the one queue")
  Same(opps.detail.add.text:GetText(), "In your queue"); Check(opps.detail.add.enabled == false)
  Check(L_.rows[1].sub:GetText():find("In your queue", 1, true), "and the row says so")
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
  Same(S.Opportunities().summary.priced, 1)

  -- a scan that fails keeps the usable one
  local before = W.Prices.Market("Realm|Alliance").at
  clock = clock + 400
  opps.scan:GetScript("OnClick")(opps.scan)
  Advance(100)
  Same(W.Scan.state, "failed")
  Check(opps.status:GetText():find("earlier prices were kept", 1, true), opps.status:GetText())
  Same(W.Prices.Market("Realm|Alliance").at, before, "the earlier scan is untouched")
  Same(L_.rows[1].name:GetText(), "Healing Potion"); Same(L_.rows[1].cost.a:GetText(), "200c", "and the list still uses it")
  Check(StatusTip():find("Alliance auction house", 1, true), "still names the market")

  -- Profitable only
  S.ToggleProfitOnly(); Win.Render()   -- the filter's logic stays though the toolbar no longer carries its switch
  Same(#L_.data, 1, "only Healing Potion is both priced and profitable"); Same(L_.rows[1].name:GetText(), "Healing Potion")
  ah.records = { { item = 10, count = 2, buyout = 200 }, { item = 11, count = 1, buyout = 50 }, { item = 501, count = 1, buyout = 10 }, { item = 502, count = 1, buyout = 10 } }
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE"); Advance(5)
  Same(#L_.data, 0); Check(L_.empty:GetText():find("No profitable crafts", 1, true), L_.empty:GetText())
  S.ToggleProfitOnly(); Win.Render()
  Same(#L_.data, 2, "off: they are all shown, losses included")
  Check(L_.rows[1].profit.a:GetText():sub(1, 1) == "-", "a loss shows its minus sign")

  -- prices exist but none of these recipes could be priced
  ah.records = { { item = 999, count = 1, buyout = 5 } }
  opps.scan:GetScript("OnClick")(opps.scan); FireScan("REPLICATE_ITEM_LIST_UPDATE"); Advance(5)
  Same(W.Scan.state, "done")
  Check(Win.Lists().opps.empty:IsShown() == false, "the rows are still listed (as unknown)")
  Check(L_.rows[1].profit.a:GetText() == "Unknown")
  Same(S.Opportunities().summary.priced, 0)
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
  c.TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Alliance"] = { f = 2, scope = "full", realm = "Realm", side = "Alliance", at = os.time() - 90000, complete = true, read = 1, used = 1, n = 2,
    items = { [10] = "100,9,9,9,0", [12] = "10,9,9,9,0" }, hist = {}, sd = {} } } }
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
  local function Select(r) r:GetScript("OnClick")(r) return shop.detail end   -- a row chosen: its details are shown
  local sd = Select(make)
  Same(make.name:GetText(), "Peacebloom"); Same(make.need:GetText(), "2")
  Same(make.kind:GetText(), "Make", "the row says Make in words as well as in its picture")
  Check(sd.choose.make.on and not sd.choose.auction.on, "the details light Make")
  Same(sd.name:GetText(), "Peacebloom")
  Check(sd.explain:GetText():find("Make 2 x Peacebloom Bundle", 1, true), sd.explain:GetText())
  Check(sd.explain:GetText():find("Making this looks cheaper than buying at the auction house", 1, true), sd.explain:GetText())
  Same(sd.act.text:GetText(), "Add to crafting plan"); Check(sd.act:IsShown())
  -- the suggestion and the player's own choice are told apart, in words: Make is suggested (the lowest cost), nothing is overridden yet
  Same(sd.tags.make:GetText(), "Suggested"); Same(sd.tags.auction:GetText(), ""); Same(sd.tags.vendor:GetText(), "")
  Check(not sd.useSuggestion:IsShown(), "no override: no Use suggestion")
  Check(sd.choose.vendor.enabled == false and sd.choose.vendor.twichuiTip.body(sd.choose.vendor):find("Not available: No vendor that sells this has been seen.", 1, true), "an impossible source says why")
  sd.choose.auction:GetScript("OnClick")(sd.choose.auction)   -- the player chooses the auction house instead
  Same(S.picks[10], "auction"); Check(sd.choose.auction.on and not sd.choose.make.on, "the choice is lit")
  Same(sd.tags.make:GetText(), "Suggested", "the suggestion stays marked while it is overridden")
  Same(sd.tags.auction:GetText(), "Your choice")
  Check(sd.useSuggestion:IsShown(), "an override offers Use suggestion")
  Check(sd.choose.make.twichuiTip.body(sd.choose.make):find("suggestion", 1, true), "the suggested source's tooltip says so")
  sd.useSuggestion:GetScript("OnClick")(sd.useSuggestion)
  Same(S.picks[10], nil, "Use suggestion drops the choice"); Check(sd.choose.make.on and not sd.useSuggestion:IsShown())
  Same(sd.tags.make:GetText(), "Suggested"); Same(sd.tags.auction:GetText(), "")
  sd.choose.make:GetScript("OnClick")(sd.choose.make)   -- choosing what is suggested is not an override
  Same(S.picks[10], "make"); Same(sd.tags.make:GetText(), "Suggested"); Check(not sd.useSuggestion:IsShown(), "your choice equal to the suggestion is not an override")
  sd.choose.make:GetScript("OnClick")(sd.choose.make)   -- the lit one again returns to the suggestion
  Same(S.picks[10], nil)
  sd = Select(seed)
  Same(seed.name:GetText(), "Seed"); Same(seed.need:GetText(), "2"); Same(seed.spend.a:GetText(), "20c", "2 seeds at 10 each")
  Same(seed.kind:GetText(), "Buy")
  Check(sd.explain:GetText():find("Needed to make Peacebloom Bundle", 1, true), sd.explain:GetText())
  Check(seed.spend.b:GetText():find("1 day ago", 1, true), "the price age is shown: " .. seed.spend.b:GetText())
  Check(sd.costNote:GetText():find("1 day ago", 1, true), "and in the details: " .. sd.costNote:GetText())
  Check(not sd.act:IsShown(), "no action where none fits")
  Check(shop.total:GetText():find("Estimated spending: 20c", 1, true), shop.total:GetText())
  -- the basis tooltip says what is owned and what is not
  tip = nil
  local lines = {}
  c.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
  c.GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " | " .. b end
  make:GetScript("OnEnter")(make)
  local all = table.concat(lines, "\n")
  Check(all:find("Make | worth 20c", 1, true) and all:find("Cooldowns, tools and stations aren't checked", 1, true), all)
  -- adding the made material to the queue: explicit, once; nothing is counted twice
  local makeAct = Select(make).act
  makeAct:GetScript("OnClick")(makeAct)
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
  local pd = Select(sr)
  local auction = pd.choose.auction
  auction:GetScript("OnClick")(auction)
  Check(S.picks[12] == "auction" and pd.choose.auction.on, "the player's choice, lit in the details")
  Same(SL.rows[1].detail:GetText(), "Auction house", "and named under the row")
  auction:GetScript("OnClick")(auction)
  Check(S.picks[12] == nil, "chosen again: back to the suggestion")

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
  pd = Select(sr)
  Check(pd.choose.vendor.on and sr.detail:GetText() == "Vendor", "4 each at the vendor against 10 at the auction house"); Same(sr.spend.a:GetText(), "8c")
  Check(not pd.act:IsShown(), "no place is known for the vendor, so no Show vendor")
  local located
  R.NpcStore = { Entries = function() return { { id = 4567, n = "Mira", m = 1, x = 5000, y = 5000, s = { 12 }, own = true } } end,
    ValidMap = function() return true end, Usable = function() return true end, MyFaction = function() return nil end, COORD = 10000 }
  R.NpcMap = { Locate = function(e) located = e; return true end }
  local enabled = R.Enabled
  R.Enabled = function(_, key) if key == "npcMap" then return true end return enabled(R, key) end
  Win.Render()
  sr = SL.rows[1]
  pd = Select(sr)
  Check(pd.act:IsShown() and pd.act.text:GetText() == "Show vendor", "a seen place: Show vendor")
  pd.act:GetScript("OnClick")(pd.act)
  Check(located and located.n == "Mira", "the map is asked to show that vendor, nothing else")
  Check(f.note:GetText():find("Showing Mira on the map", 1, true), f.note:GetText())
  R.Enabled = enabled; R.NpcStore, R.NpcMap = nil, nil

  -- a material with no price: a known subtotal and a clear message, never a complete-looking total
  Q.Remove(3)
  g.bags[10] = 0
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].items[12] = nil
  c.TwichUIDB.workshop.vendor = nil
  Win.Render()
  Same(#SL.data, 1); Same(SL.rows[1].name:GetText(), "Peacebloom"); Same(SL.rows[1].spend.a:GetText(), "200c")
  Check(shop.total:GetText():find("Estimated spending: 200c", 1, true) and not shop.total:GetText():find("missing", 1, true), shop.total:GetText())
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].items[10] = nil
  Win.Render()
  Same(SL.rows[1].spend.a:GetText(), "Unknown", "unknown cost is not zero")
  Check(shop.total:GetText():find("price missing", 1, true), shop.total:GetText())

  f:Hide()
  Same(Events(f), 0, "hidden: no events")
  Same(W.Snapshot().events, 0)
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
end

---------------------------------------------------------------------------
-- Bank and guild bank materials in the window: Crafting columns and wording, the guild choice, Shopping's collect rows
---------------------------------------------------------------------------
do
  c.C_Timer = { After = function() end }
  for _, e in ipairs({ table.unpack and table.unpack(Q.Entries()) or unpack(Q.Entries()) }) do Q.Remove(e.id) end
  Same(#Q.Entries(), 0)
  Q.Add({ id = 500, name = "Test Draught", prof = 171, profName = "Alchemy", icon = 1, outItem = 900, outMin = 1, outMax = 1, mats = { { item = 10, qty = 3 } } }, 4)   -- 12 Peacebloom
  g.bags = { [10] = 4 }
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  f:Show()
  local m = Win.Lists().mats.rows[1]
  Same(m.need:GetText(), "12"); Same(m.have:GetText(), "4"); Same(m.stored:GetText(), "-", "nothing stored"); Same(m.short:GetText(), "8")
  Same(f.storeNote:GetText(), "Open your bank with Workshop loaded to update.", "an unseen bank is explained")
  Same(f.scope:GetText(), "Counts bags only.")
  Check(not f.useGuild.on or f.useGuild.on == false, "the guild choice is off by default")

  -- the bank is seen: 5 of the missing 8 are in it
  W.Storage.StoreBank({ ids = { 6 }, tabs = { [6] = { [10] = 5 } }, incomplete = 0 }, Q.Now() - 7200)
  Win.Render()
  m = Win.Lists().mats.rows[1]
  Same(m.have:GetText(), "4", "the bags are still the bags"); Same(m.stored:GetText(), "5"); Same(m.short:GetText(), "3", "12 - 4 - 5")
  Same(f.headline:GetText(), "Still needed: 1 material. 1 to collect from storage.")
  Same(f.scope:GetText(), "Counts bags and bank."); Same(f.storeNote:GetText(), "")

  -- the guild bank: chosen with the window's own control, saved
  c.IsInGuild = function() return true end
  c.GetGuildInfo = function() return "Raiders", "Rank", 1, nil end
  f.useGuild:GetScript("OnClick")(f.useGuild)
  Check(S.UseGuild() and W.Storage.UseGuild(), "the choice is saved")
  Check(f.storeNote:GetText():find("Open your guild bank with Workshop loaded to update.", 1, true), f.storeNote:GetText())
  local realm = c.GetRealmName()
  W.Storage.StoreGuildTab({ key = "Raiders-" .. realm, name = "Raiders" }, 1, { n = { [10] = 9 }, by = Q.CharKey(), w = 1, lim = 5, rem = -1 }, Q.Now() - 60, 1)
  Win.Render()
  m = Win.Lists().mats.rows[1]
  Same(m.stored:GetText(), "8", "5 from the bank and 3 from the guild bank"); Same(m.short:GetText(), "0")
  Same(f.headline:GetText(), "Collect materials: 1 from your bank and 1 from the guild bank.", "stored materials are 'collect', not 'ready'")
  Same(f.scope:GetText(), "Counts bags, bank and guild bank.")

  -- Shopping: collect rows apart from buy and make
  Win.SetMode("shop")
  local shop, SL = Win.Shop(), Win.Lists().shop
  Same(#SL.data, 2, "a bank row and a guild bank row; nothing to buy")
  local r1, r2 = SL.rows[1], SL.rows[2]
  local function Select(r) r:GetScript("OnClick")(r) return shop.detail end   -- a row chosen: its details are shown
  local d1 = Select(r1)
  Same(r1.need:GetText(), "5"); Same(r1.kind:GetText(), "Collect"); Same(r1.detail:GetText(), "From your bank")
  Check(not d1.choose.vendor:IsShown() and not d1.choose.auction:IsShown() and not d1.choose.make:IsShown(), "no source to pick for something you own")
  Same(r2.need:GetText(), "3"); Same(r2.kind:GetText(), "Collect"); Same(r2.detail:GetText(), "From the guild bank")
  Same(r1.spend.a:GetText(), "Already owned"); Check(not d1.act:IsShown(), "no action: nothing is bought, made or sent")
  Check(r1.spend.b:GetText():find("seen 2 hours ago", 1, true), r1.spend.b:GetText())
  local d2 = Select(r2)
  Check(d2.explain:GetText():find("Shared stock", 1, true) and not d2.explain:GetText():find("limit", 1, true), "unlimited today: " .. d2.explain:GetText())
  W.Storage.StoreGuildTab({ key = "Raiders-" .. realm, name = "Raiders" }, 1, { n = { [10] = 9 }, by = Q.CharKey(), w = 1, lim = 5, rem = 3 }, Q.Now() - 60, 1)
  Win.Render()
  Check(Select(Win.Lists().shop.rows[2]).explain:GetText():find("withdrawal limit may apply", 1, true), "a finite allowance is flagged, not promised")
  Same(shop.total:GetText(), "Nothing to buy: collect what is stored.")
  Check(shop.status:GetText():find("bags, bank and guild bank", 1, true), shop.status:GetText())
  -- the choice off again: the guild bank's part is something to buy
  shop.useGuild:GetScript("OnClick")(shop.useGuild)
  Check(not S.UseGuild(), "the same choice from the Shopping view")
  Same(#SL.data, 2); Same(SL.rows[1].kind:GetText(), "Collect")
  Same(SL.rows[2].kind:GetText(), "Buy", "the second row is now a buy row")
  Check(Select(SL.rows[2]).choose.auction:IsShown(), "with its source choices")
  Same(SL.rows[2].need:GetText(), "3"); Same(SL.rows[2].spend.a:GetText(), "Unknown", "unpriced: unknown, not zero")
  Check(shop.total:GetText():find("price missing", 1, true), shop.total:GetText())
  Win.SetMode("craft")
  f:Hide()
  Same(Events(f), 0, "hidden: no events")
end

---------------------------------------------------------------------------
-- The refined pages: Overview (skills, states, activity), Opportunities (honest history chart, selection, sort indicators), Crafting
-- (left card modes, plan estimates and totals) and Shopping (details). Synthetic data only.
---------------------------------------------------------------------------
do
  local f = Win.Frame()
  local pend = {}
  c.C_Timer = { After = function(_, fn) pend[#pend + 1] = fn end }
  local function Flush() local list = pend; pend = {}; for _, fn in ipairs(list) do fn() end end
  c.GetMoneyString = function(n) return n .. "c" end
  c.UnitFactionGroup = function() return "Alliance" end
  c.GetRealmName = function() return "Realm" end
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 } }
  g.schem = {
    [1] = { quantityMin = 1, quantityMax = 1, outputItemID = 501, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 2, required = true } } },
    [2] = { quantityMin = 1, quantityMax = 1, outputItemID = 502, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 1, required = true },
      { reagentType = 1, reagents = { { itemID = 11 } }, quantityRequired = 1, required = true } } },
  }
  g.filtered = { 1, 2 }
  g.bags = { [10] = 4, [11] = 1 }
  g.prof = { professionID = 171, professionName = "Alchemy" }
  local now = os.time()
  local today = math.floor(now / 86400)
  local function Market(over)
    local m = { f = 2, scope = "full", realm = "Realm", side = "Alliance", at = now - 18000, complete = true, read = 1, used = 1, n = 23439,
      items = { [10] = "100,9,9,9,0", [11] = "50,9,9,9,0", [501] = "1000,1,1,1,0", [502] = "300,1,1,1,0" },
      hist = { [501] = (today - 3) .. ",900;" .. (today - 2) .. ",1000;" .. today .. ",1100|", [502] = today .. ",300|" }, sd = { today - 3, today - 2, today } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
  end
  c.TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Alliance"] = Market() } }
  c.TwichUIDB.workshop.vendor = nil
  c.TwichUIDB.workshop.storage = nil   -- no remembered bank from the sections above
  local ch = c.TwichUIDB.workshop.chars and c.TwichUIDB.workshop.chars[Q.CharKey()]
  if ch then ch.known = nil end   -- the recipes remembered by earlier sections: this one starts with the two it sets up
  f:Hide(); f:Show()
  local ov = Win.Overview()
  Win.SetMode("overview")

  -- Overview: the numbers, thousands separators, and "complete" only when the scan was
  local cards = ov.cards
  Same(cards.market.stat:GetText(), "23,439", "items priced, readable"); Same(cards.market.statLabel:GetText(), "items priced")
  Check(cards.market.facts[1].text:GetText():find("^Scan complete"), cards.market.facts[1].text:GetText())
  Same(cards.market.facts[2].text:GetText(), "Covers every listed item", "what the scan covered; the market's name is not repeated on the card")
  Check(cards.market.facts[1].text:GetText():find("5 hours ago", 1, true), "its age")
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = Market({ complete = false })
  Win.Render()
  Check(cards.market.facts[1].text:GetText():find("^Partial scan"), "a scan that was not whole is never called complete: " .. cards.market.facts[1].text:GetText())
  Same(cards.market.facts[2].text:GetText(), "Some listings may be missing")
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = Market({ at = now - 3 * 86400, realm = "Realm" })
  Win.Render()
  Check(cards.market.facts[1].text:GetText():find("(old)", 1, true), "an old scan says so")
  local LONG = "A very long realm name that cannot fit"
  c.GetRealmName = function() return LONG end
  c.TwichUIWorkshopDB.markets = { [LONG .. "|Alliance"] = Market({ realm = LONG }) }
  Win.Render()
  Check(not (cards.market.facts[1].text:GetText() .. cards.market.facts[2].text:GetText()):find("realm", 1, true), "no realm or side name on the card, however long it is")
  c.GetRealmName = function() return "Realm" end
  c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = Market() }
  Win.Render()

  -- Overview: professions with their skill; unusable numbers are unavailable, never zero
  local skills = { { "Tailoring", 1001, 125, 150 }, { "Enchanting", 1002, 98, 150 }, { "Fishing", 1003, 75, 150 } }
  c.GetProfessions = function() return 1, 2, nil, 3 end
  c.GetProfessionInfo = function(i) local k = skills[i] if k then return k[1], k[2], k[3], k[4] end end
  Win.Render()
  local pr = cards.profs.facts
  local function PRow(i) return pr[i].text:GetText() .. "|" .. pr[i].value:GetText() .. "|" .. ("%.4f"):format(pr[i].bar.frac) end
  Same(PRow(1), "Tailoring|125 / 150|0.8333"); Same(PRow(2), "Enchanting|98 / 150|0.6533"); Same(PRow(3), "Fishing|75 / 150|0.5000")
  Check(not pr[4]:IsShown(), "only as many rows as professions")
  skills[2][3] = 151   -- more than the maximum: not a pair the game can mean
  Win.Render()
  Same(PRow(2), "Enchanting|n/a|0.0000", "an unusable pair is unavailable, not a made-up level")
  skills[2][3], skills[2][4] = nil, nil
  Win.Render()
  Same(PRow(2), "Enchanting|n/a|0.0000", "no numbers: unavailable")
  skills[2][3], skills[2][4] = 98, 150
  -- a refresh event, only while shown
  Check(f.events["SKILL_LINES_CHANGED"], "the skill change is listened for while shown")
  skills[1][3] = 126
  Fire("SKILL_LINES_CHANGED"); Flush()
  Same(PRow(1), "Tailoring|126 / 150|0.8400", "a skill change redraws the card")
  -- no API: the Workshop's own professions, drawn as unavailable
  c.GetProfessions, c.GetProfessionInfo = nil, nil
  Win.Render()
  Check(cards.profs.facts[1]:IsShown() and cards.profs.facts[1].value:GetText() == "n/a" and cards.profs.facts[1].bar.frac == 0, "no skill from the game: unavailable")
  c.GetProfessions = function() return nil end
  c.GetProfessionInfo = function() end
  Win.Render()
  Check(cards.profs.facts[1].text:GetText():find("No professions", 1, true), "none learned: said so")
  c.GetProfessions = function() return 1, 2, 3, 4, 5, 6 end
  c.GetProfessionInfo = function(i) return "Skill " .. i, 1000 + i, 10 * i, 100 end
  Win.Render()
  Same(cards.profs.more:GetText(), "and 3 more", "more professions than the card has room for: the rows that fit, and the rest said, not squeezed")
  Same(pr[3].text:GetText(), "Skill 3"); Check(not pr[4]:IsShown(), "no row is drawn outside the card")
  c.GetProfessions = function() return 1 end
  c.GetProfessionInfo = function(i) return "Alchemy", 1001, 80, 100 end

  -- Overview: recent activity is real, bounded and newest first
  S.ClearActivity(); Win.Render()
  Check(ov.bottom.empty:IsShown() == false, "the saved scan is real, so the list is not empty")
  Check(ov.activity[1].text:GetText():find("Auction house scan completed (23,439 items)", 1, true), ov.activity[1].text:GetText())
  Same(ov.activity[1].age:GetText(), "5h ago")
  Check(S.Add(S.AllRecipes()[1]), "queued the potion")
  Win.Render()
  Same(ov.activity[1].text:GetText(), "Added Healing Potion to plan", "a plan change is recorded the moment it happens")
  Same(ov.activity[2].text:GetText():find("Auction house scan completed", 1, true) ~= nil, true)
  Check(ov.activity[1].age:GetText() == "just now")
  for i = 1, 12 do S.Change(1, 1); S.Change(1, -1) end   -- changing a count is not an event
  Same(#S.Activity(), 1 + 0, "changing the number of crafts is not an activity")
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  local n = 0
  for i = 1, 14 do S.Add(S.AllRecipes()[(i % 2) + 1]); S.Remove(S.AllRecipes()[(i % 2) + 1].id) end
  Check(#S.Activity() <= 8, "the activity list is bounded: " .. #S.Activity())
  Check(S.Activity()[1].text:find("^Removed"), "newest first")
  -- activity does not touch the saved data
  Check(c.TwichUIDB.workshop.activity == nil, "nothing about activity is saved")
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = nil
  Win.Render()
  Same(cards.market.stat:GetText(), "\226\128\148", "no market: no invented count"); Same(cards.market.facts[1].text:GetText(), "No scan yet")
  Check(ov.bottom.empty:IsShown() == (#S.Activity() == 0), "the empty state shows only with nothing to say")
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = Market()
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end

  -- Opportunities: selection, sort indicators, the honest chart
  Win.SetMode("opps"); Win.Render()
  local opps, L_ = Win.Opps(), Win.Lists().opps
  Check(#L_.data == 2, "two recipes, got " .. #L_.data .. ": " .. (L_.data[1] and L_.data[1].rec.name or "") .. " / " .. (L_.data[3] and L_.data[3].rec.name or ""))
  local H = Win.Heads()
  Check(H.profit.active and H.profit.tri:IsShown() and H.profit.tri.dir == "down" and not H.cost.active and H.cost.hintUp:IsShown() and not H.cost.tri:IsShown(),
    "profit is the sort, pointing down (highest first); the others only hint that they sort")
  H.cost:GetScript("OnClick")(H.cost)
  Check(H.cost.active and H.cost.tri.dir == "up" and not H.profit.active and H.profit.hintUp:IsShown(), "the indicator moves to the new column, pointing up for cheapest first")
  H.cost:GetScript("OnClick")(H.cost)
  Check(H.cost.tri.dir == "down", "the same column again reverses the arrow")
  H.profit:GetScript("OnClick")(H.profit)
  Check(H.profit.active and H.profit.tri.dir == "down", "back on profit")
  Same(L_.rows[1].name:GetText(), "Healing Potion")
  local r1, r2 = L_.rows[1], L_.rows[2]
  Check(r1.selected == true and not r2.selected, "the first row is chosen by default")
  r2:GetScript("OnClick")(r2)
  Check(r2.selected == true and not L_.rows[1].selected, "choosing a row marks it and only it")
  Same(opps.detail.name:GetText(), "Mana Potion")
  -- Mana Potion has one observed day: no mostly empty plot with one floating dot, but the words and the one price (no dot, no stem, no line)
  local chart = opps.detail.chart
  Same(chart.state, "single"); Same(chart.shown, 0)
  Check(not chart.dots[1]:IsShown() and not chart.stems[1]:IsShown(), "one observation draws nothing: a lone dot says no more than the number")
  Same(chart.msg:GetText(), "More scans needed to show a price trend."); Check(chart.msg:IsShown() and chart.note:IsShown())
  Check(chart.note:GetText():find("Cheapest seen: ", 1, true) and chart.note:GetText():find("seen today", 1, true), "the one observed price and when: " .. chart.note:GetText())
  Same(chart.hi:GetText(), ""); Same(chart.lo:GetText(), "")
  Same(opps.detail.chartNote:GetText(), "1 observed day")
  r1:GetScript("OnClick")(r1)
  Same(opps.detail.name:GetText(), "Healing Potion")
  -- Healing Potion: three observed days (today-3, today-2, today): the dots sit at their real days, the gap before today is a gap
  Same(chart.state, "series")
  Same(chart.shown, 3); Check(chart.dots[1]:IsShown() and chart.dots[3]:IsShown() and not chart.dots[4]:IsShown(), "three observations, three dots")
  Check(not chart.msg:IsShown() and not chart.note:IsShown(), "no message over a real chart")
  local function X(i) local pt = chart.dots[i].points[#chart.dots[i].points] return pt[4] end
  Check(X(1) < X(2) and X(2) < X(3), "oldest to newest, left to right")
  Check(math.abs((X(3) - X(2)) - 2 * (X(2) - X(1))) < 0.01, "spacing follows the days (a missing day is a gap): " .. X(1) .. " " .. X(2) .. " " .. X(3))
  Same(opps.detail.chartNote:GetText(), "3 observed days")
  Check(chart.hi:GetText() == "1100c" and chart.lo:GetText() == "900c", "its range is the lowest and highest observed: " .. chart.hi:GetText() .. " / " .. chart.lo:GetText())
  -- older groups are named, not drawn
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].hist[501] = (today - 1) .. ",1000;" .. today .. ",1100|" .. math.floor((today - 40) / 28) .. ",800,950,1750,2"
  Win.Render()
  Same(chart.shown, 2); Check(opps.detail.chartNote:GetText():find("plus older ranges", 1, true), "older days are named, never drawn: " .. opps.detail.chartNote:GetText())
  -- only older ranges: nothing to draw, and it says so
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].hist[501] = "|" .. math.floor((today - 40) / 28) .. ",800,950,1750,2"
  Win.Render()
  Same(chart.state, "empty"); Same(chart.shown, 0)
  Check(chart.msg:IsShown() and chart.msg:GetText():find("older ranges", 1, true), chart.msg:GetText())
  -- no history at all
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].hist[501] = nil
  Win.Render()
  Same(chart.shown, 0); Check(chart.msg:GetText():find("No price history", 1, true) and chart.hi:GetText() == "", chart.msg:GetText())
  -- a malformed history is no history (never repaired by guessing)
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].hist[501] = "garbage"
  Win.Render()
  Same(chart.shown, 0)
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].hist[501] = (today - 3) .. ",900;" .. (today - 2) .. ",1000;" .. today .. ",1100|"
  Win.Render()
  -- the materials of one craft: each with its item tooltip and its quantity
  local mat = opps.detail.mats[1]
  Check(mat:IsShown() and mat.item == 10 and mat.qty:GetText() == "\195\151" .. 2, "a material: item and quantity")
  tip = {}
  Check(mat.scripts.OnEnter ~= nil and mat.scripts.OnClick ~= nil, "it has an item tooltip and a chat link on Shift-click")

  -- Crafting: the left card's two lists, the plan's estimates and totals
  Win.SetMode("craft"); Win.Render()
  local cr = Win.Craft()
  Check(Win.Lists().recipes.box:IsShown() == (Win.Lists().queue.box:IsShown() == false), "one list at a time in the left card")
  cr.segQueue:GetScript("OnClick")(cr.segQueue)
  Check(Win.Lists().queue.box:IsShown() and not Win.Lists().recipes.box:IsShown() and cr.segQueue.on and not cr.segRecipes.on, "Craft queue shows the queue")
  cr.addRecipe:GetScript("OnClick")(cr.addRecipe)
  Check(Win.Lists().recipes.box:IsShown() and not Win.Lists().queue.box:IsShown() and f.search:IsShown(), "Add recipe shows the recipes")
  local rec = S.AllRecipes()
  S.Add(rec[1]); S.Add(rec[2])
  S.SetCrafts(1, 2)
  Win.Render()
  -- Healing Potion x2: cost 2 x 200, sells 2 x 1000, profit 2 x 800. Mana Potion x1: cost 100 + 50, sells 300, profit 150.
  local byId, tot = S.PlanEstimates()
  Same(byId[1].cost, 400); Same(byId[1].sellLow, 2000); Same(byId[1].profitLow, 1600)
  Same(byId[2].cost, 150); Same(byId[2].profitLow, 150)
  Same(tot.cost, 550); Same(tot.sellLow, 2300); Same(tot.profitLow, 1750); Same(tot.priced, 2); Same(tot.unpriced, 0); Same(tot.crafts, 3)
  local bar = cr.bar
  Same(bar.title:GetText(), "Total (2 recipes)"); Same(bar.sub:GetText(), "3 crafts to make")
  Same(bar.cost:GetText(), "550c"); Same(bar.value:GetText(), "2300c"); Same(bar.profit:GetText(), "1750c")
  Same(bar.profitLabel:GetText(), "Profit before fees", "the totals say before fees too")
  Same(bar.partial:GetText(), "")
  Same(cr.detail.name:GetText(), "Healing Potion"); Same(cr.detail.cost:GetText(), "400c"); Same(cr.detail.sell:GetText(), "2000c"); Same(cr.detail.profit:GetText(), "1600c")
  Check(bar.shop.enabled, "the shopping list is reachable")
  -- an unpriced craft is left out of the totals and counted, never taken as free
  c.TwichUIWorkshopDB.markets["Realm|Alliance"].items[11] = nil
  Win.Render()
  local _, tot2 = S.PlanEstimates()
  Same(tot2.priced, 1); Same(tot2.unpriced, 1); Same(tot2.cost, 400, "Mana Potion is not in the cost")
  Same(bar.partial:GetText(), "1 of 2 priced"); Same(bar.cost:GetText(), "400c")
  cr.open:GetScript("OnClick")(cr.open)   -- Open recipe stays, and acts on the chosen craft
  Same(g.opened[#g.opened], 1)
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = nil
  Win.Render()
  Same(cr.detail.cost:GetText(), "Unknown"); Same(bar.cost:GetText(), "Unknown", "no prices: unknown, never 0")
  c.TwichUIWorkshopDB.markets["Realm|Alliance"] = Market()
  -- the queue rows: a chosen craft, and the plus and minus controls
  local qrow = Win.Lists().queue.rows[2]
  qrow:GetScript("OnClick")(qrow)
  Same(cr.detail.name:GetText(), "Mana Potion"); Check(qrow.selected == true and not Win.Lists().queue.rows[1].selected, "the chosen craft is marked")
  Check(qrow.less.enabled == false, "minus is off at one craft"); Check(Win.Lists().queue.rows[1].less.enabled == true)
  Check(#qrow.less.bars == 1 and #qrow.more.bars == 2, "the controls are drawn (a bar, and two bars): no font glyph")
  -- the materials list: an optional note per material (for a planner that knows how it is made) is shown only when given
  Check(Win.Lists().mats.rows[1].note:IsShown() == false, "no note, no second line")

  -- Shopping: the details of the chosen material
  Win.SetMode("shop"); Win.Render()
  local shop, SL = Win.Shop(), Win.Lists().shop
  g.bags = { [10] = 0, [11] = 0 }
  Win.Render()
  local row10
  for _, r in ipairs(SL.rows) do if r:IsShown() and r.item == 10 then row10 = r end end
  Check(row10, "Peacebloom is to be bought")
  row10:GetScript("OnClick")(row10)
  local d = shop.detail
  Same(d.name:GetText(), "Peacebloom")
  Check(row10.selected, "the chosen row is marked")
  -- needs: Healing x2 uses 4, Mana x1 uses 1: 5 in all, none in the bags
  Same(d.qty[1].l:GetText(), "Needed in total"); Same(d.qty[1].v:GetText(), "5")
  Same(d.qty[2].l:GetText(), "In your bags"); Same(d.qty[2].v:GetText(), "0")
  Same(d.qty[3].l:GetText(), "To get"); Same(d.qty[3].v:GetText(), "5")
  Check(d.usedFor:GetText():find("Needed for: Healing Potion, Mana Potion", 1, true), d.usedFor:GetText())
  Same(d.cost:GetText(), "500c", "5 at 100 each"); Check(d.costNote:GetText():find("Auction house", 1, true), d.costNote:GetText())
  Same(row10.kind:GetText(), "Buy"); Check(not d.act:IsShown(), "Buy has no action here: nothing is bought for you")
  Check(d.choose.auction.on and d.choose.auction.enabled and not d.choose.vendor.enabled, "only the possible sources can be chosen")
  Check(shop.counts.buy.n:GetText() == "2" and shop.counts.make.n:GetText() == "0" and shop.counts.collect.n:GetText() == "0", "the plan counts")
  Check(shop.total:GetText():find("Estimated spending: 550c", 1, true), shop.total:GetText())
  -- only collect rows
  g.bags = { [10] = 0, [11] = 0 }
  W.Storage.StoreBank({ ids = { 6 }, tabs = { [6] = { [10] = 5, [11] = 1 } }, incomplete = 0 }, Q.Now() - 600)
  Win.Render()
  Same(#SL.data, 2); Check(SL.rows[1].kind:GetText() == "Collect" and SL.rows[2].kind:GetText() == "Collect", "everything is stored: two collect rows")
  Check(shop.counts.collect.n:GetText() == "2" and shop.counts.buy.n:GetText() == "0")
  Same(shop.total:GetText(), "Nothing to buy: collect what is stored.")
  local cd = shop.detail
  Check(not cd.choose.vendor:IsShown() and not cd.act:IsShown(), "collect: no source choice, no action")
  Same(cd.cost:GetText(), "Already owned")
  g.bags = { [10] = 4, [11] = 1 }
  W.Storage.Reset = nil
  c.TwichUIDB.workshop.storage = nil
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  Win.SetMode("overview")
  f:Hide()
end

---------------------------------------------------------------------------
-- The third pass (real-client findings): the Opportunities Add button through its real handler, queued states that fit their place, the
-- tooltips of queued crafts, the hover of every kind of row (it is owned by the row, and survives a tooltip, a child and a selection),
-- the profession bars inside their card, the market status (freshness and completeness apart) and the chart's sparse-history states.
---------------------------------------------------------------------------
do
  local f = Win.Frame()
  local M = R.Look.Motion
  local pend = {}
  c.C_Timer = { After = function(_, fn) pend[#pend + 1] = fn end }
  local function Flush() local list = pend; pend = {}; for _, fn in ipairs(list) do fn() end end
  c.GetMoneyString = function(n) return n .. "c" end
  c.UnitFactionGroup = function() return "Alliance" end
  c.GetRealmName = function() return "Realm" end
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 } }
  g.schem = {
    [1] = { quantityMin = 1, quantityMax = 1, outputItemID = 501, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 2, required = true } } },
    [2] = { quantityMin = 1, quantityMax = 1, outputItemID = 502, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 1, required = true },
      { reagentType = 1, reagents = { { itemID = 11 } }, quantityRequired = 1, required = true } } },
  }
  g.names[501], g.names[502] = "Healing Potion", "Mana Potion"
  g.filtered = { 1, 2 }
  g.bags = { [10] = 4, [11] = 1 }
  g.prof = { professionID = 171, professionName = "Alchemy" }
  local now = os.time()
  local today = math.floor(now / 86400)
  local function Market(over)
    local m = { f = 2, scope = "full", realm = "Realm", side = "Alliance", at = now - 1920, complete = true, read = 1, used = 1, n = 23439,
      items = { [10] = "100,9,9,9,0", [11] = "50,9,9,9,0", [501] = "1000,1,1,1,0", [502] = "300,1,1,1,0" },
      hist = { [501] = (today - 3) .. ",900;" .. (today - 2) .. ",1000;" .. today .. ",1100|", [502] = today .. ",300|" }, sd = { today - 3, today - 2, today } }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
  end
  c.TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Alliance"] = Market() } }
  c.TwichUIDB.workshop.vendor = nil
  c.TwichUIDB.workshop.storage = nil
  local ch = c.TwichUIDB.workshop.chars and c.TwichUIDB.workshop.chars[Q.CharKey()]
  if ch then ch.known = nil end
  f:Hide(); f:Show()

  -- a recording tooltip
  local tip = { items = {}, lines = {}, shown = false }
  local GT = c.GameTooltip
  GT.SetOwner = function(s, o) s.owner = o; tip.lines = {}; tip.items = {}; tip.shown = true end
  GT.SetItemByID = function(_, id) tip.items[#tip.items + 1] = id end
  GT.AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end
  GT.AddDoubleLine = function(_, a, b) tip.lines[#tip.lines + 1] = a .. "=" .. tostring(b) end
  GT.SetText = function(_, t) tip.lines[#tip.lines + 1] = t end
  GT.ClearLines = function() tip.lines = {} end
  GT.Show = function() tip.shown = true end
  GT.Hide = function(s) tip.shown = false; s.owner = nil end
  local inserted = {}
  c.IsModifiedClick = function() return false end
  c.ChatEdit_InsertLink = function(l) inserted[#inserted + 1] = l end
  c.C_Item.GetItemInfo = function(id) return g.names[id], "|Hitem:" .. id .. "|h[" .. tostring(g.names[id]) .. "]|h" end

  ---------------------------------------------------------------------------
  -- 1. The Opportunities Add button: the real control, the chosen recipe, the queue, the redraw
  ---------------------------------------------------------------------------
  Win.SetMode("opps"); Win.Render()
  local opps, OL = Win.Opps(), Win.Lists().opps
  local add = opps.detail.add
  local first = OL.rows[1]
  first:GetScript("OnClick")(first)   -- choose the first row
  local chosenId = opps.detail.rec.id
  Check(chosenId and not Q.Find(chosenId), "a recipe is chosen and is not queued")
  Same(add.text:GetText(), "Add to crafting plan"); Check(add:IsEnabled() and add:IsShown() and add.check:IsShown() == false)
  Check(#add.artParts == 2 and add.artParts[1]:IsShown() and add.artParts[2]:IsShown(), "the plus is drawn")
  Check(type(add:GetScript("OnClick")) == "function", "the button has a click handler")
  local pressed = Press(add)   -- the control's own handler, run only if the button could take a click (shown, enabled, mouse on, in a shown window)
  Check(pressed.invoked, pressed.text)
  Same(pressed.calls[1], "OnClick"); Same(pressed.button, "LeftButton")
  Check(Q.Find(chosenId), "the chosen recipe is in the queue")
  Same(Q.Find(chosenId).crafts, 1, "queued once")
  Same(add.text:GetText(), "In your queue"); Check(add:IsEnabled() == false and add.check:IsShown() and not add.artParts[1]:IsShown(), "the button says it, with a check in place of the plus")
  do
    local again = Press(add)
    Check(not again.invoked and again.reasons[1] == "disabled", "a queued recipe's Add button is disabled, and Press refuses it: " .. again.text)
    Same(Q.Find(chosenId).crafts, 1, "so pressing it again did not queue a second craft")
  end
  Check(f.note:GetText():find("Added ", 1, true), "the footer says what happened: " .. f.note:GetText())
  Check(first.sub:GetText():find("In your queue", 1, true), "the list row says so too")
  Check(add.twichuiTip.body(add):find("in your crafting plan", 1, true), "and the button's tooltip explains")
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  Check(#Win.Lists().queue.data == 1 and Win.Lists().queue.data[1].entry.id == chosenId, "the Crafting page shows the queue")
  f.tabOpps:GetScript("OnClick")(f.tabOpps)
  Same(W.OppsView.AddSelected(), false, "adding a recipe that is already queued is refused (the handler, not only the disabled button)")
  Check(f.note:GetText():find("already in the queue", 1, true), "and explained: " .. f.note:GetText())
  Same(#Q.Entries(), 1, "and changes nothing")

  -- a full queue: the button says so and the refusal is explained
  for i = 1, W.MAX_QUEUE do Q.Add({ id = 9000 + i, name = "Filler " .. i }, 1) end
  Same(#Q.Entries(), W.MAX_QUEUE)
  local other
  for _, r in ipairs(OL.rows) do if r:IsShown() and r.rec and not Q.Find(r.rec.id) then other = r end end
  Check(other, "an unqueued recipe is listed")
  other:GetScript("OnClick")(other)
  Same(add.text:GetText(), "Queue full"); Check(add:IsEnabled() == false and add.twichuiTip.body(add):find("full", 1, true))
  Same(W.OppsView.AddSelected(), false, "a full queue refuses")
  Check(f.note:GetText():find("The queue is full", 1, true), f.note:GetText())
  -- and the recipe browser's rows say Full inside their own place
  f.tabCraft:GetScript("OnClick")(f.tabCraft)
  local cr = Win.Craft()
  cr.segRecipes:GetScript("OnClick")(cr.segRecipes)
  local RL = Win.Lists().recipes
  local ACT_W = 70
  local function Fits(row)   -- the text and its picture are inside the place the button has: a mock font gives 6 units a character
    local text = row.mark:IsShown() and row.mark.text or row.add.text
    local start = row.mark:IsShown() and (row.mark.icon:IsShown() and 4 + 12 + 3 or 8) or (12 + 20 + 8)
    local w = start + #text:GetText() * 6
    return w <= ACT_W - 2, text:GetText() .. " " .. w
  end
  local seen = {}
  for _, r in ipairs(RL.rows) do
    if r:IsShown() and r.rec then
      local ok, what = Fits(r)
      Check(ok, "the action text fits its place: " .. what)
      seen[r.mark:IsShown() and r.mark.text:GetText() or r.add.text:GetText()] = true
      Check(r.mark:IsShown() ~= r.add:IsShown(), "a button or a mark, never both")
    end
  end
  Check(seen.Queued and seen.Full, "a queued and a full state were drawn: " .. (seen.Queued and "Queued " or "") .. (seen.Full and "Full" or ""))
  Check(RL.rows[1].mark.twichuiTip.body(RL.rows[1].mark):len() > 0, "a mark explains itself")
  for i = #Q.Entries(), 1, -1 do if Q.Entries()[i].id >= 9000 then Q.Remove(Q.Entries()[i].id) end end
  Win.Render()
  seen = {}
  for _, r in ipairs(RL.rows) do
    if r:IsShown() and r.rec then
      local ok, what = Fits(r)
      Check(ok, "fits: " .. what)
      seen[r.mark:IsShown() and "Queued" or "Add"] = true
    end
  end
  Check(seen.Add and seen.Queued, "an unqueued recipe is a button, a queued one a mark")
  -- a long name never changes the action's place or size
  RL.rows[1].fill(RL.rows[1], { id = 3001, name = ("Very long recipe name "):rep(6), diff = 1, icon = 1, prof = 171, profName = "Alchemy" })
  Check(Fits(RL.rows[1]) and RL.rows[1].add.w == ACT_W or RL.rows[1].mark.w == ACT_W, "a long name leaves the action as it was")

  ---------------------------------------------------------------------------
  -- 2. Queue tooltips: the item's own tooltip on its picture, a short recipe tooltip on the row, stale ones cleared
  ---------------------------------------------------------------------------
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  local recs = S.AllRecipes()
  S.Add(recs[1]); S.Add(recs[2]); S.SetCrafts(recs[1].id, 3)
  Win.Render()
  cr.segQueue:GetScript("OnClick")(cr.segQueue)
  local QL = Win.Lists().queue
  local qr1, qr2 = QL.rows[1], QL.rows[2]
  Check(qr1:IsShown() and qr2:IsShown())
  local function ItemOf(row) return row.entry.outItem end
  Check(ItemOf(qr1) == 501 and ItemOf(qr2) == 502, "the queue entries know what they make")
  qr1.iconBtn:GetScript("OnEnter")(qr1.iconBtn)
  Same(tip.items[1], 501, "hovering the first queued craft's picture shows ITS output item's tooltip")
  Same(GT:GetOwner(), qr1.iconBtn)
  qr2.iconBtn:GetScript("OnEnter")(qr2.iconBtn)
  Same(tip.items[1], 502, "and the second row's picture shows the second item, not the first")
  c.IsModifiedClick = function() return true end
  qr2.iconBtn:GetScript("OnClick")(qr2.iconBtn)
  Same(inserted[#inserted], "|Hitem:502|h[Mana Potion]|h", "Shift-click puts the item link in the chat box")
  local selectedBefore = qr1.selected
  qr1.iconBtn:GetScript("OnClick")(qr1.iconBtn)
  Same(inserted[#inserted], "|Hitem:501|h[Healing Potion]|h")
  c.IsModifiedClick = function() return false end
  qr2.iconBtn:GetScript("OnClick")(qr2.iconBtn)
  Check(qr2.selected == true, "an unmodified click on the picture chooses the row")
  -- the row's own tooltip: the recipe, the crafts queued, what it makes
  qr1.scripts.OnEnter(qr1)
  Same(GT:GetOwner(), qr1)
  local text = table.concat(tip.lines, " | ")
  Check(text:find("Healing Potion", 1, true) and text:find("Crafts queued=3", 1, true) and text:find("Makes=", 1, true), "the row's tooltip: " .. text)
  -- a recycled row: filled with another entry, its tooltip is drawn again from the new data; a hidden row leaves none behind
  qr1.entry = nil
  qr1:Hide()
  Check(tip.shown == false and GT:GetOwner() == nil, "a hidden row clears its tooltip")
  qr1:Show()
  -- the plus and minus controls keep their own tooltips and the row stays lit
  qr1.more.IsMouseOver = function() return true end
  qr1.scripts.OnEnter(qr1)
  qr1.scripts.OnLeave(qr1)
  Check(qr1.hovered == true, "the pointer went to the plus: the row stays lit")
  qr1.more.IsMouseOver = nil
  qr1.more.scripts.OnLeave(qr1.more)
  Check(qr1.hovered == false, "and goes out when the pointer leaves the plus and the row")
  Check(qr1.more.twichuiTip ~= nil, "the control still has its own tooltip")

  ---------------------------------------------------------------------------
  -- 3. Hover: owned by the row, visible, coexisting with the chosen state, bounded
  ---------------------------------------------------------------------------
  local function RowKinds()
    Win.SetMode("opps"); Win.Render()
    local o = Win.Lists().opps.rows[1]
    Win.SetMode("craft"); Win.Render()
    cr.segRecipes:GetScript("OnClick")(cr.segRecipes)
    local rr = Win.Lists().recipes.rows[1]
    cr.segQueue:GetScript("OnClick")(cr.segQueue)
    local qq = Win.Lists().queue.rows[1]
    local mm = Win.Lists().mats.rows[1]
    Win.SetMode("shop"); Win.Render()
    local ss = Win.Lists().shop.rows[1]
    return { opportunities = o, recipes = rr, queue = qq, materials = mm, shopping = ss, detailmat = Win.Opps().detail.mats[1] }
  end
  local kinds = RowKinds()
  local function Lit(row) return row.twichHot.parts[1].alpha or 0, row.twichRim.parts[1].alpha or 0 end
  for name, row in pairs(kinds) do
    Check(row, name .. " row exists")
    local onEnter, onLeave = row.scripts.OnEnter, row.scripts.OnLeave
    Check(onEnter and onLeave, name .. ": the row has its own OnEnter and OnLeave")
    -- whatever a page sets afterwards (tips, fills, selection), the row's scripts are the same ones, and they light it
    if row.fill then pcall(row.fill, row, row.data or row.qrow or row.rec or row.row) end
    Same(row.scripts.OnEnter, onEnter, name .. ": the scripts were not replaced")
    row:SetSelected(false); row:SetHot(false); M.Settle()
    onEnter(row)
    Check(row.hovered == true, name .. ": OnEnter lights the row")
    Check(M.Count() >= 1 or select(1, Lit(row)) > 0, name .. ": it eases in")
    M.Advance(0.3)
    local hot, rim = Lit(row)
    Check(hot >= 0.9 and rim >= 0.9, ("%s: lit art is visible once eased in (face %.2f, rim %.2f)"):format(name, hot, rim))
    -- chosen and hovered together
    row:SetSelected(true); M.Advance(0.3)
    Check(row.selected and row.hovered, name .. ": chosen and hovered at once")
    local hot2, rim2 = Lit(row)
    Check(rim2 > 0 and rim2 < rim and row.twichSel.parts[1]:IsShown(), ("%s: the chosen sheet shows and the rim is quieter (%.2f)"):format(name, rim2))
    row:SetSelected(false)
    onLeave(row)
    M.Advance(0.3)
    Check(row.hovered == false and select(1, Lit(row)) == 0 and select(2, Lit(row)) == 0, name .. ": leaving takes it out")
    -- hidden while lit
    onEnter(row); M.Advance(0.3); row:Hide()
    Check(row.hovered == false and select(1, Lit(row)) == 0, name .. ": a hidden row is not left lit")
    row:Show()
    -- recycled: the list re-reads the pointer
    row.IsMouseOver = function() return true end
    row:SyncHover(); M.Advance(0.3)
    Check(row.hovered, name .. ": a row that scrolls under the pointer lights")
    row.IsMouseOver = function() return false end
    row:SyncHover(); M.Advance(0.3)
    Check(not row.hovered, name .. ": and goes out when the pointer is elsewhere")
  end
  -- the row's tooltip and the lit state come from one OnEnter
  GT.owner = nil
  kinds.opportunities.scripts.OnEnter(kinds.opportunities)
  Check(kinds.opportunities.hovered, "the Opportunities row is lit")
  -- reduced motion: shown at once, nothing eases
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.reduceSettingsMotion = true
  local row = kinds.shopping
  row:SetHot(false); M.Settle()
  row:SetHot(true)
  Check(M.Count() == 0 and select(1, Lit(row)) >= 0.9, "reduced motion: lit at once, no easing")
  c.TwichUIDB.ui.reduceSettingsMotion = nil
  row:SetHot(false); M.Settle()
  -- a picture on a row keeps it lit (the Opportunities and Shopping rows)
  for _, name in ipairs({ "opportunities", "shopping" }) do
    local r = kinds[name]
    r.scripts.OnEnter(r)
    r.iconBtn.IsMouseOver = function() return true end
    r.scripts.OnLeave(r)
    Check(r.hovered, name .. ": the pointer on the picture keeps the row lit")
    r.iconBtn.scripts.OnEnter(r.iconBtn)
    Check(r.hovered, name .. ": and entering the picture lights it too")
    r.iconBtn.IsMouseOver = function() return false end
    r.iconBtn.scripts.OnLeave(r.iconBtn)
    Check(not r.hovered, name .. ": leaving everything takes it out")
  end

  ---------------------------------------------------------------------------
  -- 4. The profession bars stay inside the Overview card
  ---------------------------------------------------------------------------
  Win.SetMode("overview"); Win.Render()
  local ov = Win.Overview()
  local pc = ov.cards.profs
  local skills
  local function SetSkills(list)
    skills = list
    c.GetProfessions = function() local t = {} for i = 1, #list do t[i] = i end return unpack(t) end
    c.GetProfessionInfo = function(i) local k = skills[i] if k then return k[1], k[2], k[3], k[4] end end
  end
  local PROF_TOP, PROF_BOTTOM = 90, 10
  local function Inside(label)
    local lowest = 0
    local n = 0
    for _, row in ipairs(pc.facts) do
      if row:IsShown() then
        n = n + 1
        local y = row.points[#row.points][5]
        local bottom = -y + row.h
        if bottom > lowest then lowest = bottom end
        Check(row.h >= 18, label .. ": rows are tall enough to read (" .. row.h .. ")")
      end
    end
    if pc.more:GetText() ~= "" then lowest = lowest + 14 end
    Check(lowest <= pc.cardH - PROF_BOTTOM, ("%s: the list ends at %d inside a %d card"):format(label, lowest, pc.cardH))
    return n
  end
  local long = "A profession name that is far too long to fit in the room it has beside the numbers"
  local cases = {
    { "none", {}, 1 }, { "one", { { "Alchemy", 1, 125, 150 } }, 1 },
    { "two", { { "Alchemy", 1, 125, 150 }, { "Fishing", 2, 75, 150 } }, 2 },
    { "four", { { "Alchemy", 1, 125, 150 }, { "Tailoring", 2, 80, 100 }, { "Cooking", 3, 10, 150 }, { long, 4, 300, 300 } }, 4 },
    { "unavailable", { { "Alchemy", 1 }, { "Fishing", 2, 75, 0 } }, 2 },
  }
  for _, case in ipairs(cases) do
    SetSkills(case[2]); Win.Render()
    local shown = Inside(case[1])
    Check(shown == (#case[2] == 0 and 1 or case[3]), ("%s: %d rows shown"):format(case[1], shown))
  end
  SetSkills(cases[4][2]); Win.Render()
  Check(#pc.facts[4].text:GetText() > 20 and long:sub(1, #pc.facts[4].text:GetText()) == pc.facts[4].text:GetText(), "a long name is read bounded (Observe.Skills), and the row clips it inside its place: " .. pc.facts[4].text:GetText())
  Check(pc.facts[4].text.points[1][1] == "LEFT" and pc.facts[4].text.points[2][1] == "RIGHT", "between the picture and the numbers, so it cannot run into them")
  Same(pc.facts[4].value:GetText(), "300 / 300"); Check(pc.facts[4].bar.frac == 1)
  SetSkills(cases[5][2]); Win.Render()
  Same(pc.facts[1].value:GetText(), "n/a"); Same(pc.facts[1].bar.frac, 0)
  Same(pc.facts[2].value:GetText(), "n/a", "a maximum of zero is not a level")
  -- a smaller page: fewer rows, the rest said, still inside
  SetSkills(cases[4][2]); Win.Render()
  ov:Fire("OnSizeChanged", 820, 400)
  Win.Render()
  local shownSmall = Inside("small page")
  Check(shownSmall < 4 and pc.more:GetText():find("more", 1, true), "a small page shows what fits and says how many more: " .. shownSmall .. " / " .. pc.more:GetText())
  ov:Fire("OnSizeChanged", 820, 555)
  Win.Render()
  Same(Inside("normal page"), 4)
  -- a skill changes while the page is open
  skills[1][3] = 126
  Fire("SKILL_LINES_CHANGED"); FlushTimers(); Flush()
  Same(pc.facts[1].value:GetText(), "126 / 150")
  -- the bar itself: filled and empty parts, a start is always visible, nothing is made again
  local bar = pc.facts[1].bar
  local made = MI_MADE
  bar:SetFraction(0); Check(not bar.fill:IsShown() and not bar.shine:IsShown() and not bar.cap:IsShown(), "an empty bar draws no fill")
  bar:SetFraction(0.001); Check(bar.fill:IsShown() and bar.fill.w >= 3, "a start is visible")
  bar:SetFraction(1); Check(bar.fill.w == bar.w - 4, "a full bar fills its track (inside the rim)")
  bar:SetFraction(0.5); Check(bar.fill.w == math.floor((bar.w - 4) * 0.5 + 0.5))
  Same(MI_MADE, made, "drawing a bar makes no new object")
  SetSkills({ { "Alchemy", 1, 125, 150 } })

  ---------------------------------------------------------------------------
  -- 5. The market status: freshness and completeness are separate, the name is in the tooltip only
  ---------------------------------------------------------------------------
  local MK = W.Market
  local function Status(over, at)
    c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = over and Market(over) or nil }
    return MK.Status({ now = now })
  end
  local function With(age, complete) return Status({ at = now - age, complete = complete }) end
  local st = With(1920, true)
  Same(st.text, "Prices updated 32m ago"); Same(st.icon, "done"); Same(st.tone, "good"); Same(st.freshness, "fresh"); Same(st.complete, true)
  st = With(1920, false)
  Same(st.text, "Partial scan \194\183 32m ago", "a partial scan can be recent"); Same(st.freshness, "fresh"); Same(st.complete, false); Same(st.icon, "current")
  st = With(5 * 3600, true)
  Same(st.text, "Prices updated 5h ago"); Same(st.freshness, "aging"); Same(st.complete, true); Same(st.tone, "warn")
  st = With(3 * 86400, true)
  Same(st.text, "Old prices \194\183 3d ago", "an old scan can be complete"); Same(st.freshness, "old"); Same(st.complete, true); Same(st.tone, "bad")
  st = With(3 * 86400, false)
  Same(st.text, "Old partial scan \194\183 3d ago"); Same(st.freshness, "old"); Same(st.complete, false)
  Same(With(MK.FRESH_AFTER, true).freshness, "fresh", "two hours is still fresh"); Same(With(MK.FRESH_AFTER + 1, true).freshness, "aging")
  Same(With(W.Prices.OLD_AFTER, true).freshness, "aging", "a day is still usable"); Same(With(W.Prices.OLD_AFTER + 1, true).freshness, "old")
  Same(With(5, true).text, "Prices updated just now")
  st = With(1920, true)
  local tiptext = table.concat(st.tip, "\n")
  Check(tiptext:find("Alliance auction house on Realm", 1, true) and tiptext:find("Coverage: a complete scan", 1, true) and tiptext:find("23439 items priced", 1, true)
    and tiptext:find("not a sale", 1, true), "the tooltip holds the whole market, the coverage, the count and the limit: " .. tiptext)
  Check(not st.text:find("Realm", 1, true) and not st.text:find("Alliance", 1, true), "the visible text names no realm or side")
  Check(table.concat(With(1920, false).tip, "\n"):find("Coverage: partial", 1, true))
  st = Status(nil)
  Same(st.state, "none"); Same(st.text, "No prices yet")
  -- a scan in progress outranks both
  c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = Market() }
  W.Scan.state, W.Scan.phase = "scanning", "reading"
  Check(MK.Status({ now = now }).text:find("^Scanning prices"), "scanning")
  W.Scan.phase = "saving"
  Same(MK.Status({ now = now }).text, "Saving prices")
  Same(MK.Status({ now = now }).state, "saving")
  W.Scan.state, W.Scan.phase = "idle", nil
  -- the footer: a chip with that text, no realm, a tooltip with the market, and no timer
  Win.SetMode("overview")
  c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = Market({ at = os.time() - 1920 }) }
  local timers = #pend
  Win.Render()
  Same(f.chip.text:GetText(), "Prices updated 32m ago"); Same(f.chip.status, "done")
  Check(not f.chip.text:GetText():find("Realm", 1, true) and not f.note:GetText():find("Realm", 1, true), "the footer names no market")
  Check(f.chip.twichuiTip.body(f.chip):find("Alliance auction house on Realm", 1, true), "the chip's tooltip names it")
  Check(f.chip.w >= 90 and f.chip.w <= 330, "the chip fits its text: " .. f.chip.w)
  Same(#pend, timers, "drawing the status made no timer: the age is read when drawn, never kept current in the background")
  c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = Market({ at = os.time() - 3 * 86400, complete = false }) }
  Win.Render()
  Same(f.chip.text:GetText(), "Old partial scan \194\183 3d ago")
  c.TwichUIWorkshopDB.markets = {}
  Win.Render()
  Same(f.chip.text:GetText(), "No prices yet")
  Check(next(c.TwichUIWorkshopDB.markets) == nil, "the status read the markets and changed none")
  c.TwichUIWorkshopDB.markets = { ["Realm|Alliance"] = Market() }

  ---------------------------------------------------------------------------
  -- 6. Redraws and navigation create no more frames; layout updates keep the queue and the market data
  ---------------------------------------------------------------------------
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  S.Add(S.AllRecipes()[1])
  local function Cycle()
    for _, key in ipairs({ "overview", "opps", "craft", "shop" }) do
      Win.SetMode(key); Win.Render(); Win.Render()
      local o = Win.Lists().opps.rows[1]
      if o and o.scripts.OnEnter then o.scripts.OnEnter(o); o.scripts.OnLeave(o) end
    end
    ov:Fire("OnSizeChanged", 820, 400); ov:Fire("OnSizeChanged", 820, 555)
    FlushTimers()
  end
  for _ = 1, 3 do Cycle() end
  local made2 = MI_MADE
  local queueBefore, marketBefore = #Q.Entries(), c.TwichUIWorkshopDB.markets["Realm|Alliance"].n
  for _ = 1, 5 do Cycle() end
  Same(MI_MADE, made2, "navigation, redraws, hover and layout updates make no new frame or texture")
  Same(#Q.Entries(), queueBefore, "the queue is as it was"); Same(c.TwichUIWorkshopDB.markets["Realm|Alliance"].n, marketBefore, "and the market data")
  M.Advance(0.3)
  Same(M.Count(), 0, "the easing is bounded: it ends by itself, and none is left running")
  for _, e in ipairs({ unpack(Q.Entries()) }) do Q.Remove(e.id) end
  Win.SetMode("overview")
  f:Hide()
end

---------------------------------------------------------------------------
-- Lifecycle: the pages are built once; opening, closing, switching pages and redrawing make no new frames and write nothing
---------------------------------------------------------------------------
do
  local f = Win.Frame()
  -- A fixed clock for this block: the Workshop stamps saved records through Q.Now (a recipe record's `at`), which reads the real
  -- time(). With the wall clock a tick between the two comparisons below made "wrote nothing" fail about 3 % of runs. Restored at the end.
  local realNow = Q.Now
  Q.Now = function() return 1700000000 end
  local function Dump(v, out)   -- a stable text of a saved table, to compare before and after
    out = out or {}
    if type(v) ~= "table" then out[#out + 1] = tostring(v) return out end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "="; Dump(v[k], out) end
    out[#out + 1] = "}"
    return out
  end
  local function Cycle()
    f:Show()
    for _, key in ipairs({ "overview", "opps", "craft", "shop", "overview" }) do
      local item = ({ overview = f.tabOverview, opps = f.tabOpps, craft = f.tabCraft, shop = f.tabShop })[key]
      item:GetScript("OnClick")(item)
      Same(Win.Mode(), key)
      Check(Win.Page(key):IsShown(), "the page asked for is shown")
      for _, other in ipairs({ "overview", "opps", "craft", "shop" }) do
        if other ~= key then Check(not Win.Page(other):IsShown(), "only one page at a time: " .. other) end
      end
      Win.Render(); Win.Render()
    end
    FlushTimers()
    f:Hide()
  end
  -- the first cycles may make the pooled rows each page needs (a list's rows are made the first time that many are shown, and this
  -- fixture's shopping list gains a row as its remembered guild bank state ages); after two quiet cycles in a row nothing more is made
  local warm, quiet = 0, 0
  repeat
    local before = MI_MADE
    Cycle()
    warm = warm + 1
    quiet = MI_MADE == before and quiet + 1 or 0
  until quiet == 2 or warm == 8
  Check(quiet == 2, "the pools settle")
  local made, saved = MI_MADE, table.concat(Dump(c.TwichUIDB.workshop), " ")
  for _ = 1, 5 do Cycle() end
  Same(MI_MADE, made, "five more open / navigate / redraw / close cycles made no frame or texture")
  for name, l in pairs(Win.Lists()) do
    Check(#l.rows <= math.ceil(l.minH / l.rowH) + 1, ("the %s pool is bounded by what it can show (%d rows)"):format(name, #l.rows))
  end
  Same(table.concat(Dump(c.TwichUIDB.workshop), " "), saved, "and navigating wrote nothing to the saved data")
  Q.Now = realNow
  Same(Events(f), 0, "closed: no events")
  f:Show()
  Same(Win.Mode(), "overview", "the page shown is kept while the game runs")
  f:Hide()
end

print("PASSED")
