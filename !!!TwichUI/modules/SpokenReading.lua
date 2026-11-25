-- TwichUI: Spoken's "What Spoken reads" switches, as one
-- The Spoken addon (a separate addon, optional) lists what it reads aloud on its settings page: quests, gossip, places,
-- readables, and any other module that registered with it. Each has its own switch. This file turns all of them on or off
-- together for the TwichUI data bar entry's menu (modules/SettingsBrokerMenu.lua, the "Narrate quests" row).
--
-- It only calls Spoken's public API (Spoken:IsCompatible, IterateSources, IsPartOn, SetPartOn, RegisterCallback). The
-- switches are Spoken's own, kept in Spoken's profile like any change made on its page, so they persist and follow its
-- profiles; TwichUI saves nothing. Nothing here is secure, so it works in combat.
--
-- Spoken is not a dependency. It loads after TwichUI, so it is looked up live each time and nothing is cached: with it
-- missing, disabled or too old to have these calls, Available() is false and the menu has no row.
--
--   S.Available()   true when Spoken is loaded, speaks API 1, has the calls above and has at least one part installed
--   S.State()       "on" (every installed part on), "off" (every one off), "some" (mixed, as when the player turned one
--                   off on Spoken's page), or nil when Available() is false
--   S.Set(on)       turns every installed part on or off through Spoken:SetPartOn, touching only those that differ;
--                   returns false when Spoken is unavailable. A part that fails is reported and the rest still change.
--   S.Watch()       once per Spoken: listens for Spoken's PART_SWITCHED, so S.OnChange fires when the player changes a part
--                   on Spoken's page. Called by the menu when it opens (Spoken may not have existed at TwichUI's load).
--   S.OnChange(fn)  fn() after any part switched (once per function; a function that fails is reported, the rest run)

local R = TwichUI
local S = {}
R.SpokenReading = S

local listeners = {}
local watching       -- the Spoken table already listened to, so a second call does nothing

local function Api()
    local sp = _G.Spoken
    if type(sp) ~= "table" then return end
    if type(sp.IsCompatible) ~= "function" or not sp:IsCompatible(1) then return end
    if type(sp.IterateSources) ~= "function" or type(sp.IsPartOn) ~= "function"
        or type(sp.SetPartOn) ~= "function" then return end
    return sp
end

-- The keys of the parts installed, in Spoken's own order.
local function Keys(sp)
    local keys = {}
    for key in sp:IterateSources() do keys[#keys + 1] = key end
    return keys
end

function S.Available()
    local sp = Api()
    return sp ~= nil and #Keys(sp) > 0
end

function S.State()
    local sp = Api()
    if not sp then return nil end
    local keys = Keys(sp)
    if #keys == 0 then return nil end
    local onCount = 0
    for _, key in ipairs(keys) do
        if sp:IsPartOn(key) then onCount = onCount + 1 end
    end
    if onCount == #keys then return "on" end
    if onCount == 0 then return "off" end
    return "some"
end

function S.Set(on)
    local sp = Api()
    if not sp then return false end
    on = on and true or false
    for _, key in ipairs(Keys(sp)) do
        if (sp:IsPartOn(key) and true or false) ~= on then
            local ok, err = pcall(sp.SetPartOn, sp, key, on)
            if not ok then
                if R.Fault then R.Fault("spoken reading", err) else geterrorhandler()(err) end
            end
        end
    end
    return true
end

function S.OnChange(fn)
    if type(fn) ~= "function" then return end
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end

local function Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then
            if R.Fault then R.Fault("spoken reading", err) else geterrorhandler()(err) end
        end
    end
end

function S.Watch()
    local sp = Api()
    if not sp or watching == sp or type(sp.RegisterCallback) ~= "function" then return end
    watching = sp
    sp:RegisterCallback("PART_SWITCHED", Changed)
end
