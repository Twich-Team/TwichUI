-- Auction posting tab (auction/Window.lua) with stand-in frames and auction
-- house: the tab attaches without touching Blizzard's tab list, opening it
-- searches nothing, picking an item searches that item once, the suggested
-- price fills in but nothing is posted until Post is clicked, and the game's
-- own confirmation is followed. A posting under the item's vendor value is flagged beside the price and
-- asks before it goes (Post anyway / Cancel), bound to the exact posting asked about.
for _, WITH_SKIN in ipairs({ false, true }) do
local env = setmetatable({}, {__index = _G})
env._G = env

FONTS = {}
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
    if k == "CreateTexture" then return function() return Obj() end end
    if k == "CreateFontString" then return function() local o = Obj(); FONTS[#FONTS + 1] = o; return o end end
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
  if kind == "ScrollFrame" then   -- a short viewport (two rows) that remembers where it is scrolled
    o.GetVerticalScroll = function(self) return rawget(self, "vscroll") or 0 end
    o.SetVerticalScroll = function(self, v) rawset(self, "vscroll", v) end
    o.GetHeight = function() return 48 end
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
local now = 100
env.GetTime = function() return now end
env.time = function() return 1790000000 end
env.date = function() return "14:32" end
local popupVisible = false
env.StaticPopup_Visible = function() return popupVisible end
-- The game's popups: what was asked, and whether it is still open.
env.ACCEPT, env.CANCEL = "Accept", "Cancel"
env.StaticPopupDialogs = {}
local asked, askedCount = nil, 0
env.StaticPopup_Show = function(key, text)
  local acceptButton = Obj()
  local popup = { which = key, open = true, accept = acceptButton }
  function popup:IsShown() return self.open end
  function popup:GetButton1() return acceptButton end
  asked = { key = key, text = text, dialog = env.StaticPopupDialogs[key], popup = popup }
  askedCount = askedCount + 1
  return popup
end
env.StaticPopup_Hide = function(key) if asked and asked.key == key then asked.popup.open = false end end
-- Vendor values (copper per item) the game has given; an item not listed has not been loaded.
local VENDOR, REQUESTS = {}, {}
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
  GetContainerNumSlots = function(bag) return bag == 0 and 10 or 0 end,
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
  GetItemInfo = function(id)
    if VENDOR[id] == nil then return end
    return "name", "link", 1, 1, 1, "Tradeskill", "Cloth", 20, "", 1, VENDOR[id]
  end,
  RequestLoadItemDataByID = function(id) REQUESTS[#REQUESTS + 1] = id end,
}

local AH = { sent = {}, posts = {}, confirms = {}, results = {}, needsConfirmation = false }
env.C_AuctionHouse = {
  IsSellItemValid = function(loc) return not At(loc).isBound end,
  GetItemCommodityStatus = function(loc)
    local id = At(loc).itemID
    if id == 9999 then return 0 end   -- details still loading
    return (id == 2589 or id == 4338 or id == 4306 or id == 14047) and 2 or 1
  end,
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
  PATH = "Interface\\AddOns\\!!!TwichUI\\",
  Print = function() end,
  S = WITH_SKIN and setmetatable({
    SetTabSelection = function(t, v) tabSel[t] = v end,
  }, { __index = function(_, k) return function(obj) skinCalls[k] = (skinCalls[k] or 0) + 1 end end }) or nil,
  On = function(_, e, fn) listeners[e] = listeners[e] or {}; table.insert(listeners[e], fn) end,
  Enabled = function(_, key) return not (env.DISABLED or {})[key] end,
}
local function Emit(e, ...) for _, fn in ipairs(listeners[e] or {}) do fn(...) end end
for _, file in ipairs({ "modules/Interact.lua", "chronicle/Style.lua", "auction/Price.lua", "auction/Scan.lua", "auction/Window.lua" }) do
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
-- The next row (the sword) is chosen and searched, as a click would; it is not posted.
assert(sword.sel.shown and not linen.sel.shown, "the next item is chosen after posting")
assert(AH.sent[#AH.sent][1] == "sell" and AH.sent[#AH.sent][2].itemID == 6097 and #AH.posts == 1)

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
assert(not sword.sel.shown and not postButton.enabled, "the sword was the last row: nothing is chosen now")
sword.scripts.OnClick(sword); Settle()
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6097, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })

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
assert(not sword.sel.shown, "done after the run (the sword was last, so nothing is chosen)")
sword.scripts.OnClick(sword)   -- idle again: a manual choice is accepted
assert(sword.sel.shown, "back to idle after the run")

-- After a posting goes through, the next row below it is chosen for the player (never posted).
do
  local COUNT = { [14047] = 5, [4338] = 15, [4306] = 10 }
  local NAMES = { [14047] = "Runecloth", [4338] = "Mageweave Cloth", [4306] = "Silk Cloth", [2589] = "Linen Cloth",
                  [7000] = "Axe", [9999] = "Mystery Goods" }
  local QUALITY = { [14047] = 3, [4338] = 2, [7000] = 3 }
  local function Stack(id, n, bound)
    return { itemID = id, itemName = NAMES[id], stackCount = n, quality = QUALITY[id] or 1, iconFileID = 1,
             hyperlink = "x", isBound = bound }
  end
  local function SetBags(...)
    local b = {}
    for i, e in ipairs({ ... }) do b[i] = Stack(e[1], e[2], e[3]) end
    BAGS[0] = b
  end
  local function Without(id)
    local b, out = BAGS[0], {}
    for _, e in ipairs(b) do if e.itemID ~= id then out[#out + 1] = e end end
    BAGS[0] = out
  end
  local function Rows()
    local out = {}
    for _, o in ipairs(created) do
      if o.kind == "Button" and rawget(o, "group") and o.shown then out[#out + 1] = o end
    end
    return out
  end
  local function Names()
    local t = {}
    for _, r in ipairs(Rows()) do t[#t + 1] = r.group.name end
    return table.concat(t, ",")
  end
  local function Chosen()
    local t = {}
    for _, r in ipairs(Rows()) do if r.sel.shown then t[#t + 1] = r.group.name end end
    return table.concat(t, ",")
  end
  local function Row(name)
    for _, r in ipairs(Rows()) do if r.group.name == name then return r end end
    error("no row " .. name)
  end
  local function Said(text)
    for _, f in ipairs(FONTS) do
      local t = rawget(f, "text")
      if type(t) == "string" and t:find(text, 1, true) then return true end
    end
    return false
  end
  local function Click(name, id)
    local r = Row(name)
    AH.results = { { unitPrice = 500, quantity = 10, numOwnerItems = 0 } }
    r.scripts.OnClick(r); Settle()
    Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id); Settle()
  end
  local function Answer(id)
    Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id); Settle()
  end
  local function Press() postButton.scripts.OnClick(postButton) end
  local scroll
  for _, o in ipairs(created) do if o.kind == "ScrollFrame" and not scroll then scroll = o end end

  env.C_AuctionHouse.GetAvailablePostCount = function(loc) return At(loc).stackCount end
  -- Axe is added later; runecloth, mageweave, linen (two stacks), silk, and one item still loading.
  SetBags({ 14047, 5 }, { 4338, 15 }, { 2589, 20 }, { 2589, 7 }, { 4306, 10 }, { 9999, 1 }, { 6948, 1, true })
  Fire("BAG_UPDATE_DELAYED")
  assert(Names() == "Runecloth,Mageweave Cloth,Linen Cloth,Silk Cloth,Mystery Goods", Names())
  assert(Chosen() == "", "nothing chosen yet: " .. Chosen())

  -- One click, one post; the row clicked while it is pending is ignored; the list changes meanwhile
  -- (mageweave gone, a new row on top) but "next" is still the row after mageweave: linen.
  Click("Mageweave Cloth", 4338)
  assert(Chosen() == "Mageweave Cloth" and postButton.enabled)
  local posts = #AH.posts
  Press()
  assert(#AH.posts == posts + 1, "one click, one post")
  Row("Linen Cloth").scripts.OnClick(Row("Linen Cloth"))
  assert(Chosen() == "Mageweave Cloth", "a click while posting changes nothing")
  Without(4338)
  table.insert(BAGS[0], 1, Stack(7000, 1))
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
  assert(Names() == "Axe,Runecloth,Linen Cloth,Silk Cloth,Mystery Goods", Names())
  assert(Chosen() == "Linen Cloth", "the next row after the posted one, not the first row: " .. Chosen())
  assert(#AH.posts == posts + 1, "nothing was posted for the next item")
  assert(AH.sent[#AH.sent][1] == "search" and AH.sent[#AH.sent][2].itemID == 2589, "its listings are searched")
  assert(qtyBox:GetNumber() == 20, "quantity filled as a click would: " .. qtyBox:GetNumber())
  Answer(2589)
  assert(priceBox.amount == 500 and postButton.enabled, "price suggested, Post ready for an explicit click")
  assert(Said("Posted 15 x Mageweave Cloth"), "the posting's outcome stays on screen")
  assert(scroll:GetVerticalScroll() == 24, "the chosen row is scrolled into view: " .. tostring(scroll:GetVerticalScroll()))
  Fire("BAG_UPDATE_DELAYED")
  assert(Chosen() == "Linen Cloth", "a later bag update keeps it")

  -- A refused posting does not advance.
  Press()
  assert(#AH.posts == posts + 2)
  Fire("AUCTION_HOUSE_POST_ERROR")
  assert(Chosen() == "Linen Cloth" and postButton.enabled, "stays on the item that wasn't posted")
  assert(Said("didn't accept"))

  -- Linen is two stacks in one row; the stack posted leaves the other behind, and the row stays,
  -- but the choice moves on to silk.
  Press()
  table.remove(BAGS[0], 3)   -- the 20 stack is gone
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 2)
  assert(Names() == "Axe,Runecloth,Linen Cloth,Silk Cloth,Mystery Goods", Names())
  assert(Row("Linen Cloth").group.count == 7, "the other stack is still there")
  assert(Chosen() == "Silk Cloth", "grouped item keeps its identity: " .. Chosen())
  Answer(4306)

  -- Silk is the last item that can be chosen (the one after it is still loading): the choice
  -- clears, Post is off, the list doesn't wrap to the top, and it all stays available.
  posts = #AH.posts
  Press()
  Without(4306)
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 3)
  assert(#AH.posts == posts + 1)
  assert(Chosen() == "", "end of list: nothing chosen, no wrap: " .. Chosen())
  assert(not postButton.enabled, "Post is off until something is chosen")
  assert(Said("No more items in this list."))
  Click("Runecloth", 14047)
  assert(Chosen() == "Runecloth" and postButton.enabled, "manual choice still works")

  -- The window closing in the middle of a posting: nothing is advanced afterwards.
  Press()
  Emit("AUCTION_HOUSE_CLOSED")
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 4)
  tab.scripts.OnClick(tab)
  assert(Chosen() == "", "reopened with nothing chosen: " .. Chosen())
  assert(#AH.posts == posts + 2)

  -- The page being hidden (another tab) while it posts: the posted item is still the chosen one.
  Click("Runecloth", 14047)
  Press()
  AHF:SetDisplayMode("Buy")
  assert(not page.shown)
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 5)
  tab.scripts.OnClick(tab)
  assert(Chosen() == "Runecloth", "no advance while the page isn't showing: " .. Chosen())
  assert(#AH.posts == posts + 3)
end

-- A posting under the item's vendor value: flagged beside the price, and Post asks first.
do
  local warn = page.vendorWarn
  assert(warn, "the warning strip exists")
  local function Stack(id, name, n) return { itemID = id, itemName = name, stackCount = n, quality = 1, iconFileID = 1, hyperlink = "|H" .. name .. "|h" } end
  BAGS[0] = { Stack(4338, "Mageweave Cloth", 15), Stack(4306, "Silk Cloth", 10), Stack(7000, "Axe", 3) }
  env.C_AuctionHouse.GetAvailablePostCount = function(loc) return At(loc).stackCount end
  Fire("BAG_UPDATE_DELAYED")
  local function Row(name)
    for _, o in ipairs(created) do
      if o.kind == "Button" and rawget(o, "group") and o.shown and o.group.name == name then return o end
    end
    error("no row " .. name)
  end
  local function Chosen()
    for _, o in ipairs(created) do
      if o.kind == "Button" and rawget(o, "group") and o.shown and o.sel.shown then return o.group.name end
    end
    return ""
  end
  local function Pick(name, id, results)
    AH.results = results
    local r = Row(name); r.scripts.OnClick(r); Settle()
    if id then Fire(id > 9000 and "ITEM_SEARCH_RESULTS_UPDATED" or "COMMODITY_SEARCH_RESULTS_UPDATED",
      id > 9000 and { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } or id) end
    Settle()
  end
  local function Press() postButton.scripts.OnClick(postButton) end
  local function Price(v) priceBox:SetAmount(v); Settle() end
  local base = #AH.posts
  local function Posts() return #AH.posts - base end
  local function Said(text)
    for _, f in ipairs(FONTS) do local t = rawget(f, "text"); if type(t) == "string" and t:find(text, 1, true) then return true end end
    return false
  end

  -- Vendor value not arrived yet: a restrained note, nothing is blocked, and it is asked for once.
  local cheap = { { unitPrice = 80, quantity = 10, numOwnerItems = 0 } }
  local n = #REQUESTS
  Pick("Mageweave Cloth", 4338, cheap)
  assert(priceBox.amount == 80 and qtyBox:GetNumber() == 15)
  assert(warn.shown and warn.title.text == "Vendor value unavailable" and not warn.icon.shown, "unknown is not 'safe' and not zero")
  assert(#REQUESTS == n + 1 and REQUESTS[#REQUESTS] == 4338, "its data was requested")
  A.UpdatePost(); A.UpdatePost()
  assert(#REQUESTS == n + 1, "requested once, not again and again")
  assert(postButton.enabled, "unknown vendor value never blocks posting")
  -- It arrives (an event, no polling): 100 each, so 80 each is below.
  VENDOR[4338] = 100
  Fire("GET_ITEM_INFO_RECEIVED", 4338, true)
  assert(warn.shown and warn.icon.shown and warn.title.text == "Below vendor value", tostring(warn.title.text))
  assert(warn.detail.text == "Buyout: 1200c per stack · Vendor: 1500c per stack",
    "detail: " .. tostring(warn.detail.text))
  assert(Posts() == 0)
  Fire("GET_ITEM_INFO_RECEIVED", 9999, true)   -- some other item: nothing to do

  -- Exactly the vendor value is not below; one copper less is. Empty and invalid prices say nothing about vendors.
  Price(100); assert(not warn.shown, "100 each is not below 100")
  Price(101); assert(not warn.shown)
  Price(99); assert(warn.shown and warn.detail.text:find("1485c", 1, true), "per stack: 99 x 15")
  Price(0); assert(not warn.shown, "no price: the usual check speaks, not a vendor warning")
  Price(80)

  -- Post asks; nothing is posted, the choice stays, and Post is off while the question is open.
  Press()
  assert(Posts() == 0 and asked and asked.key == "TWICHUI_AUCTION_BELOW_VENDOR" and askedCount == 1)
  assert(asked.text:find("Post below vendor value?", 1, true) and asked.text:find("|HMageweave Cloth|h ×15", 1, true), asked.text)
  assert(asked.text:find("Buyout: 1200c per stack", 1, true) and asked.text:find("Vendor value: 1500c per stack", 1, true))
  assert(asked.dialog.button1 == "Post anyway" and asked.dialog.button2 == "Cancel" and asked.dialog.hideOnEscape == true)
  assert(Chosen() == "Mageweave Cloth" and not postButton.enabled, "no advance, no second post while asked")
  Press()
  assert(askedCount == 1 and Posts() == 0, "pressing again opens no second question")

  -- Cancel: nothing is posted, nothing advances, the prices are still there to edit.
  asked.dialog.OnCancel(nil, nil, "clicked")
  assert(Posts() == 0 and Chosen() == "Mageweave Cloth" and priceBox.amount == 80 and postButton.enabled)
  asked.dialog.OnAccept()
  assert(Posts() == 0, "the cancelled question can no longer be accepted")

  -- A key held down as the question opens can't accept it: the button is held, and a press that gets through is refused.
  Press()
  local q = asked
  assert(askedCount == 2 and q.popup.accept.enabled == false, "Accept greyed for a moment")
  assert(q.dialog.OnAccept() == true and Posts() == 0, "an early accept leaves the question open and posts nothing")
  now = now + 2; RunTimers(1)
  assert(q.popup.accept.enabled == true, "Accept comes back")

  -- Terms changed while asking: the question is withdrawn, and the old answer posts nothing.
  Price(70)
  assert(not q.popup.open and postButton.enabled and Posts() == 0 and Said("That posting changed"))
  q.dialog.OnAccept()
  assert(Posts() == 0, "an answer to an old question posts nothing")
  Price(80)
  Press(); q = asked
  qtyBox:SetNumber(14)
  assert(not q.popup.open and Posts() == 0, "a new quantity withdraws it too")
  qtyBox:SetNumber(15)

  -- The window closing withdraws it and an answer afterwards does nothing.
  Press(); q = asked
  now = now + 2
  Emit("AUCTION_HOUSE_CLOSED")
  assert(not q.popup.open)
  q.dialog.OnAccept()
  assert(Posts() == 0, "closed auction house: nothing posted")
  tab.scripts.OnClick(tab)
  Fire("BAG_UPDATE_DELAYED")
  Pick("Mageweave Cloth", 4338, cheap)
  assert(Chosen() == "Mageweave Cloth" and priceBox.amount == 80)

  -- The posting changing without the page noticing (revalidated when the answer comes): refused, nothing posted.
  Press(); q = asked
  now = now + 2
  priceBox.amount = 90   -- no change callback
  q.dialog.OnAccept()
  assert(Posts() == 0 and Said("changed while you decided"), "a different price is never posted on old consent")
  priceBox.amount = 80; A.UpdatePost()

  -- Approved: exactly the posting asked about is sent, once, and only then does the next item come up.
  Press(); q = asked
  now = now + 2
  q.dialog.OnAccept(); q.dialog.OnAccept()
  assert(Posts() == 1, "one answer, one post")
  local sent = AH.posts[base + 1]
  assert(sent[1] == "commodity" and sent[4] == 15 and sent[5] == 80, "15 at 80 each, as asked")
  assert(Chosen() == "Mageweave Cloth", "nothing advances before the posting is through")
  Press()
  assert(Posts() == 1, "no new post while this one is under way")
  -- It goes through: the next item is chosen with its own warning, and carries nothing over.
  Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
  assert(Chosen() == "Silk Cloth", "next item: " .. Chosen())
  assert(not warn.shown, "no price yet for it, so the last item's warning is gone")
  assert(REQUESTS[#REQUESTS] == 4306, "its own vendor value is asked for")
  Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4306); Settle()
  assert(priceBox.amount == 80 and warn.title.text == "Vendor value unavailable", "unknown, not the last item's value")
  VENDOR[4306] = 500
  Fire("ITEM_DATA_LOAD_RESULT", 4306, true)
  assert(warn.title.text == "Below vendor value" and warn.detail.text:find("Vendor: 5000c per stack", 1, true), warn.detail.text)
  assert(Posts() == 1)
  Press()
  assert(Posts() == 1 and asked.text:find("Silk Cloth", 1, true), "Silk asks for itself; the last answer doesn't carry over")

  -- A refused posting keeps the choice, and the next press asks again.
  now = now + 2
  asked.dialog.OnAccept()
  assert(Posts() == 2)
  Fire("AUCTION_HOUSE_POST_ERROR")
  assert(Chosen() == "Silk Cloth" and postButton.enabled and warn.shown)
  Press()
  assert(Posts() == 2, "asks again after a failed post")
  asked.dialog.OnCancel(nil, nil, "clicked")

  -- Choosing another item withdraws the question.
  Press(); q = asked
  Row("Axe").scripts.OnClick(Row("Axe")); Settle()
  assert(not q.popup.open and Posts() == 2 and Chosen() == "Axe")

  -- A known zero (the vendor pays nothing) says nothing; an item posts several auctions of one.
  VENDOR[7000] = 0
  Price(5)
  assert(not warn.shown, "no vendor value: nothing to compare")
  Press()
  assert(Posts() == 3, "a known zero posts without asking")
  Fire("AUCTION_HOUSE_POST_ERROR")
  -- Three auctions of one axe each, 900 each against a vendor value of 1000 each: asked as three auctions.
  VENDOR[7000] = 1000   -- (a vendor value never really changes: picking the row again reads it afresh)
  Row("Axe").scripts.OnClick(Row("Axe")); Settle()
  qtyBox:SetNumber(3)
  Price(900)
  assert(warn.shown and warn.detail.text == "Buyout: 900c per item · Vendor: 1000c per item", warn.detail.text)
  local before = askedCount
  Press()
  assert(askedCount == before + 1 and Posts() == 3)
  assert(asked.text:find("3 auctions of 1 item each", 1, true), asked.text)
  assert(asked.text:find("All 3 auctions: Buyout 2700c · Vendor value 3000c", 1, true), asked.text)
  assert(asked.text:find("These auctions could sell for less", 1, true))
  now = now + 2
  asked.dialog.OnAccept()
  assert(Posts() == 4, "one answer covers the whole batch")
  local sentItem = AH.posts[#AH.posts]
  assert(sentItem[1] == "item" and sentItem[4] == 3 and sentItem[5] == nil and sentItem[6] == 900, "3 auctions at 900, as asked")
  Fire("AUCTION_HOUSE_POST_ERROR")
  Price(1000)
  assert(not warn.shown, "the vendor value exactly: no warning")
  Press()
  assert(Posts() == 5 and askedCount == before + 1, "at the vendor value it posts without asking")
  Fire("AUCTION_HOUSE_POST_ERROR")
end

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
