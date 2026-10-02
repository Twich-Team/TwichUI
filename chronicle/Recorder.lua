-- TwichUI: Journey Chronicle, automatic entries
-- Writes entries for the moments the player chose to record. It never looks
-- back: only things that happen while tracking is on are written. Events are
-- registered only while they're switched on and removed again when they're
-- turned off. Nothing is announced in chat or shown as a popup.

local R = TwichUI
local C = R.Chronicle
local Rec = {}
R.ChronicleRecorder = Rec

local lastZone               -- the zone we last saw, so arriving isn't recorded at login
local active = {}            -- [event] = handler, while registered

local function On(key) return R:Enabled("chronicle") and R:Enabled(key) end

local function Changed()
    if R.ChronicleWindow then R.ChronicleWindow:Refresh() end
end

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    return text
end

local function OnLevelUp(level)
    if not On("chronicleLevels") or type(level) ~= "number" then return end
    if C.Add("level", { title = ("Reached level %d"):format(level), level = level, zone = C.CurrentZone() }) then Changed() end
end

local function OnZone()
    if not On("chronicleZones") then return end
    local zone = C.CurrentZone()
    if not zone or zone == lastZone then return end
    lastZone = zone
    if C.Add("zone", { title = "Arrived in " .. zone, zone = zone }) then Changed() end
end

-- Logging in or reloading isn't arriving anywhere. Other loading screens are
-- left to the zone event, so walking into a dungeon is still recorded.
local function OnEnteringWorld(isLogin, isReload)
    if isLogin or isReload then lastZone = C.CurrentZone() end
end

local function OnEncounterEnd(_, name, _, _, success)
    if not On("chronicleBosses") or success ~= 1 then return end
    name = Plain(name)
    if not name or name == "" then return end
    if C.Add("boss", { title = "Defeated " .. name, zone = C.CurrentZone() }) then Changed() end
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Registers exactly the events that are switched on. Safe to call any time.
function Rec.Refresh()
    local master = R:Enabled("chronicle")
    local zones = master and R:Enabled("chronicleZones")
    if zones and not active.ZONE_CHANGED_NEW_AREA then lastZone = C.CurrentZone() end
    Want("PLAYER_LEVEL_UP", OnLevelUp, master and R:Enabled("chronicleLevels"))
    Want("ZONE_CHANGED_NEW_AREA", OnZone, zones)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, zones)
    Want("ENCOUNTER_END", OnEncounterEnd, master and R:Enabled("chronicleBosses"))

    -- Say in the journal when tracking started (and when it started again).
    local rec = C.Record()
    if master and not rec.tracking then
        local first = true
        for _, e in ipairs(rec.entries) do if e.kind == "start" then first = false break end end
        C.Add("start", { title = first and "Chronicle begun" or "Tracking resumed",
            note = "From here on, TwichUI writes the moments you chose to keep. Nothing from before is added." })
        rec.tracking = true
    elseif not master and rec.tracking then
        rec.tracking = false
    end
    Changed()
end

R:OnInit(Rec.Refresh)
