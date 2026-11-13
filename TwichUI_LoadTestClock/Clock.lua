-- TwichUI Load Test clock: a DEVELOPMENT-ONLY, always-loaded companion of TwichUI_LoadTest (docs/testlab.md "Saved-data load test").
-- Never packaged. It stores GetTime() when the game logs out or reloads, and when it is back, so the Lab can report how long a /reload took
-- and whether the large synthetic saved file was loaded (and so written) at that logout. It reads and writes only TwichUILoadClockDB.
-- GetTime() is assumed to keep counting across a /reload (it reads the computer's uptime in the versions documented elsewhere); the Lab
-- reports the raw numbers and calls a negative or implausible span "not measurable", never a figure.
local R = TwichUI
local C = { MAX = 10 }
R.LoadClock = C
C.fileAt = type(GetTime) == "function" and GetTime() or nil

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
local function Loaded(name)
    local api = C_AddOns and C_AddOns.IsAddOnLoaded
    return type(api) == "function" and api(name) == true or false
end
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "TwichUI_LoadTestClock" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if type(TwichUILoadClockDB) ~= "table" then TwichUILoadClockDB = {} end
        C.previous = type(TwichUILoadClockDB.logout) == "table" and TwichUILoadClockDB.logout or nil
        TwichUILoadClockDB.logout = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C.enterAt = GetTime()
        local db, p = TwichUILoadClockDB, C.previous
        if type(db) ~= "table" or not p or type(p.at) ~= "number" then return end
        local rec = { logoutAt = p.at, fileAt = C.fileAt, enterAt = C.enterAt, toFile = C.fileAt and (C.fileAt - p.at) or nil, toWorld = C.enterAt - p.at,
            loadTestLoaded = p.loadTest == true, workshopLoaded = p.workshop == true, items = tonumber(p.items) }
        if type(db.list) ~= "table" then db.list = {} end
        table.insert(db.list, rec)
        while #db.list > C.MAX do table.remove(db.list, 1) end
        C.last = rec
    elseif event == "PLAYER_LOGOUT" then
        if type(TwichUILoadClockDB) ~= "table" then return end
        local meta = R.LoadTest and R.LoadTest.Meta and R.LoadTest.Meta()
        TwichUILoadClockDB.logout = { at = GetTime(), loadTest = Loaded("TwichUI_LoadTest"), workshop = Loaded("TwichUI_Workshop"), items = meta and meta.items or nil }
    end
end)

-- the measurements of the last reloads, newest last (copies)
function C.List()
    local out = {}
    local list = type(TwichUILoadClockDB) == "table" and TwichUILoadClockDB.list or nil
    if type(list) ~= "table" then return out end
    for i, r in ipairs(list) do
        if type(r) == "table" then
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            out[#out + 1] = c
        end
    end
    return out
end
