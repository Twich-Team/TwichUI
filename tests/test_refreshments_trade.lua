-- Mage refreshments, trade assistance: what one click would move (whole stacks, one split, loose stacks,
-- short, no bag room, a full window, two kinds); in a simulated trade: nothing moves until Fill is
-- clicked, only the planned conjured items move and only into empty slots 1-6, items already there count
-- and stay, a busy cursor, combat, a blocked action and someone outside the group stop it, a second click
-- waits for the game, the split lands and goes in; and delivery: counted on the game's completion message,
-- not on acceptance, a cancelled trade isn't counted, and without the message the offer waits for the
-- player to confirm or dismiss.
-- Mocks show TwichUI's own decisions. Whether the game lets an addon move items this way is for the game.
dofile(TESTS .. "harness.lua")

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

---------------------------------------------------------------------------
-- The planner, on its own.
---------------------------------------------------------------------------
local Plan
do
  local env = setmetatable({ TwichUI = { PATH = "", On = function() end, Off = function() end, OnInit = function() end,
    Enabled = function() return false end, Life = { Note = function() end } } }, { __index = _G })
  env.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
  Load(env, { "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageConjure.lua",
    "chronicle/Style.lua", "modules/Refreshments.lua", "modules/RefreshmentsTrade.lua" })
  Plan = env.TwichUI.RefreshmentsTrade.PlanMoves
end

local function S(...) local out = {} for i, n in ipairs({ ... }) do out[i] = { bag = 0, slot = i, count = n } end return out end
local function K(kind, need, stacks) return { kind = kind, item = kind == "water" and 1 or 2, need = need, stackSize = 20, stacks = stacks } end
local function Ops(r) local t = {} for _, m in ipairs(r.moves) do t[#t + 1] = m.op .. m.count end return table.concat(t, " ") end

local r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 40, S(20, 20, 20)) } })
assert(Ops(r) == "place20 place20", "whole stacks: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 25, S(20, 20)) } })
assert(Ops(r) == "place20 split5" and r.splitting.water == 5, "a full stack, then 5 split off for the next click: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 30, S(20, 15, 7)) } })
assert(Ops(r) == "place20 split10", "split from the 15 rather than send a 7 and a 3: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("food", 20, S(15, 15)) } })
assert(Ops(r) == "place15 split5", "a loose 15, then 5 split from the other: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("food", 20, S(13, 7)) } })
assert(Ops(r) == "place13 place7", "exactly what is owed from two loose stacks: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 20, S(20, 7)) } })
assert(Ops(r) == "place20", "the full stack, not the loose one: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = false, kinds = { K("water", 5, S(20)) } })
assert(Ops(r) == "" and r.noRoom.water == 5, "no bag slot to split into: nothing sent rather than a whole stack")
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 40, S(20, 13)) } })
assert(Ops(r) == "place20 place13" and r.short.water == 7, "short: everything there is, and how many are missing")
r = Plan({ freeSlots = 1, canSplit = true, kinds = { K("water", 40, S(20, 20)) } })
assert(Ops(r) == "place20" and r.slotsFull, "a full window stops it")
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 5, S(20)), K("food", 5, S(20)) } })
assert(Ops(r) == "split5" and r.splitting.water == 5 and r.later.food == 5, "one split per click; the other waits: " .. Ops(r))
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 0, S(20)) } })
assert(Ops(r) == "", "nothing owed, nothing moved")
r = Plan({ freeSlots = 6, canSplit = true, kinds = { K("water", 20, {}) } })
assert(Ops(r) == "" and r.short.water == 20, "none in the bags")

---------------------------------------------------------------------------
-- A Mage, a party, bags, a cursor and a trade window.
---------------------------------------------------------------------------
local Methods
local made = {}
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, attrs = {}, enabled = true }
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
  SetAttribute = function(s, k, v) s.attrs[k] = v end,
  GetAttribute = function(s, k) return s.attrs[k] end,
  CreateTexture = function() return Fake("texture") end,
  CreateFontString = function() return Fake("font") end,
  SetText = function(s, v) s.text = v end,
  GetText = function(s) return s.text end,
  SetEnabled = function(s, v) s.enabled = v and true or false end,
  IsEnabled = function(s) return s.enabled end,
  SetSize = function(s, w, h) s.w, s.h = w, h end,
}

local function Client(name)
  local c = MakeClient(name, { "!!!TwichUI" })
  c.CreateFrame = function(kind, fname, parent, template)
    local f = Fake(kind); f.name, f.parent, f.template = fname, parent, template
    if fname then c[fname] = f end
    return f
  end
  c.UIParent, c.UISpecialFrames = Fake("UIParent"), {}
  c.notices = {}
  c.UIErrorsFrame = { AddMessage = function(_, text) table.insert(c.notices, text) end }
  c.GameTooltip = setmetatable({}, { __index = function() return function() end end })
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitLevel = function(u) if u == "player" then return 50 end local m = c.ROSTER[u]; return m and m.level or 0 end
  c.UnitClass = function(u) if u == "player" then return "Mage", "MAGE" end local m = c.ROSTER[u]; return m and m.class, m and m.class end
  c.ROSTER = { party1 = { guid = "G-1", name = "Thrall", class = "SHAMAN", level = 40 } }
  c.IsInRaid = function() return false end
  c.IsInGroup = function() return next(c.ROSTER) ~= nil end
  c.UnitExists = function(u) return u == "player" or c.ROSTER[u] ~= nil end
  c.UnitIsUnit = function(a, b) return a == b end
  c.PARTNER = "G-1"
  c.UnitGUID = function(u)
    if u == "player" then return "Player-1-ME" end
    if u == "NPC" then return c.PARTNER end
    local m = c.ROSTER[u]; return m and m.guid
  end
  c.GetUnitName = function(u) local m = c.ROSTER[u]; return m and m.name end
  c.UnitIsConnected = function() return true end
  c.C_SpellBook = { IsSpellKnown = function() return true end }
  c.Enum = { SpellBookSpellBank = { Player = 0 } }
  c.C_Spell = { GetSpellName = function() return "Conjure" end, GetSpellTexture = function() return 1 end,
    GetSpellSubtext = function() return nil end, RequestLoadSpellData = function() end }

  -- Bags: bag 0 has 8 slots. The cursor holds { item, count, from = { bag, slot } }.
  c.BAG = {}
  c.CURSOR = nil
  c.calls = {}
  local function Count(item)
    local n = 0
    for _, s in pairs(c.BAG) do if s.item == item then n = n + s.count end end
    return n
  end
  c.C_Item = { GetItemCount = Count, GetItemMaxStackSizeByID = function() return 20 end }
  c.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
    GetContainerNumFreeSlots = function(bag)
      if bag ~= 0 then return 0, 0 end
      local n = 0; for i = 1, 8 do if not c.BAG[i] then n = n + 1 end end; return n, 0
    end,
    GetContainerItemInfo = function(bag, slot)
      local s = bag == 0 and c.BAG[slot]
      return s and { itemID = s.item, stackCount = s.count, isLocked = s.locked } or nil
    end,
    PickupContainerItem = function(_, slot)
      table.insert(c.calls, "pickup " .. slot)
      local s = c.BAG[slot]
      if c.CURSOR then
        if not s then c.BAG[slot] = { item = c.CURSOR.item, count = c.CURSOR.count, locked = true }; c.CURSOR = nil end   -- lands locked
      elseif s and not s.locked then
        c.CURSOR = { item = s.item, count = s.count, from = slot }; s.locked = true
      end
    end,
    SplitContainerItem = function(_, slot, n)
      table.insert(c.calls, "split " .. slot .. " " .. n)
      local s = c.BAG[slot]
      if s and not s.locked and not c.CURSOR and n < s.count then
        s.count = s.count - n; s.locked = true
        c.CURSOR = { item = s.item, count = n, split = slot }
      end
    end,
  }
  c.GetCursorInfo = function() if c.CURSOR then return "item", c.CURSOR.item end end
  c.ClearCursor = function()
    if c.CURSOR and c.CURSOR.from then c.BAG[c.CURSOR.from].locked = false end
    c.CURSOR = nil
  end
  -- The trade window: a placement shows only when acknowledged (Ack).
  c.TRADE, c.UNACKED = {}, {}
  c.GetTradePlayerItemInfo = function(i)
    local t = c.TRADE[i]
    if t then return "Item", 1, t.count, 1, nil, false, true, t.item end
  end
  c.GetTradePlayerItemLink = function() return nil end
  c.ClickTradeButton = function(i)
    table.insert(c.calls, "trade " .. i)
    assert(i >= 1 and i <= 6, "never the seventh slot")
    assert(not c.TRADE[i], "never onto something already there")
    if c.CURSOR then c.UNACKED[i] = { item = c.CURSOR.item, count = c.CURSOR.count, from = c.CURSOR.from }; c.CURSOR = nil end
  end
  function c.Ack()
    for i, t in pairs(c.UNACKED) do c.TRADE[i] = t; c.UNACKED[i] = nil; c.FireEvent("TRADE_PLAYER_ITEM_CHANGED", i) end
  end
  function c.Land()   -- splits reach the bags
    for _, s in pairs(c.BAG) do s.locked = false end
    for _, t in pairs(c.TRADE) do if t.from then c.BAG[t.from].locked = true end end   -- still in the window
    c.FireEvent("BAG_UPDATE_DELAYED")
  end

  Load(c, { "chronicle/Style.lua", "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
    "modules/MageTravel.lua", "modules/MageConjure.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua",
    "modules/RefreshmentsShares.lua", "modules/RefreshmentsTrade.lua", "diag/Diagnostics.lua", "diag/Refreshments.lua" })
  c.TwichUIDB = { modules = { mageRefreshments = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  return c
end

local c = Client("Rich")
local R = c.TwichUI
local RF, T = R.Refreshments, R.RefreshmentsTrade
assert(c.TwichUIDB.modules.mageRefreshmentsTrade == true, "on with refreshments, which are off by default")
assert(T.Enabled())

-- Thrall, level 40 shaman: 20 water at rank 5 (item 8077), 20 food at rank 5 (item 8075).
c.BAG[1] = { item = 8077, count = 20 }
c.BAG[2] = { item = 8077, count = 13 }
c.BAG[3] = { item = 8075, count = 15 }
c.BAG[4] = { item = 8075, count = 15 }
c.BAG[5] = { item = 2589, count = 20 }   -- linen cloth: never touched
c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()

-- Opening the trade moves nothing.
c.FireEvent("TRADE_SHOW")
local strip = c.TwichUIRefreshmentsTrade
assert(strip and strip.shown, "the strip shows under the trade window")
assert(#c.calls == 0, "nothing moves when a trade opens")
assert(strip.head.text:find("Thrall", 1, true) and strip.fill.enabled, "who, and Fill can be clicked")
assert(strip.w == 340, "the panel's look: a 1-pixel line round it")
R.RefreshmentsPanel.Style.Set("borderSize", 3)
assert(strip.w == 344, "and it follows a change of look while shown")
R.RefreshmentsPanel.Style.Reset()

-- A busy cursor: nothing is dropped or moved.
c.CURSOR = { item = 9999, count = 1 }
assert(not T.Fill() and #c.calls == 0 and strip.line.text:find("holding", 1, true), "puts nothing down for you")
c.CURSOR = nil

-- Combat: nothing.
c.COMBAT = true
assert(not T.Fill() and #c.calls == 0 and not strip.fill.enabled)
c.COMBAT = false

-- The first click: the full water stack, a loose 15 food, and 5 food split into an empty bag slot.
assert(T.Fill(), "the click worked")
assert(table.concat(c.calls, ","):find("^pickup 1,trade 1,pickup 3,trade 2,split 4 5,pickup 6$"), table.concat(c.calls, ","))
assert(c.BAG[6] and c.BAG[6].count == 5 and c.BAG[4].count == 10, "5 split into the empty slot")
assert(not c.CURSOR, "the cursor is left empty")
for _, call in ipairs(c.calls) do assert(not call:find("pickup 5", 1, true), "never the linen") end

-- A second click before the game answers does nothing (no second stack of the same thing).
c.calls = {}
assert(not T.Fill() and #c.calls == 0 and strip.line.text:find("Waiting", 1, true), "waits for the game")

-- The game shows them, the split lands; the next click adds the 5.
c.Ack(); c.Land()
assert(strip.fill.enabled, "ready for the last 5")
assert(T.Fill() and table.concat(c.calls, ",") == "pickup 6,trade 3", table.concat(c.calls, ","))
c.Ack(); c.Land()
assert(not strip.fill.enabled and strip.line.text:find("in the window", 1, true), "all in: " .. tostring(strip.line.text))
c.calls = {}
assert(not T.Fill() and #c.calls == 0, "and another click does nothing")

-- Accepting is not handing over. The game's completion message is.
c.FireEvent("TRADE_ACCEPT_UPDATE", 1, 0)
assert(RF.Entry("G-1").water == 0, "accepted, not yet counted")
c.ERR_TRADE_COMPLETE = "Trade complete."
c.FireEvent("UI_INFO_MESSAGE", 226, "Trade complete.")
c.FireEvent("TRADE_CLOSED"); c.FireEvent("TRADE_CLOSED")   -- the game can say it twice
assert(RF.Entry("G-1").water == 20 and RF.Entry("G-1").food == 20, "counted once, from the window as accepted")
assert(RF.RowFor("G-1").status == "supplied" and not strip.shown)
local handed = false
for _, n in ipairs(c.notices) do if n:find("Handed Thrall 20 water and 20 food", 1, true) then handed = true end end
assert(handed, "a short local line says so")
RunLongTimers(5)
assert(RF.Entry("G-1").water == 20, "not counted again")

-- A trade cancelled after you accepted: once the message has been seen working, no message means no trade.
RF.ClearGiven("G-1")
c.TRADE, c.UNACKED = {}, {}
c.FireEvent("TRADE_SHOW")
c.TRADE[1] = { item = 8077, count = 20 }   -- put in by hand: it counts towards the share
c.FireEvent("TRADE_PLAYER_ITEM_CHANGED", 1)
assert(strip.head.text:find("20 water", 1, true))
c.calls = {}
T.Fill(); c.Ack(); c.Land()
for _, call in ipairs(c.calls) do assert(call ~= "trade 1" and not call:find("pickup 1$"), "what you put in stays where it is") end
c.FireEvent("TRADE_ACCEPT_UPDATE", 1, 0)
c.FireEvent("TRADE_CLOSED")
RunLongTimers(5)
assert(RF.Entry("G-1").water == 0 and not RF.Unconfirmed("G-1"), "cancelled: nothing counted")
assert(T.Snapshot().lastOutcome == "not-completed")

-- Accepting, then the other side changing something, then closing: nothing.
c.TRADE = {}
c.FireEvent("TRADE_SHOW")
c.TRADE[1] = { item = 8077, count = 20 }
c.FireEvent("TRADE_ACCEPT_UPDATE", 1, 0)
c.FireEvent("TRADE_ACCEPT_UPDATE", 0, 0)
c.FireEvent("TRADE_CLOSED"); RunLongTimers(5)
assert(RF.Entry("G-1").water == 0 and T.Snapshot().lastOutcome == "closed")

-- Someone outside the group: no share, nothing moves.
c.TRADE, c.calls = {}, {}
c.PARTNER = "G-STRANGER"
c.FireEvent("TRADE_SHOW")
assert(not strip.fill.enabled and strip.line.text:find("Not in your group", 1, true))
assert(not T.Fill() and #c.calls == 0)
c.FireEvent("TRADE_CLOSED")
c.PARTNER = nil
c.FireEvent("TRADE_SHOW")
assert(not strip.fill.enabled and strip.line.text:find("Couldn't tell", 1, true), "a partner that can't be read gets nothing")
c.FireEvent("TRADE_CLOSED")
c.PARTNER = "G-1"

-- A blocked action stops filling for that trade.
c.TRADE, c.calls = {}, {}
c.FireEvent("TRADE_SHOW")
c.FireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "PickupContainerItem")
assert(strip.fill.enabled, "someone else's block isn't ours")
c.FireEvent("ADDON_ACTION_BLOCKED", "!!!TwichUI", "PickupContainerItem")
assert(not strip.fill.enabled and not T.Fill() and #c.calls == 0 and T.Snapshot().stats.blocked == 1)
c.FireEvent("TRADE_CLOSED")

-- Diagnostics: counts and codes, no names or GUIDs.
local report = R.Diag.Build()
assert(report:find("trade assistance", 1, true) and report:find("message codes seen during trades: 226", 1, true), "the codes seen, to check in the game")
for _, secret in ipairs({ "Thrall", "G-1", "G-STRANGER" }) do assert(not report:find(secret, 1, true), "leaves out " .. secret) end

-- Off: no trade listening, no strip.
c.TwichUIDB.modules.mageRefreshmentsTrade = false
T.Refresh()
c.calls = {}
c.FireEvent("TRADE_SHOW")
assert(not strip.shown and #T.Snapshot().events == 0, "off: nothing listens")
c.FireEvent("TRADE_CLOSED")

---------------------------------------------------------------------------
-- A client where the completion message is never seen: the offer waits for the player.
---------------------------------------------------------------------------
do
  local d = Client("Dee")
  local DRF = d.TwichUI.Refreshments
  d.BAG[1] = { item = 8077, count = 20 }
  d.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
  d.FireEvent("TRADE_SHOW")
  d.TwichUI.RefreshmentsTrade.Fill(); d.Ack(); d.Land()
  d.FireEvent("TRADE_ACCEPT_UPDATE", 1, 1)
  d.FireEvent("TRADE_CLOSED")
  assert(DRF.Entry("G-1").water == 0, "not counted at once")
  RunLongTimers(5)
  local u = DRF.Unconfirmed("G-1")
  assert(u and u.water == 20 and DRF.Entry("G-1").water == 0, "kept as offered, not handed over")
  local asked = false
  for _, n in ipairs(d.notices) do if n:find("couldn't confirm", 1, true) then asked = true end end
  assert(asked, "and says so")
  -- A new trade with them counts it, so it isn't given twice before it is sorted out.
  d.TRADE = {}
  d.FireEvent("TRADE_SHOW")
  d.calls = {}
  assert(d.TwichUIRefreshmentsTrade.line.text:find("wasn't confirmed", 1, true) and not d.TwichUIRefreshmentsTrade.fill.enabled,
    tostring(d.TwichUIRefreshmentsTrade.line.text))
  assert(not d.TwichUI.RefreshmentsTrade.Fill() and #d.calls == 0, "the unconfirmed water counts, so no more water goes in")
  d.FireEvent("TRADE_CLOSED")
  assert(DRF.ConfirmOffered("G-1") and DRF.Entry("G-1").water == 20 and not DRF.Unconfirmed("G-1"), "confirmed: handed over")
  DRF.ClearGiven("G-1")
  DRF.Offered("G-1", { water = 20, food = 0 })
  assert(DRF.DismissOffered("G-1") and DRF.Entry("G-1").water == 0 and not DRF.Unconfirmed("G-1"), "dismissed: not counted")
  assert(not DRF.Offered("G-STRANGER", { water = 20, food = 0 }), "only people in the session")
end

print("REFRESHMENTS TRADE TESTS PASSED")
