-- TwichUI: Hazard alerts, the controller
-- Turns the resolved rules (Rules.lua) into aura sounds the game itself plays (C_UnitAuras.AddAuraSound), and keeps
-- them in step with the settings. There is no combat-log handler, no OnUpdate and no timer here: once a sound is
-- registered the game plays it, so nothing of ours runs when a hazard happens. The only event this listens to is
-- ADDON_RESTRICTION_STATE_CHANGED, and only while the feature is on.
--
-- What that means, stated plainly:
--   * The game decides when a sound plays, and stops it after five seconds. The only per-rule control is the game's
--     throttleSeconds (0 to 5). There is no way to rank two sounds, hold one back for another, or know a sound played,
--     so there is no alert queue, no priority and no on-screen alert tied to a real hazard.
--   * Registering and removing may be refused while the game's addon restrictions are active (combat, an encounter, a
--     challenge mode, a PvP match, a restricted map). Then the change waits and is made when they lift.
--   * Nothing here is verified in the game; docs/hazard-alerts.md lists the checks.
-- The preview plays a sound once through PlaySoundFile. It registers nothing and touches no rule.

local R = TwichUI
local HZ, HR = R.Hazard, R.HazardRules
local A = {}
R.HazardAlerts = A

local registered = {}    -- [key] = { handle, sig }: what is registered with the game right now
local stale = {}         -- handles that must be removed but could not be yet
local pending = false    -- a change is waiting for the restrictions to lift
local evf, watching
local stats = { registrations = 0, refused = 0, removed = 0, deferred = 0, tests = 0, testsRefused = 0 }
local missing = {}       -- [category] = true: the chosen sound could not be found or is not a file the game can use
local lastDesired = 0

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- What the client offers
---------------------------------------------------------------------------
local function Triggers() return Enum and Enum.UnitAuraSoundTrigger end

function A.Available()
    return C_UnitAuras ~= nil and C_UnitAuras.AddAuraSound ~= nil and C_UnitAuras.RemoveAuraSound ~= nil and Triggers() ~= nil
end

-- True while any of the game's addon restrictions is being enforced. Without the API there is nothing to wait for.
local function Restricted()
    local RA, T = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    if not (RA and RA.IsAddOnRestrictionActive and T) then return false end
    for _, value in pairs(T) do
        if Plain(RA.IsAddOnRestrictionActive(value)) == true then return true end
    end
    return false
end
A.Restricted = Restricted

function A.GtfoActive()
    return C_AddOns ~= nil and C_AddOns.IsAddOnLoaded ~= nil and C_AddOns.IsAddOnLoaded("GTFO") == true
end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
-- What the game is given for a category: nil when the category has no sound ("None"), else a table with the file name or
-- the file ID. Resolved when the settings change, never when a hazard happens.
local function SoundFor(category)
    local name = HZ.CategorySound(category)
    if name == HZ.NONE then return nil, "none" end
    local path = R:ResolveSound(name)
    if type(path) == "number" and path > 0 then return { id = path } end
    if type(path) == "string" and path ~= "" then return { file = path } end
    return nil, "missing"
end
A.SoundFor = SoundFor

local function Signature(rule, sound)
    return table.concat({ rule.spell, rule.trigger, rule.throttle, sound.file or "", sound.id or 0, HZ.Get("channel") }, "|")
end

---------------------------------------------------------------------------
-- Registering
---------------------------------------------------------------------------
local function Remove(handle)
    local ok = pcall(C_UnitAuras.RemoveAuraSound, handle)
    if ok then stats.removed = stats.removed + 1 end
    return ok
end

local function Add(rule, sound)
    local T = Triggers()
    local trigger = T[HZ.TRIGGER[rule.trigger][3]]
    if trigger == nil then return nil end
    local info = { unitToken = "player", spellID = rule.spell, outputChannel = HZ.Get("channel"), throttleSeconds = rule.throttle }
    if sound.id then info.soundFileID = sound.id else info.soundFileName = sound.file end
    local ok, handle = pcall(C_UnitAuras.AddAuraSound, trigger, info)
    if ok and type(handle) == "number" then return handle end
    return nil
end

local worldSeen = false

-- Listens only while the feature is on: for the restrictions lifting (to finish a change that had to wait) and, once,
-- for the world loading (sounds other addons add to LibSharedMedia are not there yet when TwichUI starts).
local function SyncEvents()
    local want = R:Enabled("hazardAlerts") or pending   -- (off with a removal still waiting: hear the restriction lift)
    if want and not watching then
        evf = evf or CreateFrame("Frame")
        evf:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        if not worldSeen then evf:RegisterEvent("PLAYER_ENTERING_WORLD") end
        evf:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                worldSeen = true
                evf:UnregisterEvent("PLAYER_ENTERING_WORLD")
                A.Refresh()
            elseif pending then
                A.Refresh()
            end
        end)
        watching = true
    elseif not want and watching then
        evf:UnregisterAllEvents()
        evf:SetScript("OnEvent", nil)
        watching = false
    end
end

-- Registers exactly what the settings and rules say, and removes the rest. Safe to call at any time and as often as
-- you like: a call that changes nothing makes no game call. The one entry point.
local Apply

function A.Refresh()
    Apply()
    SyncEvents()
end

function Apply()
    local enabled = R:Enabled("hazardAlerts")
    if not enabled and next(registered) == nil and #stale == 0 then pending = false; lastDesired = 0; return end
    if not A.Available() then pending = false; return end

    local desired = {}
    if enabled then
        desired = HR.Resolve(HZ.List(), HZ.BuiltinOff(), HZ.CategoryOn, function(category) return (SoundFor(category)) ~= nil end)
    end
    for category in pairs(HZ.CATEGORY) do
        local _, why = SoundFor(category)
        missing[category] = (enabled and HZ.CategoryOn(category) and why == "missing") or nil
    end
    lastDesired = #desired

    -- what would change
    local want, work = {}, false
    for _, rule in ipairs(desired) do
        local sound = SoundFor(rule.category)
        local sig = Signature(rule, sound)
        want[rule.key] = { rule = rule, sound = sound, sig = sig }
        local have = registered[rule.key]
        if not have or have.sig ~= sig then work = true end
    end
    for key in pairs(registered) do if not want[key] then work = true end end
    if #stale > 0 then work = true end
    if not work then pending = false; return end

    if Restricted() then
        if not pending then stats.deferred = stats.deferred + 1 end
        pending = true
        return
    end
    pending = false

    for i = #stale, 1, -1 do
        if Remove(stale[i]) then table.remove(stale, i) end
    end
    for key, entry in pairs(registered) do
        local w = want[key]
        if not w or w.sig ~= entry.sig then
            if not Remove(entry.handle) then stale[#stale + 1] = entry.handle end
            registered[key] = nil
        end
    end
    for key, w in pairs(want) do
        if not registered[key] then
            local handle = Add(w.rule, w.sound)
            if handle then
                registered[key] = { handle = handle, sig = w.sig }
                stats.registrations = stats.registrations + 1
            else
                stats.refused = stats.refused + 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- The preview: one sound, once, through the game's ordinary sound call. Registers nothing, changes no rule.
---------------------------------------------------------------------------
-- Returns true when the game accepted it; false, why ("none", "missing" or "unavailable") otherwise.
function A.TestSound(category)
    if not HZ.CATEGORY[category] then return false, "category" end
    local sound, why = SoundFor(category)
    if not sound then return false, why end
    if not PlaySoundFile then return false, "unavailable" end
    local ok, played = pcall(PlaySoundFile, sound.id or sound.file, HZ.Get("channel"))
    stats.tests = stats.tests + 1
    if ok and played ~= false then return true end
    stats.testsRefused = stats.testsRefused + 1
    return false, "refused"
end

---------------------------------------------------------------------------
-- Status, for settings, /tui diagnostics and the tests: plain values
---------------------------------------------------------------------------
function A.Snapshot()
    local n = 0
    for _ in pairs(registered) do n = n + 1 end
    return { enabled = R:Enabled("hazardAlerts"), available = A.Available(), registered = n, wanted = lastDesired, pending = pending,
        restricted = A.Available() and Restricted() or false, watching = watching == true, stale = #stale,
        registrations = stats.registrations, refused = stats.refused, removed = stats.removed, deferred = stats.deferred,
        tests = stats.tests, testsRefused = stats.testsRefused, missingSound = next(missing) ~= nil,
        builtin = #HR.Builtin(), custom = HZ.Count(), gtfo = A.GtfoActive() }
end

function A.MissingSound(category) return missing[category] == true end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
HZ.Subscribe(function() if R:Enabled("hazardAlerts") or next(registered) ~= nil or #stale > 0 then A.Refresh() end end)

R:OnInit(function() A.Refresh() end)
R.Profiles.OnApply("layout", "hazard", function() A.Refresh() end)
