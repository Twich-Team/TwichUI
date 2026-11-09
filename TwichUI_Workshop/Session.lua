-- TwichUI Workshop: what the window knows and does, without a frame
-- Holds the recipe lists seen in this session (the player's own professions, in memory only), turns the saved queue and the bags
-- into the rows the window draws, and performs its actions (add, change, remove, open a recipe), each answering in plain words.
-- Nothing here is saved except through Queue.lua.

local R = TwichUI
local W = R.Workshop
local Q, M, O = W.Queue, W.Materials, W.Observe
local S = { filter = "", observations = 0 }
W.Session = S

local MAX_PROFESSIONS = 5

local profs = {}       -- [professionID] = { prof, profName, complete, recipes, at }
local order = {}       -- professionIDs, the order first seen
local current          -- the professionID being browsed
local lastWhy          -- why the last read gave nothing, or nil
local note             -- the last thing an action said, until the next action

---------------------------------------------------------------------------
-- Reading the profession window
---------------------------------------------------------------------------
-- Reads the player's open profession. A good read replaces that profession's list, becomes the one browsed, and brings the saved
-- information of any queued recipe in it up to date. A read that gives nothing leaves what was seen before as it was.
-- Returns true, or false and why (see Observe.Read).
function S.Observe()
    local r, why = O.Read()
    lastWhy = why
    if not r then return false, why end
    S.observations = S.observations + 1
    r.at = Q.Now()
    if not profs[r.prof] then
        if #order >= MAX_PROFESSIONS then
            local drop = table.remove(order, 1)
            profs[drop] = nil
        end
        order[#order + 1] = r.prof
    end
    profs[r.prof] = r
    current = r.prof
    if #Q.Entries() > 0 then
        local byId = {}
        for _, rec in ipairs(r.recipes) do byId[rec.id] = rec end
        for _, e in ipairs(Q.Entries()) do
            local rec = byId[e.id]
            if rec then Q.Refresh(O.Fill(rec)) end
        end
    end
    return true
end

-- Forgets everything seen (the window closed); the saved queue is untouched
function S.Reset()
    profs, order, current, lastWhy, note = {}, {}, nil, nil, nil
    S.filter = ""
    O.ClearCache()
end

function S.Professions()
    local out = {}
    for _, id in ipairs(order) do
        local p = profs[id]
        out[#out + 1] = { id = id, name = p.profName, count = #p.recipes, selected = id == current }
    end
    return out
end

function S.Select(id)
    if profs[id] then current = id end
end

function S.Current() return current and profs[current] or nil end

function S.SetFilter(text)
    text = type(text) == "string" and text or ""
    S.filter = (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The recipes of the browsed profession that match the search words
function S.Browse()
    local p = S.Current()
    if not p then return {} end
    local f = S.filter:lower()
    if f == "" then return p.recipes end
    local out = {}
    for _, rec in ipairs(p.recipes) do
        if rec.name:lower():find(f, 1, true) then out[#out + 1] = rec end
    end
    return out
end

-- Up to two lines for the area above the list: why it is empty, or what to know about it
local NOT_OWN = "That window isn't one of your own professions (a link, a guild list or crafting for an NPC), so it isn't used."
function S.Notices()
    local out = {}
    local p = S.Current()
    if p then
        if not p.complete then
            out[#out + 1] = "This list follows the filters in your profession window, so some recipes may not be shown."
        end
    else
        out[#out + 1] = "Open one of your professions to see its recipes here."
    end
    if lastWhy == "not-own" then out[#out + 1] = NOT_OWN
    elseif lastWhy == "combat" then out[#out + 1] = "Recipes can be read when combat ends."
    elseif lastWhy == "api" then out[#out + 1] = "This game version doesn't offer profession recipes to TwichUI." end
    return out
end

function S.Why() return lastWhy end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------
local ACTION_WHY = {
    held = "This queue was saved by a newer TwichUI, so it can't be changed here.",
    full = "The queue is full (" .. W.MAX_QUEUE .. " recipes).",
    exists = "That recipe is already in the queue.",
    unsaved = "Couldn't save the queue yet. Try again in a moment.",
    bad = "That recipe can't be queued.",
}

function S.Note() return note end
function S.ClearNote() note = nil end

function S.IsQueued(id) return Q.Find(id) ~= nil end

function S.Add(rec)
    O.Fill(rec)
    local e, why = Q.Add(rec, 1)
    if not e then
        note = ACTION_WHY[why] or ACTION_WHY.bad
        return false
    end
    note = e.mats and ("Added " .. e.name .. ".") or ("Added " .. e.name .. ". Its materials aren't known yet: open its profession to update.")
    return true
end

function S.SetCrafts(id, n)
    local ok, why = Q.SetCrafts(id, n)
    if not ok then note = ACTION_WHY[why] or ACTION_WHY.bad end
    return ok
end

function S.Change(id, delta)
    local e = Q.Find(id)
    if not e then return false end
    local n = math.max(1, math.min(W.MAX_CRAFTS, e.crafts + delta))
    return S.SetCrafts(id, n)
end

function S.Remove(id)
    local e = Q.Find(id)
    local ok, why = Q.Remove(id)
    if ok then note = e and ("Removed " .. e.name .. ".") or nil
    else note = ACTION_WHY[why] or ACTION_WHY.bad end
    return ok
end

function S.OpenRecipe(id)
    if O.OpenRecipe(id) then note = nil return true end
    local e = Q.Find(id)
    note = "The game wouldn't open that recipe." .. ((e and e.profName) and (" Open " .. e.profName .. " first.") or " Open its profession first.")
    return false
end

-- One line per queued recipe for the window
function S.QueueRows()
    local rows = {}
    for _, e in ipairs(Q.Entries()) do
        rows[#rows + 1] = {
            entry = e,
            perCraft = W.PerCraft(e.outMin, e.outMax),
            expected = W.Expected(e.outMin, e.outMax, e.crafts),
            unresolved = Q.Unresolved(e),
        }
    end
    return rows
end

---------------------------------------------------------------------------
-- Materials
---------------------------------------------------------------------------
-- Rows and a summary of everything the queue needs against the bags (see Materials.lua)
function S.Materials()
    return M.Rows(Q.Entries(), O.BagCount)
end

-- The one sentence under the materials, and its tone ("good", "warn" or "quiet": the words carry the meaning, the tone only colours them)
function S.Headline(sum)
    local function Plural(n, one, many) return n == 1 and one or many end
    if sum.state == "empty" then return "Add recipes to see the materials you need.", "quiet" end
    if sum.state == "ready" then return "All the materials are in your bags.", "good" end
    if sum.state == "short" then
        return ("Still needed: %d %s."):format(sum.shortItems, Plural(sum.shortItems, "material", "materials")), "warn"
    end
    if sum.unknown > 0 then
        return ("%d %s can't be counted yet. Open %s to update."):format(sum.unknown, Plural(sum.unknown, "recipe", "recipes"),
            Plural(sum.unknown, "its profession", "their professions")), "warn"
    end
    return "Some of your bag counts can't be read yet.", "warn"
end

function S.Snapshot()
    local n = 0
    for _, id in ipairs(order) do n = n + #profs[id].recipes end
    return { professions = #order, recipes = n, queue = Q.Count(), cache = O.CacheSize(), observations = S.observations }
end
