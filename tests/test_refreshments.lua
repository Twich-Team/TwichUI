-- Mage refreshments: the item and rank data agree with Mage Conjuring and the Food and Drink buttons; the
-- plan's sums (shares, zeros, ranks by level, reserve, party and raid, statuses, the next person); the
-- shares settings refuse bad values and fall back without erasing; the session follows the roster by
-- GUID (party to raid, leaving and coming back, leaving the group); the secure buttons cast once per
-- release, change only out of combat and go empty when the feature is off; the panel won't open in
-- combat and closes as it starts; non-Mages get nothing registered; items per cast are learned from the
-- bags; and the diagnostics report carries no names or GUIDs.
-- Mocks show TwichUI's own bookkeeping. Whether the game casts, repeats or blocks anything is for the game.
dofile(TESTS .. "harness.lua")

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

---------------------------------------------------------------------------
-- The data: six ranks of each, in step with Mage Conjuring, and the items the Food and Drink buttons
-- know as conjured.
---------------------------------------------------------------------------
do
  local env = setmetatable({ TwichUI = { PATH = "", On = function() end, OnInit = function() end, Enabled = function() return false end } }, { __index = _G })
  env.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
  Load(env, { "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageConjure.lua",
    "modules/FoodDrink.lua", "modules/Refreshments.lua" })
  local R = env.TwichUI
  local RF, M, F = R.Refreshments, R.MageConjure, R.FoodDrink
  local seen = 0
  for _, kind in ipairs(RF.KINDS) do
    assert(#RF.ITEMS[kind] == #M.SPELLS[kind] and #RF.ITEMS[kind] == #RF.USE_LEVEL, kind .. ": one item per rank")
    for rank, item in ipairs(RF.ITEMS[kind]) do
      assert(F.CONJURED[item], item .. " is an item the Food and Drink buttons call conjured")
      assert(RF.SpellIndex(M.SPELLS[kind][rank]) == rank, "spell to rank")
      seen = seen + 1
    end
  end
  local n = 0; for _ in pairs(F.CONJURED) do n = n + 1 end
  assert(seen == n, "the same twelve items in both places")
  for i = 2, #RF.USE_LEVEL do assert(RF.USE_LEVEL[i] > RF.USE_LEVEL[i - 1], "levels rise with the rank") end
  assert(RF.SpellIndex(12345) == nil, "any other spell is not a conjure")
  for _, class in ipairs(RF.CLASSES) do assert(RF.DEFAULTS[class], class .. " has a starting share") end
  assert(RF.DEFAULTS.MAGE.water == 0 and RF.DEFAULTS.MAGE.food == 0, "nothing planned for other Mages to start with")
end

---------------------------------------------------------------------------
-- A Mage in the simulated game.
---------------------------------------------------------------------------
local c = MakeClient("Rich", { "!!!TwichUI" })
local Methods
local made = {}
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, attrs = {}, points = {} }
  made[#made + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
Methods = {
  Show = function(s) if not s.shown then s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(s) end end end,
  Hide = function(s) if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end,
  IsShown = function(s) return s.shown end,
  SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end,
  GetScript = function(s, n) return s.scripts[n] end,
  SetAttribute = function(s, k, v) if COMBAT then error("SetAttribute in combat") end s.attrs[k] = v end,
  GetAttribute = function(s, k) return s.attrs[k] end,
  RegisterForClicks = function(s, ...) s.clicks = { ... } end,
  CreateTexture = function() return Fake("texture") end,
  CreateFontString = function() return Fake("font") end,
  SetText = function(s, v) s.text = v end,
  GetText = function(s) return s.text end,
  SetTexture = function(s, v) s.texture = v end,
  HasFocus = function() return false end,
  SetBackdrop = function(s, b) s.backdrop = b end,
  SetBackdropColor = function(s, r, g, b, a) s.bgColor = { r, g, b, a } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind); f.name, f.parent, f.template = name, parent, template
  if name then c[name] = f end
  return f
end
c.UIParent = Fake("UIParent")
c.UISpecialFrames = {}
c.notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) table.insert(c.notices, text) end }
c.printed = {}
c.print = function(s) table.insert(c.printed, tostring(s)) end
local tip = { lines = {} }
function tip:SetOwner(o) self.owner = o; self.lines = {} end
function tip:GetOwner() return self.owner end
function tip:IsOwned(o) return self.owner == o end
function tip:Hide() self.owner = nil end
tip.SetText, tip.AddLine, tip.SetSpellByID, tip.Show = function() end, function() end, function() end, function() end
c.GameTooltip = tip
COMBAT = false
c.InCombatLockdown = function() return COMBAT end
c.CLASS = "MAGE"
c.MYLEVEL = 50
c.UnitLevel = function(u) if u == "player" then return c.MYLEVEL end local m = c.ROSTER[u]; return m and m.level or 0 end
c.UnitClass = function(u) if u == "player" then return "Mage", c.CLASS end local m = c.ROSTER[u]; return m and m.class, m and m.class end
c.ROSTER, c.RAID = {}, false
c.IsInRaid = function() return c.RAID end
c.IsInGroup = function() return next(c.ROSTER) ~= nil end
c.GetNumGroupMembers = function() local n = 1 for _ in pairs(c.ROSTER) do n = n + 1 end return n end
c.UnitExists = function(u) return u == "player" or c.ROSTER[u] ~= nil end
c.UnitIsUnit = function(a, b) return a == b end
c.UnitGUID = function(u) if u == "player" then return "Player-1-ME" end local m = c.ROSTER[u]; return m and m.guid end
c.GetUnitName = function(u) local m = c.ROSTER[u]; return m and m.name end
c.UnitIsConnected = function(u) local m = c.ROSTER[u]; return not (m and m.offline) end
c.KNOWN = {}
for _, id in ipairs({ 587, 597, 990, 6129, 10144, 10145, 5504, 5505, 5506, 6127, 10138, 10139 }) do c.KNOWN[id] = true end
c.C_SpellBook = { IsSpellKnown = function(id) return c.KNOWN[id] == true end }
c.Enum = { SpellBookSpellBank = { Player = 0 } }
c.picked = nil
c.C_Spell = {
  GetSpellName = function() return "Conjure" end, GetSpellTexture = function(id) return 1000 + id end,
  GetSpellSubtext = function() return nil end, RequestLoadSpellData = function() end,
  PickupSpell = function(id) c.picked = id end,
}
c.BAGS = {}
c.C_Item = { GetItemCount = function(id) return c.BAGS[id] or 0 end, GetItemMaxStackSizeByID = function() return 20 end }
c.C_Container = {
  GetContainerNumFreeSlots = function(bag) return bag == 0 and 4 or 0, 0 end,
  GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end,
}
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function(key) local d = c.StaticPopupDialogs[key]; c.popup = d; return d end

Load(c, { "chronicle/Style.lua", "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
  "modules/MageTravel.lua", "modules/MageConjure.lua", "modules/Refreshments.lua" })
local castFrame = made[#made]   -- the only frame Refreshments.lua makes at load: its watch on your own casts
assert(castFrame.kind == "Frame" and castFrame.scripts.OnEvent, "a frame of its own for the player's casts")
local brokers = {}
local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
LDB.NewDataObject = function(_, name, o) brokers[name] = o; return o end
Load(c, { "modules/RefreshmentsPanel.lua", "modules/RefreshmentsShares.lua", "modules/RefreshmentsBroker.lua", "diag/Diagnostics.lua", "diag/Refreshments.lua" })
local R = c.TwichUI
local RF, P = R.Refreshments, R.RefreshmentsPanel

c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(c.TwichUIDB.modules.mageRefreshments == false, "off for a new install")

---------------------------------------------------------------------------
-- The plan, on its own.
---------------------------------------------------------------------------
do
  local all = {}; for r = 1, 6 do all[r] = true end
  local function Plan(members, context, extra)
    extra = extra or {}
    return RF.BuildPlan({
      context = context or "party", members = members, myLevel = extra.myLevel or 50,
      known = extra.known or { water = all, food = all }, share = extra.share or RF.Share,
      reserve = extra.reserve or { water = 20, food = 20 }, have = function(item) return (extra.have or {})[item] or 0 end,
    })
  end
  local p = Plan({
    { guid = "W", class = "WARRIOR", level = 30, connected = true, given = { water = 0, food = 0 } },
    { guid = "P", class = "PRIEST", level = 40, connected = true, given = { water = 0, food = 0 } },
  }, "party", { have = { [8078] = 5 } })
  assert(p.rows[1].want.water == 0 and p.rows[1].want.food == 20, "a warrior's default share: food only")
  assert(p.rows[1].rank.food == 4 and p.rows[2].rank.food == 5 and p.rows[2].rank.water == 5, "the best rank their level can use")
  assert(p.rows[1].rank.water == nil, "0 asks for nothing, so no rank is planned")
  local water = p.items.water
  assert(#water == 2 and water[1].rank == 6 and water[1].reserve == 20 and water[1].group == 0, "the reserve at your own best rank, listed first")
  assert(water[2].rank == 5 and water[2].group == 20 and water[2].recipients == 1, "the priest's water at rank 5")
  assert(water[1].have == 5 and water[1].short == 15 and p.totals.water.need == 40 and p.totals.water.covered == 5 and p.totals.water.short == 35)
  assert(p.counts.pending == 2 and p.next == "W", "the first not yet supplied is next")

  -- Statuses, partial deliveries, more than asked, offline people are never "next".
  p = Plan({
    { guid = "A", class = "WARRIOR", level = 60, connected = false, given = { water = 0, food = 0 } },
    { guid = "B", class = "PRIEST", level = 60, connected = true, given = { water = 20, food = 5 } },
    { guid = "C", class = "MAGE", level = 60, connected = true, given = { water = 0, food = 0 } },
    { guid = "D", class = "ROGUE", level = 60, connected = true, given = { water = 0, food = 40 } },
  })
  assert(p.rows[1].status == "pending" and p.rows[2].status == "partial" and p.rows[3].status == "nothing" and p.rows[4].status == "supplied")
  assert(p.rows[2].remaining.food == 15 and p.rows[4].remaining.food == 0, "never below 0 when more was handed over")
  assert(p.next == "B", "offline people are skipped for next: " .. tostring(p.next))
  assert(p.counts.supplied == 1 and p.counts.partial == 1 and p.counts.pending == 1 and p.counts.nothing == 1)

  -- An unknown level gets your best rank; an unknown class gets nothing; no known rank adds no line.
  p = Plan({ { guid = "U", class = "PRIEST", connected = true }, { guid = "X", connected = true } }, "party",
    { known = { water = {}, food = all } })
  assert(p.rows[1].rank.food == 6 and p.rows[1].noRank.water, "best rank without a level; no water rank known")
  assert(#p.items.water == 0 and p.totals.water.need == 0, "no rank known: nothing to conjure is pretended")
  assert(p.rows[2].status == "nothing", "no class read: no share")

  -- Explicit zeros, raid shares, and on your own.
  local zero = function() return 0 end
  p = Plan({ { guid = "Z", class = "PRIEST", level = 60, connected = true } }, "party", { share = zero, reserve = { water = 0, food = 0 } })
  assert(p.rows[1].status == "nothing" and #p.items.water == 0 and #p.items.food == 0 and p.next == nil)
  local asked
  p = Plan({ { guid = "R", class = "PRIEST", level = 60, connected = true } }, "raid", { share = function(ctx) asked = ctx; return 40 end })
  assert(asked == "raid" and p.rows[1].want.water == 40, "a raid reads the raid shares")
  p = Plan({ { guid = "S", class = "PRIEST", level = 60, connected = true } }, "solo")
  assert(#p.rows == 0 and p.totals.water.need == 20 and p.totals.food.need == 20, "on your own: only what you keep")
  -- A low-level Mage keeps their reserve at the rank they can use.
  p = Plan({}, "solo", { myLevel = 20 })
  assert(p.items.food[1].rank == 3, "reserve at the rank a level 20 can use")
end

---------------------------------------------------------------------------
-- Shares: checked when read and when written, defaults stored as nothing.
---------------------------------------------------------------------------
do
  assert(RF.Share("party", "PRIEST", "water") == 20 and RF.Reserve("water") == 20)
  assert(RF.SetShare("raid", "PRIEST", "water", 40) and RF.Share("raid", "PRIEST", "water") == 40 and RF.Share("party", "PRIEST", "water") == 20,
    "party and raid are separate")
  assert(RF.SetShare("party", "WARRIOR", "food", 0) and RF.Share("party", "WARRIOR", "food") == 0, "0 is a value")
  for _, bad in ipairs({ -1, 201, 1.5, 0 / 0, "20" }) do
    assert(not RF.SetShare("party", "PRIEST", "water", bad), "refused: " .. tostring(bad))
  end
  assert(not RF.SetShare("arena", "PRIEST", "water", 1) and not RF.SetShare("party", "MONK", "water", 1) and not RF.SetShare("party", "PRIEST", "gems", 1))
  assert(RF.SetShare("raid", "PRIEST", "water", 20) and c.TwichUIDB.ui.refreshments.raid == nil, "a default is stored as nothing")
  c.TwichUIDB.ui.refreshments.party.WARRIOR.water = "lots"
  assert(RF.Share("party", "WARRIOR", "water") == 0 and c.TwichUIDB.ui.refreshments.party.WARRIOR.water == "lots",
    "an unusable saved value falls back, and is not erased")
  assert(RF.Share("party", "WARRIOR", "food") == 0, "its neighbour is still read")
  assert(RF.SetReserve("food", 40) and RF.Reserve("food") == 40 and not RF.SetReserve("food", -5))
  c.TwichUIDB.ui.refreshments.position = { x = 10, y = 20 }
  RF.ResetShares()
  local s = c.TwichUIDB.ui.refreshments
  assert(s.party == nil and s.raid == nil and s.reserve == nil and s.position.x == 10, "reset keeps the panel's place")
  c.TwichUIDB.ui.refreshments = "broken"
  assert(RF.Share("party", "PRIEST", "water") == 20, "a damaged table reads as defaults")
  c.TwichUIDB.ui.refreshments = nil
end

---------------------------------------------------------------------------
-- Off: nothing listens, nothing is built, the command explains.
---------------------------------------------------------------------------
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
assert(#RF.Snapshot().events == 0 and not RF.Enabled(), "off: no events")
assert(c.TwichUIRefreshmentsWater == nil, "off: no secure buttons")
assert(brokers["TwichUI Mage Refreshments"] == nil, "off: no data bar plugin")
c.printed = {}
c.SlashCmdList.TWICHUI("refreshments")
assert(c.printed[#c.printed]:find("turned off", 1, true), "the command says it is off")

---------------------------------------------------------------------------
-- On, in a party.
---------------------------------------------------------------------------
c.ROSTER = {
  party1 = { guid = "G-1", name = "Thrall", class = "SHAMAN", level = 40 },
  party2 = { guid = "G-2", name = "Garrosh", class = "WARRIOR", level = 18 },
}
c.BAGS[8078] = 30
c.TwichUIDB.modules.mageRefreshments = true
RF.Refresh(); FlushTimers()
local snap = RF.Snapshot()
assert(snap.enabled and #snap.events > 0 and snap.context == "party" and snap.members == 2, "on: listening, the party read")
local water, food = c.TwichUIRefreshmentsWater, c.TwichUIRefreshmentsFood

-- The data bar plugin: made when it is turned on (no reload), its text the group's progress.
local broker = brokers["TwichUI Mage Refreshments"]
local RB = R.RefreshmentsBroker
assert(broker and broker.type == "data source" and broker.label == "Refreshments" and RB.Available(), "on the data bar's list once it is on")
assert(broker.text == "0/2 supplied", "its text: " .. tostring(broker.text))
assert(broker.icon == 1000 + 5504, "Conjure Water's icon")
assert(RB.TextChoice() == "progress")
assert(RB.SetTextChoice("label") and broker.text == "Refreshments" and c.TwichUIDB.ui.refreshmentsText == "label")
assert(RB.SetTextChoice("none") and broker.text == "")
assert(not RB.SetTextChoice("Portals") and RB.TextChoice() == "none", "an unknown choice is refused")
assert(RB.SetTextChoice("progress") and broker.text == "0/2 supplied")
do
  local lines = {}
  local t = { AddLine = function(_, a) lines[#lines + 1] = a end, AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. ": " .. b end }
  broker.OnTooltipShow(t)
  local all = table.concat(lines, "\n")
  assert(all:find("Supplied: 0 of 2", 1, true) and all:find("Next: Thrall", 1, true) and all:find("to conjure", 1, true), all)
  local opened
  R.OpenSettings = function(_, key) opened = key end
  broker.OnClick(nil, "RightButton")
  assert(opened == "mage", "right-click: the Mage options page")
  broker.OnClick(nil, "LeftButton")
  assert(P.IsOpen(), "click: the panel")
  broker.OnClick(nil, "LeftButton")
  assert(not P.IsOpen(), "and again closes it")
end
assert(water and food and water.template == "SecureActionButtonTemplate", "the two secure buttons exist for their keys")
assert(water.clicks[1] == "LeftButtonUp" and #water.clicks == 1 and water.attrs.useOnKeyDown == false, "once, on the release: a drag never casts")
local plan = RF.Plan()
assert(plan.rows[1].name == "Thrall" and plan.rows[2].rank.food == 3, "a level 18 warrior is planned rank 3 food")
assert(water.attrs.type == "spell" and water.attrs.spell == 10138, "water: the best rank still short (rank 5 for Thrall): " .. tostring(water.attrs.spell))
assert(food.attrs.spell == 10145, "food: rank 6 first, for what you keep (none in the bags yet)")

-- Drag: the spell goes on the cursor, never in combat.
water.scripts.OnDragStart(water); assert(c.picked == 10138, "dragging picks up the spell to drop on a bar")
c.picked = nil; COMBAT = true; water.scripts.OnDragStart(water); COMBAT = false
assert(c.picked == nil, "nothing is picked up in combat")

-- Marking: supplied, partial, cleared; next moves on.
assert(plan.next == "G-1")
RF.MarkSupplied("G-1"); plan = RF.Plan()
assert(plan.rows[1].status == "supplied" and plan.next == "G-2", "marked supplied; the next person is next")
assert(broker.text == "1/2 supplied", "the data bar follows: " .. tostring(broker.text))
RF.Adjust("G-2", "food", 10); plan = RF.Plan()
assert(plan.rows[2].status == "partial" and plan.rows[2].remaining.food == 10)
RF.Adjust("G-2", "food", -50); assert(RF.Entry("G-2").food == 0, "never below 0")
RF.ClearGiven("G-1"); assert(RF.Plan().rows[1].status == "pending")
RF.MarkSupplied("G-1")

-- A changed share: what was handed over stays; what is owed follows.
RF.SetShare("party", "SHAMAN", "water", 40); FlushTimers()
plan = RF.Plan()
assert(RF.Entry("G-1").water == 20 and plan.rows[1].remaining.water == 20 and plan.rows[1].status == "partial", "raised: 20 more owed")
RF.SetShare("party", "SHAMAN", "water", 10); FlushTimers()
assert(RF.Plan().rows[1].status == "supplied" and RF.Entry("G-1").water == 20, "lowered: supplied, and the record isn't rewritten")
RF.ResetShares(); FlushTimers()

-- Party to raid: the same people by GUID, raid shares, records kept.
c.RAID = true
c.ROSTER = {
  raid1 = { guid = "G-2", name = "Garrosh", class = "WARRIOR", level = 18 },
  raid2 = { guid = "G-1", name = "Thrall", class = "SHAMAN", level = 40 },
  raid3 = { guid = "G-3", name = "Jaina", class = "MAGE", level = 60 },
}
c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
plan = RF.Plan()
assert(plan.context == "raid" and #plan.rows == 3 and plan.rows[2].guid == "G-1" and plan.rows[2].status == "supplied", "kept across the change to a raid")
assert(plan.rows[3].status == "nothing", "another Mage: no share to start with")

-- Leaving and coming back keeps the record; same name, other GUID is someone else.
c.ROSTER.raid2 = nil
c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
assert(#RF.Plan().rows == 2 and RF.Entry("G-1") and RF.Snapshot().sessionDeparted == 1, "kept while away")
c.ROSTER.raid2 = { guid = "G-1", name = "Thrall", class = "SHAMAN", level = 40 }
c.ROSTER.raid4 = { guid = "G-9", name = "Thrall", class = "SHAMAN", level = 40 }   -- another realm's Thrall
c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
assert(RF.Entry("G-1").water == 20 and RF.Entry("G-9").water == 0, "back: their record returns; a namesake starts fresh")

-- Combat: a change waits, the button keeps its spell, the panel can't open.
local spellBefore = water.attrs.spell
c.BAGS[8077] = 200; c.BAGS[8078] = 200
COMBAT = true
c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
assert(water.attrs.spell == spellBefore and P.Snapshot().deferred, "in combat the secure button is left alone")
c.notices = {}
assert(not P.Open() and c.notices[1]:find("combat", 1, true), "can't open in combat")
COMBAT = false
c.FireEvent("PLAYER_REGEN_ENABLED")
assert(not P.Snapshot().deferred and water.attrs.spell == 10139, "after combat: the best rank, now nothing is short")

-- The panel: opens on request, closes as combat starts.
assert(P.Open() and P.IsOpen() and c.TwichUIRefreshments.shown, "opens when asked")
assert(c.UISpecialFrames[1] == "TwichUIRefreshments", "Esc closes it")
do
  local row
  for _, f in ipairs(made) do if f.row and f.row.guid == "G-2" and f.scripts.OnClick then row = f end end
  assert(row and row.shown, "a checklist row for each member")
  row.scripts.OnClick(row)
  assert(row.sel.shown, "clicking selects it")
  local body = row.twichuiTip.body(row)
  assert(body:find("Level 18", 1, true) and body:find("Food: 0 of 20", 1, true), "its tooltip: level and what is owed")
  local breakdown
  for _, f in ipairs(made) do
    if f.twichuiTip and f.twichuiTip.title == "Water" and type(f.twichuiTip.body) == "function" then breakdown = f.twichuiTip.body(f) end
  end
  assert(breakdown and breakdown:find("to keep", 1, true), "the water breakdown names what you keep")
  water.scripts.OnEnter(water); water.scripts.OnLeave(water)   -- the spell tooltip draws without error
end
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not P.IsOpen(), "closed as combat starts")
P.Open()
COMBAT = true
assert(not P.Close() and P.IsOpen(), "already in combat: it waits")
COMBAT = false
c.FireEvent("PLAYER_REGEN_ENABLED")
assert(not P.IsOpen(), "and closes when combat ends")

-- The panel's look: its own settings, drawn at once on an open panel, the panel grown round its border.
do
  local PS = P.Style
  local frame = c.TwichUIRefreshments
  assert(PS ~= R.MenuStyle and PS.Get("bgOpacity") == 98 and PS.Get("borderTexture") == "solid", "its own look, its own defaults")
  assert(P.Open())
  assert(frame.backdrop and frame.backdrop.bgFile and frame.w == 382 and frame.h == 550, "a 1-pixel line: the content plus one each side")
  assert(PS.Set("bgOpacity", 40) and math.abs(frame.bgColor[4] - 0.4) < 1e-9, "an open panel follows at once")
  assert(c.TwichUIDB.ui.refreshmentsStyle.bgOpacity == 40 and c.TwichUIDB.ui.brokerMenu == nil, "saved apart from the menus' look")
  assert(R.MenuStyle.Get("bgOpacity") == 100, "and the menus keep theirs")
  local calls = {}
  c.EllesmereUI = {
    PP = {}, GetBorderTextureList = function() return { { key = "pixels-textured", name = "Pixels Textured" } } end,
    ResolveBorderTexture = function(k) return k == "pixels-textured" and "p" or nil end,
    BorderPxStep = function() return 2 end, BorderLegacyPx = function() return 12 end, GetBorderDefaultSize = function() return 2 end,
    ApplyBorderStyle = function(_, _, _, _, _, _, key, ...) calls[#calls + 1] = { key = key, edge = select(8, ...) } end,
  }
  local listed = false
  for _, ch in ipairs(PS.BorderChoices()) do if ch[1] == "eui:pixels-textured" and ch[2] == "Pixels Textured" then listed = true end end
  assert(listed, "EllesmereUI's border textures are offered")
  assert(PS.Set("borderTexture", "eui:pixels-textured") and PS.Get("borderSize") == 12, "with a thickness that suits it")
  assert(#calls > 0 and calls[#calls].key == "pixels-textured" and calls[#calls].edge == 12, "drawn by EllesmereUI round the panel")
  assert(frame.w == 380 + 24 and frame.h == 548 + 24, "grown so the border doesn't cover the content: " .. tostring(frame.w))
  assert(R.MenuStyle.Get("borderTexture") == "solid", "the menus' border is untouched")
  COMBAT = true
  assert(PS.Set("borderSize", 4) and frame.w == 404, "not resized in combat")
  COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(frame.w == 388, "redrawn when combat ends")
  PS.Reset()
  assert(c.TwichUIDB.ui.refreshmentsStyle == nil and frame.w == 382, "reset: the defaults, and nothing saved")
  c.EllesmereUI = nil
  P.Close()
end

-- Items per cast: learned from the bags after a conjure, at this level.
c.BAGS[8078] = 100
castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 10139)
castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "raid1", "Cast-2", 10139)   -- someone else's: ignored
c.BAGS[8078] = 120
RunLongTimers(3)
assert(RF.Yield(10139) == 20, "one cast made 20")
c.MYLEVEL = 51
assert(RF.Yield(10139) == nil, "a new level: not assumed")
c.MYLEVEL = 50

-- The cue to let go: once, when a kind reaches what is needed just after a conjure.
c.BAGS[8077], c.BAGS[8078] = 0, 0
c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
c.notices = {}
castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 10139)
c.BAGS[8077], c.BAGS[8078] = 200, 200
c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
local cues = 0
for _, n in ipairs(c.notices) do if n:find("Enough water", 1, true) then cues = cues + 1 end end
assert(cues == 1, "one line when water is enough: " .. cues)
c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
cues = 0
for _, n in ipairs(c.notices) do if n:find("Enough water", 1, true) then cues = cues + 1 end end
assert(cues == 1, "and not again")

-- Diagnostics: counts and IDs, never names or GUIDs.
local report = R.Diag.Build()
assert(report:find("== Mage refreshments ==", 1, true) and report:find("group: raid", 1, true), "the section is there")
for _, secret in ipairs({ "Thrall", "Garrosh", "Jaina", "G-1", "G-2", "G-9", "SHAMAN" }) do
  assert(not report:find(secret, 1, true), "the report leaves out " .. secret)
end

-- Leaving the group: a new session.
c.ROSTER, c.RAID = {}, false
c.FireEvent("GROUP_LEFT"); c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
assert(RF.Entry("G-1") == nil and #RF.Plan().rows == 0 and RF.Plan().context == "solo", "forgotten on leaving the group")

-- Turning it off: nothing listens, the buttons go empty, the session is gone.
c.ROSTER = { party1 = { guid = "G-1", name = "Thrall", class = "SHAMAN", level = 40 } }
c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
RF.MarkSupplied("G-1")
c.TwichUIDB.modules.mageRefreshments = false
RF.Refresh()
assert(#RF.Snapshot().events == 0 and RF.Entry("G-1") == nil, "off: unregistered and forgotten")
assert(water.attrs.type == nil and water.attrs.spell == nil, "off: its key does nothing")
assert(broker.text == "Off", "the data bar says it is off")
c.printed = {}
assert(not P.Open() and c.printed[#c.printed]:find("turned off", 1, true))
c.TwichUIDB.modules.mageRefreshments = true
RF.Refresh(); FlushTimers()
assert(RF.Entry("G-1").water == 0 and water.attrs.spell, "on again: a fresh session, the buttons back")

---------------------------------------------------------------------------
-- Another class: nothing registered, a clear answer.
---------------------------------------------------------------------------
do
  local w = MakeClient("Warrior", { "!!!TwichUI" })
  w.CreateFrame = c.CreateFrame
  w.UnitClass = function() return "Warrior", "WARRIOR" end
  w.InCombatLockdown = function() return false end
  w.UIParent, w.UISpecialFrames, w.UIErrorsFrame = c.UIParent, {}, c.UIErrorsFrame
  w.printed = {}
  w.print = function(s) table.insert(w.printed, tostring(s)) end
  local wbrokers = {}
  local wLDB = w.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  wLDB.NewDataObject = function(_, name, o) wbrokers[name] = o; return o end
  Load(w, { "chronicle/Style.lua", "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
    "modules/MageTravel.lua", "modules/MageConjure.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua", "modules/RefreshmentsBroker.lua" })
  w.TwichUIDB = { modules = { mageRefreshments = true } }
  w.LOADED["!!!TwichUI"] = true; w.FireEvent("ADDON_LOADED", "!!!TwichUI"); w.FireEvent("PLAYER_LOGIN"); FlushTimers()
  local WR = w.TwichUI
  assert(not WR.Refreshments.Enabled() and #WR.Refreshments.Snapshot().events == 0, "not a Mage: nothing listens, even switched on")
  assert(not WR.RefreshmentsPanel.Open() and w.printed[#w.printed]:find("for Mages", 1, true), "and it says why")
  assert(wbrokers["TwichUI Mage Refreshments"] == nil and wbrokers["TwichUI Chronicle"], "no refreshments plugin for another class (the Chronicle's is for everyone)")
end

---------------------------------------------------------------------------
-- Turned on in combat (a reload mid-fight): the secure buttons wait for combat to end.
---------------------------------------------------------------------------
do
  local m = MakeClient("Late", { "!!!TwichUI" })
  for _, k in ipairs({ "CreateFrame", "UIParent", "UIErrorsFrame", "GameTooltip", "UnitClass", "UnitLevel", "C_SpellBook", "Enum", "C_Spell",
    "C_Item", "C_Container", "IsInRaid", "IsInGroup", "UnitExists", "UnitGUID", "UnitIsUnit", "GetUnitName", "UnitIsConnected" }) do m[k] = c[k] end
  m.UISpecialFrames = {}
  m.InCombatLockdown = function() return COMBAT end
  c.ROSTER = {}
  Load(m, { "chronicle/Style.lua", "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
    "modules/MageTravel.lua", "modules/MageConjure.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua" })
  m.TwichUIDB = { modules = { mageRefreshments = true } }
  c.TwichUIRefreshmentsWater = nil
  COMBAT = true
  m.LOADED["!!!TwichUI"] = true; m.FireEvent("ADDON_LOADED", "!!!TwichUI"); m.FireEvent("PLAYER_LOGIN"); m.FireEvent("PLAYER_ENTERING_WORLD", false, true)
  FlushTimers()
  assert(m.TwichUIRefreshmentsWater == nil and c.TwichUIRefreshmentsWater == nil, "no secure frames made in combat")
  COMBAT = false
  m.FireEvent("PLAYER_REGEN_ENABLED")
  assert(c.TwichUIRefreshmentsWater and c.TwichUIRefreshmentsWater.attrs.spell == 10139, "made, with their spell, as combat ends")
end

print("REFRESHMENTS TESTS PASSED")
