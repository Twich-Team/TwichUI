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

for _, f in ipairs({ "Data.lua", "BridgeCodec.lua", "BridgeSchema.lua", "BridgeValidate.lua", "Bridge.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Session.lua", "AuctionButton.lua", "Style.lua", "auction/AdvancedChart.lua", "LedgerQuery.lua", "LedgerChart.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewStrategy.lua", "ViewLedger.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
local Win, UI, LQ, LC, V = W.Window, W.UI, W.LedgerQuery, W.LedgerChart, W.UI.LedgerView
Check(UI.pages.ledger and UI.pages.ledger.nav == "Gold Ledger", "the page registered itself")

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
Same(LQ.Day(TODAY), os.date("!%Y-%m-%d", TODAY * DAY)); Check(LQ.Stamp(TODAY * DAY):find("UTC", 1, true))

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
Same(Card("net"), "+12g 30s 0c"); Same(Card("inn"), "+15g 50s 0c"); Same(Card("out"), "-3g 20s 0c")
Same(Card("attrIn"), "+13g 0s 0c"); Same(Card("attrOut"), "-2g 50s 0c"); Same(Card("unk"), "+1g 80s 0c" == "x" and "" or LQ.Money(25000 - 7000, true))
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
Same(#V.chart.model.days, 7); Same(V.chart.geometry.n, 7)
Check(V.chart.barCount >= 5, "bars drawn")
Same(#V.chart.hits, 7, "one pointer region for each day")
do
    local h = V.chart.hits[7]
    h:GetScript("OnEnter")(h)
    Check(TipText():find("(UTC day)", 1, true) and TipText():find("Gold in: +10g 50s 0c", 1, true) and TipText():find("Gold out: -2g 50s 0c", 1, true), TipText())
    Check(V.chart.highlight:IsShown() == true or V.chart.inspected == 7)
    h:GetScript("OnLeave")(h)
    Check(V.chart.inspected == nil, "leaving clears the inspection")
    local h4 = V.chart.hits[4]   -- today-3: -7000
    h4:GetScript("OnEnter")(h4)
    Check(TipText():find("Gold out: -0g 70s 0c", 1, true) or TipText():find("-70s", 1, true), TipText())
    h4:GetScript("OnLeave")(h4)
    local h2 = V.chart.hits[2]   -- today-5: +20000
    local h3 = V.chart.hits[3]   -- today-4: not recorded at all
    h3:GetScript("OnEnter")(h3)
    Check(TipText():find("Not recorded", 1, true) and not TipText():find("Gold in", 1, true), "a day outside coverage is not a zero: " .. TipText())
    h3:GetScript("OnLeave")(h3)
    local h5 = V.chart.hits[5]   -- today-2: recorded, nothing moved
    h5:GetScript("OnEnter")(h5)
    Check(TipText():find("Recorded: no gold moved", 1, true), TipText())
    h5:GetScript("OnLeave")(h5)
end
-- legend toggles
V.chart.legendButtons.out:GetScript("OnClick")(V.chart.legendButtons.out)
Check(V.chart.show.out == false); for _, b in ipairs(V.chart.geometry.bars) do Same(b.kind, "in") end
V.chart.legendButtons.out:GetScript("OnClick")(V.chart.legendButtons.out)
Check(V.chart.show.out == true)
Check(V.chart.legendButtons.inn.text:GetText():find("Gold in (15g 50s 0c)", 1, true), V.chart.legendButtons.inn.text:GetText())
-- the source panel: ranked, only what was recorded
do
    local rows = LQ.SourceRows(V.summary)
    Same(#rows, 5)
    Same(rows[1].code, "mail"); Same(rows[1].amount, 100000); Same(rows[2].code, "ahSale"); Same(rows[3].code, "ahBuy"); Same(rows[4].dir, 1)
    Same(V.srcRows[1].label:GetText(), "Mail collected"); Same(V.srcRows[1].amount:GetText(), "+10g 0s 0c")
    Same(V.srcRows[3].label:GetText(), "Auction purchases"); Same(V.srcRows[3].amount:GetText(), "-2g 50s 0c")
    Same(V.srcRows[5].label:GetText(), "Unclassified spending")
    local other = {}
    for _, r in ipairs(rows) do if r.code == "other" then other[#other + 1] = r.label end end
    Same(table.concat(other, "|"), "Unclassified income|Unclassified spending")
    Same(rows[5].label, "Unclassified spending")
end

-- 30 and 90 days, and the clearly selected range
V.SetFilter("days", 30)
Same(Card("inn"), "+20g 50s 0c"); Same(Card("attrIn"), "+18g 0s 0c"); Reconciles("30D"); Same(#V.chart.hits, 30); Same(V.cards.net.sub:GetText(), "Last 30 days")
Check(V.flow.ranges[30].on == true and V.flow.ranges[7].on == false and V.flow.ranges[90].on == false, "the chosen range is marked")
V.SetFilter("days", 90)
Same(Card("inn"), "+20g 60s 0c"); Reconciles("90D"); Same(#V.chart.hits, 90)
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
Same(Card("inn"), "+10g 0s 0c"); Same(Card("out"), "0c"); Same(#V.rows, 1); Reconciles("mail"); Same(#LQ.SourceRows(V.summary), 1)
Check(V.srcRows[1]:IsShown() and not V.srcRows[2]:IsShown(), "only sources with recorded money get a row")
V.SetFilter("source", "ahBuy"); Same(Card("out"), "-2g 50s 0c"); Same(#V.rows, 1); Same(V.rows[1].item, 10); Reconciles("ahBuy")
V.SetFilter("source", "other"); Same(Card("attrIn"), "0c"); Same(#V.rows, 3); Reconciles("other")
V.SetFilter("source", nil); Same(#V.rows, 6)
V.SetFilter("source", "bogus"); Check(V.Filter().source == nil, "an unknown source is no filter")

-- search narrows the list only
V.SetFilter("search", "runecl")
Same(#V.rows, 1); Same(V.rows[1].text, "Runecloth"); Same(Card("net"), "+12g 30s 0c", "the totals do not change with a text search")
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
    Same(V.cards.net.cmp:GetText(), "Prior 7d: +6g 0s 0c")
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
    local function Count() local n = 0 for _ in pairs(V.chart.hits) do n = n + 1 end return n + #V.chart.bars + #V.chart.dots + #V.list.rows end
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
    V.sourceList.scroll:SetVerticalScroll(3 * 26); V.sourceList:Layout()
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

print("LEDGER PAGE OK")
