-- Vendors and trainers (npcs/): what an NPC is decided from what it was seen to offer (merchants by item class and
-- repair, trainers by the client's trainer type, services by the interaction); creature ids are read from GUIDs and
-- nothing else is an NPC; the list keeps what you saw apart from what others sent (a report never changes yours, a
-- visit turns a report into yours); places average over visits and a far sighting is another spawn (bounded); maps must
-- be zones or smaller; names are plain text; unreadable saved entries are skipped, never erased; reports expire; the
-- list is bounded and drops reports first; clearing is scoped. Collecting listens only while switched on, notes from the
-- game's windows, skips instances, and the probe alone saves nothing. Sharing sends exactly the previewed list, only
-- your own unless asked; the receiver asks (or adds from party and guild when chosen, never from a whisper without
-- asking) and refuses forged, oversized, newer, outside-the-group and too-frequent messages. The map shows the kinds
-- chosen, class trainers for your class only unless asked, reports only while chosen. Diagnostics hold no names.
-- The network is the harness's simulation. Whether the game delivers these messages is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

-- 1415 Eastern Kingdoms (a continent), 1429 Elwynn Forest and 1453 Stormwind City (zones), 1455 Ironforge
local MAPS = {
  [1415] = { name = "Eastern Kingdoms", parentMapID = 947, mapType = 2 },
  [1429] = { name = "Elwynn Forest", parentMapID = 1415, mapType = 3 },
  [1453] = { name = "Stormwind City", parentMapID = 1415, mapType = 3 },
  [1455] = { name = "Ironforge", parentMapID = 1415, mapType = 3 },
}
GROUP, GUILD = nil, nil
CLOCK = 1000

local function boot(name, saved, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
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
  c.IsInInstance = function() return c.INSTANCE == true end
  c.UnitClassBase = function() return opts.class or "MAGE" end
  c.NPC = nil   -- { guid, name }
  c.UnitGUID = function(u) if u == "npc" then return c.NPC and c.NPC.guid end return "Player-1-" .. name end
  c.UnitName = function(u) if u == "npc" then return c.NPC and c.NPC.name end return (name:gsub(" .*$", "")) end
  c.MERCHANT = {}   -- item ids for sale
  c.ITEMS = {}      -- [id] = { classID, subClassID }
  c.GetMerchantNumItems = function() return #c.MERCHANT end
  c.GetMerchantItemID = function(i) return c.MERCHANT[i] end
  c.C_Item = { GetItemInfoInstant = function(id) local it = c.ITEMS[id]; if it then return id, "", "", "", 0, it[1], it[2] end end }
  c.CanMerchantRepair = function() return c.REPAIR == true end
  c.C_Trainer = { GetTrainerType = function() return c.TRAINER end }
  c.GetTrainerServiceSkillLine = function() return c.SKILL end
  c.UnitIsPlayer = function() return false end
  c.POPUPS = {}
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function(key, text) table.insert(c.POPUPS, { key = key, text = text, dialog = c.StaticPopupDialogs[key] }) return {} end
  c.InCombatLockdown = function() return false end
  c.IsInRaid = function() return false end
  c.UIErrorsFrame = { AddMessage = function() end }
  c.PRINTED = {}
  c.print = function(s) table.insert(c.PRINTED, tostring(s)) end
  Load(c, { "modules/Interact.lua", "pins/Pins.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua",
    "npcs/Map.lua", "npcs/Share.lua", "diag/Diagnostics.lua", "diag/Npcs.lua" })
  c.TwichUIDB = saved or { modules = { npcMap = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end end
local function printed(c, text)
  for _, line in ipairs(c.PRINTED) do if line:find(text, 1, true) then return true end end
  return false
end

local A, B, C = "Ranulf Ashenvow", "Pal Stonebrook", "Cora Vale"

---------------------------------------------------------------------------
-- 1. Kinds: decided from what was offered, never from words
---------------------------------------------------------------------------
local a = boot(A)
local R = a.TwichUI
local NK, NS, NP, NC, NSH, NMAP = R.NpcKinds, R.NpcStore, R.NpcPrefs, R.NpcCollect, R.NpcShare, R.NpcMap
local function tagset(t) local l = {} for k in pairs(t) do l[#l + 1] = k end table.sort(l) return table.concat(l, ",") end
assert(tagset(NK.Classify({ merchant = true, items = { { 5, 0 }, { 6, 2 }, { 0, 5 }, { 7, 1 } } }).tags) == "ammo,food,reagents,trade")
assert(tagset(NK.Classify({ merchant = true, items = { { 9, 0 }, { 1, 0 }, { 11, 2 } }, repair = true }).tags) == "bags,recipes,repair")
assert(tagset(NK.Classify({ merchant = true, items = { { 4, 1 }, { 2, 7 } } }).tags) == "vendor", "armor and weapons only: another merchant")
assert(tagset(NK.Classify({ merchant = true, items = { { 0, 1 } } }).tags) == "vendor", "a potion isn't food and drink")
assert(tagset(NK.Classify({ merchant = true, items = {}, repair = true }).tags) == "repair", "repair alone is enough")
assert(tagset(NK.Classify({ service = 20 }).tags) == "innkeeper" and tagset(NK.Classify({ service = 8 }).tags) == "banker")
assert(tagset(NK.Classify({ service = 21 }).tags) == "auctioneer" and tagset(NK.Classify({ service = 22 }).tags) == "stable")
assert(tagset(NK.Classify({ service = 6 }).tags) == "flight" and tagset(NK.Classify({ service = 18 }).tags) == "spirit")
assert(tagset(NK.Classify({ service = 11 }).tags) == "guild")
assert(NK.Classify({ service = 5 }) == nil and NK.Classify({ service = 3 }) == nil, "a merchant or gossip window alone says nothing")
local ct = NK.Classify({ trainerType = 0, playerClass = "MAGE" })
assert(tagset(ct.tags) == "classTrainer" and ct.cls == "MAGE")
assert(NK.Classify({ trainerType = 0, playerClass = "DEATHKNIGHT" }) == nil, "a class this list doesn't know is not recorded")
local pt = NK.Classify({ trainerType = 2, profession = "Alchemy" })
assert(tagset(pt.tags) == "profTrainer" and pt.prof == "Alchemy" and pt.cls == nil)
assert(tagset(NK.Classify({ trainerType = 3 }).tags) == "petTrainer")
assert(NK.Primary({ food = true, innkeeper = true }).id == "innkeeper", "an innkeeper wears the innkeeper icon")
assert(NK.Primary({ food = true, innkeeper = true }, function(k) return k ~= "innkeeper" end).id == "food", "unless innkeepers are hidden")
local codes, ids = {}, {}
for _, k in ipairs(NK.LIST) do
  assert(not codes[k.code] and not ids[k.id], "kinds and codes are unique")
  codes[k.code], ids[k.id] = true, true
  assert(#k.code == 2 and k.label and k.noun and k.section and k.icon:find("npc%-" .. k.id, 1, false))
  local f = io.open(ROOT .. "media/textures/npc-" .. k.id .. ".tga", "rb")
  assert(f, "an icon for " .. k.id); f:close()
end

-- creature ids from GUIDs; nothing else is an NPC
assert(NC.CreatureId("Creature-0-3137-0-47-1213-0000123456") == 1213)
assert(NC.CreatureId("Player-1-0ABCDEF") == nil and NC.CreatureId("Pet-0-1-2-3-4-5") == nil)
assert(NC.CreatureId("GameObject-0-1-2-3-4-5") == nil and NC.CreatureId(nil) == nil and NC.CreatureId(7) == nil)

---------------------------------------------------------------------------
-- 2. The list: yours, others', places, spawns, checks
---------------------------------------------------------------------------
local function See(id, map, x, y, tags, extra)
  local seen = { id = id, name = "Npc " .. id, map = map, x = x, y = y, tags = tags }
  for k, v in pairs(extra or {}) do seen[k] = v end
  return NS.Observe(seen)
end
local e1, s1 = See(1213, 1453, 0.50, 0.50, { reagents = true })
assert(e1 and s1 == "new" and e1.own and e1.seen == 1 and e1.x == 5000 and e1.m == 1453)
local e2, s2 = See(1213, 1453, 0.52, 0.50, { repair = true })
assert(rawequal(e1, e2) and s2 == "updated" and e1.seen == 2, "a nearby sighting is the same NPC")
assert(e1.x == 5100 and e1.tags.reagents and e1.tags.repair, "the place averages and what it offered adds up")
local far = See(1213, 1453, 0.10, 0.10, { reagents = true })
assert(far ~= e1, "far away: another spawn of the same creature")
for i = 1, 3 do See(1213, 1453, 0.1 * i + 0.2, 0.9, { reagents = true }) end
local own = NS.Counts()
assert(own == NS.MAX_PER_NPC, "at most four spawns of one creature")
assert(select(2, See(5, 1415, 0.5, 0.5, { banker = true })) == "unknown-map", "a continent is too coarse")
assert(select(2, See(5, 99999, 0.5, 0.5, { banker = true })) == "unknown-map")
assert(select(2, See(5, 1429, 1.5, 0.5, { banker = true })) == "bad-coordinates")
assert(select(2, See(5, 1429, 0.5, 0.5, { banker = "yes" })) == "no-kind" and select(2, See(5, 1429, 0.5, 0.5, { nonsense = true })) == "no-kind")
assert(select(2, NS.Observe({ id = 0, name = "x", map = 1429, x = 0.5, y = 0.5, tags = { banker = true } })) == "bad-id")
local clean = NS.Observe({ id = 77, name = "|cffff0000Red|r |Hitem:1|h[Bob]|h", map = 1429, x = 0.3, y = 0.3, tags = { banker = true } })
assert(clean.n == "Red [Bob]", "names are plain text")
local trainer = NS.Observe({ id = 88, name = "Jennea", map = 1453, x = 0.4, y = 0.4, tags = { classTrainer = true }, cls = "MAGE" })
assert(trainer.cls.MAGE and not trainer.cls.PRIEST)
NS.Observe({ id = 88, name = "Jennea", map = 1453, x = 0.4, y = 0.4, tags = { classTrainer = true }, cls = "PRIEST" })
assert(trainer.cls.MAGE and trainer.cls.PRIEST, "each class that visits adds itself")

-- reports: read as untrusted, never change yours
local good = { i = 501, n = "Wenna", m = 1429, x = 4000, y = 4000, k = { "rg", "rp" } }
local f = assert(NS.ReadWire(good))
assert(f.tags.reagents and f.tags.repair and f.n == "Wenna")
local function Bad(w, code) local r, why = NS.ReadWire(w); assert(r == nil and why == code, tostring(why) .. " vs " .. code) end
Bad("x", "not-a-table")
Bad({ i = -1, n = "a", m = 1429, x = 1, y = 1, k = { "rg" } }, "bad-id")
Bad({ i = 1, n = "|T x|t", m = 1429, x = 1, y = 1, k = { "rg" } }, "no-name")
Bad({ i = 1, n = "a", m = 1429, x = 10001, y = 1, k = { "rg" } }, "bad-coordinates")
Bad({ i = 1, n = "a", m = 1415, x = 1, y = 1, k = { "rg" } }, "unknown-map")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = {} }, "no-kind")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "zz" } }, "unknown-kind")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "rg" }, c = { "MAGE" } }, "bad-class")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "ct" }, c = { "HACKER" } }, "bad-class")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "rg" }, p = "Alchemy" }, "bad-profession")
-- the title under the name: optional, plain text, travels with the entry
local tw = assert(NS.ReadWire({ i = 502, n = "Vendor", m = 1429, x = 1, y = 1, k = { "rg" }, t = "|cffff0000Enchanting Reagents|r" }))
assert(tw.t == "Enchanting Reagents" and NS.Wire({ id = 502, n = "V", m = 1429, x = 1, y = 1, tags = { reagents = true }, t = "Enchanting Reagents" }).t == "Enchanting Reagents")
assert(NS.ReadWire({ i = 502, n = "Vendor", m = 1429, x = 1, y = 1, k = { "rg" } }).t == nil)
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "rg" }, t = "|T x|t" }, "bad-title")
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { "rg" }, t = 5 }, "bad-title")
local long = string.rep("k", 30)
Bad({ i = 1, n = "a", m = 1429, x = 1, y = 1, k = { long } }, "unknown-kind")
local yours = NS.ReadWire({ i = 1213, n = "Renamed", m = 1453, x = 5100, y = 5000, k = { "fd" } })
local preview = NS.PreviewMerge({ f, yours })
assert(preview.new == 1 and preview.yours == 1 and preview.more == 0)
local res = NS.MergeReported({ f, yours })
assert(res.added == 1 and res.yours == 1)
assert(e1.n == "Npc 1213" and not e1.tags.food and e1.rep == 1, "a report never changes an NPC you saw; it counts as a report")
local rep = NS.Near(501, 1429, 4000, 4000)
assert(rep and not rep.own and rep.rep == 1)
NS.MergeReported({ NS.ReadWire({ i = 501, n = "Wenna", m = 1429, x = 4100, y = 4000, k = { "am" } }) })
assert(rep.rep == 2 and rep.tags.ammo and rep.tags.reagents, "another report adds to a report")
-- a visit makes it yours, with what you saw
a.HERE = { map = 1429, x = 0.40, y = 0.40 }
local confirmed, cs = NS.Observe({ id = 501, name = "Wenna", map = 1429, x = 0.40, y = 0.40, tags = { food = true } })
assert(rawequal(confirmed, rep) and cs == "confirmed" and rep.own and rep.tags.food and not rep.tags.ammo, "what you saw replaces what was said")

-- saved, read back after a reload; an unreadable entry is skipped, never erased
table.insert(a.TwichUIDB.npcs.list, { id = "bad", n = "x" })
local count = #NS.Entries()
local saved = a.TwichUIDB
local a2 = boot(A, saved)
assert(#a2.TwichUI.NpcStore.Entries() == count and #saved.npcs.list == count + 1, "the list survives a reload; the bad entry stays")
assert(a2.TwichUI.NpcStore.Snapshot().unreadable == 1)
-- a newer list is read, never written
saved.npcs.v = 99
assert(select(2, a2.TwichUI.NpcStore.Observe({ id = 9, name = "x", map = 1429, x = 0.1, y = 0.1, tags = { banker = true } })) == "newer-store")
assert(a2.TwichUI.NpcStore.Clear("all") == 0 and #saved.npcs.list == count + 1)
saved.npcs.v = 1

-- reports expire; yours don't
local b0 = boot(B, { modules = { npcMap = true } })
local BS = b0.TwichUI.NpcStore
BS.MergeReported({ BS.ReadWire(good) })
b0.TwichUI.NpcStore.Observe({ id = 9, name = "Mine", map = 1429, x = 0.1, y = 0.1, tags = { banker = true } })
for _, e in ipairs(BS.Entries()) do e.at = os.time() - 200 * 86400 end
assert(BS.Expire() == 1)
local o2, r2 = BS.Counts()
assert(o2 == 1 and r2 == 0, "an old report goes; an old visit of yours stays")
-- clearing is scoped
BS.MergeReported({ BS.ReadWire(good) })
assert(BS.Clear("reported") == 1 and select(1, BS.Counts()) == 1)
assert(BS.Clear("all") == 1 and select(1, BS.Counts()) == 0)
-- bounded: reports go first to make room
BS.MAX_ENTRIES = 3
BS.Observe({ id = 21, name = "One", map = 1429, x = 0.1, y = 0.1, tags = { banker = true } })
BS.MergeReported({ BS.ReadWire({ i = 22, n = "Two", m = 1429, x = 2000, y = 2000, k = { "bk" } }) })
BS.Observe({ id = 23, name = "Three", map = 1429, x = 0.3, y = 0.3, tags = { banker = true } })
BS.Observe({ id = 24, name = "Four", map = 1429, x = 0.4, y = 0.4, tags = { banker = true } })
assert(#BS.Entries() == 3 and not BS.Near(22, 1429, 2000, 2000) and BS.Near(21, 1429, 1000, 1000), "the report made room")
local r3 = BS.MergeReported({ BS.ReadWire({ i = 25, n = "Five", m = 1429, x = 5000, y = 5000, k = { "bk" } }) })
assert(r3.refused == 1 and #BS.Entries() == 3, "a report never pushes out one of yours")
BS.MAX_ENTRIES = 3000
BS.Clear("all")

---------------------------------------------------------------------------
-- 3. Collecting from the game's windows
---------------------------------------------------------------------------
local c = boot(C, { modules = { npcMap = true } })
local CS, CC = c.TwichUI.NpcStore, c.TwichUI.NpcCollect
c.HERE = { map = 1453, x = 0.62, y = 0.71 }
c.NPC = { guid = "Creature-0-1-0-1-5500-00001", name = "Reagent Seller" }
c.MERCHANT = { 17020, 17031, 4470 }
c.ITEMS = { [17020] = { 5, 0 }, [17031] = { 5, 0 }, [4470] = { 7, 0 } }
c.FireEvent("MERCHANT_SHOW")
local m = CS.Near(5500, 1453, 6200, 7100)
assert(m and m.own and m.tags.reagents and m.tags.trade and not m.tags.repair and m.n == "Reagent Seller")
c.MERCHANT[#c.MERCHANT + 1] = 2512; c.ITEMS[2512] = { 6, 2 }
FlushTimers()   -- the second read a moment later
assert(m.tags.ammo, "a list that arrives in parts is read again")
assert(m.seen == 1 and m.x == 6200, "reading it again in the same visit is not another visit")
c.FireEvent("MERCHANT_CLOSED")
-- a list not in yet notes nothing; "another merchant" gives way to anything more specific
c.NPC = { guid = "Creature-0-1-0-1-5600-00009", name = "Armorer" }
c.MERCHANT = {}
c.FireEvent("MERCHANT_SHOW")
assert(not CS.Near(5600, 1453, 6200, 7100) and CC.Snapshot().skipped["merchant-empty"] == 1)
c.MERCHANT = { 9001 }; c.ITEMS[9001] = { 4, 1 }
FlushTimers()
local armorer = CS.Near(5600, 1453, 6200, 7100)
assert(armorer and armorer.tags.vendor, "armour only: another merchant")
c.FireEvent("MERCHANT_CLOSED")
c.MERCHANT = { 9001, 2512 }
c.FireEvent("MERCHANT_SHOW")
assert(armorer.tags.ammo and not armorer.tags.vendor and armorer.seen == 2, "now known to sell ammunition")
c.FireEvent("MERCHANT_CLOSED")
-- a trainer, a service
c.NPC = { guid = "Creature-0-1-0-1-331-00002", name = "Maginor Dumas" }
c.TRAINER = 0
c.FireEvent("TRAINER_SHOW")
local t = CS.Near(331, 1453, 6200, 7100)
assert(t and t.tags.classTrainer and t.cls.MAGE)
c.NPC = { guid = "Creature-0-1-0-1-6740-00003", name = "Innkeeper Allison" }
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 20)
assert(CS.Near(6740, 1453, 6200, 7100).tags.innkeeper)
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)   -- the merchant window's own interaction: read at MERCHANT_SHOW
local before = #CS.Entries()
-- not an NPC, inside an instance, nowhere: nothing
c.NPC = { guid = "Player-1-ABC", name = "Someone" }
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
c.NPC = { guid = "Creature-0-1-0-1-2455-00004", name = "Banker" }
c.INSTANCE = true
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
c.INSTANCE = false
c.HERE = nil
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
assert(#CS.Entries() == before, "players, instances and unknown places note nothing")
local snap = CC.Snapshot()
assert(snap.skipped["not-a-creature"] == 1 and snap.skipped.instance == 1 and snap.skipped["no-map"] == 1)
-- off: nothing listens; the probe alone notes nothing
c.TwichUIDB.modules.npcMap = false
CC.Refresh()
c.HERE = { map = 1453, x = 0.2, y = 0.2 }
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
assert(#CS.Entries() == before and not CC.Snapshot().listening)
CC.Probe(true)
c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
assert(#CS.Entries() == before, "the probe only prints")
assert(printed(c, "would be noted as: Banker"), "it says what it would note")
CC.Probe(false)
assert(not CC.Snapshot().listening)
c.TwichUIDB.modules.npcMap = true
CC.Refresh()

---------------------------------------------------------------------------
-- 4. Sharing
---------------------------------------------------------------------------
NET, SENT_LOG, CLIENTS = {}, {}, {}
GROUP = { [A] = true, [B] = true, [C] = true }
GUILD = { [A] = true, [B] = true }
local sa = boot(A, { modules = { npcMap = true } })
local sb = boot(B, { modules = { npcMap = true } })
local sc = boot(C, { modules = { npcMap = true } })
local SA, SB, SC = sa.TwichUI.NpcStore, sb.TwichUI.NpcStore, sc.TwichUI.NpcStore
for i = 1, 160 do SA.Observe({ id = 1000 + i, name = "Vendor " .. i, map = 1453, x = (i % 40) / 40, y = math.floor(i / 40) / 5, tags = { reagents = true } }) end
SA.MergeReported({ SA.ReadWire({ i = 9001, n = "Heard of", m = 1429, x = 100, y = 100, k = { "bk" } }) })
local plan = assert(sa.TwichUI.NpcShare.Plan("party"))
assert(#plan.wires == 160 and plan.own == 160 and plan.reported == 0 and plan.parts == 2, "only your own unless chosen")
assert(sa.TwichUI.NpcShare.Describe(plan):find("160 NPCs you dealt with yourself", 1, true))
sa.TwichUI.NpcPrefs.Set("sendReports", true)
assert(#assert(sa.TwichUI.NpcShare.Plan("party")).wires == 161, "with reports when chosen")
sa.TwichUI.NpcPrefs.Set("sendReports", false)
-- the button path asks first; nothing is sent until accepted
assert(sa.TwichUI.NpcShare.Offer("party"))
assert(#NET == 0 and sa.POPUPS[#sa.POPUPS].key == "TWICHUI_NPC_SEND")
sa.POPUPS[#sa.POPUPS].dialog.OnAccept()
assert(#NET == 3, "an offer and two parts")
settle()
-- B and C are asked; nothing is added before they answer
assert(select(2, SB.Counts()) == 0)
local q = sb.POPUPS[#sb.POPUPS]
assert(q.key == "TWICHUI_NPC_RECEIVE" and q.text:find("160 are new to you", 1, true), q.text)
q.dialog.OnAccept()
local ownB, repB = SB.Counts()
assert(ownB == 0 and repB == 160, "added as reports")
sc.POPUPS[#sc.POPUPS].dialog.OnCancel(nil, nil, "clicked")
assert(select(2, SC.Counts()) == 0, "declined: nothing added")
-- a send right after is refused (one list at a time)
assert(not sa.TwichUI.NpcShare.Send(plan))
-- auto: from the guild without asking; a whisper still asks
CLOCK = CLOCK + 60
sb.TwichUI.NpcPrefs.Set("receive", "auto")
SB.Clear("all")
local nb = #sb.POPUPS
assert(sa.TwichUI.NpcShare.Send(assert(sa.TwichUI.NpcShare.Plan("guild"))))
settle()
assert(select(2, SB.Counts()) == 160 and #sb.POPUPS == nb, "auto from the guild")
assert(#sc.POPUPS == 1, "not in the guild: nothing reaches C")
CLOCK = CLOCK + 60
SB.Clear("all")
assert(sa.TwichUI.NpcShare.Send(assert(sa.TwichUI.NpcShare.Plan("whisper", "Pal Stonebrook"))))
settle()
assert(select(2, SB.Counts()) == 0 and #sb.POPUPS == nb + 1, "a whisper asks even on auto")
sb.POPUPS[#sb.POPUPS].dialog.OnCancel(nil, nil, "clicked")
-- off: ignored
sb.TwichUI.NpcPrefs.Set("receive", "off")
CLOCK = CLOCK + 60
assert(sa.TwichUI.NpcShare.Send(assert(sa.TwichUI.NpcShare.Plan("party"))))
settle()
assert(select(2, SB.Counts()) == 0 and sb.TwichUI.NpcShare.Snapshot().drops["receive-off"] == 3)
sb.TwichUI.NpcPrefs.Set("receive", "ask")
assert(sa.TwichUI.NpcShare.Plan("whisper", A) == nil, "not to yourself")
assert(sa.TwichUI.NpcShare.Plan("nowhere") == nil)

-- forged and broken messages
local LibSerialize, LibDeflate = sa.LibStub("LibSerialize"), sa.LibStub("LibDeflate")
local function Raw(msg) return LibDeflate:EncodeForWoWAddonChannel(LibSerialize:Serialize(msg)) end
local recv = sb._comm["TwichUINpc"]
local function Dropped(code) return sb.TwichUI.NpcShare.Snapshot().drops[code] or 0 end
recv("TwichUINpc", Raw({ v = 2, o = "offer", t = 1, k = 1, n = 1 }), "PARTY", A)
assert(Dropped("newer-protocol") == 1)
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 1, k = 1, n = 1 }), "PARTY", "Not Here")
assert(Dropped("not-member") == 1, "a group message from outside the group")
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 1, k = 99, n = 1 }), "PARTY", A)
assert(Dropped("bad-offer") == 1)
recv("TwichUINpc", Raw({ v = 1, o = "part", t = 5, i = 1, l = {} }), "PARTY", A)
assert(Dropped("no-offer") == 1, "a part without its offer")
recv("TwichUINpc", string.rep("x", 50000), "PARTY", A)
assert(Dropped("too-large") == 1)
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 1, k = 1, n = 1 }), "SAY", A)
assert(Dropped("channel") == 1)
-- a part with bad entries keeps the good ones only; a repeated part is refused
local pops = #sb.POPUPS
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 7, k = 2, n = 3 }), "PARTY", A)
recv("TwichUINpc", Raw({ v = 1, o = "part", t = 7, i = 1, l = { good, { i = 1, n = "bad", m = 1415, x = 1, y = 1, k = { "rg" } } } }), "PARTY", A)
recv("TwichUINpc", Raw({ v = 1, o = "part", t = 7, i = 1, l = { good } }), "PARTY", A)
assert(Dropped("bad-part") == 1)
recv("TwichUINpc", Raw({ v = 1, o = "part", t = 7, i = 2, l = {} }), "PARTY", A)
assert(#sb.POPUPS == pops + 1 and sb.POPUPS[#sb.POPUPS].text:find("sent you 1 NPC from", 1, true), sb.POPUPS[#sb.POPUPS].text)
-- an incomplete transfer is asked about once it times out, saying so
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 8, k = 2, n = 2 }), "PARTY", C)
recv("TwichUINpc", Raw({ v = 1, o = "part", t = 8, i = 1, l = { { i = 777, n = "Late", m = 1429, x = 10, y = 10, k = { "bk" } } } }), "PARTY", C)
sb.POPUPS[#sb.POPUPS].dialog.OnCancel(nil, nil, "clicked")   -- (the earlier question)
RunLongTimers(STAGE or 200)
assert(sb.POPUPS[#sb.POPUPS].text:find("not all of it arrived", 1, true), "partial says so")
-- the rate per sender
local before = Dropped("rate")
for _ = 1, 40 do recv("TwichUINpc", Raw({ v = 1, o = "unknown" }), "WHISPER", "Spam Mer") end
assert(Dropped("rate") > before, "too many from one sender")
-- switched off: nothing is taken in and anything held goes
sb.TwichUIDB.modules.npcMap = false
sb.TwichUI.NpcShare.Refresh()
local rec = sb.TwichUI.NpcShare.Snapshot().received
recv("TwichUINpc", Raw({ v = 1, o = "offer", t = 9, k = 1, n = 1 }), "PARTY", A)
assert(sb.TwichUI.NpcShare.Snapshot().received == rec and sb.TwichUI.NpcShare.Snapshot().held == 0)
sb.TwichUIDB.modules.npcMap = true

-- 4b. Live sharing: one small message per new NPC, all of it opt-in
do
  CLOCK = CLOCK + 120
  local npa, npb, npc = sa.TwichUI.NpcPrefs, sb.TwichUI.NpcPrefs, sc.TwichUI.NpcPrefs
  assert(npa.Get("liveGroup") == false and npa.Get("liveGuild") == false and npb.Get("liveReceive") == false, "all off by default")
  SB.Clear("all"); SC.Clear("all")
  local function Seen(id) return SA.Observe({ id = id, name = "Live " .. id, map = 1453, x = 0.4, y = 0.4, tags = { reagents = true } }) end
  -- nothing chosen: nothing goes
  local function Sent() return sa.TwichUI.NpcShare.Snapshot().liveSent end
  local n0 = Sent()
  Seen(5001); RunLongTimers(30); settle()
  assert(Sent() == n0, "off: nothing sent")
  -- sending on, receiving off: B drops it and says why
  npa.Set("liveGroup", true)
  Seen(5002); RunLongTimers(30); settle()
  assert(Sent() == n0 + 1, "one live message")
  assert(sb.TwichUI.NpcShare.Snapshot().drops["live-off"] == 1 and select(2, SB.Counts()) == 0, "receiver has not chosen it")
  -- receiving on: added quietly as a report, no question, no print
  npb.Set("liveReceive", true); npc.Set("liveReceive", true)
  local pops = #sb.POPUPS
  Seen(5003); RunLongTimers(30); settle()
  local ownB, repB = SB.Counts()
  assert(ownB == 0 and repB == 1 and #sb.POPUPS == pops, "added as a report without asking")
  assert(select(2, SC.Counts()) == 1, "the group's other member too")
  -- a second visit with nothing new is not sent again; something new is
  local n1 = Sent()
  Seen(5003); RunLongTimers(30); settle()
  assert(Sent() == n1, "same NPC, same offer: once")
  SA.Observe({ id = 5003, name = "Live 5003", map = 1453, x = 0.4, y = 0.4, tags = { bags = true } })
  RunLongTimers(30); settle()
  assert(Sent() == n1 + 1, "it offers more now")
  -- guild only reaches the guild (B), not C
  npa.Set("liveGroup", false); npa.Set("liveGuild", true)
  local cBefore = select(2, SC.Counts())
  Seen(5004); RunLongTimers(30); settle()
  assert(select(2, SC.Counts()) == cBefore, "C isn't in the guild")
  assert(select(2, SB.Counts()) == 2, "B is")
  npa.Set("liveGuild", false)
  -- a receiver never takes what it should not: whisper, forgery, bad entries, over the size, a burst
  local recvB = sb._comm["TwichUINpc"]
  local LS, LD = sb.LibStub("LibSerialize"), sb.LibStub("LibDeflate")
  local function Live(msg) return LD:EncodeForWoWAddonChannel(LS:Serialize(msg)) end
  local good = { i = 6001, n = "Good", m = 1453, x = 100, y = 100, k = { "rg" } }
  local function Drops(code) return sb.TwichUI.NpcShare.Snapshot().drops[code] or 0 end
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = { good } }), "WHISPER", A)
  assert(Drops("live-channel") == 1, "never by whisper")
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = { good } }), "PARTY", "Not Here")
  assert(Drops("not-member") >= 1, "a stranger in the group channel")
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = { good, good, good, good, good, good } }), "PARTY", A)
  assert(Drops("bad-live") == 1, "more than five")
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = "x" }), "PARTY", A)
  assert(Drops("bad-live") == 2)
  local before = select(2, SB.Counts())
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = { { i = 1, n = "Bad", m = 1415, x = 1, y = 1, k = { "zz" } }, "junk" } }), "PARTY", A)
  assert(select(2, SB.Counts()) == before, "unreadable entries add nothing")
  recvB("TwichUINpc", Live({ v = 1, o = "live", l = { good } }), "PARTY", A)
  assert(select(2, SB.Counts()) == before + 1)
  -- the per-sender rate for entries
  local rateBefore = Drops("live-rate")
  for i = 1, 12 do
    local l = {}
    for j = 1, 5 do l[j] = { i = 7000 + i * 10 + j, n = "Flood", m = 1453, x = 100 * j, y = 100 * i, k = { "rg" } } end
    recvB("TwichUINpc", Live({ v = 1, o = "live", l = l }), "PARTY", A)
  end
  assert(Drops("live-rate") > rateBefore, "a flood is held back")
  -- lists off does not stop live, live off does not stop lists
  npb.Set("receive", "off")
  CLOCK = CLOCK + 300
  recvB("TwichUINpc", Live({ v = 1, o = "offer", t = 1, k = 1, n = 1 }), "PARTY", A)
  assert(Drops("receive-off") >= 1, "lists are still off")
  npb.Set("receive", "ask")
  -- switched off: pending live work goes and nothing more is queued
  npa.Set("liveGroup", true)
  Seen(5005)
  sa.TwichUIDB.modules.npcMap = false
  sa.TwichUI.NpcShare.Refresh()
  local n2 = Sent()
  RunLongTimers(30); settle()
  assert(Sent() == n2, "switched off: the queued one is not sent")
  sa.TwichUIDB.modules.npcMap = true
  npa.Set("liveGroup", false)
end

---------------------------------------------------------------------------
-- 5. What the map shows
---------------------------------------------------------------------------
local MM, MP = sa.TwichUI.NpcMap, sa.TwichUI.NpcPrefs
local mine = { own = true, tags = { classTrainer = true }, cls = { MAGE = true } }
local other = { own = true, tags = { classTrainer = true }, cls = { PRIEST = true } }
local reported = { tags = { reagents = true } }
local multi = { own = true, tags = { food = true, innkeeper = true } }
assert(MM.ShownKind(mine).id == "classTrainer" and MM.ShownKind(other) == nil, "your class's trainers only")
MP.Set("trainerClass", "all")
assert(MM.ShownKind(other).id == "classTrainer")
assert(MM.ShownKind(reported).id == "reagents")
MP.Set("reports", false)
assert(MM.ShownKind(reported) == nil, "reports hidden when chosen")
assert(MM.ShownKind(multi).id == "innkeeper")
MP.Set("show.innkeeper", false)
assert(MM.ShownKind(multi).id == "food", "a hidden kind gives way to the next")
MP.Set("show.food", false)
assert(MM.ShownKind(multi) == nil)
assert(not MP.Set("show.nonsense", true) and not MP.Set("iconSize", 1000) and not MP.Set("receive", "always"))
MP.Reset("all")
assert(MP.Get("trainerClass") == "mine" and MP.Get("reports") == true and MP.Shown("innkeeper"))
assert(table.concat(MM.KindLines({ tags = { classTrainer = true, food = true }, cls = { MAGE = true, PRIEST = true } }), "|") == "Class trainer (Mage, Priest)|Sells food and drink")
assert(MM.KindLines({ tags = { profTrainer = true }, prof = "Alchemy" })[1] == "Profession trainer (Alchemy)")
assert(MM.Provenance({ own = true, seen = 3, at = 0 }):find("3 visits", 1, true))
assert(MM.Provenance({ rep = 2 }):find("not seen by you", 1, true))

---------------------------------------------------------------------------
-- 6. Diagnostics: counts and codes, never names
---------------------------------------------------------------------------
local report = sa.TwichUI.Diag.Build()
assert(report:find("Vendors and trainers", 1, true))
assert(not report:find("Vendor 1", 1, true) and not report:find("Pal Stonebrook", 1, true) and not report:find("Heard of", 1, true),
  "no NPC or player names in the report")

print("PASSED")
