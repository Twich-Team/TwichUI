-- TwichUI: Loot Rolls, the switch
-- Turns the feature on and off (TwichUIDB.modules.lootRolls, off by default): on, it listens for group-loot rolls, shows a card for each
-- and lets the game's own roll frames step aside one roll at a time; off, nothing is listened for, every card goes, and the game's frames
-- are as they were. Automatic choices are a separate, later opt-in (LootRolls.Get("auto")) and need the cards.
--
-- What stays loaded when it is off: these files and nothing else (no frame, no event, no timer).

local R = TwichUI
local LR, Ro, C, A, B = R.LootRolls, R.LootRoll, R.LootCards, R.LootAuto, R.LootBlizzard

local on = false

function LR.IsOn() return on end

-- Called by the switch (Switches.lua) and at login.
function LR.Refresh()
    local want = R:Enabled("lootRolls")
    if want == on then return end
    on = want
    if on then
        C.Enable()
        Ro.Enable()
    else
        Ro.Disable()
        C.Disable()
        A.Stopped()
    end
end

R:On("PLAYER_LOGIN", function() if R:Enabled("lootRolls") then LR.Refresh() end end)

-- For TwichUI_Diagnostics and the status rows: read only.
function LR.Snapshot()
    local rolls, live = Ro.Rolls(), 0
    for _, r in ipairs(rolls) do if Ro.IsLive(r) then live = live + 1 end end
    return {
        on = on, listening = Ro.Listening(), events = Ro.EventCount(), records = #rolls, live = live, cards = C.CardCount(),
        pool = C.PoolSize(), failed = C.Failed(), parked = B.ParkedCount(), scheduled = A.Scheduled(),
        auto = LR.AutoOn(), paused = LR.Paused(), rules = LR.Count(),
    }
end
