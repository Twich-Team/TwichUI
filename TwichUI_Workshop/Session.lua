-- TwichUI Workshop: what the window knows and does, without a frame
-- Holds the recipe lists of the player's own professions: those read in the profession window this session, and, for the others, what
-- was remembered from earlier sessions (Known.lua; a read of a profession brings its remembered entry up to date). Turns the saved
-- queue and the bags into the rows the window draws, and performs its actions (add, change, remove, open a recipe), each answering
-- in plain words. Nothing here is saved except through Queue.lua and Known.lua.

local R = TwichUI
local W = R.Workshop
local Q, M, O, KN = W.Queue, W.Materials, W.Observe, W.Known
local PR, Op, SC = W.Prices, W.Opps, W.Scan
local V, Sh = W.Vendor, W.Shopping
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

---------------------------------------------------------------------------
-- What is remembered (Known.lua)
---------------------------------------------------------------------------
-- Brings the remembered professions in, once per time the window has been open (Reset forgets them from memory again; they stay saved).
-- A profession read this session is never replaced by an older remembered one.
local function Ensure()
    if loaded then return end
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
            if not good then ok, why = false, err end
        end
    end
    dirty = {}
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
    S.Save()
    profs, order, current, lastWhy, note = {}, {}, nil, nil, nil
    loaded, dirty = false, {}
    S.filter = ""
    S.opp.prof = nil
    O.ClearCache()
end

function S.Professions()
    Ensure()
    local out = {}
    for _, id in ipairs(order) do
        local p = profs[id]
        out[#out + 1] = { id = id, name = p.profName, count = #p.recipes, selected = id == current }
    end
    return out
end

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
-- The known recipes by id, and by the item they make (each list by recipe id). Built from this session's lists, nothing is asked of the game.
local function Index()
    Ensure()
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

-- Rows and a summary of everything the queue needs against the bags (see Materials.lua)
function S.Materials()
    return M.Rows(QueueView(), O.BagCount)
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

---------------------------------------------------------------------------
-- Opportunities: what one craft costs and could earn (Prices.lua, Opportunities.lua)
---------------------------------------------------------------------------
-- Every recipe known (read this session or remembered), all professions
function S.AllRecipes()
    Ensure()
    local out = {}
    for _, id in ipairs(order) do
        Each(profs[id], function(rec) out[#out + 1] = rec end)
    end
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
    if did and left == 0 then S.Save() end
    return left
end

-- The items worth a saved price: what the known recipes make and need. Returns the set, how many, and whether it was cut.
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

-- The player's click on Scan prices. Returns true, or false and why (Scan.lua says it in words).
function S.StartScan()
    S.FillSome(math.huge)
    local set, _, cut = S.Wanted()
    return SC.Start(set, cut)
end

-- Which saved prices the view uses: with an auction house open, only that one; otherwise the one of this realm scanned last
function S.PriceSource()
    local open = SC.AuctionOpen()
    local key, market
    if open then
        key = SC.Market()
        market = key and PR.Market(key) or nil
    else
        local realm = SC.Realm()
        market = realm and PR.Newest(realm) or nil
    end
    return { open = open, key = key, market = market, label = market and PR.Label(market) or nil }
end

local EMPTY = {
    norecipes = "Open one of your professions to see which crafts could be worth making.",
    noprices = "None of your recipes could be priced from the last scan. Some materials or products had no listings, or a profession wasn't open when you scanned.",
    noprofit = "No profitable crafts at the scanned prices. Turn off Profitable only to see them all.",
    nofilter = "No recipes match this profession.",
}

-- Everything the Opportunities view draws: rows (filtered and sorted), counts, the price source, the cut, and the text for an empty list
function S.Opportunities()
    local src = S.PriceSource()
    local recipes = S.AllRecipes()
    local market = src.market
    local rate = market and PR.CutRate(market.side) or nil
    local lookup = function(item) return market and PR.Lookup(market, item) or nil end
    local all = Op.Rows(recipes, lookup, rate)
    local rows = Op.Select(all, S.opp)
    local out = { rows = rows, summary = Op.Summary(all), source = src, rate = rate, lookup = lookup, incomplete = false }
    for _, id in ipairs(order) do
        if not profs[id].complete then out.incomplete = true end
    end
    if #recipes == 0 then out.state = "norecipes"
    elseif not market then out.state = "noscan"
    elseif out.summary.priced == 0 then out.state = "noprices"
    elseif #rows == 0 then out.state = S.opp.profitOnly and "noprofit" or "nofilter"
    else out.state = "ok" end
    if out.state == "noscan" then
        out.empty = src.open and "No prices for this auction house yet. Choose Scan prices."
            or "No prices saved yet. Open the auction house and choose Scan prices."
    else
        out.empty = EMPTY[out.state]
    end
    return out
end

function S.SortBy(key) Op.SetSort(S.opp, key) end

function S.FilterProfession(id)
    Ensure()
    if id == nil or profs[id] then S.opp.prof = id end
end

function S.ToggleProfitOnly() S.opp.profitOnly = not S.opp.profitOnly end

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
    return true
end

-- The plan for what the queue still needs. Returns plan (Shopping.Plan's), and ctx: { summary (Materials'), source (PriceSource),
-- sellers ([item] = merchants of the NPC collection that were seen to sell it), now }
function S.Shopping()
    local byId, byOut = Index()
    local mrows, msum = M.Rows(QueueView(byId), O.BagCount)
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
        rows = mrows, picks = S.picks, have = O.BagCount,
        auction = function(item) return market and PR.Lookup(market, item) or nil end,
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
    return plan, { summary = msum, source = src, sellers = sellers, now = Q.Now() }
end

local function FindRow(plan, item, kind)
    for _, r in ipairs(plan.rows) do
        if r.item == item and (kind == nil or r.kind == kind) then return r end
    end
end

-- Chooses where a material comes from: kind is "vendor", "auction", "make" or nil (the suggestion)
function S.PickSource(item, kind)
    if kind ~= nil and kind ~= "vendor" and kind ~= "auction" and kind ~= "make" then return false end
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
    note = ("Queued %d %s of %s."):format(mk.crafts, mk.crafts == 1 and "craft" or "crafts", rec.name)
    return true
end

-- The click on Show vendor: shows the vendor seen to sell the item on the world map (the NPC collection's own "find"); it sets no waypoint,
-- starts no route and buys nothing. Returns true, or false (and says why in the note).
function S.ShowVendor(item)
    local sellers = V.Sellers({ [item] = true })[item]
    local rec = V.Entry(item)
    local e = V.Places(sellers, rec and rec.npc, 1)[1]
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
    note = ok and ("Showing %s on the map."):format(e.n) or "The map couldn't show that vendor."
    return ok
end

function S.Snapshot()
    local n = 0
    for _, id in ipairs(order) do n = n + #profs[id].recipes + (profs[id].extra and #profs[id].extra or 0) end
    local realm = SC.Realm()
    local market = realm and PR.Newest(realm) or nil
    local picks = 0
    for _ in pairs(S.picks) do picks = picks + 1 end
    return { professions = #order, recipes = n, queue = Q.Count(), cache = O.CacheSize(), observations = S.observations,
        prices = market and market.n or 0, vendor = V.Count(), picks = picks, scan = SC.state }
end
