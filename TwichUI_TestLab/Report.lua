-- TwichUI Test Lab: the plain-text report (R.TestLab.Report)
-- What a player (or a developer) pastes back: a fixed header, one line per case with its evidence label, and a facts line. It holds counts,
-- case ids and the Lab's own messages only: no character, realm, guild or account name, no chat, no item link, no saved value. Text that
-- came from a case is cleaned (control characters, item links and colour codes) and cut short before it is written.
--
--   TWICHUI-TESTLAB REPORT schema 1
--   client <version> build <n> interface <toc> | TwichUI <version> | Workshop <version or "not loaded"> | TestLab <version>
--   run: core,client | N cases: a pass, b fail, ... | 0.41 s | slices 31, worst 6.1 ms, worst frame 38 ms, overruns 0 | ended: complete
--   labels: ...
--   one line per case, then the overruns, then "facts: key=value ..."

local R = TwichUI
local TL = R.TestLab
local RP = {}
TL.Report = RP

RP.SCHEMA = 1
RP.MAX_DETAIL = 240
RP.MAX_BYTES = 30000

local WORD = { pass = "PASS", fail = "FAIL", error = "ERROR", skipped = "SKIP", timeout = "TIMEOUT", stopped = "STOP", pending = "PENDING", running = "RUNNING" }

-- Text from a case, made safe to paste
local function Clean(text, limit)
    text = tostring(text or "")
    text = text:gsub("|H.-|h(.-)|h", "[link]")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%c", " "):gsub("|", "/")
    if #text > (limit or RP.MAX_DETAIL) then text = text:sub(1, limit or RP.MAX_DETAIL) .. "..." end
    return text
end
RP.Clean = Clean

local function Version(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = get and get(addon, "Version")
    return v and Clean(v, 20) or "unknown"
end

local function Header(sum)
    local version, build, _, toc = "?", "?", nil, "?"
    if GetBuildInfo then version, build, _, toc = GetBuildInfo() end
    local workshop = R.Workshop and R.Workshop.ready and ("Workshop " .. Version("TwichUI_Workshop")) or "Workshop not loaded"
    local lines = {}
    lines[1] = ("TWICHUI-TESTLAB REPORT schema %d"):format(RP.SCHEMA)
    lines[2] = ("client %s build %s interface %s | TwichUI %s | %s | TestLab %s"):format(Clean(version, 20), Clean(build, 20), Clean(toc, 20),
        Version("!!!TwichUI"), workshop, TL.VERSION)
    local c = sum.counts
    local total = #sum.results
    lines[3] = ("run: %s | %d cases: %d pass, %d fail, %d skipped, %d error, %d timeout, %d stopped | %.2f s | slices %d, worst %.1f ms, worst frame %.0f ms, overruns %d | ended: %s")
        :format(#sum.cats > 0 and table.concat(sum.cats, ",") or "none", total, c.pass, c.fail, c.skipped, c.error, c.timeout, c.stopped,
            sum.seconds, sum.slices, sum.worstSlice * 1000, sum.worstFrame * 1000, sum.overrunCount, Clean(sum.ended, 20))
    lines[4] = ("clock: %s | slice %.0f ms | cooperative: a step that never yields cannot be interrupted, only measured"):format(sum.clock, (sum.slice or 0) * 1000)
    lines[5] = "labels: client = observed in this game client | synthetic = production code in the client's Lua on made-up data | guided = observed with the player's help | not run = never started"
    return lines
end

-- sum: Runner's summary ({ results, counts, cats, seconds, slices, worstSlice, worstFrame, overruns, overrunCount, ended, clock })
function RP.Build(sum)
    local lines = Header(sum)
    for _, r in ipairs(sum.results) do
        local label = (r.status == "stopped" and r.ms == nil) and "not run" or r.label
        local word = WORD[r.status] or r.status
        if r.class == "guided" and r.status == "stopped" and r.ms ~= nil then word = "CANCEL" end   -- the player's observation was cancelled part way
        local timing = r.ms and ("%.1f ms"):format(r.ms) or ""
        local detail = r.detail and Clean(r.detail) or ""
        lines[#lines + 1] = ("%-8s%s  %-9s %s%s"):format(word, Clean(r.id, 80), label, timing,
            detail ~= "" and ("  " .. detail) or "")
        for _, note in ipairs(r.notes or {}) do lines[#lines + 1] = "        " .. Clean(note, 400) end
    end
    if #sum.overruns > 0 then
        lines[#lines + 1] = "overruns (a step ran longer than the slice; it could not be interrupted):"
        for _, o in ipairs(sum.overruns) do
            lines[#lines + 1] = ("  %s  %.1f ms in one step"):format(Clean(o.id, 80), o.ms)
        end
    end
    local facts = {}
    for _, r in ipairs(sum.results) do
        for _, f in ipairs(r.facts or {}) do facts[#facts + 1] = f[1] .. "=" .. f[2] end
    end
    table.sort(facts)
    lines[#lines + 1] = "facts: " .. (#facts > 0 and table.concat(facts, " ") or "none")
    local text = table.concat(lines, "\n")
    if #text > RP.MAX_BYTES then text = text:sub(1, RP.MAX_BYTES) .. "\n... (cut at " .. RP.MAX_BYTES .. " bytes)" end
    return text
end
