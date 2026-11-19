-- Optional EllesmereUI item-ID marking. Shares the tooltip's Advisor policy;
-- never sells, unmarks, writes EllesmereUI saved data or loads either addon.
local R = TwichUI
local W = R.Workshop
local J = {}
W.Junk = J
local frame, active, pending, generation = nil, false, false, 0
local epoch=0
local professionItems,classItems={},{}
local needWear,needUpgrade=false,false
local touched, touchedCount = {}, 0 -- bounded; respect a manual unmark this session
local EVENTS = {"BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ADDON_LOADED", "SPELLS_CHANGED", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TALENT_UPDATE"}
-- Why an item may never be marked, or nil. The Cozy Sleeping Bag and the player's Never mark list are one
-- protection ("never"); Mage Sell's exclusions and vendor restocking each keep their own reason.
local function Why(id)
    if R.WorkshopLauncher.JunkIgnored(id) then return "never" end
    if R.MageSell and R.MageSell.IsExcluded(id) then return "mage" end
    if R.Restock and R.Restock.Protects(id) then return "restock" end
end
local function Protected(id) return Why(id)~=nil end
local function Wanted()
    local l = R.WorkshopLauncher
    return W.Active() and l and l.VendorJunkEnabled and l.VendorJunkEnabled() and not W.Queue.Held()
end
local function Ready()
    return active and Wanted() and not (InCombatLockdown and InCombatLockdown())
        and (not R.Life or R.Life.InWorld()) and R.EllesmereJunk and R.EllesmereJunk.Ready()
end

-- One held copy, using the same item fields and actual-level rules as WorthTip. Returns nil for an empty slot, false
-- for an occupied slot that cannot be read (it may be another copy of anything), or the item's facts. An unknown,
-- locked, quest or protected copy carries `veto`, and vetoes marking the entire item ID.
-- `wear` and `upgrade` say whether a rule asks for those facts: they are the costly ones.
local function Gather(bag, slot, wear, upgrade)
    local x = C_Container.GetContainerItemInfo(bag, slot)
    if type(x) ~= "table" then return nil end
    local id = W.Int(W.Plain(x.itemID), 1, W.MAX_ID)
    if not id then return false end
    local info = {id = id, x = x}
    local why = Why(id)
    if why then info.veto, info.why = "protected", why; return info end
    local link = W.Text(W.Plain(x.hyperlink), 1000)
    if not link or W.Plain(x.isLocked) ~= false then info.veto = "locked"; return info end
    info.link = link
    local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if type(quest) ~= "table" or W.Plain(quest.isQuestItem) ~= false or W.Plain(quest.questID) then info.veto = "quest"; return info end
    local name, _, quality, level, _, _, _, _, equip, icon, sell, class, _, bind = C_Item.GetItemInfo(link)
    name = W.Text(W.Plain(name), 200)
    if not name then info.veto = "unknown"; return info end
    class=W.Plain(class)
    info.name, info.icon, info.class, info.quality = name, W.Plain(icon), class, W.Plain(quality)
    info.level, info.equip, info.sell, info.bind = level, equip, sell, bind
    local facts={quality=info.quality,profession=professionItems[id],classReagent=classItems[id]}
    if class==2 or class==4 then
        local data=wear and C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag,slot)
        if wear and data and type(data.lines)=="table" and #data.lines>0 and R.GearData then
            facts.wearable=R.GearData.RedLines(data.lines)==0
        end
        if upgrade and R.GearHints then
            local judged=R.GearHints.Judge(link,nil,nil,bag,slot)
            local verdict=judged and judged.result and judged.result.verdict
            if verdict=="likely" or verdict=="possible" or verdict=="empty" then facts.upgrade=true
            elseif verdict=="similar" or verdict=="worse" then facts.upgrade=false end
        end
    end
    info.facts = facts
    return info
end

-- The Advisor's answer for one gathered copy: true when it recommends Vendor, false for anything else, nil when
-- the item's own numbers are unusable (which vetoes marking). `advice` is the full answer, for the item test.
local function Advise(info)
    local x, link, level = info.x, info.link, info.level
    local f = {item=info.id, count=W.Int(W.Plain(x.stackCount),1,W.MAX_ID), sell=W.Plain(info.sell), quality=info.quality,
        itemLevel=W.Int(W.Plain(level),1,1000), classID=info.class, equipLoc=W.Plain(info.equip), bindType=W.Plain(info.bind),
        bound=W.Plain(x.isBound), variant=W.Worth.LinkVariant(link), now=time()}
    if not f.count or not W.Int(f.sell,1,W.Prices.MAX_COPPER) or not W.Int(f.quality,0,20)
        or not W.Int(f.classID,0,100) or f.bindType==4 then return nil end
    f.actualLevel=f.itemLevel~=nil and not f.variant
    if C_Item.GetDetailedItemLevelInfo then
        local actual, _, base=C_Item.GetDetailedItemLevelInfo(link)
        actual,base=W.Plain(actual),W.Plain(base)
        if W.Int(actual,1,1000) then f.itemLevel=actual;f.actualLevel=true end
        if not f.variant and type(actual)=="number" and type(base)=="number" and actual~=base then f.variant="level" end
    end
    local source=W.Session.PriceSource()
    f.marketTable=source.market
    local advice=W.AdvisorData.Tooltip(f)
    return advice.action=="vendor", advice
end

local function Read(bag, slot)
    local info = Gather(bag, slot, needWear, needUpgrade)
    if info == nil or info == false then return info end
    if info.veto or not R.WorkshopLauncher.JunkAllows(info.id, info.class, info.facts) then return info.id end
    local vendor = Advise(info)
    if vendor == nil then return info.id end
    return info.id, vendor, info.quality
end

-- What the "Recipe material" and "Class reagent" conditions know: remembered recipes and this class's reagents.
local function Learn()
    professionItems,classItems={},{}
    needWear,needUpgrade=false,false
    for _,p in ipairs(W.Known and W.Known.Load() or {}) do
        for _,rec in ipairs(p.recipes or {}) do
            for _,mat in ipairs(rec.mats or {}) do professionItems[mat.item]=true end
        end
    end
    for _,entry in ipairs(R.Restock and R.Restock.Suggestions and R.Restock.Suggestions() or {}) do classItems[entry.id]=true end
end

local function Scan()
    if not Ready() or not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
        and C_Item and C_Item.GetItemInfo) then return end
    Learn()
    for _,rule in ipairs(R.WorkshopLauncher.JunkRules()) do
        if rule.on then
            needWear=needWear or (rule.tree and R.WorkshopLauncher.JunkTree.Uses(rule.tree,"wearable") or not rule.tree and rule.wearable~="any")
            needUpgrade=needUpgrade or (rule.tree and R.WorkshopLauncher.JunkTree.Uses(rule.tree,"upgrade") or not rule.tree and rule.upgrade~="any")
        end
    end
    local candidates, order, slots = {}, {}, 0
    for bag=0,math.min(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4,10) do
        local n=W.Int(W.Plain(C_Container.GetContainerNumSlots(bag)),0,200)
        if not n then return end
        for slot=1,n do
            local id, vendor, quality=Read(bag,slot)
            if id==false then return end -- an unreadable occupied slot may be another copy
            if id then
                if not candidates[id] then candidates[id]={ok=true,quality=quality};order[#order+1]=id end
                if not vendor then candidates[id].ok=false end
            end
            slots=slots+1
            if slots%40==0 then coroutine.yield() end
        end
    end
    local changed=false
    for index,id in ipairs(order) do
        if not Ready() then return end
        local c=candidates[id]
        -- No stale planning or prices: reread the crafting reservation immediately
        -- before marking. Bag/price changes invalidate the whole pending job.
        local reserved, unresolved=W.AdvisorData.Reserved(id)
        if c.ok and reserved==0 and not unresolved and not Protected(id) and not touched[id] and touchedCount<2048 then
            local result=R.EllesmereJunk.Mark(id,c.quality)
            if result=="marked" or result=="failed" then
                touched[id]=true;touchedCount=touchedCount+1
            end
            if result=="marked" then J.marked=J.marked+1;changed=true end
        end
        if index%20==0 then
            if changed then R.EllesmereJunk.Repaint();changed=false end
            coroutine.yield()
        end
    end
    if changed then R.EllesmereJunk.Repaint() end
end

---------------------------------------------------------------------------
-- The rule builder's item test. It reads and decides through the same Gather, Judge and Advise marking uses, and
-- changes nothing: no mark, no timer, no saved data, no EllesmereUI call that writes.
---------------------------------------------------------------------------
local function Bags()
    return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo and C_Item and C_Item.GetItemInfo
end
local function EachSlot(fn)
    for bag=0,math.min(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4,10) do
        local n=W.Int(W.Plain(C_Container.GetContainerNumSlots(bag)),0,200)
        if n then for slot=1,n do if fn(bag,slot)==false then return end end end
    end
end
local function Uses(rule,key)
    return rule and rule.tree and R.WorkshopLauncher.JunkTree.Uses(rule.tree,key) or false
end

-- state "empty" | "unreadable" | "unavailable" | "ok". When ok: item, verdict ("protected", "blocked", "class",
-- "match", "nomatch", "unknown"), trace (node -> "yes"/"no"/"unknown"), why (never, cozy, mage, restock), block
-- (locked, quest, unknown), advice (the Advisor's action), vendor, reserved, touched, marker, wanted.
local Inspect
function J.Inspect(bag, slot, rule)
    local Perf = R.Perf
    if Perf and Perf.Call then return Perf.Call("workshop.junkTest", Inspect, bag, slot, rule) end
    return Inspect(bag, slot, rule)
end
function Inspect(bag, slot, rule)
    local out = {bag = bag, slot = slot, state = "unavailable"}
    if not Bags() or not rule or not rule.tree then return out end
    Learn()
    local info = Gather(bag, slot, Uses(rule, "wearable"), Uses(rule, "upgrade"))
    if info == nil then out.state = "empty"; return out end
    if info == false then out.state = "unreadable"; return out end
    out.state = "ok"
    out.item = {id = info.id, name = info.name, icon = info.icon, link = info.link, count = W.Int(W.Plain(info.x.stackCount), 1, W.MAX_ID)}
    out.quality, out.class, out.facts = info.quality, info.class, info.facts
    out.wanted = Wanted()
    out.touched = touched[info.id] == true
    -- One unsafe copy anywhere vetoes the whole item ID, so read the other copies' safety too.
    local veto, why = info.veto, info.why
    if not veto then
        EachSlot(function(b, sl)
            if b == bag and sl == slot then return end
            local other = Gather(b, sl, false, false)
            if other == false then veto = "unknown"; return false end
            if other and other.id == info.id and other.veto and other.veto ~= "protected" then veto = other.veto; return false end
        end)
    end
    if veto == "protected" then
        out.verdict = "protected"
        out.why = info.id == 211527 and "cozy" or why
        return out
    end
    if veto then out.verdict, out.block = "blocked", veto; return out end
    local trace = {}
    local verdict = R.WorkshopLauncher.JunkJudge(info.id, info.class, info.facts, {rule}, trace)
    out.verdict, out.trace = verdict, trace
    if verdict == "protected" then out.why = info.id == 211527 and "cozy" or "never" end
    local vendor, advice = Advise(info)
    out.vendor, out.advice = vendor, advice and advice.action or nil
    out.reserved = W.AdvisorData.Reserved(info.id)
    out.marker = R.EllesmereJunk and R.EllesmereJunk.Peek(info.id, info.quality) or "unavailable"
    return out
end

-- Where a held item sits, for an item chosen by ID or link (the first copy).
function J.Find(id)
    local at
    if Bags() then
        EachSlot(function(bag, slot)
            local x = C_Container.GetContainerItemInfo(bag, slot)
            if type(x) == "table" and W.Plain(x.itemID) == id then at = {bag = bag, slot = slot}; return false end
        end)
    end
    return at
end

-- How many different bag items a rule would pick out, without touching anything. One pass over the bags in
-- small slices (never in a frame handler), only when asked. `done(result)` gets {items, match, protected,
-- unknown, blocked, names}; a newer survey cancels an older one.
local surveyToken = 0
function J.CancelSurvey() surveyToken = surveyToken + 1 end
function J.Survey(rule, done)
    surveyToken = surveyToken + 1
    local mine = surveyToken
    if not Bags() or not rule or not rule.tree then done({unavailable = true}); return false end
    Learn()
    local wear, upgrade = Uses(rule, "wearable"), Uses(rule, "upgrade")
    local job = coroutine.create(function()
        local seen, result, slots = {}, {items = 0, match = 0, protected = 0, unknown = 0, blocked = 0, names = {}}, 0
        EachSlot(function(bag, slot)
            local info = Gather(bag, slot, wear, upgrade)
            if info and not seen[info.id] then
                seen[info.id] = true
                result.items = result.items + 1
                local verdict = "blocked"
                if info.veto == "protected" then verdict = "protected"
                elseif not info.veto then verdict = R.WorkshopLauncher.JunkJudge(info.id, info.class, info.facts, {rule}) end
                if verdict == "match" then
                    result.match = result.match + 1
                    if #result.names < 5 then result.names[#result.names + 1] = info.name or ("Item " .. info.id) end
                elseif verdict == "protected" or verdict == "class" then result.protected = result.protected + 1
                elseif verdict == "unknown" then result.unknown = result.unknown + 1
                elseif verdict == "blocked" then result.blocked = result.blocked + 1 end
            end
            slots = slots + 1
            if slots % 30 == 0 then coroutine.yield() end
        end)
        return result
    end)
    local function Step()
        if mine ~= surveyToken then return end
        local pt = R.Perf and R.Perf.on and R.Perf.Start("workshop.junkTest")
        local ok, result = coroutine.resume(job)
        if pt then R.Perf.Stop(pt) end
        if not ok then if R.Fault then R.Fault("workshop.junk", result) end; done({unavailable = true}); return end
        if coroutine.status(job) == "dead" then done(result) else C_Timer.After(0, Step) end
    end
    Step()
    return true
end

function J.Request()
    generation=generation+1 -- a changed bag/price must invalidate an in-flight scan
    if not active or pending or not Wanted() then return end
    pending=true
    local scheduled=epoch
    C_Timer.After(0.5,function()
        if scheduled~=epoch then return end
        pending=false
        if not Ready() then return end
        local mine=generation
        local job=coroutine.create(Scan)
        local function Step()
            if mine~=generation or not Ready() then return end
            local pt=R.Perf and R.Perf.on and R.Perf.Start("workshop.junk")
            local ok,err=coroutine.resume(job)
            if pt then R.Perf.Stop(pt) end
            if not ok then if R.Fault then R.Fault("workshop.junk",err) end;return end
            if coroutine.status(job)~="dead" then C_Timer.After(0,Step) end
        end
        Step()
    end)
end
function J.Stop()
    active,pending=false,false;generation=generation+1
    epoch=epoch+1
    if frame then frame:UnregisterAllEvents() end
end
function J.Start()
    J.Stop()
    if not Wanted() or not CreateFrame then return end
    active=true
    if not frame then frame=CreateFrame("Frame");frame:SetScript("OnEvent",function() J.Request() end) end
    for _,e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    J.Request()
end
function J.Events() return active and #EVENTS or 0 end
function J.Retained() return touchedCount end
J.marked=0
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("workshop.junkListeners",{label="Workshop junk listeners",kind="events",group="workshop",unit="count",read=J.Events})
    R.Perf.Gauge("workshop.junkTouched",{label="Workshop junk session identities",kind="cache",group="workshop",unit="count",read=J.Retained})
end
if R.GearHints and R.GearHints.OnChange then R.GearHints:OnChange(J.Request) end
J.Start()
