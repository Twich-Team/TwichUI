-- TwichUI Load Test: a DEVELOPMENT-ONLY companion for the A4 saved-variables load gate (docs/testlab.md "Saved-data load test";
-- docs/workshop/market-data-foundation-v2.md "A4 as built"). Never packaged (.pkgmeta, tools/release.py).
--
-- It owns ONE saved variable, TwichUILoadTestDB, filled with SYNTHETIC market data in the Workshop's version-2 format by the Test Lab's
-- "Saved-data load test" group, so the client's loading of a large saved file can be timed without touching anyone's real data. It never
-- reads or writes TwichUIWorkshopDB, TwichUIDB or TwichUIDiagnosticsDB (tests/test_loadtest.lua scans this file for that).
--
-- WHAT IT RECORDS ABOUT ITS OWN LOADING (read by the Lab case loadtest.measure, which times C_AddOns.LoadAddOn around it):
--   fileAt / heapAtFile / dbAtFile          when this file started to run, the Lua heap then, and whether the saved variable already existed
--   loadedAt / heapAtLoaded / dbAtLoaded    the same at this addon's ADDON_LOADED
-- If the client runs an addon's files before it reads its saved variables (as other versions of the game do), dbAtFile is false, dbAtLoaded
-- true, and loadedAt - fileAt is the deserialization; if it reads them first, dbAtFile is true and the time sits before fileAt. The Lab
-- reports which one this client did; nothing here assumes it.
-- At PLAYER_LOGOUT it stamps meta.logoutAt = GetTime() (what the client then writes at logout includes this data).

local R = TwichUI
local LT = { NAME = "TwichUI_LoadTest", FORMAT = 1, STEP_MS = 4 }
R.LoadTest = LT

local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
LT.fileAt, LT.heapAtFile, LT.dbAtFile = clock and clock() or nil, collectgarbage("count"), TwichUILoadTestDB ~= nil

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= LT.NAME then return end
        LT.loadedAt, LT.heapAtLoaded, LT.dbAtLoaded = clock and clock() or nil, collectgarbage("count"), type(TwichUILoadTestDB) == "table"
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGOUT" then
        local db = TwichUILoadTestDB
        if type(db) == "table" and type(db.meta) == "table" and type(GetTime) == "function" then db.meta.logoutAt = GetTime() end
    end
end)

-- What the saved variable holds now (a copy of its meta), or nil
function LT.Meta()
    local db = TwichUILoadTestDB
    if type(db) ~= "table" or type(db.meta) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(db.meta) do if type(v) ~= "table" then out[k] = v end end
    return out
end

-- A generation job. spec = { items (1 .. 60000), preset (a word), days, make = function(i) -> itemEntry, distEntry or nil, h2 or nil, c2 or nil }.
-- The data is built into a NEW table; the saved variable is replaced only by the last step, so a stopped generation leaves the previous one.
-- job:Step(ms) works for about ms milliseconds (one item at a time) and returns true when finished; job.done / job.total say how far.
local Job = {}
Job.__index = Job

function LT.Begin(spec)
    if type(spec) ~= "table" or type(spec.make) ~= "function" then return nil, "nospec" end
    local n = tonumber(spec.items)
    if not n or n < 1 or n > 60000 or n ~= math.floor(n) then return nil, "items" end
    local market = { f = 3, scope = "full", realm = "LoadTest", side = "Synthetic", items = {}, dist = {}, h2 = {}, c2 = {} }
    return setmetatable({ spec = spec, total = n, done = 0, bytes = 0, entries = 0, market = market }, Job)
end

-- bytes one string adds to the saved file, roughly: the text, its key and the quoting ([12345] = "...",)
local function Cost(id, s) return #s + #tostring(id) + 8 end

function Job:Step(ms)
    local t0 = clock and clock()
    local m, make = self.market, self.spec.make
    while self.done < self.total do
        local i = self.done + 1
        local item, dist, h2, c2 = make(i)
        local id = 1000 + i
        if type(item) == "string" then m.items[id] = item self.bytes = self.bytes + Cost(id, item) end
        if type(dist) == "string" then m.dist[id] = dist self.bytes = self.bytes + Cost(id, dist) end
        if type(h2) == "string" then m.h2[id] = h2 self.bytes, self.entries = self.bytes + Cost(id, h2), self.entries + 1 end
        if type(c2) == "string" then m.c2[id] = c2 self.bytes = self.bytes + Cost(id, c2) end
        self.done = i
        if not t0 or clock() - t0 >= (ms or LT.STEP_MS) then break end
    end
    if self.done < self.total then return false end
    m.n = self.total
    TwichUILoadTestDB = { v = LT.FORMAT, meta = { items = self.total, preset = tostring(self.spec.preset or "custom"), days = tonumber(self.spec.days) or nil,
        bytes = self.bytes, h2items = self.entries, generatedAt = time and time() or nil, format = tonumber(self.spec.format) or nil }, market = m }
    return true
end

-- Empties the saved variable (the next logout writes a small file again)
function LT.Clear()
    TwichUILoadTestDB = { v = LT.FORMAT, meta = { cleared = time and time() or 0, items = 0, bytes = 0 } }
end
