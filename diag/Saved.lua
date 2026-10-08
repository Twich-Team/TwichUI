-- TwichUI: troubleshooting report, saved data
-- Which schema TwichUI's saved settings and Chronicle were at when the game loaded them, whether they
-- needed upgrading, and how many values had to be reset or set aside, by stable reason code. Counts and
-- codes only: no profile or setup contents, no character names, no notes, no saved-variable dumps.
-- Read from Persist.lua's report; nothing is measured or changed here.

local R = TwichUI
local D = R.Diag

local OUTCOME = {
    fresh = "new, nothing saved before",
    current = "already up to date",
    migrated = "upgraded at this load",
    future = "saved by a newer TwichUI: left untouched and not used this session",
    failed = "upgrade failed: nothing was changed, it will be tried again next load",
}

local function Stored(n) return n == nil and "none (saved before versions existed)" or tostring(n) end

local function Saved()
    local P = R.Persist
    if not (P and P.Report) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local r = P.Report()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end

    Line("settings schema: stored %s, this TwichUI writes %d; %s", Stored(r.main.stored), r.main.current, OUTCOME[r.main.outcome] or "not loaded yet")
    if r.main.outcome == "failed" then
        Line("failed at upgrade step %s", tostring(r.main.failedStep))
    end
    local chronicleStored = r.chronicle.stored == nil and "none" or tostring(r.chronicle.stored)
    Line("journey chronicle format: stored %s, this TwichUI writes %d; %s", chronicleStored, r.chronicle.current,
        OUTCOME[r.chronicle.outcome] or "not loaded yet")

    local codes = {}
    for code in pairs(r.repairs) do codes[#codes + 1] = code end
    table.sort(codes)
    if #codes == 0 then
        Line("repairs at this load: none")
    else
        for _, code in ipairs(codes) do
            Line("repair %s: %d%s", code, r.repairs[code], P.CODES[code] and " (something stored was reset or set aside)" or "")
        end
    end
    Line("stored values reset or set aside at this load: %d", r.lost)

    local status, reason = "ready", nil
    if r.main.outcome == "future" or r.chronicle.outcome == "future" then status, reason = "unavailable", "newer-saved-data"
    elseif r.main.outcome == "failed" then status, reason = "unavailable", "migration-failed"
    elseif r.lost > 0 then reason = "repaired" end
    return {
        configured = true, initialized = r.main.outcome ~= nil, status = status, reason = reason, lines = lines,
        limits = {
            "TwichUI can upgrade and repair what it can read. Data that was never written, or is too damaged to read, cannot be reconstructed.",
            "This is what TwichUI found when the game loaded its data. It cannot tell whether the game managed to write the files at logout; the game shows its own warning when a saved file is too large.",
        },
    }
end

D.Register("saved", { title = "Saved data", order = 15, snapshot = Saved })
