-- Optional EllesmereUI item-ID marking. Shares the tooltip's Advisor policy;
-- never sells, unmarks, writes EllesmereUI saved data or loads either addon.
local R = TwichUI
local W = R.Workshop
local J = {}
W.Junk = J
local frame, active, pending, generation = nil, false, false, 0
local epoch=0
local touched, touchedCount = {}, 0 -- bounded; respect a manual unmark this session
local EVENTS = {"BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ADDON_LOADED", "SPELLS_CHANGED", "SKILL_LINES_CHANGED"}
local function Protected(id)
    return R.WorkshopLauncher.JunkIgnored(id)
        or R.MageSell and R.MageSell.IsExcluded(id) or R.Restock and R.Restock.Protects(id)
end
local function Wanted()
    local l = R.WorkshopLauncher
    return W.Active() and l and l.VendorJunkEnabled and l.VendorJunkEnabled() and not W.Queue.Held()
end
local function Ready()
    return active and Wanted() and not (InCombatLockdown and InCombatLockdown())
        and (not R.Life or R.Life.InWorld()) and R.EllesmereJunk and R.EllesmereJunk.Ready()
end

-- One held copy, using the same item fields and actual-level rules as WorthTip.
-- Unknown, locked and quest copies veto marking the entire item ID.
local function Read(bag, slot)
    local x = C_Container.GetContainerItemInfo(bag, slot)
    if type(x) ~= "table" then return nil end
    local id = W.Int(W.Plain(x.itemID), 1, W.MAX_ID)
    if not id then return false end
    if Protected(id) then return id end
    local link = W.Text(W.Plain(x.hyperlink), 1000)
    if not link or W.Plain(x.isLocked) ~= false then return id end
    local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if type(quest) ~= "table" or W.Plain(quest.isQuestItem) ~= false or W.Plain(quest.questID) then return id end
    local name, _, quality, level, _, _, _, _, equip, _, sell, class, _, bind = C_Item.GetItemInfo(link)
    if not W.Text(W.Plain(name), 200) then return id end
    if not R.WorkshopLauncher.JunkAllows(id,W.Plain(class)) then return id end
    local f = {item=id, count=W.Int(W.Plain(x.stackCount),1,W.MAX_ID), sell=W.Plain(sell), quality=W.Plain(quality),
        itemLevel=W.Int(W.Plain(level),1,1000), classID=W.Plain(class), equipLoc=W.Plain(equip), bindType=W.Plain(bind),
        bound=W.Plain(x.isBound), variant=W.Worth.LinkVariant(link), now=time()}
    if not f.count or not W.Int(f.sell,1,W.Prices.MAX_COPPER) or not W.Int(f.quality,0,20)
        or not W.Int(f.classID,0,100) or f.bindType==4 then return id end
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
    return id, advice.action=="vendor", f.quality
end

local function Scan()
    if not Ready() or not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
        and C_Item and C_Item.GetItemInfo) then return end
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
J.Start()
