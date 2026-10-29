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
-- Conditions sit in a tree: the reminder's top level is a list that matches on all or any, and a group is a condition
-- that holds such a list, so each group is decided the same way and then counts as one match, no match or unknown in
-- its parent. An empty group, a group that can't be read and a condition that isn't finished are *invalid*: the whole
-- reminder is invalid (it never shows) rather than the part being left out. Every condition is read from the one table
-- of observations, none is skipped because another already settled the answer, so Test can show them all.
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

-- A condition in words (its provider's summary), or a line saying it can't be read; a group in words, in parentheses.
local GroupText
function E.Summary(entry)
    if entry.group then return GroupText(entry) end
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
    if result == E.INVALID then return "Something in it can't be checked until it is fixed." end
    if match == "any" then
        if result == MATCH then return "At least one condition matches." end
        if result == UNKNOWN then return "None matches yet, and at least one can't be checked yet." end
        return "At least one condition must match."
    end
    if result == MATCH then return "All conditions match." end
    if result == UNKNOWN then return "None fails, but at least one can't be checked yet." end
    return "All conditions must match."
end

-- What a group is called in the editor and in Test.
function E.GroupWords(match) return match == "any" and "Match any - OR" or "Match all - AND" end

-- Decides the entries of one list (the top level's, or a group's) and writes a node per entry into st.nodes, in reading
-- order (a group before what is in it); returns the list's own answer. Nodes are reused from one run to the next.
local st = { n = 0 }
local function EvalList(entries, match, obs)
    local sawMatch, sawNo, sawUnknown, sawInvalid = false, false, false, false
    for _, entry in ipairs(entries) do
        local n = st.n + 1
        st.n = n
        local node = st.nodes[n]
        if not node then node = {}; st.nodes[n] = node end
        node.entry, node.path, node.depth = entry, entry.path, entry.depth
        local result
        if entry.group then
            node.group, node.match, node.summary, node.observed, node.reason = true, entry.match, E.GroupWords(entry.match), "", nil
            result = EvalList(entry.children, entry.match, obs)
            if entry.why then result, node.reason = E.INVALID, entry.why end
        else
            node.group, node.match = false, nil
            result, node.observed, node.reason = E.Condition(entry, obs)
            node.summary = E.Summary(entry)
            st.leaves[#st.leaves + 1] = node
        end
        node.result = result
        if result == MATCH then sawMatch = true
        elseif result == NOMATCH then sawNo = true
        elseif result == UNKNOWN then sawUnknown = true
        else sawInvalid = true end
    end
    if #entries == 0 then return NOMATCH end
    if sawInvalid then return E.INVALID end
    if match == "any" then
        if sawMatch then return MATCH end
        return sawUnknown and UNKNOWN or NOMATCH
    end
    if sawNo then return NOMATCH end
    return sawUnknown and UNKNOWN or MATCH
end

-- Decides one reminder. out (optional, reused between calls, its tables too): receives
--   status, result (the conditions together), explain (a sentence), reason (why it isn't showing, for the statuses
--   that need one), nodes = { { summary, result, observed, reason, group, match, depth, path }, ... } for every
--   condition and group in reading order (the same order as view.flat), and conditions = the nodes of the conditions alone.
function E.Run(view, obs, ctx, out)
    out = out or {}
    out.nodes = out.nodes or {}
    out.conditions = out.conditions or {}
    local nodes, list = out.nodes, out.conditions
    for i = #list, 1, -1 do list[i] = nil end
    st.nodes, st.leaves, st.n = nodes, list, 0

    out.result = EvalList(view.conditions, view.match, obs)
    for i = #nodes, st.n + 1, -1 do nodes[i] = nil end
    st.nodes, st.leaves = nil, nil
    out.explain = Explain(view.match, out.result)
    out.reason = nil

    local valid = view.valid and out.result ~= E.INVALID
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

---------------------------------------------------------------------------
-- The rule in words, from the same tree the evaluator reads (nothing else is kept that could drift from it).
--   "Shows when: Off hand is not Shield."
--   "Shows when all of these are true: Player class is Warrior, Hunter or Rogue; and Player is in combat."
--   "Shows when any of these is true: Off hand is empty; or (all of: Player is in combat; and Main hand is empty)."
-- A group inside another is in parentheses, so which "and" and "or" belong together is never left to the reader. A
-- provider with Merge says a run of its own conditions in one phrase; a group left with one thing says just that.
---------------------------------------------------------------------------
local Items

function GroupText(entry)
    local items = Items(entry.children, entry.match)
    if #items == 0 then return "(an empty group)" end
    if #items == 1 then return items[1] end
    local any = entry.match == "any"
    return ("(%s: %s)"):format(any and "any of" or "all of", table.concat(items, any and "; or " or "; and "))
end

function Items(entries, match)
    local merged, skip, byProvider = {}, {}, {}
    for i, entry in ipairs(entries) do
        local p = entry.provider
        if not entry.group and p and p.Merge and entry.cond then
            local g = byProvider[p]
            if not g then g = { at = {}, conds = {} }; byProvider[p] = g end
            g.at[#g.at + 1] = i
            g.conds[#g.conds + 1] = entry.cond
        end
    end
    for p, g in pairs(byProvider) do
        local ok, words, used = pcall(p.Merge, match, g.conds)
        if ok and type(words) == "string" and type(used) == "table" and #used >= 2 then
            local first
            for _, u in ipairs(used) do
                local at = g.at[u]
                if at then
                    skip[at] = true
                    if not first or at < first then first = at end
                end
            end
            if first then merged[first], skip[first] = words, nil end
        end
    end
    local items = {}
    for i, entry in ipairs(entries) do
        if merged[i] then items[#items + 1] = merged[i]
        elseif not skip[i] then items[#items + 1] = entry.group and GroupText(entry) or E.Summary(entry) end
    end
    return items
end

function E.RuleSentence(view)
    local entries, match = view.conditions, view.match
    if #entries == 0 then return "No conditions yet: it can't show until you add one." end
    -- a top level that is only one group reads as that group
    while #entries == 1 and entries[1].group do entries, match = entries[1].children, entries[1].match end
    local items = Items(entries, match)
    if #items == 0 then return "A group with nothing in it: it can't show until you add a condition or remove the group." end
    if #items == 1 then return "Shows when: " .. items[1] .. "." end
    if match == "any" then
        return "Shows when any of these is true: " .. table.concat(items, "; or ") .. "."
    end
    return "Shows when all of these are true: " .. table.concat(items, "; and ") .. "."
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
-- Simulation: the same decision over made-up observations. picks[i] is the scenario key chosen for input i of E.SimInputs
-- (nil: its first). Returns the decision (status from E.Run, with the scope set aside) and the observations it used. The
-- live observations are never read or written.
---------------------------------------------------------------------------
function E.Scenarios(entry)
    if not (entry.provider and entry.cond) then return {} end
    local ok, list = pcall(entry.provider.Scenarios, entry.cond)
    return ok and type(list) == "table" and list or {}
end

-- What a simulation lets the player choose: one input for each thing in the world a rule asks about. Conditions whose
-- provider names the same Subject (three "Player class is ..." in one group) share one input, so the made-up facts can't
-- contradict each other; every other condition has an input of its own. { { entry (the first), leaves = { entries },
-- label (when shared), scenarios }, ... } in reading order.
function E.SimInputs(view)
    local inputs, bySubject = {}, {}
    for _, entry in ipairs(view.leaves) do
        if entry.provider and entry.cond then
            local key, label
            if entry.provider.Subject then
                local ok, k, l = pcall(entry.provider.Subject, entry.cond)
                if ok and type(k) == "string" then key, label = k, l end
            end
            local input = key and bySubject[key]
            if input then
                input.leaves[#input.leaves + 1] = entry
            else
                input = { entry = entry, leaves = { entry }, label = label }
                inputs[#inputs + 1] = input
                if key then bySubject[key] = input end
            end
        end
    end
    for _, input in ipairs(inputs) do input.scenarios = E.Scenarios(input.entry) end
    return inputs
end

function E.Simulate(view, picks)
    local obs = { slots = {} }
    for i, input in ipairs(E.SimInputs(view)) do
        local chosen = input.scenarios[1]
        for _, s in ipairs(input.scenarios) do
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
