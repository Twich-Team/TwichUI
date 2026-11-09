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
--   Q.On()           true while the screen is quiet
--   Q.Set(on)        turns it on or off (true/false); the same state again does nothing
--   Q.Toggle()       the other state; returns the new one
--   Q.OnChange(fn)   fn(on) after it changed (once per function); a function that fails is reported and the rest still run
--   Q.Snapshot()     { on = bool, changes = n } for /tui diagnostics: counts only

local R = TwichUI
local Q = {}
R.QuietScreen = Q

local on = false
local changes = 0
local listeners = {}

function Q.On() return on end

function Q.OnChange(fn)
    if type(fn) ~= "function" then return end
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end

function Q.Set(value)
    value = value and true or false
    if value == on then return end
    on = value
    changes = changes + 1
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, on)
        if not ok then
            if R.Fault then R.Fault("quiet screen", err) else geterrorhandler()(err) end
        end
    end
end

function Q.Toggle()
    Q.Set(not on)
    return on
end

function Q.Snapshot() return { on = on, changes = changes } end
