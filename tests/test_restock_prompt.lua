dofile(TESTS .. "harness.lua")
-- Vendor restocking's question (modules/RestockPrompt.lua): TwichUI's own window for "Ask before purchasing".
--   * a real visit shows it instead of the game's dialog; one row per item with its icon, quality-colored name,
--     quantity, carried-of-target, and price with colored g/s/c letters; short items say how many and why;
--     the total, what you have and the spending limit; items beyond the visible rows are counted, not dropped;
--   * Purchase buys the approved plan (checked again, as before); Cancel, the close box and Esc buy nothing;
--   * putting it away for the code's own reasons (merchant closed, rule edited, combat) answers nothing;
--   * a stale Purchase says nothing was bought; asking again reuses the same frame and rows;
--   * where it can't be drawn, the game's dialog is used with the same words.
-- Stand-in frames keep their scripts, text, colors and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetTexture = function(s, t) s.texture = t end,
    SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end


local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MakeClient("Rich", { "!!!TwichUI" })
c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
c.UIParent = Fake("Frame"); c.UIParent.w, c.UIParent.h = 1920, 1080
c.GameTooltip = Fake("GameTooltip")
c.UISpecialFrames = {}
c.R_OUT = {}
c.print = function(s) table.insert(c.R_OUT, tostring(s)) end
c.COMBAT = false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitClass = function() return "Mage", "MAGE" end
c.CANCEL = "Cancel"
c.StaticPopupDialogs = {}
c.POPUPS, c.HIDDEN = {}, {}
c.StaticPopup_Show = function(name, text) table.insert(c.POPUPS, { name = name, text = text }); return {} end
c.StaticPopup_Hide = function(name) c.HIDDEN[name] = (c.HIDDEN[name] or 0) + 1 end

c.ITEMS = {
  [17020] = { name = "Arcane Powder", maxStack = 20, quality = 1 }, [17031] = { name = "Rune of Teleportation", maxStack = 20, quality = 1 },
  [2512] = { name = "Rough Arrow", maxStack = 200, quality = 1 }, [4000] = { name = "Moonwell Water", maxStack = 20, quality = 3 },
}
c.C_Item = {
  GetItemInfoInstant = function(id) if c.ITEMS[id] then return id, "", "", "", 1000 + id, 15, 0 end end,
  GetItemInfo = function(id) local i = c.ITEMS[id]; if i then return i.name, "[" .. i.name .. "]" end end,
  GetItemNameByID = function(id) local i = c.ITEMS[id]; return i and i.name end,
  GetItemIconByID = function(id) if c.ITEMS[id] then return 1000 + id end end,
  GetItemQualityByID = function(id) return c.ITEMS[id] and c.ITEMS[id].quality end,
  GetItemQualityColor = function(q) if q == 3 then return 0, 0.44, 0.87 end return 1, 1, 1 end,
  GetItemMaxStackSizeByID = function(id) return c.ITEMS[id] and c.ITEMS[id].maxStack end,
  GetItemFamily = function() return 0 end,
  RequestLoadItemDataByID = function() end,
}
for id in pairs(c.ITEMS) do c.ITEMS[id].link = "[" .. c.ITEMS[id].name .. "]" end
c.BAGS = {}
local function Bags(slots, size)
  c.BAGS = { [0] = { size = size or 16, slots = slots or {} } }
end
c.C_Container = {
  GetContainerNumSlots = function(bag) return c.BAGS[bag] and c.BAGS[bag].size or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
    if s then return { itemID = s[1], stackCount = s[2] } end
  end,
  GetContainerNumFreeSlots = function() return 10, 0 end,
}
c.MERCHANT, c.MERCHANT_UP, c.MONEY = {}, false, 500000
c.MerchantFrame = { IsShown = function() return c.MERCHANT_UP end }
c.GetMoney = function() return c.MONEY end
c.GetMerchantNumItems = function() return #c.MERCHANT end
c.GetMerchantItemID = function(i) local e = c.MERCHANT[i]; return e and e.id end
c.GetMerchantItemLink = function(i) local e = c.MERCHANT[i]; return e and c.ITEMS[e.id].link end
c.GetMerchantItemMaxStack = function() return 200 end
c.GetMerchantItemCostInfo = function() return 0 end
c.C_MerchantFrame = { GetItemInfo = function(i)
  local e = c.MERCHANT[i]
  if not e then return nil end
  return { name = "x", texture = 1, price = e.price, stackCount = e.stack or 1, numAvailable = e.avail or -1,
    isPurchasable = true, isUsable = true, hasExtendedCost = false }
end }
c.BOUGHT = {}
c.BuyMerchantItem = function(index, n) table.insert(c.BOUGHT, { index = index, n = n }) end

for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "modules/Interact.lua", "modules/Restock.lua", "modules/RestockPrompt.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local RS, PR = R.Restock, R.RestockPrompt
local function Flush() for _ = 1, 6 do FlushTimers() end end
local function Open() c.MERCHANT_UP = true; c.FireEvent("MERCHANT_SHOW"); Flush() end
local function Close() c.MERCHANT_UP = false; c.FireEvent("MERCHANT_CLOSED"); Flush() end
local function Rules(list) c.TwichUIDB.ui = c.TwichUIDB.ui or {}; c.TwichUIDB.ui.restock = { items = list }; RS.Refresh() end
local function Reset() c.R_OUT, c.BOUGHT, c.POPUPS, c.HIDDEN = {}, {}, {}, {} end
R:SetEnabled("restock", true)

local function Rows(f)
  local out = {}
  for _, ch in ipairs(f.list.children) do if ch.cost and ch.shown then out[#out + 1] = ch end end
  return out
end

---------------------------------------------------------------------------
-- 1. A visit shows the window, not the game's dialog
---------------------------------------------------------------------------
Check(RS.ColorMoney(131520) == "13|cffffd700g|r 15|cffc7c7cfs|r 20|cffeda55fc|r", "coins: colored letters on each unit: " .. RS.ColorMoney(131520))
Check(RS.ColorMoney(0) == "0|cffeda55fc|r" and RS.ColorMoney(500) == "5|cffc7c7cfs|r", "zero units are left out; none at all is 0c")
Check(RS.MoneyText(131520) == "13g 15s 20c", "the plain text is unchanged")

Rules({ { id = 17020, target = 20, enabled = true }, { id = 4000, target = 10, enabled = true } })
c.MERCHANT = { { id = 17020, price = 500 }, { id = 4000, price = 20000, avail = 3 } }
Bags({ [1] = { 17020, 7 } })
Reset(); Open()
Check(#c.POPUPS == 0, "no game dialog when the window can be drawn")
local f = PR.Frame()
Check(f and PR.IsShown() and RS.Asking(), "the window is up")
local rows = Rows(f)
Check(#rows == 2, "one row per item (" .. #rows .. ")")
local r1, r2 = rows[1], rows[2]
Check(r1.name.text == "Arcane Powder" and r1.icon.texture == 1000 + 17020 and r1.id == 17020, "its name and its own icon")
Check(r1.meta.text:find("×13", 1, true) and r1.meta.text:find("you carry 7 of 20", 1, true), "how many, and what you carry against the target: " .. r1.meta.text)
Check(r1.cost.text == "65|cffc7c7cfs|r" and r1.each.text == "5|cffc7c7cfs|r each", "the price in colored coins, and each: " .. r1.cost.text .. " / " .. r1.each.text)
Check(r2.name.text == "Moonwell Water" and r2.name.color and r2.name.color[3] == 0.87 and r1.name.color and r1.name.color[3] ~= 0.87, "an item's name takes its quality color")
Check(r2.warn.shown and r2.warn.text:find("7 short: the merchant has only a few left", 1, true), "short: how many and why: " .. tostring(r2.warn.text))
Check(not r1.warn.shown, "an item that reaches its target has no warning")
Check(r2.h > r1.h, "a row with a warning is taller")
Check(f.total.text:find("|cffffd700g|r", 1, true) and f.have.text:find("You have 50|cffffd700g|r", 1, true), "the total and your money, in colored coins: " .. f.total.text .. " / " .. f.have.text)
Check(f.promise.text:find("Nothing is bought unless you press Purchase", 1, true), "it says nothing is bought until Purchase")
Check(#c.BOUGHT == 0, "showing it buys nothing")
Check(f.h >= 260 and c.UISpecialFrames[1] == "TwichUIRestockPrompt", "Esc closes it through the game's list of frames")

---------------------------------------------------------------------------
-- 2. Purchase, Cancel, the close box, Esc
---------------------------------------------------------------------------
f.purchase:Fire("OnClick")
Check(not PR.IsShown() and #c.BOUGHT == 1 and c.BOUGHT[1].n == 13 and c.BOUGHT[1].index == 1, "Purchase buys the approved plan")
Close()

Reset(); Bags({ [1] = { 17020, 7 } }); Open()
Check(PR.IsShown(), "asked again at the next visit, in the same frame")
Check(PR.Frame() == f, "one frame")
f.cancel:Fire("OnClick")
Check(not PR.IsShown() and #c.BOUGHT == 0 and not RS.Asking(), "Cancel buys nothing")
Check(RS.Last().outcome == "cancelled", "and is remembered as cancelled")
Flush(); c.FireEvent("MERCHANT_UPDATE"); c.FireEvent("BAG_UPDATE_DELAYED"); Flush()
Check(not PR.IsShown() and #c.BOUGHT == 0, "nothing asks again this visit")
Close()

Reset(); Open()
f.close:Fire("OnClick")
Check(not PR.IsShown() and #c.BOUGHT == 0 and RS.Last().outcome == "cancelled", "the close box is a Cancel")
Close()
Reset(); Open()
f:Hide()   -- what Esc does through UISpecialFrames
Check(#c.BOUGHT == 0 and RS.Last().outcome == "cancelled" and not RS.Asking(), "Esc is a Cancel")
Close()

---------------------------------------------------------------------------
-- 3. Put away for the code's own reasons: nothing is answered, and a stale Purchase buys nothing
---------------------------------------------------------------------------
Reset(); Open()
c.MERCHANT_UP = false; c.FireEvent("MERCHANT_CLOSED")
Check(not PR.IsShown() and not RS.Asking(), "the merchant closing puts it away")
do
  -- (answers nothing: the window's own callbacks don't run when the code puts it away)
  local answered = 0
  PR.Show({ items = {}, notes = {}, total = 0, money = 0 }, nil, function() answered = answered + 1 end, function() answered = answered + 1 end)
  PR.Hide()
  Check(answered == 0 and not PR.IsShown(), "putting it away answers nothing")
end
Reset(); Open()
RS.SetTarget(17020, 30)
Check(not PR.IsShown() and not RS.Asking() and #c.BOUGHT == 0, "a rule edited puts it away")
Close()
Reset(); Open()
c.FireEvent("PLAYER_REGEN_DISABLED")
Check(not PR.IsShown() and #c.BOUGHT == 0, "combat puts it away")
Close()
-- Purchase pressed after the window went stale (a rule changed without the window being told)
Reset(); Rules({ { id = 17020, target = 20, enabled = true } }); Open()
c.COMBAT = true
f.purchase:Fire("OnClick")
Check(#c.BOUGHT == 0 and c.R_OUT[1] and c.R_OUT[1]:find("combat started", 1, true), "Purchase in combat buys nothing and says so: " .. tostring(c.R_OUT[1]))
c.COMBAT = false
Close()

---------------------------------------------------------------------------
-- 4. A long list, the spending limit, what wasn't bought, a plan that changed
---------------------------------------------------------------------------
do
  local items, merchant = {}, {}
  for i = 1, 12 do
    local id = 60000 + i
    c.ITEMS[id] = { name = "Reagent " .. i, maxStack = 20, quality = 1, link = "[Reagent " .. i .. "]" }
    items[i] = { id = id, target = 5, enabled = true }
    merchant[i] = { id = id, price = 100 }
  end
  Rules(items); c.MERCHANT = merchant; Bags({})
  RS.Set("useLimit", true); RS.Set("limit", 10000)
  Reset(); Open()
  Check(#Rows(f) == 8, "at most eight rows are drawn (" .. #Rows(f) .. ")")
  Check(f.more.shown and f.more.text:find("4 more, included in the total", 1, true), "and the rest are counted: " .. f.more.text)
  Check(f.have.text:find("spending limit for a visit: 1|cffffd700g|r", 1, true), "the limit is shown: " .. f.have.text)
  local total = f.total.text
  f.purchase:Fire("OnClick")
  Check(#c.BOUGHT == 1 and total == "60|cffc7c7cfs|r", "all twelve are in the total, though eight are drawn: " .. total)
  Close()
  RS.Set("useLimit", false)

  -- an item that can't be bought at all is named under the list
  c.ITEMS[2512].link = "[Rough Arrow]"
  Rules({ { id = 17020, target = 20, enabled = true }, { id = 2512, target = 100, enabled = true } })
  c.MERCHANT = { { id = 17020, price = 500 }, { id = 2512, price = 1000, stack = 200 } }
  Bags({})
  Reset(); Open()
  Check(f.notes.shown and f.notes.text:find("Not bought: [Rough Arrow] (sold only in bundles", 1, true), "what isn't bought, and why: " .. tostring(f.notes.text))
  Check(#Rows(f) == 1, "the rest is still offered")
  f.cancel:Fire("OnClick")
  Close()

  -- a price that went up after approval: the window comes back with a lead line
  Rules({ { id = 17020, target = 20, enabled = true } })
  c.MERCHANT = { { id = 17020, price = 500 } }
  Reset(); Open()
  c.MERCHANT[1].price = 600
  f.purchase:Fire("OnClick")
  Check(#c.BOUGHT == 0, "a dearer price buys nothing")
  Flush()
  Check(PR.IsShown() and f.lead.shown and f.lead.text:find("price of something went up", 1, true), "asked again, saying why")
  Check(Rows(f)[1].each.text:find("6|cffc7c7cfs|r each", 1, true), "with the new price: " .. Rows(f)[1].each.text)
  f.cancel:Fire("OnClick")
  Close()
  Reset(); Open()
  Check(not f.lead.shown, "the next visit has no lead line")
  f.cancel:Fire("OnClick")
  Close()
end

---------------------------------------------------------------------------
-- 5. Where it can't be drawn, the game's dialog asks instead
---------------------------------------------------------------------------
do
  Rules({ { id = 17020, target = 20, enabled = true } })
  c.MERCHANT = { { id = 17020, price = 500 } }
  Bags({})
  local saved = R.RestockPrompt
  R.RestockPrompt = { Show = function() return false end, Hide = function() end }
  Reset(); Open()
  Check(#c.POPUPS == 1 and c.POPUPS[1].name == "TWICHUI_RESTOCK_CONFIRM" and c.POPUPS[1].text:find("Arcane Powder", 1, true), "the game's dialog, same words")
  c.StaticPopupDialogs.TWICHUI_RESTOCK_CONFIRM.OnAccept()
  Check(#c.BOUGHT == 1, "and it buys on Purchase")
  Close()
  R.RestockPrompt = saved
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_restock_prompt failed")
end
print("RESTOCK PROMPT PASSED")
