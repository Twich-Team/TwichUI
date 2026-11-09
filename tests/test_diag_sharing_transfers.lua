dofile(TESTS .. "harness.lua")
-- Transfer rendering and section status in diag/Sharing.lua: the 'started Ns ago' age, the
-- 'last activity Ns ago' idle suffix, the synthetic self-test suffix, the 'no data yet' and
-- 'via ?' fallbacks, and the 'waiting (messaging-locked-by-game)' /
-- 'unavailable (receivers-not-registered)' status branches. Names, reason texts and payloads
-- must never reach the report.
local out = {}
local DIAG_FILES = { "diag/Diagnostics.lua", "diag/Environment.lua", "diag/Lifecycle.lua", "diag/Notifications.lua", "diag/Zones.lua", "diag/Sharing.lua", "diag/Window.lua" }

local function Has(text, needle) return text:find(needle, 1, true) ~= nil end
local function Section(report, title)
  local from = report:find("== " .. title .. " ==", 1, true)
  assert(from, "section " .. title)
  return report:sub(from, report:find("\n== ", from + 5, true) or #report)
end

local c = MakeClient("Rich", { "!!!TwichUI" })
CLIENTS.Rich = c
c.print = function(s) table.insert(out, tostring(s)) end
c.TwichUIDB = {}
for _, f in ipairs(DIAG_FILES) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
c.LOADED["!!!TwichUI"] = true
c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)

local R, S, SD = c.TwichUI, c.TwichUI.Share, c.TwichUI.Diag
assert(S and S.Snapshot and SD and SD.Build, "Share and Diag are loaded")
c.GetTime = function() return 1000 end   -- fixed clock: ages become exact literals
local NOW = 1000
c.C_ChatInfo.IsAddonMessagePrefixRegistered = function() return true end   -- all prefixes registered, so the ladder reaches the receivers/blocked branches

-- age and idle: started 30s and last activity 10s before the fixed clock
S.outgoing = { target = "Zeta Zulu-Forever", id = "1", stage = "sending", route = { "WHISPER", "Zeta Zulu-Forever" },
  started = NOW - 30, last = NOW - 10, sent = 100, total = 5000, reason = "Check Zeta Zulu is online." }
local report = SD.Build()
local sh = Section(report, "Configuration sharing")
assert(Has(sh, "Configuration sharing: configured on, initialized yes, ready"), "healthy baseline: " .. sh)
-- contract: '<label> Pn: stage <stage> via <route>, <sent> of <total> bytes, started <age>s ago, last activity <idle>s ago'
assert(Has(sh, "outgoing P1: stage sending via WHISPER, 100 of 5000 bytes, started 30s ago, last activity 10s ago"), sh)
assert(Has(sh, "receivers registered with the message library: 5 of 5"), sh)
assert(not Has(sh, "Zeta") and not Has(sh, "Zulu") and not Has(sh, "Check Zeta"), "no names or reason text in the report: " .. sh)

-- self-test: the synthetic self-test transfer gets its own suffix
S.outgoing = { target = "Rich-Forever", id = "1", stage = "offering", route = { "LOOP" }, started = NOW - 5, last = NOW - 5, sent = 0, total = 0 }
sh = Section(SD.Build(), "Configuration sharing")
assert(Has(sh, "outgoing P1: stage offering via LOOP, 0 of 0 bytes, started 5s ago, last activity 5s ago (SYNTHETIC self-test: sent to this character)"), sh)

-- no byte counts: 'no data yet'; no route: 'via ?'
S.outgoing = { target = "Zeta Zulu-Forever", id = "1", stage = "offering", started = NOW - 2 }
sh = Section(SD.Build(), "Configuration sharing")
assert(Has(sh, "outgoing P1: stage offering via ?, no data yet, started 2s ago, no activity yet"), sh)

-- status ladder: receivers below expected -> unavailable (receivers-not-registered).
-- The receivers count is a local upvalue inside Share.lua, so the test trims the snapshot
-- table the section reads: the s.receivers < s.receiversExpected branch of Sharing.lua.
S.outgoing = nil
local realSnapshot = S.Snapshot
S.Snapshot = function() local snap = realSnapshot(); snap.receivers = 3; return snap end
report = SD.Build()
assert(Has(report, "unavailable (receivers-not-registered)"), report)
assert(Has(Section(report, "Configuration sharing"), "receivers registered with the message library: 3 of 5"), report)
S.Snapshot = realSnapshot

-- status ladder: the game locks addon messages -> waiting (messaging-locked-by-game)
c.C_ChatInfo.InChatMessagingLockdown = function() return true end
report = SD.Build()
assert(Has(report, "waiting (messaging-locked-by-game)"), report)
c.C_ChatInfo.InChatMessagingLockdown = function() return false end

-- status ladder: a prefix the game has not registered -> unavailable (prefix-not-confirmed),
-- and the unregistered prefix name is named (it is a code, not a person). Mirrors the
-- proven pattern in test_diagnostics.lua:304.
c.C_ChatInfo.IsAddonMessagePrefixRegistered = function(p) return p ~= "TwichUIData2" end
report = SD.Build()
assert(Has(Section(report, "Configuration sharing"), "unavailable (prefix-not-confirmed)"), report)
assert(Has(report, "not registered: TwichUIData2"), report)
c.C_ChatInfo.IsAddonMessagePrefixRegistered = function() return true end

-- privacy backstop for the transfer lines: peer names, reason texts and payloads stay out
S.outgoing = { target = "Zeta Zulu-Forever", id = "1", stage = "sending", route = { "WHISPER", "Zeta Zulu-Forever" },
  started = NOW - 30, last = NOW - 10, sent = 100, total = 5000, reason = "Check Zeta Zulu is online.", payload = "payload-secret" }
report = SD.Build()
for _, leak in ipairs({ "Zeta", "Zulu", "Check Zeta", "payload-secret" }) do
  assert(not Has(report, leak), "sharing report leaks: " .. leak)
end
assert(Has(Section(report, "Configuration sharing"), "outgoing P1:"), "peers stay labelled")

print("TEST_DIAG_SHARING_TRANSFERS PASSED")
