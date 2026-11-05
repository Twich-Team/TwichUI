-- Guild Locations, the core (guildloc/State.lua, Roster.lua, Comm.lua): the policy wording, the account-wide choice and how it
-- reads when missing, malformed or held, the epochs, persistence placement (profiles, sharing, backups), the message and its
-- strict reading, roster identity, the receiver's epoch rules and caps, the send schedule (movement, heartbeat, jitter), the
-- transport gate against the bundled ChatThrottleLib (C_ChatInfo is the mock), withdrawals (ordering, reload while off, stale
-- callbacks), rapid state changes, and cleanup. The network, the clock and the map are mocks: the bundled AceComm and
-- ChatThrottleLib are the real ones, driven through C_ChatInfo and CHAT_MSG_ADDON. Whether the game delivers these messages,
-- the roster's return values and what the throttle really does are for the game (docs/guild-locations.md).
--   1  policy wording      2  the choice          3  epochs             4  persistence placement
--   5  the message         6  receiving           7  caps and expiry    8  sending: schedule
--   9  the transport       10 withdrawals         11 rapid changes      12 guild changes and cleanup
REAL_COMM = true
dofile(TESTS .. "harness.lua")

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. tostring(msg), 2) end
end
local function Section(s) print("-- " .. s) end

---------------------------------------------------------------------------
-- A virtual clock; every client's C_Timer and GetTime run on it
---------------------------------------------------------------------------
CLOCK = 1000
local T0 = 1700000000
local queue, qseq = {}, 0
local function After(d, fn) qseq = qseq + 1; queue[#queue + 1] = { at = CLOCK + d, fn = fn, seq = qseq } end
local function Advance(sec, step)
  local target = CLOCK + sec
  while true do
    local best, bi
    for i, e in ipairs(queue) do
      if e.at <= target and (not best or e.at < best.at or (e.at == best.at and e.seq < best.seq)) then best, bi = e, i end
    end
    if not best then break end
    table.remove(queue, bi)
    if best.at > CLOCK then CLOCK = best.at end
    best.fn()
  end
  CLOCK = target
end

local MAPS = {
  [1415] = { name = "Eastern Kingdoms", parentMapID = 947, mapType = 2 },
  [1429] = { name = "Elwynn Forest", parentMapID = 1415, mapType = 3 },
  [1453] = { name = "Stormwind City", parentMapID = 1415, mapType = 3 },
}
GUILD, GUILDNAME = {}, "The Guild"

local function copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local t = {}; seen[v] = t
  for k, x in pairs(v) do t[copy(k, seen)] = copy(x, seen) end
  return t
end

local function Boot(name, saved, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.name = name
  c.C_Timer = { After = After }
  c.GetTime = function() return CLOCK end
  c.time = function() return c.CLOCK_OFF or (T0 + math.floor(CLOCK)) end
  c.HERE = opts.here == nil and { map = 1429, x = 0.5, y = 0.5 } or opts.here or nil
  c.C_Map = {
    GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parentMapID, mapType = m.mapType } or nil end,
    GetBestMapForUnit = function() return c.HERE and c.HERE.map end,
    GetPlayerMapPosition = function(map)
      local h = c.HERE
      if not h or h.map ~= map then return nil end
      return { GetXY = function() return h.x, h.y end }
    end,
  }
  if opts.yards then   -- a continent 1000 yards across: 0.01 of a map is 10 yards
    c.CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
    c.C_Map.GetWorldPosFromMapPos = function(map, v) local x, y = v:GetXY(); return 1, { GetXY = function() return x * 1000, y * 1000 end } end
  end
  c.IsInGuild = function() return GUILD[name] ~= nil end
  c.GetGuildInfo = function() if GUILD[name] ~= nil then return GUILDNAME end end
  c.EXTRA = {}
  c.GetGuildRosterInfo = function(i)
    local list = {}
    for k in pairs(GUILD) do list[#list + 1] = k end
    table.sort(list)
    local k = list[i]
    if k then local e = c.EXTRA[k] or {}; return k, "", 0, e.level, "", "", "", "", GUILD[k], "", e.class end
  end
  c.ASKS = 0
  c.C_GuildInfo = { GuildRoster = function() c.ASKS = c.ASKS + 1 end }
  c.WIRE, c.LOG, c.RESULT, c.LOCK = {}, {}, 0, false
  c.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    InChatMessagingLockdown = function() return c.LOCK end,
    SendAddonMessage = function(prefix, text, dist)
      local ctl = c.ChatThrottleLib
      if c.REFILL ~= false and ctl.avail < 400 then ctl.avail = 400 end
      c.LOG[#c.LOG + 1] = { at = CLOCK, text = text, result = c.RESULT }
      if c.RESULT == 0 then c.WIRE[#c.WIRE + 1] = { prefix = prefix, text = text, dist = dist, at = CLOCK } end
      if c.SENDHOOK then c.SENDHOOK(text) end
      return c.RESULT
    end,
  }
  c.UnitClassBase = function() return "MAGE" end
  for _, f in ipairs({ "pins/Pins.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Search.lua", "guildloc/State.lua", "guildloc/Roster.lua",
    "guildloc/Comm.lua", "diag/Diagnostics.lua", "diag/GuildLoc.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  -- the real AceComm, with its sends counted by priority
  local AceComm = c.LibStub("AceComm-3.0")
  c.PRIOS = {}
  local real = AceComm.SendCommMessage
  AceComm.SendCommMessage = function(self, prefix, text, dist, target, prio, cb, arg)
    c.PRIOS[#c.PRIOS + 1] = { text = text, prio = prio }
    return real(self, prefix, text, dist, target, prio, cb, arg)
  end
  c.LOCK = opts.lock or false
  c.TwichUIDB = saved or {}
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  c.ChatThrottleLib.avail = 400   -- entering the world empties the library; the mock tops it up after each send (REFILL)
  c.GL, c.R = c.TwichUI.GuildLoc, c.TwichUI
  return c
end

-- lets this client's ChatThrottleLib release what it queued (only this client's: others may be sabotaged on purpose)
local function Despool(c)
  local ctl = c.ChatThrottleLib
  for _ = 1, 20 do ctl.avail = math.max(ctl.avail, 400); ctl.OnUpdate(ctl.Frame, 0.2) end
end
local function Move(c, x, y, map) c.HERE = { map = map or (c.HERE and c.HERE.map) or 1429, x = x, y = y } end

-- everything c has put on the wire since the last call, delivered to the others
local function Deliver(from, ...)
  local wire = from.WIRE; from.WIRE = {}
  for _, m in ipairs(wire) do
    for _, rc in ipairs({ ... }) do rc.FireEvent("CHAT_MSG_ADDON", m.prefix, m.text, m.dist, from.name) end
  end
  return wire
end
local function Kinds(wire)
  local p, w = 0, 0
  for _, m in ipairs(wire) do if m.text:find("^1:p:") then p = p + 1 elseif m.text:find("^1:w:") then w = w + 1 end end
  return p, w
end
local function EpochOf(text) return tonumber(text:match("^1:%a:(%d+)")) end
local SPACED = false   -- true: four seconds before each message, so the sender's rate never gets in the way
local function Msg(c, sender, text, dist)
  if SPACED then Advance(4) end
  c.GL.OnMessage("TwichUIGuild", text, dist or "GUILD", sender)
end
local function P(e, n, map, x, y) return ("1:p:%d:%d:%d:%d:%d"):format(e, n, map or 1429, x or 5000, y or 5000) end
local function W(e) return ("1:w:%d"):format(e) end

local A, B = "Alice Stone", "Bob Reeve"
local function Fresh(names)
  GUILD = {}
  for _, n in ipairs(names or { A, B, "Cara Dunn" }) do GUILD[n] = true end
  GUILDNAME = "The Guild"
end

---------------------------------------------------------------------------
Section("1 policy wording")
do
  local function Read(p) local f = assert(io.open(REPO .. p)); local s = f:read("*a"); f:close(); return s end
  local claude, rules, dev = Read("CLAUDE.md"), Read(".clinerules"), Read("docs/dev-rules.md")
  Check(claude:find("Never broadcast Chronicle feedback or Chronicle data", 1, true), "CLAUDE.md keeps the Chronicle prohibition")
  Check(claude:find("Guild Locations (`docs/guild-locations.md`) may default on and send the local player's current map position over the GUILD addon channel only", 1, true), "CLAUDE.md names the one exception")
  Check(claude:find("party pins, map pings, NPC lists", 1, true) and claude:find("not affected", 1, true), "party features are not contradicted")
  Check(not claude:find("Never broadcast Chronicle feedback or location", 1, true), "the blanket sentence is gone")
  Check(dev:find("sole exception is Guild Locations", 1, true) and dev:find("Chronicle prohibition below is unchanged", 1, true), "dev-rules names it")
  Check(dev:find("Never broadcast Chronicle feedback to Party, Guild or public chat", 1, true), "the Chronicle rule is untouched")
  Check(rules:find("The only exception is Guild Locations", 1, true) and rules:find("keep their own rules", 1, true), ".clinerules agrees")
end

---------------------------------------------------------------------------
Section("2 the choice: missing, malformed, held, outside a guild")
do
  Fresh({})   -- no guild at all
  local c = Boot(A)
  local GL = c.GL
  Check(GL.State() == "sharing" and GL.Interval() == 15, "a missing record is the default")
  Check(c.TwichUIDB.guildLoc == nil or c.TwichUIDB.guildLoc.state == nil, "the default is not written as a choice")
  -- a record with no state is still missing
  local c2 = Boot(A, { guildLoc = { interval = 30 } })
  Check(c2.GL.State() == "sharing" and c2.GL.Interval() == 30, "a record without a state is the default state")
  -- present but unusable reads as invisible and is not rewritten
  for _, bad in ipairs({ "x", 5, true, false }) do
    local cb = Boot(A, { guildLoc = bad })
    local st, why = cb.GL.State()
    Check(st == "invisible" and why == "bad-record", "a record that is not a table reads invisible: " .. tostring(bad))
    Advance(120)
    Check(cb.TwichUIDB.guildLoc == bad, "...and is not rewritten")
  end
  for _, bad in ipairs({ "Sharing", "", 5, false, true, {} }) do
    local cb = Boot(A, { guildLoc = { state = bad, interval = 7, lastEpoch = 1 } })
    local st, why = cb.GL.State()
    Check(st == "invisible" and why == "bad-state", "an unusable state reads invisible: " .. tostring(bad))
    Check(cb.GL.Interval() == 15, "an interval that is not offered reads as the default")
    Check(cb.TwichUIDB.guildLoc.state == bad, "not rewritten")
  end
  Check(Boot(A, { guildLoc = { state = "off" } }).GL.State() == "off", "off is a state")
  -- held: a newer schema is set aside; the feature is inactive and writes nothing
  local stored = { schema = 99, guildLoc = { state = "sharing" } }
  local ch = Boot(A, stored)
  Check(ch.R.Persist.IsHeld("TwichUIDB"), "the newer save is held")
  local st, why = ch.GL.State()
  Check(st == "off" and why == "held", "held reads as off")
  local ok, reason = ch.GL.SetState("invisible")
  Check(ok == false and reason == "held", "a held save takes no choice")
  Check(ch.GL.SetInterval(30) == false and ch.GL.NextEpoch() == nil, "...nor an interval or an epoch")
  Check(stored.guildLoc.state == "sharing" and stored.guildLoc.lastEpoch == nil and stored.guildLoc.wp == nil, "the held data is untouched")
  Check(ch.GL.Snapshot().events == 0, "nothing listens while held")
  -- outside a guild a choice can still be made and saved
  local co = Boot(A)
  Check(co.GL.SetState("invisible") and co.TwichUIDB.guildLoc.state == "invisible", "invisible can be saved outside a guild")
  Check(co.GL.SetState("sharing") and co.TwichUIDB.guildLoc.state == "sharing", "...and sharing")
  Check(co.GL.SetState("off") and co.GL.State() == "off", "...and off")
  Check(co.GL.SetState("bogus") == false and co.GL.SetState(nil) == false and co.GL.State() == "off", "an unknown state is refused")
  Check(co.GL.Toggle() == false and co.GL.State() == "off", "a toggle never leaves off")
  co.GL.SetState("sharing")
  co.GL.Toggle(); Check(co.GL.State() == "invisible", "toggle: sharing to invisible")
  co.GL.Toggle(); Check(co.GL.State() == "sharing", "toggle: invisible to sharing")
  Check(co.GL.SetInterval(10) and co.GL.Interval() == 10, "an offered interval")
  Check(co.GL.SetInterval(20) == false and co.GL.SetInterval("15") == false and co.GL.SetInterval(0) == false and co.GL.Interval() == 10, "others refused")
  -- a choice replaces an unusable record; that is the only way
  local cr = Boot(A, { guildLoc = "junk" })
  Check(cr.GL.SetState("invisible") and type(cr.TwichUIDB.guildLoc) == "table" and cr.GL.State() == "invisible", "the player's choice replaces junk")
  -- listeners hear a change once
  local heard = {}
  co.GL.OnChange(function(kind, new, old) heard[#heard + 1] = kind .. ":" .. tostring(old) .. ">" .. tostring(new) end)
  co.GL.SetState("invisible"); co.GL.SetState("invisible")
  Check(#heard == 1 and heard[1] == "state:sharing>invisible", "one notice per change")
end

---------------------------------------------------------------------------
Section("3 epochs")
do
  Fresh({})
  local c = Boot(A)
  local GL = c.GL
  local e1, e2, e3 = GL.NextEpoch(), GL.NextEpoch(), GL.NextEpoch()
  local now0 = T0 + math.floor(CLOCK)
  Check(e1 == now0 and e2 == e1 + 1 and e3 == e2 + 1, "several in one second still rise")
  Check(c.TwichUIDB.guildLoc.lastEpoch == e3, "saved before use")
  Advance(5)
  Check(GL.NextEpoch() == T0 + math.floor(CLOCK), "the clock wins once it is ahead")
  c.TwichUIDB.guildLoc.lastEpoch = T0 + 90000
  Check(GL.NextEpoch() == T0 + 90001, "a saved value ahead of the clock is respected")
  for _, bad in ipairs({ -1, 1.5, "7", true, 0 / 0, 2 ^ 32, 2 ^ 53 }) do
    c.TwichUIDB.guildLoc.lastEpoch = bad
    local e, why = GL.NextEpoch()
    Check(e == nil and why == "bad-epoch", "an unusable saved epoch gives none: " .. tostring(bad))
    Check(c.TwichUIDB.guildLoc.lastEpoch == bad or bad ~= bad, "...and is not rewritten")
  end
  c.TwichUIDB.guildLoc.lastEpoch = GL.EPOCH_MAX
  local e, why = GL.NextEpoch()
  Check(e == nil and why == "epoch-range", "at the top it fails rather than wraps")
  c.TwichUIDB.guildLoc.lastEpoch = GL.EPOCH_MAX - 1
  Check(GL.NextEpoch() == GL.EPOCH_MAX, "the last valid one is given once")
  Check(GL.NextEpoch() == nil, "...and then none")
  c.TwichUIDB.guildLoc.lastEpoch = nil
  c.CLOCK_OFF = 5
  e, why = GL.NextEpoch()
  Check(e == nil and why == "epoch-range", "a clock that is not telling the time gives none")
  c.TwichUIDB.guildLoc = "junk"
  e, why = GL.NextEpoch()
  Check(e == nil and why == "bad-record" and c.TwichUIDB.guildLoc == "junk", "an unusable record is not written to")
  -- no valid epoch: no session, nothing sent, receiving still works
  Fresh()
  local s = Boot(A, { guildLoc = { lastEpoch = -3 } })
  local r = Boot(B)
  Advance(200)
  Check(#s.LOG == 0 and s.GL.Snapshot().noSend == "bad-epoch" and not s.GL.Snapshot().session, "no epoch: nothing sent")
  Msg(s, B, P(T0 + 500, 1)); Check(s.GL.Peek(B), "...but still receiving")
  Check(s.TwichUIDB.guildLoc.lastEpoch == -3, "...and nothing rewritten")
end

---------------------------------------------------------------------------
Section("4 persistence: profiles, sharing, backups")
do
  Fresh({})
  local saved = { guildLoc = { state = "invisible", interval = 30, lastEpoch = T0 + 77 } }
  local c = Boot(A, saved)
  local R = c.R
  Check(R.Restore.OWN_LEFT_OUT.guildLoc and #R.Restore.OWN_LEFT_OUT.guildLoc > 20, "backups leave it out, with a reason")
  Check(R.TwichConfig.LOCAL.guildLoc == "network", "sharing keeps it local")
  local function Same() return c.TwichUIDB.guildLoc.state == "invisible" and c.TwichUIDB.guildLoc.interval == 30 and c.TwichUIDB.guildLoc.lastEpoch == T0 + 77 end
  local PF = R.Profiles
  Check(PF.Create("Other"), "a new profile")
  Check(Same(), "...leaves the choice")
  Check(PF.Switch("Default") or true, "switch")
  PF.CopyFrom("Other"); Check(Same(), "copying a profile leaves it")
  PF.Reset(); Check(Same(), "resetting a profile leaves it")
  -- an import of someone else's settings
  local entry = R.TwichConfig.Build({ all = true })
  if entry then
    local ok = R.TwichConfig.Apply(entry, { newProfile = true })
    Check(Same(), "applying a shared setup leaves it" .. (ok and "" or " (not applied)"))
  end
  -- a backup holds nothing of it, and restoring one changes nothing
  local st, point = R.Restore:Create("snap")
  Check(st == "created" and point.own and point.own.keys.guildLoc == nil, "a backup carries no part of it")
  c.TwichUIDB.guildLoc.state = "sharing"
  Check(R.Restore:Restore(point.id), "restore queued")
  local rdb = c.TwichUIRestoreDB
  local db2 = copy(c.TwichUIDB)
  local c2 = MakeClient(A, { "!!!TwichUI" })
  c2.TwichUIDB, c2.TwichUIRestoreDB, c2.TwichUIBackupDB, c2.TwichUIShareDB = db2, copy(rdb), copy(c.TwichUIBackupDB), copy(c.TwichUIShareDB)
  c2.LOADED["!!!TwichUI"] = true; c2.FireEvent("ADDON_LOADED", "!!!TwichUI")
  Check(c2.TwichUIDB.guildLoc.state == "sharing" and c2.TwichUIDB.guildLoc.interval == 30, "restoring a backup leaves the choice as it was")
  Check(c2.TwichUIDB.guildLoc.lastEpoch == T0 + 77, "...and the epoch")
end

---------------------------------------------------------------------------
Section("5 the message")
do
  Fresh({})
  local c = Boot(A)
  local GL = c.GL
  local e = T0 + 5
  Check(GL.EncodePosition(e, 7, 1429, 4521, 0) == "1:p:" .. e .. ":7:1429:4521:0", "position text")
  Check(GL.EncodeWithdraw(e) == "1:w:" .. e, "withdrawal text")
  local longest = GL.EncodePosition(GL.EPOCH_MAX, 1048576, 999999, 10000, 10000)
  Check(#longest <= 64 and longest == "1:p:4294967295:1048576:999999:10000:10000", "the longest is " .. #longest .. " bytes, epochs past 2^31 are exact")
  local k, e2, n, map, x, y = GL.Parse(GL.EncodePosition(e, 7, 1429, 4521, 0))
  Check(k == "p" and e2 == e and n == 7 and map == 1429 and x == 4521 and y == 0, "round trip; zero is a place")
  k, e2 = GL.Parse(GL.EncodeWithdraw(GL.EPOCH_MAX)); Check(k == "w" and e2 == GL.EPOCH_MAX, "withdrawal round trip")
  local function Bad(text, code)
    local kk, why = GL.Parse(text)
    Check(kk == nil and why == code, ("%q reads as %s (got %s)"):format(tostring(text), code, tostring(why)))
  end
  Bad(nil, "malformed"); Bad("", "malformed"); Bad("hello", "malformed")
  Bad("2:p:1700000000:1:1429:1:1", "newer-protocol"); Bad("0:p:1700000000:1:1429:1:1", "bad-version")
  Bad("01:p:1700000000:1:1429:1:1", "malformed"); Bad("1000:w:1700000000", "malformed")
  Bad("1:q:1700000000", "bad-kind"); Bad("1:p:1700000000:1:1429:1", "malformed"); Bad("1:p:1700000000:1:1429:1:1:1", "malformed")
  Bad("1:p:1700000000:1:1429:1:1 ", "malformed"); Bad(" 1:p:1700000000:1:1429:1:1", "malformed"); Bad("1:p:1700000000:1:1429:1:1\n", "malformed")
  Bad("1:p:-1700000000:1:1429:1:1", "malformed"); Bad("1:p:1700000000:1:1429:1.5:1", "malformed"); Bad("1:p:0x1:1:1429:1:1", "malformed")
  Bad("1:p:1599999999:1:1429:1:1", "bad-range"); Bad("1:p:4294967296:1:1429:1:1", "bad-range"); Bad("1:p:99999999999:1:1429:1:1", "bad-range")
  Bad("1:p:1700000000:0:1429:1:1", "bad-range"); Bad("1:p:1700000000:1048577:1429:1:1", "bad-range"); Bad("1:p:1700000000:1:0:1:1", "bad-range")
  Bad("1:p:1700000000:1:1429:10001:1", "bad-range"); Bad("1:p:1700000000:1:1429:1:10001", "bad-range")
  Bad("1:p:1700000000:01:1429:1:1", "bad-range"); Bad("1:p:1700000000:1:1429:00:1", "bad-range"); Bad("1:p:01700000000:1:1429:1:1", "bad-range")
  Bad("1:w:1700000000:1", "malformed"); Bad("1:w:abc", "malformed"); Bad("1:w:1599999999", "bad-range")
  Bad(("1:w:1700000000"):rep(5), "too-long")
end

---------------------------------------------------------------------------
Section("6 receiving: identity, order, the epoch rules")
do
  SPACED = true
  Fresh()
  local v = Boot(B)
  local GL = v.GL
  local E = T0 + 2000
  -- unknown sender: dropped, one throttled roster refresh, not remembered
  Advance(11)
  local asks = v.ASKS
  Msg(v, "Mallory Vane", P(E, 1)); Msg(v, "Mallory Vane", P(E, 2))
  Check(GL.Peek("Mallory Vane") == nil and v.ASKS == asks + 1, "a stranger is dropped and asks for one refresh")
  Advance(11); Msg(v, "Mallory Vane", P(E, 3)); Check(v.ASKS == asks + 2, "...at most once per interval")
  Check(GL.Snapshot().drops["not-in-roster"] == 3 and GL.Snapshot().buckets == 0, "...counted by code, no state kept")
  -- the other checks
  Msg(v, A, P(E, 1), "PARTY"); Check(GL.Peek(A) == nil and GL.Snapshot().drops.channel == 1, "only GUILD")
  Msg(v, B, P(E, 1)); Check(GL.Peek(B) == nil, "never ourselves")
  Msg(v, A, "garbage"); Msg(v, A, P(E, 1, 99999)); Check(GL.Peek(A) == nil, "malformed or unknown map dropped")
  Msg(v, A, P(E, 1, 1415)); Check(GL.Peek(A) == nil and GL.Snapshot().drops["unknown-map"] == 2, "a continent is too coarse")
  Msg(v, A, P(E, 1, 1429, 0, 10000)); local pk = GL.Peek(A)
  Check(pk and pk.map == 1429 and pk.x == 0 and pk.y == 10000 and pk.epoch == E and pk.number == 1 and not pk.closed, "a position, zero and the edge included")
  Check(GL.Snapshot().records == 1, "one record")
  -- names in other forms are the same sender
  Msg(v, "Alice Stone-Forever", P(E, 2, 1429, 1, 2)); Check(GL.Peek(A).number == 2, "Name-Realm form agrees")
  -- through the real AceComm path
  Advance(30)
  v.FireEvent("CHAT_MSG_ADDON", "TwichUIGuild", P(E, 3, 1453, 7, 8), "GUILD", A)
  Check(GL.Peek(A).number == 3 and GL.Peek(A).map == 1453, "CHAT_MSG_ADDON reaches the handler")
  -- class and level only from the roster, unknown stays unknown
  v.EXTRA[A] = { level = 60, class = "MAGE" }; v.EXTRA["Bob Reeve"] = { level = 0, class = "mage" }
  v.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  local RS = GL.Roster
  local e = RS.Lookup(A)
  Check(e and e.level == 60 and e.class == "MAGE" and e.online == true, "class and level come from the roster")
  e = RS.Lookup(B); Check(e and e.level == nil and e.class == nil, "an unusable value is unknown")
  -- the epoch rules
  Advance(400)
  Check(GL.Peek(A) == nil, "(records expire; start clean)")
  local C = "Cara Dunn"
  -- order within an epoch
  Msg(v, C, P(E, 5)); Msg(v, C, P(E, 5)); Msg(v, C, P(E, 4))
  Check(GL.Peek(C).number == 5 and GL.Snapshot().drops["old-number"] == 2, "same or lower number in an epoch is dropped")
  Msg(v, C, P(E, 6)); Check(GL.Peek(C).number == 6, "higher is taken")
  Msg(v, C, P(E + 1, 1)); Check(GL.Peek(C).epoch == E + 1 and GL.Peek(C).number == 1, "a higher epoch restarts the numbers")
  Msg(v, C, P(E, 99)); Check(GL.Peek(C).epoch == E + 1 and GL.Snapshot().drops["old-epoch"] == 1, "a lower epoch never replaces")
  -- timeline 1: a position queued, then invisible: w(101), late p(100,7)
  Advance(400)
  Msg(v, C, P(E + 100, 5)); Msg(v, C, W(E + 101))
  local tomb = GL.Peek(C)
  Check(tomb and tomb.closed and tomb.map == nil and GL.Snapshot().tombstones == 1 and GL.Snapshot().records == 0, "p then w removes the marker")
  Msg(v, C, P(E + 100, 7)); Check(GL.Peek(C).closed, "a late p(100,7) is dropped")
  Advance(400)
  Msg(v, C, W(E + 101)); Msg(v, C, P(E + 100, 7)); Check(GL.Peek(C).closed and GL.Snapshot().drops["closed-epoch"] == nil and GL.Snapshot().drops["old-epoch"] >= 2, "w first, then the late p, is dropped")
  -- timeline 2: withdrawal before any position
  Advance(400)
  Msg(v, C, W(E + 101)); Check(GL.Peek(C).closed and GL.Snapshot().records == 0, "a withdrawal with no earlier record is a tombstone, no marker")
  Msg(v, C, P(E + 100, 1)); Check(GL.Peek(C).closed, "...and a late p(100) is dropped")
  Msg(v, C, W(E + 101)); Check(GL.Peek(C).closed, "a repeated withdrawal changes nothing")
  Msg(v, C, W(E + 50)); Check(GL.Peek(C).epoch == E + 101, "a lower withdrawal never lowers it")
  -- timelines 3 and 4: resume after the withdrawal, delayed older traffic
  Msg(v, C, P(E + 102, 1)); Check(GL.Peek(C).epoch == E + 102 and not GL.Peek(C).closed, "the resumed session is taken")
  Msg(v, C, W(E + 101)); Check(not GL.Peek(C).closed and GL.Peek(C).epoch == E + 102, "a delayed w(101) does not kill the new session")
  Msg(v, C, P(E + 100, 7)); Check(GL.Peek(C).epoch == E + 102, "a delayed p(100,7) is dropped")
  Msg(v, C, W(E + 103)); Check(GL.Peek(C).closed, "the next withdrawal closes it")
  Msg(v, C, P(E + 102, 2)); Check(GL.Peek(C).closed, "...its own session's late numbers too")
  -- a withdrawal closes unseen lower epochs: the same-epoch withdrawal
  Advance(400)
  Msg(v, C, P(E + 10, 1)); Msg(v, C, W(E + 10)); Msg(v, C, P(E + 10, 2))
  Check(GL.Peek(C).closed and GL.Snapshot().drops["closed-epoch"] == 1, "w(E) closes epoch E itself")
  -- the rate: five in a burst, then one every four seconds
  Advance(400)
  SPACED = false
  for i = 1, 8 do Msg(v, A, P(E + 20, i)) end
  Check(GL.Peek(A).number == 5 and GL.Snapshot().drops.rate == 3, "burst of five")
  Advance(4); Msg(v, A, P(E + 20, 9)); Check(GL.Peek(A).number == 9, "one more after four seconds")
  SPACED = true
  -- offline: only a pass newer than the record, only live records; tombstones stay
  Msg(v, C, P(E + 30, 1)); Msg(v, C, W(E + 31))
  GUILD[A] = false
  v.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  Check(GL.Peek(A) == nil and GL.Snapshot().stats.offlineCleared == 1, "an offline member's marker goes")
  Check(GL.Peek(C) and GL.Peek(C).closed, "tombstones stay")
  GUILD[A] = true
  Msg(v, A, P(E + 20, 20)); Advance(6)
  v.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  Check(GL.Peek(A), "online again, kept (absence or a stale pass proves nothing)")
  GUILD["Cara Dunn"] = nil
  v.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  Msg(v, "Cara Dunn", P(E + 40, 1)); Check(GL.Peek("Cara Dunn") and GL.Peek("Cara Dunn").closed, "a member missing from the roster is not an unknown sender for held state")
end

---------------------------------------------------------------------------
Section("7 caps and expiry")
do
  SPACED = false
  local names = {}
  for i = 1, 420 do names[#names + 1] = ("Guild%03d Member"):format(i) end
  Fresh(names); GUILD[A] = true
  local v = Boot(A, { guildLoc = { state = "invisible" } })   -- receives, sends nothing
  local GL = v.GL
  local E = T0 + 3000
  -- 200 live, 200 withdrawn first (tombstones with no earlier record)
  for i = 1, 200 do Msg(v, names[i], P(E, 1)) end
  for i = 201, 400 do Msg(v, names[i], W(E)) end
  local s = GL.Snapshot()
  Check(s.records == 200 and s.tombstones == 200 and s.buckets == 400, "400 held, 400 senders rated")
  Msg(v, names[401], P(E, 1)); Check(GL.Peek(names[401]) == nil and GL.Snapshot().drops["bucket-cap"] == 1, "a new sender is refused at the bucket cap")
  Advance(100)   -- buckets idle for 60 s are swept; records and tombstones are held for 300 s
  s = GL.Snapshot()
  Check(s.buckets == 0 and s.records == 200 and s.tombstones == 200, "idle buckets swept, nothing else")
  Msg(v, names[401], P(E, 1)); Msg(v, names[402], W(E))
  Check(GL.Peek(names[401]) == nil and GL.Peek(names[402]) == nil and GL.Snapshot().drops.full == 2, "at the record cap a new identity is refused, position or withdrawal")
  for i = 201, 400 do Check(GL.Peek(names[i]) and GL.Peek(names[i]).closed, "tombstone kept " .. i) end
  Msg(v, names[1], P(E, 2)); Check(GL.Peek(names[1]).number == 2, "an update for a held sender is taken at the cap")
  Msg(v, names[2], W(E + 1)); Check(GL.Peek(names[2]).closed, "...and a withdrawal")
  Msg(v, names[201], P(E + 5, 1)); Check(GL.Peek(names[201]) and not GL.Peek(names[201]).closed, "a tombstoned sender may start a new session at the cap")
  s = GL.Snapshot()
  Check(s.records + s.tombstones == 400, "still 400")
  -- expiry frees room: 300 s after the last message
  Advance(150)   -- 250 s since the first messages; the updated ones are younger
  Check(GL.Snapshot().records + GL.Snapshot().tombstones == 400, "nothing expires early")
  Advance(60)
  s = GL.Snapshot()
  Check(s.records + s.tombstones == 3 and GL.Peek(names[1]) and GL.Peek(names[2]) and GL.Peek(names[201]), "the rest expired on the receiver's own clock")
  Msg(v, names[401], P(E, 1)); Check(GL.Peek(names[401]), "room again")
  Advance(400)
  s = GL.Snapshot()
  Check(s.records == 0 and s.tombstones == 0 and s.buckets == 0 and s.armed == 0, "everything gone and the sweep timer stopped")
  -- documented limitation: ordering lives only in the receiver's memory
  Msg(v, names[5], W(E + 101)); Advance(301)
  Msg(v, names[5], P(E + 100, 7))
  Check(GL.Peek(names[5]) and not GL.Peek(names[5]).closed, "after the tombstone expired an old delayed position is first contact (limit)")
  -- the receiver's reload forgets as well
  local v2 = Boot("Guild010 Member")
  Msg(v2, names[5], P(E + 100, 7)); Check(v2.GL.Peek(names[5]), "a reloaded receiver takes old traffic as first contact (limit)")
end

---------------------------------------------------------------------------
Section("8 sending: when, how often, how fresh")
do
  local function Run(interval, seconds, still)
    Fresh({ A })
    local c = Boot(A, { guildLoc = { interval = interval } })
    local last = CLOCK
    local first
    c.SENDHOOK = nil
    local gaps, prev = {}, nil
    for t = 1, seconds do
      Advance(1)
      if not still then Move(c, 0.1 + 0.8 * ((t * 0.0731) % 1), 0.5) end
      while #c.WIRE > 0 do
        local m = table.remove(c.WIRE, 1)
        if prev then gaps[#gaps + 1] = m.at - prev else first = m.at - last end
        prev = m.at
      end
    end
    return c, first, gaps
  end
  for _, interval in ipairs({ 10, 15, 30, 60 }) do
    local c, first, gaps = Run(interval, 900, true)
    local worst = 0
    for _, g in ipairs(gaps) do worst = math.max(worst, g) end
    Check(first >= 5 - 1 and first <= 20 + 1, ("interval %d: the first send comes %ds in"):format(interval, first))
    Check(#gaps >= 10 and worst <= 66.01, ("interval %d: healthy standing-still gap %.1f s is at most 66"):format(interval, worst))
    Check(worst >= 0.9 * 60 - interval, ("...and it really is a heartbeat, not every tick (%d: worst %.1f, %d gaps)"):format(interval, worst, #gaps))
  end
  -- moving sends at every tick, jittered +-10%
  for _, interval in ipairs({ 10, 15, 30, 60 }) do
    local c, first, gaps = Run(interval, 700, false)
    local lo, hi = math.huge, 0
    for _, g in ipairs(gaps) do lo, hi = math.min(lo, g), math.max(hi, g) end
    Check(#gaps >= 700 / interval - 3 and lo >= interval * 0.9 - 1.01 and hi <= interval * 1.1 + 1.01, ("interval %d moving: gaps %.1f..%.1f"):format(interval, lo, hi))
    Check(hi - lo > 0.2 or interval == 10, "the jitter varies")
  end
  -- the interval can change on the fly
  Fresh({ A })
  local c = Boot(A)
  Advance(40); Deliver(c)
  c.GL.SetInterval(60)
  Advance(1000)
  Check(c.GL.Interval() == 60 and #Deliver(c) >= 14 and c.GL.Snapshot().stats.ticks < 80, "a changed interval takes over, one chain")
  -- movement, in yards and in the fallback
  Fresh({ A })
  local y = Boot(A, nil, { yards = true })
  Advance(21); Deliver(y)
  Move(y, 0.502, 0.5)   -- 2 yards
  Advance(16); Check(#y.WIRE == 0, "2 yards is not moving")
  Move(y, 0.52, 0.5)    -- 20 yards from the last send
  Advance(16); Check(#y.WIRE == 1, "20 yards is")
  y.WIRE = {}
  Move(y, 0.52, 0.5, 1453)
  Advance(16); Check(#y.WIRE == 1, "a new map counts as moving")
  local f = Boot(A)   -- no world positions: the fallback
  Advance(21); f.WIRE = {}
  Move(f, 0.502, 0.5); Advance(16); Check(#f.WIRE == 0, "fallback: a tiny step is not moving")
  Move(f, 0.51, 0.5); Advance(16); Check(#f.WIRE == 1, "fallback: a normalized 0.005 is")
  -- no position: nothing, and no heartbeat
  local n = Boot(A, nil, { here = false })
  Advance(300)
  Check(#n.LOG == 0 and n.GL.Snapshot().skips["no-position"] >= 10, "no position, no message")
  Move(n, 0.3, 0.3); Advance(16); Check(#n.WIRE == 1, "the first valid position goes at once")
  -- loading screens
  local l = Boot(A)
  l.FireEvent("PLAYER_LEAVING_WORLD"); Advance(200)
  Check(#l.LOG == 0 and l.GL.Snapshot().skips.loading >= 5, "nothing while loading")
  l.FireEvent("PLAYER_ENTERING_WORLD"); l.ChatThrottleLib.avail = 400; Advance(30); Check(#l.WIRE >= 1, "...and on after")
  -- a continent is not a place to send from
  local k = Boot(A, nil, { here = { map = 1415, x = 0.5, y = 0.5 } }); Advance(100)
  Check(#k.LOG == 0, "only zones or smaller")
  -- off, invisible and malformed never send; initial state applies before any send
  for _, saved in ipairs({ { guildLoc = { state = "invisible" } }, { guildLoc = { state = "off" } }, { guildLoc = "junk" }, { guildLoc = { state = "x" } } }) do
    Fresh({ A, B })
    local q = Boot(A, saved)
    Advance(400)
    Check(#q.LOG == 0 and #q.PRIOS == 0 and not q.GL.Snapshot().session, "no message: " .. tostring(saved.guildLoc.state or saved.guildLoc))
  end
  -- outside a guild, nothing; joining starts a session
  Fresh({})
  local o = Boot(A); Advance(100); Check(#o.LOG == 0 and not o.GL.Snapshot().session, "no guild, no session")
  GUILD[A] = true; o.FireEvent("PLAYER_GUILD_UPDATE", "player"); Advance(30)
  Check(#o.WIRE == 1 and o.GL.Snapshot().session, "joining a guild starts one")
  -- a bad pass of the schedule: lockdown
  Fresh({ A })
  local b = Boot(A); b.LOCK = true; Advance(200)
  Check(#b.LOG == 0 and b.GL.Snapshot().skips.blocked >= 5, "no sends while the game refuses addon messages")
  b.LOCK = false; Advance(16); Check(#b.WIRE >= 1, "...and the stalled one goes at the next tick")
end

---------------------------------------------------------------------------
Section("9 the transport")
do
  Fresh({ A, B })
  local function Setup()
    local c = Boot(A)
    return c, c.ChatThrottleLib, c.LibStub("AceComm-3.0")
  end
  -- the gate reads the library's own numbers
  local c, CTL = Setup()
  local text = c.GL.EncodePosition(T0 + 1, 1, 1429, 5000, 5000)
  CTL.bQueueing = false
  CTL.avail = #text + CTL.MSG_OVERHEAD + 1; CTL.LastAvailUpdate = os.clock(); CTL.HardThrottlingBeginTime = 0
  CTL.BURST = 100000
  local ok = c.GL.Preflight(CTL, text); Check(ok, "room: sends")
  CTL.avail = #text + CTL.MSG_OVERHEAD - 0.5; ok = c.GL.Preflight(CTL, text); Check(ok == false, "less than the message and its overhead: skip")
  CTL.avail = 0; CTL.MAX_CPS = 0
  local fits, why = c.GL.Preflight(CTL, text); Check(fits == false and why == "no-room", "no bandwidth")
  CTL.MAX_CPS = 800
  CTL.bQueueing = true; CTL.avail = 100000
  fits, why = c.GL.Preflight(CTL, text); Check(fits == false and why == "queueing", "already queueing")
  CTL.bQueueing = nil; CTL.avail = 100000
  Check(c.GL.Preflight(CTL, text), "a never-set bQueueing is not queueing")
  -- AceComm's one escape byte counts when a text starts with a control character
  local ctl = "\001" .. text
  CTL.bQueueing = false; CTL.avail = #ctl + CTL.MSG_OVERHEAD + 0.5; CTL.LastAvailUpdate = os.clock()
  Check(c.GL.Preflight(CTL, ctl) == false, "the escape byte is counted")
  CTL.avail = #ctl + CTL.MSG_OVERHEAD + 1.5; CTL.LastAvailUpdate = os.clock()
  Check(c.GL.Preflight(CTL, ctl), "...and fits one more")

  -- skipped by the gate: stays due, goes at the next tick, never queued
  c, CTL = Setup()
  c.REFILL = false; CTL.bQueueing = true
  Advance(100)
  Check(#c.LOG == 0 and c.GL.Snapshot().skips.queueing >= 3, "queueing: nothing handed over")
  Check(next(CTL.Prio.NORMAL.ByName) == nil, "...and nothing queued by us")
  CTL.bQueueing = false; CTL.avail = 1000; CTL.LastAvailUpdate = os.clock()
  Advance(16); Check(#c.LOG == 1, "room again: the stalled position goes at the next tick")

  -- an unexpected game throttle: the library queues it; we notice, count it, and wait
  c, CTL = Setup()
  c.REFILL = true; c.RESULT = 3   -- AddonMessageThrottle
  Advance(21)
  local s = c.GL.Snapshot()
  Check(s.stats.queued == 1 and s.outstanding == 1 and #c.WIRE == 0, "a throttled send is counted as queued, honestly")
  Check(CTL.bQueueing == true, "(the library is queueing it)")
  Advance(200)
  s = c.GL.Snapshot()
  Check(s.stats.queued == 1 and #c.LOG == 1 and (s.skips.queueing or 0) + (s.skips.outstanding or 0) >= 5, "nothing else is handed over meanwhile")
  c.RESULT = 0
  Despool(c)
  s = c.GL.Snapshot()
  Check(#c.WIRE == 1 and s.stats.queuedSent == 1 and s.outstanding == 0, "released later: it does go out, and the hold is lifted")
  Check(c.GL.Parse(c.WIRE[1].text) == "p", "(it was a position)")
  -- a queued send whose callback never comes does not hold for ever
  c, CTL = Setup()
  c.RESULT = 3; Advance(21); Check(c.GL.Snapshot().outstanding == 1, "queued")
  c.RESULT = 0; CTL.bQueueing = false; CTL.Prio.NORMAL.Ring.pos = nil
  Advance(100)
  Check(c.GL.Snapshot().stats.outstandingReset == 1 and c.GL.Snapshot().outstanding <= 1, "forgotten after a minute")

  -- the game refuses (not a throttle): counted, stays due
  c, CTL = Setup()
  c.RESULT = 5
  Advance(21)
  s = c.GL.Snapshot()
  Check(s.stats.refused >= 1 and s.stats.sent == 0 and s.outstanding == 0, "a refusal is not a send")
  c.RESULT = 0; Advance(16); Check(#c.WIRE >= 1, "and it goes when the game takes it")

  -- an incompatible library: no ordinary queued send, receiving still works
  local variants = {
    function(ctl, ace) ctl.UpdateAvail = nil end,
    function(ctl, ace) ctl.MSG_OVERHEAD = "40" end,
    function(ctl, ace) ctl.bQueueing = "no" end,
    function(ctl, ace) ctl.SendAddonMessage = nil end,
    function(ctl, ace) ace.SendCommMessage = nil end,
    function(ctl, ace) ctl.UpdateAvail = function() error("boom") end end,
    function(ctl, ace) ctl.UpdateAvail = function() return "lots" end end,
  }
  for i, break_ in ipairs(variants) do
    c, CTL, ace = Setup()
    local ace = c.LibStub("AceComm-3.0")
    local calls = 0
    break_(CTL, ace)
    c.PRIOS = {}
    Advance(200)
    Check(#c.LOG == 0 and #c.PRIOS == 0, "variant " .. i .. ": no position, not even a queued one")
    s = c.GL.Snapshot()
    Check(s.transport ~= "ok" and s.transport ~= "unchecked" and s.lastSkip, "variant " .. i .. ": the report says why (" .. tostring(s.transport) .. ")")
    Check(c.GL.CanSend() == false, "variant " .. i .. ": CanSend says no")
    Msg(c, B, P(T0 + 4000, 1)); Check(c.GL.Peek(B), "variant " .. i .. ": receiving still works")
  end
end

---------------------------------------------------------------------------
Section("10 withdrawals")
do
  Fresh({ A, B })
  -- sharing to invisible: a withdrawal with a higher epoch, ALERT, not gated
  local a, v = Boot(A), Boot(B)
  Advance(40)
  Deliver(a, v)
  local pe = v.GL.Peek(A)
  Check(pe and not pe.closed, "the receiver shows the sender")
  a.ChatThrottleLib.bQueueing = true; a.ChatThrottleLib.avail = 0; a.REFILL = false
  a.PRIOS = {}
  Check(a.GL.SetState("invisible"), "invisible")
  Check(#a.PRIOS == 1 and a.PRIOS[1].prio == "ALERT" and a.PRIOS[1].text:find("^1:w:"), "the withdrawal is not held back by the position gate")
  Check(a.TwichUIDB.guildLoc.wp == true, "owed, saved")
  a.ChatThrottleLib.bQueueing = false; a.ChatThrottleLib.avail = 1000; a.REFILL = true
  Despool(a)
  local wire = Deliver(a, v)
  local _, nw = Kinds(wire); Check(nw == 1, "the withdrawal went out when the library released it")
  local we = EpochOf(wire[#wire].text)
  Check(we > pe.epoch, "its epoch is higher than the session's")
  Check(v.GL.Peek(A).closed and a.TwichUIDB.guildLoc.wp == nil, "removed there; accepted here, so no longer owed")
  Advance(200); Check(#a.LOG == 1 + 1 or #a.LOG == 2, "(no further positions while invisible)")
  local logs = #a.LOG
  Advance(200); Check(#a.LOG == logs, "...none at all")
  -- resume: epochs in one second still rise; late old traffic is ignored
  a.GL.SetState("sharing"); Advance(40)
  local w2 = Deliver(a, v)
  local ne = EpochOf(w2[#w2].text)
  Check(ne > we, "the resumed session is above the withdrawal")
  Check(v.GL.Peek(A) and not v.GL.Peek(A).closed and v.GL.Peek(A).epoch == ne, "shown again")
  Msg(v, A, W(we)); Msg(v, A, P(pe.epoch, 99)); Check(v.GL.Peek(A).epoch == ne and not v.GL.Peek(A).closed, "delayed old withdrawal and position do nothing")

  -- withdrawal before the first position
  Fresh({ A, B })
  a, v = Boot(A), Boot(B)
  a.GL.SetState("invisible")
  w2 = Deliver(a, v)
  Check(select(2, Kinds(w2)) == 1 and v.GL.Peek(A).closed and v.GL.Snapshot().records == 0, "a tombstone and no marker")
  Msg(v, A, P(EpochOf(w2[1].text) - 1, 1)); Check(v.GL.Peek(A).closed, "the late first position is dropped")

  -- refused by the game: still owed, retried at +15 and +45, ends at the first one the game takes
  Fresh({ A })
  a = Boot(A); Advance(40)
  a.RESULT = 5; a.LOG = {}
  a.GL.SetState("off")
  Check(#a.LOG == 1 and a.TwichUIDB.guildLoc.wp == true, "attempt one")
  Advance(14); Check(#a.LOG == 1, "...nothing before +15")
  Advance(2); Check(#a.LOG == 2, "attempt two at +15")
  a.RESULT = 0
  Advance(31); Check(#a.LOG == 3 and a.TwichUIDB.guildLoc.wp == nil, "attempt three at +45, taken: no longer owed")
  Advance(300); Check(#a.LOG == 3, "no more")
  Check(a.GL.Snapshot().stats.wRefused == 2 and a.GL.Snapshot().stats.wAccepted == 1, "counted: refused 2, accepted 1")

  -- never accepted: gives up after the last attempt and says so
  Fresh({ A })
  a = Boot(A); Advance(40)
  a.RESULT = 5; a.LOG = {}
  a.GL.SetState("invisible")
  Advance(100)
  s = a.GL.Snapshot()
  Check(#a.LOG == 3 and s.stats.wGaveUp == 1 and a.TwichUIDB.guildLoc.wp == nil and not s.withdrawing, "three attempts, then it stops and the flag is cleared")
  Advance(600); Check(#a.LOG == 3, "and stays stopped")

  -- a lockdown: the attempts are skipped (nothing sent), the flag survives a reload while off
  Fresh({ A, B })
  a, v = Boot(A), Boot(B)
  Advance(40); Deliver(a, v)
  a.LOCK = true; a.LOG = {}
  a.GL.SetState("off")
  Advance(10)
  Check(#a.LOG == 0 and a.TwichUIDB.guildLoc.wp == true and a.TwichUIDB.guildLoc.state == "off", "blocked: owed")
  local db = copy(a.TwichUIDB)
  local last = db.guildLoc.lastEpoch
  -- reload while Off
  local a2 = Boot(A, db)
  Check(a2.GL.State() == "off", "still off after the reload")
  Check(#a2.PRIOS == 1 and a2.PRIOS[1].prio == "ALERT" and a2.PRIOS[1].text:find("^1:w:"), "the owed withdrawal is handed over at once, ALERT")
  Despool(a2)   -- (entering the world empties the library's bandwidth; it sends within a second)
  Check(#a2.LOG == 1, "...and the library sends it")
  Check(EpochOf(a2.LOG[1].text) > last, "with a fresh epoch")
  Check(db.guildLoc.wp == nil, "taken: cleared")
  local sn = a2.GL.Snapshot()
  Check(not sn.session and sn.records == 0 and sn.tombstones == 0 and sn.roster == 0, "no session, no recording, no roster")
  Advance(400); Check(#a2.LOG == 1, "never a position")
  Msg(a2, B, P(T0 + 9000, 1)); Check(a2.GL.Peek(B) == nil, "nothing received while off")
  Check(sn.events <= 1, "at most the one world event, and it goes once nothing is owed")
  a2.FireEvent("PLAYER_ENTERING_WORLD"); Check(a2.GL.Snapshot().events == 0, "...it goes")
  -- off with an owed withdrawal and the lockdown still on: bounded, no positions, no records
  db = { guildLoc = { state = "off", wp = true, lastEpoch = last } }
  local a3 = Boot(A, db, { lock = true })
  Advance(100)
  Check(#a3.LOG == 0 and a3.GL.Snapshot().stats.wGaveUp == 1 and db.guildLoc.wp == nil and not a3.GL.Snapshot().session, "bounded: gave up, nothing started")
  -- an owed flag with sharing chosen is superseded
  local a4 = Boot(A, { guildLoc = { state = "sharing", wp = true, lastEpoch = T0 } })
  a4.FireEvent("PLAYER_ENTERING_WORLD"); Advance(40)
  Check(a4.TwichUIDB.guildLoc.wp == nil and select(2, Kinds(a4.WIRE)) == 0, "a new session replaces the owed withdrawal")
  -- an unusable epoch state cannot withdraw and says so
  local a5 = Boot(A, { guildLoc = { state = "off", wp = true, lastEpoch = "x" } })
  Advance(100); Check(#a5.LOG == 0 and a5.GL.Snapshot().stats.wNoEpoch == 1, "no valid epoch: silent")

  -- resuming sharing invalidates the retries and the old callbacks
  Fresh({ A })
  a = Boot(A); Advance(40)
  a.RESULT = 5; a.LOG = {}
  a.GL.SetState("invisible")
  a.RESULT = 0
  a.GL.SetState("sharing")
  Check(a.TwichUIDB.guildLoc.wp == nil, "choosing sharing clears the owed flag")
  Advance(100)
  local ws = 0
  for _, l in ipairs(a.LOG) do if l.text:find("^1:w:") then ws = ws + 1 end end
  Check(ws == 1, "no retry of the old withdrawal")
  -- a stale callback must not clear a newer debt
  Fresh({ A })
  a = Boot(A); Advance(40)
  a.RESULT = 3; a.LOG = {}
  a.GL.SetState("invisible")          -- w1 queued by the throttle
  a.GL.SetState("sharing")
  a.GL.SetState("invisible")          -- w2 queued too
  a.RESULT = 0
  local sawPending
  local sends = 0
  a.SENDHOOK = function(text)
    if text:find("^1:w:") then
      sends = sends + 1
      if sends == 2 then sawPending = a.GL.Pending() end   -- w1's callback has run by now
    end
  end
  Despool(a)
  Check(sends == 2 and sawPending == true, "w1's late callback left the newer debt alone")
  Check(a.GL.Pending() == false and a.GL.Snapshot().stats.wStale >= 1, "w2's callback cleared it; w1's was ignored")
  -- the library's queued old withdrawal is ignored by receivers
  -- (covered by the epoch rules in section 6)
end

---------------------------------------------------------------------------
Section("11 rapid changes")
do
  Fresh({ A, B })
  local a, v = Boot(A), Boot(B)
  Advance(1)
  for i = 1, 60 do a.GL.SetState(i % 2 == 0 and "sharing" or "invisible") end
  a.GL.SetState("sharing")
  local s = a.GL.Snapshot()
  Check(s.timers <= 6, "timers outstanding stay bounded (" .. s.timers .. ")")
  Check(#queue < 30, "engine timers pending stay bounded (" .. #queue .. ")")
  Advance(300)
  s = a.GL.Snapshot()
  Check(s.stats.ticks <= 300 / 15 * 1.2 + 1 and s.stats.ticks >= 10, "one tick chain, not many (" .. s.stats.ticks .. " ticks)")
  Check(s.session and a.TwichUIDB.guildLoc.wp == nil, "settled as sharing")
  local wire = Deliver(a, v)
  local p = Kinds(wire)
  Check(p >= 3 and p <= 6, "a normal count of heartbeats (" .. p .. ")")
  local sessions, es = 0, {}
  for _, m in ipairs(wire) do if m.text:find("^1:p:") then es[EpochOf(m.text)] = true end end
  for _ in pairs(es) do sessions = sessions + 1 end
  Check(sessions == 1, "all from the last session")
  -- toggling while a tick or a withdrawal timer is outstanding does nothing stale
  a.GL.SetState("invisible"); a.GL.SetState("off"); a.GL.SetState("invisible"); a.GL.SetState("sharing")
  Advance(500)
  s = a.GL.Snapshot()
  Check(s.timers <= 6 and s.armed <= 3, "still bounded")
  -- no position is created after a state change: go invisible and advance through the stale tick
  a.WIRE = {}; a.LOG = {}
  a.GL.SetState("invisible"); a.LOG = {}
  Advance(400)
  Check(select(1, Kinds(a.WIRE)) == 0 and #a.LOG == 0, "nothing after invisible, even through stale timers")
end

---------------------------------------------------------------------------
Section("12 guild changes, off, cleanup")
do
  Fresh({ A, B })
  local a, v = Boot(A), Boot(B)
  Advance(40); Deliver(a, v); Deliver(v, a)
  Check(a.GL.Peek(B) and v.GL.Peek(A), "both see each other")
  local e1 = EpochOf(a.LOG[1].text)
  -- leaving the guild: no withdrawal can reach it; everything held goes; no more sends
  GUILD[A] = nil
  a.LOG = {}
  a.FireEvent("PLAYER_GUILD_UPDATE", "player")
  s = a.GL.Snapshot()
  Check(not s.session and s.records == 0 and s.tombstones == 0, "left: session ended, records forgotten")
  Check(#a.LOG == 0 and a.TwichUIDB.guildLoc.wp == nil, "...no withdrawal attempted into a guild we have left")
  Advance(300); Check(#a.LOG == 0, "...and nothing is sent")
  Check(a.GL.State() == "sharing", "the choice is untouched")
  -- joining another guild: a new session, a new epoch, nothing carried over
  GUILD[A] = true; GUILDNAME = "Another Guild"
  a.FireEvent("PLAYER_GUILD_UPDATE", "player")
  Check(a.GL.Snapshot().session, "a new guild, a new session")
  Advance(30)
  Check(#a.LOG == 1 and EpochOf(a.LOG[1].text) > e1, "with a higher epoch")
  -- the same guild named again later (or unreadable for a moment) is not a change
  local sess = a.GL.Snapshot().stats.sessions
  a.FireEvent("PLAYER_GUILD_UPDATE", "player"); a.GetGuildInfo = function() return nil end
  a.FireEvent("PLAYER_GUILD_UPDATE", "player")
  Check(a.GL.Snapshot().stats.sessions == sess, "no change, no new session")
  a.GetGuildInfo = function() return GUILDNAME end
  a.FireEvent("PLAYER_GUILD_UPDATE", "party1")

  -- off: records, buckets, roster and events go; the handler discards
  Fresh({ A, B })
  a, v = Boot(A), Boot(B)
  Advance(40); Deliver(a, v)
  Check(v.GL.Snapshot().events >= 2 and v.GL.Snapshot().roster == 2, "listening")
  Check(v.R.ListenerCounts({}).GUILD_ROSTER_UPDATE == 1, "one roster listener")
  v.GL.SetState("off")
  s = v.GL.Snapshot()
  Check(s.records == 0 and s.tombstones == 0 and s.buckets == 0 and s.roster == 0 and s.events == 0, "off: everything gone")
  local counts = v.R.ListenerCounts({})
  Check(counts.GUILD_ROSTER_UPDATE == nil and counts.PLAYER_GUILD_UPDATE == nil, "...no events listened for")
  Advance(100); Check(v.GL.Snapshot().armed == 0, "...and no timers armed")
  Msg(v, A, P(T0 + 7000, 1)); Check(v.GL.Peek(A) == nil, "the handler discards")
  v.GL.SetState("invisible")
  Check(v.GL.Snapshot().events >= 2 and v.GL.Snapshot().roster == 2, "invisible listens again")
  Msg(v, A, P(T0 + 7000, 1)); Check(v.GL.Peek(A), "invisible still shows others")
  v.LOG = {}
  Advance(40); Check(#v.LOG == 0, "...and sends nothing")
  -- the report reads without names, places or epochs
  local lines = v.R.Diag and v.R.Diag.Sections and nil
  local snap = v.GL.Snapshot()
  local flat = {}
  local function walk(t) for k, x in pairs(t) do flat[#flat + 1] = tostring(k); if type(x) == "table" then walk(x) else flat[#flat + 1] = tostring(x) end end end
  walk(snap)
  local blob = table.concat(flat, " ")
  Check(not blob:find("Alice") and not blob:find("Bob") and not blob:find("1429") and not blob:find(tostring(T0)), "the snapshot holds counts and codes only")
end

---------------------------------------------------------------------------
Section("13 roster validation and refresh bookkeeping (offline semantics)")
do
  Fresh({ A, B })
  local c = Boot(A)
  local RS = c.GL.Roster
  local refreshedAt
  RS.OnRefresh(function() refreshedAt = CLOCK end)
  local function Pass()
    local serial = RS.Serial()
    refreshedAt = nil
    c.FireEvent("GUILD_ROSTER_UPDATE")
    Advance(RS.REBUILD_GAP + RS.COALESCE)
    Check(refreshedAt ~= nil, "the requested roster pass actually ran")
    Check(RS.Serial() == serial + 1, "one requested refresh makes one pass")
    Check(RS.Stamp() == refreshedAt, "stamp is the actual refresh callback time")
    return serial, refreshedAt
  end
  -- valid levels and classes are kept
  c.EXTRA[A] = { level = 1, class = "MAGE" }
  c.EXTRA[B] = { level = 60, class = "WARRIOR" }
  local s0, t0 = Pass()
  local ea, ka = RS.Lookup(A)
  local eb, kb = RS.Lookup(B)
  Check(ea and ea.level == 1 and ea.class == "MAGE", "level 1 and MAGE kept")
  Check(eb and eb.level == 60 and eb.class == "WARRIOR", "level 60 and WARRIOR kept")
  Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "serial advances once; stamp is the pass time")
  c.EXTRA[A] = { level = 255, class = "MAGE" }
  s0, t0 = Pass()
  Check(RS.Lookup(A).level == 255, "level 255 kept")
  Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "second pass: serial once, stamp at the pass")
  -- invalid levels stay nil, the class is not lost
  for _, lv in ipairs({ "7", 1.5, 0, -3, 256, false, {}, 0 / 0, math.huge, -math.huge }) do
    c.EXTRA[A] = { level = lv, class = "MAGE" }
    s0, t0 = Pass()
    local e = RS.Lookup(A)
    Check(e and e.level == nil and e.class == "MAGE", "level " .. tostring(lv) .. " is nil, class kept")
    Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "pass bookkeeping holds for " .. tostring(lv))
  end
  -- invalid classes stay nil, the level is not lost
  for _, cl in ipairs({ "", "mage", "MaGe", "MAGE2", ("M"):rep(21), 42, false, {} }) do
    c.EXTRA[A] = { level = 60, class = cl }
    s0, t0 = Pass()
    local e = RS.Lookup(A)
    Check(e and e.class == nil and e.level == 60, "class " .. tostring(cl) .. " is nil, level kept")
    Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "pass bookkeeping holds for class " .. tostring(cl))
  end
  -- equivalent sender spellings resolve to the same entry and key
  c.EXTRA[A] = { level = 60, class = "WARRIOR" }
  s0, t0 = Pass()
  local eA, kA = RS.Lookup(A)
  local eR, kR = RS.Lookup("Alice Stone-Forever")
  local eC, kC = RS.Lookup("alice stone")
  local eU, kU = RS.Lookup("ALICE STONE")
  local eW, kW = RS.Lookup("  alice   stone  ")
  Check(eA == eR and eA == eC and eA == eW and eA == eU, "full-name, realm, case and whitespace spellings share one entry")
  Check(kA == kR and kA == kC and kA == kW and kA == kU, "...and the same normalized key")
  Check(eA.level == 60 and eA.class == "WARRIOR", "the shared entry holds the roster values")
  Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "identity pass bookkeeping")
  -- an unchanged roster still passes: serial once, stamp at the pass, data intact
  s0, t0 = Pass()
  local e2, k2 = RS.Lookup(A)
  Check(e2 and k2 == kA and e2.level == 60 and e2.class == "WARRIOR", "unchanged data survives a pass")
  Check(RS.Serial() == s0 + 1 and RS.Stamp() == t0, "unchanged pass: serial once, stamp at the pass")
end

print(("guild locations: %d checks PASSED"):format(checks))
