-- TwichUI: Quiet screen
-- One temporary switch for when the player is relaxing and doesn't want anything on the screen competing for attention.
-- While it is on, the things TwichUI puts up by itself stay away: the notification cards (zone, training, friend login,
-- Welcome Back, party death, the Cozy Sleeping Bag offer), Reminders and their sounds, action bar glows and their
-- messages and sounds, the Healer Watch panel, and Return the Favor's list. Each of those asks Q.On() at the place where
-- it decides to draw (a surface that is a window or a bar the player opened, or that stays on screen as part of the
-- interface, is not one of them), and is told through Q.OnChange when the switch moves.
--
-- It is not a setting. Nothing is saved: it starts off at every login and reload, and it is the player's to turn on and
-- off from the TwichUI data bar entry's menu (modules/SettingsBrokerMenu.lua). Turning it on puts away what is up;
-- turning it off brings back what is still true (a reminder whose condition holds, a glow still wanted) and nothing
-- that happened meanwhile: a card for an event during the quiet is not shown afterwards. It prints nothing in chat.
-- Settings previews are the player asking to see something, so they ignore it.
--
-- A feature may also hold the screen quiet for a while (TwichUI Fishing's Fishing Mode does, while the player fishes with it
-- on). A hold is not the player's switch: it never turns that on or off, nothing is saved, and the data bar shows and toggles
-- the player's own switch only. The screen is quiet while the player's switch is on or any hold is.
--
--   Q.On()           true while the screen is quiet (the player's switch, or a feature's hold)
--   Q.Player()       true while the player's own switch is on
--   Q.Set(on)        turns the player's switch on or off (true/false); the same state again does nothing
--   Q.Toggle()       the player's switch the other way; returns its new state
--   Q.Hold(owner, on) a feature (owner: a short string) holds the screen quiet, or lets go; the same state again does nothing
--   Q.Holding(owner) true while that owner holds it
--   Q.OnChange(fn)   fn(on) after the quiet changed (once per function); a function that fails is reported and the rest run
--   Q.Snapshot()     { on = bool, player = bool, holds = n, changes = n } for /tui diagnostics: counts only

local R = TwichUI
local Q = {}
R.QuietScreen = Q

local on = false
local changes = 0
local listeners = {}
local holds = {}         -- [owner] = true

local function Held() return next(holds) ~= nil end
local function Quiet() return on or Held() end

function Q.On() return Quiet() end
function Q.Player() return on end
function Q.Holding(owner) return holds[owner] == true end

function Q.OnChange(fn)
    if type(fn) ~= "function" then return end
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end

-- Listeners hear a change of the quiet; a change of the player's own switch is told too (the data bar menu shows it), with
-- the quiet as it is.
local function Changed(before, player)
    local now = Quiet()
    if now == before and not player then return end
    changes = changes + 1
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, now)
        if not ok then
            if R.Fault then R.Fault("quiet screen", err) else geterrorhandler()(err) end
        end
    end
end

function Q.Set(value)
    value = value and true or false
    if value == on then return end
    local before = Quiet()
    on = value
    Changed(before, true)
end

function Q.Toggle()
    Q.Set(not on)
    return on
end

function Q.Hold(owner, value)
    if type(owner) ~= "string" or owner == "" then return end
    value = value and true or nil
    if holds[owner] == value then return end
    local before = Quiet()
    holds[owner] = value
    Changed(before)
end

function Q.Snapshot()
    local n = 0
    for _ in pairs(holds) do n = n + 1 end
    return { on = Quiet(), player = on, holds = n, changes = changes }
end
