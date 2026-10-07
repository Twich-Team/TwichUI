dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
math.randomseed(11)
local function boot(name, saved, scan)
  local c = MakeClient(name, {"!!!TwichUI","Foo"})
  CLIENTS[name] = c
  if saved then c.TwichUIDB = saved end
  if scan then c.TwichUIDB = c.TwichUIDB or {}; c.TwichUIDB.setup = {scanNext = true} end
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
  c.FooDB = {a = string.rep("abcdefghij", 300)}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
  c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
  return c
end
local function settle() for _=1,12 do FlushTimers(); Pump() end end
local function sentTo(dist) local n = 0 for _, m in ipairs(SENT_LOG or {}) do if m.dist == dist then n = n + 1 end end return n end

-- 1) Defaults and migration -------------------------------------------------
assert(boot("Fresh").TwichUIDB.shareTransport == "DIRECT", "fresh install: Direct")
assert(boot("Defaults", {modules = {shareWhisper = true, shareGroup = false, shareGuild = false}}).TwichUIDB.shareTransport == "DIRECT", "legacy defaults: Direct")
assert(boot("NoDirect", {modules = {shareWhisper = false}}).TwichUIDB.shareTransport == "DIRECT", "direct switched off, no other channel: Direct")
assert(boot("Grp", {modules = {shareGroup = true}}).TwichUIDB.shareTransport == "PARTY", "explicit group kept")
assert(boot("Gld", {modules = {shareGuild = true}}).TwichUIDB.shareTransport == "GUILD", "explicit guild kept")
assert(boot("Both", {modules = {shareGroup = true, shareGuild = true}}).TwichUIDB.shareTransport == "PARTY", "both on: group, as the old router tried it first")
local keep = boot("Chosen", {shareTransport = "GUILD", modules = {shareGroup = true}})
assert(keep.TwichUIDB.shareTransport == "GUILD", "an existing choice is never overwritten")
assert(boot("Junk", {shareTransport = "BANANA"}).TwichUI.Share.Transport() == "DIRECT", "invalid value reads as Direct")
local unrelated = boot("Other", {modules = {chronicleDeaths = true, groupCheck = false}, whisperProbe = {ok = false}})
assert(unrelated.TwichUIDB.modules.chronicleDeaths == true and unrelated.TwichUIDB.modules.groupCheck == false and unrelated.TwichUIDB.whisperProbe, "unrelated settings untouched")
assert(not unrelated.TwichUI.Share.SetTransport("nope") and unrelated.TwichUI.Share.Transport() == "DIRECT")

-- 2) Direct is the default, sent as a WHISPER to the full name --------------
local rich = boot("Ranulf Ashenvow", nil, true); rich.TwichUI.Setups:SaveMine(false)
local pal = boot("Pal Stonebrook")
local zed = boot("Zed Quill")
local SH = rich.TwichUI.Share
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true, ["Zed Quill"]=true}   -- grouped, but Direct is chosen
SENT_LOG = {}
assert(SH:SendTo("pal  stonebrook")); settle()
assert(sentTo("WHISPER") > 0 and sentTo("PARTY") == 0, "direct only, nothing on the group channel")
assert(SENT_LOG[1].to == "pal stonebrook" or SENT_LOG[1].to == "Pal Stonebrook" or SENT_LOG[1].to:lower() == "pal stonebrook", SENT_LOG[1].to)
assert(pal.TwichUI.Share.incoming["Ranulf Ashenvow"].stage == "asking")
assert(next(zed.TwichUI.Share.incoming) == nil, "others in the group see nothing")
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done" and SH.outgoing.route[1] == "WHISPER", "done is the receiver's acknowledgment")
assert(pal.TwichUIDB.setup.received["Ranulf Ashenvow"].tables.FooDB.data.a:len() == 3000, "reassembled over whispers")
assert(sentTo("PARTY") == 0)
-- nothing was applied without the receiver choosing to
assert(pal.FooDB.a == string.rep("abcdefghij", 300) and not pal.TwichUIDB.setup.pending)

-- 3) Missing / bad recipients ------------------------------------------------
SH.outgoing = nil
local ok, why = SH:SendTo(""); assert(not ok and why:find("name"), why)
ok, why = SH:SendTo("Pal"); assert(not ok and why:find("full name"), why)
ok, why = SH:SendTo("Pal#1234"); assert(not ok and why:find("Battle.net"), why)
ok, why = SH:SendTo("Ranulf Ashenvow"); assert(not ok and why:find("That's you"), why)

-- 4) Direct fails: no fallback to Party or Guild -----------------------------
GUILD = {["Ranulf Ashenvow"] = true, ["Pal Stonebrook"] = true}
-- a) the game refuses the whisper
FAIL_SEND = function(dist) return dist == "WHISPER" end
SENT_LOG = {}
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(SH.outgoing.stage == "failed" and SH.outgoing.reason:find("wouldn't send a direct message"), SH.outgoing.reason)
assert(sentTo("PARTY") == 0 and sentTo("GUILD") == 0, "no automatic fallback")
FAIL_SEND = nil
-- b) the game accepts it but nothing arrives (as in the beta): times out, still no fallback
DROP_SPACED_WHISPERS = true
SENT_LOG = {}
SH.outgoing = nil
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(SH.outgoing.stage == "offered")
RunLongTimers(130)
assert(SH.outgoing.stage == "failed" and SH.outgoing.reason:find("No answer") and SH.outgoing.reason:find("accepted the offer"), SH.outgoing.reason)
assert(sentTo("PARTY") == 0 and sentTo("GUILD") == 0 and sentTo("WHISPER") >= 1)
DROP_SPACED_WHISPERS = false

-- 5) Party and Guild, when chosen --------------------------------------------
SH.outgoing = nil; SH.SetTransport("PARTY"); SENT_LOG = {}
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(sentTo("PARTY") > 0 and sentTo("WHISPER") == 0 and sentTo("GUILD") == 0)
assert(pal.TwichUI.Share.incoming["Ranulf Ashenvow"].route[1] == "PARTY")
assert(next(zed.TwichUI.Share.incoming) == nil, "addressed to one person; others ignore it")
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done")
-- not in the same group
ok, why = SH:SendTo("Nobody Here"); assert(not ok and why:find("isn't in your group"), why)
local oldGroup = GROUP; GROUP = nil
ok, why = SH:SendTo("Pal Stonebrook"); assert(not ok and why:find("not in a party"), why)
GROUP = oldGroup
-- guild
SH.outgoing = nil; SH.SetTransport("GUILD"); SENT_LOG = {}
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(sentTo("GUILD") > 0 and sentTo("PARTY") == 0 and sentTo("WHISPER") == 0)
assert(next(zed.TwichUI.Share.incoming) == nil, "guild: not in the guild, not addressed")
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done")
ok, why = SH:SendTo("Zed Quill"); assert(not ok and why:find("isn't in your guild"), why)
GUILD["Zed Quill"] = false
ok, why = SH:SendTo("Zed Quill"); assert(not ok and why:find("isn't in your guild") or why:find("online"), why)
GUILD["Pal Stonebrook"] = false
ok, why = SH:SendTo("Pal Stonebrook"); assert(not ok and why:find("isn't online"), why)
GUILD["Pal Stonebrook"] = true
local savedGuild = GUILD; GUILD = nil
ok, why = SH:SendTo("Pal Stonebrook"); assert(not ok and why:find("not in a guild"), why)
GUILD = savedGuild

-- 6) A receiver reads all three whatever it sends with -----------------------
for _, mine in ipairs({"DIRECT", "PARTY", "GUILD"}) do
  pal.TwichUI.Share.SetTransport(mine)
  for _, theirs in ipairs({"DIRECT", "PARTY", "GUILD"}) do
    SH.outgoing = nil; SH.SetTransport(theirs); pal.TwichUI.Share.incoming = {}
    assert(SH:SendTo("Pal Stonebrook")); settle()
    assert(pal.TwichUI.Share.incoming["Ranulf Ashenvow"].stage == "asking", mine .. " receiver, " .. theirs .. " sender")
    pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
    assert(SH.outgoing.stage == "done", mine .. "/" .. theirs)
  end
end

-- 7) The game refuses the data pieces mid-transfer ---------------------------
SH.outgoing = nil; pal.TwichUI.Share.incoming = {}; SH.SetTransport("DIRECT")
assert(SH:SendTo("Pal Stonebrook")); settle()
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true)
Pump()                                        -- the accept reaches the sender, which starts packing
assert(SH.outgoing.stage == "packing")
FAIL_SEND = function() return true end        -- from here the game refuses everything the sender sends
for _ = 1, 8 do FlushTimers(); Pump() end
FAIL_SEND = nil
assert(SH.outgoing.stage == "failed" and SH.outgoing.reason:find("wouldn't send"), tostring(SH.outgoing.stage) .. " " .. tostring(SH.outgoing.reason))

-- 8) Everything was sent but the receiver's "done" never comes back ----------
SH.outgoing = nil; pal.TwichUI.Share.incoming = {}
assert(SH:SendTo("Pal Stonebrook")); settle()
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true)
Pump()                                        -- the accept gets through; later replies are lost
local guard = 0
while SH.outgoing.stage ~= "delivered" and SH.outgoing.stage ~= "done" and guard < 200 do
  FlushTimers()
  local keep = {}                             -- the receiver's messages are lost on the way back
  for _, m in ipairs(NET) do if m.from ~= pal then keep[#keep + 1] = m end end
  NET = keep
  Pump(); guard = guard + 1
end
assert(SH.outgoing.stage == "delivered", SH.outgoing.stage)
RunTickers()
assert(SH.outgoing.stage == "delivered", "not failed yet: still within the wait")
SH.outgoing.last = SH.outgoing.last - 61
RunTickers()
assert(SH.outgoing.stage == "failed" and SH.outgoing.reason:find("never confirmed"), tostring(SH.outgoing.reason))
print("TRANSPORT TESTS PASSED")
