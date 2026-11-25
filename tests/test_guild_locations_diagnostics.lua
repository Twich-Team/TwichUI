-- Guild Locations diagnostics use the real AceComm/ChatThrottleLib on a synthetic guild.
-- Delivery is controlled independently in each direction; neither game networking nor a
-- successful control round trip is treated as proof of a normal location update.
REAL_COMM = true
dofile(TESTS .. "harness.lua")

local checks = 0
local function Check(ok, message)
  checks = checks + 1
  if not ok then error("FAILED: " .. message, 2) end
end
local function Has(text, fragment) return text:find(fragment, 1, true) ~= nil end
local A, B, C = "Alice Stone", "Bob Reeve", "Cara Dunn"
CLOCK = 1000
local queue, serial = {}, 0
local function After(delay, fn)
  serial = serial + 1
  queue[#queue + 1] = { at = CLOCK + delay, fn = fn, serial = serial }
end
local function Advance(seconds)
  local untilAt = CLOCK + seconds
  while true do
    local nextTimer, nextIndex
    for i, timer in ipairs(queue) do
      if timer.at <= untilAt and (not nextTimer or timer.at < nextTimer.at
        or (timer.at == nextTimer.at and timer.serial < nextTimer.serial)) then nextTimer, nextIndex = timer, i end
    end
    if not nextTimer then break end
    table.remove(queue, nextIndex)
    CLOCK = math.max(CLOCK, nextTimer.at)
    nextTimer.fn()
  end
  CLOCK = untilAt
end
local function Fresh()
  queue, CLIENTS = {}, {}
  GUILD = { [A] = true, [B] = true, [C] = true }
end
local function Boot(name, state, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.name, c.wire, c.history, c.registered = name, {}, {}, {}
  c.C_Timer = { After = After }
  c.GetTime = function() return CLOCK end
  c.time = function() return 1700000000 + math.floor(CLOCK) end
  c.here = not opts.noPosition and { map = 1429, x = 0.6543, y = 0.6789 } or nil
  c.C_Map = {
    GetMapInfo = function(id) if id == 1429 then return { mapID = id, mapType = 3, parentMapID = 1415 } end end,
    GetBestMapForUnit = function() return c.here and c.here.map end,
    GetPlayerMapPosition = function(map)
      if c.here and c.here.map == map then return { GetXY = function() return c.here.x, c.here.y end } end
    end,
  }
  c.IsInGuild = function() return GUILD[name] ~= nil end
  c.GetGuildInfo = function() if GUILD[name] ~= nil then return "Synthetic Guild" end end
  c.GetNumGuildMembers = function() local n = 0 for _ in pairs(GUILD) do n = n + 1 end return n end
  c.GetGuildRosterInfo = function(i)
    local names = {} for member in pairs(GUILD) do names[#names + 1] = member end table.sort(names)
    local member = names[i]
    if member then return member, "", 0, 60, "", "", "", "", GUILD[member], "", "MAGE" end
  end
  c.C_GuildInfo = { GuildRoster = function() end }
  c.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) c.registered[prefix] = true return true end,
    IsAddonMessagePrefixRegistered = function(prefix) return c.registered[prefix] == true end,
    InChatMessagingLockdown = function() return c.blocked == true end,
    SendAddonMessage = function(prefix, text, dist)
      local message = { prefix = prefix, text = text, dist = dist, at = CLOCK }
      c.wire[#c.wire + 1], c.history[#c.history + 1] = message, message
      c.ChatThrottleLib.avail = 400
      return 0
    end,
  }
  for _, file in ipairs({ "pins/Pins.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Search.lua",
    "guildloc/State.lua", "guildloc/Roster.lua", "guildloc/Comm.lua", "guildloc/Diagnostics.lua" }) do
    local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.TwichUIDB = { guildLoc = { state = state } }
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  c.ChatThrottleLib.avail = 400
  c.GL, c.D = c.TwichUI.GuildLoc, c.TwichUI.GuildLoc.Diagnostics
  return c
end
local function Deliver(from, to, filter)
  local wire = from.wire; from.wire = {}
  for _, m in ipairs(wire) do
    if not filter or filter(m) then to.FireEvent("CHAT_MSG_ADDON", m.prefix, m.text, m.dist, from.name) end
  end
  return wire
end
local function Pump(a, b, seconds, filterAB, filterBA)
  for _ = 1, seconds do
    Advance(1); Deliver(a, b, filterAB); Deliver(b, a, filterBA)
  end
end
local function Input(client, sender, text, dist, prefix)
  client.FireEvent("CHAT_MSG_ADDON", prefix or client.GL.PREFIX, text, dist or "GUILD", sender)
end
local function Count(client, kind)
  local n = 0 for _, m in ipairs(client.history) do if m.text:find("^1:" .. kind .. ":") then n = n + 1 end end return n
end
local function Nonce(client)
  for i = #client.history, 1, -1 do
    local id = client.history[i].text:match("^1:q:(%d+):")
    if id then return id end
  end
  error("No request was sent")
end
local function Reply(id, state, send, receive, render, epoch, number, age)
  return ("1:r:%s:%s:%s:%s:%s:%s:%s:%s"):format(id, state or "invisible", send or "not-sharing",
    receive or "unseen", render or "map-closed", epoch or 0, number or 0, age or 0)
end
local function Stable(value)
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  local keys, parts = {}, {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do parts[#parts + 1] = Stable(k) .. "=" .. Stable(value[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

print("-- Control round trip and normal-location evidence")
Fresh()
do
  local a, b = Boot(A, "sharing"), Boot(B, "invisible")
  Advance(25); Deliver(a, b); Deliver(b, a)
  Check(b.GL.Peek(A) ~= nil, "the normal location receiver holds Alice before the check")
  Check(a.D.Start(B), "a selected online guildmate check starts")
  Deliver(a, b); Deliver(b, a)
  local report = a.D.Report(B)
  Check(Has(report, "Round trip: confirmed"), "the selected peer automatically responds")
  Check(Has(report, "matches your last game-accepted update"), "a peer's held normal update confirms actual location reception")
  Check(not Has(report, "6543") and not Has(report, "6789") and not Has(report, "0.6543"), "the report excludes location coordinates")
  Pump(a, b, 91)
  Check(not a.D.IsRunning() and Count(a, "q") == 4, "the check stops after its four bounded polls")
  Check(Count(b, "p") == 0 and b.GL.State() == "invisible", "Invisible answers diagnostics without sending positions or changing state")
  for _, client in ipairs({ a, b }) do
    for _, message in ipairs(client.history) do
      Check(message.prefix == client.GL.PREFIX and message.dist == "GUILD", "controls and positions share the real location prefix and guild route")
    end
  end
end

Fresh()
do
  local a, b = Boot(A, "sharing", { noPosition = true }), Boot(B, "sharing", { noPosition = true })
  Check(a.D.Start(B), "diagnostics can run while no valid local position exists")
  Deliver(a, b); Deliver(b, a)
  local report = a.D.Report(B)
  Check(Has(report, "Round trip: confirmed") and Has(report, "Peer holds no live location for you"), "control delivery alone does not claim position delivery")
  Check(not Has(report, "matches your last game-accepted update"), "normal position proof is absent when no position was sent")
end

print("-- Missing and asymmetric delivery stays inconclusive")
for _, blockedDirection in ipairs({ "outbound", "inbound" }) do
  Fresh()
  local a, b = Boot(A, "invisible"), Boot(B, "invisible")
  Check(a.D.Start(B), "a missing-reply check starts")
  Pump(a, b, 91, blockedDirection == "outbound" and function() return false end or nil,
    blockedDirection == "inbound" and function() return false end or nil)
  local report = a.D.Report(B)
  Check(Has(report, "Round trip: inconclusive") and not Has(report, "Round trip: confirmed"), "silence in either direction remains inconclusive")
  Check(a.D.Snapshot().timeouts == 1 and not a.D.IsRunning(), "silence times out exactly once")
  Check(Count(a, "q") == 4, "missing replies do not produce an unbounded retry loop")
end

print("-- Recipient, nonce, route and payload validation")
Fresh()
do
  local a, b = Boot(A, "invisible"), Boot(B, "invisible")
  Check(a.D.Start(B), "validation fixture starts")
  local id = Nonce(a)
  local function Unconfirmed() return not Has(a.D.Report(B), "Round trip: confirmed") end
  Input(a, C, Reply(id)); Check(Unconfirmed(), "a different guildmate cannot answer for the selected peer")
  Input(a, B, Reply(id .. "9")); Check(Unconfirmed(), "a wrong nonce cannot complete the check")
  Input(a, B, Reply(id), "PARTY"); Check(Unconfirmed(), "a reply on another channel is rejected")
  Input(a, B, Reply(id), "GUILD", "UnrelatedPrefix"); Check(Unconfirmed(), "a reply on another prefix never reaches the diagnostic receiver")
  Input(a, "Stranger Name", Reply(id)); Check(Unconfirmed(), "a sender outside the roster is rejected")
  local invalid = {
    Reply(id, "off"), Reply(id, "invisible", "invented"), Reply(id, "invisible", nil, "invented"),
    Reply(id, "invisible", nil, nil, "invented"), Reply(id, nil, nil, nil, nil, 1, 1),
    Reply(id, nil, "drawn"), Reply(id, nil, nil, "ready"), Reply(id, nil, nil, nil, "accepted"),
    Reply(id, nil, nil, nil, nil, 0, 1), Reply(id, nil, nil, nil, nil, 1700000000, 0),
    Reply(id, nil, nil, nil, nil, 1700000000, 1, 301), Reply(id, nil, nil, nil, nil, "01700000000", 1),
    Reply(id, nil, nil, nil, nil, 4294967296, 1), Reply(id, nil, nil, nil, nil, 1700000000, 1048577),
    Reply(id, nil, nil, nil, nil, 1700000000, "01"), Reply(id, nil, nil, nil, nil, 0, 0, "00"),
    "1:r:" .. id .. ":" .. string.rep("x", 220), Reply(id) .. ":extra",
  }
  for _, text in ipairs(invalid) do
    Input(a, B, text)
    Check(Unconfirmed(), "malformed, unsupported or inconsistent replies cannot confirm a round trip")
  end
  Input(b, A, "1:q:123:" .. C)
  Input(b, A, "1:q:" .. string.rep("1", 25) .. ":" .. B)
  Input(b, A, "1:q:123:" .. B, "PARTY")
  Input(b, A, "1:q:123:" .. B .. "|bad")
  Input(b, "Stranger Name", "1:q:123:" .. B)
  Check(Count(b, "r") == 0, "invalid requests never trigger a response")
  Advance(4)
  Input(a, B, Reply(id))
  Check(not Unconfirmed(), "a valid selected-peer reply still works after rejected inputs")
  Check(Has(a.D.Report(B), "Peer holds no live location for you"), "canonical epoch/sequence zero describes an empty peer inbox")
  Input(a, B, Reply(id, "sharing", "ready"))
  Check(Has(a.D.Report(B), "Peer's choice: invisible"), "a reply burst cannot overwrite the accepted snapshot")
  Advance(4); Input(a, B, Reply(id, "sharing", "ready", "accepted", "drawn", 1700000000, 1, 0))
  Check(Has(a.D.Report(B), "Peer's choice: sharing") and Has(a.D.Report(B), "an earlier normal update"),
    "a later valid numeric reply is accepted without claiming a match to a local update")
end

print("-- Rate limits, inspection and bounded lifecycle")
Fresh()
do
  local a, b = Boot(A, "invisible"), Boot(B, "invisible")
  Check(a.D.Snapshot().events == 0 and a.D.Snapshot().armed == 0, "idle diagnostics hold no event listener or armed timers")
  Input(b, A, "1:q:123:" .. B)
  Input(b, A, "1:q:123:" .. B)
  Input(b, C, "1:q:456:" .. B)
  Check(Count(b, "r") == 1, "requests are globally throttled and one responder is retained")
  Advance(10); Input(b, A, "1:q:123:" .. B)
  Check(Count(b, "r") == 2, "the same bounded check can poll after the response throttle")
  Check(a.D.Start(B), "a check starts before stop and cooldown tests")
  local ok, code = a.D.Start(C)
  Check(not ok and code == "busy", "only one selected peer check may run")
  a.D.Stop(); ok, code = a.D.Start(B)
  Check(not ok and code == "cooldown", "manual stopping cannot bypass the start throttle")
  local probes = Count(a, "q")
  Advance(130)
  Check(Count(a, "q") == probes and not a.D.Snapshot().watching and not b.D.Snapshot().responding,
    "stopped work sends nothing later and responder retention expires")
  Check(a.D.Snapshot().events == 0 and b.D.Snapshot().events == 0 and a.D.Snapshot().armed == 0 and b.D.Snapshot().armed == 0,
    "expired checks release their diagnostic event listeners and timers")
  a.D.Inspect(B)
  Check(a.D.Snapshot().events == 1, "temporary inspection registers its guild cleanup event")
  Input(a, B, "1:p:1700000000:1:999999:5000:5000")
  Check(Has(a.D.Report(B), "could not be validated"), "selected inspection records real receive rejection reasons")
  Input(a, C, "1:p:1700000000:1:1429:5000:5000")
  Check(Has(a.D.Report(B), "could not be validated"), "another sender cannot overwrite the selected receive result")
  Advance(121)
  Check(not a.D.Snapshot().watching and not Has(a.D.Report(B), "could not be validated"), "temporary receive trace expires")
  Check(a.D.Start(B), "a check can restart after expiry")
  GUILD[A] = nil; a.FireEvent("PLAYER_GUILD_UPDATE", "player")
  Check(not a.D.IsRunning() and not a.D.Snapshot().watching, "leaving the guild clears a selected check")
  local before = Count(a, "q")
  Advance(100); Check(Count(a, "q") == before, "guild cleanup cancels future polls")
end

print("-- Off and local synthetic checks preserve player data")
Fresh()
do
  local a, b = Boot(A, "off"), Boot(B, "invisible")
  local ok, why = a.D.Start(B)
  Check(not ok and why == "off", "Off cannot start a network test")
  Input(a, B, "1:q:123:" .. A)
  Advance(100)
  Check(#a.history == 0 and a.GL.Snapshot().records == 0, "Off neither answers probes nor records positions")
  Check(b.D.Start(A), "an invisible requester may test an Off peer")
  Deliver(b, a); Deliver(a, b)
  Check(Has(b.D.Report(A), "Round trip: inconclusive"), "an Off peer's silence is not presented as a diagnosis of delivery")
  b.GL.SetState("off")
  Check(not b.D.IsRunning() and not b.D.Snapshot().watching, "changing state clears the selected check")
  local previewCalls = 0
  a.GL.Map = { SelfTest = function() previewCalls = previewCalls + 1 return true, "shown" end, Snapshot = function() return {} end }
  local saved, sent, held = Stable(a.TwichUIDB), #a.history, a.GL.Snapshot().records
  local text = a.D.SelfTest()
  Check(Has(text, "SYNTHETIC") and not Has(text, "FAIL:") and previewCalls == 1, "synthetic protocol tests pass and request only a local map preview")
  Check(Stable(a.TwichUIDB) == saved and #a.history == sent and a.GL.Snapshot().records == held and a.GL.State() == "off",
    "self-test changes no saved variables, network messages, real records or sharing choice")
  local snapshot = Stable(a.D.Snapshot())
  Check(not Has(snapshot, A) and not Has(snapshot, B) and not Has(snapshot, "6543") and not Has(snapshot, "1700000000"),
    "routine diagnostic snapshots contain counts and codes without names, positions or epoch identifiers")
end

print("-- Delayed transport callbacks describe only their own poll")
Fresh()
do
  local a = Boot(A, "invisible")
  local pending, calls = nil, 0
  -- Model the allowed preflight race: the first handover queues unexpectedly and
  -- the next poll finds the throttle busy. Other scenarios use the real libraries.
  a.GL.SendDiagnostic = function(_, callback)
    calls = calls + 1
    if calls == 1 then pending = callback return true, "handed-over" end
    return false, "queueing"
  end
  Check(a.D.Start(B), "a check with a queued first probe starts")
  Advance(20)
  Check(calls == 2 and Has(a.D.Report(B), "Last probe accepted by your game: not reported"),
    "a skipped later poll has no local acceptance result")
  pending(true)
  local report = a.D.Report(B)
  Check(Has(report, "Last probe accepted by your game: not reported")
    and not Has(report, "Last probe accepted by your game: yes"),
    "releasing the earlier queued probe cannot mark the later poll as accepted")
  a.D.Stop(); pending(false)
  Check(not a.D.IsRunning() and not Has(a.D.Report(B), "Communication check:"), "stopped checks ignore old transport callbacks")
end

Fresh()
do
  local a = Boot(A, "invisible")
  Check(a.D.Start(B), "a check starts before a modeled client stall")
  -- Run timers after their original due times, as after loading or a client stall.
  CLOCK = CLOCK + 55; Advance(0)
  Check(Count(a, "q") == 2, "a delayed timer sends one current probe without replaying missed polls")
  CLOCK = CLOCK + 40; Advance(0)
  Check(not a.D.IsRunning() and Count(a, "q") == 2 and a.D.Snapshot().timeouts == 1,
    "a timer waking past the deadline completes the check without a late probe")
end

print("-- Responder cleanup and unavailable peers")
Fresh()
do
  local a, b = Boot(A, "invisible"), Boot(B, "invisible")
  local ok, code = a.D.Start("Bob")
  Check(not ok and code == "bad-name", "Forever requires a full diagnostic target name")
  ok, code = a.D.Start(A)
  Check(not ok and code == "self", "a self round trip cannot be confused with a peer check")
  ok, code = a.D.Start("Stranger Name")
  Check(not ok and code == "not-in-roster", "unknown targets cannot start a check")
  GUILD[B] = false
  a.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  ok, code = a.D.Start(B)
  Check(ok, "a stale offline roster flag does not block the diagnostic trust path")
  Check(Has(a.D.Report(B), "listed offline"), "the cached offline flag remains visible as evidence")
  a.D.Stop()
  GUILD[B] = true
  a.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6)
  a.blocked = true
  ok, code = a.D.Start(B)
  Check(not ok and code == "blocked", "message lockdown prevents starting a diagnostic exchange")
  a.blocked = false
  Input(b, A, "1:q:123:" .. B)
  Check(b.D.Snapshot().responding and b.D.Snapshot().events == 1, "answering a peer installs bounded responder cleanup")
  b.FireEvent("PLAYER_GUILD_UPDATE", "party1")
  Check(b.D.Snapshot().responding, "another unit's guild notice does not clear the local check")
  GUILD[B] = nil; b.FireEvent("PLAYER_GUILD_UPDATE", "player")
  Check(not b.D.Snapshot().responding and b.D.Snapshot().events == 0 and b.D.Snapshot().armed == 0,
    "leaving a guild clears the responder, diagnostic listeners and armed timers")
  local replies = Count(b, "r")
  Input(b, A, "1:q:123:" .. B); Advance(100)
  Check(Count(b, "r") == replies, "a guildless former responder cannot send later replies")
  GUILD[B] = true; b.FireEvent("PLAYER_GUILD_UPDATE", "player")
  Input(b, A, "1:q:456:" .. B)
  Check(b.D.Snapshot().responding, "a responder may participate after joining its guild again")
  b.GL.SetState("off")
  Check(not b.D.Snapshot().responding and b.D.Snapshot().events == 0 and b.D.Snapshot().armed == 0,
    "Off cancels responder state and its diagnostic work")
end

print(("guild locations diagnostics: %d checks PASSED"):format(checks))
