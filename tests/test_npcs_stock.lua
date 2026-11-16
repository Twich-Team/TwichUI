-- Vendors and trainers: which side an NPC serves, and what merchants sell (npcs/Store.lua, Collect.lua, Share.lua, Items.lua,
-- Search.lua, SearchBar.lua's text, Map.lua's menu, Stock.lua). The game is the harness's stand-in (frames, item cache,
-- addon messages), so this shows TwichUI's own bookkeeping, not that the game delivers or names anything: the in-game
-- checks are in docs/npc-map.md ("Still to check in the game").
--   1 side recorded           2 side hides NPCs      3 side on the wire and in reports
--   4 stock recorded          5 stock on the wire    6 stock in reports (bounded)
--   7 sharing a list / live   8 item names           9 searching by item
--   10 the menu and window    11 diagnostics hold no names
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end

-- A frame stand-in that keeps what the code asks of it (as test_cozy_bag.lua's)
local function Obj()
  local o = { text = "", shown = true }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s)
      local was = s.shown
      s.shown = true
      if not was or s.firstShow then
        s.firstShow = nil
        for _, h in ipairs((s.hooks or {}).OnShow or {}) do h(s) end
      end
    end end
    if k == "Hide" then return function(s)
      local was = s.shown
      s.shown = false
      if was then for _, h in ipairs((s.hooks or {}).OnHide or {}) do h(s) end end
    end end
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetTextColor" then return function(s, r, g, b) s.color = { r, g, b } end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetWidth" then return function(s) return s.width or 372 end end
    if k == "GetHeight" then return function(s) return s.height or 100 end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetWidth" then return function(s, w) s.width = w end end
    if k == "SetHeight" then return function(s, h) s.height = h end end
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "GetScale" then return function(s) return s.scale or 1 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "ClearAllPoints" then return function(s) s.points = {} end end
    if k == "SetPoint" then return function(s, ...) s.points = s.points or {}; s.points[#s.points + 1] = { ... } end end
    if k == "CreateFontString" then return function() return Obj() end end
    if k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" then
      local sb = Obj(); rawset(sb, "ThumbTexture", false); rawset(sb, "ScrollUpButton", false); rawset(sb, "ScrollDownButton", false)
      rawset(t, k, sb); return sb
    end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

local MAPS = {
  [1415] = { name = "Eastern Kingdoms", parentMapID = 947, mapType = 2 },
  [1429] = { name = "Elwynn Forest", parentMapID = 1415, mapType = 3 },
  [1453] = { name = "Stormwind City", parentMapID = 1415, mapType = 3 },
}
GROUP, GUILD = nil, nil
CLOCK = 1000
local SECRET = {}

-- A client: opts.side is your own side ("Alliance", "Horde", "Neutral" or nil for "the game doesn't say").
local function boot(name, saved, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  local realCreate = c.CreateFrame
  c.FRAMES = {}
  c.CreateFrame = function(kind, fname)
    local o = Obj()
    local base = realCreate()
    for k, v in pairs(base) do if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end end
    rawset(o, "kindOf", kind)
    c.FRAMES[#c.FRAMES + 1] = o
    if fname then c[fname] = o end
    return o
  end
  c.UISpecialFrames = {}
  c.UIParent = Obj()
  rawset(c.UIParent, "width", 1024); rawset(c.UIParent, "height", 768)
  c.TIP = {}
  c.GameTooltip = setmetatable({}, { __index = function(_, k)
    return function(_, ...) c.TIP[#c.TIP + 1] = { k, ... } end
  end })
  c.C_Map = {
    GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parentMapID, mapType = m.mapType } or nil end,
    GetBestMapForUnit = function() return c.HERE and c.HERE.map end,
    GetPlayerMapPosition = function(map)
      local h = c.HERE
      if not h or h.map ~= map then return nil end
      return { GetXY = function() return h.x, h.y end }
    end,
  }
  c.GetTime = function() return CLOCK end
  c.IsInInstance = function() return false end
  c.UnitClassBase = function() return "MAGE" end
  c.issecretvalue = function(v) return v == SECRET end
  c.SIDE = opts.side
  c.UnitFactionGroup = function(unit)
    if unit == "npc" then return c.NPC and c.NPC.side end
    return c.SIDE
  end
  c.NPC = nil
  c.UnitGUID = function(u) if u == "npc" then return c.NPC and c.NPC.guid end return "Player-1-" .. name end
  c.UnitName = function(u) if u == "npc" then return c.NPC and c.NPC.name end return (name:gsub(" .*$", "")) end
  c.MERCHANT = {}
  c.ITEMS = {}
  c.GetMerchantNumItems = function() return #c.MERCHANT end
  c.GetMerchantItemID = function(i) return c.MERCHANT[i] end
  -- the item cache: NAMES[id] is what the client has; asking for an item brings it in when the test says so
  c.NAMES, c.QUALITY, c.REQUESTED = {}, {}, {}
  c.C_Item = {
    GetItemInfoInstant = function(id) local it = c.ITEMS[id]; if it then return id, "", "", "", 134400, it[1], it[2] end end,
    GetItemNameByID = function(id) return c.NAMES[id] end,
    GetItemIconByID = function(id) return c.NAMES[id] and 100000 + id or nil end,
    GetItemQualityByID = function(id) return c.NAMES[id] and (c.QUALITY[id] or 1) or nil end,
    GetItemQualityColor = function(q) if q == 2 then return 0.12, 1, 0 end return 1, 1, 1 end,
    GetItemInfo = function(id) if c.NAMES[id] then return c.NAMES[id], "|cff1eff00|Hitem:" .. id .. "|h[" .. c.NAMES[id] .. "]|h|r" end end,
    RequestLoadItemDataByID = function(id) c.REQUESTED[#c.REQUESTED + 1] = id end,
  }
  c.CanMerchantRepair = function() return false end
  c.C_Trainer = { GetTrainerType = function() return c.TRAINER end }
  c.GetTrainerServiceSkillLine = function() return nil end
  c.UnitIsPlayer = function() return false end
  c.CLICKS = {}
  c.HandleModifiedItemClick = function(link) c.CLICKS[#c.CLICKS + 1] = link return true end
  c.POPUPS = {}
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function(key, text) table.insert(c.POPUPS, { key = key, text = text, dialog = c.StaticPopupDialogs[key] }) return {} end
  c.InCombatLockdown = function() return false end
  c.IsInRaid = function() return false end
  c.UIErrorsFrame = { AddMessage = function() end }
  c.PRINTED = {}
  c.print = function(s) table.insert(c.PRINTED, tostring(s)) end
  Load(c, { "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "modules/Interact.lua", "pins/Pins.lua", "npcs/Kinds.lua", "npcs/Store.lua",
    "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Share.lua", "npcs/Knowledge.lua", "npcs/Items.lua", "npcs/Stock.lua",
    "npcs/Search.lua", "diag/Diagnostics.lua", "diag/Npcs.lua" })
  c.TwichUIDB = saved or { modules = { npcMap = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
  c.R = c.TwichUI
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end end

local A, B = "Ranulf Ashenvow", "Pal Stonebrook"

-- Opens a merchant's window (one read now, one a moment later) at a place; `side` is the NPC's own.
local function Visit(c, id, name, items, side, place)
  c.HERE = place or { map = 1453, x = 0.40, y = 0.40 }
  c.NPC = { guid = ("Creature-0-1-0-1-%d-00001"):format(id), name = name, side = side }
  c.MERCHANT = items
  for _, item in ipairs(items) do c.ITEMS[item] = c.ITEMS[item] or { 0, 1 } end
  c.FireEvent("MERCHANT_SHOW")
  FlushTimers()
  c.FireEvent("MERCHANT_CLOSED")
  c.NPC = nil
end

---------------------------------------------------------------------------
-- 1. The side an NPC serves is recorded from what the game says
---------------------------------------------------------------------------
local a = boot(A, nil, { side = "Alliance" })
local R = a.R
local NS, NC, NK, NP, NMAP, KN, NI, ST, SR = R.NpcStore, R.NpcCollect, R.NpcKinds, R.NpcPrefs, R.NpcMap, R.NpcKnowledge, R.NpcItems, R.NpcStock, R.NpcSearch
NP.Set("show.vendor", true)   -- (these merchants sell nothing the default kinds list)
NP.Set("show.banker", true)
Visit(a, 100, "Stormwind Baker", { 4540 }, "Alliance")
Visit(a, 101, "Orgrimmar Baker", { 4540 }, "Horde")
Visit(a, 102, "Booty Bay Baker", { 4540 }, nil)
local function At(id) return NS.Near(id, 1453, 4000, 4000) end
Check(At(100).f == "A" and At(101).f == "H", "the game's faction group is kept as a code")
Check(At(102).f == "N", "a creature of neither side: neutral")
a.NPC = { guid = "Creature-0-1-0-1-103-00001", name = "Odd", side = SECRET }
a.HERE = { map = 1453, x = 0.40, y = 0.40 }
a.MERCHANT = { 4540 }
a.FireEvent("MERCHANT_SHOW"); FlushTimers(); a.FireEvent("MERCHANT_CLOSED")
Check(At(103) and At(103).f == nil, "a reading the game won't give leaves the side unrecorded")
Check(NS.Valid(At(100)) and NS.FactionCode("Alliance") == "A" and NS.FactionCode("Neutral") == "N" and NS.FactionCode("Gnome") == nil)
-- a stored side that isn't one of the three makes the entry unreadable (skipped, never erased)
local odd = { id = 9, n = "Odd", m = 1429, x = 1, y = 1, tags = { banker = true }, f = "X" }
Check(not NS.Valid(odd), "an unknown side is not valid")
-- a later visit fills a side in; a visit never loses one
a.NPC = { guid = "Creature-0-1-0-1-103-00001", name = "Odd", side = "Horde" }
a.MERCHANT = { 4540 }
a.FireEvent("MERCHANT_SHOW"); FlushTimers(); a.FireEvent("MERCHANT_CLOSED")
Check(At(103).f == "H", "the next visit records it")
a.NPC = { guid = "Creature-0-1-0-1-103-00001", name = "Odd", side = SECRET }
a.FireEvent("MERCHANT_SHOW"); FlushTimers(); a.FireEvent("MERCHANT_CLOSED")
Check(At(103).f == "H", "an unreadable visit keeps what was known")

---------------------------------------------------------------------------
-- 2. A character never meets an NPC of the other side on the map or in a search
---------------------------------------------------------------------------
NS.Observe({ id = 200, name = "Legacy Vendor", map = 1453, x = 0.40, y = 0.40, tags = { banker = true } })
Check(NS.Near(200, 1453, 4000, 4000).f == nil, "an NPC noted without a side stays unrecorded")
Check(NS.MyFaction() == "A")
local Aend, Hend, Nend, Lend = At(100), At(101), At(102), NS.Near(200, 1453, 4000, 4000)
Check(NS.Usable(Aend, "A") and not NS.Usable(Aend, "H") and NS.Usable(Hend, "H") and not NS.Usable(Hend, "A"))
Check(NS.Usable(Nend, "A") and NS.Usable(Nend, "H") and NS.Usable(Lend, "A") and NS.Usable(Lend, "H"), "neutral and unrecorded are for everyone")
Check(NS.Usable(Hend, nil) and NS.Usable(Aend, nil), "a character with no side known hides nothing")
Check(not NS.Usable(Aend, "N") and NS.Usable(Nend, "N"), "a neutral character is shown neutral ones only")
Check(NMAP.ShownKind(Aend) and NMAP.ShownKind(Hend) == nil, "the map: your side's merchants, not the other's")
Check(NMAP.ShownKind(Nend) and NMAP.ShownKind(Lend), "the map shows the neutral and the unrecorded")
a.SIDE = "Horde"
Check(NMAP.ShownKind(Hend) and NMAP.ShownKind(Aend) == nil, "and the other way round")
a.SIDE = nil
Check(NMAP.ShownKind(Hend) and NMAP.ShownKind(Aend), "no side readable: nothing is hidden")
a.SIDE = SECRET
Check(NS.MyFaction() == nil, "a secret value is not a side")
a.SIDE = "Alliance"
-- search
local names = {}
for _, r in ipairs((SR.Run("baker", { }, 8))) do names[#names + 1] = r.name end
table.sort(names)
Check(table.concat(names, ",") == "Booty Bay Baker,Stormwind Baker", "search: " .. table.concat(names, ","))
a.SIDE = "Horde"
names = {}
for _, r in ipairs((SR.Run("baker", { }, 8))) do names[#names + 1] = r.name end
table.sort(names)
Check(table.concat(names, ",") == "Booty Bay Baker,Orgrimmar Baker", "a Horde character: " .. table.concat(names, ","))
a.SIDE = "Alliance"
-- the World Knowledge tab still lists everything, and says which side
local rowH = KN.Row(Hend)
Check(rowH and KN.Details(rowH).faction:find("Horde", 1, true) and KN.Details(rowH).faction:find("not shown", 1, true), KN.Details(rowH).faction)
Check(KN.Details(KN.Row(Aend)).faction == "Alliance" and KN.Details(KN.Row(Lend)).faction:find("not recorded", 1, true))
Check(KN.Details(KN.Row(Nend)).faction == "Neutral")
Check(#KN.Filter({ text = "baker" }) == 3, "the list itself keeps every NPC it knows")

---------------------------------------------------------------------------
-- 3. The side travels with a report and never changes what you saw
---------------------------------------------------------------------------
local w = NS.Wire(Hend)
Check(w.f == "H" and NS.Wire(Lend).f == nil)
local read = assert(NS.ReadWire({ i = 300, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" }, f = "H" }))
Check(read.f == "H")
Check(NS.ReadWire({ i = 301, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" } }).f == nil, "an older TwichUI sends no side")
for _, bad in ipairs({ "Horde", "", 5, true, {} }) do
  local r, why = NS.ReadWire({ i = 302, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" }, f = bad })
  Check(r == nil and why == "bad-faction", "bad side " .. tostring(bad))
end
NS.MergeReported({ read })
Check(NS.Near(300, 1429, 100, 100).f == "H", "a report brings its side")
NS.MergeReported({ NS.ReadWire({ i = 300, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" }, f = "A" }) })
Check(NS.Near(300, 1429, 100, 100).f == "H", "a later report never flips it")
NS.MergeReported({ NS.ReadWire({ i = 301, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" } }) })
NS.MergeReported({ NS.ReadWire({ i = 301, n = "Heard", m = 1429, x = 100, y = 100, k = { "bk" }, f = "A" }) })
Check(NS.Near(301, 1429, 100, 100).f == "A", "a report fills in a side that was missing")
NS.MergeReported({ NS.ReadWire({ i = 100, n = "Stormwind Baker", m = 1453, x = 4000, y = 4000, k = { "fd" }, f = "H" }) })
Check(At(100).f == "A", "a report never changes an NPC you saw yourself")
-- a reported NPC you then visit takes your reading
a.HERE = { map = 1429, x = 0.01, y = 0.01 }
a.NPC = { guid = "Creature-0-1-0-1-300-00001", name = "Heard", side = "Alliance" }
a.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
Check(NS.Near(300, 1429, 100, 100).f == "A" and NS.Near(300, 1429, 100, 100).own, "seen yourself: what you saw replaces what was said")
a.NPC = nil

---------------------------------------------------------------------------
-- 4. What a merchant sells is recorded as item numbers, newest visit first
---------------------------------------------------------------------------
Visit(a, 400, "Acorn Seller", { 7005, 4540, 4540, 117, 7005 }, "Alliance", { map = 1429, x = 0.30, y = 0.30 })
local m = NS.Near(400, 1429, 3000, 3000)
Check(m.s and table.concat(m.s, ",") == "117,4540,7005", "sorted, once each: " .. table.concat(m.s or {}, ","))
Check(m.seen == 1, "reading the list twice in a visit is one visit")
-- a list that arrives in parts: the second read adds to the first
a.HERE = { map = 1429, x = 0.30, y = 0.30 }
a.NPC = { guid = "Creature-0-1-0-1-400-00001", name = "Acorn Seller", side = "Alliance" }
a.MERCHANT = { 117 }; a.ITEMS[117] = { 0, 1 }
a.FireEvent("MERCHANT_SHOW")
Check(table.concat(m.s, ",") == "117", "a new visit replaces the last list")
a.MERCHANT = { 117, 8932 }; a.ITEMS[8932] = { 0, 1 }
FlushTimers()
Check(table.concat(m.s, ",") == "117,8932", "the same visit's later read adds to it: " .. table.concat(m.s, ","))
a.FireEvent("MERCHANT_CLOSED"); a.NPC = nil
-- bad numbers never get in; the list is bounded
local capped = {}
for i = 1, 200 do capped[#capped + 1] = 1000 + i end
capped[#capped + 1] = -4; capped[#capped + 1] = 2.5; capped[#capped + 1] = 0; capped[#capped + 1] = "x"
local cleaned = NS.CleanItems(capped)
Check(#cleaned == NS.MAX_ITEMS and cleaned[1] == 1001 and cleaned[#cleaned] == 1000 + NS.MAX_ITEMS, "whole numbers only, at most " .. NS.MAX_ITEMS)
Check(NS.CleanItems({}) == nil and NS.CleanItems("x") == nil and NS.CleanItems({ "a", 0 }) == nil)
-- a saved list that isn't item numbers makes the entry unreadable (kept, not erased)
Check(not NS.Valid({ id = 9, n = "X", m = 1429, x = 1, y = 1, tags = { vendor = true }, s = { 5, "x" } }))
Check(not NS.Valid({ id = 9, n = "X", m = 1429, x = 1, y = 1, tags = { vendor = true }, s = { 5, 9, [7] = 3 } }), "no holes")
Check(NS.Valid({ id = 9, n = "X", m = 1429, x = 1, y = 1, tags = { vendor = true }, s = { 5, 9 } }))
-- what the probe prints says how many ids were kept
a.NPC = { guid = "Creature-0-1-0-1-401-00001", name = "Probe Vendor", side = "Horde" }
NC.Probe(true)
a.PRINTED = {}
a.HERE = { map = 1453, x = 0.5, y = 0.5 }
a.MERCHANT = { 117, 4540 }
a.FireEvent("MERCHANT_SHOW"); a.FireEvent("MERCHANT_CLOSED")
local said = table.concat(a.PRINTED, "\n")
Check(said:find("2 item ids kept", 1, true) and said:find("side: Horde", 1, true), said)
NC.Probe(false); a.NPC = nil

---------------------------------------------------------------------------
-- 5. Stock on the wire is read as untrusted
---------------------------------------------------------------------------
local function Bad(w2, code)
  local r, why = NS.ReadWire(w2)
  Check(r == nil and why == code, tostring(why) .. " vs " .. code)
end
local base = { i = 500, n = "Seller", m = 1429, x = 100, y = 100, k = { "fd" } }
local function With(s) local t = {} for k, v in pairs(base) do t[k] = v end t.s = s return t end
Check(table.concat(NS.ReadWire(With({ 9, 3, 3, 5 })).s, ",") == "3,5,9", "cleaned on arrival")
Bad(With({ 3, "x" }), "bad-items")
Bad(With({ 3, -1 }), "bad-items")
Bad(With({ 3, 2.5 }), "bad-items")
Bad(With({ 3, 2 ^ 31 + 1 }), "bad-items")
Bad(With("12"), "bad-items")
local tooMany = {}
for i = 1, NS.MAX_ITEMS + 1 do tooMany[i] = i end
Bad(With(tooMany), "bad-items")
local notMerchant = { i = 501, n = "Banker", m = 1429, x = 100, y = 100, k = { "bk" }, s = { 4 } }
Bad(notMerchant, "bad-items")   -- a banker has no stock
Check(NS.Wire(m).s == m.s, "the stock goes as it is held")

---------------------------------------------------------------------------
-- 6. Stock in reports: added to, bounded, never changing what you saw
---------------------------------------------------------------------------
local rep1 = NS.ReadWire({ i = 600, n = "Reported Seller", m = 1429, x = 5000, y = 5000, k = { "fd" }, s = { 10, 20 } })
NS.MergeReported({ rep1 })
local repE = NS.Near(600, 1429, 5000, 5000)
Check(repE and table.concat(repE.s, ",") == "10,20" and not repE.own)
NS.MergeReported({ NS.ReadWire({ i = 600, n = "Reported Seller", m = 1429, x = 5000, y = 5000, k = { "fd" }, s = { 20, 30 } }) })
Check(table.concat(repE.s, ",") == "10,20,30", "another report adds to a report's stock")
NS.MergeReported({ NS.ReadWire({ i = 400, n = "Acorn Seller", m = 1429, x = 3000, y = 3000, k = { "fd" }, s = { 999999 } }) })
Check(table.concat(m.s, ",") == "117,8932", "a report never changes the stock you saw")
-- once the list holds as many items as allowed, what others send adds none
local was = NS.MAX_ITEM_SLOTS
local slots = NS.ItemSlots()
NS.MAX_ITEM_SLOTS = slots
NS.MergeReported({ NS.ReadWire({ i = 600, n = "Reported Seller", m = 1429, x = 5000, y = 5000, k = { "fd" }, s = { 40, 50 } }) })
Check(table.concat(repE.s, ",") == "10,20,30", "over the limit: no more stock from reports")
NS.MergeReported({ NS.ReadWire({ i = 601, n = "Late Seller", m = 1429, x = 6000, y = 6000, k = { "fd" }, s = { 60 } }) })
local late = NS.Near(601, 1429, 6000, 6000)
Check(late and late.s == nil, "the NPC is still noted, without its stock")
Check(NS.ItemSlots() == slots)
NS.MAX_ITEM_SLOTS = was
-- you visiting a reported merchant replaces what was said with what you saw
a.HERE = { map = 1429, x = 0.50, y = 0.50 }
Visit(a, 600, "Reported Seller", { 77 }, "Alliance", { map = 1429, x = 0.50, y = 0.50 })
Check(repE.own and table.concat(repE.s, ",") == "77", "your visit: " .. table.concat(repE.s or {}, ","))

---------------------------------------------------------------------------
-- 7. Sharing: lists and live messages carry the side and the stock
---------------------------------------------------------------------------
NET, SENT_LOG, CLIENTS = {}, {}, {}
GROUP = { [A] = true, [B] = true }
GUILD = nil
local sa = boot(A, nil, { side = "Alliance" })
local sb = boot(B, nil, { side = "Horde" })
local SA, SB = sa.R.NpcStore, sb.R.NpcStore
local sbp = sb.R.NpcPrefs
-- a merchant with a big stock splits a list into parts by item count (live sharing is for later in this section)
sa.R.NpcPrefs.Set("liveGroup", false)
for i = 1, 30 do
  local items = {}
  for j = 1, 100 do items[j] = i * 1000 + j end
  Visit(sa, 2000 + i, "Big Seller " .. i, items, i % 2 == 0 and "Alliance" or "Horde", { map = 1453, x = i / 40, y = 0.5 })
end
local plan = assert(sa.R.NpcShare.Plan("party"))
Check(plan.count == 30 and plan.items == 3000, "the plan counts what goes: " .. plan.count .. " / " .. plan.items)
Check(plan.parts == 3, "1000 items a part: " .. plan.parts)
for _, part in ipairs(plan.partList) do
  local n = 0
  for _, wire in ipairs(part) do n = n + #wire.s end
  Check(n <= sa.R.NpcShare.PART_ITEMS and #part <= sa.R.NpcShare.PART_SIZE, "a part is bounded")
end
local text = sa.R.NpcShare.Describe(plan)
Check(text:find("3000 items", 1, true) and text:find("which side", 1, true) and text:find("seconds", 1, true), text)
sa.R.NpcShare.Send(plan)
settle()
local q = sb.POPUPS[#sb.POPUPS]
Check(q and q.key == "TWICHUI_NPC_RECEIVE" and q.text:find("30 are new to you", 1, true), q and q.text)
q.dialog.OnAccept()
local got = SB.Near(2002, 1453, 500, 5000)
Check(got and got.f == "A" and #got.s == 100 and got.s[1] == 2001, "the list arrives with side and stock")
Check(not got.own, "as a report")
-- a long list takes minutes, and the question says so
local bigPlan = { count = 3000, items = 60000, own = 3000, reported = 0, dist = "PARTY", label = "your group", wires = {} }
Check(sa.R.NpcShare.Describe(bigPlan):find("minutes", 1, true), "an honest time")
-- live: one small message when you deal with an NPC, with its stock
RunLongTimers(30); settle()   -- (the sellers above were waiting to be passed on; with no channel chosen they go nowhere)
CLOCK = CLOCK + 120
sbp.Set("liveReceive", true)
sa.R.NpcPrefs.Set("liveGroup", true)
local before = select(2, SB.Counts())
Visit(sa, 3001, "Live Seller", { 55, 56, 57 }, "Horde", { map = 1453, x = 0.9, y = 0.9 })
RunLongTimers(30); settle()
local live = SB.Near(3001, 1453, 9000, 9000)
Check(live and live.f == "H" and table.concat(live.s, ",") == "55,56,57" and select(2, SB.Counts()) == before + 1, "live: side and stock")
-- the same merchant with another item is sent again; with nothing new it is not
local sent = sa.R.NpcShare.Snapshot().liveSent
Visit(sa, 3001, "Live Seller", { 55, 56, 57 }, "Horde", { map = 1453, x = 0.9, y = 0.9 })
RunLongTimers(30); settle()
Check(sa.R.NpcShare.Snapshot().liveSent == sent, "nothing new: once")
Visit(sa, 3001, "Live Seller", { 55, 56, 57, 58 }, "Horde", { map = 1453, x = 0.9, y = 0.9 })
RunLongTimers(30); settle()
Check(sa.R.NpcShare.Snapshot().liveSent == sent + 1 and #live.s == 4, "a new item is passed on")
-- a forged stock in a live message adds nothing
local LS, LD = sb.LibStub("LibSerialize"), sb.LibStub("LibDeflate")
local function Raw(msg) return LD:EncodeForWoWAddonChannel(LS:Serialize(msg)) end
local recv = sb._comm["TwichUINpc"]
local n0 = #SB.Entries()
recv("TwichUINpc", Raw({ v = 1, o = "live", l = { { i = 9100, n = "Forged", m = 1429, x = 1, y = 1, k = { "fd" }, s = { "<script>" } } } }), "PARTY", A)
Check(#SB.Entries() == n0, "a stock that isn't numbers adds nothing")
-- an old TwichUI's entry (no side, no stock) is still read
recv("TwichUINpc", Raw({ v = 1, o = "live", l = { { i = 9101, n = "Old Style", m = 1429, x = 1, y = 1, k = { "fd" } } } }), "PARTY", A)
Check(#SB.Entries() == n0 + 1 and SB.Near(9101, 1429, 1, 1).f == nil and SB.Near(9101, 1429, 1, 1).s == nil)

---------------------------------------------------------------------------
-- 8. Item names come from the game, asked for a few at a time
---------------------------------------------------------------------------
local c = boot("Namer", nil, { side = "Alliance" })
local CR = c.R
local CNS, CNI = CR.NpcStore, CR.NpcItems
Check(CNI.Name(1) == nil and CNI.Link(1) == nil and CNI.Color(1) == nil)
c.NAMES[1], c.QUALITY[1] = "Acorn", 2
Check(CNI.Name(1) == "Acorn" and CNI.Link(1):find("|Hitem:1|h[Acorn]|h", 1, true))
local r, g, b = CNI.Color(1)
Check(r == 0.12 and g == 1 and b == 0)
-- a name the client already has is not asked for, and is not left waiting
c.NAMES[3] = "Known Thing"
Check(CNI.Request({ 3 }) == 0, "the known one is not queued")
FlushTimers()
Check(#c.REQUESTED == 0, "the known one is not asked for")
Check(CNI.Snapshot().waiting == 0, "the known one is not left waiting")
-- a name the client learns while the ask is still queued is not asked for, and is not left waiting
local early = {}
for i = 1, 30 do early[i] = 7000 + i end
Check(CNI.Request(early) == 30)
c.NAMES[7001] = "Early Arrival"
for _ = 1, 3 do FlushTimers() end
local askedEarly = {}
for _, id in ipairs(c.REQUESTED) do askedEarly[id] = true end
Check(not askedEarly[7001], "the one already named is not asked for")
Check(askedEarly[7002] and askedEarly[7030], "the rest of the batch still goes")
Check(CNI.Snapshot().waiting == 29, "the named one is not left waiting: " .. CNI.Snapshot().waiting)
for _, id in ipairs(c.REQUESTED) do c.NAMES[id] = "Arrived " .. id end
for _, id in ipairs(c.REQUESTED) do c.FireEvent("GET_ITEM_INFO_RECEIVED", id, true) end
FlushTimers()
Check(CNI.Snapshot().waiting == 0, "the batch settles: " .. CNI.Snapshot().waiting)
c.REQUESTED = {}
c.NAMES[2] = "Plain Thing"
c.C_Item.GetItemInfo = nil
Check(CNI.Link(2) == "|cffffffff|Hitem:2|h[Plain Thing]|h|r", "a link made from the name when the game has none: " .. tostring(CNI.Link(2)))
c.NAMES[1], c.NAMES[2] = nil, nil
-- many unknown names: asked a batch at a time, once each
local ids = {}
for i = 1, 70 do ids[i] = 5000 + i end
Check(CNI.Request(ids) == 70)
Check(CNI.Request(ids) == 70, "(queued again only until they are asked)")
Check(#c.REQUESTED == 0, "nothing at once")
FlushTimers()
Check(#c.REQUESTED == CNI.REQUEST_BATCH, "one batch: " .. #c.REQUESTED)
FlushTimers()
Check(#c.REQUESTED == 2 * CNI.REQUEST_BATCH)
for _ = 1, 5 do FlushTimers() end
Check(#c.REQUESTED == 70, "every one asked for once: " .. #c.REQUESTED)
local seenId = {}
for _, id in ipairs(c.REQUESTED) do Check(not seenId[id], "never twice") seenId[id] = true end
for _ = 1, 3 do FlushTimers() end
Check(#c.REQUESTED == 70, "never asked again this session")
-- an answer calls the listeners once, a moment later
local told = 0
CNI.OnNames(function() told = told + 1 end)
c.NAMES[5001] = "Arrived"
c.FireEvent("GET_ITEM_INFO_RECEIVED", 5001, true)
c.FireEvent("GET_ITEM_INFO_RECEIVED", 5002, true)
c.FireEvent("GET_ITEM_INFO_RECEIVED", 424242, true)   -- not one we asked for
FlushTimers()
Check(told == 1, "told once: " .. told)
-- an answer for an id the client already knew is not dropped:
-- it still tells the listeners once, a moment later
local toldKnown = 0
CNI.OnNames(function() toldKnown = toldKnown + 1 end)
c.NAMES[5003] = "Already Known"
c.FireEvent("GET_ITEM_INFO_RECEIVED", 5003, true)
FlushTimers()
Check(toldKnown == 1, "told once for the already-known one: " .. toldKnown)
-- a name the client learns while the ask is still queued is not asked for, and is not left waiting
local late = {}
for i = 1, 30 do late[i] = 6000 + i end
Check(CNI.Request(late) == 30)
c.NAMES[6001] = "Early Arrival"
for _ = 1, 3 do FlushTimers() end
local askedLate = {}
for _, id in ipairs(c.REQUESTED) do askedLate[id] = true end
Check(not askedLate[6001], "the one already named is not asked for")
Check(askedLate[6002] and askedLate[6030], "the rest of the batch still goes")

---------------------------------------------------------------------------
-- 9. Searching by what a merchant sells
---------------------------------------------------------------------------
local s = boot("Seeker", nil, { side = "Alliance" })
local SS = s.R
local SNS, SSR, SNI = SS.NpcStore, SS.NpcSearch, SS.NpcItems
-- three merchants: two near each other sell an acorn (one is the other side's), one sells something else
Visit(s, 7001, "Gilnean Forager", { 1100, 1101 }, "Alliance", { map = 1429, x = 0.30, y = 0.30 })
Visit(s, 7002, "Horde Forager", { 1100 }, "Horde", { map = 1429, x = 0.31, y = 0.30 })
Visit(s, 7003, "Far Baker", { 1100, 1200 }, nil, { map = 1453, x = 0.80, y = 0.80 })
Visit(s, 7004, "Plain Smith", { 1300 }, "Alliance", { map = 1429, x = 0.50, y = 0.50 })
s.NAMES[1100], s.NAMES[1101], s.NAMES[1200], s.NAMES[1300] = "Tough Acorn", "Oak Acorn Cap", "Hunk of Bread", "Iron Hammer"
s.QUALITY[1100] = 2
s.HERE = { map = 1429, x = 0.30, y = 0.30 }
local spot = { map = 1429 }
local res, total = SSR.Run("acorn", spot, 8)
local list = {}
for _, rr in ipairs(res) do list[#list + 1] = rr.name end
Check(table.concat(list, ",") == "Gilnean Forager,Far Baker" and total == 2, "the other side's merchant is not a result: " .. table.concat(list, ","))
Check(res[1].items and res[1].itemCount == 2 and res[1].items[1] == 1101 or res[1].items[1] == 1100, "the matching items are named")
Check(res[1].items[1] == 1101 and res[1].items[2] == 1100, "by name: Oak Acorn Cap, Tough Acorn")
Check(res[1].tier == 2 and res[2].tier == 3, "the one in this area ranks first")
-- every word has to be found: an item word and an NPC word together
res = SSR.Run("acorn gilnean", spot, 8)
Check(#res == 1 and res[1].name == "Gilnean Forager", "the words an item lacks are looked for in the NPC's text")
Check(#SSR.Run("acorn smith", spot, 8) == 0, "an item's word and a word in neither: nothing")
Check(#SSR.Run("hammer", spot, 8) == 1 and SSR.Run("hammer", spot, 8)[1].name == "Plain Smith")
Check(#SSR.Run("zzzz", spot, 8) == 0)
-- a merchant that matches by its own text is not described by items
res = SSR.Run("forager", spot, 8)
Check(#res == 1 and res[1].items == nil, "found by name: no item line")
-- an item the client has not met has no name to search; it is asked for, and found once it arrives
Visit(s, 7005, "Mystery Seller", { 9999 }, "Alliance", { map = 1429, x = 0.60, y = 0.60 })
res = SSR.Run("lantern", spot, 8)
Check(#res == 0, "not known yet")
FlushTimers()
local asked = false
for _, id in ipairs(s.REQUESTED) do if id == 9999 then asked = true end end
Check(asked, "a search asks the game for the names it lacks")
s.NAMES[9999] = "Glowing Lantern"
s.FireEvent("GET_ITEM_INFO_RECEIVED", 9999, true)
FlushTimers()
res = SSR.Run("lantern", spot, 8)
Check(#res == 1 and res[1].name == "Mystery Seller", "found once the game has it")
-- the search stops asking when it is let go, and the index with it
SNI.Release()
Check(not SNI.Snapshot().indexed)
-- a limit on how many a session asks for
local capSeen = 0
for i = 1, 50 do SNS.Observe({ id = 8000 + i, name = "Cap " .. i, map = 1429, x = (i % 20) / 40 + 0.05, y = math.floor(i / 20) / 10 + 0.05, tags = { vendor = true }, items = { 20000 + i } }) end
SNI.REQUEST_SESSION_MAX = #s.REQUESTED + 10
SSR.Run("qqq", spot, 8)
for _ = 1, 6 do FlushTimers() end
Check(#s.REQUESTED <= SNI.REQUEST_SESSION_MAX + SNI.REQUEST_BATCH, "a search asks for no more than its share: " .. #s.REQUESTED)

---------------------------------------------------------------------------
-- 10. The menu and the window
---------------------------------------------------------------------------
local menus
local ST = SS.NpcStock
SS.PinsWindow = { OpenMenu = function(anchor, title, choices) menus = { title = title, choices = choices } end }
local merchant = SNS.Near(7001, 1429, 3000, 3000)
SS.NpcMap.Menu(merchant, {})
Check(menus.choices[1].label == "Show items for sale" and menus.choices[1].enabled == true, "the first choice for a merchant")
local banker = SNS.Observe({ id = 7100, name = "A Banker", map = 1429, x = 0.7, y = 0.7, tags = { banker = true } })
SS.NpcMap.Menu(banker, {})
Check(menus.choices[1].label == "Set waypoint", "no stock choice for an NPC that sells nothing")
local nostock = SNS.Observe({ id = 7101, name = "Quiet Seller", map = 1429, x = 0.8, y = 0.8, tags = { food = true } })
SS.NpcMap.Menu(nostock, {})
Check(menus.choices[1].label == "Show items for sale" and menus.choices[1].enabled == false and menus.choices[1].why:find("No stock"),
  "a merchant with no stock noted: the choice says why it can't")
-- the window
s.NAMES[1100], s.NAMES[1101] = "Tough Acorn", "Oak Acorn Cap"
s.NAMES[1099] = nil
local okShow, whyShow = ST.Show(merchant)
Check(okShow, "opens for a merchant in the list: " .. tostring(whyShow))
local win = ST.Frame()
Check(win:IsShown() and ST.Shown() == merchant)
Check(win.title.text == "Gilnean Forager" and win.sub.text:find("Elwynn Forest", 1, true), win.title.text .. " / " .. win.sub.text)
Check(win.status.text == "2 items noted.", win.status.text)
local rowsShown = {}
for _, f in ipairs(s.FRAMES) do if f.id and f.scripts and f.scripts.OnClick then rowsShown[#rowsShown + 1] = f end end
Check(#rowsShown == 2, "a row for each item")
table.sort(rowsShown, function(x, y) return x.name.text < y.name.text end)
Check(rowsShown[1].name.text == "Oak Acorn Cap" and rowsShown[2].name.text == "Tough Acorn", "full names")
Check(rowsShown[2].id == 1100 and rowsShown[2].icon.texture == 101100, "its own icon")
local cr = rowsShown[2].name.color
Check(cr and cr[1] == 0.12 and cr[2] == 1, "in its quality colour")
-- the tooltip is the game's item tooltip, and a click is the game's item click
s.TIP = {}
rowsShown[2].scripts.OnEnter(rowsShown[2])
local gotTip = false
for _, call in ipairs(s.TIP) do if call[1] == "SetItemByID" and call[2] == 1100 then gotTip = true end end
Check(gotTip, "SetItemByID with the item number")
rowsShown[2].scripts.OnClick(rowsShown[2])
Check(#s.CLICKS == 1 and s.CLICKS[1]:find("|Hitem:1100|h[Tough Acorn]|h", 1, true), "the item's link goes to the game's item click")
-- the filter
win.filter.text = "oak"
win.filter.hooks.OnTextChanged[#win.filter.hooks.OnTextChanged](win.filter, true)
Check(win.status.text == "1 of 2 shown.", win.status.text)
win.filter.text = "zzz"
win.filter.hooks.OnTextChanged[#win.filter.hooks.OnTextChanged](win.filter, true)
Check(win.empty:IsShown(), "says nothing matches")
-- an item the client hasn't met shows by number, and is asked for; the names settle when they arrive
Visit(s, 7006, "Lantern Seller", { 9998 }, "Alliance", { map = 1429, x = 0.65, y = 0.65 })
local mystery = SNS.Near(7006, 1429, 6500, 6500)
s.REQUESTED = {}
ST.Show(mystery)
Check(win.status.text:find("1 still loading", 1, true), win.status.text)
FlushTimers()
Check(s.REQUESTED[1] == 9998, "asked for")
local row = nil
for _, f in ipairs(s.FRAMES) do if f.id == 9998 then row = f end end
Check(row and row.name.text == "Item 9998", "shown by number until the game has it")
s.NAMES[9998] = "Glowing Lantern"
s.FireEvent("GET_ITEM_INFO_RECEIVED", 9998, true)
FlushTimers()
Check(row.name.text == "Glowing Lantern", "then by name")
-- a mixed list: the known ones are named at once, the unknown ones by number until their answers arrive late
Visit(s, 7007, "Mixed Seller", { 1100, 9997, 9996 }, "Alliance", { map = 1429, x = 0.70, y = 0.70 })
local mixed = SNS.Near(7007, 1429, 7000, 7000)
s.REQUESTED = {}
ST.Show(mixed)
Check(win.status.text:find("3 items noted", 1, true) and win.status.text:find("2 still loading", 1, true), win.status.text)
local function Row(id)
    for _, f in ipairs(s.FRAMES) do if f.id == id then return f end end
    return nil
end
Check(Row(1100) and Row(1100).name.text == "Tough Acorn", "the known one is named at once")
Check(Row(9997) and Row(9997).name.text == "Item 9997", "the unknown one by number, with its icon")
Check(Row(9996) and Row(9996).name.text == "Item 9996", "the other unknown one by number")
FlushTimers()
local askedMixed = {}
for _, id in ipairs(s.REQUESTED) do askedMixed[id] = true end
Check(askedMixed[9997] and askedMixed[9996] and not askedMixed[1100], "only the unknown ones are asked for")
s.NAMES[9997] = "Glowing Lantern"
s.FireEvent("GET_ITEM_INFO_RECEIVED", 9997, true)
FlushTimers()
Check(Row(9997) and Row(9997).name.text == "Glowing Lantern", "the first late answer settles its row: " .. tostring(Row(9997) and Row(9997).name.text))
Check(Row(9996) and Row(9996).name.text == "Item 9996", "the other row is still by number: " .. tostring(Row(9996) and Row(9996).name.text))
Check(Row(9996).name.text == "Item 9996" and win.status.text:find("1 still loading", 1, true), win.status.text)
s.NAMES[9996] = "Dull Lantern"
s.FireEvent("GET_ITEM_INFO_RECEIVED", 9996, true)
FlushTimers()
Check(Row(9996).name.text == "Dull Lantern", "the second late answer settles its row")
Check(not win.status.text:find("still loading", 1, true), "nothing still loading: " .. win.status.text)
s.CLICKS = {}
Row(9996).scripts.OnClick(Row(9996))
Check(#s.CLICKS == 1 and s.CLICKS[1]:find("|Hitem:9996|h[Dull Lantern]|h", 1, true), "the settled row links the item by its name")
-- the filter still matches by the settled name, and says when nothing matches
win.filter.text = "lantern"
win.filter.hooks.OnTextChanged[#win.filter.hooks.OnTextChanged](win.filter, true)
Check(win.status.text == "2 of 3 shown.", win.status.text)
win.filter.text = "zzz"
win.filter.hooks.OnTextChanged[#win.filter.hooks.OnTextChanged](win.filter, true)
Check(win.empty:IsShown(), "nothing matches")
win.filter.text = ""
win.filter.hooks.OnTextChanged[#win.filter.hooks.OnTextChanged](win.filter, true)
-- a name the client learns between the ask and the pump is not asked for, and the answer that follows still settles the row
Visit(s, 7008, "Early Seller", { 9995 }, "Alliance", { map = 1429, x = 0.75, y = 0.75 })
local earlyRow = SNS.Near(7008, 1429, 7500, 7500)
s.REQUESTED = {}
ST.Show(earlyRow)
assert(win.status.text:find("1 still loading", 1, true), win.status.text)
s.NAMES[9995] = "Early Lantern"
FlushTimers()
assert(#s.REQUESTED == 0, "the one already named is not asked for")
assert(Row(9995) and Row(9995).name.text == "Item 9995", "still by number until the game's answer arrives")
s.FireEvent("GET_ITEM_INFO_RECEIVED", 9995, true)
FlushTimers()
assert(Row(9995) and Row(9995).name.text == "Early Lantern", "the answer for the already-named one still settles its row: " .. tostring(Row(9995) and Row(9995).name.text))
assert(not win.status.text:find("still loading", 1, true), "nothing still loading: " .. win.status.text)
ST.Show(mystery)   -- back to the first merchant, so the "forget" line below still applies
-- forgetting the merchant closes the window; the feature going off does too
SNS.Forget(mystery)
Check(not win:IsShown(), "the merchant left the list")
ST.Show(merchant)
Check(win:IsShown())
s.TwichUIDB.modules.npcMap = false
ST.Refresh()
Check(not win:IsShown(), "switched off")
Check(select(1, ST.Show(merchant)) == false, "and it won't open while off")
s.TwichUIDB.modules.npcMap = true
Check(s.UISpecialFrames[#s.UISpecialFrames] == "TwichUINpcStock", "Esc closes it (the stand-in entry, never the game-menu handler)")
local made = #s.FRAMES
ST.Show(merchant); ST.Hide(); ST.Show(merchant); ST.Hide()
Check(#s.FRAMES == made, "showing again makes no new frame")

---------------------------------------------------------------------------
-- 11. Diagnostics hold counts only
---------------------------------------------------------------------------
local snap = SNS.Snapshot()
Check(snap.itemSlots > 0 and snap.stocked > 0 and snap.oneSide > 0)
local ds = SS.NpcItems.Snapshot()
Check(ds.asked > 0 and ds.indexed == false)
local report = SS.Diag.Build()
Check(report:find("Vendors and trainers", 1, true) and report:find("sides:", 1, true) and report:find("item names:", 1, true), report)
for _, name in ipairs({ "Gilnean Forager", "Acorn Seller", "Tough Acorn", "Glowing Lantern", "Big Seller" }) do
  Check(not report:find(name, 1, true), "no NPC or item names in the report: " .. name)
end

print("NPC STOCK TESTS PASSED")
