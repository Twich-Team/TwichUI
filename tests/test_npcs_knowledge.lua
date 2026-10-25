-- World Knowledge (npcs/Knowledge.lua): the list's entries as rows that are filtered and ordered without touching what is
-- saved; how each entry became known is only what it records (yours, reported, or not recorded); identical names stay
-- apart; filters combine; deleting a chosen set, a selected record or one area removes exactly those entries (a set
-- read when asked is not widened by what arrives later; an NPC in other areas keeps those); the map and the settings
-- hear of it once; sending goes through the same question and protocol as the whole list, for the entries chosen,
-- and a chosen destination that isn't available is refused. The network is the harness's simulation.
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
    "npcs/Map.lua", "npcs/Share.lua", "npcs/Knowledge.lua", "diag/Diagnostics.lua", "diag/Npcs.lua" })
  c.TwichUIDB = saved or { modules = { npcMap = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end end
local function Check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end end
local A, B = "Ranulf Ashenvow", "Pal Stonebrook"
NET, SENT_LOG, CLIENTS = {}, {}, {}
GROUP, GUILD = { [A] = true, [B] = true }, { [A] = true, [B] = true }

---------------------------------------------------------------------------
-- 1. An empty database
---------------------------------------------------------------------------
local a = boot(A, { modules = { npcMap = true } })
local R = a.TwichUI
local NS, KN, NSH = R.NpcStore, R.NpcKnowledge, R.NpcShare
Check(KN and #KN.Rows() == 0 and KN.Total() == 0 and #KN.Filter({ text = "x" }) == 0, "empty: no rows, no matches")
Check(#KN.Zones() == 0 and #KN.Kinds() == 0 and #KN.AreaEntries(1453) == 0, "empty: no areas or roles")
Check(NS.ForgetMany({}) == 0 and NS.ForgetMany(nil) == 0, "nothing to forget is zero, not an error")
Check(KN.Active({ text = "  " }) == false and KN.Active({ source = "any" }) == false and KN.Active({ map = 1 }), "what counts as a filter")

---------------------------------------------------------------------------
-- 2. A list: yours, others', legacy, identical names, several places and roles
---------------------------------------------------------------------------
local function See(id, name, map, x, y, tags, extra)
  local seen = { id = id, name = name, map = map, x = x, y = y, tags = tags }
  for k, v in pairs(extra or {}) do seen[k] = v end
  return assert(NS.Observe(seen))
end
local function Heard(id, name, map, x, y, kinds, more)
  local w = { i = id, n = name, m = map, x = x, y = y, k = kinds }
  for k, v in pairs(more or {}) do w[k] = v end
  local f = assert(NS.ReadWire(w))
  return NS.MergeReported({ f })
end
local inn = See(100, "Innkeeper Farley", 1429, 0.40, 0.60, { innkeeper = true, food = true })
local inn2 = See(100, "Innkeeper Farley", 1429, 0.40, 0.60, { innkeeper = true, food = true }, { again = true })
See(101, "Brog", 1453, 0.20, 0.20, { reagents = true })
See(102, "Brog", 1455, 0.30, 0.30, { repair = true })            -- identical name, another NPC and area
See(100, "Innkeeper Farley", 1455, 0.80, 0.80, { innkeeper = true })   -- the same creature in another area
See(103, "Archmage Adler", 1453, 0.50, 0.50, { classTrainer = true }, { cls = "MAGE" })
See(104, "Alchemist Ana", 1453, 0.55, 0.50, { profTrainer = true }, { prof = "Alchemy", title = "Alchemy Trainer" })
Heard(200, "Wandering Wend", 1429, 100, 100, { "bk" })
Heard(201, "Zora", 1453, 200, 200, { "au" })
Heard(201, "Zora", 1453, 200, 200, { "au" })   -- reported twice
-- a legacy entry: neither seen nor counted as reported (written by hand, as an older version might have)
local db = a.TwichUIDB.npcs
db.list[#db.list + 1] = { id = 300, n = "Old Orrin", m = 1455, x = 5000, y = 5000, tags = { banker = true } }
NS.Invalidate()
local total = KN.Total()
Check(total == 9, "nine entries, got " .. total)

-- order: by name, then area, deterministic; identical names stay two rows
local names = {}
for _, row in ipairs(KN.Rows()) do names[#names + 1] = row.name .. "@" .. row.zone end
Check(names[1]:find("^Alchemist Ana") and names[#names]:find("^Zora"), "ordered by name: " .. table.concat(names, "; "))
local brogs = KN.Filter({ text = "brog" })
Check(#brogs == 2 and brogs[1].zone ~= brogs[2].zone and brogs[1].e.id ~= brogs[2].e.id, "identical names are two rows, apart by area and id")
local again = KN.Filter({})
for i, row in ipairs(KN.Rows()) do Check(again[i] == row, "unfiltered is the same order") end

-- missing fields don't break rows
local old = KN.Filter({ text = "orrin" })[1]
Check(old and old.source == "unknown" and KN.SourceWord(old) == "Not recorded", "a legacy entry has no invented source")
local od = KN.Details(old)
Check(table.concat(od.sources, " "):find("not recorded", 1, true) and not table.concat(od.sources, " "):find("[Ss]een by you"), "and says so")

---------------------------------------------------------------------------
-- 3. Provenance: only what the entries record
---------------------------------------------------------------------------
local function Source(name) return KN.Filter({ text = name })[1] end
Check(Source("farley").source == "mine" and KN.SourceWord(Source("wend")) == "Others" and Source("wend").source == "others", "yours / reported")
local zd = KN.Details(Source("zora"))
Check(table.concat(zd.sources, " "):find("2 times", 1, true), "reported twice says twice: " .. table.concat(zd.sources, " "))
Check(table.concat(zd.sources, " "):find("isn't kept", 1, true), "and that the sender and channel aren't kept")
-- a report of one you saw is yours, plus the count (not a new source)
Heard(101, "Brog", 1453, 2000, 2000, { "rg" })
local bd = KN.Details(Source("brog") == nil and brogs[1] or KN.Filter({ text = "brog", map = 1453 })[1])
Check(table.concat(bd.sources, " "):find("Seen by you", 1, true) and table.concat(bd.sources, " "):find("Also reported", 1, true), "yours and also reported: " .. table.concat(bd.sources, " "))
Check(KN.Filter({ text = "brog", map = 1453 })[1].source == "mine", "still yours")
-- timestamps: only ones that exist
local fresh = See(105, "Fresh", 1453, 0.7, 0.7, { trade = true })
fresh.at = nil
NS.Invalidate()
local fd = KN.Details(KN.Filter({ text = "fresh" })[1])
Check(not table.concat(fd.sources, " "):find("last saw it on", 1, true), "no date is invented")
Check(table.concat(KN.Details(Source("zora")).sources, " "):find("Last reported on", 1, true), "a report has its date")

---------------------------------------------------------------------------
-- 4. Filters combine and never change what is saved
---------------------------------------------------------------------------
local listSize = #db.list
Check(#KN.Filter({ text = "farley" }) == 2, "text finds by name")
Check(#KN.Filter({ text = "farley", map = 1429 }) == 1 and #KN.Filter({ text = "farley", map = 1455 }) == 1, "text and area")
Check(#KN.Filter({ text = "FARLEY inn" }) == 2 and #KN.Filter({ text = "inn farley" }) == 2, "every word, any order, any case")
Check(#KN.Filter({ text = "alchemy" }) == 1, "text matches the profession and the title")
Check(#KN.Filter({ text = "elwynn" }) >= 2, "text matches the area name")
Check(#KN.Filter({ kind = "innkeeper" }) == 2 and #KN.Filter({ kind = "innkeeper", map = 1455 }) == 1, "role and area")
Check(#KN.Filter({ kind = "innkeeper", source = "others" }) == 0, "role and source: nothing matches")
Check(#KN.Filter({ text = "zzz-no-such" }) == 0, "a search with no match is empty")
Check(#KN.Filter({ source = "others" }) == 2 and #KN.Filter({ source = "unknown" }) == 1, "sources")
Check(#KN.Filter({ source = "mine" }) == 7 and #KN.Filter({ source = "any" }) == KN.Total(), "yours is seven; any is everything")
Check(KN.Describe({ text = " inn ", map = 1429, kind = "innkeeper", source = "mine" }) == '"inn", in Elwynn Forest, Innkeeper, Seen by you', KN.Describe({ text = " inn ", map = 1429, kind = "innkeeper", source = "mine" }))
Check(KN.Describe({}) == "no filters", "no filters says so")
Check(#db.list == listSize, "filtering never changes the saved list")
local zones = KN.Zones()
Check(#zones == 3 and zones[1].name == "Elwynn Forest", "areas, by name, with counts")
local kinds = KN.Kinds()
Check(kinds[1].id == "classTrainer", "roles in the settings' order")

---------------------------------------------------------------------------
-- 5. Deleting: a record, a set, an area
---------------------------------------------------------------------------
local changes = 0
NS.OnChange(function() changes = changes + 1 end)
-- one record: only it, though the same creature stands elsewhere and another NPC has its name
local countBefore = KN.Total()
local farleyElwynn = KN.Filter({ text = "farley", map = 1429 })[1].e
Check(KN.Forget({ farleyElwynn }) == 1 and changes == 1, "one record, one notification")
Check(#KN.Filter({ text = "farley" }) == 1 and KN.Filter({ text = "farley" })[1].zone == "Ironforge", "its other place stays")
Check(#KN.Filter({ text = "brog" }) == 2, "and so does another NPC's name")
Check(KN.Forget({ farleyElwynn }) == 0 and changes == 1, "forgetting it again is zero and tells nobody")
Check(KN.Total() == countBefore - 1, "the rows follow")

-- a set read when asked is not widened by what arrives later
local set = KN.Entries(KN.Filter({ map = 1453 }))
local inSet = #set
See(106, "Latecomer", 1453, 0.9, 0.9, { food = true })
changes = 0
Check(KN.Forget(set) == inSet and changes == 1, "exactly the confirmed set went, with one notification")
Check(#KN.Filter({ text = "latecomer" }) == 1, "what arrived afterwards stayed")
Check(#KN.AreaEntries(1453) == 1, "only it is left in that area")

-- an area: only that map's entries, whatever the filters
local before2 = KN.Total()
local area = KN.AreaEntries(1455)
Check(#area == 3 and NS.Valid(area[1]), "Ironforge has three")
Check(KN.Forget(area) == 3, "cleared")
Check(#KN.AreaEntries(1455) == 0 and #KN.Filter({ text = "farley" }) == 0, "none left there")
Check(KN.Total() == before2 - 3 and #KN.Filter({ map = 1429 }) == 1 and #KN.Filter({ map = 1453 }) == 1, "other areas untouched")
Check(#KN.Zones() == 2, "the area is gone from the area list")
-- unrelated data and settings are left alone
Check(a.TwichUIDB.modules.npcMap == true, "settings untouched")

-- a newer store is never written to
a.TwichUIDB.npcs.v = 99
NS.Invalidate()
Check(KN.Forget(KN.Entries(KN.Filter({}))) == 0, "a store from a newer version is read, not written")
a.TwichUIDB.npcs.v = 1
NS.Invalidate()

---------------------------------------------------------------------------
-- 6. Sending: the chosen entries, the same question, the same protocol
---------------------------------------------------------------------------
NET, SENT_LOG, CLIENTS = {}, {}, {}
local sa = boot(A, { modules = { npcMap = true } })
local sb = boot(B, { modules = { npcMap = true } })
local RA, RB = sa.TwichUI, sb.TwichUI
for i = 1, 5 do RA.NpcStore.Observe({ id = 500 + i, name = "Mine " .. i, map = 1453, x = i / 10, y = 0.5, tags = { reagents = true } }) end
RA.NpcStore.MergeReported({ RA.NpcStore.ReadWire({ i = 600, n = "Theirs", m = 1429, x = 100, y = 100, k = { "bk" } }) })
local KA = RA.NpcKnowledge
local mine3 = KA.Entries(KA.Filter({ text = "mine 3" }))
Check(#mine3 == 1, "one record chosen")
Check(KA.Share(mine3, "party", "Mine 3"), "offered to the group")
local q = sa.POPUPS[#sa.POPUPS]
Check(q.key == "TWICHUI_NPC_SEND" and q.text:find("Mine 3 (1 NPC you dealt with yourself)", 1, true), q.text)
Check(#NET == 0, "nothing sent before the question is answered")
q.dialog.OnAccept()
Check(#NET == 2, "an offer and one part: " .. #NET)
settle()
local qb = sb.POPUPS[#sb.POPUPS]
Check(qb and qb.key == "TWICHUI_NPC_RECEIVE" and qb.text:find("1 NPC", 1, true), qb and qb.text)
qb.dialog.OnAccept()
local _, repB = RB.NpcStore.Counts()
Check(repB == 1, "the receiver got exactly the one record")
-- a record that is only a report goes when chosen, whatever 'also send what others sent you' says
CLOCK = CLOCK + 60
local theirs = KA.Entries(KA.Filter({ text = "theirs" }))
local plan = assert(RA.NpcShare.Plan("party", nil, theirs, "Theirs"))
Check(#plan.wires == 1 and plan.reported == 1 and RA.NpcShare.Describe(plan):find("others sent you", 1, true), "a chosen report is sent, and the question says it is one")
-- the results of a filter
local shown = KA.Entries(KA.Filter({ source = "mine" }))
local plan2 = assert(RA.NpcShare.Plan("party", nil, shown, "the 5 records shown"))
Check(#plan2.wires == 5 and plan2.own == 5 and RA.NpcShare.Describe(plan2):find("the 5 records shown", 1, true), "the filtered set, named")
-- the whole-list plan is unchanged
local whole = assert(RA.NpcShare.Plan("party"))
Check(#whole.wires == 5 and not whole.scope and not RA.NpcShare.Describe(whole):find("(", 1, true), "the whole list keeps its wording")
-- an entry forgotten while the question was open is not sent
local gone = KA.Entries(KA.Filter({ text = "mine 1" }))
RA.NpcStore.ForgetMany(gone)
Check(not RA.NpcShare.Plan("party", nil, gone, "Mine 1"), "nothing left to send")
-- destinations that aren't available
GROUP, GUILD = {}, {}
Check(KA.Unavailable("party") and KA.Unavailable("guild") and not KA.Unavailable("whisper"), "no group, no guild: refused with a reason; a whisper needs neither")
sa.IsInGroup = function() return false end
sa.IsInGuild = function() return false end
Check(not RA.NpcShare.Plan("party", nil, shown, "x") and not RA.NpcShare.Plan("guild", nil, shown, "x"), "and the plan refuses too")
local pops = #sa.POPUPS
Check(KA.Share(shown, "party", "x") == false and #sa.POPUPS == pops, "no question for a destination that can't be used")
-- a whisper asks for a name, then the same question
sa.IsInGroup = nil
KA.Share(shown, "whisper", "the 4 records shown")
local ask = sa.POPUPS[#sa.POPUPS]
Check(ask.key == "TWICHUI_NPC_SEND_TO", "a whisper asks who first")
-- feature off: refused
RA:SetEnabled("npcMap", false)
Check(KA.Unavailable("party"), "off: every destination says so")

print("PASSED")
