-- Control messages on the sharing prefix (setup/Share.lua): anyone can whisper one, and it has to be
-- decompressed before it can be read. One longer than the limit is dropped unread (nothing is
-- decompressed), a normal one is still read, and a setup whose offer would be over the limit is refused
-- before anything is sent, with a reason, instead of waiting for an answer that can't come.
-- Mocks show TwichUI's bookkeeping only. How the game throttles and joins addon messages is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
math.randomseed(5)

local function boot(name)
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
  return c
end
local function settle() for _ = 1, 12 do FlushTimers(); Pump() end end

local pal = boot("Pal Stonebrook")
local SH = pal.TwichUI.Share
local LS, LD = pal.LibStub("LibSerialize"), pal.LibStub("LibDeflate")
local function Encode(t) return LD:EncodeForWoWAddonChannel(LD:CompressDeflate(LS:Serialize(t), { level = 5 })) end

-- counts decompressions from here on (the library is shared by every client in this file)
local inflates = 0
local inflate = LD.DecompressDeflate
LD.DecompressDeflate = function(...) inflates = inflates + 1; return inflate(...) end
local receive = pal._comm.TwichUISetup

-- 1) Too long: dropped before it is decompressed, whatever it holds -----------------------------
local filler = {}
for i = 1, 9000 do filler[i] = ("%08d%s"):format(i, tostring(math.random())) end
local big = Encode({ t = "offer", p = SH.PROTOCOL, id = "1", tables = { pad = { owner = "x", hash = table.concat(filler) } }, to = "Pal Stonebrook" })
assert(#big > 65536, "the test message is over the limit: " .. #big)
receive("TwichUISetup", big, "WHISPER", "Evil Stranger")
assert(inflates == 0, "nothing was decompressed")
assert(SH.droppedCode == "control-too-large", tostring(SH.droppedCode))
assert(next(SH.incoming) == nil, "no transfer was started")

-- even with sharing off it is never opened
pal.TwichUIDB.modules.setupSharing = false
receive("TwichUISetup", big, "GUILD", "Evil Stranger")
assert(inflates == 0)
pal.TwichUIDB.modules.setupSharing = true

-- 2) A normal message is still read --------------------------------------------------------------
SH.droppedCode = nil
local offer = Encode({ t = "offer", p = SH.PROTOCOL, id = "42", tables = { FooDB = { owner = "Foo", hash = "abcd" } }, to = "Pal Stonebrook" })
assert(#offer < 65536)
receive("TwichUISetup", offer, "WHISPER", "Ranulf Ashenvow")
assert(inflates == 1, "read as before")
assert(SH.incoming["Ranulf Ashenvow"] and SH.incoming["Ranulf Ashenvow"].stage == "asking", "an ordinary offer still arrives")

-- 3) Sending: an offer over the limit is refused with a reason, and nothing goes out ------------
local rich = boot("Ranulf Ashenvow")
local RSH = rich.TwichUI.Share
local tables = {}
for i = 1, 2000 do tables[("Addon%04dSettingsDB%s"):format(i, tostring(math.random()))] = { owner = ("Owner%04d%s"):format(i, tostring(math.random())), hash = tostring(math.random()), data = {} } end
rich.TwichUIShareDB.pack = { created = 1, version = "test", tables = tables }
SENT_LOG = {}
local ok, why = RSH:SendTo("Pal Stonebrook")
assert(not ok and why:find("too many settings"), tostring(why))
assert(RSH.outgoing == nil, "no transfer was started")
assert(#SENT_LOG == 0, "nothing was sent")

-- an ordinary setup is sent as before
rich.TwichUIShareDB.pack = { created = 1, version = "test", tables = { FooDB = { owner = "Foo", hash = "abcd", data = { a = 1 } } } }
ok, why = RSH:SendTo("Pal Stonebrook")
assert(ok, tostring(why))
settle()
assert(RSH.outgoing and RSH.outgoing.stage == "offered" and #SENT_LOG > 0, "offered as before")

print("PASSED")
