-- Opt-in, temporary observation only. No crafting, queue credit or saved-state writes.
local TL = TwichUI.TestLab
local G, P = TL.Guided, TL.Probe
local WAIT, MAX_EVENTS, MAX_ARGS = 180, 400, 8
local EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP", "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "BAG_UPDATE_DELAYED" }
local CODES = { "SENT", "START", "OK", "FAIL", "INT", "STOP", "BEGIN", "RESULT", "BAG" }
local code = {}
for i, event in ipairs(EVENTS) do code[event] = CODES[i] end
TL.Category{ id = "progress", label = "Crafting progress probe (opt-in)", guided = true, manual = true,
    blurb = "temporary, redacted craft-event evidence; never changes your queue" }
local function Now() return TL.Runner.Now() end
local function Combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Number(v)
    if Secret(v) or type(v) ~= "number" then return nil end
    if TL.Reference.Finite(v) and v >= 0 and v <= 2147483647 and v == math.floor(v) then return v end
end
local function IsRecipe(id)
    if not Number(id) or not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if not ok or Secret(info) then return nil end
    return type(info) == "table"
end

-- Retain types/counts and only allowlisted values. Never retain names, target strings,
-- links, arbitrary table keys or raw GUIDs. Cast identities become run-local ordinals.
function TL.ProgressCapture(ids, event, ...)
    local e = { event = event, args = {}, n = select("#", ...), shape = {} }
    local spellcast = event:find("^UNIT_SPELLCAST_") ~= nil
    local guidSlot = event == "UNIT_SPELLCAST_SENT" and 3 or 2
    for i = 1, math.min(e.n, MAX_ARGS) do
        local v = select(i, ...)
        local kind = Secret(v) and "secret" or type(v)
        local text = kind
        if kind ~= "secret" then
            if spellcast and i == 1 then
                e.args[1] = kind == "string" and v == "player" and "player" or "other"
                text = kind .. ":" .. e.args[1]
            elseif spellcast and i == guidSlot and kind == "string" and #v > 0 and #v <= 128 then
                ids.values = ids.values or {}
                if not ids.values[v] then ids.count = (ids.count or 0) + 1; ids.values[v] = ids.count end
                e.args[i], text = "c" .. ids.values[v], "string:c" .. ids.values[v]
            elseif kind == "number" and Number(v) then
                e.args[i], text = v, "number:" .. v
            elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" and i == 1 and kind == "table" then
                local fields, parts = {}, {}
                for _, key in ipairs({ "itemID", "quantity", "operationID" }) do
                    local ok, value = pcall(function() return v[key] end)
                    local n = ok and Number(value)
                    fields[key] = n
                    parts[#parts + 1] = key .. "=" .. (n and tostring(n) or (ok and Secret(value) and "secret" or "unknown"))
                end
                e.args[i], text = fields, "table{" .. table.concat(parts, ",") .. ";other fields omitted}"
            end
        end
        e.shape[i] = text
    end
    e.text = (code[event] or "?") .. "(" .. e.n .. ") " .. table.concat(e.shape, "/") .. (e.n > MAX_ARGS and "/ARGS TRUNCATED" or "")
    return e
end

function TL.ProgressSummary(log)
    local casts, order, ids = {}, {}, {}
    local out = { succeeded = 0, failed = 0, twice = 0, recipeSpells = 0, otherSpells = 0, results = 0, begins = 0, bags = 0, items = {}, casts = {}, unmapped = 0 }
    for _, raw in ipairs(log) do
        local e = raw.shape and raw or TL.ProgressCapture(ids, raw.event, unpack(raw.args, 1, raw.n or #raw.args))
        local ev, a = e.event, e.args
        if ev:find("^UNIT_SPELLCAST_") and a[1] == "player" then
            local sent = ev == "UNIT_SPELLCAST_SENT"
            local guid, spell = a[sent and 3 or 2], a[sent and 4 or 3]
            if type(guid) == "string" and Number(spell) then
                local c = casts[guid]
                if not c then c = { guid = guid, spell = spell, seen = {} }; casts[guid] = c; order[#order + 1] = guid end
                c.seen[ev] = (c.seen[ev] or 0) + 1
            else out.unmapped = out.unmapped + 1 end
        elseif ev == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            out.results = out.results + 1
            local d = a[1]
            if type(d) == "table" then out.items[#out.items + 1] = ("%s x%s"):format(tostring(d.itemID), tostring(d.quantity)) end
        elseif ev == "TRADE_SKILL_CRAFT_BEGIN" then out.begins = out.begins + 1
        elseif ev == "BAG_UPDATE_DELAYED" then out.bags = out.bags + 1 end
    end
    for _, guid in ipairs(order) do
        local c = casts[guid]
        local s = c.seen.UNIT_SPELLCAST_SUCCEEDED or 0
        if s > 0 then
            out.succeeded = out.succeeded + 1
            if IsRecipe(c.spell) then out.recipeSpells = out.recipeSpells + 1 else out.otherSpells = out.otherSpells + 1 end
        end
        if s > 1 then out.twice = out.twice + 1 end
        if s == 0 and ((c.seen.UNIT_SPELLCAST_FAILED or 0) + (c.seen.UNIT_SPELLCAST_INTERRUPTED or 0)) > 0 then out.failed = out.failed + 1 end
        out.casts[#out.casts + 1] = guid
    end
    return out
end

-- Ten timeline lines fit the existing 16-note/400-byte report contract.
function TL.ProgressReport(log, registration, dropped, timedOut)
    local s = TL.ProgressSummary(log)
    local out = { "W13 observation only; " .. (timedOut and "TIME LIMIT" or "Done pressed") .. "; auto credit remains OFF.",
        "registration: " .. table.concat(registration, " "),
        ("unique OK=%d recipe lookup=%d other/unknown=%d duplicate OK=%d failed/interrupted without OK=%d unmapped=%d BEGIN=%d RESULT=%d BAG=%d"):format(
            s.succeeded, s.recipeSpells, s.otherSpells, s.twice, s.failed, s.unmapped, s.begins, s.results, s.bags) }
    local lines, current, shown = {}, "", 0
    for i, e in ipairs(log) do
        local entry = i .. ":" .. e.text
        if #current + #entry + 3 > 370 then
            lines[#lines + 1], current = current, ""
            if #lines == 10 then break end
        end
        current = current == "" and entry or current .. " ; " .. entry
        shown = i
    end
    if current ~= "" and #lines < 10 then lines[#lines + 1] = current end
    out[#out + 1] = ("capture kept=%d dropped=%d; timeline shown=%d omitted=%d%s; n is actual arg count; cN is a run-local cast alias."):format(
        #log, dropped or 0, shown, #log - shown, ((dropped or 0) > 0 or shown < #log) and " TRUNCATED" or "")
    for _, line in ipairs(lines) do out[#out + 1] = line end
    out[#out + 1] = "INCONCLUSIVE: events/recipe lookup do not prove operation counts or selected recipe mapping. Compare against your written scenario counts, including multi-output and partial cancellation."
    out[#out + 1] = "Types/counts preserved up to 8 args; strings/secret values redacted, result fields allowlisted. STOP/start/bags are not success. No EVIDENCE OK verdict or automatic-credit authorization."
    return out, s
end

TL.Case{ id = "crafting.progress.events", cat = "progress", class = "guided", budget = WAIT + 30,
    about = "Record one craft scenario per run: singles, batch, partial cancellation, failure or multi-output. Listen only; no queue changes.", run = function(t)
    if Combat() then return t:Skip("not during combat") end
    local fr = P.Get("progress.listen", "Frame")
    if not fr then return t:Skip("the Lab could not make its listener frame") end
    local log, ids, registration, dropped = {}, {}, {}, 0
    for i, event in ipairs(EVENTS) do
        local ok, result = pcall(fr.RegisterEvent, fr, event)
        local status = not ok and "raised" or (Secret(result) and "unknown" or (result == false and "refused" or "call-ok"))
        if ok and fr.IsEventRegistered then
            local checked, value = pcall(fr.IsEventRegistered, fr, event)
            if checked and not Secret(value) then status = value and "yes" or "no" end
        end
        registration[#registration + 1] = CODES[i] .. "=" .. status
    end
    fr:SetScript("OnEvent", function(_, event, ...)
        if #log >= MAX_EVENTS then dropped = dropped + 1; return end
        local e = TL.ProgressCapture(ids, event, ...)
        e.at = Now()
        log[#log + 1] = e
    end)
    local function Cleanup() fr:UnregisterAllEvents(); fr:SetScript("OnEvent", nil) end
    local ok, why = G.Begin({ mode = "click", title = "Crafting progress evidence", choices = { "Done" }, lines = {
        "One scenario per run: three singles; a batch; a batch cancelled partway; a failed/interrupted craft; or multi-output.",
        "Write down recipe ID and requested/completed operations/output count. Keep the profession open. Do not press Workshop Done.",
        "Craft manually, then press this Done within 180 seconds. The Lab only listens; automatic queue credit stays off." } })
    if not ok then Cleanup(); return t:Skip(why) end
    local deadline = Now() + WAIT
    while Now() < deadline and G.Choice() == nil do
        local status = G.Status()
        if status == "skipped" or status == "idle" then Cleanup(); return t:Skip("the request was closed") end
        if Combat() then Cleanup(); return t:Skip("combat started") end
        t:Progress(("listening: %d retained, %d dropped (%d s left)"):format(#log, dropped, math.max(0, math.floor(deadline - Now()))))
        t:Wait(0.25)
    end
    Cleanup()
    local notes, s = TL.ProgressReport(log, registration, dropped, Now() >= deadline)
    for _, note in ipairs(notes) do t:Note(note) end
    G.Say("Evidence recorded; compare with your scenario. Automatic queue credit remains OFF.")
    t:Fact("crafting.progress.succeeded", s.succeeded)
    t:Fact("crafting.progress.results", s.results)
    t:Fact("crafting.progress.dropped", dropped)
end }
