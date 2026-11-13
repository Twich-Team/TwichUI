-- Workshop "What's it worth?" (TwichUI_Workshop/Worth.lua and WorthTip.lua): the comparison of vendor, auction and disenchant for ONE item.
-- DISENCHANT IS NOT ESTIMATED: no legally reusable, Forever-appropriate outcome table was found (docs/workshop.md, "Disenchant outcome
-- data"), so there is nothing to test an average against; these tests pin that a disenchantable-looking item shows "no data", never a
-- number, and that the missing option stops a winner from being suggested. Covered: vendor and auction values, a known and an unknown
-- auction cut (the cut here is a TEST INPUT, Prices.CUT is empty in the product), missing and unsupported prices, bound / unlistable
-- items, variants, the suggestion (Worth.Recommend; WorthLayout's own tests cover customising the lines) only when the evidence supports it, and the tooltip: repeated updates, tooltip reuse, Shift,
-- item information arriving late, no auction queries. A fake GameTooltip and fake item APIs stand in for the game: this proves our
-- logic, not what Forever returns (docs/workshop.md lists the in-game checks).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua",
  "Vendor.lua", "Shopping.lua", "Worth.lua", "WorthLayout.lua", "Scan.lua", "Market.lua", "Session.lua" }

local function Load(c, file)
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. file))
  setfenv(chunk, c)
  chunk("TwichUI_Workshop", {})
end

local NOW = 1000000
local function Money(n) return "[" .. n .. "]" end

---------------------------------------------------------------------------
-- The pure comparison
---------------------------------------------------------------------------
local c0 = MIClient("Rich", { db = { modules = {} } })
c0.TwichUIDB = c0.TwichUIDB or {}
c0.time = function() return NOW end
c0.CreateFrame = function(kind) return MIFake(kind) end
c0.GetRealmName = function() return "Realm" end
c0.C_Timer = { After = function() end }
for _, f in ipairs(FILES) do Load(c0, f) end
local W = c0.TwichUI.Workshop
local WO, WL, PR = W.Worth, W.WorthLayout, W.Prices
local function Kind(r) local x = WO.Recommend(r) return x and x.kind end
local function Text(r) local x = WO.Recommend(r) return x and x.text end

-- a base item: not bound, plain, unlikely to disenchant (a trade good)
local function F(t)
  local f = { sell = 50, quality = 1, classID = 7, bindType = 0, bound = false, now = NOW,
    market = { label = "the Alliance auction house on Realm", side = "Alliance", at = NOW - 60, complete = true },
    price = { price = 200, qty = 1, listings = 1, total = 1, at = NOW - 60, complete = true } }
  for k, v in pairs(t or {}) do if v == "nil" then f[k] = nil else f[k] = v end end
  return f
end

-- vendor and auction, the cut unknown (the product's state): the auction value is "before fees", an upper bound
do
  local r = WO.Evaluate(F())
  Same(r.vendor.state, "ok"); Same(r.vendor.value, 50)
  Same(r.auction.state, "ok"); Same(r.auction.value, 200, "before fees, the whole listing price")
  Check(r.auction.beforeFees and r.auction.net == nil and r.auction.cut == nil, "no cut deducted and none claimed")
  Same(Kind(r), "fee", "auction beats the vendor only before fees: no after-fees winner is claimed")
  Same(Text(r), "No suggestion: auction fee unknown")
  Check(r.disenchant == nil, "a trade good has no disenchant line")
  -- the vendor wins even without knowing the cut: the cut can only lower the auction
  r = WO.Evaluate(F({ sell = 300 }))
  Same(Text(r), "Suggested: Vendor", "vendor >= the auction's upper bound is a verified winner")
  r = WO.Evaluate(F({ sell = 200 }))
  Same(Text(r), "Suggested: Vendor", "equal to the upper bound: the vendor is still at least as good after any cut")
end

-- a known cut (TEST INPUT: 5%), rounding like the Opportunities arithmetic
do
  local r = WO.Evaluate(F({ rate = 0.05, sell = 150 }))
  Same(r.auction.cut, 10); Same(r.auction.net, 190); Same(r.auction.value, 190)
  Check(not r.auction.beforeFees, "with a confirmed cut it is not 'before fees'")
  Same(Text(r), "Suggested: Auction house")
  Same(Text(WO.Evaluate(F({ rate = 0.05, sell = 190 }))), "Similar value", "equal values name no winner")
  Same(Text(WO.Evaluate(F({ rate = 0.05, sell = 191 }))), "Suggested: Vendor")
  local r2 = WO.Evaluate(F({ rate = 0.05, price = { price = 150, at = NOW, complete = true } }))
  Same(r2.auction.cut, 8, "7.5 rounds half up, like the rest of the Workshop"); Same(r2.auction.net, 142)
  Check(WO.Evaluate(F({ rate = 1.5 })).auction.beforeFees, "an impossible rate is not a cut")
end

-- missing and unsupported: never zero, and an unknown competitor blocks the winner
do
  local r = WO.Evaluate(F({ price = "nil" }))
  Same(r.auction.state, "unknown"); Same(r.auction.why, "noprice"); Same(r.auction.value, nil, "no price is not 0")
  Same(Text(r), "More prices needed", "the missing thing is a price")
  r = WO.Evaluate(F({ market = "nil", price = "nil" }))
  Same(r.auction.why, "nomarket"); Same(Text(r), "More prices needed")
  r = WO.Evaluate(F({ sell = 0 }))
  Same(r.vendor.state, "none", "no sell value is unavailable, not a zero estimate"); Same(Text(r), nil, "one real option and nothing unknown: nothing to compare")
  r = WO.Evaluate(F({ sell = "nil" }))
  Same(r.vendor.state, "unknown"); Same(Text(r), "More prices needed", "an unknown vendor value is unknown too")
  Same(WO.Evaluate(F({ sell = -5 })).vendor.state, "unknown", "a negative value is not believed")
  Same(WO.Evaluate(F({ sell = 0.5 })).vendor.state, "unknown", "a fraction is not believed")
end

-- unavailable actions are not unknown estimates
do
  local r = WO.Evaluate(F({ bound = true }))
  Same(r.auction.state, "unavailable"); Same(r.auction.why, "bound")
  Same(Text(r), nil, "one known option and one unavailable: nothing to compare, nothing blocked")
  r = WO.Evaluate(F({ bindType = 1, bound = false }))
  Same(r.auction.state, "unavailable", "bind on pickup never goes to the auction house, even before it is marked bound")
  Same(WO.Evaluate(F({ bindType = 4 })).auction.why, "quest")
  Same(WO.Evaluate(F({ bindType = 2 })).auction.state, "ok", "bind on equip, not yet bound")
  Same(WO.Evaluate(F({ bindType = 2, bound = true })).auction.state, "unavailable", "bind on equip, bound now")
  Same(WO.Evaluate(F({ bindType = 3 })).auction.state, "ok")
  r = WO.Evaluate(F({ bindType = 9 }))
  Same(r.auction.state, "unknown"); Same(r.auction.why, "bind", "an unknown binding value is not guessed")
  r = WO.Evaluate(F({ bindType = "nil" }))
  Same(r.auction.why, "bind")
  -- bound AND without a price: it is unavailable, which wins over unknown
  Same(WO.Evaluate(F({ bound = true, price = "nil" })).auction.state, "unavailable")
end

-- variants: never priced from the base item's listings
do
  Same(WO.LinkVariant("|cff1eff00|Hitem:1234:0:0:0:0:0:0:0:60|h[Plain]|h|r"), nil)
  Same(WO.LinkVariant("|cff1eff00|Hitem:1234:0:0:0:0:0:-15|h[Cloak of the Bear]|h|r"), "suffix")
  Same(WO.LinkVariant("|Hitem:1234:0:0:0:0:0:0:0:60:0:0:0:0|h[x]|h"), nil, "no suffix and no bonus IDs: the plain item")
  Same(WO.LinkVariant("|Hitem:1234:0:0:0:0:0:0:0:60:0:0:0:3:1:2:3|h[x]|h"), "bonus", "three bonus IDs")
  Same(WO.LinkVariant("item:1234:0:0:0:0:0:0:0:0:0:0:0:2:5001:5002"), "bonus")
  Same(WO.LinkVariant("item:1234"), nil)
  Same(WO.LinkVariant(nil), nil); Same(WO.LinkVariant(42), nil); Same(WO.LinkVariant("[not a link]"), nil)
  local r = WO.Evaluate(F({ variant = "suffix" }))
  Same(r.auction.state, "unknown"); Same(r.auction.why, "variant"); Same(r.auction.value, nil, "the base price is not used")
  Same(Text(r), "No suggestion: this variant isn't priced", "more prices would not help a variant")
end

-- disenchant: relevant for green-to-epic weapons and armour, and then only "no data"; it blocks a best option
do
  local function De(class, quality) return WO.Evaluate(F({ classID = class, quality = quality })).disenchant end
  Check(De(4, 2) and De(4, 4) and De(2, 3), "uncommon to epic armour and weapons")
  Check(not De(4, 1) and not De(4, 5) and not De(7, 2) and not De(0, 3), "not common, not legendary, not trade goods or consumables")
  Check(not WO.Evaluate(F({ classID = 4, quality = 2, equipLoc = "INVTYPE_BODY" })).disenchant and not WO.Evaluate(F({ classID = 4, quality = 3, equipLoc = "INVTYPE_TABARD" })).disenchant, "shirts and tabards never")
  Check(WO.Evaluate(F({ classID = 4, quality = 2, equipLoc = "INVTYPE_CHEST" })).disenchant, "other armour slots do")
  local r = WO.Evaluate(F({ classID = 4, quality = 2, rate = 0.05, sell = 150 }))
  Same(r.disenchant.state, "unknown"); Same(r.disenchant.why, "nodata")
  Same(r.disenchant.value, nil); Same(r.disenchant.chance, nil); Same(r.disenchant.mats, nil)
  Same(Text(r), "Auction beats vendor (disenchant unknown)", "vendor and auction compare, and the missing disenchant is said in the same line")
  -- bound armour: auction unavailable, vendor known, disenchant unknown -> still not named
  r = WO.Evaluate(F({ classID = 4, quality = 3, bound = true }))
  Same(Text(r), "Disenchant value unknown")
end

-- the words (the default layout; WorthLayout's own tests cover customising it)
do
  local function Ctx(extra)
    local c = { money = Money, ageText = PR.AgeText, now = NOW, count = 1, market = { label = "the Alliance auction house on Realm", at = NOW - 60, complete = true } }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
  end
  local function Flat(lines) local t = {} for _, l in ipairs(lines or {}) do t[#t + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end return table.concat(t, "\n"), #(lines or {}) end
  local function Short(f, ctx, shift) return Flat(WL.Lines(WO.Evaluate(F(f)), ctx or Ctx(), WL.Get(), shift)) end
  local text, n = Short({ sell = 300 })
  Same(text, "What's it worth?\n*Suggested: Vendor\nVendor | [300]\nAuction (before fees) | [200]\n~Hold Shift for details")
  Check(n >= 4 and n <= 6, "four to six lines")
  text = Short()
  Check(text:find("~No suggestion: auction fee unknown", 1, true) and not text:find("Suggested", 1, true), "no winner while the fee is unknown")
  text = Short({ price = "nil" })
  Check(text:find("Auction | no price", 1, true) and text:find("~More prices needed", 1, true), "a missing price is said once, shortly")
  text, n = Short({ classID = 4, quality = 2, rate = 0.05 })
  Check(text:find("Disenchant (average) | no data", 1, true) and text:find("Auction beats vendor (disenchant unknown)", 1, true), "disenchant: no data, and the comparison says it is not counted")
  Check(n <= 7, "still short")
  text = Short({ bound = true })
  Check(text:find("Auction | can't be listed (bound)", 1, true), "unavailable, said as such")
  text = Short({ sell = 0 })
  Check(text:find("Vendor | no sell value", 1, true))
  Check(Short(nil, Ctx({ count = 20 })):find("What's it worth? (each)", 1, true), "a stack says the values are for one item")
  -- old prices and a partial scan are visible without opening the details
  text = Short({ price = { price = 200, at = NOW - 3 * 86400, complete = false } })
  Check(text:find("Auction (before fees, old prices, partial scan) | [200]", 1, true), "age and a partial scan are on the line: " .. text)
  -- the details (Shift): age, source and the exclusion ONCE; no cut lines (the cut is on the auction line)
  text = Short({ rate = 0.05, classID = 4, quality = 2 }, nil, true)
  Check(text:find("Auction (after fees) | [190]", 1, true), "a confirmed cut: the value is after fees: " .. text)
  Check(text:find("Scanned | 1 minute ago", 1, true) and text:find("Prices from | the Alliance auction house on Realm", 1, true), "how old, and where from: " .. text)
  local _, count = text:gsub("Deposits and failed listings", "")
  Same(count, 1, "the deposit / failed-listing exclusion is stated once")
  Same(select(2, text:gsub("auction house on Realm", "")), 1, "the market is named once")
  text = Short(nil, nil, true)
  Check(text:find("Auction (before fees) | [200]", 1, true), "an unknown cut is said on the value itself: " .. text)
end

---------------------------------------------------------------------------
-- The tooltip, over fakes
---------------------------------------------------------------------------
-- item[id] = { name, quality, class, bind, sell, link, bound, count, where = "bag"|"equip" }
local function Game(opts)
  opts = opts or {}
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  c.time = function() return NOW end
  local frames = {}
  c.CreateFrame = function(kind) local f = MIFake(kind); frames[#frames + 1] = f; return f end
  c.GetRealmName = function() return "Realm" end
  c.C_Timer = { After = function() end }
  c.UnitFactionGroup = function() return "Alliance" end
  -- any call into the auction house from a tooltip is a failure
  c.C_AuctionHouse = setmetatable({}, { __index = function(_, k) error("the tooltip asked the auction house: " .. tostring(k)) end })
  local g = { items = {}, shift = false, moneyArgs = {}, infoCalls = 0, requested = {} }
  c.IsShiftKeyDown = function() return g.shift end
  c.GetMoneyString = function(n, a, b, d) g.moneyArgs[#g.moneyArgs + 1] = { n, a, b, d } return Money(n) end
  c.C_Item = {
    GetItemLocation = function(guid)
      local id = tonumber(tostring(guid):match("^Item%-(%d+)"))
      local it = id and g.items[id]
      if not it then return nil end
      return { IsBagAndSlot = function() return it.where ~= "equip" end, IsEquipmentSlot = function() return it.where == "equip" end, id = id }
    end,
    DoesItemExist = function(loc) return g.items[loc.id] ~= nil end,
    GetItemLink = function(loc) local it = g.items[loc.id]; return it.link or ("|cffffffff|Hitem:" .. loc.id .. "::::::::60|h[" .. it.name .. "]|h|r") end,
    GetItemID = function(loc) return loc.id end,
    GetItemInfo = function(x)
      g.infoCalls = g.infoCalls + 1
      if g.infoError then error("item info exploded") end
      local id = type(x) == "number" and x or tonumber(tostring(x):match("Hitem:(%d+)"))
      local it = g.items[id]
      if not it or it.unloaded then return nil end
      return it.name, "link", it.quality, 10, 1, "", "", 20, "", 1, it.sell, it.class, 0, it.bind
    end,
    IsBound = function(loc) return g.items[loc.id].bound == true end,
    GetStackCount = function(loc) return g.items[loc.id].count or 1 end,
    GetDetailedItemLevelInfo = function(link) local it = g.items[tonumber(link:match("Hitem:(%d+)"))]; return it.ilvl or 10, false, it.baseIlvl or it.ilvl or 10 end,
    RequestLoadItemDataByID = function(id) g.requested[id] = (g.requested[id] or 0) + 1 end,
  }
  -- a GameTooltip that rebuilds from its data the way the real one does: clear, the item's own lines, then every post call
  local tt = { lines = {}, hooks = {}, shown = true, rebuilds = 0 }
  function tt:AddLine(text) self.lines[#self.lines + 1] = { text } end
  function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = { l, r } end
  function tt:IsShown() return self.shown end
  function tt:IsForbidden() return false end
  function tt:HookScript(name, fn) self.hooks[name] = fn end
  function tt:Build()
    self.lines = {}
    if self.hooks.OnTooltipCleared then self.hooks.OnTooltipCleared(self) end
    self.lines[1] = { self.data.name or "Item" }
    for _, fn in ipairs(g.posts) do fn(self, self.data) end
  end
  function tt:Show(data) self.data = data; self.shown = true; self:Build() end
  function tt:RefreshData() self.rebuilds = self.rebuilds + 1; self:Build() end
  g.posts = {}
  g.tt = tt
  if not opts.noProcessor then
    c.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) Check(kind == "Item", "an item post call"); g.posts[#g.posts + 1] = fn end }
    c.Enum = { TooltipDataType = { Item = "Item" } }
  end
  c.GameTooltip = tt
  c.ItemRefTooltip = { }
  g.faults = 0
  c.TwichUI.Fault = function() g.faults = g.faults + 1 end
  g.c = c
  for _, f in ipairs(FILES) do Load(c, f) end
  g.W = c.TwichUI.Workshop
  g.load = function() Load(c, "WorthTip.lua"); return g.W.WorthTip end
  g.frames = frames
  -- a saved scan of this realm's Alliance auction house
  Check(g.W.Prices.Commit("Realm|Alliance", { realm = "Realm", side = "Alliance", at = NOW - 60, complete = true, read = 3, used = 3, n = 2,
    items = { [111] = { 200, 1, 1, 1 }, [112] = { 900, 1, 1, 1 } } }), "price scan saved")
  return g
end

local function Hover(g, id, extra)
  local d = { guid = "Item-" .. id, id = id, name = (g.items[id] or {}).name }
  for k, v in pairs(extra or {}) do d[k] = v end
  g.tt:Show(d)
end
local function Texts(g) local t = {} for _, l in ipairs(g.tt.lines) do t[#t + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end return table.concat(t, "\n") end
local function Count(s, pat) local _, n = s:gsub(pat, "") return n end
local function Listener(g) for _, f in ipairs(g.frames) do if f.scripts.OnEvent then return f end end end

-- not loaded without the tooltip API
do
  local g = Game({ noProcessor = true })
  local T = g.load()
  Check(not T.registered and #g.posts == 0, "no TooltipDataProcessor: nothing registered, nothing breaks")
end

-- a plain item: one section, updated in place, never doubled
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  local T = g.load()
  Check(T.registered and #g.posts == 1, "one post call")
  T.Start(); Check(#g.posts == 1, "starting twice does not register twice")
  Hover(g, 111)
  local t = Texts(g)
  Same(Count(t, "What's it worth%?"), 1)
  Check(t:find("Vendor | [50]", 1, true) and t:find("Auction (before fees) | [200]", 1, true), "values: " .. t)
  Check(t:find("Rough Bracers", 1, true) and t:find("Hold Shift for details", 1, true), "the item's own tooltip is kept")
  Check(t:find("No suggestion: auction fee unknown", 1, true), "and the fee is not hidden: " .. t)
  for _ = 1, 5 do Hover(g, 111) end   -- the game rebuilds bag tooltips over and over
  Same(Count(Texts(g), "What's it worth%?"), 1, "five more updates: still one section")
  Check(#g.tt.lines <= 9, "the tooltip stays short: " .. #g.tt.lines)
  Check(#g.moneyArgs > 0 and g.moneyArgs[1][2] == true and g.moneyArgs[1][4] == true, "the coin graphics (GetMoneyString with textures), like the Workshop window")
end

-- tooltip reuse: the same tooltip next shows an item the player does not hold, an equipped item, a linked item
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  g.items[113] = { name = "Worn Sword", quality = 1, class = 2, bind = 0, sell = 10, where = "equip" }
  local T = g.load()
  Hover(g, 111); Check(Texts(g):find("What's it worth?", 1, true), "section on the held item")
  g.tt:Show({ id = 111, name = "Rough Bracers" })   -- no guid: a link, a vendor, an auction listing
  Check(not Texts(g):find("worth", 1, true), "no section without a guid")
  Hover(g, 113); Check(not Texts(g):find("worth", 1, true), "no section on an equipped item")
  g.tt:Show({ guid = "Item-999", id = 999, name = "Gone" }); Check(not Texts(g):find("worth", 1, true), "an unknown guid gets nothing")
  g.tt:Show({ guid = 12, name = "x" }); Check(not Texts(g):find("worth", 1, true), "a bad guid gets nothing")
  g.tt:Show({ name = "x" }); Check(not Texts(g):find("worth", 1, true))
  -- another tooltip is left alone
  local before = T.added
  local post = g.posts[1]
  post({ AddLine = function() error("must not be used") end, AddDoubleLine = function() error("must not be used") end }, { guid = "Item-111", id = 111 })
  Same(T.added, before, "only GameTooltip gets the section")
  Hover(g, 111); Check(Texts(g):find("Vendor | [50]", 1, true), "and it is back for the held item")
end

-- Shift: one rebuild per press and release, never doubled, only Shift
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  g.load()
  local f = Listener(g)
  Check(f and f.events.MODIFIER_STATE_CHANGED, "listening for modifier changes")
  Hover(g, 111)
  Check(not Texts(g):find("Scanned", 1, true), "short at first")
  g.shift = true
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
  Same(g.tt.rebuilds, 1)
  local t = Texts(g)
  Same(Count(t, "What's it worth%?"), 1, "details replace the short form, they do not stack on it")
  Check(t:find("Auction (before fees) | [200]", 1, true) and t:find("Scanned | 1 minute ago", 1, true), "details: " .. t)
  Same(Count(t, "Deposits and failed listings"), 1)
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LCTRL", 1)
  Same(g.tt.rebuilds, 1, "Ctrl does not rebuild")
  g.shift = false
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "RSHIFT", 0)
  Same(g.tt.rebuilds, 2)
  t = Texts(g)
  Check(t:find("Hold Shift for details", 1, true) and not t:find("Scanned", 1, true) and Count(t, "What's it worth%?") == 1, "short again")
  -- no tooltip showing our section: a Shift change touches nothing
  g.tt:Show({ name = "Something else" })
  g.shift = true
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
  Same(g.tt.rebuilds, 2, "a tooltip without the section is not rebuilt")
  g.tt.shown = false
  Hover(g, 111); g.tt.shown = false
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
  Same(g.tt.rebuilds, 2, "a hidden tooltip is not rebuilt")
end

-- the player's layout on the live tooltip: the same definitions the designer's preview uses
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  g.items[117] = { name = "Green Gloves", quality = 2, class = 4, bind = 2, sell = 30 }
  g.load()
  local f = Listener(g)
  local L = g.W.WorthLayout
  local function Section(shift)   -- what the preview would build for the held item, as the tooltip draws it
    local info = { sell = 50, quality = 1, classID = 7, bindType = 0, bound = false, now = NOW,
      market = { label = g.W.Session.PriceSource().label, side = "Alliance", at = NOW - 60, complete = true }, price = { price = 200, at = NOW - 60, complete = true } }
    local ctx = { money = Money, ageText = PR.AgeText, market = info.market, now = NOW, count = 1 }
    local lines = L.Lines(g.W.Worth.Evaluate(info), ctx, L.Get(), shift)
    local t = {}
    for i, l in ipairs(lines or {}) do
      local kind, a, b = L.Style(l)   -- the tooltip draws the text without its style mark
      t[#t + 1] = i == 1 and l[1] or (kind == "double" and (a .. " | " .. b) or a)
    end
    return table.concat(t, "\n")
  end
  local function Mine() local t = Texts(g); return (t:gsub("^[^\n]*\n ?\n?", "")) end   -- without the item's own first line and the blank line before our heading
  Hover(g, 111)
  Same(Mine(), Section(false), "the default layout: the tooltip draws what the shared builder builds")
  -- a customised layout: Vendor only on Shift, the note moved to the top, no recommendation
  Check(L.SetLines({ { id = "note", when = "shift" }, { id = "auction", when = "always" }, { id = "vendor", when = "shift" } }))
  Hover(g, 111)
  local t = Texts(g)
  Check(t:find("Auction (before fees) | [200]", 1, true) and not t:find("Vendor |", 1, true) and not t:find("Suggested", 1, true) and not t:find("No suggestion", 1, true),
    "Always lines only, in the layout's terms: " .. t)
  Check(t:find("Hold Shift for details", 1, true), "details exist: the hint")
  Same(Mine(), Section(false), "and still equal to the preview's lines")
  g.shift = true
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
  t = Texts(g)
  Same(Count(t, "What's it worth%?"), 1, "Shift: one section")
  Same(Count(t, "Auction %(before fees%)"), 1, "the Always line is not repeated")
  Same(Count(t, "Vendor |"), 1, "the Shift line joins it")
  local note, auction, vendor = t:find("Estimates, not sales", 1, true), t:find("Auction (before fees)", 1, true), t:find("Vendor |", 1, true)
  Check(note < auction and auction < vendor, "in the configured order")
  Same(Mine(), Section(true), "Hold Shift equals the preview's Hold Shift")
  Check(not t:find("Hold Shift for details", 1, true), "no hint while Shift is held")
  g.shift = false
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
  t = Texts(g)
  Check(not t:find("Vendor |", 1, true) and not t:find("Estimates", 1, true) and Count(t, "What's it worth%?") == 1, "released: no stale Shift lines")
  -- the layout is read at each hover: a change takes effect on the next one, no reload
  Check(L.SetLines({ { id = "vendor", when = "always" } }))
  Hover(g, 111)
  Same(Mine(), "What's it worth?\nVendor | [50]", "just the vendor line, no hint (nothing more to show)")
  -- nothing to show: no heading
  Check(L.SetLines({ { id = "disenchant", when = "always" } }))
  Hover(g, 111)
  Check(not Texts(g):find("worth", 1, true), "a section with no content leaves no heading")
  Hover(g, 117)
  Check(Texts(g):find("Disenchant (average) | no data", 1, true), "but a green armour piece has its row")
  Check(L.SetLines({}))
  Hover(g, 111)
  Check(not Texts(g):find("worth", 1, true), "no lines chosen: nothing")
  -- Enable tooltip off: nothing, and the held layout comes back with it on
  Check(L.Reset()); Check(L.SetEnabled(false))
  Hover(g, 111); Hover(g, 117)
  Check(not Texts(g):find("worth", 1, true), "switched off: no section")
  g.shift = true
  f.scripts.OnEvent(f, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
  Same(g.tt.rebuilds > 0 and Count(Texts(g), "What's it worth%?") or 0, 0, "and Shift cannot bring one back")
  g.shift = false
  Check(L.SetEnabled(true))
  Hover(g, 111)
  Check(Texts(g):find("Hold Shift for details", 1, true), "switched back on")
  -- a changed layout never changes a figure
  Check(L.SetLines({ { id = "auction", when = "always" } }))
  Hover(g, 111)
  Check(Texts(g):find("Auction (before fees) | [200]", 1, true))
end

-- item information arriving late
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50, unloaded = true }
  g.load()
  local f = Listener(g)
  Hover(g, 111)
  Check(not Texts(g):find("worth", 1, true), "nothing is added while the item is not known")
  Same(g.requested[111], 1, "its information is asked for once")
  Check(f.events.GET_ITEM_INFO_RECEIVED, "waiting for it")
  f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 555, true)
  Same(g.tt.rebuilds, 0, "another item's information changes nothing")
  g.items[111].unloaded = nil
  f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 111, true)
  Same(g.tt.rebuilds, 1)
  Same(Count(Texts(g), "What's it worth%?"), 1, "the section appears once the information is there")
  Check(not f.events.GET_ITEM_INFO_RECEIVED, "no longer listening")
  f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 111, true)
  Same(g.tt.rebuilds, 1, "and a repeat does nothing")
  -- the information never comes (success = false): given up quietly
  g.items[111].unloaded = true
  Hover(g, 111)
  f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", 111, false)
  Same(g.tt.rebuilds, 1, "a failed load is not retried by this addon")
  Check(not f.events.GET_ITEM_INFO_RECEIVED, "and it stops listening")
  -- the tooltip moves on to another item while waiting
  g.items[111].unloaded = true
  Hover(g, 111)
  g.items[111].unloaded = nil
  g.tt:Show({ name = "Other" })
  Check(not f.events.GET_ITEM_INFO_RECEIVED, "leaving the item stops the wait")
end

-- eligibility and variants on the tooltip
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  g.items[112] = { name = "Soul Cloak", quality = 1, class = 7, bind = 1, sell = 100, bound = true }
  g.items[114] = { name = "Cloak of the Bear", quality = 1, class = 7, bind = 0, sell = 20, link = "|cffffffff|Hitem:114:0:0:0:0:0:-15|h[Cloak of the Bear]|h|r" }
  g.items[112].bind = 1
  g.items[115] = { name = "Scaled Helm", quality = 1, class = 7, bind = 0, sell = 20, ilvl = 14, baseIlvl = 10 }
  g.load()
  Hover(g, 112)
  local t = Texts(g)
  Check(t:find("Auction | can't be listed (bound)", 1, true) and t:find("Vendor | [100]", 1, true) and not t:find("Suggested", 1, true), "bound: " .. t)
  Hover(g, 114)
  t = Texts(g)
  Check(t:find("Auction | this variant isn't priced", 1, true) and t:find("No suggestion: this variant isn't priced", 1, true), "variant: " .. t)
  Hover(g, 115)
  Check(Texts(g):find("this variant isn't priced", 1, true), "a changed item level is a variant")
  -- an item nobody scanned
  g.items[116] = { name = "Odd Thing", quality = 1, class = 7, bind = 0, sell = 5 }
  Hover(g, 116)
  Check(Texts(g):find("Auction | no price", 1, true) and Texts(g):find("More prices needed", 1, true), "no listing seen: no price, and no zero")
  -- a stack
  g.items[111].count = 20
  Hover(g, 111)
  Check(Texts(g):find("What's it worth? (each)", 1, true), "a stack says each")
  -- green armour: no disenchant data, so no best option, whatever the prices
  g.items[117] = { name = "Green Gloves", quality = 2, class = 4, bind = 2, sell = 30 }
  Hover(g, 117)
  t = Texts(g)
  Check(t:find("Disenchant (average) | no data", 1, true) and not t:find("Suggested", 1, true), "disenchant unknown: " .. t)
end

-- no saved scan at all, and old prices
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  g.c.TwichUIWorkshopDB = nil
  g.load()
  Hover(g, 111)
  Check(Texts(g):find("Auction | not scanned yet", 1, true) and Texts(g):find("[50]", 1, true), "no scan: the vendor value still shows")
  g.W.Prices.Commit("Realm|Alliance", { realm = "Realm", side = "Alliance", at = NOW - 3 * 86400, complete = true, read = 1, used = 1, n = 1, items = { [111] = "200,1,1,1,0" } })
  Hover(g, 111)
  Check(Texts(g):find("old prices", 1, true), "old prices are marked: " .. Texts(g))
end

-- a fault never takes the item's tooltip with it, and is reported once
do
  local g = Game()
  g.items[111] = { name = "Rough Bracers", quality = 1, class = 7, bind = 0, sell = 50 }
  local T = g.load()
  g.infoError = true
  for _ = 1, 3 do Hover(g, 111) end
  Same(g.faults, 1, "reported once through the normal error path")
  Same(T.faults, 3)
  Check(g.tt.lines[1][1] == "Rough Bracers", "the item's own lines are untouched")
  g.infoError = false
  Hover(g, 111)
  Check(Texts(g):find("What's it worth?", 1, true), "and it recovers")
end

-- the packaging: both files are listed, in an order that works, before the window
do
  local f = assert(io.open(REPO .. "TwichUI_Workshop/TwichUI_Workshop.toc", "rb")); local toc = f:read("*a"); f:close()
  local prices, worth, layout, session, tip, window = toc:find("\nPrices.lua", 1, true), toc:find("\nWorth.lua", 1, true), toc:find("\nWorthLayout.lua", 1, true),
    toc:find("\nSession.lua", 1, true), toc:find("\nWorthTip.lua", 1, true), toc:find("\nWindow.lua", 1, true)
  Check(prices and worth and layout and session and tip and window, "listed")
  Check(prices < worth and worth < layout and session < tip and layout < tip and tip < window, "after the files they use, before the window")
end

print("PASSED")
