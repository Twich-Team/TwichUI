-- A8: bounded discovery and evidence adapter. Identity sources are bags, the selected
-- saved market, this character's known recipes and explicit tracked items. No scan.
local R = TwichUI
local W = R.Workshop
local D = { BATCH = 160, TRACK_MAX = 200 }
W.AdvisorData = D
local S, A, O = W.Session, W.Advisor, W.Observe
local function View(create)
    if W.Queue.Held() and create then return nil end
    local db = type(TwichUIDB) == "table" and TwichUIDB.workshop
    if type(db) ~= "table" then
        if not create or type(TwichUIDB) ~= "table" then return nil end
        db = { v = W.SAVED_VERSION }; TwichUIDB.workshop = db
    end
    if type(db.view) ~= "table" then if not create then return nil end db.view = {} end
    return db.view
end
function D.Selected() local v = View(); return v and W.Int(v.advisorItem, 1, W.MAX_ID) end
local sources = { bags=true, tracked=true, all=true }
function D.Source()
    local v=View()
    return v and sources[v.advisorSource] and v.advisorSource or "bags"
end
function D.SetSource(value)
    local v=sources[value] and View(true)
    if not v then return false end
    v.advisorSource=value
    return true
end
function D.Select(item)
    item = W.Int(item, 1, W.MAX_ID)
    local v = item and View(true)
    if not v then return false end
    v.advisorItem = item
    return true
end
function D.Tracked()
    local v = View()
    return v and type(v.advisorTracked) == "table" and v.advisorTracked or {}
end
function D.Track(item)
    item = W.Int(item, 1, W.MAX_ID)
    local v = item and View(true)
    if not v then return false end
    local old, t, n = D.Tracked(), {}, 0
    for id, on in pairs(old) do
        if on == true and W.Int(id, 1, W.MAX_ID) and id ~= item and n < D.TRACK_MAX then t[id], n = true, n + 1 end
    end
    if not old[item] then if n >= D.TRACK_MAX then return false end t[item] = true end
    v.advisorTracked = t
    return true
end
function D.Info(item)
    local name, link, quality, _, _, kind, sub, _, equip, icon, sell, class, _, bind
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, kind, sub, _, equip, icon, sell, class, _, bind = C_Item.GetItemInfo(item)
    end
    return { item = item, known = W.Text(name,200)~=nil, name = W.Text(name, 200) or ("Item " .. item), link = W.Text(link, 1000), quality = W.Int(quality, 0, 20),
        category = W.Text(kind, 60), sub = W.Text(sub, 60), icon = W.Int(icon, 0, W.MAX_ID) or W.Text(icon, 300), sell = W.Int(sell, 0, W.Prices.MAX_COPPER),
        classID = W.Int(class, 0, 100), bindType = W.Int(bind, 0, 20), equipLoc = W.Text(equip, 80) }
end
-- Request only an explicitly selected item, never the whole saved catalog.
local requestedItem
function D.Request(item, force)
    if requestedItem==item and not force then return end
    if C_Item and C_Item.RequestLoadItemDataByID and not D.Info(item).known then
        requestedItem=item
        C_Item.RequestLoadItemDataByID(item)
    end
end
-- A coroutine is stepped by the page's existing timer convention. Each resume
-- does at most BATCH identity reads; no price evaluation and no data requests.
function D.Catalog()
    local rows, byID, uses = {}, {}, {}
    local co = coroutine.create(function()
        local work = 0
        local function Tick()
            work = work + 1
            if work >= D.BATCH then work = 0; coroutine.yield() end
        end
        local function Add(id, source)
            id = W.Int(id, 1, W.MAX_ID)
            if not id then return end
            local r = byID[id]
            if not r then r = { item = id }; byID[id] = r; rows[#rows + 1] = r end
            r[source] = true
            return r
        end
        local src = S.PriceSource()
        for id in pairs(src.market and src.market.items or {}) do Add(id, "market"); Tick() end
        for id, on in pairs(D.Tracked()) do if on == true then Add(id, "tracked") end Tick() end
        local selected = D.Selected(); if selected then Add(selected, "selected") end
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
            for bag = 0, (NUM_BAG_SLOTS or 4) do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local x = C_Container.GetContainerItemInfo(bag, slot)
                    if type(x) == "table" then
                        local r=Add(W.Plain(x.itemID), "bags")
                        if r then
                            r.slots=true
                            local n=W.Int(x.stackCount,0,W.MAX_ID) or 0
                            local bound=W.Plain(x.isBound)
                            if bound==false then r.unbound=(r.unbound or 0)+n
                            elseif bound==true then r.bound=(r.bound or 0)+n
                            else r.bindingUnknown=true end
                            if W.Worth.LinkVariant(W.Plain(x.hyperlink)) then r.variant=true end
                        end
                    end
                    Tick()
                end
            end
        end
        for _, rec in ipairs(S.AllRecipes()) do
            if rec.outItem then Add(rec.outItem, "recipe") end
            for _, m in ipairs(rec.mats or {}) do
                Add(m.item, "recipe")
                uses[m.item] = uses[m.item] or {}
                uses[m.item][#uses[m.item] + 1] = rec
            end
            Tick()
        end
        table.sort(rows, function(a,b) return a.item < b.item end)
        for _, r in ipairs(rows) do
            r.info = D.Info(r.item)
            r.count = O.BagCount(r.item)
            r.uses = uses[r.item] or {}
            r.search = (r.info.name .. " " .. r.item):lower()
            Tick()
        end
    end)
    local job = { rows = rows, byID = byID, uses = uses }
    function job:Step()
        local pt = R.Perf and R.Perf.on and R.Perf.Start("workshop.advisor")
        local ok, why = coroutine.resume(co)
        if pt then R.Perf.Stop(pt) end
        self.done = coroutine.status(co) == "dead"
        self.error = not ok and why or nil
        return self.done, self.error
    end
    return job
end
-- Direct queue demand plus an already finished multilevel allocation. Reading
-- this from a tooltip never starts a planner job or rebuilds the recipe index.
function D.Reserved(item)
    local reserved = 0
    for _, e in ipairs(W.Queue.Entries()) do
        for _, m in ipairs(e.mats or {}) do if m.item == item then reserved = reserved + m.qty * e.crafts end end
    end
    local plan, key = W.Strategy.Last("queue")
    if plan and type(key) == "string" and key:find(tostring(W.Strategy.epoch) .. "|queue|", 1, true) == 1 then
        for _, line in ipairs(plan.items or {}) do if line.item == item then reserved = math.max(reserved, line.need or 0) end end
        local summary=plan.summary or {}
        return reserved, (summary.unknownEntries or 0)>0 or (summary.invalidEntries or 0)>0 or summary.unavailable==true
    end
    return reserved, W.Queue.Count() > 0
end
function D.Tooltip(f, facts)
    local reserved, pending = D.Reserved(f.item)
    local can = C_SpellBook and C_SpellBook.ContainsAnyDisenchantSpell and W.Plain(C_SpellBook.ContainsAnyDisenchantSpell())
    return A.Decide(f.item, { qty = f.count or 1, sell = f.sell, bindType = f.bindType, bound = f.bound, variant = f.variant,
        now = f.now, minGain = A.Gain(), facts = facts, pendingPlan = pending, crafting = { uses = {}, reserved = reserved },
        disenchantValue = W.Disenchant.Evaluate({item=f.item,quality=f.quality,classID=f.classID,equipLoc=f.equipLoc,canDisenchant=can}) })
end
-- Select-only heavy context. QueueStrategy reuses P2's cooperative job and its
-- actual allocation. Direct queued demand is kept while a newer plan runs.
function D.Context(item, full, row)
    local f = row and row.info or D.Info(item)
    local ctx = { qty = O.BagCount(item), sell = f.sell, bindType = f.bindType, now = time(),
        minGain = A.Gain(), facts = W.Facts.Of(item, {variant=row and row.variant==true}), disenchant = W.Worth.DisenchantRelevant(f) }
    local reserved, pending = D.Reserved(item)
    ctx.pendingPlan = pending
    -- A generic item id cannot prove that a held BoE/BoU copy is unbound.
    if (f.bindType == 2 or f.bindType == 3) and (ctx.qty or 0) > 0 then ctx.bindType = nil end
    if row and row.slots and (ctx.qty or 0)>0 then
        if row.unbound and row.unbound>0 then ctx.qty=row.unbound; ctx.bindType=f.bindType
        elseif row.bound and row.bound>0 and not row.bindingUnknown then ctx.bound=true
        else ctx.bindType=nil end
        ctx.variant=row.variant
    end
    local craft = { uses = row and row.uses or {}, reserved = reserved }
    if full then
        local state, plan = S.QueueStrategy()
        craft.state = state
        ctx.pendingPlan = state == "planning" or state == "failed" or (plan and plan.summary and ((plan.summary.unknownEntries or 0)>0 or (plan.summary.invalidEntries or 0)>0 or plan.summary.unavailable==true))
        if state == "ready" and plan then
            for _, line in ipairs(plan.items or {}) do
                if line.item == item then craft.reserved = math.max(reserved, line.need or 0); craft.owned = line.owned end
            end
        end
    end
    local can = C_SpellBook and C_SpellBook.ContainsAnyDisenchantSpell and W.Plain(C_SpellBook.ContainsAnyDisenchantSpell())
    ctx.disenchantValue = W.Disenchant.Evaluate({ item = item, quality = f.quality, classID = f.classID, equipLoc = f.equipLoc, canDisenchant = can })
    ctx.crafting = craft
    return ctx
end
function D.Decide(item, full, row) return A.Decide(item, D.Context(item, full, row)) end
function D.Matches(row, query, source, auctionable, category)
    if query ~= "" and not row.search:find(query:lower(), 1, true) then return false end
    if source == "bags" and not (row.count and row.count > 0) then return false end
    if source == "tracked" and D.Tracked()[row.item] ~= true then return false end
    if category and row.info.category ~= category then return false end
    local b = row.info.bindType
    local can = b==0 or ((b==2 or b==3) and (row.unbound or 0)>0)
    if auctionable and (not can or row.variant or (row.slots and (row.unbound or 0)==0)) then return false end
    return true
end
