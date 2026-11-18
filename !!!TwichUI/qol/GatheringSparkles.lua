-- Optional herb/ore overlays on Forever's single soft interaction target.
-- Uses the documented cursor/nameplate APIs; never interacts, casts or changes bindings.
-- The native quest sparkle is independent. Original implementation; no external addon code/assets.
local R = TwichUI
local G = { stats = { frames = 0, shown = 0, timers = 0, listeners = 0, units = 0, cvars = 0 } }
R.QoLGathering = G
local Perf = R.Perf
local SOFT = "softinteract"
local SPECS = {
    SoftTargetInteract = { "3", 3 }, SoftTargetNameplateInteract = { "0", 1 },
    SoftTargetInteractRange = { "15", 10000 }, SoftTargetInteractArc = { "2", 2 },
    SoftTargetInteractOnlyInRange = { "0", 1 }, SoftTargetIconGameObject = { "1", 1 },
}
local ORDER = { "SoftTargetInteractRange", "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange",
    "SoftTargetIconGameObject", "SoftTargetNameplateInteract", "SoftTargetInteract" }
local COMPETITORS = { "Lueur", "LueurStill", "LueurLegacy", "ForeverLootSparkles_Coloring" }
local units, cursors, listening = {}, {}, {}
local ticker, probe, paused, blocked, working, writing, leaving
local herbs, ore = false, false
G.status = "off"

function G.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
local Safe = G.Safe
local function Combat() return InCombatLockdown() end
local function Read(name) return C_CVar and Safe(C_CVar.GetCVar, name) end
local function Valid(name, value)
    if type(value) ~= "string" or #value > 12 then return false end
    local n = tonumber(value)
    return n ~= nil and n == n and n >= 0 and n <= SPECS[name][2] and n % 1 == 0
end
local function Record()
    local t = TwichUIDB and TwichUIDB.gatheringSparklesCVars
    return type(t) == "table" and t or nil
end
local function CountRecord()
    local t, n = Record(), 0
    if t then for name in pairs(SPECS) do if t[name] then n = n + 1 end end end
    G.stats.cvars = n
end
local function Write(name, value)
    if Combat() then return false end
    writing = true
    local ok = Safe(C_CVar and C_CVar.SetCVar, name, value)
    writing = false
    return ok ~= false and Read(name) == value
end
local function Owned(name, value)
    if Combat() then return false end
    local current = Read(name)
    if not Valid(name, current) then return false end
    local t = Record()
    if not t then t = {}; TwichUIDB.gatheringSparklesCVars = t end
    local entry = t[name]
    if entry then
        if type(entry) ~= "table" or not Valid(name, entry.was) or not Valid(name, entry.set) then return false end
        if current ~= entry.set then blocked = "changed"; return false end
    else
        entry = { was = current, set = current }
        t[name] = entry
        CountRecord()
    end
    if current == value then return true end
    entry.set = value -- persist recovery before the synchronous CVAR_UPDATE callback
    return Write(name, value)
end
local function Restore()
    local t = Record()
    if not t or Combat() then return end
    for _, name in ipairs({ "SoftTargetInteract", unpack(ORDER, 1, 5) }) do
        local entry = t[name]
        if entry then
            if type(entry) ~= "table" or not Valid(name, entry.was) or not Valid(name, entry.set) then
                t[name] = nil
            else
                local current = Read(name)
                if current ~= nil and (current ~= entry.set or current == entry.was or Write(name, entry.was)) then
                    t[name] = nil -- preserve an external change; restore only the value we still own
                end
            end
        end
    end
    if next(t) == nil then TwichUIDB.gatheringSparklesCVars = nil end
    CountRecord()
end
local function Hide() if G.Display then G.Display.Hide() end end
local function StopTimer()
    if ticker then ticker:Cancel(); ticker = nil end
    G.stats.timers = 0
end
local function Conflict()
    local api = C_AddOns
    if not api then return nil end
    for _, name in ipairs(COMPETITORS) do
        if Safe(api.IsAddOnLoaded, name) then return name end
    end
    if Safe(api.IsAddOnLoaded, "ForeverLootSparkles") then
        local version = Safe(api.GetAddOnMetadata, "ForeverLootSparkles", "Version")
        if type(version) ~= "string" or version:match("^1%.") then return "ForeverLootSparkles" end
    end
end
local function Available()
    return C_CVar and C_CVar.GetCVar and C_CVar.SetCVar and C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and SetUnitCursorTexture and UnitIsGameObject and C_Timer and C_Timer.NewTicker and UIParent
end
local function Position()
    local ok, y, x
    if UnitPosition then ok, y, x = pcall(UnitPosition, "player") end
    if ok and type(y) == "number" and type(x) == "number"
        and not (issecretvalue and (issecretvalue(y) or issecretvalue(x))) then return y, x end
end
local function Pause()
    Hide()
    if not paused then
        local y, x = Position()
        paused = { at = GetTime(), y = y, x = x }
    end
    Owned("SoftTargetNameplateInteract", "0")
    Owned("SoftTargetInteract", "0")
end
local function Moved()
    local y, x = Position()
    if y and paused.y then return (y - paused.y)^2 + (x - paused.x)^2 >= 25 end
    return GetTime() - paused.at >= 3
end
local function Probe()
    if probe then return end
    probe = UIParent:CreateTexture(nil, "BACKGROUND")
    probe:Hide()
    for _, kind in ipairs({ { "GatherHerbs", "herb" }, { "Mine", "ore" } }) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local path = "Interface\\Cursor\\" .. prefix .. kind[1]
            local id = Safe(GetFileIDFromPath, path) or Safe(GetFileIDFromPath, path .. ".blp")
            if type(id) == "number" then cursors[id] = { kind[2], prefix ~= "" } end
        end
    end
end
local function Cursor(value)
    if type(value) == "number" then
        local hit = cursors[value]
        if hit then return hit[1], hit[2] end
    elseif type(value) == "string" then
        local s = value:lower()
        local kind = s:find("gather", 1, true) and "herb" or s:find("mine", 1, true) and "ore"
        if kind then return kind, s:find("unable", 1, true) ~= nil end
    end
end
local function Classify()
    Probe()
    if Safe(SetUnitCursorTexture, probe, SOFT, nil, true, true) ~= true then return nil end
    local kind, locked = Cursor(Safe(probe.GetTexture, probe))
    if not kind then kind, locked = Cursor(Safe(probe.GetAtlas, probe)) end
    return kind, locked
end
local function Plate()
    local plate = Safe(C_NamePlate.GetNamePlateForUnit, SOFT)
    if plate then return plate end
    local guid = Safe(UnitGUID, SOFT)
    for unit in pairs(units) do
        if Safe(UnitIsUnit, unit, SOFT) == true or (guid and Safe(UnitGUID, unit) == guid) then
            plate = Safe(C_NamePlate.GetNamePlateForUnit, unit)
            if plate then return plate end
        end
    end
end
local function TrackUnit(unit)
    if type(unit) == "string" and not (issecretvalue and issecretvalue(unit))
        and unit:match("^nameplate%d+$") and not units[unit] and G.stats.units < 64 then
        units[unit] = true; G.stats.units = G.stats.units + 1
    end
end
local function SeedPlates()
    local plates = C_NamePlate and Safe(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then return end
    for i = 1, math.min(#plates, 64) do
        local plate = plates[i]
        if plate and not (issecretvalue and issecretvalue(plate)) then TrackUnit(plate.namePlateUnitToken) end
    end
end
local function Evaluate()
    if leaving or not (herbs or ore) or blocked or G.conflict or not Available() then Hide(); return end
    if Combat() then Hide(); G.status = "combat"; return end
    if paused then
        if not Moved() then Hide(); G.status = "unit"; return end
        paused = nil
    end
    -- Observe a living target before enabling targeting again. No identity values are compared.
    if Safe(UnitIsGameObject, SOFT) ~= true and Safe(UnitExists, SOFT) == true
        and Safe(UnitIsDead, SOFT) ~= true then Pause(); G.status = "unit"; return end
    for name in pairs(SPECS) do
        if not Valid(name, Read(name)) then Hide(); G.status = "unavailable"; return end
    end
    for _, name in ipairs(ORDER) do
        if name ~= "SoftTargetNameplateInteract" and not Owned(name, SPECS[name][1]) then
            Hide(); G.status = blocked or "unavailable"; return
        end
    end
    if Safe(UnitIsGameObject, SOFT) ~= true and Safe(UnitExists, SOFT) == true
        and Safe(UnitIsDead, SOFT) ~= true then Pause(); G.status = "unit"; return end
    if Safe(UnitIsGameObject, SOFT) ~= true then
        G.status = Owned("SoftTargetNameplateInteract", "0") and "ready" or "unavailable"
        Hide(); return
    end
    local kind, locked = Classify()
    if not ((kind == "herb" and herbs) or (kind == "ore" and ore)) then
        G.status = Owned("SoftTargetNameplateInteract", "0") and "ready" or "unavailable"
        Hide(); return
    end
    if not Owned("SoftTargetNameplateInteract", "1") then Hide(); G.status = "unavailable"; return end
    local plate = Plate()
    if plate then G.Display.Show(plate, kind, locked) else Hide() end
    G.status = "ready"
end
function G.Poll()
    if working or writing then return end
    working = true
    local ok, err = pcall(Perf.Call, "gathering.evaluate", Evaluate)
    working = false
    if not ok then StopTimer(); Hide(); R.Fault("gathering.evaluate", err) end
    if blocked then StopTimer(); Hide(); Restore(); G.status = blocked end
    if G.status == "unavailable" then StopTimer(); Hide(); Restore() end
end
local HANDLERS = {}
local function Listen(on)
    for event, handler in pairs(HANDLERS) do
        local want = on or (Record() and (event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"))
        if want and not listening[event] then
            R:On(event, handler); listening[event] = true; G.stats.listeners = G.stats.listeners + 1
        elseif not want and listening[event] then
            R:Off(event, handler); listening[event] = nil; G.stats.listeners = G.stats.listeners - 1
        end
    end
end
local function ClearUnits()
    for unit in pairs(units) do units[unit] = nil end
    G.stats.units = 0
end
local function Refresh()
    local h, o = R:Enabled("qolHerbSparkles") == true, R:Enabled("qolOreSparkles") == true
    if h ~= herbs or o ~= ore then blocked = nil; paused = nil end
    herbs, ore = h, o
    G.conflict = Conflict()
    if not (h or o) or G.conflict or blocked or not Available() or leaving then
        StopTimer(); Hide(); Restore(); ClearUnits()
        G.status = G.conflict and "conflict" or blocked or ((h or o) and "unavailable" or "off")
    else
        if not ticker then
            SeedPlates() -- one bounded snapshot; nameplate events maintain it afterward
            ticker = C_Timer.NewTicker(0.2, G.Poll)
            G.stats.timers = 1
        end
        G.Poll()
    end
    Listen((h or o) and not leaving)
end
function G.Refresh() return Perf.Call("gathering.refresh", Refresh) end
HANDLERS.PLAYER_LOGIN = G.Refresh
HANDLERS.PLAYER_ENTERING_WORLD = function() leaving = false; G.Refresh() end
HANDLERS.PLAYER_REGEN_ENABLED = function() paused = nil; G.Refresh() end
HANDLERS.ADDON_LOADED = G.Refresh
HANDLERS.PLAYER_REGEN_DISABLED = function()
    -- A client may already be locked by this event. Never bypass that restriction.
    -- Hide immediately; return owned settings at the next permitted opportunity.
    Hide()
    if (herbs or ore) and not G.conflict and not blocked and Available() then Pause(); G.status = "combat" end
end
HANDLERS.PLAYER_SOFT_INTERACT_CHANGED = G.Poll
HANDLERS.NAME_PLATE_UNIT_ADDED = function(unit)
    TrackUnit(unit)
    G.Poll()
end
HANDLERS.NAME_PLATE_UNIT_REMOVED = function(unit)
    if not (issecretvalue and issecretvalue(unit)) and units[unit] then units[unit] = nil; G.stats.units = G.stats.units - 1 end
    Hide(); G.Poll()
end
HANDLERS.CVAR_UPDATE = function(name)
    if writing or working or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
    local t = Record()
    if t then
        for key in pairs(SPECS) do
            local entry = t[key]
            if key:lower() == name:lower() and type(entry) == "table" and Read(key) ~= entry.set then
                blocked = "changed"; G.Refresh(); return
            end
        end
    end
end
HANDLERS.PLAYER_LOGOUT = function()
    leaving = true; StopTimer(); Hide(); Restore(); Listen(false)
end
local STATUS = {
    off = "Off.", ready = "Ready: highlights one nearby gathering target at a time.",
    combat = "Paused during combat. Pending setting changes wait until combat ends.",
    unit = "Paused near a character. Move a few yards to resume.",
    changed = "Paused after an interaction setting changed elsewhere. Switch the gathering options off and on to resume.",
    unavailable = "This client could not provide the required interaction settings or APIs.",
}
function G.Status()
    if G.conflict then return "Paused while " .. G.conflict .. " is loaded; use one gathering highlight addon at a time." end
    return STATUS[G.status] or STATUS.unavailable
end
for _, entry in ipairs({ { "frames", "pool" }, { "shown", "state" }, { "timers", "state" },
    { "listeners", "listeners" }, { "units", "cache" }, { "cvars", "state" } }) do
    local key = entry[1]
    Perf.Gauge("gathering." .. key, { label = "Gathering sparkles: " .. key, kind = entry[2], group = "qol", unit = "count",
        read = function() return G.stats[key] end })
end
R:OnInit(G.Refresh)
