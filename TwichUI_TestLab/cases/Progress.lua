-- TwichUI Test Lab: what the client says when a craft finishes (P2.1, the evidence for TwichUI_Workshop/Progress.lua)
-- Workshop's automatic queue counting is OFF (Progress.auto = false) until this case has been run in Forever and its answer read by the owner.
--   crafting.progress.events  (guided) you craft a few items yourself in the game's profession window; the Lab only LISTENS (one Lab-owned
--                             frame, released when the case ends) and then says:
--     * whether UNIT_SPELLCAST_SUCCEEDED arrived for the player once per craft, with a spell id equal to a recipe id the profession window knows
--       (Progress.lua's evidence), and whether any cast GUID came twice
--     * what TRADE_SKILL_CRAFT_BEGIN and TRADE_SKILL_ITEM_CRAFTED_RESULT said (the item, the quantity), if they came at all
--     * how a cancelled or failed craft looked (FAILED / INTERRUPTED with no SUCCEEDED for that cast)
-- Nothing is crafted, clicked or cast by the Lab; it changes no queue, setting or saved data. Bounded: at most MAX_EVENTS events are kept, and
-- the report has at most 15 lines (2 counts, 4 results, 8 casts, the verdict).

local R = TwichUI
local TL = R.TestLab
local G, P = TL.Guided, TL.Probe

TL.Category{ id = "progress", label = "Crafting progress probe (opt-in)", guided = true, manual = true,
    blurb = "you craft a few items yourself; the Lab only listens and says which events mark a finished craft" }

local WAIT = 120         -- seconds the case listens
local MAX_EVENTS = 400

local EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP", "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "BAG_UPDATE_DELAYED" }

local function Now() return TL.Runner.Now() end
local function Combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return v
end

local function IsRecipe(id)
    if type(id) ~= "number" or not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if not ok then return nil end
    return type(info) == "table"
end

-- the summary of one recording (pure: the offline tests read it)
function TL.ProgressSummary(log)
    local casts, order = {}, {}
    local results, begins, bags = 0, 0, 0
    local items = {}
    for _, e in ipairs(log) do
        local ev, a = e.event, e.args
        if ev:find("^UNIT_SPELLCAST_") and a[1] == "player" then
            local guid, spell = a[2], a[3]
            local key = tostring(guid)
            local c = casts[key]
            if not c then c = { guid = guid, spell = spell, seen = {} } casts[key] = c order[#order + 1] = key end
            c.seen[ev] = (c.seen[ev] or 0) + 1
        elseif ev == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            results = results + 1
            local d = a[1]
            if type(d) == "table" then items[#items + 1] = ("%s x%s (operation %s)"):format(tostring(Plain(d.itemID)), tostring(Plain(d.quantity)), tostring(Plain(d.operationID))) end
        elseif ev == "TRADE_SKILL_CRAFT_BEGIN" then begins = begins + 1
        elseif ev == "BAG_UPDATE_DELAYED" then bags = bags + 1 end
    end
    local out = { succeeded = 0, failed = 0, twice = 0, recipeSpells = 0, otherSpells = 0, results = results, begins = begins, bags = bags, items = items, casts = {} }
    for _, key in ipairs(order) do
        local c = casts[key]
        local s = c.seen.UNIT_SPELLCAST_SUCCEEDED or 0
        if s > 0 then out.succeeded = out.succeeded + 1 end
        if s > 1 then out.twice = out.twice + 1 end
        if s == 0 and ((c.seen.UNIT_SPELLCAST_FAILED or 0) + (c.seen.UNIT_SPELLCAST_INTERRUPTED or 0)) > 0 then out.failed = out.failed + 1 end
        local recipe = IsRecipe(c.spell)
        if s > 0 then
            if recipe then out.recipeSpells = out.recipeSpells + 1 else out.otherSpells = out.otherSpells + 1 end
        end
        out.casts[#out.casts + 1] = ("spell %s guid %s: %s%s"):format(tostring(Plain(c.spell)), tostring(Plain(c.guid)), (function()
            local parts = {}
            for ev, n in pairs(c.seen) do parts[#parts + 1] = ev:gsub("UNIT_SPELLCAST_", "") .. "=" .. n end
            table.sort(parts)
            return table.concat(parts, " ")
        end)(), recipe == true and " (a recipe id)" or (recipe == false and " (not a recipe id)" or ""))
    end
    return out
end

TL.Case{ id = "crafting.progress.events", cat = "progress", class = "guided", budget = WAIT + 30,
  about = "Which events say a craft finished? The Lab listens while you craft three of one item yourself and cancel one more; nothing is crafted for you.", run = function(t)
    if Combat() then return t:Skip("not during combat") end
    local fr = P.Get("progress.listen", "Frame")
    if not fr then return t:Skip("the Lab could not make its listener frame") end
    local log = {}
    for _, e in ipairs(EVENTS) do pcall(fr.RegisterEvent, fr, e) end
    fr:SetScript("OnEvent", function(_, event, ...)
        if #log < MAX_EVENTS then log[#log + 1] = { at = Now(), event = event, args = { ... } } end
    end)
    local ok, whyNot = G.Begin({ mode = "click", title = "Crafting progress probe", choices = { "Done" },
        lines = { "Open one of your professions and craft THREE of one item yourself (Create three times, or Create All with 3).",
            "Then start one more craft and cancel it by moving or pressing Escape.", "Press Done when you have finished. Nothing is crafted, clicked or changed by the Lab." } })
    if not ok then
        fr:UnregisterAllEvents()
        return t:Skip(whyNot)
    end
    local deadline = Now() + WAIT
    while Now() < deadline and G.Choice() == nil do
        local status = G.Status()
        if status == "skipped" or status == "idle" then fr:UnregisterAllEvents(); return t:Skip("the request was closed") end
        if Combat() then fr:UnregisterAllEvents(); return t:Skip("combat started") end
        t:Progress(("listening: %d events (%d s left)"):format(#log, math.max(0, math.floor(deadline - Now()))))
        t:Wait(0.25)
    end
    fr:UnregisterAllEvents()
    fr:SetScript("OnEvent", nil)
    local s = TL.ProgressSummary(log)
    t:Note(("player casts that SUCCEEDED: %d (%d with a recipe id, %d with another id); a GUID that SUCCEEDED twice: %d; cancelled or failed casts: %d"):format(
        s.succeeded, s.recipeSpells, s.otherSpells, s.twice, s.failed))
    t:Note(("TRADE_SKILL_CRAFT_BEGIN: %d; TRADE_SKILL_ITEM_CRAFTED_RESULT: %d; BAG_UPDATE_DELAYED: %d"):format(s.begins, s.results, s.bags))
    for i = 1, math.min(#s.items, 4) do t:Note("crafted result: " .. s.items[i]) end
    for i = 1, math.min(#s.casts, 8) do t:Note("cast " .. s.casts[i]) end
    local verdict
    if s.recipeSpells >= 3 and s.twice == 0 and s.otherSpells == 0 then
        verdict = "EVIDENCE OK: one SUCCEEDED per craft, with the recipe id, no GUID twice. Check the counts match what you crafted before turning Progress.auto on."
    elseif s.succeeded == 0 then
        verdict = "NO EVIDENCE: no successful player cast was seen. Keep Progress.auto off."
    else
        verdict = "UNCLEAR: the casts don't match the rule (see the lines above). Keep Progress.auto off."
    end
    G.Say(verdict)
    t:Note("verdict: " .. verdict)
    t:Fact("crafting.progress.succeeded", s.succeeded)
    t:Fact("crafting.progress.results", s.results)
end }
