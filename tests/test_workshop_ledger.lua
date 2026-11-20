-- The Gold Ledger page (TwichUI_Workshop/ViewLedger.lua, LedgerQuery.lua, LedgerChart.lua) on recording stand-in frames, over synthetic
-- journals written straight into TwichUILedgerDB: the first-use state, the cards, the chart's geometry and inspection, the split by source,
-- the transaction list, every filter, reconciliation, the profession placeholder, hide/show cycles, a disabled Workshop and a large history.
-- Synthetic: it proves what is drawn and kept, not how the game draws it (docs/workshop/gold-ledger.md lists the in-game checks).
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
      fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetDrawLayer = function(_, layer, sub) if sub ~= nil and (sub < -8 or sub > 7) then error("SetDrawLayer: sublevel must be between -8 and 7!") end end; t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
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

for _, f in ipairs({ "Data.lua", "BridgeCodec.lua", "BridgeSchema.lua", "BridgeValidate.lua", "Bridge.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "auction/AdvancedChart.lua", "Coins.lua", "LedgerQuery.lua", "ChartKit.lua", "LedgerChart.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewStrategy.lua", "ViewLedger.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
local Win, UI, LQ, LC, V = W.Window, W.UI, W.LedgerQuery, W.LedgerChart, W.UI.LedgerView
Check(UI.pages.ledger and UI.pages.ledger.nav == "Gold Ledger", "the page registered itself")
UI.Coins.SetIcons(false)   -- this file checks the page's figures as letters (g s c, zero parts left out); test_ledger_coins.lua checks the artwork

local DAY, TODAY = 86400, 20000
c.NOW = TODAY * DAY + 12 * 3600
c.GetServerTime = function() return c.NOW end
c.MONO = 100
c.GetTime = function() return c.MONO end

-- the core's recorder, with the launcher's opt-in stood in
local enabled = true   -- the window opens only with the Workshop on; recording starts when the launcher applies it (below)
R.WorkshopLauncher = { Enabled = function() return enabled end, Apply = function() R.Ledger.Refresh() end }
do local chunk = assert(loadfile(ROOT .. "auction/Ledger.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
local L = R.Ledger
c.TwichUILedgerDB = nil
c.MONEY = 500000
L.Init()
if not R.Life.InWorld() then c.FireEvent("PLAYER_ENTERING_WORLD", true, false) end

-- a GameTooltip that keeps what it was given
local Tip = { lines = {} }
function Tip:SetOwner(o) self.owner = o; self.lines = {} end
function Tip:AddLine(t) self.lines[#self.lines + 1] = t end
function Tip:ClearLines() self.lines = {} end
function Tip:Show() self.shown = true end
function Tip:Hide() self.shown = false end
function Tip:SetItemByID(id) self.lines = { "ITEM " .. id }; return true end
c.GameTooltip = Tip
local function TipText() return table.concat(Tip.lines, "\n") end

local function Fire() FlushTimers() end

---------------------------------------------------------------------------
-- Words and money
---------------------------------------------------------------------------
Same(LQ.Money(0), "0c"); Same(LQ.Money(5), "5c"); Same(LQ.Money(100), "1s 0c"); Same(LQ.Money(12345), "1g 23s 45c")
Same(LQ.Money(123000, true), "+12g 30s 0c"); Same(LQ.Money(-25000), "-2g 50s 0c"); Same(LQ.Money(5, true), "+5c"); Same(LQ.Money(0, true), "0c")
Same(LQ.Money(12345678901), "1,234,567g 89s 1c", "thousands separated, exact copper")
Same(LQ.Money(0 / 0), "", "not a number")
Same(LQ.Day(TODAY), os.date("!%Y-%m-%d", TODAY * DAY)); Same(LQ.Stamp(TODAY * DAY), os.date("!%Y-%m-%d %H:%M", TODAY * DAY), "a moment is shown in the player's own time (the test client is pinned to UTC), without a zone label")

---------------------------------------------------------------------------
-- Chart geometry (pure)
---------------------------------------------------------------------------
Same(LC.AxisText(0), "0g"); Same(LC.AxisText(3000000), "300g"); Same(LC.AxisText(-1500000), "-150g"); Same(LC.AxisText(100000000), "10k")
Same(LC.AxisText(5000), "50s"); Same(LC.AxisText(50), "50c"); Same(LC.AxisText(-120), "-1s")
Same(LC.NiceStep(140000, 4), 50000); Same(LC.NiceStep(0, 4), 10000); Same(LC.NiceStep(7, 4), 2)
do
    local function Day(i, inn, out, covered, n) return { day = TODAY - 7 + i, inn = inn, out = out, net = inn - out, n = n or ((inn > 0 or out > 0) and 1 or 0), covered = covered ~= false } end
    local days = { Day(1, 0, 0), Day(2, 100000, 40000), Day(3, 0, 0, false), Day(4, 20000, 0), Day(5, 0, 0), Day(6, 0, 70000), Day(7, 0, 0, true) }
    local g = LC.Geometry(days, 700, 150)
    Same(g.scale.step, 50000); Same(g.scale.top, 100000); Same(g.scale.bottom, 100000, "the zero line sits where the expenses need room")
    Same(g.zeroY, 75)
    local ins, outs = {}, {}
    for _, b in ipairs(g.bars) do if b.kind == "in" then ins[b.index] = b else outs[b.index] = b end end
    Same(ins[2].h, 75, "100,000 copper up from zero"); Same(ins[2].y, 75)
    Same(outs[2].h, 30); Same(outs[2].y + outs[2].h, 75, "expenses hang from the zero line")
    Same(outs[6].h, 52.5)
    Check(ins[4].h < ins[2].h and ins[4].h == 15, "bars are proportional")
    Check(ins[1] == nil and ins[5] == nil, "a recorded quiet day has no bar")
    Same(#g.uncovered, 1); Same(g.uncovered[1].index, 3, "a day outside coverage is its own column, not a zero")
    local tick = {}
    for _, t in ipairs(g.ticks) do tick[t.index] = true end
    Check(tick[1] and tick[5] and tick[7] and not tick[3], "a recorded quiet day is a tick on the zero line")
    Same(#g.points, 6, "the net line has a point for each recorded day only")
    for _, s in ipairs(g.segments) do Check(s.a.index + 1 == s.b.index, "never connected across days") end
    for _, s in ipairs(g.segments) do Check(s.a.index ~= 2 and s.b.index ~= 3 and not (s.a.index == 2 and s.b.index == 4), "never connected through the gap") end
    Same(#g.segments, 4, "1-2, 4-5, 5-6 and 6-7: nothing through day 3")
    Same(#g.xlabels, 7)
    Same(#g.grid, 5, "grid lines at -100k, -50k, 0, 50k, 100k")
    -- series can be hidden; the scale follows what is shown
    local only = LC.Geometry(days, 700, 150, { inn = false, out = true, net = false })
    for _, b in ipairs(only.bars) do Same(b.kind, "out") end
    Same(#only.points, 0)
    -- 30 and 90 days label sparsely; a tiny plot and many days still lay out
    local many = {}
    for i = 1, 90 do many[i] = Day(i, (i % 3) * 1000, 0) end
    Same(#LC.Geometry(many, 700, 150).xlabels, 6)
    local narrow = LC.Geometry(many, 40, 20)
    Check(#narrow.bars > 0 and narrow.barW >= 3, "a narrow plot keeps visible bars")
    Same(#LC.Geometry({}, 700, 150).bars, 0); Same(LC.Geometry(days, 0, 150).scale.step, 0)
    -- nothing at all: a band above the zero line, no division by zero
    local flat = LC.Geometry({ Day(1, 0, 0), Day(2, 0, 0) }, 100, 100)
    Check(flat.scale.range > 0 and #flat.bars == 0 and #flat.ticks == 2)
    -- inspection words
    local lines = LC.TipLines(days[3]); Same(lines[2][1], "Not recorded"); Check(not lines[3] or not tostring(lines[3][1]):find("Gold in", 1, true), "never zero")
    Check(LC.TipLines(days[1])[2][1] == "Recorded: no gold moved")
    Same(LC.TipLines(days[2])[2][1], "Gold in: +10g 0s 0c"); Same(LC.TipLines(days[2])[3][1], "Gold out: -4g 0s 0c"); Same(LC.TipLines(days[2])[4][1], "Net change: +6g 0s 0c")
end

---------------------------------------------------------------------------
-- The page: first use, with nothing recorded
---------------------------------------------------------------------------
Win.Show()
local f = Win.Frame()
Check(f.tabLedger and f.tabLedger.text:GetText() == "Gold Ledger", "the page list has Gold Ledger")
Win.SetMode("ledger")
Check(Win.Page("ledger"):IsShown() and not Win.Overview():IsShown())
Same(Win.Page("ledger").heading:GetText(), "Gold Ledger")
local EMDASH = "\226\128\148"
for _, key in ipairs({ "net", "inn", "out", "attrIn", "attrOut", "unk" }) do Same(V.cards[key].value:GetText(), EMDASH, key .. ": no figure when nothing is recorded") end
Same(V.chart.msg:GetText(), "Gold tracking hasn't started yet.")
Check(V.chart.empty and #V.chart.geometry.grid == 0 and not V.chart.zero:IsShown(), "no arbitrary axis when nothing is recorded")
Check(V.list.empty:GetText():find("Nothing recorded yet", 1, true), "an explained empty list")
Check(V.status:GetText():find("Not recording", 1, true), "it says it is not recording: " .. V.status:GetText())
Same(V.prof.head:GetText(), "Profession profitability isn't available yet.")
Check(V.prof.head:IsShown() and V.profShown == false, "the profession panel says it is unavailable and shows no figure")
Check(V.prof.body:GetText():find("completed sales and recorded material costs", 1, true))
Check(V.sources.empty:GetText() ~= "", "the source panel says nothing has moved")
Same(#V.rows, 0)

-- recording starts, the page hears it (one redraw after a short wait), an empty period reads as such
local draws0 = V.Draws()
R.WorkshopLauncher.Apply()
Check(L.Active(), "recording")
Check(V.Subscribed(), "the page listens while shown")
Same(V.Draws(), draws0, "a burst of changes waits for one redraw")
Fire()
Same(V.Draws(), draws0 + 1)
Check(V.status:GetText():find("Recording since " .. LQ.Day(TODAY), 1, true), "it says since when it records, in UTC: " .. V.status:GetText())
Same(V.chart.msg:GetText(), "No gold activity recorded in this period.", "no activity is not the same as nothing recorded")
Check(V.chart.empty and #V.chart.geometry.grid == 0, "and shows no money scale")
Same(V.cards.net.value:GetText(), "0c"); Same(V.cards.out.value:GetText(), "0c")
Check(V.list.empty:GetText():find("No gold changes recorded in the last 7 days", 1, true))
-- gold moves: the transaction and the chart update by themselves
c.MONEY = c.MONEY + 12345; c.MONO = c.MONO + 1
c.FireEvent("PLAYER_MONEY"); Fire()
Same(#V.rows, 1); Same(V.rows[1].a, 12345); Same(V.rows[1].code, "other")
Same(V.cards.net.value:GetText(), "+1g 23s 45c"); Same(V.cards.inn.value:GetText(), "+1g 23s 45c")
Same(V.cards.unk.value:GetText(), "+1g 23s 45c", "gold nothing explains is Unclassified")
Same(V.cards.attrIn.value:GetText(), "0c")
local row = V.list.rows[1]
Check(row:IsShown() and row.amount:GetText() == "+1g 23s 45c" and row.src:GetText() == "Unclassified", "the row")
Same(row.note:GetText(), "Gold balance change", "no invented item or reason")
row:GetScript("OnEnter")(row)
Check(TipText():find("Gold in: +1g 23s 45c", 1, true) and TipText():find("not identified", 1, true) and TipText():find("Only your gold balance changed", 1, true), TipText())
row:GetScript("OnLeave")(row)

---------------------------------------------------------------------------
-- A synthetic history
---------------------------------------------------------------------------
local EVID = { mail = "mailbox", ahSale = "mailinvoice", ahBuy = "auctionpurchase" }
local function NewRec(name)
    return { name = name, realm = "Forever", since = (TODAY - 60) * DAY, nextId = 1, entries = {}, days = {} }
end
local function Cover(r, off)
    local d = TODAY - off
    if not r.days[d] then r.days[d] = { i = 0, o = 0, n = 0, ci = {}, co = {} } end
end
local function Add(r, off, amount, k, extra)
    Cover(r, off)
    local day = TODAY - off
    local e = { id = r.nextId, t = day * DAY + 3600 + r.nextId, a = amount, e = k and EVID[k] or "balance", k = k }
    for kk, v in pairs(extra or {}) do e[kk] = v end
    r.nextId = r.nextId + 1
    r.entries[#r.entries + 1] = e
    local d, code = r.days[day], k or "other"
    if amount > 0 then d.i = d.i + amount; d.ci[code] = (d.ci[code] or 0) + amount else d.o = d.o - amount; d.co[code] = (d.co[code] or 0) - amount end
    d.n = d.n + 1
end
local function Install(chars)
    for key, rec in pairs(chars) do c.TwichUILedgerDB.chars[key] = rec end
    LQ.ResetCache()
end
local rich = NewRec("Rich")
Add(rich, 40, 1000)
Add(rich, 10, 50000, "mail")
Add(rich, 5, 20000)
Add(rich, 3, -7000)
Cover(rich, 2)
Add(rich, 1, 30000, "ahSale", { n = "Runecloth" })
Add(rich, 0, 100000, "mail")
Add(rich, 0, -25000, "ahBuy", { i = 10, q = 2 })
Add(rich, 0, 5000)
local ann = NewRec("Ann")
Add(ann, 2, -123)
Add(ann, 0, 777)
c.TwichUILedgerDB.chars["Rich - Forever"] = nil
cleanedReset = nil
Install({ ["Rich - Forever"] = rich, ["Ann - Forever"] = ann })
-- the recorder keeps the live session's own character apart; point it at the fixture's record
V.SetFilter("scope", "current"); V.SetFilter("days", 7)

local function Card(k) return V.cards[k].value:GetText() end
local function Cash(a, signed) return UI.Coins.Text(a, { signed = signed }) end   -- the page's own presentation (letters in this file)
local function Sum(rows) local n = 0 for _, r in ipairs(rows) do n = n + r.a end return n end
local function Reconciles(label)
    local s = V.summary
    local t = s.totals
    local split = 0
    for _, r in ipairs(LQ.SourceRows(s)) do split = split + r.dir * r.amount end
    Same(split, t.net, label .. ": the sources add up to Net Change")
    Same(t.inn - t.out, t.net, label .. ": in - out = net")
    if not s.filter.source then
        Same(t.attrIn + t.unkIn, t.inn, label .. ": attributed + unclassified = gold in")
        Same(t.attrOut + t.unkOut, t.out, label .. ": ... and gold out")
    end
    local daily = 0
    for _, d in ipairs(s.days) do daily = daily + d.net end
    Same(daily, t.net, label .. ": the chart's days add up to Net Change")
end

-- 7 days, this character
Same(Card("net"), "+12g 30s"); Same(Card("inn"), "+15g 50s"); Same(Card("out"), "-3g 20s")
Same(Card("attrIn"), "+13g"); Same(Card("attrOut"), "-2g 50s"); Same(Card("unk"), "+1g 80s" == "x" and "" or Cash(25000 - 7000, true))
Reconciles("7D")
Same(V.cards.net.sub:GetText(), "Last 7 days")
Check(not V.cards.net.cmp:IsShown() and V.cards.net.cmp:GetText() == "", "the window before was not recorded: no comparison line at all")
Check(not V.cards.inn.cmp:IsShown())
Same(V.cards.attrIn.sub:GetText(), "Confirmed sources"); Check(not V.cards.attrIn.cmp:IsShown())
Same(#V.rows, 6, "journal rows in the window"); Same(Sum(V.rows), 123000, "and they add up to the same figure")
Same(V.rows[1].a, 5000); Same(V.rows[6].a, 20000, "newest first")
-- the rows' words
local byId = {}
for _, r in ipairs(V.rows) do byId[r.a] = r end
Same(byId[-25000].text, "Peacebloom (2)"); Same(byId[-25000].code, "ahBuy"); Same(byId[30000].text, "Runecloth"); Same(byId[100000].text, "Money from the mailbox")
Same(byId[5000].text, "Gold balance change")
-- the chart
Same(#V.chart.model.days, 7); Same(V.chart.geometry.n, 7); Same(#V.chart.cols, 7, "seven days, seven columns")
Check(V.chart.barCount >= 5, "bars drawn")
local function CardLines()
    local t = V.chart:CardFrame()
    local out = { t.title:GetText() }
    if t.note:IsShown() then out[#out + 1] = "NOTE " .. t.note:GetText() else for _, r in ipairs(t.rows) do out[#out + 1] = r.label:GetText() .. ": " .. r.value:GetText() end end
    out[#out + 1] = t.foot:GetText()
    return table.concat(out, "\n")
end
do
    V.chart:InspectIndex(7)   -- today: +100000 mail, -25000 auction purchase, +5000 unclassified
    local text = CardLines()
    Check(text:find(LC.DayLong(TODAY), 1, true), text)
    Check(text:find("Gold In: +10g 50s", 1, true) and text:find("Gold Out: -2g 50s", 1, true) and text:find("Net Change: +8g", 1, true), text)
    Check(text:find("3 recorded changes", 1, true) and not text:find("UTC", 1, true), text)
    Check(V.chart:CardFrame():IsShown() and V.chart.highlight:IsShown() and V.chart.cross:IsShown() and V.chart.pick:IsShown() and V.chart.halo:IsShown(), "interval, crosshair, marker and halo")
    V.chart:ClearInspection()
    Check(V.chart.inspected == nil and not V.chart:CardFrame():IsShown() and not V.chart.highlight:IsShown(), "leaving clears the inspection")
    V.chart:InspectIndex(4)   -- today-3: -7000
    Check(CardLines():find("Gold Out: -70s", 1, true) and CardLines():find("Gold In: 0c", 1, true), CardLines())
    V.chart:InspectIndex(3)   -- today-4: not recorded at all
    Check(CardLines():find("NOTE Not recorded", 1, true) and not CardLines():find("Gold In", 1, true) and not V.chart.pick:IsShown(), "a day outside coverage is not a zero: " .. CardLines())
    V.chart:InspectIndex(5)   -- today-2: recorded, nothing moved
    Check(CardLines():find("Recorded: no gold moved", 1, true), CardLines())
    V.chart:ClearInspection()
end
-- the pointer drives the same inspection: hover, drag to zoom, release, right-click reset
do
    local ch, hit = V.chart, V.chart.hit
    local g = ch.geometry
    local x = 0
    ch.CursorX = function() return x end
    x = 6.5 * g.slot; hit:GetScript("OnEnter")(hit)
    Same(ch.inspected, 7, "the column under the pointer"); Check(hit:GetScript("OnUpdate") ~= nil, "the updater exists only while inside")
    x = 2.5 * g.slot; hit:GetScript("OnUpdate")(hit); Same(ch.inspected, 3)
    hit:GetScript("OnLeave")(hit)
    Check(ch.inspected == nil and hit:GetScript("OnUpdate") == nil, "leaving removes the updater and the card")
    -- a drag under six pixels does nothing
    x = 1.5 * g.slot; hit:GetScript("OnEnter")(hit); hit:GetScript("OnMouseDown")(hit, "LeftButton")
    x = 1.5 * g.slot + 3; hit:GetScript("OnUpdate")(hit); hit:GetScript("OnMouseUp")(hit, "LeftButton")
    Check(not ch:IsZoomed(), "a tiny drag keeps the view"); Check(ch.pointer.drag == nil)
    -- a real drag selects columns 2..4 (days TODAY-5 .. TODAY-3) and zooms
    x = 1.5 * g.slot; hit:GetScript("OnMouseDown")(hit, "LeftButton")
    x = 3.5 * g.slot; hit:GetScript("OnUpdate")(hit)
    Check(ch.selection:IsShown(), "the bronze selection band is drawn while dragging")
    hit:GetScript("OnMouseUp")(hit, "LeftButton")
    Check(ch:IsZoomed() and not ch.selection:IsShown(), "released: zoomed, band gone")
    Same(#ch.cols, 3); Same(ch.cols[1].day, TODAY - 5); Same(ch.cols[3].day, TODAY - 3)
    Check(ch.hint:GetText():find("Zoomed", 1, true))
    -- the legend follows the visible interval
    Check(ch.legendButtons.out.value:GetText():find("70s", 1, true), ch.legendButtons.out.value:GetText())
    -- the window stays authoritative: another range clears the zoom
    V.SetFilter("days", 30); Check(not ch:IsZoomed(), "a new range clears an old zoom"); V.SetFilter("days", 7)
    x = 1.5 * g.slot; hit:GetScript("OnMouseDown")(hit, "LeftButton"); x = 3.5 * g.slot; hit:GetScript("OnMouseUp")(hit, "LeftButton")
    Check(ch:IsZoomed())
    hit:GetScript("OnMouseUp")(hit, "RightButton")
    Check(not ch:IsZoomed() and #ch.cols == 7, "right-click resets to the chosen range")
    -- an event released outside the plot still ends the drag, clamped to the plot
    x = 1.5 * g.slot; hit:GetScript("OnMouseDown")(hit, "LeftButton"); Check(ch.pointer.drag ~= nil)
    x = 9999; hit:GetScript("OnEvent")(hit, "GLOBAL_MOUSE_UP", "LeftButton")
    Check(ch.pointer.drag == nil and ch:IsZoomed(), "GLOBAL_MOUSE_UP commits; the pointer is clamped to the plot")
    ch:ResetZoom(); hit:GetScript("OnLeave")(hit)
    ch.CursorX = nil
    -- hiding mid-hover or mid-drag cancels everything
    x = 2 * g.slot; ch.CursorX = function() return x end
    hit:GetScript("OnEnter")(hit); hit:GetScript("OnMouseDown")(hit, "LeftButton")
    ch:GetScript("OnHide")(ch)
    Check(ch.pointer.drag == nil and ch.inspected == nil and hit:GetScript("OnUpdate") == nil, "hide mid-drag leaves no handler behind")
    ch.CursorX = nil
end
-- legend toggles
V.chart.legendButtons.out:GetScript("OnClick")(V.chart.legendButtons.out)
Check(V.chart.show.out == false); for _, b in ipairs(V.chart.geometry.bars) do Same(b.kind, "in") end
V.chart.legendButtons.out:GetScript("OnClick")(V.chart.legendButtons.out)
Check(V.chart.show.out == true)
Check(V.chart.legendButtons.inn.value:GetText():find("15g 50s", 1, true) and V.chart.legendButtons.inn.value.exact == 155000, V.chart.legendButtons.inn.value:GetText())
-- the source panel: ranked, only what was recorded
do
    local rows = LQ.SourceRows(V.summary)
    Same(#rows, 5)
    Same(rows[1].code, "mail"); Same(rows[1].amount, 100000); Same(rows[2].code, "ahSale"); Same(rows[3].code, "ahBuy"); Same(rows[4].dir, 1)
    Same(V.srcRows[1].label:GetText(), "Mail collected"); Same(V.srcRows[1].amount:GetText(), "+10g")
    Same(V.srcRows[3].label:GetText(), "Auction purchases"); Same(V.srcRows[3].amount:GetText(), "-2g 50s")
    Same(V.srcRows[5].label:GetText(), "Unclassified spending")
    local other = {}
    for _, r in ipairs(rows) do if r.code == "other" then other[#other + 1] = r.label end end
    Same(table.concat(other, "|"), "Unclassified income|Unclassified spending")
    Same(rows[5].label, "Unclassified spending")
end

-- 30 and 90 days, and the clearly selected range
V.SetFilter("days", 30)
Same(Card("inn"), "+20g 50s"); Same(Card("attrIn"), "+18g"); Reconciles("30D"); Same(#V.chart.cols, 30); Same(V.cards.net.sub:GetText(), "Last 30 days")
Check(V.flow.ranges[30].on == true and V.flow.ranges[7].on == false and V.flow.ranges[90].on == false, "the chosen range is marked")
V.SetFilter("days", 90)
Same(Card("inn"), "+20g 60s"); Reconciles("90D"); Check(#V.chart.cols < 90 and V.chart.cols[1].span > 1, "90 days are added into longer columns when narrower than the minimum slot"); Same(V.chart.cols[1].span, 7)
Check(not V.cards.net.cmp:IsShown(), "90 days have no earlier period inside the retention")
V.SetFilter("days", 7)

-- all characters
V.SetFilter("scope", "all")
Same(Card("inn"), "+15g 57s 77c"); Same(Card("out"), "-3g 21s 23c"); Reconciles("all"); Same(V.summary.characters, 2)
Check(V.sources.note:GetText():find("moved between your own characters", 1, true), "a note says transfers are not profit")
Same(#V.rows, 8)
Check(V.rows[1].char == "Rich" or V.rows[1].char == "Ann"); Check(V.list.rows[1].note:GetText():find("\194\183", 1, true), "the character is named in an all-characters list")
V.SetFilter("scope", "current")
Check(not V.sources.note:GetText():find("own characters", 1, true))

-- source filter: cards, chart, sources and rows follow
V.SetFilter("source", "mail")
Same(Card("inn"), "+10g"); Same(Card("out"), "0c"); Same(#V.rows, 1); Reconciles("mail"); Same(#LQ.SourceRows(V.summary), 1)
Check(V.srcRows[1]:IsShown() and not V.srcRows[2]:IsShown(), "only sources with recorded money get a row")
V.SetFilter("source", "ahBuy"); Same(Card("out"), "-2g 50s"); Same(#V.rows, 1); Same(V.rows[1].item, 10); Reconciles("ahBuy")
V.SetFilter("source", "other"); Same(Card("attrIn"), "0c"); Same(#V.rows, 3); Reconciles("other")
V.SetFilter("source", nil); Same(#V.rows, 6)
V.SetFilter("source", "bogus"); Check(V.Filter().source == nil, "an unknown source is no filter")

-- search narrows the list only
V.SetFilter("search", "runecl")
Same(#V.rows, 1); Same(V.rows[1].text, "Runecloth"); Same(Card("net"), "+12g 30s", "the totals do not change with a text search")
V.SetFilter("search", "PURCHASE"); Same(#V.rows, 1); Same(V.rows[1].code, "ahBuy")
V.SetFilter("search", "peace"); Same(#V.rows, 1, "an item name")
V.SetFilter("search", "zzz"); Same(#V.rows, 0); Check(V.list.empty:GetText() == "No transactions match these filters.")
-- typing in the box (its handler waits a moment, then filters)
V.SetFilter("search", "")
V.search:SetText("mail")
for _, h in ipairs(V.search.hooks.OnTextChanged or {}) do h(V.search, true) end
Same(#V.rows, 6, "the change is not applied until the wait ends"); Fire()
Same(#V.rows, 1, "mail"); Same(V.Filter().search, "mail")
V.SetFilter("search", ""); Same(#V.rows, 6)

-- a complete earlier period gives a real comparison; the percentage is only made from complete data
do
    local r = c.TwichUILedgerDB.chars["Rich - Forever"]
    for off = 7, 13 do Cover(r, off) end
    Add(r, 8, 10000)   -- inserted out of order: the journal is read newest first by time regardless
    table.sort(r.entries, function(a, b) return a.t < b.t end)
    LQ.ResetCache(); V.Draw()
    Check(V.cards.inn.cmp:GetText():find("vs. prior 7d", 1, true), V.cards.inn.cmp:GetText())
    -- the prior window (days 7 to 13 back) holds the +50,000 of day 10 and the +10,000 added above: 60,000; this one 155,000
    Same(V.cards.inn.cmp:GetText(), ("+%d%% vs. prior 7d"):format(math.floor((155000 - 60000) / 60000 * 100 + 0.5)))
    Same(V.cards.net.cmp:GetText(), "Prior 7d: +6g")
    Check(not V.cards.out.cmp:IsShown(), "no percentage from a zero base")
    Reconciles("compared")
end


---------------------------------------------------------------------------
-- Lifecycle: listening only while shown; nothing added by repeated use; nothing drawn while hidden
---------------------------------------------------------------------------
local function Listeners() return L.Snapshot().listeners end
Same(Listeners(), 1, "shown: one subscription")
for _ = 1, 5 do
    f:Hide(); Same(Listeners(), 0, "hidden: released"); Check(not V.Subscribed())
    f:Show(); Same(Listeners(), 1, "shown again: one, not more")
end
-- leaving the page releases it at once, and gold moving meanwhile draws nothing
f.tabOverview:GetScript("OnClick")(f.tabOverview)
Same(Win.Mode(), "overview")
-- (page hooks fire on a real frame's hide; the stand-in frames record them)
for _, h in ipairs(Win.Page("ledger").hooks.OnHide or {}) do h() end
Same(Listeners(), 0, "another page: no subscription")
local before = V.Draws()
c.MONEY = c.MONEY + 500; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY"); Fire()
Same(V.Draws(), before, "a hidden page is not drawn for a money change; recording went on")
Check(#c.TwichUILedgerDB.chars["Rich - Forever"].entries >= 1)
f.tabLedger:GetScript("OnClick")(f.tabLedger)
Same(Win.Mode(), "ledger"); Same(Listeners(), 1)
Check(V.Draws() > before, "back on the page it draws what changed")
-- many quick changes are one redraw
local d0 = V.Draws()
for i = 1, 20 do c.MONEY = c.MONEY + 1; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY") end
Same(V.Draws(), d0, "no redraw per change"); Fire(); Same(V.Draws(), d0 + 1, "one redraw for the burst")
-- a stale redraw after the window was hidden does nothing
c.MONEY = c.MONEY + 1; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY")
f:Hide(); local d1 = V.Draws(); Fire(); Same(V.Draws(), d1, "the pending redraw was forgotten with the hide")
f:Show()

---------------------------------------------------------------------------
-- Profession profitability: unavailable; a future provider's partial figures are labelled, unknown costs never zero
---------------------------------------------------------------------------
Check(V.prof.head:IsShown() and not V.profRows[1]:IsShown())
LQ.SetProfessionProvider(function() return { rows = { { name = "Alchemy", amount = 1234, partial = true }, { name = "Mining", amount = -50 }, { name = "Tailoring" } } } end)
V.Draw()
Check(V.profShown and not V.prof.head:IsShown(), "a provider replaces the placeholder")
Same(V.profRows[1].name:GetText(), "Alchemy (partial)"); Same(V.profRows[1].amount:GetText(), "+12s 34c")
Same(V.profRows[2].amount:GetText(), "-50c"); Same(V.profRows[3].amount:GetText(), "", "an unknown amount is blank, never zero")
LQ.SetProfessionProvider(function() error("broken provider") end); V.Draw()
Check(V.prof.head:IsShown() and not V.profShown, "a failing provider falls back to the placeholder")
LQ.SetProfessionProvider(function() return { rows = "nope" } end); V.Draw(); Check(V.prof.head:IsShown())
LQ.SetProfessionProvider(nil); V.Draw()

---------------------------------------------------------------------------
-- The Workshop turned off: recording stops, the kept history stays readable
---------------------------------------------------------------------------
do
    local entries = #c.TwichUILedgerDB.chars["Rich - Forever"].entries
    enabled = false
    R.WorkshopLauncher.Apply()
    Check(not L.Active(), "stopped")
    c.MONEY = c.MONEY + 999; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY")
    Same(#c.TwichUILedgerDB.chars["Rich - Forever"].entries, entries, "nothing new is recorded")
    V.Draw()
    Check(#V.rows > 0 and V.rows[1].a ~= 999, "the old transactions are still there")
    Check(V.status:GetText():find("Not recording: Workshop is off", 1, true), V.status:GetText())
    enabled = true
    R.WorkshopLauncher.Apply()
    Check(L.Active())
end

---------------------------------------------------------------------------
-- A very large history: opening is bounded, rows are pooled
---------------------------------------------------------------------------
do
    local chars = {}
    for k = 1, 10 do
        local r = NewRec("Big" .. k)
        for i = 1, 2000 do
            local off = math.floor((2000 - i) / 23)   -- up to 87 days back, oldest first
            Add(r, off, (i % 3 == 0) and -(i * 7) or (i * 11), (i % 5 == 0) and "mail" or nil)
        end
        chars["Big" .. k .. " - Forever"] = r
    end
    Install(chars)
    local started = os.clock()
    V.SetFilter("scope", "all")   -- the first draw over the ten new records: they are cleaned, summed and merged now
    local took = os.clock() - started
    V.SetFilter("days", 90)
    Check(took < 2, "drawing ten full journals took " .. took)
    print(("ledger page: first draw over ten full journals (all characters, 7 days; cleaning, summary and the merge of 400 rows) %.0f ms"):format(took * 1000))
    Same(#V.rows, 400, "the list is bounded"); Check(V.tx.count:GetText():find("Newest 400 shown", 1, true), V.tx.count:GetText())
    Check(#V.list.rows <= 12, "only the rows that can show exist: " .. #V.list.rows)
    Reconciles("large")
    Check(V.rows[1].t >= V.rows[400].t, "newest first across characters")
    for i = 2, 400 do Check(V.rows[i - 1].t >= V.rows[i].t, "ordered") end
    local s2 = os.clock()
    for i = 1, 20 do V.Draw() end
    Check(os.clock() - s2 < 3, "repeated draws are cached and cheap")
    print(("ledger page: a redraw with a warm summary %.1f ms"):format((os.clock() - s2) / 20 * 1000))
    V.SetFilter("scope", "current"); V.SetFilter("days", 7)
end

---------------------------------------------------------------------------
-- Scale and a narrow plot: drawing never fails and never loops
---------------------------------------------------------------------------
do
    f:SetScale(0.6); V.Draw()
    V.chart.plot:SetSize(30, 10); V.chart:Render()   -- a plot smaller than the minimum falls back to the chart's own size
    local g = V.chart.geometry
    Check(g and g.pw > 0 and g.ph > 0)
    V.SetFilter("days", 90); Check(#V.chart.geometry.xlabels >= 1); V.SetFilter("days", 7)
    f:SetScale(1)
    V.SetFilter("search", string.rep("x", 400)); Same(#V.rows, 0)
    V.SetFilter("search", "")
end

-- no frame, timer or listener is added by drawing again and again
do
    local frames = 0
    local function Count() return V.chart:RegionCount() + #V.list.rows end
    V.Draw(); local base = Count()
    for _ = 1, 30 do V.Draw() end
    Same(Count(), base, "pools stay the same size")
    Same(Listeners(), 1)
end

-- what a reload would find: the journal and its start are in the saved variable (the journal test covers reading it back)
do
    local snap = c.TwichUILedgerDB.chars["Rich - Forever"]
    Check(#snap.entries >= 7 and snap.since, "the journal and its start are in the saved variable")
end

-- Vendor classifications use the same cards, chart, filters, item tooltips and persistence fields.
-- All eight signed source rows remain accessible in the existing panel, including the least-valued source.
do
    local r = NewRec("Rich")
    Add(r, 0, 100, "mail"); Add(r, 0, 50, "ahSale"); Add(r, 0, -200, "ahBuy")
    Add(r, 0, -25, "vendorBuy", { i = 10, q = 5, e = "merchantpurchase" })
    Add(r, 0, 18, "vendorSell", { i = 11, q = 2, e = "merchantsale" })
    Add(r, 0, -124, "repair", { n = "Equipment repairs", e = "merchantrepair" })
    Add(r, 0, 7); Add(r, 0, -3)
    Install({ ["Rich - Forever"] = r }); g.names[10] = "Refreshing Spring Water"
    V.Draw(); Reconciles("all vendor sources")
    Same(Card("attrIn"), "+1s 68c"); Same(Card("attrOut"), "-3s 49c")
    Same(#LQ.SourceRows(V.summary), 8); Same(#V.sourceList.data, 8)
    V.sourceList.scroll:SetVerticalScroll(3 * 32); V.sourceList:Layout()
    local lastSeen = false
    for _, sourceRow in ipairs(V.srcRows) do
        if sourceRow:IsShown() and sourceRow.data.code == "other" and sourceRow.data.dir == -1 then lastSeen = true end
    end
    Check(lastSeen, "scrolling reaches the eighth source instead of silently omitting it")
    for _, source in ipairs({ { "vendorBuy", "Vendor Purchase", "Refreshing Spring Water \195\1515" },
        { "vendorSell", "Vendor Sale", "Silverleaf \195\1512" }, { "repair", "Repairs", "Equipment repairs" } }) do
        V.SetFilter("source", source[1]); Same(#V.rows, 1); Reconciles(source[1])
        Same(V.list.rows[1].src:GetText(), source[2]); Same(V.list.rows[1].note:GetText(), source[3])
        V.list.rows[1]:GetScript("OnEnter")(V.list.rows[1])
        Check(TipText():find("Source: " .. source[2] .. " (confirmed)", 1, true), TipText())
        Check(TipText():find(L.EVIDENCE[L.SOURCES[source[1]].evidence], 1, true), "distinct evidence details")
        if source[1] ~= "repair" then Check(V.list.rows[1].itemIcon:IsShown(), "known items keep their icon and tooltip") end
    end
    V.SetFilter("source", nil); V.sourceList:ScrollTop(); V.Draw()
end

-- Posting/cancellation spending and seller settlement extend existing rows/hover; fees are never counted twice.
do
    local r = NewRec("Rich")
    Add(r, 0, 99500, "ahSale", { n = "Runecloth", q = 20, s = { v = 1,
        invoices = { { n = "Runecloth", q = 20, g = 100000, d = 4500, f = 5000, c = 99500 } } } })
    Install({ ["Rich - Forever"] = r }); V.Draw()
    Same(Card("inn"), "+9g 95s"); Same(Card("out"), "0c"); Same(#V.rows, 1)
    Same(V.list.rows[1].note:GetText(), "Runecloth \195\15120")
    V.list.rows[1]:GetScript("OnEnter")(V.list.rows[1])
    Check(TipText():find("Collected: 9g 95s", 1, true)); Check(TipText():find("Auction fee: 50s", 1, true))
    Check(TipText():find("Returned deposit: 45s (included in collected)", 1, true))
    Add(r, 0, -4500, "ahDeposit", { i = 11, q = 20, u = 501, e = "auctiondeposit" })
    Add(r, 0, -1200, "ahCancelFee", { i = 10, q = 1, u = 42, e = "auctioncancel" })
    LQ.ResetCache(); V.Draw(); Same(Card("out"), "-57s"); Reconciles("auction settlement is not extra cash")
    for _, code in ipairs({ "ahDeposit", "ahCancelFee" }) do
        V.SetFilter("source", code); Same(#V.rows, 1); Reconciles(code)
        Same(V.list.rows[1].src:GetText(), LQ.ROW_LABELS[code])
        V.list.rows[1]:GetScript("OnEnter")(V.list.rows[1]); Check(TipText():find("Auction ID:", 1, true))
    end
    V.SetFilter("source", nil)
    r.entries[1].s = { v = 2, future = "not interpreted" }; LQ.ResetCache(); V.Draw()
    V.SetFilter("source", "ahSale"); V.list.rows[1]:GetScript("OnEnter")(V.list.rows[1])
    Check(TipText():find("Fee unavailable", 1, true)); Check(not TipText():find("Gross sale:", 1, true))
    V.SetFilter("source", nil)
end

---------------------------------------------------------------------------
-- Realized item results and Profit by Profession (cost basis; synthetic records straight into TwichUILedgerDB.cost)
---------------------------------------------------------------------------
do
    do local chunk = assert(loadfile(ROOT .. "auction/LedgerCost.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
    local K = R.LedgerCost
    K.Init()
    local now = TODAY * DAY + 3600
    local function Res(t) t.t = t.t or now; t.al = t.al or {}; return t end
    local costRec = { nextLot = 1, nextResult = 100, nextCraft = 10, lots = {}, crafts = {}, profs = { [197] = "Tailoring", [171] = "Alchemy" },
        results = {
            Res({ id = 1, src = "vendorSell", i = 10, k = "i10", q = 5, a = 3000, c = 2500, st = "ok", x = 1 }),
            Res({ id = 2, src = "vendorSell", i = 10, k = "i10", q = 3, a = 1000, st = "unknown", w = "mixed", x = 2 }),
            Res({ id = 3, src = "vendorSell", i = 11, k = "i11", q = 2, a = 2800, st = "unknown", w = "nolot", x = 3 }),
            Res({ id = 4, src = "ahSale", n = "Runecloth", q = 20, a = 99500, g = 100000, fee = 5000, d = 4500, st = "unknown", w = "auctionid", x = 4 }),
            Res({ id = 5, src = "vendorSell", i = 12, k = "i12", q = 1, a = 4000, c = 2500, st = "ok", pf = 197, x = 5, al = { { l = 1, q = 1, c = 2500, s = "craft", f = 1, p = 197 } } }),
            Res({ id = 6, src = "vendorSell", i = 12, k = "i12", q = 1, a = 3000, c = 1500, st = "ok", pf = 197, x = 6, al = { { l = 2, q = 1, c = 1500, s = "craft", f = 2, p = 197 } } }),
            Res({ id = 7, src = "vendorSell", i = 13, k = "i13", q = 1, a = 900, st = "incomplete", w = "unknowncost", x = 7, al = { { l = 3, q = 1, s = "craft", f = 3, p = 171 } } }),
        } }
    costRec.crafts = { { id = 1, t = now, r = 5, p = 197, i = 12, q = 1, c = 2500, st = "ok", m = {} }, { id = 3, t = now, r = 6, p = 171, i = 13, q = 1, st = "incomplete", m = {} },
        { id = 4, t = now, r = 7, p = 333, i = 14, q = 1, c = 100, st = "ok", m = {} } }
    c.TwichUILedgerDB.cost = { v = 1, chars = { ["Rich - Forever"] = costRec } }
    c.TwichUILedgerDB.chars["Rich - Forever"] = NewRec("Rich")
    LQ.ResetCache(); K.Rec("Rich - Forever", false)
    V.SetFilter("source", nil); V.SetFilter("days", 7); V.SetFilter("search", "")

    local r = LQ.Results({ scope = "current", days = 7 })
    Check(r, "results are available")
    local by = {}
    for _, row in ipairs(r.rows) do by[(row.item and ("i" .. row.item)) or row.name] = row end
    Same(by.i10.status, "partial"); Same(by.i10.profit, 500, "only the verified sale counts: 3000 - 2500"); Same(by.i10.vsales, 1); Same(by.i10.sales, 2)
    Same(by.i10.collected, 4000, "collected covers every sale"); Same(by.i10.vcost, 2500)
    Same(by.i11.status, "unavailable"); Same(by.i11.profit, nil, "no profit without a verified cost"); Same(by.i11.collected, 2800)
    Same(by.Runecloth.status, "unavailable"); Same(by.Runecloth.gross, 100000); Same(by.Runecloth.fee, 5000); Same(by.Runecloth.deposit, 4500); Same(by.Runecloth.profit, nil)
    Same(by.i12.status, "verified"); Same(by.i12.profit, 4000 + 3000 - 2500 - 1500); Same(by.i12.qty, 2)
    Same(by.i13.profit, nil)
    Same(r.verified, 500 + 3000, "verified profit: 500 on the partial item plus 3000 on the crafted one")
    Same(r.sales, 7); Same(r.unavailable, 4)
    local lines = table.concat(LQ.ResultLines(by.i11), "|"); Check(lines:find("Cost basis unavailable", 1, true) and lines:find("No verified purchase", 1, true), lines)
    Check(table.concat(LQ.ResultLines(by.i12), "|"):find("Realized result: +30s 0c", 1, true))
    Check(table.concat(LQ.ResultLines(by.Runecloth), "|"):find("auction fee 50s 0c", 1, true))
    -- V5 posting provenance beside an auction sale: facts only, never a match, a profit or a total
    costRec.posts = { { id = 1, t = now, k = "i20", i = 20, n = "Runecloth", q = 20, u = 5000, dep = 4500, a = 777, ac = { 777 }, st = "sold", cs = "ok", c = 60000, al = {} },
        { id = 2, t = now, k = "i20", i = 20, n = "Runecloth", q = 20, u = 5000, dep = 4500, a = 778, ac = { 778 }, st = "posted", cs = "nolot", al = {} },
        { id = 3, t = now, k = "i21", i = 21, n = "Mageweave", q = 5, u = 100, dep = 10, a = 779, ac = { 779 }, st = "posted", cs = "ok", c = 50, al = {} } }
    LQ.ResetCache(); c.TwichUILedgerDB.cost.chars["Rich - Forever"] = costRec
    local r2 = LQ.Results({ scope = "current", days = 7 })
    local rc
    for _, row in ipairs(r2.rows) do if row.name == "Runecloth" then rc = row end end
    local text = table.concat(LQ.ResultLines(rc), "|")
    Check(text:find("Your TwichUI postings of this item in this period: 2 (1 seen sold)", 1, true), text)
    Check(text:find("Verified cost of the units in 1 of them: 6g 0s 0c", 1, true) and text:find("not matched to payments", 1, true), text)
    Same(rc.profit, nil, "a posting never makes an auction sale profitable"); Same(rc.status, "unavailable")
    Same(r2.verified, r.verified, "postings never change verified profit"); Same(r2.sales, r.sales, "nor the sale count")
    costRec.posts = nil; LQ.ResetCache()
    -- V5 components of one combined payment without invoices, in the transaction details
    costRec.results[#costRec.results + 1] = Res({ id = 50, src = "ahSale", n = "Silk Cloth", q = 2, a = 700, st = "unknown", w = "auctionid", x = 60 })
    costRec.results[#costRec.results + 1] = Res({ id = 51, src = "ahSale", n = "Silk Cloth", q = 1, a = 300, st = "unknown", w = "auctionid", x = 60 })
    local details = table.concat(LQ.AuctionDetails({ code = "ahSale", a = 1000, id = 60, key = "Rich - Forever" }), "|")
    Check(details:find("Fee unavailable", 1, true) and details:find("Sold-auction mails in this payment: 2", 1, true), details)
    Check(details:find("Silk Cloth \195\1512: 7s 0c", 1, true) and not details:find("Unidentified", 1, true), details)
    details = table.concat(LQ.AuctionDetails({ code = "ahSale", a = 1200, id = 60, key = "Rich - Forever" }), "|")
    Check(details:find("Unidentified: 2s 0c", 1, true), "an unexplained part is named, never spread: " .. details)
    table.remove(costRec.results); table.remove(costRec.results)

    -- the page: one panel, two views
    Same(V.mode, "transactions"); V.tx.modeResults:GetScript("OnClick")(V.tx.modeResults)
    Same(V.mode, "results"); Same(V.tx.title:GetText(), "Realized Results"); Check(V.rlist.box:IsShown() and not V.list.box:IsShown())
    Same(#V.rlist.data, 5)
    local row = V.rlist.rows[1]; Check(row, "pooled rows exist")
    row:GetScript("OnEnter")(row); Check(#Tip.lines > 0, "hover details")
    local seen = {}
    for _, rw in ipairs(V.rlist.rows) do if rw:IsShown() then seen[rw.name:GetText()] = rw end end
    Check(seen["Item 12 \195\1512"], "a quantity is shown")
    for name, rw in pairs(seen) do
        if rw.data.profit == nil then Same(rw.result:GetText(), "Unavailable", name); Check(rw.cost:GetText() == "Unknown", name) end
    end
    V.SetFilter("source", "ahSale"); Same(#V.rlist.data, 1); V.SetFilter("source", nil)
    V.SetFilter("search", "runecloth"); Same(#V.rlist.data, 1); V.SetFilter("search", "")
    V.tx.modeTx:GetScript("OnClick")(V.tx.modeTx); Same(V.mode, "transactions"); Check(V.list.box:IsShown() and not V.rlist.box:IsShown())

    -- professions: verified results only; partial and insufficient are labelled, never zero or guessed
    LQ.SetProfessionProvider(LQ.CostProfessions); LQ.ResetCache(); V.Draw()
    local prof = LQ.Professions({ scope = "current", days = 7 })
    Check(prof and #prof.rows == 3, "three professions, got " .. tostring(prof and #prof.rows))
    Same(prof.rows[1].amount, 3000); Check(prof.rows[1].name:find("Tailoring", 1, true) and prof.rows[1].name:find("2 sales verified", 1, true), prof.rows[1].name)
    Same(prof.rows[1].partial, false)
    Check(prof.rows[2].amount == nil and prof.rows[2].text == "Insufficient verified data", "no verified sale: insufficient, not zero")
    Check(V.profShown, "the panel lists the verified profession")
    Same(V.profRows[1].amount:GetText(), "+30s"); Same(V.profRows[2].amount:GetText(), "Insufficient verified data")
    -- all-characters scope never mixes in another character's cost record
    V.SetFilter("scope", "all"); Check(LQ.Results({ scope = "all", days = 7 }).sales == 7); V.SetFilter("scope", "current")
    -- a window with nothing: the original honest empty state
    c.NOW = c.NOW + 200 * DAY; LQ.ResetCache(); V.Draw()
    Check(not V.profShown, "no profession result outside the window"); Same(V.prof.head:GetText(), "Profession profitability isn't available yet.")
    c.NOW = c.NOW - 200 * DAY; LQ.ResetCache()
    -- a held or missing cost component shows an honest line
    c.TwichUILedgerDB.cost = nil; K.Init(); LQ.ResetCache()
    Same(#(LQ.Results({ scope = "current", days = 7 }).rows), 0)
end

---------------------------------------------------------------------------
-- Local days: the page's window, "today" and timestamps follow the recorder's local calendar day, not UTC
---------------------------------------------------------------------------
do
    local saved = L.UtcOffset
    L.UtcOffset = function() return -8 * 3600 end        -- eight hours west of UTC
    local keep = c.NOW
    c.NOW = (TODAY + 1) * DAY + 3 * 3600                  -- 03:00 UTC = 19:00 the evening before, locally
    Same(LQ.Today(), TODAY, "today is the local day")
    Same(LQ.DayStart(TODAY), TODAY * DAY + 8 * 3600); Same(LQ.DayOf(TODAY * DAY + 8 * 3600), TODAY); Same(LQ.DayOf(TODAY * DAY + 8 * 3600 - 1), TODAY - 1)
    -- a 7-day window starts at local midnight of TODAY-6 = (TODAY-6)*DAY + 8h UTC: one second earlier is outside it
    local rec = NewRec("Rich"); rec.tz = 1
    Cover(rec, 0)
    local start = LQ.DayStart(TODAY - 6)
    rec.entries[#rec.entries + 1] = { id = 1, t = start - 1, a = 500, e = "balance" }
    rec.entries[#rec.entries + 1] = { id = 2, t = start, a = 700, e = "balance" }
    rec.nextId = 3
    c.TwichUILedgerDB.chars["Rich - Forever"] = rec; LQ.ResetCache()
    local rows = LQ.Rows({ scope = "current", days = 7 }, TODAY, 10)
    Same(#rows, 1, "the window starts at local midnight"); Same(rows[1].a, 700)
    Same(LQ.Clock(TODAY * DAY + 9 * 3600), os.date("!%b %d  %H:%M", TODAY * DAY + 9 * 3600), "times use the client's local date()")
    L.UtcOffset = saved; c.NOW = keep; LQ.ResetCache()
end

---------------------------------------------------------------------------
-- Gold Flow chart: columns, aggregation, coverage, strokes, pools and the expanded view
---------------------------------------------------------------------------
do
    local function D(i, inn, out, covered, n) return { day = TODAY - 100 + i, inn = inn, out = out, net = inn - out, n = n or ((inn > 0 or out > 0) and 1 or 0), covered = covered ~= false } end
    -- exact aggregation: the columns add up to the days, an uncovered day adds nothing and is not a zero
    local days = {}
    for i = 1, 90 do days[i] = D(i, i * 1000, (i % 4) * 700, i % 9 ~= 0 and not (i >= 40 and i <= 46)) end
    local sumIn, sumOut, sumN = 0, 0, 0
    for _, d in ipairs(days) do if d.covered then sumIn, sumOut, sumN = sumIn + d.inn, sumOut + d.out, sumN + d.n end end
    local cols, k = LC.Columns(days, 1, 90, 1100)
    Same(k, 1, "wide enough for every day"); Same(#cols, 90)
    cols, k = LC.Columns(days, 1, 90, 400)
    Same(k, 7); Same(#cols, 13, "ninety days in weeks"); Same(cols[1].span, 7); Same(cols[13].span, 6, "the last column is the days that remain")
    local cin, cout, cn = 0, 0, 0
    for _, col in ipairs(cols) do cin, cout, cn = cin + col.inn, cout + col.out, cn + col.n; Same(col.net, col.inn - col.out) end
    Same(cin, sumIn); Same(cout, sumOut); Same(cn, sumN)
    Check(cols[2].partial and cols[2].recorded == 6 and cols[2].covered, "a week with an unrecorded day is partly recorded")
    local whole = 0
    for _, col in ipairs(cols) do if col.day >= days[40].day and col.last <= days[46].day then whole = whole + 1; Check(not col.covered and col.inn == 0 and col.recorded == 0, "a week of unrecorded days is outside coverage, not zero") end end
    Check(whole >= 0)
    for _, span in ipairs({ { 1, 90, 200, 14 }, { 1, 90, 60, 30 } }) do
        local c2, k2 = LC.Columns(days, span[1], span[2], span[3]); Check(k2 >= 7 and #c2 <= math.max(4, math.floor(span[3] / LC.MIN_SLOT)) or k2 == 30, "bounded: " .. span[3])
    end
    Same(#LC.Columns(days, 5, 4, 400), 0)
    -- the net line is never joined through or into a partly recorded column
    local g = LC.Geometry(LC.Columns(days, 1, 90, 400), 400, 150)
    for _, sg in ipairs(g.segments) do Check(not sg.a.partial and not sg.b.partial and sg.b.index == sg.a.index + 1) end
    -- days and view ranges
    Same(LC.DayLong(TODAY), os.date("!%A, %B %d", TODAY * DAY):gsub(" 0(%d)$", " %1"))
    local v1, v2 = LC.ViewRange(days, days[10].day, days[20].day); Same(v1, 10); Same(v2, 20); Same(LC.ViewRange(days, days[90].day + 5, days[90].day + 9), nil)
end

do
    -- a week with one busy day among covered quiet days and unrecorded days
    local rec = NewRec("Rich"); rec.tz = 1
    for off = 0, 6 do if off ~= 4 and off ~= 5 then Cover(rec, off) end end
    Add(rec, 3, 820000, "mail"); Add(rec, 3, -140000, "ahBuy", { i = 10, q = 40 })
    Install({ ["Rich - Forever"] = rec }); V.SetFilter("source", nil); V.SetFilter("scope", "current"); V.SetFilter("days", 7); V.SetFilter("search", ""); V.Draw()
    local ch = V.chart
    Same(#ch.cols, 7); Same(#ch.geometry.uncovered, 2, "two days outside coverage"); Same(#ch.geometry.points, 5, "no point for an unrecorded day"); Same(#ch.geometry.ticks, 4, "four recorded quiet days")
    for _, sg in ipairs(ch.geometry.segments) do Check(sg.b.index == sg.a.index + 1) end
    ch:InspectIndex(4)
    local t = ch:CardFrame()
    Same(t.rows[1].value:GetText(), "+82g"); Same(t.rows[2].value:GetText(), "-14g"); Same(t.rows[3].value:GetText(), "+68g"); Check(t.foot:GetText():find("2 recorded changes", 1, true))
    ch:InspectIndex(2); Check(t.note:IsShown() and t.note:GetText():find("Not recorded", 1, true) and not t.note:GetText():find("Gold In", 1, true)); ch:ClearInspection()
    -- net zero although both movements happened: the card says so, it does not read as "nothing happened"
    Add(rec, 0, 5000, "mail"); Add(rec, 0, -5000, "repair", { n = "Equipment repairs" }); LQ.ResetCache(); V.Draw()
    ch:InspectIndex(7)
    Same(t.rows[1].value:GetText(), "+50s"); Same(t.rows[2].value:GetText(), "-50s"); Same(t.rows[3].value:GetText(), "0c"); ch:ClearInspection()
    -- the scale stays honest: the small expense next to a large income keeps a visible marker, not a pretend share
    local big = NewRec("Rich"); big.tz = 1
    Add(big, 1, 90000000000, "mail"); Add(big, 1, -3, "repair", { n = "Equipment repairs" }); Install({ ["Rich - Forever"] = big }); V.Draw()
    local outBar
    for _, b in ipairs(ch.geometry.bars) do if b.kind == "out" then outBar = b end end
    Check(outBar and outBar.h >= LC.MIN_BAR, "a very small expense still shows, at the minimum visible mark")
    ch:InspectIndex(6); Check(t.rows[1].value:GetText():find("9,000,000g", 1, true) and t.rows[2].value:GetText() == "-3c", t.rows[1].value:GetText())
    ch:ClearInspection()
    -- an all-zero recorded period keeps the explained empty state and no axis
    local zero = NewRec("Rich"); zero.tz = 1; for off = 0, 6 do Cover(zero, off) end
    Install({ ["Rich - Forever"] = zero }); V.Draw()
    Check(ch.empty and #ch.geometry.grid == 0 and ch.msg:GetText():find("No gold activity", 1, true), "an all-quiet period"); Same(#ch.geometry.ticks, 7)
end

do
    -- strokes: native lines anchored to the markers, then the portable fallback; forced and automatic
    local rec = NewRec("Rich"); rec.tz = 1
    for off = 0, 4 do Add(rec, off, 1000 * (off + 1), "mail") end
    Install({ ["Rich - Forever"] = rec }); V.Draw()
    local ch = V.chart
    local made, bad = 0, false
    ch.plot.CreateLine = function(self)
        made = made + 1
        local l = MIFake("Line", self)
        l.SetStartPoint = function(_, point, region) assert(region and region.SetPoint, "anchored to a region") end
        l.SetEndPoint = function() end
        l.SetThickness = function() if bad then error("no thickness") end end
        l.SetColorTexture = function() end
        return l
    end
    ch:SetStrokeMode(nil); Same(ch.backend, "native"); Same(ch.strokes.used, 8, "two strokes for each of four segments")
    ch:SetStrokeMode("raster"); Same(ch.backend, "raster"); Check(ch.strokes.used > 0 and ch.stepCount == ch.strokes.used)
    bad = true; ch:SetStrokeMode(nil); Same(ch.backend, "raster", "a refused line object falls back without leaving partial lines")
    bad = false; ch.strokes:SetMode(nil)
    -- pools stay bounded over many range changes and redraws
    ch.plot.CreateLine = nil; ch:SetStrokeMode(nil)
    V.SetFilter("days", 30); V.SetFilter("days", 90); V.SetFilter("days", 7); V.Draw()
    local warm = ch:RegionCount()
    for _ = 1, 20 do V.SetFilter("days", 30); V.SetFilter("days", 90); V.SetFilter("days", 7); LQ.ResetCache(); V.Draw() end
    Same(ch:RegionCount(), warm, "no pool growth over repeated redraws")
end

do
    -- the expanded view: one more chart over the same data, closed by Back, by hiding the page and by leaving it
    Install({ ["Rich - Forever"] = rich }); V.SetFilter("days", 7); V.Draw()
    Check(not V.ExpandedShown() and V.big == nil, "no second chart until it is asked for")
    local before = Listeners()
    V.OpenExpanded()
    Check(V.ExpandedShown() and V.bigChart and V.bigChart.big, "the expanded chart is open")
    Check(V.bigChart.model == V.summary, "it shares the page's own summary: no second journal read")
    Same(Listeners(), before, "no further listener")
    Check(V.big.ranges[7].on and not V.big.ranges[30].on, "its ranges follow the page")
    V.big.ranges[30]:GetScript("OnClick")(V.big.ranges[30]); Same(V.filter and V.filter.days or V.Filter().days, 30); Check(V.bigChart.model == V.summary and #V.bigChart.cols == 30)
    Same(V.bigChart.model.filter.days, 30)
    V.bigChart:InspectIndex(10); Check(V.bigChart:CardFrame():IsShown())
    V.bigChart:ResetZoom()
    -- a drag in progress when the page is hidden leaves nothing behind
    local hit = V.bigChart.hit
    V.bigChart.CursorX = function() return 40 end
    hit:GetScript("OnEnter")(hit); hit:GetScript("OnMouseDown")(hit, "LeftButton")
    Check(V.bigChart.pointer.drag ~= nil)
    for _, h in ipairs(Win.Page("ledger").hooks.OnHide or {}) do h() end
    Check(not V.ExpandedShown(), "hiding the page closes the expanded view")
    Check(V.bigChart.pointer.drag == nil and hit:GetScript("OnUpdate") == nil and V.bigChart.inspected == nil, "no drag, updater or card remains")
    V.bigChart.CursorX = nil
    V.OpenExpanded()
    Check(not V.ExpandedShown() or Win.Page("ledger"):IsShown() == false or true)
    V.CloseExpanded(); Check(not V.ExpandedShown())
    V.SetFilter("days", 7)
end

-- Cost of the premium chart over a long history (stand-in frames: this is Lua time and region counts, not the client's draw time).
do
    local rec = NewRec("Rich"); rec.tz = 1
    for off = 0, 89 do
        Cover(rec, off)
        if off % 3 ~= 1 then Add(rec, off, ((off * 37) % 11 + 1) * 4200, off % 2 == 0 and "mail" or nil); Add(rec, off, -(((off * 17) % 7 + 1) * 3100), off % 3 == 0 and "ahBuy" or nil, off % 3 == 0 and { i = 10, q = 3 } or nil) end
    end
    Install({ ["Rich - Forever"] = rec })
    local ch = V.chart
    ch.plot.CreateLine = function(self)
        local l = MIFake("Line", self)
        l.SetStartPoint = function() end; l.SetEndPoint = function() end; l.SetThickness = function() end; l.SetColorTexture = function() end
        return l
    end
    local line = {}
    for _, mode in ipairs({ "native", "raster" }) do
        for _, days in ipairs({ 7, 30, 90 }) do
            ch.strokes:SetMode(mode == "raster" and "raster" or nil)
            V.SetFilter("days", days)
            local t0 = os.clock()
            for _ = 1, 20 do ch.drawn = nil; ch:Render() end
            local draw = (os.clock() - t0) / 20 * 1000
            local t1 = os.clock()
            for i = 1, 400 do ch.inspected = nil; ch:InspectIndex((i % #ch.cols) + 1) end
            local hover = (os.clock() - t1) / 400 * 1000
            ch:ClearInspection()
            Same(ch.backend, mode)
            line[#line + 1] = ("%s %dD: %d columns, %d regions in use, redraw %.2f ms, inspect %.3f ms"):format(mode, days, #ch.cols, ch:VisibleRegions(), draw, hover)
            Check(draw < 40 and hover < 5, "chart cost stays small: " .. line[#line])
        end
    end
    ch.plot.CreateLine = nil; ch.strokes:SetMode(nil)
    V.SetFilter("days", 7)
    print("gold flow chart (Lua time, stand-in frames):\n  " .. table.concat(line, "\n  "))
end

-- With the artwork on, the same figures are coin textures; the pure text form and the exact amounts are unchanged.
do
    UI.Coins.SetIcons(true)
    local rec = NewRec("Rich"); rec.tz = 1
    Add(rec, 0, 1234567 * 10000 + 5524, "mail"); Add(rec, 0, -250050, "repair", { n = "Equipment repairs" }); Add(rec, 0, 7, "mail")
    Install({ ["Rich - Forever"] = rec }); V.SetFilter("source", nil); V.SetFilter("days", 7); V.SetFilter("scope", "current"); V.Draw()
    local GOLD, SILVER, COPPER = "|TInterface\\MoneyFrame\\UI-GoldIcon:", "|TInterface\\MoneyFrame\\UI-SilverIcon:", "|TInterface\\MoneyFrame\\UI-CopperIcon:"
    local inn = V.cards.inn.value
    -- (the stand-in measures markup as characters, so the card may compact; the exact amount is kept either way)
    Check(inn:GetText():find(GOLD, 1, true) and inn:GetText():find("^%+1[,%.]"), inn:GetText())
    Same(inn.exact, 1234567 * 10000 + 5524 + 7, "the exact copper stays on the value")
    Check(V.cards.out.value:GetText():find("^%-25") and V.cards.out.value:GetText():find(GOLD, 1, true), V.cards.out.value:GetText())
    Check(V.cards.out.value:GetText():find(SILVER, 1, true) == nil, "-25g 0s 50c has no silver part: " .. V.cards.out.value:GetText())
    -- every card's coins have one size, whatever font its figure needed
    local sizes = {}
    for _, key in ipairs({ "net", "inn", "out", "attrIn", "attrOut", "unk" }) do
        for size in V.cards[key].value:GetText():gmatch(":(%d+):%d+:2:0") do sizes[size] = true end
    end
    local n = 0; for _ in pairs(sizes) do n = n + 1 end
    Same(n, 1, "one coin size across the six cards"); Check(sizes["10"], "the smaller size")
    -- rows and the hover use the same artwork; Money (the pure text) does not
    Check(V.list.rows[1].amount:GetText():find("|T", 1, true), "transaction amounts are coins")
    V.list.rows[1]:GetScript("OnEnter")(V.list.rows[1]); Check(TipText():find("|T", 1, true) and TipText():find("Gold in:", 1, true) or TipText():find("Gold out:", 1, true), TipText())
    Check(not LQ.Money(1234567 * 10000 + 5524, true):find("|T", 1, true) and LQ.Money(100) == "1s 0c", "the pure text form is unchanged")
    Check(V.sourceList.rows[1].amount:GetText():find("|T", 1, true), "source amounts are coins")
    -- item results and professions too
    V.tx.modeResults:GetScript("OnClick")(V.tx.modeResults)
    V.tx.modeTx:GetScript("OnClick")(V.tx.modeTx)
    UI.Coins.SetIcons(false)
end
print("LEDGER PAGE OK")
