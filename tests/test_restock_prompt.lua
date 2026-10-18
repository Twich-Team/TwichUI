dofile(TESTS .. "harness.lua")
-- Vendor restocking's question (modules/RestockPrompt.lua): TwichUI's own window for "Ask before purchasing".
--   * a real visit shows it instead of the game's dialog; one row per item with its icon, quality-colored name,
--     quantity, carried-of-target, and price with colored g/s/c letters; short items say how many and why;
--     the total, what you have and the spending limit; items beyond the visible rows are counted, not dropped;
--   * Purchase buys the approved plan (checked again, as before); Cancel, the close box and Esc buy nothing;
--   * putting it away for the code's own reasons (merchant closed, rule edited, combat) answers nothing;
--   * a stale Purchase says nothing was bought; asking again reuses the same frame and rows;
--   * where it can't be drawn, the game's dialog is used with the same words;
--   * its background and border are the player's (RestockPrompt.Style): the default is the TwichUI rim, any other
--     border replaces it and the window grows so the content keeps clear of it, a change redraws an open window,
--     Reset puts it back, and only the look moves (rows, texts, buttons and answers are the same);
--   * the settings page's preview shows the real window with made-up items: it buys nothing, never replaces a real
--     question, is replaced by one, and leaves the real window where it always opens.
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

for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Restock.lua", "modules/RestockPrompt.lua" }) do
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

---------------------------------------------------------------------------
-- 6. The player's background and border
---------------------------------------------------------------------------
do
  local Style = PR.Style
  Check(Style and Style.DEFAULTS.borderTexture == PR.LEDGER and Style.DEFAULTS.bgTexture == "solid", "the default is the rim over a solid page")
  Rules({ { id = 17020, target = 20, enabled = true }, { id = 4000, target = 10, enabled = true } })
  c.MERCHANT = { { id = 17020, price = 500 }, { id = 4000, price = 20000, avail = 3 } }
  Bags({ [1] = { 17020, 7 } })
  local backdrops = {}
  f.SetBackdrop = function(_, info) backdrops[#backdrops + 1] = info end
  local function Pt(region, i) local p = region.points[i or 1]; return p and { p[3], p[4], p[5] } end
  local function Shown(list) for _, t in ipairs(list) do if not t.shown then return false end end return #list > 0 end
  local function Hidden(list) for _, t in ipairs(list) do if t.shown then return false end end return #list > 0 end

  Reset(); Open()
  local shell = f.twichShell
  Check(shell and Shown(shell.rim) and Shown(shell.tone), "the default shows the rim, the grain and the shade")
  do
    local inkLines = {}
    for _, line in pairs(f.edgeInk) do inkLines[#inkLines + 1] = line end
    Check(#inkLines == 4 and Shown(inkLines), "and the dark line at the very edge that the backdrop used to draw")
  end
  Check(f.w == 460 and f.twichBand.points[1][4] == 4 and f.twichBand.points[1][5] == -4, "and the layout it always had: width " .. f.w)
  local baseH, baseList = f.h, f.list.points[1]
  local baseTitle = f.title.points[1]
  Check(baseList[4] == 16 and baseTitle[4] == 16 and baseTitle[5] == -(44 / 2 + 4), "the content at its usual margin")
  local baseTexts = { f.title.text, f.total.text, f.have.text, f.promise.text, Rows(f)[1].name.text, Rows(f)[1].cost.text }
  Check(backdrops[#backdrops] and backdrops[#backdrops].edgeFile == nil, "the rim is drawn by the window, not as a backdrop edge")

  -- a solid line 12 px thick replaces the rim; the window grows by the difference from the rim's own reach
  Check(Style.Set("borderTexture", "solid") and Style.Set("borderSize", 12), "a border can be chosen")
  Check(Hidden(shell.rim) and Hidden(shell.tone), "the rim and the grain are put away")
  local inkLines = {}
  for _, line in pairs(f.edgeInk) do inkLines[#inkLines + 1] = line end
  Check(Hidden(inkLines), "and the rim's outer dark line")
  Check(f.w == 460 + 2 * 8 and f.h == baseH + 2 * 8, "the window grows by twice the extra: " .. f.w .. " x " .. f.h)
  Check(f.twichBand.points[1][4] == 12 and f.twichBand.points[1][5] == -12, "the title band sits inside the border")
  Check(f.list.points[1][4] == 24 and f.list.points[1][5] == baseList[5] - 8 and f.title.points[1][4] == 24,
    "the content is pushed in: list at " .. tostring(f.list.points[1][4]))
  Check(f.close.points[1][2] == -18 and f.close.points[1][3] == -19, "and the close box with it")
  Check(f.purchase and f.cancel.points[1][4] == -24, "the buttons keep clear of it")
  Check(backdrops[#backdrops].edgeFile and backdrops[#backdrops].edgeSize == 12, "the border is drawn at the thickness chosen")
  Check(f.total.text == baseTexts[2] and f.title.text == baseTexts[1] and Rows(f)[1].name.text == baseTexts[5]
    and Rows(f)[1].cost.text == baseTexts[6] and #Rows(f) == 2, "only the look moved: the same texts and rows")
  Check(PR.IsShown() and RS.Asking(), "and it is still asking")

  -- no border: nothing to keep clear of
  Style.Set("borderTexture", "none")
  Check(f.w == 460 and f.twichBand.points[1][4] == 0, "no border: the band reaches the edge and the window is its usual width")
  -- thinner than the rim: the content stays where it was
  Style.Set("borderTexture", "solid"); Style.Set("borderSize", 2)
  Check(f.w == 460 and f.list.points[1][4] == 16 and f.twichBand.points[1][4] == 2, "a thin line leaves the content where it was")

  -- the answers are the same whatever it looks like
  Style.Set("borderSize", 12)
  f.purchase:Fire("OnClick")
  Check(#c.BOUGHT == 1 and c.BOUGHT[1].n == 13 and not PR.IsShown(), "Purchase buys the approved plan with any border")
  Close()
  Reset(); Open(); f.cancel:Fire("OnClick")
  Check(#c.BOUGHT == 0 and RS.Last().outcome == "cancelled", "and Cancel buys nothing")
  Close()

  -- opened with a saved look: drawn that way from the first frame
  Reset(); Open()
  Check(f.w == 476 and Hidden(shell.rim), "the next question opens with the saved look")
  -- Reset: the defaults, nothing else touched
  c.TwichUIDB.ui.restock.items[1].target = 20
  local before = c.TwichUIDB.ui.restock
  Style.Reset()
  Check(c.TwichUIDB.ui.restockPromptStyle == nil and c.TwichUIDB.ui.restock == before, "Reset forgets the look and leaves the restock list alone")
  Check(f.w == 460 and Shown(shell.rim) and Shown(shell.tone) and f.twichBand.points[1][4] == 4, "an open window is back to its default look")
  f.cancel:Fire("OnClick")
  Close()

  -- invalid saved values never break it
  c.TwichUIDB.ui.restockPromptStyle = { borderTexture = 7, borderSize = "wide", bgColor = "red", bgOpacity = 400 }
  Reset(); Open()
  Check(PR.IsShown() and f.w == 460 and Style.Get("borderSize") == 1 and Style.Get("bgOpacity") == 98, "damaged saved values read as the defaults")
  f.cancel:Fire("OnClick")
  Close()
  c.TwichUIDB.ui.restockPromptStyle = nil
end

---------------------------------------------------------------------------
-- 7. The settings page's preview
---------------------------------------------------------------------------
do
  local anchor = { GetRight = function() return 900 end }
  R.SettingsAnchor = function() return anchor end
  Rules({ { id = 17020, target = 20, enabled = true } })
  c.MERCHANT = { { id = 17020, price = 500 } }
  Bags({})
  Reset()
  PR.TogglePreview()
  Check(PR.IsShown() and PR.IsPreview() and #Rows(f) == 3, "the preview shows the window with three made-up items")
  Check(f.lead.shown and f.lead.text:find("sample", 1, true) and f.lead.text:find("buys nothing", 1, true), "and says it is a sample: " .. tostring(f.lead.text))
  Check(f.points[1][2] == anchor and f.points[1][3] == "TOPRIGHT", "beside the settings window")
  Check(#c.POPUPS == 0 and not RS.Asking(), "it is not a question: no dialog, nothing pending")
  f.purchase:Fire("OnClick")
  Check(not PR.IsShown() and #c.BOUGHT == 0, "Purchase in the preview only closes it")
  PR.TogglePreview(); PR.TogglePreview()
  Check(not PR.IsShown(), "pressed again it goes away")
  PR.TogglePreview(); f:Hide()
  Check(not PR.IsShown() and #c.BOUGHT == 0 and #c.R_OUT == 0, "Esc closes it and says nothing")

  -- a real question is never replaced by it
  Reset(); Open()
  Check(PR.IsShown() and not PR.IsPreview() and RS.Asking(), "a real question is up")
  local rows = #Rows(f)
  PR.TogglePreview()
  Check(PR.IsShown() and not PR.IsPreview() and RS.Asking() and #Rows(f) == rows, "the preview leaves it alone")
  f.cancel:Fire("OnClick")
  Close()

  -- and a real question replaces it, opening where it always does
  PR.TogglePreview()
  Check(PR.IsPreview(), "preview up")
  Reset(); Open()
  Check(PR.IsShown() and not PR.IsPreview() and RS.Asking() and not f.lead.shown, "a visit replaces the preview with the real question")
  Check(f.points[1][2] == c.UIParent and f.points[1][4] == 0 and f.points[1][5] == 150, "in its usual place, not beside the settings")
  f.purchase:Fire("OnClick")
  Check(#c.BOUGHT == 1, "and Purchase buys, as ever")
  Close()

  -- the merchant closing does not take a preview away, and the settings closing does
  PR.TogglePreview()
  c.MERCHANT_UP = false; c.FireEvent("MERCHANT_CLOSED")
  Check(PR.IsPreview(), "a merchant closing leaves the preview")
  Check(R.SettingsLauncher and R.SettingsLauncher.Closed, "the settings launcher is there to tell it")
  R.SettingsLauncher.Closed()
  Check(not PR.IsShown(), "the settings window closing takes the preview with it")
  -- ...but not a real question
  Reset(); Open()
  R.SettingsLauncher.Closed()
  Check(PR.IsShown() and RS.Asking(), "and leaves a real question up")
  f.cancel:Fire("OnClick")
  Close()
  R.SettingsAnchor = nil
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_restock_prompt failed")
end
print("RESTOCK PROMPT PASSED")
