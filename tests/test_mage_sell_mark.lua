-- Mage selling, "Mark as junk with EllesmereUI" mode. The same classifier as selling, the mode setting and its
-- confirmation, what is marked and when, repeated and delayed looks, changed bag slots, EllesmereUI absent,
-- turned off, not started or its Junk Marker off, EllesmereUI's own Auto Sell Junk off, switching modes and
-- turning the feature off, marks the player made themselves, and that TwichUI sells nothing in this mode.
-- The EllesmereUI mock follows what its source does (EllesmereUIBags_Categories.lua, 9.5.5): marks are item ID
-- assignments to "Junk", IsJunk is true for a mark and for an unfiled grey item. Whether the real addon does it,
-- and what its bags show afterwards, is for the game.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI", "EllesmereUI", "EllesmereUIBags", "EllesmereUIQoL" })
local function Fake(name)
  local o = { shown = false, scripts = {}, hooks = {}, events = {}, attrs = {}, enabled = true }
  return setmetatable(o, { __index = function(_, k)
    if k == "Show" then return function(s) s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(s) end end end
    if k == "Hide" then return function(s) s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetStringWidth" or k == "GetStringHeight" then return function() return 10 end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    return function() end
  end })
end
c.CreateFrame = function(_, name) return Fake(name) end
c.UIParent = Fake()
c.UISpecialFrames = {}
c.GameTooltip = Fake()
c.R_OUT = {}
c.print = function(s) table.insert(c.R_OUT, tostring(s)) end
c.CLASS, c.COMBAT = "MAGE", false
c.UnitClass = function() return "Mage", c.CLASS end
c.InCombatLockdown = function() return c.COMBAT end
c.HEALTH, c.MANA = "Health", "Mana"
c.ITEM_CONJURED, c.ITEM_BIND_QUEST, c.ITEM_STARTS_QUEST = "Conjured Item", "Quest Item", "This Item Begins a Quest"
c.BUYBACK_ITEMS_PER_PAGE = 12
c.NUM_BAG_SLOTS = 4
c.MERCHANT_UP = false
c.MerchantFrame = { IsShown = function() return c.MERCHANT_UP end }

c.BAGS, c.ITEMS, c.UNCACHED, c.REQUESTED, c.NOTIP, c.USED = {}, {}, {}, {}, {}, {}
c.INFO_CALLS, c.ON_INFO_CALL = 0, nil
c.C_Container = {
  GetContainerNumSlots = function(bag) return c.BAGS[bag] and 40 or 0 end,
  GetContainerItemInfo = function(bag, slot)
    c.INFO_CALLS = c.INFO_CALLS + 1
    if c.ON_INFO_CALL then c.ON_INFO_CALL(c.INFO_CALLS) end
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    if not s then return nil end
    local i = c.ITEMS[s.id]
    return { itemID = s.id, stackCount = s.count, isLocked = s.locked or false, isBound = s.bound or false,
      hasNoValue = s.noValue or false, iconFileID = 100 + s.id, itemName = i and i.name, quality = i and i.quality }
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    return { isQuestItem = s and s.quest or false, questID = s and s.questID, isActive = false }
  end,
  UseContainerItem = function(bag, slot) table.insert(c.USED, { bag, slot }) end,
}
c.C_Item = {
  GetItemInfoInstant = function(id) local i = c.ITEMS[id]; if not i then return end return id, "", "", "", 100 + id, i.class, i.sub end,
  GetItemInfo = function(id)
    local i = c.ITEMS[id]
    if not i or c.UNCACHED[id] then return end
    return i.name, "link", i.quality, 1, 1, "", "", 20, "", 100 + id, i.price
  end,
  GetItemSpell = function(id) local i = c.ITEMS[id]; if i and i.spell then return i.spellName, i.spell end end,
  RequestLoadItemDataByID = function(id) c.REQUESTED[id] = true end,
}
c.C_Spell = {
  GetSpellName = function(id) return ({ [434] = "Food", [431] = "Drink" })[id] end,
  GetSpellDescription = function(id) for _, i in pairs(c.ITEMS) do if i.spell == id then return i.text end end end,
  RequestLoadSpellData = function() end,
}
c.C_TooltipInfo = {
  GetBagItem = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    local i = s and c.ITEMS[s.id]
    if not i or c.NOTIP[s.id] then return nil end
    local lines = { { leftText = i.name }, { leftText = "Use: restores" } }
    for _, extra in ipairs(i.tip or {}) do table.insert(lines, { leftText = extra }) end
    return { lines = lines }
  end,
}

-- EllesmereUI, as its source behaves. Everything TwichUI is not meant to call is counted.
c.EllesmereUIDB = { bagItemAssignments = {}, autoSellJunk = true }
local EUI = { assign = {}, toggle = 0, unassign = 0, sellJunk = 0, repaint = 0, rawWrites = 0 }
local CM = { JUNK_KEY = "Junk" }
function CM:IsJunkMarkerEnabled() return c.MARKER ~= false end
function CM:IsJunk(itemID, quality)
  if not self:IsJunkMarkerEnabled() or not itemID then return false end
  local assigned = c.EllesmereUIDB.bagItemAssignments[itemID]
  if assigned == self.JUNK_KEY then return true end
  if assigned then return false end
  if quality == nil then quality = select(3, c.C_Item.GetItemInfo(itemID)) end
  return quality == 0
end
function CM:AssignItem(itemID, key)
  table.insert(EUI.assign, itemID)
  if c.FORGETFUL then return end            -- something that does not keep the mark
  c.EllesmereUIDB.bagItemAssignments[itemID] = key
end
function CM:ToggleJunk() EUI.toggle = EUI.toggle + 1 end
function CM:UnassignItem() EUI.unassign = EUI.unassign + 1 end
c.EUI_CategoryManager = CM
c.EUI_Bags = {
  RefreshInventory = function() EUI.repaint = EUI.repaint + 1; if c.REPAINT_FIRES then c.FireEvent("BAG_UPDATE_DELAYED") end end,
  SellJunk = function() EUI.sellJunk = EUI.sellJunk + 1 end,
}
c.LOADED["EllesmereUI"], c.LOADED["EllesmereUIBags"], c.LOADED["EllesmereUIQoL"] = true, true, true

local FOOD, DRINK = "Restores %d health over 21 sec.  Must remain seated while eating.", "Restores %d mana over 21 sec.  Must remain seated while drinking."
local function Item(id, name, o)
  local i = { class = 0, sub = 5, name = name, quality = 1, price = 25, spell = 10000 + id, spellName = "Food", text = FOOD:format(243) }
  for k, v in pairs(o or {}) do i[k] = v end
  c.ITEMS[id] = i
end
local function Drink(id, name, o)
  Item(id, name, { spellName = "Drink", text = DRINK:format(420) })
  for k, v in pairs(o or {}) do c.ITEMS[id][k] = v end
end
local function Bags(list)
  c.BAGS = { [0] = {} }
  for i, e in ipairs(list) do
    local s = { id = e[1], count = e[2] or 5 }
    for k, v in pairs(e[3] or {}) do s[k] = v end
    c.BAGS[0][i] = s
  end
end

for _, f in ipairs({ "chronicle/Style.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/FoodDrink.lua",
  "modules/EllesmereJunk.lua", "modules/MageSell.lua", "modules/MageSellWindow.lua"}) do
  local chunk = loadfile(ROOT .. f)
  if chunk then setfenv(chunk, c); chunk("!!!TwichUI", {}) end
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local MS, W, EJ = R.MageSell, R.MageSellWindow, R.EllesmereJunk
local M = c.TwichUIDB.modules
local events = R.frame.events
local ASSIGN = c.EllesmereUIDB.bagItemAssignments

local function Says(pattern)
  for _, line in ipairs(c.R_OUT) do if line:find(pattern, 1, true) then return true end end
  return false
end
local function Look()                     -- a bag change, and the moment passes
  c.FireEvent("BAG_UPDATE_DELAYED")
  FlushTimers()
end
local function Visit()
  c.MERCHANT_UP = true
  c.FireEvent("MERCHANT_SHOW")
  FlushTimers()
end
local function Leave() c.MERCHANT_UP = false; c.FireEvent("MERCHANT_CLOSED") end
local function Marked() local out = {} for id, v in pairs(ASSIGN) do if v == "Junk" then out[#out + 1] = id end end table.sort(out) return out end
local function Ids() return table.concat(Marked(), ",") end
local function Wipe() for k in pairs(ASSIGN) do ASSIGN[k] = nil end end
local function Fresh()                    -- no marks, and no memory of what this session marked
  Wipe(); EUI.assign = {}
  local on = M.mageSell
  M.mageSell = false; MS.Refresh()
  M.mageSell = on; MS.Refresh()
end
local function NothingForbidden(tag)
  assert(EUI.toggle == 0 and EUI.unassign == 0 and EUI.sellJunk == 0, tag .. ": TwichUI never toggles, unmarks or sells in EllesmereUI")
  assert(#c.USED == 0, tag .. ": TwichUI sold nothing itself")
end

-- the same bags the selling test's classifier is run on
Item(4540, "Tough Hunk of Bread")
Item(4541, "Hearty Bread", { price = 60 })
Drink(1179, "Ice Cold Milk", { price = 40 })
Item(3448, "Senggin Root", { spell = 2639, text = "Restores 282 health and 282 mana over 21 sec. Must remain seated while eating.", price = 10 })
Item(5349, "Conjured Muffin", { price = 0 })
Item(9001, "Conjured Mystery Roll", { price = 5, tip = { "Conjured Item" } })
Item(9004, "Feast of Plenty", { text = FOOD:format(243) .. " Well Fed: gain 8 Stamina for 15 min." })
Item(9005, "Quest Cheese", { price = 5 })
Item(9009, "My Favourite Bread", { price = 5 })
Item(9010, "Unloaded Bread", { price = 5 })
Item(9014, "Pastry I Filed Myself", { price = 5 })
Item(9015, "Grey Crumbs", { price = 1, quality = 0 })
Item(118, "Lesser Healing Potion", { sub = 1, spell = 9118, spellName = "Lesser Healing Potion", text = "Restores 150 to 170 health instantly." })
local function StandardBags()
  Bags({ { 4540, 5 }, { 4541, 3 }, { 1179, 10 }, { 3448, 4 }, { 5349, 20 }, { 9001, 6 }, { 9004, 5 }, { 9005, 5, { quest = true } },
    { 118, 3 } })
end
StandardBags()
c.UNCACHED, c.NOTIP = {}, {}
MS.OnChange = nil

---------------------------------------------------------------------------
-- The mode setting: direct unless explicitly "ellesmere"; confirming comes first; the confirmation stays local.
---------------------------------------------------------------------------
do
  assert(MS.Mode() == "direct" and MS.DEFAULT_MODE == "direct", "a new or existing install sells directly")
  assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.mageSellMode == nil, "the default is not written over anything")
  c.TwichUIDB.ui = { mageSellMode = "banana" }
  assert(MS.Mode() == "direct", "a damaged value is the default")
  c.TwichUIDB.ui.mageSellMode = 7
  assert(MS.Mode() == "direct")
  c.TwichUIDB.ui = {}
  local ok, why = MS.SetMode("ellesmere")
  assert(ok == false and why == "needs-ack" and MS.Mode() == "direct", "choosing EllesmereUI needs the confirmation first")
  assert(MS.SetMode("banana") == false)
  assert(MS.SetMode("direct") == true and c.TwichUIDB.ui.mageSellMode == "direct")
  assert(MS.Acknowledged() == false)
  assert(MS.Acknowledge() and MS.Acknowledged() == true and c.TwichUIDB.ui.mageSell.euiAck == true)
  -- the never-sell list is a sibling, not replaced
  assert(MS.Exclude(9009) and MS.Acknowledged(), "the list and the confirmation live side by side")
  assert(MS.Include(9009))
  c.TwichUIDB.ui.mageSell.euiAck = "yes"
  assert(MS.Acknowledged() == false, "only an explicit true counts")
  c.TwichUIDB.ui.mageSell.euiAck = nil
  assert(MS.Acknowledged() == false)
  c.TwichUIDB.ui = {}
end

---------------------------------------------------------------------------
-- The feature off: nothing listens. On in direct mode: selling is as it always was, and nothing is marked.
---------------------------------------------------------------------------
do
  assert(MS.Enabled() == false and not events.BAG_UPDATE_DELAYED and not events.MERCHANT_SHOW, "off: nothing listens")
  M.mageSell, M.mageSellDryRun = true, false
  MS.Refresh()
  assert(MS.Mode() == "direct" and MS.SellsDirectly() and not MS.Marks())
  assert(events.MERCHANT_SHOW and events.MERCHANT_CLOSED, "direct: it listens at a merchant")
  assert(not events.GET_ITEM_INFO_RECEIVED, "and for no bag changes while no sale is waiting")
  Look()
  assert(#EUI.assign == 0, "direct mode never marks")
  Visit()
  assert(#c.USED >= 1, "direct mode still sells at the merchant")
  assert(#EUI.assign == 0 and EUI.toggle == 0 and EUI.sellJunk == 0, "and never touches EllesmereUI")
  Leave()
  RunLongTimers(3)
  c.USED, c.R_OUT = {}, {}
  M.mageSell = false
  MS.Refresh()
end

---------------------------------------------------------------------------
-- EllesmereUI not available: nothing is marked, nothing is sold, the choice is kept and said, and marking
-- resumes by itself when it is.
---------------------------------------------------------------------------
local function UseMarking(dry)
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.mageSellMode = "ellesmere"
  MS.Acknowledge()
  M.mageSell, M.mageSellFood, M.mageSellDrink, M.mageSellDryRun = true, true, true, dry and true or false
  MS.Refresh()
  FlushTimers()
end
do
  Wipe(); StandardBags(); EUI.assign = {}
  UseMarking(false)
  assert(MS.Mode() == "ellesmere" and MS.Marks() and not MS.SellsDirectly())
  assert(select(1, MS.MarkState()) == "active", "ready: " .. tostring(select(1, MS.MarkState())))
  Fresh()

  local function Unavailable(tag, why, setup, undo)
    setup()
    local state, text = MS.MarkState()
    assert(state == why, tag .. ": " .. tostring(state))
    assert(text:find("Nothing is marked and nothing is sold"), tag .. ": says so in a sentence: " .. text)
    Look(); Visit(); Leave()
    assert(#EUI.assign == 0, tag .. ": nothing marked")
    assert(#c.USED == 0 and MS.Mode() == "ellesmere", tag .. ": not silently switched to selling")
    assert(MS.Marks() and not MS.SellsDirectly(), tag)
    undo()
  end
  Unavailable("not loaded", "not-loaded", function() c.LOADED.EllesmereUIBags = false end, function() c.LOADED.EllesmereUIBags = true end)
  Unavailable("turned off in the addon list", "disabled", function() OFF = { EllesmereUIBags = true }; c.LOADED.EllesmereUIBags = false end,
    function() OFF = nil; c.LOADED.EllesmereUIBags = true end)
  Unavailable("not installed", "not-installed", function()
    c.LOADED.EllesmereUIBags = false
    c.SAVED_EXISTS, c.C_AddOns.DoesAddOnExist = c.C_AddOns.DoesAddOnExist, function() return false end
  end, function() c.C_AddOns.DoesAddOnExist = c.SAVED_EXISTS; c.LOADED.EllesmereUIBags = true end)
  Unavailable("parent not loaded", "not-loaded", function() c.LOADED.EllesmereUI = false end, function() c.LOADED.EllesmereUI = true end)
  Unavailable("no accessor", "not-ready", function() c.EUI_CategoryManager = nil end, function() c.EUI_CategoryManager = CM end)
  Unavailable("no AssignItem", "not-ready", function() CM.AssignItem, c.SAVED_ASSIGN = nil, CM.AssignItem end,
    function() CM.AssignItem = c.SAVED_ASSIGN end)
  Unavailable("saved data not up", "not-ready", function() c.SAVED_DB, c.EllesmereUIDB = c.EllesmereUIDB, nil end,
    function() c.EllesmereUIDB = c.SAVED_DB end)
  Unavailable("junk marker off", "marker-off", function() c.MARKER = false end, function() c.MARKER = true end)
  Unavailable("client blocked", "blocked", function() c.EUI_CLIENT_BLOCKED = true end, function() c.EUI_CLIENT_BLOCKED = nil end)
  assert(select(1, MS.MarkState()) == "active")

  -- resumes when it loads: it was not loaded, bags changed, then it loaded
  c.LOADED.EllesmereUIBags = false
  Look()
  assert(#EUI.assign == 0)
  c.LOADED.EllesmereUIBags = true
  c.FireEvent("ADDON_LOADED", "EllesmereUIBags")
  FlushTimers()
  assert(Ids() == "1179,3448,4540,4541", "marking resumed once it was there: " .. Ids())
  NothingForbidden("resume")
  Fresh()
end

---------------------------------------------------------------------------
-- Needing the player's confirmation: a mode that arrived from a setup does nothing until confirmed here.
---------------------------------------------------------------------------
do
  c.TwichUIDB.ui.mageSell = nil
  c.TwichUIDB.ui.mageSellMode = "ellesmere"     -- as an import or a profile switch leaves it
  MS.Refresh(); FlushTimers()
  assert(MS.Acknowledged() == false and select(1, MS.MarkState()) == "needs-ack")
  Look(); Visit(); Leave()
  assert(#EUI.assign == 0 and #c.USED == 0 and MS.Mode() == "ellesmere", "chosen but not confirmed: nothing marked, nothing sold")
  MS.Acknowledge(); MS.Refresh(); FlushTimers()
  assert(Ids() == "1179,3448,4540,4541", "confirmed: marking starts: " .. Ids())
  Fresh()
end

---------------------------------------------------------------------------
-- Dry run: counted and said at a merchant, never marked.
---------------------------------------------------------------------------
do
  UseMarking(true)
  assert(select(1, MS.MarkState()) == "dry-run")
  c.R_OUT = {}
  EUI.repaint = 0
  Look()
  assert(#EUI.assign == 0 and EUI.repaint == 0, "a dry run marks nothing and repaints nothing")
  assert(#c.R_OUT == 0, "and says nothing on a bag change")
  Visit()
  assert(Says("Dry run: would mark 4 kinds"), "once, at the merchant: " .. table.concat(c.R_OUT, " | "))
  assert(#EUI.assign == 0 and #c.USED == 0)
  c.R_OUT = {}
  c.FireEvent("MERCHANT_SHOW"); FlushTimers()
  assert(#c.R_OUT == 1, "opening it again is a new visit, and says it once")
  Leave()
  assert(MS.MarkLast() and MS.MarkLast().dry and MS.MarkLast().would == 4)
  M.mageSellDryRun = false
  MS.Refresh(); FlushTimers()
   assert(Ids() == "1179,3448,4540,4541", "dry run off: it marks")
  Fresh(); EUI.repaint = 0
end

---------------------------------------------------------------------------
-- Marking: the same eligibility as selling, repeated looks, and what is never touched.
---------------------------------------------------------------------------
do
  UseMarking(false)
  Fresh(); EUI.repaint = 0
  MS.ClearCache()
  local scan = MS.Scan(true)
  local expected = {}
  for _, v in ipairs(scan.eligible) do expected[#expected + 1] = v.id end
  table.sort(expected)
  assert(table.concat(expected, ",") == "1179,3448,4540,4541", "what a sale would take")
  assert(MS.Exclude(9009) and MS.IsExcluded(9009))
  table.insert(c.BAGS[0], { id = 9009, count = 5 })     -- on the never-sell list

  Look()
  assert(Ids() == table.concat(expected, ","), "marked exactly what selling would sell: " .. Ids())
  assert(ASSIGN[5349] == nil and ASSIGN[9001] == nil and ASSIGN[9004] == nil and ASSIGN[9005] == nil and ASSIGN[9009] == nil
    and ASSIGN[118] == nil, "conjured, buff food, quest, never-sell and potions are untouched")
  assert(EUI.repaint == 1, "one repaint after marking")
  local n = #EUI.assign
  Look(); Look()
  assert(#EUI.assign == n and EUI.repaint == 1, "repeated looks mark and repaint nothing: idempotent")
  NothingForbidden("marking")

  -- the kinds switches are the same ones
  Fresh()
  M.mageSellDrink = false; MS.Refresh(); FlushTimers()
  assert(Ids() == "4540,4541", "drink off: neither the milk nor the combined root: " .. Ids())
  M.mageSellDrink = true
  Fresh()

  -- marks the player made: kept, never counted as ours, never undone
  ASSIGN[4541] = "Junk"                     -- their own mark of an eligible item
  ASSIGN[118] = "Junk"                      -- their own mark of something this feature never touches
  ASSIGN[9014] = "My Pastries"              -- filed in a category of their own
  Bags({ { 4540, 5 }, { 4541, 3 }, { 9014, 5 }, { 118, 3 } })
  c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
  assert(ASSIGN[4541] == "Junk" and ASSIGN[118] == "Junk" and ASSIGN[9014] == "My Pastries", "their choices stand")
  local touched = {}
  for _, id in ipairs(EUI.assign) do touched[id] = true end
  assert(touched[4540] and not touched[4541] and not touched[118] and not touched[9014], "only the item that was nobody's yet")
  assert(MS.MarkLast().filed == 1 and MS.MarkLast().already == 1, "counted: " .. MS.MarkLast().filed .. " filed, " .. MS.MarkLast().already .. " already")
  Fresh()
  StandardBags()
  MS.Include(9009)
end

---------------------------------------------------------------------------
-- A grey food item is junk to EllesmereUI already: not marked.
---------------------------------------------------------------------------
do
  Bags({ { 9015, 4 } })
  Fresh()
  Look()
  assert(#EUI.assign == 0 and ASSIGN[9015] == nil, "already junk (grey) is left alone")
  StandardBags()
end

---------------------------------------------------------------------------
-- Stacks of one item: a mark is for the item, so every carried stack has to be eligible.
---------------------------------------------------------------------------
do
  Fresh()
  Bags({ { 4540, 5 }, { 4540, 3, { locked = true } } })
  Look()
  assert(#EUI.assign == 0, "one stack is locked: the item is not marked yet")
  assert(MS.MarkLast().mixed == 1)
  c.BAGS[0][2].locked = false
  Look()
  assert(Ids() == "4540", "unlocked: marked")
  Fresh()
  Bags({ { 4540, 5 }, { 4540, 3, { quest = true } } })
  Look()
  assert(#EUI.assign == 0, "one stack is flagged as a quest item: not marked")
  StandardBags()
end

---------------------------------------------------------------------------
-- Delayed item data: kept, asked for once, looked at again when it arrives; bounded when it never does.
---------------------------------------------------------------------------
do
  Fresh()
  Bags({ { 9010, 5 } })
  c.UNCACHED[9010] = true
  c.REQUESTED = {}
  Look()
  assert(#EUI.assign == 0 and c.REQUESTED[9010], "not loaded: not marked, and asked for")
  assert(events.GET_ITEM_INFO_RECEIVED, "listening for the data")
  c.UNCACHED[9010] = nil
  c.FireEvent("GET_ITEM_INFO_RECEIVED", 9010, true); FlushTimers()
  assert(Ids() == "9010", "it arrived: marked")
  assert(not events.GET_ITEM_INFO_RECEIVED, "and no longer listening for it")

  -- data that never comes: the looks stop
  Fresh()
  c.UNCACHED[9010] = true
  Look()
  local before = MS.Snapshot().marks.looks
  for _ = 1, 12 do c.FireEvent("GET_ITEM_INFO_RECEIVED", 9010, false); FlushTimers() end
  assert(MS.Snapshot().marks.looks - before <= 3 and #EUI.assign == 0, "bounded: " .. (MS.Snapshot().marks.looks - before))
  assert(not events.GET_ITEM_INFO_RECEIVED, "gave up listening until the bags change")
  c.UNCACHED[9010] = nil
  Look()
  assert(Ids() == "9010", "a bag change looks again")
  StandardBags()
end

---------------------------------------------------------------------------
-- Acquiring, moving, splitting and merging stacks.
---------------------------------------------------------------------------
do
  Fresh(); EUI.repaint = 0
  Bags({ { 4540, 5 } })
  Look()
  assert(Ids() == "4540" and #EUI.assign == 1)
  table.insert(c.BAGS[0], { id = 4541, count = 2 })                    -- picked up
  Look()
  assert(Ids() == "4540,4541" and #EUI.assign == 2, "a new item is marked as it arrives")
  c.BAGS[0][5], c.BAGS[0][1] = c.BAGS[0][1], nil                       -- moved
  Look()
  assert(#EUI.assign == 2, "moved: no new mark")
  c.BAGS[0][5].count = 3                                               -- split off two
  c.BAGS[0][7] = { id = 4540, count = 2 }
  Look()
  assert(#EUI.assign == 2, "split: no new mark")
  c.BAGS[0][5].count = 5                                               -- merged back
  c.BAGS[0][7] = nil
  Look()
  assert(#EUI.assign == 2 and EUI.repaint == 2, "merged: no new mark")
  c.BAGS[0][5] = nil                                                   -- all gone: the mark stays with EllesmereUI
  Look()
  assert(ASSIGN[4540] == "Junk", "TwichUI does not unmark when the last copy goes")
  NothingForbidden("stacks")
  StandardBags()
end

---------------------------------------------------------------------------
-- A slot that changed after the scan is not acted on.
---------------------------------------------------------------------------
do
  Fresh()
  Bags({ { 4540, 5 } })
  local stale = MS.Snapshot().marks.stale        -- (a snapshot reads the bags too)
  local base = c.INFO_CALLS
  c.ON_INFO_CALL = function(n) if n == base + 41 then c.BAGS[0][1] = nil end end   -- after the 40-slot scan, at the re-check
  c.FireEvent("BAG_UPDATE_DELAYED"); FlushTimers()
  c.ON_INFO_CALL = nil
  assert(#EUI.assign == 0, "the stack went before it was marked: nothing is asked of EllesmereUI")
  assert(MS.Snapshot().marks.stale == stale + 1)
  StandardBags()
end

---------------------------------------------------------------------------
-- Combat: held back, done when it ends. Our own repaint cannot start a cycle. A mark that does not stay is
-- tried a few times and left alone.
---------------------------------------------------------------------------
do
  Fresh()
  Bags({ { 4541, 3 } })
  c.COMBAT = true
  Look()
  assert(#EUI.assign == 0, "not in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers()
  assert(Ids() == "4541", "marked once combat ended")

  Fresh(); EUI.repaint = 0
  c.REPAINT_FIRES = true
  Bags({ { 4540, 5 } })
  Look()
  assert(Ids() == "4540" and EUI.repaint == 1, "its own repaint's bag event started nothing more: " .. EUI.repaint)
  c.REPAINT_FIRES = false

  Fresh()
  MS.Refresh(); FlushTimers()      -- a new settle: the attempt counts are the session's, so use a fresh item
  Item(9020, "Reset Bread", { price = 5 })
  Bags({ { 9020, 5 } })
  for _ = 1, 6 do Wipe(); Look() end
  local n = 0
  for _, id in ipairs(EUI.assign) do if id == 9020 then n = n + 1 end end
  assert(n == 1, "marked once; when it is taken off, the player's choice stands, it is not marked again (" .. n .. ")")
  assert(MS.Snapshot().marks.released >= 1)

  Item(9021, "Forgotten Bread", { price = 5 })
  Bags({ { 9021, 5 } })
  c.FORGETFUL = true
  for _ = 1, 6 do Look() end
  c.FORGETFUL = false
  n = 0
  for _, id in ipairs(EUI.assign) do if id == 9021 then n = n + 1 end end
  assert(n == 3 and MS.Snapshot().marks.failed >= 3, "a mark EllesmereUI doesn't keep is not claimed, and not retried forever (" .. n .. ")")
  StandardBags()
  Fresh()
end

---------------------------------------------------------------------------
-- EllesmereUI's own selling: described, never changed.
---------------------------------------------------------------------------
do
  assert(EJ.Selling() == "auto")
  c.EllesmereUIDB.autoSellJunk = false
  assert(EJ.Selling() == "button", "its Auto Sell Junk is off: marked items wait for its Sell Junk button")
  Look()
  assert(select(1, MS.MarkState()) == "active" and Ids() == "1179,3448,4540,4541", "marking goes on")
  assert(c.EllesmereUIDB.autoSellJunk == false, "its setting is never changed")
  c.LOADED.EllesmereUIQoL = false
  c.EllesmereUIDB.autoSellJunk = true
  assert(EJ.Selling() == "button", "its QoL module isn't loaded: no automatic selling")
  c.LOADED.EllesmereUIQoL = true
  NothingForbidden("selling")
  Visit(); Leave()
  assert(EUI.sellJunk == 0 and not events.MERCHANT_SHOW, "TwichUI neither calls its sell nor listens at a merchant")
  local snap = MS.Snapshot()
  assert(snap.mode == "ellesmere" and snap.acknowledged and snap.markState == "active" and snap.bridge == "ready")
  Fresh()
end

---------------------------------------------------------------------------
-- Window text
---------------------------------------------------------------------------
do
  local rows = W.Rows(MS.Scan(true))
  assert(rows[1].kind == "header" and rows[1].text:find("marked as junk in EllesmereUI"), rows[1].text)
  assert(rows[1].right == nil, "no price in a list of what is marked")
end

---------------------------------------------------------------------------
-- Switching modes, turning the feature off, profile changes: stops the old behaviour, never unmarks.
---------------------------------------------------------------------------
do
  Fresh()
  Look()
  local marked = Ids()
  assert(marked == "1179,3448,4540,4541")

  -- back to selling: marking stops, the marks stay
  local assigned = #EUI.assign
  assert(MS.SetMode("direct"))
  assert(not events.BAG_UPDATE_DELAYED and not events.PLAYER_REGEN_ENABLED, "marking no longer listens")
  table.insert(c.BAGS[0], { id = 9020, count = 5 })
  Look()
  assert(ASSIGN[9020] == nil and Ids() == marked, "nothing new is marked; nothing is unmarked")
  assert(EUI.unassign == 0 and EUI.toggle == 0, "switching modes never unmarks")
  Visit()
  assert(#c.USED >= 1 and #EUI.assign == assigned, "direct selling is back")
  Leave(); RunLongTimers(3); c.USED = {}

  -- a sale waiting when the mode changes is dropped
  Visit()
  assert(MS.Running() and #c.USED >= 1)
  local used = #c.USED
  assert(MS.SetMode("ellesmere"))
  assert(not MS.Running(), "the run was dropped")
  RunLongTimers(3); FlushTimers()
  assert(#c.USED == used, "and sells nothing more")
  Leave(); c.USED = {}

  -- off: both stop, marks stay
  M.mageSell = false
  MS.Refresh()
  assert(not events.BAG_UPDATE_DELAYED and not events.MERCHANT_SHOW and not events.GET_ITEM_INFO_RECEIVED, "nothing listens")
  Fresh()
  ASSIGN[4540] = "Junk"
  Look(); Visit(); Leave()
  assert(#EUI.assign == 0 and #c.USED == 0 and ASSIGN[4540] == "Junk", "off: nothing is marked, sold or unmarked")

  -- a look already waiting does nothing once the feature is off
  M.mageSell = true
  MS.Refresh()                          -- queues a look
  M.mageSell = false
  MS.Refresh()
  FlushTimers()
  assert(#EUI.assign == 0, "the waiting look was dropped")

  -- a profile change: the next profile may choose the other mode, or none
  M.mageSell = true
  c.TwichUIDB.ui.mageSellMode = "ellesmere"
  MS.Refresh(); FlushTimers()
  assert(events.BAG_UPDATE_DELAYED)
  c.TwichUIDB.ui.mageSellMode = "direct"
  R.Profiles.Refresh("switch")
  assert(not events.GET_ITEM_INFO_RECEIVED and MS.Mode() == "direct" and MS.SellsDirectly(), "follows the profile")
  assert(not events.BAG_UPDATE_DELAYED, "marking stopped with it")
  c.TwichUIDB.ui.mageSellMode = "ellesmere"
  R.Profiles.Refresh("switch")
  FlushTimers()
  assert(events.BAG_UPDATE_DELAYED and MS.Marks(), "and back")
  assert(MS.Acknowledged(), "the confirmation is not part of a profile")
  NothingForbidden("modes")
end

print("MAGE SELL MARK TEST PASSED")
