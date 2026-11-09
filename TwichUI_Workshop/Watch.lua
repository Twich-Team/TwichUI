-- TwichUI Workshop: remembering recipes while the window is closed
-- Once the Workshop addon is loaded (it is load on demand: nothing here exists at login), the player's own professions are read when
-- one is opened or its recipe list changes, even with the Workshop window hidden, so the recipes are remembered (Known.lua) without
-- opening the window first. While the window is shown it does this itself (Window.lua), so this stays out of its way.
--
-- Reads only (Observe.Read: the player's own open profession, never a link, a guild or an NPC; Blizzard's filters are never changed);
-- one small event frame, a burst of events becoming one read; it never opens a profession. After a read the recipes' details are read in
-- small batches (Session.FillSome), then what was held in memory is let go again: it is saved, and comes back from there when needed.

local R = TwichUI
local W = R.Workshop
local S = W.Session
local Wt = {}
W.Watch = Wt

local SETTLE = 0.5
local BATCH = 120
local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "PLAYER_REGEN_ENABLED" }

local frame
local pending = false
local token = 0
Wt.reads = 0

local function WindowShown() return W.Window ~= nil and W.Window.IsShown() end

-- Reads the open profession now (unless the window is shown and does it), then its recipes' details a batch at a time
function Wt.Run()
    if WindowShown() then return false end
    token = token + 1
    local mine = token
    local ok = R.Perf.Call("workshop.read", S.Observe)
    if not ok then return false end
    Wt.reads = Wt.reads + 1
    local function Step()
        if mine ~= token then return end
        if WindowShown() then return end   -- the window took over (its own Prepare finishes the reading)
        local left = S.FillSome(BATCH)
        if left > 0 then C_Timer.After(0, Step) else S.Reset() end   -- everything is kept: let go of the copy in memory
    end
    Step()
    return true
end

function Wt.Request()
    if pending then return end
    pending = true
    C_Timer.After(SETTLE, function()
        pending = false
        Wt.Run()
    end)
end

function Wt.Start()
    if frame or not CreateFrame then return end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function() Wt.Request() end)
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    Wt.Request()   -- a profession that is already open when the addon loads
end

function Wt.Events() return frame and #EVENTS or 0 end
Wt.Start()
