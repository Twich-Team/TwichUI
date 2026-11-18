-- TwichUI: optional quest item sparkles. Forever's native loot effect is controlled by
-- outlineModeShowLootEffectWhenDisabled; graphics presets can reset it. The game chooses
-- the objects (including some quest NPCs), and removing a visible effect needs a full restart.
-- API reference: ForeverLootSparkles, https://github.com/svengabr/ForeverLootSparkles
-- This module changes only that CVar, preserving the player's outline and interact settings.

local R = TwichUI
local S = {}
R.QoLLootSparkles = S

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local WATCHED = { outlinemodeshowlooteffectwhendisabled = true, graphicsquality = true, raidgraphicsquality = true }
local listeners = {}
local timer, writing

local function CancelTimer()
    if timer then timer:Cancel(); timer = nil end
end

local function Listen(event, handler, on)
    if on and not listeners[event] then
        R:On(event, handler)
        listeners[event] = handler
    elseif not on and listeners[event] then
        R:Off(event, listeners[event])
        listeners[event] = nil
    end
end

local function Read()
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, CVAR)
    if ok and (value == "0" or value == "1") then return value end
end

local function Write(value)
    writing = true
    local ok, result = pcall(C_CVar.SetCVar, CVAR, value)
    writing = false
    return ok and result ~= false and Read() == value
end

local function Schedule(seconds)
    CancelTimer()
    timer = C_Timer.NewTimer(seconds, function()
        timer = nil
        S.Refresh()
    end)
end

local function OnLogin()
    S.Refresh()
    if R:Enabled("qolLootSparkles") then Schedule(5) end -- account-synced CVars can arrive after login
end

local function OnCVar(name)
    if not writing and type(name) == "string" and WATCHED[name:lower()] then Schedule(1) end
end

function S.Refresh()
    CancelTimer()
    local db = TwichUIDB
    if type(db) ~= "table" then return end
    local on = R:Enabled("qolLootSparkles")
    Listen("PLAYER_LOGIN", OnLogin, on)
    Listen("CVAR_UPDATE", OnCVar, on)

    -- A recovery record belongs to the game setting, outside profiles and shared settings.
    -- Only "0" can be a value we replaced. Never write damaged saved data to the client.
    local restore = db.lootSparklesWas == "0"
    if not restore then db.lootSparklesWas = nil end
    if InCombatLockdown() then
        Listen("PLAYER_REGEN_ENABLED", S.Refresh, on or restore)
        return
    end
    Listen("PLAYER_REGEN_ENABLED", S.Refresh, on)

    if on then
        if Read() == "0" then
            if Write("1") then db.lootSparklesWas = "0" end
        end
    elseif restore then
        local current = Read()
        -- Restore only our value. If the player or another addon changed it, keep theirs.
        if current == "0" or (current == "1" and Write("0")) then db.lootSparklesWas = nil end
    end
end

R:OnInit(S.Refresh)
