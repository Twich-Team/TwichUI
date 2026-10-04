-- Auction posting tab (auction/Window.lua) with stand-in frames and auction
-- house: the tab attaches without touching Blizzard's tab list, opening it
-- searches nothing, picking an item searches that item once, the suggested
-- price fills in but nothing is posted until Post is clicked, and the game's
-- own confirmation is followed.
for _, WITH_SKIN in ipairs({ false, true }) do
local env = setmetatable({}, {__index = _G})
env._G = env

local function Obj(o)
  o = o or {}
  o.shown = o.shown ~= false
  return setmetatable(o, {__index = function(t, k)
    if k == "SetText" then return function(s, v) rawset(s, "text", v) end end
    if k == "GetText" then return function(s) return rawget(s, "text") end end
    if k == "IsShown" then return function(s) return rawget(s, "shown") end end
    if k == "Show" then return function(s)
      local was = rawget(s, "shown"); rawset(s, "shown", true)
      local sc = rawget(s, "scripts"); if not was and sc and sc.OnShow then sc.OnShow(s) end end end
    if k == "Hide" then return function(s)
      local was = rawget(s, "shown"); rawset(s, "shown", false)
      local sc = rawget(s, "scripts"); if was and sc and sc.OnHide then sc.OnHide(s) end end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetEnabled" then return function(s, v) rawset(s, "enabled", v and true or false) end end
    if k == "Enable" then return function(s) rawset(s, "enabled", true) end end
    if k == "Disable" then return function(s) rawset(s, "enabled", false) end end
    if k == "IsEnabled" then return function(s) return rawget(s, "enabled") ~= false end end
    if k == "SetScript" then return function(s, n, fn)
      local sc = rawget(s, "scripts"); if not sc then sc = {}; rawset(s, "scripts", sc) end; sc[n] = fn end end
    if k == "GetFrameLevel" then return function(s) return rawget(s, "level") or 10 end end
    if k == "SetFrameLevel" then return function(s, v) rawset(s, "level", v) end end
    if k == "SetFrameStrata" then return function(s, v) rawset(s, "strata", v) end end
    if k == "GetWidth" then return function() return 800 end end
    if k == "GetHeight" then return function() return 538 end end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return Obj() end end
    if k == "SetNumber" then return function(s, v) rawset(s, "number", v)
      local sc = rawget(s, "scripts"); if sc and sc.OnTextChanged then sc.OnTextChanged(s) end end end
    if k == "GetNumber" then return function(s) return rawget(s, "number") or 0 end end
    return function() end
  end})
end

local function MoneyInput()
  local m = Obj({ amount = 0 })
  m.CopperBox, m.SilverBox, m.GoldBox = Obj({ Icon = Obj() }), Obj({ Icon = Obj() }), Obj({ Icon = Obj() })
  function m:SetOnValueChangedCallback(fn) self.cb = fn end
  -- The boxes report a change a moment later, not during SetAmount.
  function m:SetAmount(v) self.amount = v; if self.cb then LATER[#LATER + 1] = self.cb end end
  function m:GetAmount() return self.amount end
  function m:Clear() self:SetAmount(0) end
  return m
end

local created = {}
LATER = {}
local function Settle() local l = LATER; LATER = {} for _, fn in ipairs(l) do fn() end end
env.CreateFrame = function(kind, _, parent, template)
  local o = template == "LargeMoneyInputFrameTemplate" and MoneyInput() or Obj()
  o.kind, o.template, o.parent = kind, template, parent
  o.shown = true
  if kind == "Frame" and parent == nil then   -- event frames
    o.events = {}
    function o:RegisterEvent(e) self.events[e] = true end
    function o:UnregisterEvent(e) self.events[e] = nil end
  end
  created[#created + 1] = o
  return o
end
local function Fire(e, ...)
  for _, fr in ipairs(created) do
    local ev, sc = rawget(fr, "events"), rawget(fr, "scripts")
    if ev and ev[e] and sc and sc.OnEvent then sc.OnEvent(fr, e, ...) end
  end
end
local timers = {}
env.C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end }
local function RunTimers(upTo) local t = timers; timers = {} for _, e in ipairs(t) do if e.d <= upTo then e.fn() else timers[#timers + 1] = e end end end

env.hooksecurefunc = function(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end
local tabCalls = { select = 0, deselect = 0, update = 0 }
env.PanelTemplates_SelectTab = function() tabCalls.select = tabCalls.select + 1 end
env.PanelTemplates_DeselectTab = function() tabCalls.deselect = tabCalls.deselect + 1 end
env.PanelTemplates_UpdateTabs = function() tabCalls.update = tabCalls.update + 1 end
env.PlaySound, env.SOUNDKIT = function() end, { IG_CHARACTER_INFO_TAB = 1 }
env.GetMoneyString = function(v) return tostring(v) .. "c" end
env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 4
env.AUCTION_DURATION_ONE, env.AUCTION_DURATION_TWO, env.AUCTION_DURATION_THREE = "2 Hours", "8 Hours", "24 Hours"
env.GameTooltip, env.GameTooltip_Hide, env.EditBox_ClearFocus = Obj(), function() end, function() end
env.GetCVar = function() return "2" end
env.GetMoney = function() return 1000000 end
env.InCombatLockdown = function() return false end
env.GetTime = function() return 100 end
env.time = function() return 1790000000 end
env.date = function() return "14:32" end
local popupVisible = false
env.StaticPopup_Visible = function() return popupVisible end
env.Enum = {
  ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
  AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
  ItemClass = { Weapon = 2, Armor = 4 },
}
env.ScrollUtil = { InitScrollFrameWithScrollBar = function() end }
env.C_AddOns = { IsAddOnLoaded = function() return false end }

-- Bags: linen cloth (commodity, two stacks), a sword (item), a bound hearthstone.
local BAGS = {
  [0] = { [1] = { itemID = 2589, itemName = "Linen Cloth", stackCount = 20, quality = 1, iconFileID = 1, hyperlink = "l" },
          [2] = { itemID = 6948, itemName = "Hearthstone", stackCount = 1, quality = 1, isBound = true, iconFileID = 2, hyperlink = "h" },
          [3] = { itemID = 2589, itemName = "Linen Cloth", stackCount = 7, quality = 1, iconFileID = 1, hyperlink = "l" },
          [4] = { itemID = 6097, itemName = "Sword of the Bear", stackCount = 1, quality = 1, iconFileID = 3, hyperlink = "s" } },
}
env.C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
local function At(loc) return BAGS[loc.bag] and BAGS[loc.bag][loc.slot] end
env.C_Item = {
  DoesItemExist = function(loc) return At(loc) ~= nil end,
  GetItemID = function(loc) local i = At(loc); return i and i.itemID end,
  GetStackCount = function(loc) local i = At(loc); return i and i.stackCount end,
  GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, id == 6097 and 2 or 7 end,
  GetCurrentItemLevel = function() return 25 end,
}

local AH = { sent = {}, posts = {}, confirms = {}, results = {}, needsConfirmation = false }
env.C_AuctionHouse = {
  IsSellItemValid = function(loc) return not At(loc).isBound end,
  GetItemCommodityStatus = function(loc) return At(loc).itemID == 2589 and 2 or 1 end,
  GetItemKeyFromItem = function(loc) return { itemID = At(loc).itemID, itemLevel = 25, itemSuffix = 1040, battlePetSpeciesID = 0 } end,
  GetItemKeyInfo = function() return { isEquipment = true } end,
  MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
  GetAvailablePostCount = function(loc) return At(loc).itemID == 2589 and 27 or 1 end,
  CalculateCommodityDeposit = function(_, _, q) return 15 * q end,
  CalculateItemDeposit = function() return 250 end,
  SupportsCopperValues = function() return true end,
  IsThrottledMessageSystemReady = function() return true end,
  SendSearchQuery = function(key) AH.sent[#AH.sent + 1] = { "search", key } end,
  SendSellSearchQuery = function(key) AH.sent[#AH.sent + 1] = { "sell", key } end,
  GetNumCommoditySearchResults = function() return #AH.results end,
  GetCommoditySearchResultInfo = function(_, i) return AH.results[i] end,
  HasFullCommoditySearchResults = function() return true end,
  GetNumItemSearchResults = function() return #AH.results end,
  GetItemSearchResultInfo = function(_, i) return AH.results[i] end,
  HasFullItemSearchResults = function() return true end,
  PostCommodity = function(...) AH.posts[#AH.posts + 1] = { "commodity", ... }; return AH.needsConfirmation end,
  PostItem = function(...) AH.posts[#AH.posts + 1] = { "item", ... }; return AH.needsConfirmation end,
  ConfirmPostCommodity = function(...) AH.confirms[#AH.confirms + 1] = { "commodity", ... } end,
  ConfirmPostItem = function(...) AH.confirms[#AH.confirms + 1] = { "item", ... } end,
  CancelSell = function() end,
}

-- TwichUI's own bits the tab uses.
local listeners = {}
local skinCalls, tabSel = {}, {}
env.TwichUI = {
  S = WITH_SKIN and setmetatable({
    SetTabSelection = function(t, v) tabSel[t] = v end,
  }, { __index = function(_, k) return function(obj) skinCalls[k] = (skinCalls[k] or 0) + 1 end end }) or nil,
  On = function(_, e, fn) listeners[e] = listeners[e] or {}; table.insert(listeners[e], fn) end,
  Enabled = function(_, key) return not (env.DISABLED or {})[key] end,
}
local function Emit(e, ...) for _, fn in ipairs(listeners[e] or {}) do fn(...) end end
for _, file in ipairs({ "chronicle/Style.lua", "auction/Price.lua", "auction/Scan.lua", "auction/Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, env); chunk("!!!TwichUI", {})
end
local A, SC = env.TwichUI.AuctionWindow, env.TwichUI.AuctionScan

-- Blizzard's window appears when its addon loads.
local blizzTabs = { Obj({ displayMode = "Buy" }), Obj({ displayMode = "ItemSell" }), Obj({ displayMode = "Auctions" }) }
local currentMode = "Buy"
local displayModes = 0
env.AuctionHouseFrame = Obj({
  Tabs = blizzTabs, AuctionsTab = blizzTabs[3],
  SetDisplayMode = function(_, m) displayModes = displayModes + 1; currentMode = m end,
  GetDisplayMode = function() return currentMode end,
  SellTab = blizzTabs[2],
  MoneyFrameBorder = Obj(), PortraitContainer = Obj({ portrait = Obj() }),
  SetDialogOverlayShown = function() end,
  ItemSellFrame = Obj({ shown = false, ConfirmPost = function() end }),
  CommoditiesSellFrame = Obj({ shown = false }), WoWTokenSellFrame = Obj({ shown = false }),
})
local AHF = env.AuctionHouseFrame
Emit("ADDON_LOADED", "Blizzard_AuctionHouseUI")
assert(#AHF.Tabs == 3, "Blizzard's tab list is untouched")

local tab, page
for _, o in ipairs(created) do
  if o.template == "AuctionHouseFrameTabTemplate" then tab = o end
end
assert(tab and tab.parent ~= AHF and tab.parent.parent == AHF, "our tab sits on our own holder")
for _, o in ipairs(created) do
  local sc = rawget(o, "scripts")
  if sc and sc.OnShow and o.parent == tab.parent and o ~= tab then page = o end
end
assert(page and not page.shown, "page built hidden")
assert(page.strata == "HIGH" and page.level == 500, "page above Blizzard's level-350 sell parts and HIGH-strata stars")
if WITH_SKIN then
  for _, k in ipairs({ "Tab", "Button", "EditBox", "Dropdown", "Panel", "ScrollBar", "Font" }) do
    assert(skinCalls[k], "EllesmereUI styles our " .. k)
  end
end

-- Opening the tab lists bag items and searches nothing.
tab.scripts.OnClick(tab)
assert(page.shown and tabCalls.select == 1, "page shown, our tab selected")
if WITH_SKIN then
  assert(tabSel[tab] == true and tabSel[blizzTabs[1]] == false and tabSel[blizzTabs[2]] == false, "skinned tabs follow our page")
end
assert(#AH.sent == 0, "opening sends no query")
local rows = {}
for _, o in ipairs(created) do
  local sc = rawget(o, "scripts")
  if o.kind == "Button" and sc and sc.OnClick and rawget(o, "group") then rows[#rows + 1] = o end
end
assert(#rows == 2, "two rows: linen (both stacks together) and the sword; the bound item is left out, got " .. #rows)
local linen, sword
for _, r in ipairs(rows) do if r.group.itemID == 2589 then linen = r else sword = r end end
assert(linen.group.count == 27)

-- Picking linen searches linen, once.
AH.results = { { unitPrice = 1240, quantity = 40, numOwnerItems = 0 }, { unitPrice = 1300, quantity = 5, numOwnerItems = 0 } }
linen.scripts.OnClick(linen)
Settle()   -- the cleared price box reports its change late
assert(#AH.sent == 1 and AH.sent[1][1] == "search" and AH.sent[1][2].itemID == 2589)
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
Settle()
assert(SC.state == "done")
assert(#AH.posts == 0, "results never post anything")

-- The price box got the suggestion; Post is enabled; still nothing posted.
local priceBox, postButton
for _, o in ipairs(created) do
  if o.template == "LargeMoneyInputFrameTemplate" then priceBox = o end
  if o.kind == "Button" and rawget(o, "text") == "Post" then postButton = o end
end
assert(priceBox.amount == 1240, "suggestion fills the empty price: " .. tostring(priceBox.amount))
assert(postButton.enabled, "Post enabled: " .. tostring(postButton.reason))
assert(#AH.posts == 0)

-- A price the player types is not overwritten by a later search.
priceBox:SetAmount(1500); Settle()
A.Search()
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(priceBox.amount == 1500, "player's price kept")
assert(#AH.sent == 2, "Search again sends one more query")

-- Clicking Post sends exactly what's on screen.
postButton.scripts.OnClick(postButton)
assert(#AH.posts == 1)
local p = AH.posts[1]
assert(p[1] == "commodity" and p[3] == 2 and p[4] == 20 and p[5] == 1500, "duration 2, 20 (first stack), 1500 each")
Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
assert(SC.stale, "results are old after posting")

-- Equipment: sell search without level or suffix; only the same variant prices it.
AH.results = {
  { itemKey = { itemID = 6097, itemLevel = 25, itemSuffix = 1041 }, buyoutAmount = 20000, quantity = 1 },
  { itemKey = { itemID = 6097, itemLevel = 25, itemSuffix = 1040 }, buyoutAmount = 45000, quantity = 1 },
}
sword.scripts.OnClick(sword)
Settle()
local q = AH.sent[#AH.sent]
assert(q[1] == "sell" and q[2].itemLevel == 0 and q[2].itemSuffix == 0)
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6097, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
assert(priceBox.amount == 45000, "other suffix not used: " .. tostring(priceBox.amount))

-- When the game asks for confirmation, only its own dialog's Accept confirms.
AH.needsConfirmation = true
popupVisible = true
postButton.scripts.OnClick(postButton)
assert(#AH.posts == 2 and #AH.confirms == 0)
assert(not postButton.enabled, "no second post while waiting")
RunTimers(1)
AHF.ItemSellFrame:ConfirmPost()                      -- the player clicked Accept
assert(#AH.confirms == 1 and AH.confirms[1][1] == "item" and AH.confirms[1][6] == 45000)
AHF:SetDialogOverlayShown(false)
Fire("AUCTION_HOUSE_AUCTION_CREATED", 2)

-- Cancelled confirmation: nothing confirmed, Post comes back.
postButton.scripts.OnClick(postButton)
AHF:SetDialogOverlayShown(false)                     -- dialog closed without Accept
AHF.ItemSellFrame:ConfirmPost()                      -- (a later Blizzard post of its own)
assert(#AH.confirms == 1, "cancelled post never confirmed")
assert(postButton.enabled)

-- Several of one item: the first "auction created" doesn't end it; the multisell run does.
AH.needsConfirmation = false
env.C_AuctionHouse.GetAvailablePostCount = function() return 3 end
local qtyBox
for _, o in ipairs(created) do if o.template == "InputBoxTemplate" then qtyBox = o end end
qtyBox:SetNumber(3)
postButton.scripts.OnClick(postButton)
local before = #AH.posts
assert(AH.posts[before][4] == 3, "quantity 3 sent")
Fire("AUCTION_HOUSE_AUCTION_CREATED", 3)
assert(not postButton.enabled, "still posting after the first auction")
Fire("AUCTION_MULTISELL_START", 3)
Fire("AUCTION_MULTISELL_UPDATE", 1, 3)
assert(not postButton.enabled)
Fire("AUCTION_MULTISELL_UPDATE", 3, 3)
assert(postButton.enabled, "done after the run")

-- Going back to a Blizzard tab hides our page; closing the auction house clears everything.
AHF:SetDisplayMode("Buy")
assert(not page.shown and tabCalls.update >= 1)
if WITH_SKIN then
  assert(tabSel[tab] == false and tabSel[blizzTabs[1]] == true and tabSel[blizzTabs[2]] == false, "back on Buy")
end
tab.scripts.OnClick(tab)
Emit("AUCTION_HOUSE_CLOSED")
assert(not page.shown and SC.state == "idle" and SC.listings == nil)

-- Turned off: the tab hides and won't open.
env.DISABLED = { auctionPosting = true }
A.Refresh()
assert(not tab.shown)
tab.scripts.OnClick(tab)
assert(not page.shown)

end
print("PASSED")
