-- TwichUI Fishing: fading the interface around Fishing Mode (Stage 2)
-- While Fishing Mode is immersive the parts of the interface the player doesn't need for fishing fade out, and come back as
-- they were afterwards. Never UIParent itself, never anything that carries a warning, an error, a cast bar, loot or a window
-- the player opened.
--
-- What fades (config fade.*; each group its own switch):
--   bars      the game's action bars, stance and pet bars, the micro menu and bags bar, and the experience/reputation bars
--   units     the player, target, focus, pet and party frames (and EllesmereUI's unit frames by the names it gives them)
--   minimap   the minimap cluster
--   panels    (off by default) the quest tracker, the buff and debuff frames and the durability figure
--   extra     frames another addon draws that the player names (/tui fish fade add <FrameName>): an addon's own bars
--   notices   TwichUI's own notification cards, reminders and glows, through the Quiet screen's hold (QuietScreen.lua): a
--             hold of Fishing Mode's own, which never turns on, off or shows as the player's Quiet screen switch
-- A frame is faded only while it exists, is shown, can take an alpha and is not forbidden; one that is hidden is left alone.
--
-- Only the frame's own alpha is changed (SetAlpha): nothing is hidden, moved, re-parented, hooked or saved, and nothing in
-- another addon is called. Each frame's alpha is read first. Coming back, a frame returns to that alpha only if its alpha is
-- still the one Fishing Mode set: an addon (or the game) that changed it meanwhile wins, and the frame is left as they set it.
-- Fades are short (config: none with present.motion off) and run on one driver frame whose OnUpdate exists only while
-- something is moving. An alpha change is not a protected action, so putting things back works in combat too (unverified on
-- Forever: docs/fishing-feasibility.md).
--
-- Other addons. EllesmereUI replaces the game's bars and unit frames with its own; its unit frames are faded by name where
-- they exist, its bars are not (their names are not known here), and EllesmereUI's own mouse-over and combat fading still
-- decide when it changes them. Dialogue UI fades UIParent itself while a conversation is open and puts it back after: Fishing
-- Mode never touches UIParent, so the two never fight; its pieces simply fade with the rest of UIParent then.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Fa = {}
F.Fade = Fa

Fa.GROUPS = {
    bars = { "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame",
        "PossessActionBar", "PossessBarFrame", "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar", "MainMenuExpBar",
        "ReputationWatchBar", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager" },
    units = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame", "CompactPartyFrame",
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target", "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_Pet" },
    minimap = { "MinimapCluster" },
    panels = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame", "BuffFrame", "DebuffFrame", "DurabilityFrame" },
}
-- Never faded, whatever a list says: the game's root, and what carries warnings, errors, casts, loot and the player's windows.
Fa.NEVER = { UIParent = true, WorldFrame = true, UIErrorsFrame = true, RaidWarningFrame = true, RaidBossEmoteFrame = true,
    PlayerCastingBarFrame = true, CastingBarFrame = true, LootFrame = true, StaticPopup1 = true, GameTooltip = true,
    ChatFrame1EditBox = true, MirrorTimer1 = true }
Fa.DURATION = 0.4
Fa.QUIET_OWNER = "fishing"

local entries = {}          -- { frame, name, from, set, to, start, kept } for each frame Fishing Mode changed
local faded, revealed = false, false
local driver, moving = nil, false
Fa.steps = 0                -- alpha changes made (diagnostics, tests)

local function Usable(name)
    if Fa.NEVER[name] then return nil end
    local f = rawget(_G, name)
    if type(f) ~= "table" or f == rawget(_G, "UIParent") then return nil end
    if type(f.GetAlpha) ~= "function" or type(f.SetAlpha) ~= "function" then return nil end
    if f.IsForbidden and f:IsForbidden() then return nil end
    if f.IsShown and not f:IsShown() then return nil end
    return f
end

local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end

local function SetAlpha(e, a)
    local ok = pcall(e.frame.SetAlpha, e.frame, a)
    if ok then e.set = a; Fa.steps = Fa.steps + 1 else F.Note("fade-refused", e.name) end
    return ok
end

local function Duration()
    if S.Get("present.motion") == false then return 0 end
    if R.Enabled and R:Enabled("arrivalReducedMotion") then return 0 end
    return Fa.DURATION
end

local function Smooth(t) return t * t * (3 - 2 * t) end

local function Step()
    local now = F.Clock()
    local busy = false
    for _, e in ipairs(entries) do
        if e.to ~= nil and not e.kept then
            -- someone else changed it while it was moving: theirs wins, and it is left alone from now on
            local cur = e.frame:GetAlpha()
            if not Near(cur, e.set) then
                e.kept, e.to = true, nil
            else
                local d = e.duration or 0
                local t = d > 0 and math.min(1, (now - e.start) / d) or 1
                SetAlpha(e, e.origin + (e.to - e.origin) * Smooth(t))
                if t >= 1 then e.to = nil else busy = true end
            end
        end
    end
    return busy
end

local function Drive()
    if Step() then
        if not moving then
            moving = true
            if not driver and CreateFrame then driver = CreateFrame("Frame") end
            if driver then
                driver:SetScript("OnUpdate", function()
                    if not Step() then moving = false; driver:SetScript("OnUpdate", nil) end
                end)
            end
        end
    elseif moving and driver then
        moving = false
        driver:SetScript("OnUpdate", nil)
    end
end

-- Moves each entry from its current alpha towards target(e). instant: in one step.
local function Move(target, instant)
    local d = instant and 0 or Duration()
    local now = F.Clock()
    for _, e in ipairs(entries) do
        if not e.kept then
            e.origin, e.to, e.start, e.duration = e.set, target(e), now, d
        end
    end
    Drive()
end

-- Which frame names are wanted now: the switched-on groups, and the player's own list.
function Fa.Names()
    local names, seen = {}, {}
    local function Add(n) if not seen[n] then seen[n] = true; names[#names + 1] = n end end
    for _, group in ipairs({ "bars", "units", "minimap", "panels" }) do
        if S.Get("fade." .. group) then for _, n in ipairs(Fa.GROUPS[group]) do Add(n) end end
    end
    local extra = S.Get("fade.extra")
    if type(extra) == "table" then for _, n in ipairs(extra) do Add(n) end end
    return names
end

-- Fades what is wanted. Returns the number of frames faded.
function Fa.Apply(instant)
    if faded then return #entries end
    -- a fade back still moving is finished first, so each frame's alpha is read as it was before Fishing Mode
    if moving then Fa.Finish() end
    local alpha = S.Get("fade.alpha") or 0
    entries = {}
    for _, name in ipairs(Fa.Names()) do
        local f = Usable(name)
        if f then
            local a = f:GetAlpha()
            if type(a) == "number" and a > alpha + 0.01 then
                entries[#entries + 1] = { frame = f, name = name, from = a, set = a }
            end
        end
    end
    faded, revealed = true, false
    if S.Get("fade.notices") and R.QuietScreen and R.QuietScreen.Hold then R.QuietScreen.Hold(Fa.QUIET_OWNER, true) end
    Move(function() return alpha end, instant)
    return #entries
end

-- Everything back as it was (each frame whose alpha is still Fishing Mode's). force: back regardless (the player's own
-- recovery). instant: no fade.
function Fa.Restore(instant, force)
    if R.QuietScreen and R.QuietScreen.Hold then R.QuietScreen.Hold(Fa.QUIET_OWNER, false) end
    if not faded and #entries == 0 then return 0 end
    local n = 0
    for _, e in ipairs(entries) do
        if force then e.kept = false; e.set = e.frame:GetAlpha() end
        if not e.kept and not Near(e.frame:GetAlpha(), e.set) then e.kept = true end
        if not e.kept then n = n + 1 end
    end
    Move(function(e) return e.from end, instant or force)
    faded, revealed = false, false
    -- entries stay while their fade back is still moving; the next Apply starts a fresh list
    return n
end

-- The player looks at the interface for a moment (held key, or /tui fish reveal): everything comes back, and fades again
-- when they let go. Frames someone else changed meanwhile are left as they are.
function Fa.Reveal(on)
    if not faded then return false end
    on = on and true or false
    if on == revealed then return true end
    revealed = on
    local alpha = S.Get("fade.alpha") or 0
    if R.QuietScreen and R.QuietScreen.Hold and S.Get("fade.notices") then R.QuietScreen.Hold(Fa.QUIET_OWNER, not on) end
    Move(function(e) return on and e.from or alpha end)
    return true
end

function Fa.Faded() return faded end
function Fa.Revealed() return revealed end
function Fa.Moving() return moving end

function Fa.Status()
    local kept, list = 0, {}
    for _, e in ipairs(entries) do
        if e.kept then kept = kept + 1 end
        list[#list + 1] = e.name
    end
    return { faded = faded, revealed = revealed, frames = #entries, kept = kept, names = list, moving = moving,
        quiet = R.QuietScreen and R.QuietScreen.Holding and R.QuietScreen.Holding(Fa.QUIET_OWNER) or false }
end

-- Test support: finishes any fade at once.
function Fa.Finish()
    for _, e in ipairs(entries) do if e.to ~= nil then e.duration = 0 end end
    Step()
    if driver then driver:SetScript("OnUpdate", nil) end
    moving = false
end
