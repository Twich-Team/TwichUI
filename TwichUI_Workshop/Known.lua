-- TwichUI Workshop: the recipes a character knows, remembered between sessions
-- When the player's own profession window has been read (Session.Observe), the recipes of that profession are kept for the
-- character: which recipe, its name and icon, what one craft makes and the materials it needs. The next session starts from that, so
-- Opportunities and the price scan know the recipes without opening every profession again, and a fresh read of a profession
-- brings its entry up to date (new recipes are added, changed ones replaced).
--
--   TwichUIDB.workshop.chars["Name - Realm"].known = { [professionID] = { name, at, complete, r = { recipe, ... } } }
--   recipe = { id, name, icon, outItem, outMin, outMax, state, item1, qty1, item2, qty2, ... }   (a flat list: it is saved a lot of times)
--       icon, outItem, outMin, outMax are 0 when not known; state 0 = output and materials not read yet, 1 = read (the item/qty
--       pairs are the materials), 2 = read but not supported (a choice of items, required extras, variable quantities: no materials).
--   at = when the profession was last read in the player's own window; complete = the list came from GetAllRecipeIDs.
--
-- What is NOT kept: difficulty (it changes with the character's skill, so it is shown only for a profession read this session), other
-- characters' recipes, linked or guild lists, recipes the player has not learned. At most MAX_PROFS professions and MAX_RECIPES recipes
-- each. Same rules as the queue (Queue.lua): never written when a newer TwichUI wrote the data (Held), reading never writes, every
-- record is checked on the way in, a record that can't be read is left out of the next write. Part of TwichUIDB.workshop, so never in
-- a profile, a share or a backup.

local R = TwichUI
local W = R.Workshop
local Int, Text = W.Int, W.Text
local Q = W.Queue
local K = {}
W.Known = K

K.MAX_PROFS = 5
K.MAX_RECIPES = 600

local function Encode(rec)
    local state = 0
    if rec.mats then state = 1 elseif rec.why == "unsupported" and (rec.filled or rec.remembered) then state = 2 end
    local t = { rec.id, rec.name, rec.icon or 0, rec.outItem or 0, rec.outMin or 0, rec.outMax or 0, state }
    if state == 1 then
        for _, m in ipairs(rec.mats) do t[#t + 1] = m.item; t[#t + 1] = m.qty end
    end
    return t
end

-- A recipe record of the session from a saved one, or nil when it can't be used
local function Decode(t, prof, profName)
    if type(t) ~= "table" then return nil end
    local id, name = Int(t[1], 1, W.MAX_ID), Text(t[2], 80)
    if not id or not name then return nil end
    local rec = { id = id, name = name, icon = Int(t[3], 1, W.MAX_ID), prof = prof, profName = profName }
    local state = Int(t[7], 0, 2) or 0
    if state == 0 then return rec end
    rec.outItem = Int(t[4], 1, W.MAX_ID)
    local lo, hi = Int(t[5], 1, W.MAX_QTY), Int(t[6], 1, W.MAX_QTY)
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
    if lo and hi and hi >= lo then rec.outMin, rec.outMax = lo, hi end
    if state == 1 then
        local list = {}
        local i = 8
        while t[i] ~= nil do
            list[#list + 1] = { item = t[i], qty = t[i + 1] }
            i = i + 2
        end
        rec.mats = Q.CleanMats(list)
        if not rec.mats then return { id = id, name = name, icon = rec.icon, prof = prof, profName = profName } end
    else
        rec.why = "unsupported"
    end
    rec.remembered = true
    return rec
end

-- The remembered professions of this character as the session keeps them: { prof, profName, complete, at, recipes }, the most recently
-- read first. Reads only; an empty list when nothing is saved.
function K.Load()
    local out = {}
    local slot = Q.Slot(false)
    local known = slot and slot.known
    if type(known) ~= "table" then return out end
    for key, p in pairs(known) do
        local prof = Int(key, 1, W.MAX_ID)
        local profName = type(p) == "table" and Text(p.name, 40) or nil
        if prof and profName and type(p.r) == "table" then
            local recipes, seen = {}, {}
            for i = 1, math.min(#p.r, K.MAX_RECIPES) do
                local rec = Decode(p.r[i], prof, profName)
                if rec and not seen[rec.id] then
                    seen[rec.id] = true
                    recipes[#recipes + 1] = rec
                end
            end
            if #recipes > 0 then
                out[#out + 1] = { prof = prof, profName = profName, complete = p.complete == true, at = Int(p.at, 0, 4102444800) or 0, recipes = recipes }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.prof < b.prof
    end)
    while #out > K.MAX_PROFS do out[#out] = nil end
    return out
end

-- Keeps one profession (a session record: prof, profName, complete, at, recipes). Returns true, or false and why ("held", "unsaved", "empty").
function K.Store(p)
    if type(p) ~= "table" or not p.prof or type(p.recipes) ~= "table" then return false, "empty" end
    if Q.Held() then return false, "held" end
    local slot, root = Q.Slot(true)
    if not slot then return false, "unsaved" end
    local r = {}
    for _, list in ipairs({ p.recipes, p.extra or {} }) do   -- the ones the window shows, then the ones it doesn't but are still known
        for i = 1, #list do
            if #r >= K.MAX_RECIPES then break end
            r[#r + 1] = Encode(list[i])
        end
    end
    if #r == 0 then return false, "empty" end
    if type(slot.known) ~= "table" then slot.known = {} end
    root.v = W.SAVED_VERSION
    slot.known[p.prof] = { name = p.profName, at = p.at or Q.Now(), complete = p.complete == true, r = r }
    -- over the limit: the one read longest ago goes
    local n = 0
    for _ in pairs(slot.known) do n = n + 1 end
    while n > K.MAX_PROFS do
        local oldest, oldAt
        for key, v in pairs(slot.known) do
            local at = type(v) == "table" and tonumber(v.at) or 0
            if key ~= p.prof and (not oldAt or at < oldAt) then oldest, oldAt = key, at end
        end
        if oldest == nil then break end
        slot.known[oldest] = nil
        n = n - 1
    end
    return true
end
