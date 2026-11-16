-- TwichUI Workshop: progress on the crafting plan (P2.1)
-- It observes and counts; it never crafts, casts, buys or clicks anything. A queued craft is counted as done in one of two ways:
--   * The player says so: "Crafted one" (Session.MarkCrafted, on the Crafting page and in the compact Craft view). Always available.
--   * The game says so, AUTOMATICALLY, which is OFF (P.auto = false) until it is verified in Forever. The evidence would be
--     UNIT_SPELLCAST_SUCCEEDED for the player whose spell id is a queued recipe's id, counted once per cast GUID. Not counted, ever: a click on
--     a Craft button, a cast that started, failed or was interrupted, a bag count that went up (it may be a purchase, a trade or a move), a
--     second event for the same cast. What is NOT known (none of it has run in the client): that Forever's recipe ids are the crafting spell
--     ids, that one SUCCEEDED arrives per craft when several are made in a row, and how a craft that makes a varying amount is reported. The
--     developer Test Lab probe (crafting.progress.events) records what the client fires; only after that run may P.auto become true. While it is
--     false no event is registered and P.OnSpellcast refuses.
-- The player's last credit can be taken back (P.Undo: "Undo" beside "Crafted one").
-- A credit goes through Queue.SetCrafts / Queue.Remove (the queue's own save and rollback): an entry's crafts go down by one, and the entry is
-- removed after its last craft. A cast GUID is credited at most once (bounded memory, MAX_SEEN, never saved: a reload starts empty, and the
-- queue it saved already has the credit). No separate progress record is kept.

local R = TwichUI
local W = R.Workshop
local Q = W.Queue
local P = {}
W.Progress = P

P.auto = false        -- automatic counting from the game's events: off until the Test Lab run confirms the evidence (see above)
P.MAX_SEEN = 64       -- cast identities remembered, to refuse a second event for the same craft
P.onCredit = nil      -- fn(info): called after a credit, info = { id, name, left, done, planDone, how = "player" | "game" }

local seen, order = {}, {}
local last            -- the player's last "Crafted one", so it can be taken back: { id, entry (as it was), removed }; memory only
local stats = { credited = 0, duplicate = 0, refused = 0 }

local function Remember(key)
    seen[key] = true
    order[#order + 1] = key
    if #order > P.MAX_SEEN then seen[table.remove(order, 1)] = nil end
end

-- One craft of the queued recipe `id` is done. key: the evidence's identity (a cast GUID) or nil for the player's own "Crafted one".
-- Returns true, info, or false and why: "duplicate" (that cast was counted already), "notqueued", "bad", or the queue's reason ("held", "unsaved").
function P.Credit(id, key)
    if key ~= nil then
        if type(key) ~= "string" or key == "" then stats.refused = stats.refused + 1 return false, "bad" end
        if seen[key] then stats.duplicate = stats.duplicate + 1 return false, "duplicate" end
    end
    local e = Q.Find(id)
    if not e then stats.refused = stats.refused + 1 return false, "notqueued" end
    local name, left = e.name, (e.crafts or 1) - 1
    local copy = {}
    for k, v in pairs(e) do copy[k] = v end   -- for Undo (the entry as it was; mats are not changed by a credit, so they are shared safely)
    local ok, why
    if left <= 0 then ok, why = Q.Remove(id) else ok, why = Q.SetCrafts(id, left) end
    if not ok then stats.refused = stats.refused + 1 return false, why end
    if key then Remember(key) else last = { id = id, entry = copy, removed = left <= 0 } end
    stats.credited = stats.credited + 1
    local info = { id = id, name = name, left = math.max(0, left), done = left <= 0, planDone = Q.Count() == 0, how = key and "game" or "player" }
    if P.onCredit then P.onCredit(info) end
    return true, info
end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The game's evidence, only while P.auto: the player's own SUCCESSFUL cast whose spell id is a queued recipe. Anything else is ignored.
function P.OnSpellcast(unit, castGUID, spellID)
    if not P.auto then return false, "off" end
    unit, castGUID, spellID = Plain(unit), Plain(castGUID), Plain(spellID)
    if unit ~= "player" or type(castGUID) ~= "string" or type(spellID) ~= "number" then return false, "other" end
    if not Q.Find(spellID) then return false, "notqueued" end
    return P.Credit(spellID, castGUID)
end

local frame
-- Starts listening, only when automatic counting is on (it is not, until verified)
function P.Start()
    if not P.auto or frame or not CreateFrame then return false end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, _, unit, castGUID, spellID) P.OnSpellcast(unit, castGUID, spellID) end)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    return true
end

-- Takes back the player's last "Crafted one" (a mistaken click): the craft is counted again, or the entry its last craft removed comes back (at
-- the end of the queue). Only the player's own credit, only the last one, only while the game runs. Returns true, info, or false and why
-- ("nothing", "exists": the recipe was queued again meanwhile, or the queue's reason).
function P.Undo()
    local l = last
    if not l then return false, "nothing" end
    local ok, why
    if l.removed then
        if Q.Find(l.id) then last = nil return false, "exists" end
        local e
        e, why = Q.Add(l.entry, 1)
        ok = e ~= nil
    else
        local e = Q.Find(l.id)
        if not e then last = nil return false, "nothing" end
        ok, why = Q.SetCrafts(l.id, e.crafts + 1)
    end
    if not ok then return false, why end
    last = nil
    local e = Q.Find(l.id)
    return true, { id = l.id, name = l.entry.name, left = e and e.crafts or 1 }
end
function P.CanUndo() return last ~= nil end

function P.Listening() return frame ~= nil end
function P.Stats() return { credited = stats.credited, duplicate = stats.duplicate, refused = stats.refused, seen = #order, auto = P.auto } end
function P.Forget() seen, order = {}, {} end   -- (the tests)

P.Start()
