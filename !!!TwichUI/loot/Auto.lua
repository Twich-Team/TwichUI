-- TwichUI: Loot Rolls, automatic choices
-- Turns what the rules say about a roll into one visible, cancellable countdown and, when it ends and everything still holds, one choice
-- sent through Roll.lua (the same call a click makes). It never rolls anything the player cannot see on a card, never rolls Need unless
-- Need automation was allowed on its own, never acts on a fact the client did not give (an unknown stays manual), and never sends in the
-- last moments of a roll.
--
-- A roll's way through it: pending -> (a rule matched) scheduled, with roll.auto = { ruleId, name, action, delay, startedAt, fireAt }
-- -> submitted. At any point before that the player can Stop (the roll goes back to pending and is not scheduled again), Roll now,
-- or press a choice (which sends that choice and ends the countdown). Pausing, switching automation off, editing or removing the rule,
-- or the roll running short of time puts every scheduled roll back to pending. Everything is rechecked when the countdown ends.
--
-- One timer for all rolls, set to the nearest due time: nothing polls.

local R = TwichUI
local Ru, LR, Ro = R.LootRules, R.LootRolls, R.LootRoll
local A = {}
R.LootAuto = A

A.MIN_DELAY = 1          -- seconds: a countdown is never shorter
A.LAST_MOMENTS = 1.0     -- a countdown ends at least this long before the roll does; with less time left there is none

local timer, timerDue
local evaluating = false

local function Now() return GetTime() end

-- Whether automation may act at all right now: the player's switches, and a card on screen to show it on.
function A.Allowed()
    if not LR.AutoOn() then return false, LR.Paused() and "paused" or "off" end
    local C = R.LootCards
    if not (C and C.Ready and C.Ready()) then return false, "cards" end
    return true
end

local function Note(roll, text)
    if roll.autoNote ~= text then
        roll.autoNote = text
        return true
    end
end

local function Decision(roll)
    return Ru.Decide(LR.Active(), roll.obs or {}, { allowUpgrade = LR.Get("autoUpgrade") == true })
end

local function Rearm() A.Arm() end

-- Puts a scheduled roll back to the player. stop: it was the player who stopped it (it will not be scheduled again).
function A.Cancel(roll, stop, note)
    if not roll then return end
    local changed = false
    if roll.state == "scheduled" then roll.state, changed = "pending", true end
    if roll.auto then roll.auto, changed = nil, true end
    if stop and not roll.autoStopped then roll.autoStopped, changed = true, true end
    if note and Note(roll, note) then changed = true end
    if changed then Ro.Tell("updated", roll) end
    Rearm()
end

-- Looks at one roll and starts, keeps or ends its countdown as the rules now say.
function A.Evaluate(roll)
    if evaluating or not roll then return end
    if roll.state ~= "pending" and roll.state ~= "scheduled" then return end
    evaluating = true
    local ok, err = pcall(function()
        local allowed, why = A.Allowed()
        -- a countdown is shown on the roll's own card: a roll with no card (too many at once, or the player took it back) is manual
        if allowed and not (R.LootCards.Shows and R.LootCards.Shows(roll)) then allowed = false end
        if not allowed then
            if roll.state == "scheduled" then A.Cancel(roll, false) end
            if Note(roll, nil) then Ro.Tell("updated", roll) end
            return
        end
        if roll.autoStopped then return end
        if not (roll.obs and roll.obs.ready) then return end   -- the item is still being read: no decision yet, and no guess
        local decision = Decision(roll)
        if decision.status == "none" then
            if roll.state == "scheduled" then A.Cancel(roll, false, nil) elseif Note(roll, nil) then Ro.Tell("updated", roll) end
            return
        end
        local rule = LR.Rule(decision.rule.id)
        if decision.status == "unknown" then
            A.Cancel(roll, false, rule and ("Rule \"%s\" could not be checked for this item."):format(rule.name) or nil)
            return
        end
        if not rule then return end
        local action = rule.action
        if action == "need" and LR.Get("autoNeed") ~= true then
            return A.Cancel(roll, false, ("Rule \"%s\" would choose Need: allow that in the settings to let it."):format(rule.name))
        end
        if rule.usesUpgrade and LR.Get("autoUpgrade") ~= true then
            return A.Cancel(roll, false, ("Rule \"%s\" uses upgrades: allow that in the settings to let it."):format(rule.name))
        end
        local can, reason = Ro.CanChoose(roll, action)
        if not can then
            return A.Cancel(roll, false, ("Rule \"%s\" matched, but %s"):format(rule.name, (reason or "it can't be rolled now"):gsub("^%u", string.lower)))
        end
        local remaining = Ro.Remaining(roll)
        local delay = math.max(A.MIN_DELAY, rule.delay or LR.Get("autoDelay"))
        if remaining - A.LAST_MOMENTS < A.MIN_DELAY then
            return A.Cancel(roll, false, ("Rule \"%s\" matched, but there is too little time to roll automatically."):format(rule.name))
        end
        local now = Now()
        local keep = roll.state == "scheduled" and roll.auto and roll.auto.ruleId == rule.id and roll.auto.action == action
        local startedAt = keep and roll.auto.startedAt or now
        local fireAt = math.min(startedAt + delay, now + remaining - A.LAST_MOMENTS)
        if fireAt < now + 0.05 then fireAt = now + 0.05 end
        if keep and roll.auto.fireAt == fireAt and roll.auto.name == rule.name then return end
        roll.state = "scheduled"
        roll.auto = { ruleId = rule.id, name = rule.name, action = action, delay = delay, startedAt = startedAt, fireAt = fireAt,
            showResult = rule.result }
        roll.showResult = rule.result
        Note(roll, nil)
        Ro.Tell("updated", roll)
        Rearm()
    end)
    evaluating = false
    if not ok then
        R.Life.Note("loot-auto-error")
        R.Fault("loot rolls", err)
    end
end

-- The countdown ended: check everything again, then send, or hand the roll back.
local function Execute(roll)
    local auto = roll.auto
    if roll.state ~= "scheduled" or not auto then return end
    local allowed = A.Allowed()
    if not allowed then return A.Cancel(roll, false) end
    local decision = Decision(roll)
    local rule = decision.status == "match" and LR.Rule(decision.rule.id)
    if not rule or rule.id ~= auto.ruleId or rule.action ~= auto.action then
        R.Life.Note("loot-auto-stale")
        return A.Cancel(roll, false)
    end
    if rule.action == "need" and LR.Get("autoNeed") ~= true then return A.Cancel(roll, false) end
    if rule.usesUpgrade and LR.Get("autoUpgrade") ~= true then return A.Cancel(roll, false) end
    local ok, why = Ro.Submit(roll, rule.action, "auto")
    if not ok then
        R.Life.Note("loot-auto-refused")
        A.Cancel(roll, false, why and ("Rule \"%s\": %s"):format(rule.name, why) or nil)
    end
end

local function Fire()
    timer, timerDue = nil, nil
    local now = Now()
    local due = {}
    for _, roll in ipairs(Ro.Rolls()) do
        if roll.state == "scheduled" and roll.auto and roll.auto.fireAt <= now + 0.02 then due[#due + 1] = roll end
    end
    for _, roll in ipairs(due) do
        local ok, err = pcall(Execute, roll)
        if not ok then
            R.Life.Note("loot-auto-error")
            R.Fault("loot rolls", err)
            A.Cancel(roll, false)
        end
    end
    A.Arm()
end

-- One timer, for the nearest countdown to end.
function A.Arm()
    local nearest
    for _, roll in ipairs(Ro.Rolls()) do
        if roll.state == "scheduled" and roll.auto and (not nearest or roll.auto.fireAt < nearest) then nearest = roll.auto.fireAt end
    end
    if timer and (not nearest or timerDue ~= nearest) then timer:Cancel(); timer, timerDue = nil, nil end
    if nearest and not timer then
        timerDue = nearest
        timer = C_Timer.NewTimer(math.max(0.02, nearest - Now()), Fire)
    end
end

-- The player's own controls on a card.
function A.Stop(roll)
    if roll and roll.state == "scheduled" then A.Cancel(roll, true) end
end

function A.RollNow(roll)
    if not (roll and roll.state == "scheduled" and roll.auto) then return false end
    local action = roll.auto.action
    if action == "need" and LR.Get("autoNeed") ~= true then return false end
    return Ro.Submit(roll, action, "auto")
end

-- Every roll is looked at again (a setting, a rule or the profile changed).
function A.Refresh()
    for _, roll in ipairs({ unpack(Ro.Rolls()) }) do A.Evaluate(roll) end
    Rearm()
end

function A.Stopped()
    if timer then timer:Cancel(); timer, timerDue = nil, nil end
end
function A.Scheduled()
    local n = 0
    for _, roll in ipairs(Ro.Rolls()) do if roll.state == "scheduled" then n = n + 1 end end
    return n
end

Ro.Subscribe(function(kind, roll)
    if kind == "added" or kind == "updated" then
        if roll.state == "pending" or roll.state == "scheduled" then A.Evaluate(roll) end
    end
    if kind == "removed" then Rearm() end
end)
LR.Subscribe(function(what)
    if what == "settings" or what == "rules" or what == "profile" then A.Refresh() end
end)
