-- Simulator lab diagnostic (docs/simulator-lab.md "Delayed failures"): what happens when the simulated clock runs
-- past TwichUI's group hello timer and Blizzard's own timers, with and without a party. diagnose.sh runs it three
-- times, selected by SIMLAB_PARAMS.mode:
--   baseline  no addon at all (--no-addons): the simulator and Blizzard's UI alone. Whatever fails here is not TwichUI's.
--   solo      TwichUI loaded, then the character leaves the simulator's sample party (Lab.Solo, state verified)
--   grouped   TwichUI loaded, the sample party kept on purpose: this is the run that crosses the hello boundary
-- All three run the same clock window (SIMLAB_PARAMS.window, in simulated seconds from the script's start).
--
-- Every send the addon attempts goes through Lab.WatchSends, a pass-through observer (records, then calls the
-- simulator's own function and returns or raises exactly what it did). No send is stubbed, filtered or skipped.
--
-- What this proves and does not: that the clock crossed these timers, what was sent, and what the simulator did with it.
-- It does not prove any message was delivered, received or understood by another client.
local P = rawget(_G, "SIMLAB_PARAMS") or {}
local mode, window = P.mode, P.window or 12
local Check, Say = Lab.Check, Lab.Say
local R = rawget(_G, "TwichUI")

Check("init", "TwichUI is loaded exactly when the run asked for it", mode ~= "baseline", R ~= nil)
Say("window", mode, "seconds=" .. window)

-- Group state first, so the run says what it is a run of.
local state
if mode == "solo" then
    state = Lab.Solo()
    Check("init", "solo: the game reports no group", false, state.inGroup)
    Check("init", "solo: not a raid", false, state.inRaid)
    Check("init", "solo: no members counted", 0, state.count)
    Check("init", "solo: no party unit exists", 0, state.partyUnits)
    Check("init", "solo: TwichUI's own member list is empty", 0, state.twichMembers)
else
    state = Lab.GroupState()
    if mode == "grouped" then
        Check("init", "grouped: the game reports a group", true, state.inGroup)
        Check("init", "grouped: not a raid", false, state.inRaid)
        Check("init", "grouped: party units exist", true, state.partyUnits > 0)
        Check("init", "grouped: TwichUI sees the same members", state.partyUnits, state.twichMembers)
    end
end
Say("group", mode, "inGroup=" .. tostring(state.inGroup), "inRaid=" .. tostring(state.inRaid), "count=" .. state.count,
    "partyUnits=" .. state.partyUnits, "twichMembers=" .. tostring(state.twichMembers))
if R then
    Check("init", "groupCheck is on (the default; the hello is gated by it)", true, R:Enabled("groupCheck"))
end

A_Admin.SetManualClock(GetTime())
Lab.WatchSends()
local steps = Lab.RunUntil(window, 0.5)
Say("clock", "simSeconds=" .. Lab.simSeconds, "advanceSteps=" .. steps, "window=" .. window)
Check("state", "the clock covered the declared window", true, Lab.simSeconds >= window - 1e-6)

local sends = Lab.sends
local attempted = #sends   -- from the timeline alone; the direct and control calls below add more
if mode == "baseline" then
    Check("state", "baseline: no addon sent anything", 0, attempted)
elseif mode == "solo" then
    -- TwichUI's hello timer still fires (it was set when the party arrived, before the character left); the send is
    -- skipped because Group.lua's Broadcast asks IsInGroup() when the timer runs. That is TwichUI's own logic.
    Check("state", "solo: no addon message was attempted across the window", 0, attempted)
    Check("state", "solo: TwichUI's peer list is empty", 0, next(R.Group.peers) and 1 or 0)
else
    Check("state", "grouped: at least one addon message was attempted", true, attempted >= 1)
    for i = 1, attempted do
        local e = sends[i]
        Say("attempt", "n=" .. i, "at=" .. ("%.2f"):format(e.at), "prefix=" .. tostring(e.prefix), "chatType=" .. tostring(e.chatType),
            "len=" .. tostring(e.len), "strictUtf8=" .. tostring(e.valid), "ok=" .. tostring(e.ok), "result=" .. tostring(e.result),
            "hex=" .. Lab.Hex(e.message or "", 48))
    end
    local first = sends[1]
    if first then
        Say("send", "n=1", "at=" .. ("%.2f"):format(first.at), "argc=" .. first.argc, "types=" .. table.concat(first.types, ","),
            "prefix=" .. tostring(first.prefix), "chatType=" .. tostring(first.chatType), "target=" .. tostring(first.target),
            "len=" .. tostring(first.len), "strictUtf8=" .. tostring(first.valid), "firstInvalidByte=" .. tostring(select(2, Lab.Utf8Valid(first.message or ""))),
            "ok=" .. tostring(first.ok), "result=" .. tostring(first.result), "hex=" .. Lab.Hex(first.message or ""))
        -- Typed from the source (setup/Share.lua: PREFIX; setup/Group.lua Broadcast, Share.lua GroupDist), not read from it.
        Check("state", "first send: prefix", "TwichUISetup", first.prefix)
        Check("state", "first send: chat type", "PARTY", first.chatType)
        Check("state", "first send: target", nil, first.target)
        Check("state", "first send: argument types", "string,string,string,nil", table.concat(first.types, ","))
        Check("state", "first send: made between 2.5 and 3.5 simulated seconds in (the hello timer is 3 s; the clock is read in 0.5 s chunks)", true,
            first.at >= 2.5 and first.at <= 3.5)

        -- Where the bytes come from: the same three steps Share.lua's Encode takes, repeated here on the same message
        -- (a version number and a protocol number; nothing about the player), and each stage's bytes judged.
        local SH = R.Share
        local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")
        local msg = { t = "hello", v = R.Group.Version(), p = SH.PROTOCOL }
        msg.to = "*"
        local serialized = LibSerialize:Serialize(msg)
        local compressed = LibDeflate:CompressDeflate(serialized, { level = 5 })
        local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
        for _, s in ipairs({ { "1 LibSerialize:Serialize", serialized }, { "2 LibDeflate:CompressDeflate (level 5)", compressed },
                             { "3 EncodeForWoWAddonChannel", encoded } }) do
            local ok, at = Lab.Utf8Valid(s[2])
            local nul = s[2]:find("\0", 1, true) ~= nil
            Say("stage", s[1], "len=" .. #s[2], "strictUtf8=" .. tostring(ok), "firstInvalidByte=" .. tostring(at), "hasNul=" .. tostring(nul))
        end
        Check("state", "stage 3 has no NUL (the only property EncodeForWoWAddonChannel promises)", false, encoded:find("\0", 1, true) ~= nil)
        -- The observed bytes decode back to the hello (byte-level integrity of what was handed to the API; not delivery).
        local decoded = LibDeflate:DecodeForWoWAddonChannel(first.message or "")
        local plain = decoded and LibDeflate:DecompressDeflate(decoded)
        local ok, t = false, nil
        if plain then ok, t = LibSerialize:Deserialize(plain) end
        Check("state", "the attempted bytes decode back to the hello message", "hello|*|true", ok and (tostring(t.t) .. "|" .. tostring(t.to) .. "|" .. tostring(t.v == R.Group.Version())) or "undecodable")
        Check("state", "the attempted bytes equal this script's reconstruction", true, first.message == encoded)

        -- Determinism: the identical call, made directly under pcall (no error handler between).
        local ok2, err2 = pcall(C_ChatInfo.SendAddonMessage, first.prefix, first.message, first.chatType)
        Say("direct", "pcall with the same bytes", "accepted=" .. tostring(ok2), "result=" .. tostring(err2))
        Check("state", "the same bytes given directly get the same verdict", tostring(first.ok), tostring(ok2))

        -- Discrimination: the same ChatThrottleLib/AceComm path, with a plain-text payload that is valid UTF-8.
        -- This is NOT TwichUI's serialization; it only shows whether the path itself is what refuses.
        local AceComm = LibStub("AceComm-3.0")
        local n0 = #Lab.sends
        AceComm:SendCommMessage("TwichUISetup", "hello", "PARTY", nil, "ALERT")
        Lab.Settle(0.5)
        local plainSend = Lab.sends[n0 + 1]
        Say("control", "AceComm path with ASCII 'hello' (synthetic, not TwichUI's payload)",
            "attempted=" .. tostring(plainSend ~= nil), "accepted=" .. tostring(plainSend and plainSend.ok), "result=" .. tostring(plainSend and plainSend.result))
        Check("state", "control: the same library path accepts a UTF-8 payload", true, plainSend ~= nil and plainSend.ok == true)
    end
    Say("sends", "attemptedInTimeline=" .. attempted, "totalWithDiagnosticCalls=" .. #sends)
end
Lab.Finish()
