-- TwichUI: Cozy Sleeping Bag guide, the progression
-- Works out which steps are done, which is next and what the window follows, from plain facts about the character's quests.
-- No frames, no events and no game calls: guides/CozyBag.lua reads the game and hands the answers in through a `reader`,
-- so everything here is checked offline (tests/test_cozy_bag.lua).
--
-- reader = {
--   ready         whether the character's quest history can be trusted yet (nothing is concluded until it can),
--   completed(id) whether quest id was turned in, ever (the game's own history flag),
--   onQuest(id)   whether quest id is in the quest log now,
--   readyToTurnIn(id)  whether quest id's objectives are all done (only asked of a quest that is in the log),
-- }
--
-- Evaluate(guide, faction, reader) returns
--   status  "loading" (history not there yet: no step has a state), "needs-faction" (the faction is unknown, so the two
--           sides of the chain cannot be told apart) or "ready"
--   steps   the steps that apply to this faction, in order: { step, state, phase, inferred }
--             state  "done", "current" (the first required step not done), "upcoming", or "optional" (an optional step
--                    not done; an optional step is never current or upcoming)
--             phase  for a step not done whose quest is in the log: "accepted", or "ready" (objectives complete, not turned in)
--             inferred  true when the step is done only because a later step it names in `provedBy` is
--   current index of the current step in `steps`, nil when the chain is finished or unknown
--   done, total   required steps done and required steps (optional ones are not counted)
--   complete      every required step is done
-- Done comes from the character's own quest history. Nothing saved, nothing from this session's events, and not the reward
-- item: a quest that was turned in before TwichUI was installed counts exactly as one turned in a minute ago.

local R = TwichUI
local S = {}
R.CozyBagState = S

local function Flag(fn, id)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, id)
    return ok and value == true
end

local function Applies(step, faction)
    return step.faction == nil or step.faction == faction
end

function S.Evaluate(guide, faction, reader)
    local result = { status = "ready", steps = {}, done = 0, total = 0, complete = false }
    if not (reader and reader.ready) then
        result.status = "loading"
        return result
    end
    if faction ~= "Alliance" and faction ~= "Horde" then
        result.status = "needs-faction"
        return result
    end
    local list, at = result.steps, {}
    for _, step in ipairs(guide.steps) do
        if Applies(step, faction) then
            list[#list + 1] = { step = step, state = "upcoming" }
            at[step.id] = #list
        end
    end
    -- What the character's own history says.
    for _, entry in ipairs(list) do
        local step = entry.step
        local done = Flag(reader.completed, step.quest)
        local inLog = not done and Flag(reader.onQuest, step.quest)
        if inLog and step.kind == "start" then done = true end     -- taking the quest is the step
        entry.done = done
        if not done and inLog then
            entry.phase = Flag(reader.readyToTurnIn, step.quest) and "ready" or "accepted"
        end
    end
    -- A later step that names this one proves it, last to first so a chain of them carries through. Only where the data says so.
    for i = #list, 1, -1 do
        local entry = list[i]
        if not entry.done and entry.step.provedBy then
            for _, id in ipairs(entry.step.provedBy) do
                local later = at[id]
                if later and later > i and list[later].done then
                    entry.done, entry.inferred = true, true
                    entry.phase = nil
                    break
                end
            end
        end
    end
    for i, entry in ipairs(list) do
        local optional = entry.step.optional == true
        if entry.done then
            entry.state = "done"
        elseif optional then
            entry.state = "optional"
        else
            entry.state = "upcoming"
        end
        if not optional then
            result.total = result.total + 1
            if entry.done then result.done = result.done + 1
            elseif not result.current then
                result.current = i
                entry.state = "current"
            end
        end
        entry.done = nil
    end
    result.complete = result.total > 0 and result.done == result.total
    return result
end

-- Index of the step with this id in result.steps, or nil.
function S.IndexOf(result, id)
    for i, entry in ipairs(result.steps) do
        if entry.step.id == id then return i end
    end
end

-- The step the window shows. `view` is { id, following }: following means "the step I am on is whichever one is current".
-- A step the player picked stays put however progress moves; only a view that is following moves on its own. A chosen
-- step that no longer applies (the faction changed) falls back to following. Returns the view's step id (nil while the
-- history is unknown). Mutates view.
function S.Select(view, result)
    if result.status ~= "ready" or #result.steps == 0 then
        return nil
    end
    local pickedAt = view.id and S.IndexOf(result, view.id)
    if view.following or not pickedAt then
        view.following = true
        local at = result.current or #result.steps
        if not result.current then
            -- finished: the last required step, not the optional one after it
            for i = #result.steps, 1, -1 do
                if not result.steps[i].step.optional then at = i break end
            end
        end
        view.id = result.steps[at].step.id
    end
    return view.id
end

-- The player picks a step. Picking the current step puts the view back to following it.
function S.Pick(view, result, id)
    local at = S.IndexOf(result, id)
    if not at then return false end
    view.id = id
    view.following = (result.current == at)
    return true
end

-- Back to the detected current step.
function S.Follow(view)
    view.following = true
    view.id = nil
end
