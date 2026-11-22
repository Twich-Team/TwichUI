-- TwichUI Workshop: what the window knows and does, without a frame
-- Holds the recipe lists of the player's own professions: those read in the profession window this session, and, for the others, what
-- was remembered from earlier sessions (Known.lua; a read of a profession brings its remembered entry up to date). Turns the saved
-- queue and the bags into the rows the window draws, and performs its actions (add, change, remove, open a recipe), each answering
-- in plain words. Nothing here is saved except through Queue.lua and Known.lua.

local R = TwichUI
local W = R.Workshop
local Q, M, O, KN = W.Queue, W.Materials, W.Observe, W.Known
local PR, Op, SC, MK = W.Prices, W.Opps, W.Scan, W.Pricing or W.Market
local V, Sh = W.Vendor, W.Shopping
-- Strategy.lua loads before this file (the .toc); a test that loads the session alone has no planner and nothing to invalidate
local Sg = W.Strategy or { Bump = function() end, Reset = function() end }
local St, K = W.Storage, W.Stock
local S = { filter = "", observations = 0 }
W.Session = S

local MAX_PROFESSIONS = 5

S.opp = { sort = Op.DEFAULTS.sort, desc = Op.DEFAULTS.desc, prof = nil, profitOnly = false }   -- the Opportunities view's choices (memory only)

local profs = {}       -- [professionID] = { prof, profName, complete, recipes, at, live }   (live: read in the profession window this session)
local order = {}       -- professionIDs, remembered ones first, then in the order first seen
local loaded = false   -- the remembered professions have been brought in
local dirty = {}       -- [professionID] = true: changed since it was last kept
local current          -- the professionID being browsed
local lastWhy          -- why the last read gave nothing, or nil
local note             -- the last thing an action said, until the next action
local lastShop         -- the last finished multilevel shopping package (shown, marked as updating, while a newer plan is computed)
local recipesCache,recipesObservation,recipesCharacter,indexCache,indexRecipes
local opportunityEngine

---------------------------------------------------------------------------
-- How costs are shown: the one Workshop choice of presentation (Strategy.CostText reads Strategy.detailed)
--   TwichUIDB.workshop.view = { prices = "detailed" }   absent (or anything else) means Simple, the default. Account-wide, like the rest of
--   the "workshop" key; a held (newer) workshop record is never changed.
---------------------------------------------------------------------------
function S.PriceDetail()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local v = type(ws) == "table" and ws.view
    return type(v) == "table" and v.prices == "detailed"
end

function S.SetPriceDetail(on)
    if Q.Held() then return false, "held" end
    on = on == true
    if type(TwichUIDB) ~= "table" then return false, "unsaved" end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if not on then Sg.detailed = false return true end
        ws = { v = W.SAVED_VERSION }
        TwichUIDB.workshop = ws
    end
    if type(ws.view) ~= "table" then ws.view = {} end
    ws.view.prices = on and "detailed" or nil
    Sg.detailed = on
    return true
end

-- These account preferences use the existing view record. A future Workshop
-- schema is read-only, as it is for prices, notices and source choices.
function S.Objective()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local v = type(ws) == "table" and ws.view
    return type(v) == "table" and v.objective == "cash" and "cash" or "economic"
end
function S.CompactMode()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local v = type(ws) == "table" and ws.view
    return type(v) == "table" and v.compactMode == "craft" and "craft" or "travel"
end
local function SetViewChoice(key, value, default)
    if Q.Held() then return false, "held" end
    if type(TwichUIDB) ~= "table" then return false, "unsaved" end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if value == default then return true end
        ws = { v = W.SAVED_VERSION }; TwichUIDB.workshop = ws
    end
    if type(ws.view) ~= "table" then ws.view = {} end
    ws.view[key] = value ~= default and value or nil
    return true
end
function S.SetObjective(value)
    if value ~= "economic" and value ~= "cash" then return false, "bad" end
    local before = S.Objective()
    local ok, why = SetViewChoice("objective", value, "economic")
    if ok and before ~= value then Sg.Bump() end
    return ok, why
end
function S.SetCompactMode(value)
    if value ~= "travel" and value ~= "craft" then return false, "bad" end
    return SetViewChoice("compactMode", value, "travel")
end

Sg.detailed = S.PriceDetail()

---------------------------------------------------------------------------
-- What happened this session (memory only, never saved: the Overview's "Recent activity" shows real events, not a history)
---------------------------------------------------------------------------
local activity = {}    -- newest last: { at, text, tone ("done" | "current" | "failed") }
local MAX_ACTIVITY = 8
local lastEnded = 0    -- the scan end (Scan.ended) already recorded

local function Log(text, tone, scan)
    activity[#activity + 1] = { at = Q.Now(), text = text, tone = tone or "done", scan = scan or nil }
    if #activity > MAX_ACTIVITY then table.remove(activity, 1) end
end

-- The player's own actions this session and what the scans did, newest first, at most `n`
function S.Activity(n)
    local out = {}
    for i = #activity, math.max(1, #activity - (n or MAX_ACTIVITY) + 1), -1 do out[#out + 1] = activity[i] end
    return out
end

-- Forgets what was recorded (the tests start each section from nothing; the window never calls it)
function S.ClearActivity() activity = {}; lastEnded = SC.ended end

-- Records a scan that ended (a scan watcher, whether or not the window is open). One entry per end, in the scan's own plain words.
function S.NoteScan()
    if SC.ended == lastEnded then return end
    lastEnded = SC.ended
    Sg.Bump()   -- new prices: every plan is worked out again
    local text, tone = SC.Message()
    if text then Log(text, tone == "good" and "done" or (tone == "warn" and "failed" or "current"), true) end
end
SC.Listen(S.NoteScan)

---------------------------------------------------------------------------
-- What is remembered (Known.lua)
---------------------------------------------------------------------------
-- Brings the remembered professions in, once per time the window has been open (Reset forgets them from memory again; they stay saved).
-- A profession read this session is never replaced by an older remembered one.
local function Ensure()
    if loaded then return end
    if not Q.CharKey() then return end   -- retry when the player's identity is available
    loaded = true
    for _, p in ipairs(KN.Load()) do
        if not profs[p.prof] and #order < MAX_PROFESSIONS then
            profs[p.prof] = p
            order[#order + 1] = p.prof
            if not current then current = p.prof end   -- the most recently read comes first
        end
    end
    table.sort(order, function(a, b) return profs[a].profName:lower() < profs[b].profName:lower() end)
end

-- Calls fn for every recipe of a profession: the ones the window shows, then the ones it doesn't but are still known
local function Each(p, fn)
    for _, rec in ipairs(p.recipes) do fn(rec) end
    if p.extra then for _, rec in ipairs(p.extra) do fn(rec) end end
end
S.Each = Each

-- Keeps what changed. Returns true, or false and why (held by a newer TwichUI, ...). Nothing is written when nothing changed.
function S.Save()
    local ok, why = true, nil
    for id in pairs(dirty) do
        if profs[id] then
            local good, err = KN.Store(profs[id])
            if not good then ok, why = false, err
            else dirty[id] = nil end
        else
            dirty[id] = nil
        end
    end
    return ok, why
end

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
    Ensure()
    S.observations = S.observations + 1
    r.at = Q.Now()
    r.live = true
    -- what was known of this profession (remembered, or read earlier this session) carries over to the recipes read now, so nothing
    -- has to be read again to be known; a list that follows the window's filters keeps the recipes it leaves out (they are still known)
    local old = profs[r.prof]
    if old then
        local byId, here = {}, {}
        for _, rec in ipairs(old.recipes) do byId[rec.id] = rec end
        for _, rec in ipairs(old.extra or {}) do byId[rec.id] = rec end
        for _, rec in ipairs(r.recipes) do
            here[rec.id] = true
            local o = byId[rec.id]
            if o and (o.filled or o.remembered) then
                rec.outItem, rec.outMin, rec.outMax, rec.mats, rec.why = o.outItem, o.outMin, o.outMax, o.mats, o.why
                rec.filled, rec.remembered = o.filled, o.remembered
            end
        end
        -- Whatever the window's list leaves out (filters, or a list that isn't the whole profession) is still known: kept apart, so
        -- browsing follows the list but pricing and saving don't lose it. A remembered recipe goes only when the game listed it
        -- as not learned; absence from a list, a filtered list or an empty one is never evidence.
        local extra = {}
        for _, list in ipairs({ old.recipes, old.extra or {} }) do
            for _, o in ipairs(list) do
                if not here[o.id] and not (r.unlearned and r.unlearned[o.id]) and #r.recipes + #extra < KN.MAX_RECIPES then
                    here[o.id] = true
                    o.diff = nil   -- the old difficulty means nothing now
                    extra[#extra + 1] = o
                end
            end
        end
        if #extra > 0 then r.extra = extra end
    end
    if not profs[r.prof] then
        if #order >= MAX_PROFESSIONS then
            local drop = table.remove(order, 1)
            profs[drop] = nil
            dirty[drop] = nil
        end
        order[#order + 1] = r.prof
    end
    profs[r.prof] = r
    current = r.prof
    dirty[r.prof] = true
    S.Save()
    Sg.Bump()   -- the known recipes changed
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

-- Forgets what is held in memory (the window closed); what changed is kept first, and the saved queue and recipes are untouched
function S.Reset()
    if W.suspended then S.ForgetEstimator()
    elseif opportunityEngine then opportunityEngine:Cancel(opportunityEngine.error~=nil)end
    S.Save()
    -- A failed write is still the only copy. Retain it until a later save can
    -- succeed, without treating its profession as open after the window closes.
    local kept, keptOrder = {}, {}
    for _, id in ipairs(order) do
        if dirty[id] then
            kept[id] = profs[id]
            kept[id].live = nil
            keptOrder[#keptOrder + 1] = id
        end
    end
    profs, order, current, lastWhy, note = kept, keptOrder, nil, nil, nil
    loaded = false
    S.filter = ""
    S.opp.prof = nil
    O.ClearCache()
    Sg.Reset()
    lastShop = nil
end

function S.Professions()
    Ensure()
    local out = {}
    for _, id in ipairs(order) do
        local p = profs[id]
        -- live: read in the profession window this session; at: when it was read (a remembered one: when it was last read)
        out[#out + 1] = { id = id, name = p.profName, count = #p.recipes, known = #p.recipes + (p.extra and #p.extra or 0),
            selected = id == current, live = p.live == true, at = p.at }
    end
    return out
end

-- The character's professions and their skill, read from the game when asked (the Overview draws them; nothing is polled). Returns the list
-- (see Observe.Skills: rank and max are nil when unusable) or nil and "api" when the game has no such call.
function S.Skills() return O.Skills() end

function S.Select(id)
    Ensure()
    if profs[id] then current = id end
end

function S.Current()
    Ensure()
    return current and profs[current] or nil
end

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
        if not p.live then
            out[#out + 1] = ("Remembered from %s. Open %s to update it."):format(PR.AgeText(PR.Age(p.at)), p.profName)
        elseif not p.complete then
            out[#out + 1] = "Follows your profession window's filters; some recipes may not show."
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
    Sg.Bump()
    note = e.mats and ("Added " .. e.name .. ".") or ("Added " .. e.name .. ". Its materials aren't known yet: open its profession to update.")
    Log("Added " .. e.name .. " to plan")
    return true
end

function S.SetCrafts(id, n)
    local ok, why = Q.SetCrafts(id, n)
    if not ok then note = ACTION_WHY[why] or ACTION_WHY.bad end
    if ok then Sg.Bump() end
    return ok
end

function S.Change(id, delta)
    local e = Q.Find(id)
    if not e then return false end
    local n = math.max(1, math.min(W.MAX_CRAFTS, e.crafts + delta))
    return S.SetCrafts(id, n)
end

-- "Crafted one": the player says one craft of a queued recipe is done (Progress.Credit: the queue's own save; the entry goes after its last craft).
-- Never from a click on the game's Craft button and never from a bag count. Returns true, or false (the note says why).
function S.MarkCrafted(id)
    local P = W.Progress
    if not P then return false end
    local ok, info = P.Credit(id)
    if not ok then
        note = ACTION_WHY[info] or (info == "notqueued" and "That recipe isn't in the queue.") or ACTION_WHY.bad
        return false
    end
    Sg.Bump()
    note = W.Notice and W.Notice.CreditText(info) or (info.name .. " crafted.")
    Log(note, info.planDone and "done" or "current")
    return true
end

-- Takes back the player's last "Crafted one" (Progress.Undo). Returns true, or false (the note says why).
function S.UndoCrafted()
    local P = W.Progress
    if not P then return false end
    local ok, info = P.Undo()
    if not ok then
        note = info == "exists" and "That recipe was queued again, so there is nothing to undo." or (info == "nothing" and "Nothing to undo." or (ACTION_WHY[info] or ACTION_WHY.bad))
        return false
    end
    Sg.Bump()
    note = ("Undone: %s, %d %s left."):format(info.name, info.left, info.left == 1 and "craft" or "crafts")
    Log(note, "current")
    return true
end

function S.Remove(id)
    local e = Q.Find(id)
    local ok, why = Q.Remove(id)
    if ok then
        Sg.Bump()
        note = e and ("Removed " .. e.name .. ".") or nil
        if e then Log("Removed " .. e.name .. " from plan", "current") end
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
-- The known recipes by id, and by the item they make (each list by recipe id). Built from this session's lists, nothing is asked of the game.
local function Index()
    Ensure()
    local recipes=S.AllRecipes()
    if indexCache and indexRecipes==recipes then return indexCache[1],indexCache[2]end
    local byId, byOut = {}, {}
    for _, id in ipairs(order) do
        Each(profs[id], function(rec)
            byId[rec.id] = rec
            if rec.outItem and (rec.filled or rec.remembered) then
                local list = byOut[rec.outItem]
                if not list then list = {} byOut[rec.outItem] = list end
                list[#list + 1] = rec
            end
        end)
    end
    for _, list in pairs(byOut) do table.sort(list, function(a, b) return a.id < b.id end) end
    indexCache,indexRecipes={byId,byOut},recipes
    return byId, byOut
end

-- The queue as the materials are worked out from it: an entry saved before the queue kept what a craft makes learns it from the known recipe
-- (a copy; the saved entry is not changed)
local function QueueView(byId)
    local entries, view, missing = Q.Entries(), {}, false
    for _, e in ipairs(entries) do if e.outItem == nil then missing = true end end
    if not missing then return entries end
    byId = byId or Index()
    for i, e in ipairs(entries) do
        local rec = e.outItem == nil and byId[e.id] or nil
        if rec and rec.outItem then
            local c = {}
            for k, v in pairs(e) do c[k] = v end
            c.outItem = rec.outItem
            e = c
        end
        view[i] = e
    end
    return view
end

-- What the remembered bank and guild bank can add to the bags (Stock.lua): the view every part of the window plans with, built once per draw.
-- Nothing is asked of the game except who the character is and which guild it is in.
function S.Stock()
    local bank = W.Bank
    local live = bank and bank.Pending and bank.Pending() or nil
    return K.Sources({ char = Q.CharKey(), guild = O.GuildId() }, St.UseGuild(), live, Q.Now())
end

-- "Use guild bank materials": the player's saved choice (off unless turned on)
function S.UseGuild() return St.UseGuild() end
function S.SetUseGuild(on)
    local ok, why = St.SetUseGuild(on)
    if ok then Sg.Bump() end
    if not ok then note = why == "held" and ACTION_WHY.held or "Couldn't save that choice yet. Try again in a moment." end
    return ok
end

-- Rows and a summary of everything the queue needs against the bags, then the bank and (if chosen) the guild bank (see Materials.lua); the
-- third value is the stock view the rows were made with (its notes and tooltips read it)
function S.Materials()
    local view = S.Stock()
    local rows, sum = M.Rows(QueueView(), O.BagCount, K.Fn(view))
    return rows, sum, view
end

-- The notes about stores that were never seen ("Open your bank with Workshop loaded to update."), only while the queue still needs something
-- from outside the bags, as one line of text; nil when there is nothing to say
function S.StockNote(sum, view)
    if not sum or sum.state == "empty" or sum.state == "ready" then return nil end
    local notes = K.Notes(view)
    if #notes == 0 then return nil end
    return table.concat(notes, " ")
end

-- The words for what has to be collected from storage: "2 from your bank and 1 from the guild bank"
local function CollectWords(sum)
    local parts = {}
    if sum.bankItems > 0 then parts[#parts + 1] = ("%d from your bank"):format(sum.bankItems) end
    if sum.guildItems > 0 then parts[#parts + 1] = ("%d from the guild bank"):format(sum.guildItems) end
    return table.concat(parts, " and ")
end

-- The one sentence under the materials, and its tone ("good", "warn" or "quiet": the words carry the meaning, the tone only colours them)
function S.Headline(sum)
    local function Plural(n, one, many) return n == 1 and one or many end
    if sum.state == "empty" then return "Add recipes to see the materials you need.", "quiet" end
    if sum.state == "ready" then return "Ready to craft: all the materials are in your bags.", "good" end
    if sum.state == "collect" then return ("Collect materials: %s."):format(CollectWords(sum)), "warn" end
    if sum.state == "short" then
        local text = ("Still needed: %d %s."):format(sum.shortItems, Plural(sum.shortItems, "material", "materials"))
        if sum.collectItems > 0 then text = text .. (" %d to collect from storage."):format(sum.collectItems) end
        return text, "warn"
    end
    if sum.unknown > 0 then
        return ("%d %s can't be counted yet. Open %s to update."):format(sum.unknown, Plural(sum.unknown, "recipe", "recipes"),
            Plural(sum.unknown, "its profession", "their professions")), "warn"
    end
    return "Some of your bag counts can't be read yet.", "warn"
end

---------------------------------------------------------------------------
-- Opportunities: what one craft costs and could earn (Prices.lua, Opportunities.lua)
---------------------------------------------------------------------------
-- Every recipe known (read this session or remembered), all professions
function S.AllRecipes()
    Ensure()
    local character=Q.CharKey()
    if recipesCache and recipesObservation==S.observations and recipesCharacter==character then return recipesCache end
    local out = {}
    for _, id in ipairs(order) do
        Each(profs[id], function(rec) out[#out + 1] = rec end)
    end
    recipesCache,recipesObservation,recipesCharacter=out,S.observations,character
    return out
end

-- Reads the output and materials of up to n recipes not read yet (each once). Returns how many are still waiting.
function S.FillSome(n)
    Ensure()
    local left, did = 0, false
    for _, id in ipairs(order) do
        local p = profs[id]
        -- only a profession read this session is asked again: the game may not give the details of one that isn't open, and
        -- what is remembered of it stands until it is read
        if p.live then
            Each(p, function(rec)
                if not rec.filled and not rec.tried then
                    if n > 0 then
                        rec.tried = true
                        O.Fill(rec)
                        if rec.filled then dirty[id], did = true, true end
                        n = n - 1
                    else
                        left = left + 1
                    end
                end
            end)
        end
    end
    if did then recipesCache=nil;Sg.Bump() end
    if did and left == 0 then S.Save() end
    return left
end

-- The items of the known recipes: what a full scan keeps FIRST should the auction house list more items than a market holds. It limits
-- nothing (a scan prices every item, with or without recipes). Returns the set, how many, and whether it was cut.
function S.Wanted()
    Ensure()
    local set, n, cut = {}, 0, false
    local function Add(item)
        if not item or set[item] then return end
        if n >= PR.MAX_ITEMS then cut = true return end
        set[item] = true
        n = n + 1
    end
    for _, id in ipairs(order) do
        Each(profs[id], function(rec)
            if rec.filled or rec.remembered then
                Add(rec.outItem)
                if rec.mats then for _, m in ipairs(rec.mats) do Add(m.item) end end
            end
        end)
    end
    return set, n, cut
end

-- The player's click on Scan prices. Returns true, or false and why (Scan.lua says it in words). Needs no profession: the scan prices
-- every item the auction house lists.
-- opts.auto (A6, Auto.lua only): started on opening the auction house, not by a click. It reads no profession window first (the scan needs no recipe;
-- the recipes only decide which items to keep first when the auction house lists more than the Workshop keeps).
function S.StartScan(opts)
    local auto = type(opts) == "table" and opts.auto == true
    if not auto then S.FillSome(math.huge) end
    local set = S.Wanted()
    return SC.Start(set, { auto = auto })
end

-- Which saved prices the view uses (Market.Source): with an auction house open, only that one; otherwise the one of this realm scanned last
function S.PriceSource() return MK.Source() end

local EMPTY = {
    norecipes = "Open one of your professions to see which crafts could be worth making.",
    noprices = "None of your recipes could be priced from the last scan. Some materials or products had no listings.",
    noprofit = "No profitable crafts at the scanned prices. Turn off Profitable only to see them all.",
    nofilter = "No recipes match this profession.",
    lowonly = "Every priced craft here is Low confidence. Turn off Hide low confidence to see them.",
}

-- What an item sells to a merchant for (C_Item.GetItemInfo's sellPrice), or nil and "loading" while the game loads the item (it is asked for, and
-- GET_ITEM_INFO_RECEIVED redraws the window). 0 is returned as 0: "no vendor value", never a price.
local function VendorSell(item)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(get) ~= "function" then return nil, "api" end
    local ok, name, _, _, _, _, _, _, _, _, _, sell = pcall(get, item)
    if not ok then return nil, "api" end
    if W.Plain(name) == nil then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
        return nil, "loading"
    end
    return W.Int(W.Plain(sell), 0, PR.MAX_COPPER)
end
S.VendorSell = VendorSell

-- The planning estimator (Estimate.lua) over one price source: the same market every price comes from, its local scan for the valuation
-- services, the vendor records, the cut and the deposit (Fees.lua). nil without a market or without Estimate.lua (then Prices.Estimate is used).
-- The estimator is KEPT between draws while nothing its answers depend on changes (the window draws often; every Market service decodes an
-- item's saved tiers per call): the market and its scan, the reference generation, the cut, the vendor records, the Ledger's sales and deposits,
-- the listing duration and an hour of time (ages and the stale rule: their thresholds are a day and more). Anything else (a scan, a merchant, a sale) makes a new one.
local lastEstimator, lastKey, lastCut, lastCutWhy
local feeEvidence,feeRevision
-- Counts alone miss replacement postings with a different amount/duration.
-- Compare only economic evidence when Fees rebuilds its existing cached view;
-- unrelated Ledger activity must not discard completed recipe estimates.
local function FeeRevision(ev)
    if ev==feeEvidence then return feeRevision or 0 end
    local old=feeEvidence
    local equal=old and ev and old.invoices==ev.invoices and old.depositCount==ev.depositCount
        and old.match.faction==ev.match.faction and old.match.neutral==ev.match.neutral
    if equal then
        for item,list in pairs(ev.deposits or {})do
            local before=old.deposits and old.deposits[item]
            if not before or #before~=#list then equal=false;break end
            for i,d in ipairs(list)do if d.per~=before[i].per or d.r~=before[i].r then equal=false;break end end
            if not equal then break end
        end
        if equal then for item in pairs(old.deposits or {})do if not(ev.deposits and ev.deposits[item])then equal=false;break end end end
    end
    if not equal then feeRevision=(feeRevision or 0)+1 end
    feeEvidence=ev;return feeRevision or 0
end
S.ESTIMATE_MEMO_MAX = 20000   -- answers kept at most; beyond it the next draw starts a new estimator
function S.Estimator(src)
    src = src or S.PriceSource()
    local market = src.market
    local Es, Fe, LM = W.Estimate, W.Fees, W.Market
    if not (Es and market) then return nil end
    local lm = market.pricing and market.localMarket or market
    local local_ = lm and { market = lm } or nil
    local cut, cutWhy
    if Fe then cut, cutWhy = Fe.Cut(market.side) end
    -- the Gold Ledger counts only through what the fees read from it (verified sales and deposits): any other gold change (loot, repairs)
    -- moves its revision without changing an estimate
    local ev = Fe and Fe.Evidence and Fe.Evidence() or nil
    local fees = FeeRevision(ev)
    local snap = lm and lm.snap
    local key = table.concat({ tostring(market.key), tostring(market.at), tostring(lm and lm.at), tostring(snap and snap.seq), tostring(SC.ended or 0),
        tostring(market.pricing and MK.ContextGeneration and MK.ContextGeneration()or src.generation or ""),
        tostring(cut and cut.rate), tostring(cut and cut.source), tostring(cutWhy), tostring(not W.OpportunityEngine and V.Count and V.Count() or 0),
        fees, tostring(Fe and Fe.Duration() or 0), tostring(math.floor(Q.Now() / 3600)),
        tostring(Q.CharKey()),tostring(lm and lm.at and Q.Now()-lm.at>Es.STALE_BUY),
        tostring(lm and lm.at and Q.Now()-lm.at>(W.Valuation and W.Valuation.FAIR_AGE or 259200)) }, "|")
    if lastEstimator and lastKey == key then
        if lastEstimator.size>=S.ESTIMATE_MEMO_MAX then lastEstimator:ClearMemo()end
        return lastEstimator, lastCut, lastCutWhy
    end
    local function Local(fn) return (LM and LM[fn] and local_) and fn or nil end
    local ctx = {
        cut = cut, cutWhy = cutWhy,
        price = function(item) return MK.Price(item, { market = market }) end,
        cost = MK.Cost and function(item, qty) return MK.Cost(item, qty, { market = market, fromCompeting = true }) end or nil,
        competition = Local("Competition") and function(item) return LM.Competition(item, nil, local_) end or nil,
        value = Local("Value") and function(item, kind) return LM.Value(item, kind, local_) end or nil,
        quality = Local("Quality") and function(item) return LM.Quality(item, local_) end or nil,
        supply = Local("Supply") and function(item) return LM.Supply(item, local_) end or nil,
        reference = (market.pricing and W.Pricing and W.Pricing.Reference) and function(item) return W.Pricing.Reference(item, { market = market }) end or nil,
        vendor = V.Entry,
        vendorSell = VendorSell,
        deposit = Fe and function(item, qty) return Fe.Deposit(item, qty) end or nil,
    }
    local est = Es.New(ctx)
    lastEstimator, lastKey, lastCut, lastCutWhy = est, key, cut, cutWhy
    return est, cut, cutWhy
end
function S.EstimatorSize() return lastEstimator and lastEstimator.size or 0 end
function S.ForgetEstimator()
    lastEstimator,lastKey=nil,nil
    if opportunityEngine then opportunityEngine:Cancel(true)end
end
function S.ItemsChanged(items)
    if lastEstimator and(not opportunityEngine or not opportunityEngine.args or opportunityEngine.args.estimator~=lastEstimator)then
        for item in pairs(items or {})do lastEstimator:InvalidateItem(item)end
    end
    if opportunityEngine then opportunityEngine:ItemsChanged(items)end
end
function S.OpportunityStatus()return opportunityEngine and opportunityEngine:Status()or {}end
function S.OpportunityItemRevision(item)return opportunityEngine and opportunityEngine.versions[item]or 0 end
function S.PrioritizeOpportunities(ids)if opportunityEngine then opportunityEngine:Prioritize(ids)end end
function S.PauseOpportunities()if opportunityEngine then opportunityEngine:Cancel(false)end end
function S.RetryOpportunities()if opportunityEngine then opportunityEngine:RetryWaiting()end end
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("workshop.estimate", { label = "Workshop: answers kept by the last Opportunities estimate", kind = "cache", group = "workshop", unit = "count", read = S.EstimatorSize })
end

-- Everything the Opportunities view draws: rows (filtered and sorted), counts, the price source, the cut, and the text for an empty list
function S.Opportunities()
    local pt = R.Perf and R.Perf.on and R.Perf.Start("workshop.estimate")
    local src = S.PriceSource()
    local recipes = S.AllRecipes()
    local market = src.market
    local estimator, cut, cutWhy = S.Estimator(src)
    local rate
    if estimator then rate = cut and cut.rate or nil
    else rate = market and PR.CutRate(market.side) or nil end
    local lookup = function(item) return market and MK.Price(item, { market = market }) or nil end
    local all,rows,summary,calculating,positions,viewRevision,progress,criteria
    if W.OpportunityEngine then
        if not opportunityEngine then opportunityEngine=W.OpportunityEngine.New(function()if W.Active()and W.UI and W.UI.Redraw then W.UI.Redraw()end end)end
        local key=estimator and lastKey or 'none:'..tostring(src.label)
        local sourceVersion=market and market.pricing and MK.ContextGeneration()
        local lm=market and(market.pricing and market.localMarket or market)
        local localAt,seq,ended=lm and lm.at,lm and lm.snap and lm.snap.seq,SC.ended
        opportunityEngine:Request({recipes=recipes,key=key,estimator=estimator,lookup=lookup,rate=rate,filter=S.opp,now=Q.Now(),
            prefetch=market and market.pricing and MK.PrepareBucket and function(ids,work)MK.PrepareBucket(ids,work,opportunityEngine)end,
            release=MK.ReleasePreparation and function()MK.ReleasePreparation(opportunityEngine)end,
            ready=market and market.pricing and MK.Ready,settled=MK.Settled,
            valid=function()
                return (not sourceVersion or sourceVersion==MK.ContextGeneration())and SC.ended==ended
                    and(not lm or lm.at==localAt and(lm.snap and lm.snap.seq)==seq)
            end,
            current=function()
                local source=S.PriceSource()
                if not estimator then return source.market==nil end
                S.Estimator(source);return lastKey==key
            end})
        all,rows,summary=opportunityEngine.all,opportunityEngine.rows,opportunityEngine.summary
        if next(opportunityEngine.incoming)then summary={total=summary.total,priced=0,profitable=0,refreshing=true}end
        progress=opportunityEngine:Status();calculating=progress.refreshing;positions=opportunityEngine.positions;viewRevision=opportunityEngine.viewRevision
        criteria=opportunityEngine.filterKey
    else
        if R.Perf and R.Perf.on then R.Perf.Count('workshop.pricing.fullLists')end
        all=Op.Rows(recipes,lookup,rate,nil,estimator);rows=Op.Select(all,S.opp);summary=Op.Summary(all)
    end
    if pt then R.Perf.Stop(pt) end
    -- Whether one craft's materials are in the bags or in storage, asked only for the rows the window draws (each answer reads bag counts) and kept
    -- apart from the estimate: stored materials never lower a cost or raise a profit.
    local view, counts = S.Stock(), {}
    local function Have(item)
        local n = counts[item]
        if n == nil then n = O.BagCount(item) or false counts[item] = n end
        return n or nil
    end
    -- all: every row before the page's filter and sort (the Overview reads its best one; nothing is priced twice)
    local out = { rows = rows, all = all, summary = summary, source = src, rate = rate, cut = cut, cutWhy = cutWhy, estimator = estimator, lookup = lookup, incomplete = false, stock = view,
        calculating=calculating,positions=positions,viewRevision=viewRevision,progress=progress,criteria=criteria,
        avail = function(rec) return K.Craft(rec.mats, Have, view) end }
    for _, id in ipairs(order) do
        if not profs[id].complete then out.incomplete = true end
    end
    if opportunityEngine and opportunityEngine.error then out.state='calculation_failed'
    elseif #recipes == 0 then out.state = "norecipes"
    elseif not market then out.state = "noscan"
    elseif calculating then out.state='calculating'
    elseif out.summary.priced == 0 then out.state = "noprices"
    elseif #rows == 0 then out.state = S.opp.profitOnly and "noprofit" or (S.opp.hideLow and #Op.Select(all, { prof = S.opp.prof }) > 0 and "lowonly" or "nofilter")
    else out.state = "ok" end
    if out.state == "noscan" then
        out.empty = src.open and "No prices for this auction house yet. Choose Scan prices."
            or "No prices saved yet. Open the auction house and choose Scan prices."
    else
        out.empty = out.state=='calculation_failed'and 'These calculations could not be completed. Change the source or reopen Workshop to retry.'or
            out.state=='calculating'and 'Calculating prices... Ranking is provisional.'or EMPTY[out.state]
    end
    return out
end

function S.SortBy(key) Op.SetSort(S.opp, key) end

function S.FilterProfession(id)
    Ensure()
    if id == nil or profs[id] then S.opp.prof = id end
end

function S.ToggleProfitOnly() S.opp.profitOnly = not S.opp.profitOnly end
function S.ToggleHideLow() S.opp.hideLow = not S.opp.hideLow end

-- What the queue's crafts are estimated to cost and earn: the Opportunities estimate of each queued recipe (one craft) times its crafts,
-- by recipe id, and the totals over those that could be priced. Nothing is estimated here: a recipe the estimate can't price is counted
-- in `unpriced` and left out of the totals, never taken as free. `v` may be a draw's S.Opportunities() so nothing is priced twice.
--   byId[id] = { crafts, cost, sellLow, sellHigh, profitLow, profitHigh, confidence, absorb, deposit, cooldown } or nil (not priced)
--   totals   { entries, priced, unpriced, crafts, cost, sellLow, sellHigh, profitLow, profitHigh, rate, deposit (the deposits known), low (Low
--            confidence entries), absorb (entries that would sell more than the market holds) }
-- With the planning estimator (Estimate.lua) a queued recipe of several crafts is estimated for all of them at once.
function S.PlanEstimates(v)
    local entries = Q.Entries()
    local byId, t = {}, { entries = #entries, priced = 0, unpriced = 0, crafts = 0, cost = 0, sellLow = 0, sellHigh = 0, profitLow = 0, profitHigh = 0 }
    if #entries == 0 then return byId, t end
    v = v or S.Opportunities()
    t.rate = v.rate
    local rows, recs = {}, {}
    for _, r in ipairs(v.all) do rows[r.rec.id] = r.est recs[r.rec.id] = r.rec end
    for _, e in ipairs(entries) do
        t.crafts = t.crafts + e.crafts
        local est = rows[e.id]
        -- the planning estimate of the queued number of crafts: materials walk the listings for the whole quantity and selling that many is
        -- checked against what is listed (never one craft's figures multiplied)
        if v.estimator and recs[e.id] and e.crafts > 1 then est = v.estimator:Craft(recs[e.id], e.crafts) end
        local mult = (v.estimator and recs[e.id]) and 1 or e.crafts
        if est and est.state == "ok" then
            local x = { reference=est.reference, crafts = e.crafts, cost = est.cost * mult, sellLow = est.sellLow * mult, sellHigh = est.sellHigh * mult,
                profitLow = est.profitLow * mult, profitHigh = est.profitHigh * mult, confidence = est.confidence, absorb = est.absorb,
                deposit = est.depositTotal, cooldown = est.cooldown }
            byId[e.id] = x
            t.reference=t.reference or est.reference
            t.priced = t.priced + 1
            t.cost, t.sellLow, t.sellHigh = t.cost + x.cost, t.sellLow + x.sellLow, t.sellHigh + x.sellHigh
            t.profitLow, t.profitHigh = t.profitLow + x.profitLow, t.profitHigh + x.profitHigh
            if x.deposit then t.deposit = (t.deposit or 0) + x.deposit end
            if x.confidence == "low" then t.low = (t.low or 0) + 1 end
            if x.absorb then t.absorb = (t.absorb or 0) + 1 end
        else
            t.unpriced = t.unpriced + 1
        end
    end
    return byId, t
end

-- Queued consumers of a material (one level, no catalog search). The second return
-- supplies recorded output identities for presentation; existing name-list callers keep their contract.
function S.NeededFor(item)
    local out, records = {}, {}
    for _, e in ipairs(Q.Entries()) do
        if e.mats then
            for _, m in ipairs(e.mats) do
                if m.item == item then
                    out[#out + 1] = e.name
                    records[#records + 1] = { name = e.name, item = e.outItem, recipe = e.id, icon = e.icon }
                    break
                end
            end
        end
    end
    return out, records
end

---------------------------------------------------------------------------
-- The shopping list (Shopping.lua): the materials still needed, where to get each, and what it may cost
---------------------------------------------------------------------------
S.picks = {}   -- the player's source choices: [item] = "vendor" | "auction" | "make". Memory only, kept while the item is on the list.

-- The materials of every known recipe and of the queue: the vendor prices worth keeping
function S.WantedMaterials()
    Ensure()
    local set = {}
    for _, id in ipairs(order) do
        Each(profs[id], function(rec)
            if rec.mats then for _, m in ipairs(rec.mats) do set[m.item] = true end end
        end)
    end
    for _, e in ipairs(Q.Entries()) do
        if e.mats then for _, m in ipairs(e.mats) do set[m.item] = true end end
    end
    return set
end

-- The merchant window just opened or changed: keep what its money-only listings charge for the materials this character's recipes use.
-- Returns true, or false and why. Reads and saves nothing else.
function S.ReadMerchant()
    local list, npc = O.ReadMerchant()
    if not list then return false, npc end
    local kept, why = V.Observe(list, S.WantedMaterials(), npc)
    if kept == false then return false, why end
    Sg.Bump()
    return true
end

-- The plan for what the queue still needs. Returns plan (Shopping.Plan's), and ctx: { summary (Materials'), source (PriceSource),
-- sellers ([item] = merchants of the NPC collection that were seen to sell it), now }
function S.Shopping()
    local byId, byOut = Index()
    local view = S.Stock()
    local stock = K.Fn(view)
    local mrows, msum = M.Rows(QueueView(byId), O.BagCount, stock)
    local src = S.PriceSource()
    local market = src.market
    -- the items a merchant could matter for: what is needed and the reagents of anything that could make it
    local wanted = {}
    for _, r in ipairs(mrows) do
        if r.short == nil or r.short > 0 then
            wanted[r.item] = true
            for _, rec in ipairs(byOut[r.item] or {}) do
                if rec.mats then for _, m in ipairs(rec.mats) do wanted[m.item] = true end end
            end
        end
    end
    local sellers = V.Sellers(wanted)
    local inp = {
        rows = mrows, picks = S.picks, have = O.BagCount, stock = stock,
        stockMeta = function(item, where) return K.Meta(view, item, where) end,
        auction = function(item) return market and MK.Price(item, { market = market }) or nil end,
        -- the quantity-aware price (A7): Market.Cost over the very market the prices come from; none without a market (the plan then uses the unit quote)
        cost = (market and MK.Cost) and function(item, qty) return MK.Cost(item, qty, { market = market }) end or nil,
        vendor = V.Entry,
        sells = function(item) return sellers[item] ~= nil end,
        recipes = function(item) return byOut[item] or {} end,
        queued = function(id) return Q.Find(id) end,
    }
    local plan = Sh.Plan(inp)
    -- a choice stays while its material is part of the queue's needs or of the plan; otherwise it is forgotten (bounded)
    local keep = {}
    for _, r in ipairs(mrows) do keep[r.item] = true end
    for _, r in ipairs(plan.rows) do keep[r.item] = true end
    for item in pairs(S.picks) do
        if not keep[item] then S.picks[item] = nil end
    end
    return plan, { summary = msum, source = src, sellers = sellers, now = Q.Now(), stock = view }
end

---------------------------------------------------------------------------
-- The multilevel strategy (Strategy.lua, over the P1 planner): Opportunities, the Crafting Plan and Shopping
---------------------------------------------------------------------------
local function PicksSig()
    local items = {}
    for item in pairs(S.picks) do items[#items + 1] = item end
    table.sort(items)
    local out = {}
    for _, item in ipairs(items) do out[#out + 1] = item .. "=" .. tostring(S.picks[item]) end
    return table.concat(out, ",")
end

-- The key of one planning snapshot: the epoch (anything that invalidates plans), what the plan is about, the queue, the player's source choices,
-- the guild bank choice and what was seen of the bank and guild bank, the price source and its scan, the vendor prices and the known recipes. A
-- result is only ever used for the key it was made for.
function S.PlanKey(scope, entries, view, src, extra, nopicks)
    local q, bags, seen = {}, {}, {}
    for i, e in ipairs(entries) do
        q[i] = tostring(e.id) .. ":" .. tostring(e.crafts)
        -- what the bags hold of the entries' own materials (a bag event also invalidates every plan; this keeps a missed event from showing an old plan)
        for _, m in ipairs(e.mats or {}) do
            if not seen[m.item] then
                seen[m.item] = true
                bags[#bags + 1] = tostring(O.BagCount(m.item))
            end
        end
    end
    local g, b, mk = view.guild, view.bank, src.market
    -- what the remembered bank and guild bank can supply right now (a tab turning uncertain, or read again, changes it without a new time)
    local stock = table.concat({ tostring(g.tabs), tostring(g.unread), tostring(g.uncertain), tostring(g.limitedTabs), b.counted and "B" or "b", tostring(b.tabs) }, ".")
    return table.concat({ Sg.epoch, scope, S.Objective(), extra or "", table.concat(q, ","), table.concat(bags, ","), nopicks and "" or PicksSig(), g.enabled and "G" or "g", tostring(g.at or 0),
        tostring(b.at or 0), stock, mk and (tostring(src.label) .. "@" .. tostring(mk.at) .. ":" .. tostring(src.generation or "")) or "none", tostring(SC.ended or 0), V.Count(), V.Revision and V.Revision()or 0, S.observations }, "|")
end

-- the planner's input for a list of queue-shaped entries: Shopping's functions over the same price, vendor, stock and recipe services
local function PlanInput(entries, byOut, view, src, nopicks)
    local market = src.market
    local sellers
    return {
        entries = entries, have = O.BagCount, stock = K.Fn(view), picks = nopicks and {} or S.picks,
        stockMeta = function(item, where) return K.Meta(view, item, where) end,
        auction = function(item) return market and MK.Price(item, { market = market }) or nil end,
        cost = (market and MK.Cost) and function(item, qty) return MK.Cost(item, qty, { market = market }) end or nil,
        vendor = V.Entry,
        sells = function(item)
            if not sellers then sellers = V.Sellers(S.WantedMaterials()) end
            return sellers[item] ~= nil
        end,
        recipes = function(item) return byOut[item] or {} end,
    }
end

-- the queue entry of a known recipe for one craft (a recipe the planner is asked about, not a queued one)
local function RecipeEntry(rec, crafts)
    return { id = rec.id, name = rec.name, crafts = crafts or 1, mats = rec.mats, outItem = rec.outItem, outMin = rec.outMin, outMax = rec.outMax }
end

-- Can this recipe be planned and queued: its materials and a fixed output are known
local function Plannable(rec)
    if not (rec and type(rec.mats) == "table" and #rec.mats > 0 and rec.outItem and rec.outMin) then return false end
    return rec.outMin == (rec.outMax or rec.outMin)
end

-- The whole queue's plan. Returns state ("ready" | "planning" | "failed" | "empty"), the planner's plan (nil unless ready), why, and the pieces
-- the pages need: { entries, mrows, msum, view, src, byId, byOut }.
local function QueuePlan()
    local byId, byOut = Index()
    local view = S.Stock()
    local entries = QueueView(byId)
    local mrows, msum = M.Rows(entries, O.BagCount, K.Fn(view))
    local src = S.PriceSource()
    local env = { entries = entries, mrows = mrows, msum = msum, view = view, src = src, byId = byId, byOut = byOut }
    if #entries == 0 then return "empty", nil, nil, env end
    local key = S.PlanKey("queue", entries, view, src)
    env.key = key
    local state, plan, why = Sg.Request("queue", key, function() return PlanInput(entries, byOut, view, src), { objective = S.Objective() } end)
    return state, plan, why, env
end

-- The queue's strategy for the Crafting Plan page: state, plan, why
function S.QueueStrategy()
    local state, plan, why = QueuePlan()
    return state, plan, why
end

-- The shopping list from the multilevel plan. Returns plan (Shopping.Plan's shape: rows, totals, unknownBags, and engine), ctx (as S.Shopping's
-- plus engine and stale) and the state: "ready", "planning" (plan is the last finished one, marked ctx.stale, or an empty list), or "basic" (the
-- planner failed: Shopping's own one-level plan is shown, and says so). A basic plan is never presented as the multilevel one.
function S.ShoppingPlan()
    local state, cp, why, env = QueuePlan()
    local function Ctx(extra)
        local sellers = {}
        local wanted = {}
        for _, r in ipairs(env.mrows) do wanted[r.item] = true end
        if extra then for _, r in ipairs(extra.rows) do wanted[r.item] = true end end
        sellers = V.Sellers(wanted)
        return { summary = env.msum, source = env.src, sellers = sellers, now = Q.Now(), stock = env.view }
    end
    if state == "failed" then
        local plan, ctx = S.Shopping()
        plan.engine, ctx.engine, ctx.why = "basic", "basic", why
        return plan, ctx, "basic"
    end
    if state == "ready" or state == "empty" then
        local plan
        if state == "empty" then
            plan = { rows = {}, totals = { cash = 0, low = 0, high = 0, open = false, priced = 0, missing = 0, estimate = false, makes = 0, incomplete = false, collect = 0 },
                unknownBags = 0, engine = "multilevel" }
        else
            local inp = PlanInput(env.entries, env.byOut, env.view, env.src)
            -- the player's own choices: what Workshop would suggest without them is worked out as a second plan (only while choices exist)
            local suggest
            if next(S.picks) then
                local skey = S.PlanKey("suggest", env.entries, env.view, env.src, nil, true)
                local st, sp = Sg.Request("suggest", skey, function() return PlanInput(env.entries, env.byOut, env.view, env.src, true), { objective = S.Objective() } end)
                if st == "ready" and sp then
                    suggest = {}
                    for _, l in ipairs(sp.items) do
                        if l.source == "make" or l.source == "vendor" or l.source == "auction" then suggest[l.item] = l.source end
                    end
                end
            end
            plan = Sg.Adapt(cp, { mrows = env.mrows, inp = inp, recById = function(id) return env.byId[id] end, stockMeta = inp.stockMeta, suggest = suggest })
        end
        local ctx = Ctx(plan)
        ctx.engine = "multilevel"
        -- a choice stays while its material is part of the queue's needs or of the plan; otherwise it is forgotten (bounded)
        local keep = {}
        for _, r in ipairs(env.mrows) do keep[r.item] = true end
        for _, r in ipairs(plan.rows) do keep[r.item] = true end
        if cp then for _, l in ipairs(cp.items or {}) do keep[l.item] = true end end
        for item in pairs(S.picks) do
            if not keep[item] then S.picks[item] = nil end
        end
        lastShop = { plan = plan, ctx = ctx, key = env.key }
        return plan, ctx, "ready"
    end
    -- planning: the last finished list is shown but marked as not current; with none, an empty list says it is being worked out
    if lastShop then
        local ctx = {}
        for k, v in pairs(lastShop.ctx) do ctx[k] = v end
        ctx.stale = true
        return lastShop.plan, ctx, "planning"
    end
    local plan = { rows = {}, totals = { cash = 0, low = 0, high = 0, open = false, priced = 0, missing = 0, estimate = false, makes = 0, incomplete = false, collect = 0 },
        unknownBags = 0, engine = "multilevel" }
    local ctx = Ctx(plan)
    ctx.engine, ctx.stale, ctx.first = "multilevel", true, true
    return plan, ctx, "planning"
end

-- One recipe's strategy for Opportunities: the recipe made once, on its own (the queue is not part of it). Returns state ("ready" | "planning" |
-- "failed" | "unknown" when its materials or output aren't known), the plan, why.
function S.OppStrategy(rec)
    if not Plannable(rec) then return "unknown", nil, "Its materials or what it makes aren't known yet, or it makes a varying amount." end
    local byId, byOut = Index()
    local view, src = S.Stock(), S.PriceSource()
    local entries = { RecipeEntry(rec, 1) }
    local key = S.PlanKey("opp", entries, view, src)
    local state, plan, why = Sg.Request("opp", key, function() return PlanInput(entries, byOut, view, src), { objective = S.Objective() } end)
    return state, plan, why
end

-- The plan a confirmation would apply: the queue as it is now, plus `rec` made once when it is not queued yet. Returns state, plan, ops (Strategy.Ops)
-- and the key the plan was made for (ApplyOptimized checks it again). The queue is not changed.
function S.PreviewOptimized(rec)
    local byId, byOut = Index()
    local view, src = S.Stock(), S.PriceSource()
    local entries = {}
    for i, e in ipairs(QueueView(byId)) do entries[i] = e end
    local final
    if rec and not Q.Find(rec.id) then
        if not Plannable(rec) then return "unknown", nil, nil, nil, "Its materials or what it makes aren't known yet." end
        entries[#entries + 1] = RecipeEntry(rec, 1)
        final = { id = rec.id, name = rec.name, crafts = 1, outItem = rec.outItem }
    end
    if #entries == 0 then return "empty" end
    local key = S.PlanKey("confirm", entries, view, src, rec and rec.id or nil)
    local state, plan, why = Sg.Request("confirm", key, function() return PlanInput(entries, byOut, view, src), { objective = S.Objective() } end)
    if state ~= "ready" then return state, nil, nil, key, why end
    return state, plan, Sg.Ops(plan, final), key
end

local OPT_WHY = {
    changed = "Your plan changed while you were looking. Review the updated list.",
    nothing = "Nothing to add: your queue already covers that.",
    unknown = "A recipe in the plan isn't known any more, so nothing was added.",
}

-- The player confirmed: adds the plan's crafts to the queue as one change (Queue.AddBatch), after checking again that the plan was made for the queue
-- as it is now. Returns true, or false and why ("changed", "nothing", "unknown", or the queue's reason).
function S.ApplyOptimized(key, rec)
    local byId = Index()
    local view, src = S.Stock(), S.PriceSource()
    local entries = {}
    for i, e in ipairs(QueueView(byId)) do entries[i] = e end
    local extra = rec and not Q.Find(rec.id) and rec or nil
    if extra then entries[#entries + 1] = RecipeEntry(extra, 1) end
    local cur = S.PlanKey("confirm", entries, view, src, rec and rec.id or nil)
    local plan = key and cur == key and Sg.Peek("confirm", key) or nil
    if not plan then
        note = OPT_WHY.changed
        return false, "changed"
    end
    local ops = {}
    for _, c in ipairs(plan.crafts) do
        local r = byId[c.recipe]
        if not r then note = OPT_WHY.unknown return false, "unknown" end
        O.Fill(r)
        ops[#ops + 1] = { rec = r, crafts = c.crafts }
    end
    if extra then O.Fill(extra); ops[#ops + 1] = { rec = extra, crafts = 1 } end
    if #ops == 0 then note = OPT_WHY.nothing return false, "nothing" end
    local ok, res = Q.AddBatch(ops)
    if not ok then
        note = ACTION_WHY[res] or (res == "toomany" and "That would be more crafts than a queue entry can hold.") or ACTION_WHY.bad
        return false, res
    end
    for _, c in ipairs(plan.crafts) do S.picks[c.item] = nil end
    Sg.Bump()
    local n = #ops
    if n == 1 then
        note = ("Queued %d %s of %s."):format(ops[1].crafts, ops[1].crafts == 1 and "craft" or "crafts", ops[1].rec.name)
    else
        note = ("Added %d recipes to your crafting plan."):format(n)
    end
    Log(note)
    return true
end

-- The buy or make row of an item (a collect row is never the one a source is chosen for: the same item can have both)
local function FindRow(plan, item, kind)
    for _, r in ipairs(plan.rows) do
        if r.item == item and r.kind ~= "collect" and (kind == nil or r.kind == kind) then return r end
    end
end

-- Chooses where a material comes from: kind is "vendor", "auction", "make" or nil (the suggestion)
function S.PickSource(item, kind)
    if kind ~= nil and kind ~= "vendor" and kind ~= "auction" and kind ~= "make" then return false end
    if S.picks[item] ~= kind then Sg.Bump() end
    S.picks[item] = kind
    return true
end

-- Click on a row's source: the suggestion, then each option that can be chosen, then the suggestion again. Recalculated from now's plan.
function S.CycleSource(item)
    local plan = S.Shopping()
    local row = FindRow(plan, item)
    if not row then return false end
    local choices = Sh.Choices(row)
    local nextKind
    if not row.picked then
        nextKind = choices[1]
    else
        for i, k in ipairs(choices) do
            if k == row.source then nextKind = choices[i + 1] break end
        end
    end
    if S.picks[item] ~= nextKind then Sg.Bump() end
    S.picks[item] = nextKind
    return true
end

-- Adds the crafts that make a short material to the queue (the player's explicit action). The queue then makes it, so the plan no longer
-- counts it as short and its materials are the queue's own needs: nothing is counted twice, and a second click finds nothing to add.
function S.AddSubcraft(item)
    local plan = S.Shopping()
    local row = FindRow(plan, item, "make")
    if not row then
        note = "Nothing to add: your queue already covers that."
        return false
    end
    local mk = row.make
    local rec = mk.rec
    O.Fill(rec)
    local e = Q.Find(rec.id)
    local ok, why
    if e then
        if e.crafts + mk.crafts > W.MAX_CRAFTS then
            note = "That would be more crafts than a queue entry can hold."
            return false
        end
        ok, why = Q.SetCrafts(rec.id, e.crafts + mk.crafts)
    else
        local added
        added, why = Q.Add(rec, mk.crafts)
        ok = added ~= nil
    end
    if not ok then
        note = ACTION_WHY[why] or ACTION_WHY.bad
        return false
    end
    S.picks[item] = nil
    Sg.Bump()
    note = ("Queued %d %s of %s."):format(mk.crafts, mk.crafts == 1 and "craft" or "crafts", rec.name)
    return true
end

-- A waypoint on a merchant, named after it where that can be done. With WaypointUI loaded, its public API (WaypointUIAPI.Navigation.
-- NewUserNavigation: name, map, x and y in percent; it sets and tracks the game's waypoint itself) makes a waypoint that carries the NPC's name.
-- Without it, or if it refuses or fails, the game's own waypoint (the NPC collection's NpcMap.SetWaypoint, which has no name: the game's waypoint
-- has none) is set and tracked. Returns true and "named" | "game", or false.
local function Waypoint(NMAP, e)
    local api = type(WaypointUIAPI) == "table" and type(WaypointUIAPI.Navigation) == "table" and WaypointUIAPI.Navigation or nil
    local NS = R.NpcStore
    if api and type(api.NewUserNavigation) == "function" and NS and NS.COORD then
        local ok, nav = pcall(api.NewUserNavigation, { name = e.n, mapID = e.m, x = e.x / NS.COORD * 100, y = e.y / NS.COORD * 100 })
        if ok and nav then return true, "named" end
    end
    if NMAP.SetWaypoint and NMAP.SetWaypoint(e) then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        return true, "game"
    end
    return false
end

-- The click on Show vendor: shows the vendor seen to sell the item on the world map (the NPC collection's own "find") and puts the game's own
-- waypoint on it, tracked, so its marker shows in the world (Waypoint above: named after the NPC through WaypointUI when it is loaded; it replaces
-- the waypoint you had, as setting one in the game does, and only on this click). It starts no route and buys nothing. Returns true, or false (and says why in the note).
function S.ShowVendor(item)
    local sellers = V.Sellers({ [item] = true })[item]
    local rec = V.Entry(item)
    local places, how = V.Places(sellers, rec and rec.npc, 3)
    local e = places[1]
    if not e then
        note = "No vendor location is known for that item."
        return false
    end
    local NMAP = R.NpcMap
    if not (NMAP and NMAP.Locate) then
        note = "Vendors and trainers isn't available, so the vendor can't be shown."
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        note = "The map can be opened when combat ends."
        return false
    end
    if WorldMapFrame and WorldMapFrame.IsShown and not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
    local ok = NMAP.Locate(e)
    -- the game's waypoint on the seller, tracked: placed even if the map couldn't be shown (the marker is the way to find it)
    local marked = Waypoint(NMAP, e)
    -- the words say only what is known: "nearest" for a compared distance, "in this area" for the same map, otherwise how many others are known
    local more = #sellers - 1
    if not ok then note = marked and ("Waypoint set on %s; the map couldn't show it."):format(e.n) or "The map couldn't show that vendor."
    elseif how == "nearest" then note = ("Showing %s, the nearest known seller."):format(e.n)
    elseif how == "local" then note = ("Showing %s, a seller in this area."):format(e.n)
    elseif more > 0 then note = ("Showing %s. %d other %s known."):format(e.n, more, more == 1 and "seller is" or "sellers are")
    else note = ("Showing %s on the map."):format(e.n) end
    if ok and marked then note = note .. " Waypoint set." end
    return ok or marked
end

function S.Snapshot()
    local n = 0
    for _, id in ipairs(order) do n = n + #profs[id].recipes + (profs[id].extra and #profs[id].extra or 0) end
    local realm = SC.Realm()
    local market = realm and PR.Newest(realm) or nil
    local picks = 0
    for _ in pairs(S.picks) do picks = picks + 1 end
    return { professions = #order, recipes = n, queue = Q.Count(), cache = O.CacheSize(), observations = S.observations,
        prices = market and market.n or 0, history = market and market.histItems or 0, vendor = V.Count(), picks = picks, marketFacts = W.Facts and W.Facts.CacheSize() or 0, scan = SC.state, stored = St.Counts() }
end
