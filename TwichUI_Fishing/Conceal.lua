-- TwichUI Fishing: concealing the minimap in Immersive Fishing Mode
-- Frame alpha can't hide the minimap: the engine draws its blips (the player's arrow, tracking dots, quest markers) with no
-- regard to the frame's alpha (EllesmereUI says so where it hides the map, EUI_Minimap_Lifecycle.lua: "Alpha is no stand-in:
-- engine-drawn blips ignore frame alpha"; its own idle states use a real Hide() for that reason). So the minimap is concealed
-- with the one thing the engine does respect, the frame's own Hide(), and everything parented to it (EllesmereUI parents its
-- buttons and border pieces to the map) goes with it and leaves no invisible clickable area behind.
--
-- Why Hide() and not moving the map off screen: moving needs the map's anchors saved and restored, and EllesmereUI re-anchors
-- it (and owns its saved position and Edit Mode / unlock layout), so a moved map would drift or fight it. Hide() touches no
-- anchor, no parent and no saved setting: EllesmereUI stays responsible for layout, and for whether the map is shown at all.
-- (The AzeriteUI changelog that describes moving the map off screen could not be read from here; this follows
-- EllesmereUI's own source, which shows Hide() removes the blips. Unverified in the real client.)
--
-- Ownership: while concealed the map's owner may call Show() or Hide() (EllesmereUI's visibility passes do). A post-hook on the
-- map's Show/Hide (installed once, inert while not concealed) re-hides at once after an owner's Show() and remembers what the
-- owner wanted; coming back, the map is shown only if its owner wants it shown. A map that was hidden to begin with (an
-- EllesmereUI visibility rule) is never shown by this file.
--
-- Combat: Show() and Hide() of the minimap are protected in combat on some clients. This file never calls them in combat. A
-- restoration that falls in combat waits for PLAYER_REGEN_ENABLED (one event, registered only while something waits), and
-- Fishing Mode's own combat exit tries first (a call the client refuses is noted, not retried in a loop).
-- Nothing is saved: a reload makes a new, shown map, which its owner then lays out as always.
--
--   C.On()         conceal (when the map exists, is shown and it is not combat); returns true when concealed
--   C.Off(force)   restore; returns true when the map is back (or was never concealed)
--   C.Reveal(on)   the reveal key: back while held, concealed again on release
--   C.State()      { concealed, revealed, waiting, ownerWants, present, refused }

local R = TwichUI
local F = R.Fishing
local C = {}
F.Conceal = C

local state = { concealed = false, revealed = false, waiting = false, ownerWants = true, refused = 0 }
local hooked, guard = false, false
local regen = false

local function Map()
    local m = rawget(_G, "Minimap")
    if type(m) == "table" and type(m.Show) == "function" and type(m.Hide) == "function" and type(m.IsShown) == "function" then return m end
    return nil
end

local function Shown(m)
    local ok, v = pcall(m.IsShown, m)
    return ok and F.Readable(v) == true
end

-- In combat only a map the client does not protect may be shown or hidden by addon code; a protected one waits for the
-- end of combat.
local function Blocked(m)
    if not F.InCombat() then return false end
    if type(m.IsProtected) ~= "function" then return true end
    local ok, p = pcall(m.IsProtected, m)
    return not ok or F.Readable(p) ~= false
end

-- A change the map's owner makes while it is concealed.
local function OnShow(m)
    if guard or not state.concealed then return end
    state.ownerWants = true
    if state.revealed or Blocked(m) then return end
    guard = true
    local ok = pcall(m.Hide, m)
    guard = false
    if not ok then state.refused = state.refused + 1; F.Note("conceal-refused", "Minimap Hide") end
end
local function OnHide()
    if guard or not state.concealed then return end
    state.ownerWants = false
end

local function Hook(m)
    if hooked or not hooksecurefunc then return hooked end
    local a = pcall(hooksecurefunc, m, "Show", OnShow)
    local b = pcall(hooksecurefunc, m, "Hide", OnHide)
    hooked = a and b
    return hooked
end

local function Do(m, fn)
    guard = true
    local ok = pcall(fn, m)
    guard = false
    if not ok then state.refused = state.refused + 1; F.Note("conceal-refused", "Minimap") end
    return ok
end

local function WaitForRegen()
    if regen then return end
    regen = true
    R:On("PLAYER_REGEN_ENABLED", C.OnRegen)
    state.waiting = true
end

function C.OnRegen()
    if regen then regen = false; R:Off("PLAYER_REGEN_ENABLED", C.OnRegen) end
    state.waiting = false
    if state.concealed and not state.revealed then C.Hold() end
    if not state.concealed then C.Finish() end
end

-- Puts the map as its owner wants it (after a concealment). Returns true when done.
function C.Finish()
    local m = Map()
    if not m then state.concealed, state.waiting = false, false return true end
    if state.ownerWants and not Shown(m) then
        if Blocked(m) then WaitForRegen(); return false end
        if not Do(m, m.Show) then return false end
    end
    state.waiting = false
    return true
end

-- Hides the map now (concealed and not revealed).
function C.Hold()
    local m = Map()
    if not m then return false end
    if Blocked(m) then WaitForRegen(); return false end
    if Shown(m) then return Do(m, m.Hide) end
    return true
end

function C.On()
    if state.concealed then return true end
    local m = Map()
    if not m or Blocked(m) then return false end
    if not Shown(m) then return false end   -- not shown to begin with (its owner's rule): left as it is
    Hook(m)
    state.ownerWants, state.revealed, state.concealed = true, false, true
    if not C.Hold() then state.concealed = false; return false end
    return true
end

function C.Off(force)
    if not state.concealed then return true end
    state.concealed, state.revealed = false, false
    local done = C.Finish()
    if not done and force then done = C.Finish() end
    return done
end

function C.Reveal(on)
    if not state.concealed then return false end
    on = on and true or false
    if on == state.revealed then return true end
    state.revealed = on
    local m = Map()
    if not m then return true end
    if on then
        if state.ownerWants and not Shown(m) then
            if Blocked(m) then WaitForRegen() else Do(m, m.Show) end
        end
    else
        C.Hold()
    end
    return true
end

function C.State()
    return { concealed = state.concealed, revealed = state.revealed, waiting = state.waiting, ownerWants = state.ownerWants,
        present = Map() ~= nil, refused = state.refused, hooked = hooked }
end
