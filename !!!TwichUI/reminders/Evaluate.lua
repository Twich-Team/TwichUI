-- TwichUI: Reminders, deciding
-- Pure: a reminder's view (Config.lua), a table of observations and who is playing go in; whether it shows, and why,
-- comes out. Nothing here reads the game, touches a frame or keeps state, so the live reminders, the Test section's
-- simulations and the offline tests all run this same code. The live observations are State.lua's; a simulation builds
-- a table of its own from the conditions' scenarios and never sees, or changes, the live one.
--
-- Three answers for a condition: C.MATCH, C.NOMATCH and C.UNKNOWN (the game hasn't given what it needs). Together:
--   All conditions match:  any no match -> no match; otherwise any unknown -> unknown; otherwise match.
--   Any condition matches: any match -> match; otherwise any unknown -> unknown; otherwise no match.
-- No conditions is no match (a reminder can't be turned on without one; this is the safety net). Unknown never shows.
--
-- Status of a reminder, most important first:
--   invalid        something about it can't be used (its problems say what); it never shows
--   disabled       turned off (a new reminder starts here)
--   notApplicable  not for this character or class
--   waiting        the game hasn't given enough to decide (or who is playing isn't known yet)
--   showing / hidden   the conditions' answer
-- The controller adds what only it knows: "off" (Reminders switched off), "world" (not in the world yet), "pending"
-- (waiting out its delay) and "holding" (kept up for its minimum time).

local R = TwichUI
local C = R.ReminderConditions
local E = {}
R.ReminderEval = E

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
E.INVALID = "invalid"

E.RESULT_WORDS = { match = "Match", nomatch = "No match", unknown = "Unavailable", invalid = "Invalid" }
E.STATUS_WORDS = {
    showing = "Showing", hidden = "Hidden", disabled = "Disabled", notApplicable = "Not applicable",
    waiting = "Waiting for information", invalid = "Invalid configuration",
    off = "Off (Reminders are turned off)", world = "Waiting for the game world",
    pending = "Waiting out its delay", holding = "Showing (kept up for its minimum time)",
}

function E.Combine(match, results)
    if #results == 0 then return NOMATCH end
    local unknown = false
    if match == "any" then
        for _, r in ipairs(results) do
            if r == MATCH then return MATCH end
            if r ~= NOMATCH then unknown = true end
        end
        return unknown and UNKNOWN or NOMATCH
    end
    for _, r in ipairs(results) do
        if r == NOMATCH then return NOMATCH end
        if r ~= MATCH then unknown = true end
    end
    return unknown and UNKNOWN or MATCH
end

-- One condition of a view: result, what was observed (words), why it is unknown or invalid (words or nil).
function E.Condition(entry, obs)
    local p, cond = entry.provider, entry.cond
    if not (p and cond) then return E.INVALID, "", entry.why end
    local ok, result, reason = pcall(p.Evaluate, cond, obs)
    if not ok then
        R.Fault("reminders condition", result)
        return E.INVALID, "", "This condition couldn't be checked."
    end
    local okObs, observed = pcall(p.Observed, cond, obs)
    observed = okObs and observed or ""
    if entry.why then return E.INVALID, observed, entry.why end
    return result, observed, result == UNKNOWN and reason or nil
end

-- A condition in words (its provider's summary), or a line saying it can't be read.
function E.Summary(entry)
    if entry.provider and entry.cond then
        local ok, text = pcall(entry.provider.Summary, entry.cond)
        if ok and type(text) == "string" then return text end
    end
    return "A condition TwichUI can't read"
end

-- Whether a reminder is for whoever is playing. ctx: { character = "Name - Realm" or nil, class = token or nil,
-- simulated = true (a simulation tries the rules, not the scope) }. Returns MATCH, NOMATCH or UNKNOWN, and words.
function E.Applies(view, ctx)
    if ctx and ctx.simulated then return MATCH end
    local s = view.scope
    if s.who == "characters" then
        local me = ctx and ctx.character
        if not me then return UNKNOWN, "The game hasn't said which character this is yet." end
        local listed = false
        for _, c in ipairs(s.characters) do if c == me then listed = true end end
        if not listed then return NOMATCH, "It is for other characters." end
    end
    if s.class then
        local class = ctx and ctx.class
        if not class then return UNKNOWN, "The game hasn't said which class this is yet." end
        if class ~= s.class then return NOMATCH, ("It is only for %s characters."):format(R.Reminders.ClassName(s.class)) end
    end
    return MATCH
end

local function Explain(match, result)
    if match == "any" then
        if result == MATCH then return "At least one condition matches." end
        if result == UNKNOWN then return "None matches yet, and at least one can't be checked yet." end
        return "At least one condition must match."
    end
    if result == MATCH then return "All conditions match." end
    if result == UNKNOWN then return "None fails, but at least one can't be checked yet." end
    return "All conditions must match."
end

-- Decides one reminder. out (optional, reused between calls): receives
--   status, result (the conditions together), explain (a sentence), reason (why it isn't showing, for the statuses
--   that need one) and conditions = { { summary, result, observed, reason }, ... }.
function E.Run(view, obs, ctx, out)
    out = out or {}
    local list = out.conditions or {}
    out.conditions = list
    local results = out.results or {}
    out.results = results
    for i = #list, 1, -1 do list[i] = nil end
    for i = #results, 1, -1 do results[i] = nil end

    local valid = view.valid
    for i, entry in ipairs(view.conditions) do
        local result, observed, reason = E.Condition(entry, obs)
        list[i] = { summary = E.Summary(entry), result = result, observed = observed, reason = reason }
        if result == E.INVALID then valid = false end
        results[i] = result
    end
    out.result = E.Combine(view.match, results)
    out.explain = Explain(view.match, out.result)
    out.reason = nil

    if not valid then
        out.status, out.reason = "invalid", view.problems[1] or "Something about it can't be used."
        return out
    end
    if not view.enabled then
        out.status = "disabled"
        return out
    end
    local applies, why = E.Applies(view, ctx)
    if applies == NOMATCH then
        out.status, out.reason = "notApplicable", why
        return out
    elseif applies == UNKNOWN then
        out.status, out.reason = "waiting", why
        return out
    end
    if out.result == MATCH then out.status = "showing"
    elseif out.result == UNKNOWN then out.status = "waiting"
    else out.status = "hidden" end
    return out
end

-- The rule in one sentence: "Shows when: Off hand is not Shield." / "Shows when all of these are true: ...".
function E.RuleSentence(view)
    local n = #view.conditions
    if n == 0 then return "No conditions yet: it can't show until you add one." end
    if n == 1 then return "Shows when: " .. E.Summary(view.conditions[1]) .. "." end
    local parts = {}
    for i, entry in ipairs(view.conditions) do parts[i] = E.Summary(entry) end
    if view.match == "any" then
        return "Shows when any of these is true: " .. table.concat(parts, "; or ") .. "."
    end
    return "Shows when all of these are true: " .. table.concat(parts, "; and ") .. "."
end

-- Who it is for, in words.
function E.ScopeSentence(view, me)
    local s = view.scope
    local who
    if s.who == "characters" then
        local n = #s.characters
        local mine = false
        for _, c in ipairs(s.characters) do if c == me then mine = true end end
        if n == 0 then who = "No character chosen yet"
        elseif n == 1 and mine then who = "This character only"
        elseif n == 1 then who = "Only " .. s.characters[1]
        else who = ("%d chosen characters%s"):format(n, mine and ", this one included" or "") end
    else
        who = "Every character using this profile"
    end
    if s.class then who = who .. (", %s only"):format(R.Reminders.ClassName(s.class)) end
    return who
end

---------------------------------------------------------------------------
-- Simulation: the same decision over made-up observations. picks[i] is the scenario key chosen for condition i (nil:
-- its first). Returns the decision (status from E.Run, with the scope set aside) and the observations it used. The
-- live observations are never read or written.
---------------------------------------------------------------------------
function E.Scenarios(entry)
    if not (entry.provider and entry.cond) then return {} end
    local ok, list = pcall(entry.provider.Scenarios, entry.cond)
    return ok and type(list) == "table" and list or {}
end

function E.Simulate(view, picks)
    local obs = { slots = {} }
    for i, entry in ipairs(view.conditions) do
        local list = E.Scenarios(entry)
        local chosen = list[1]
        for _, s in ipairs(list) do
            if picks and s.key == picks[i] then chosen = s end
        end
        if chosen then chosen.Apply(obs) end
    end
    -- rules, not the switch: a draft can be tried before it is turned on
    local sim = setmetatable({ enabled = true }, { __index = view })
    local out = E.Run(sim, obs, { simulated = true })
    out.simulated = true
    return out, obs
end
