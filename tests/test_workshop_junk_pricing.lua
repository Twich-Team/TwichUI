-- Actual prepared-price proofs, canonical advice, rules and marking adapter over
-- fabricated game/EllesmereUI boundaries. No posting, live bags or vendor calls.
local function Client()
    local c=dofile(TESTS..'auction_mock.lua')
    local R,W=c.TwichUI,c.TwichUI.Workshop
    local P,B,J,Q=W.Pricing,W.Bridge,W.BridgeCodec,W.Summary
    local file=assert(io.open(TESTS..'fixtures/workshop_prepared_v1/synthetic.json'))
    local fixture=J.Parse(file:read('*a'));file:close()
    local _,at=W.BridgeValidate.Time(fixture.manifest.generated_at)
    local s={c=c,R=R,W=W,P=P,B=B,events={},loads={},bags={},sell={},assignments={},marks=0,clears=0,now=at+60}
    c.time=function()return s.now end
    c.GetRealmName=function()return 'Realm'end
    c.UnitFactionGroup=function()return 'Horde'end
    c.GetTimePreciseSec=function()return s.clock or 0 end
    c.C_Timer.After=function(_,fn)s.events[#s.events+1]=fn end
    W.UI.Redraw=function()end
    R.Life={InWorld=function()return true end}
    c.C_AddOns.IsAddOnLoaded=function()return true end
    c.EllesmereUIDB={bagItemAssignments=s.assignments}
    local cm={JUNK_KEY='Junk',IsJunkMarkerEnabled=function()return true end}
    function cm:IsJunk(id)return s.assignments[id]==self.JUNK_KEY end
    function cm:AssignItem(id,key)s.marks=s.marks+1;s.assignments[id]=key end
    function cm:UnassignItem(id)s.clears=s.clears+1;s.assignments[id]=nil end
    c.EUI_CategoryManager=cm
    c.hooksecurefunc=function(object,key,hook)
        local original=assert(object[key])
        object[key]=function(...)
            local result={original(...)};hook(...);return unpack(result)
        end
    end
    c.EUI_Bags={RefreshInventory=function()end,SellJunk=function()
        local sold={}
        for _,x in ipairs(s.bags)do if cm:IsJunk(x.itemID)then sold[x.itemID]=true end end
        return sold
    end}
    c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=0
    c.C_Container={GetContainerNumSlots=function()return #s.bags end,
        GetContainerItemInfo=function(_,slot)return s.bags[slot]end,
        GetContainerItemQuestInfo=function()return {isQuestItem=false}end}
    c.C_Item.GetItemInfo=function(link)
        local id=tonumber(tostring(link):match('item:(%d+)'))or link
        return 'Fixture '..id,'item:'..id,1,10,1,'Trade Goods','',1,'',1,s.sell[id]or 50,7,0,0
    end
    c.C_Item.GetDetailedItemLevelInfo=function()return 10,nil,10 end
    c.TwichUIWorkshopDB={v=2,markets={}}
    c.TwichUIMarketCurrentParts={};c.TwichUIMarketHistoryParts={}
    c.C_AddOns.LoadAddOn=function(name)
        s.loads[#s.loads+1]=name
        local bank,bucket=name:match('Part([AB])(%d%d)$');bucket=tonumber(bucket)
        assert(bank and bucket,'unexpected addon request '..tostring(name))
        assert(not name:find('History',1,true),'junk evaluation must not load full history')
        local p=s.prepared.partitions[bucket+1];local payload=s.payloads[tostring(bucket)]
        c.TwichUIMarketCurrentParts[bank..('%02d'):format(bucket)]={version=1,layout=16,content_id=p.sha256,data=payload[1],proofs=payload[2]}
        if s.addonLoaded then s.addonLoaded(name)end
        return true
    end
    function s.addonLoaded(name)
        for _,frame in ipairs(c.testFrames)do
            if frame.events and frame.events.ADDON_LOADED then
                local callback=frame:GetScript('OnEvent')
                if callback then callback(frame,'ADDON_LOADED',name)end
            end
        end
    end
    function s.tick()
        local events=s.events;s.events={};s.clock=(s.clock or 0)+1/60
        for _,fn in ipairs(events)do fn()end
    end
    function s.drain()
        for _=1,20000 do if #s.events==0 then return end;s.tick()end
        error('junk pricing work failed to settle')
    end
    function s.begin()
        local h=J.Copy(fixture.manifest)
        h.synthetic=false;for _,o in ipairs(h.observations)do o.synthetic=false end
        s.serial=(s.serial or 0)+1;h.source_watermark=tostring(902+s.serial)
        local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
        s.prepared=J.Copy(fixture.layouts['16'].attestation);s.payloads=J.Copy(fixture.layouts['16'].payloads)
        s.prepared.source_generation_id=h.generation_id
        body=J.Copy(s.prepared);body.attestation_id=nil;s.prepared.attestation_id=J.SHA(J.Encode(body))
        local root={summary_version=2,bank=s.serial%2==1 and 'A'or 'B',manifest=J.Encode(h),prepared=J.Encode(s.prepared),
            receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='junk-test',completed_at=h.generated_at},J.OBJECT))}
        B.Begin(root)
        return h.generation_id
    end
    function s.item(id,variant)
        return {itemID=id,stackCount=1,isLocked=false,isBound=false,
            hyperlink=variant and ('item:'..id..':0:0:0:0:0:1')or ('item:'..id)}
    end
    function s.localMarket(value,age)
        local batch=W.Prices.NewBatch()
        for _=1,5 do batch:Add(2589,20,value*20,true)end
        local items,n,_,_,dist=batch:Items()
        local marketAt=s.now-(age or 60)
        local m={f=3,scope='full',realm='Realm',side='Horde',key='Realm|Horde',at=marketAt,
            complete=true,read=5,used=5,partial=0,n=n,items=items,hist={},hn=0,sd={},dist=dist,h2={},c2={},
            scans={},days={},v2from=1,h2info={v=1,from=1,at=marketAt},
            snap={seq=(s.localSeq or 0)+1,kind='full',at=marketAt,alg=1,records=5,used=5,partial=0,items=n}}
        s.localSeq=m.snap.seq;c.TwichUIWorkshopDB.markets[m.key]=m
        W.Facts.CacheClear()
        return m
    end
    function s.advice(id,variant)
        return W.AdvisorData.Tooltip({item=id,count=1,sell=s.sell[id]or 50,quality=1,itemLevel=10,
            actualLevel=true,classID=7,equipLoc='',bindType=0,bound=false,variant=variant and 'suffix'or nil,now=s.now})
    end
    local function Load(path)local fn=assert(loadfile(path));setfenv(fn,c);fn()end
    Load(ROOT..'modules/EllesmereJunk.lua')
    s.begin();s.drain();assert(B.Status().prepared_version==1 and #s.loads==0)
    c.TwichUIDB.ui.workshopVendorJunk=true
    Load(REPO..'TwichUI_Workshop/Junk.lua')
    s.Junk=W.Junk;s.cm=cm
    s.drain()
    return s
end

-- A readable local fallback must not settle a still-loading Market reference.
local s=Client();local id=2589
s.localMarket(30,4*86400);s.bags={s.item(id),s.item(id)}
local decisions=0;local canonical=s.W.AdvisorData.Tooltip
s.W.AdvisorData.Tooltip=function(...)
    decisions=decisions+1;return canonical(...)
end
s.Junk.Request();s.tick()
assert(s.P.PendingCount()==1 and not s.assignments[id],'pending Market valuation marked junk')
assert(decisions==1,'identical bag copies repeated canonical valuation in one scan')
local pending=s.advice(id)
assert(pending.pending and pending.action=='unknown','canonical Advisor must expose pending pricing')
local loads=#s.loads
for _=1,20 do assert(s.advice(id).pending)end
assert(s.P.PendingCount()==1 and #s.loads==loads,'repeated decisions duplicated pending load requests')
s.drain()
assert(s.advice(id).action=='auction' and not s.assignments[id],'final Market auction was ignored')
assert(#s.loads==1 and s.B.Status().history_loaded_parts==0,'identical slots repeated price loading/history')

-- Confirmed Vendor marks promptly; sale classification waits for current proof.
s=Client();s.sell[id]=100;s.bags={s.item(id),s.item(id)}
s.Junk.Request();s.tick();assert(not s.assignments[id])
s.drain();assert(s.advice(id).action=='vendor' and s.assignments[id]=='Junk')
assert(s.R.EllesmereJunk.Owned(id) and s.c.EUI_Bags:SellJunk()[id],'final owned mark should be sellable')
s.now=s.now+120
assert(s.c.EUI_Bags:SellJunk()[id],'unchanged fresh evidence must remain sellable across idle minutes')
local row={item=id,count=2,slots=true,unbound=2,info=s.W.AdvisorData.Info(id)}
local uiAdvice=s.W.AdvisorData.Decide(id,false,row)
local inspectRule=s.R.WorkshopLauncher.NewJunkRule('Vendor test')
inspectRule.tree={type='group',match='all',children={{type='vendor',value=true}}}
local inspected=s.Junk.Inspect(0,1,inspectRule)
assert(uiAdvice.action==s.advice(id).action and inspected.advice==uiAdvice.action and inspected.vendor==true,
    'Advisor page, held tooltip and Junk item test disagree on the same ready evidence')
local marks=s.marks;s.Junk.Request()
assert(not s.c.EUI_Bags:SellJunk()[id],'invalidated valuation must block vendor before deferred scan')
s.drain();assert(s.marks==marks and s.c.EUI_Bags:SellJunk()[id],'stable Vendor should not flicker/re-mark')

-- A new generation reevaluates the old owned decision, preserving the category
-- while waiting and removing only the automatically owned mark when disproved.
s.sell[id]=50
local previous=s.B.Status().generation
s.begin();assert(s.B.Status().generation~=previous or s.B.Status().loading)
s.Junk.Request()
assert(not s.c.EUI_Bags:SellJunk()[id],'old generation remained eligible for automatic selling')
-- Workshop reload retains the small core-owned provenance table, but an old
-- sale authorization must never survive the new module's initial evaluation.
local ownership=s.c.TwichUIDB.workshopJunkOwned
s.Junk.Stop()
local reload=assert(loadfile(REPO..'TwichUI_Workshop/Junk.lua'));setfenv(reload,s.c);reload()
s.Junk=s.W.Junk
assert(s.c.TwichUIDB.workshopJunkOwned==ownership and s.R.EllesmereJunk.Owned(id),
    'Workshop reload lost ownership of its persisted automatic mark')
assert(not s.c.EUI_Bags:SellJunk()[id],'Workshop reload retained a stale sale authorization')
s.drain()
assert(s.advice(id).action=='auction' and not s.assignments[id],'updated Auction left its old automatic mark')
assert(s.clears==1,'reconciliation should clear an owned mark exactly once')

-- Current, supported local competition remains authoritative under the existing
-- Advisor policy even when a higher Market reference is available.
s=Client();s.sell[id]=50;s.localMarket(30,1);s.bags={s.item(id)}
s.Junk.Request();s.drain()
local advice=s.advice(id)
assert(advice.action=='vendor' and advice.suggestion.price==30 and s.assignments[id]=='Junk',
    'integration blindly favored Market over supported local competition')

-- True absence, ineligible/stale evidence and corrupt proofs use the exact
-- canonical fallback; none invent an Auction quote or permanent pending state.
for _,kind in ipairs({'absent','stale','invalid'})do
    s=Client();s.sell[id]=100
    if kind=='absent'then id=64;s.sell[id]=100
    elseif kind=='stale'then s.now=s.now+2*86400
    else local payload=s.payloads['13'];payload[2]=string.rep('0',#payload[2])end
    s.bags={s.item(id)};s.Junk.Request();s.drain()
    local final=s.advice(id)
    assert(not final.pending and final.action=='vendor' and s.assignments[id]=='Junk',kind..' differed from canonical fallback')
    assert(s.P.PendingCount()==0,kind..' stranded a price request')
    id=2589
end

-- The marker is item-ID based: one base copy favoring Auction vetoes a Vendor
-- suffix, regardless of which slot was visited first.
for _,reverse in ipairs({false,true})do
    s=Client();s.bags={s.item(id,true),s.item(id)}
    if reverse then s.bags={s.bags[2],s.bags[1]}end
    s.Junk.Request();s.drain()
    assert(s.advice(id,true).action=='vendor' and s.advice(id).action=='auction')
    assert(not s.assignments[id],'same-ID variants were collapsed into one Vendor decision')
end

-- Explicit player junk ownership and Keep filings always survive repricing.
for _,category in ipairs({'Junk','Keep'})do
    s=Client();s.sell[id]=100;s.bags={s.item(id)};s.Junk.Request();s.drain()
    assert(s.R.EllesmereJunk.Owned(id))
    s.cm:AssignItem(id,category)
    assert(not s.R.EllesmereJunk.Owned(id),'manual assignment did not take ownership')
    s.sell[id]=50;s.Junk.Request();s.drain()
    assert(s.assignments[id]==category,'reconciliation overwrote player '..category)
end
s=Client();s.sell[id]=100;s.bags={s.item(id)};s.Junk.Request();s.drain()
s.cm:UnassignItem(id);s.Junk.Request();s.drain()
assert(not s.assignments[id],'explicit manual unmark was reapplied')

-- An independently satisfied rule keeps the mark despite a Vendor rule losing
-- support, and can match while the unrelated Advisor condition is pending.
s=Client();s.sell[id]=100;s.bags={s.item(id)};s.Junk.Request();s.drain()
local advisorRule=s.R.WorkshopLauncher.NewJunkRule('Advisor')
advisorRule.on=true;advisorRule.tree={type='group',match='all',children={{type='vendor',value=true}}}
local materialRule=s.R.WorkshopLauncher.NewJunkRule('Ordinary material')
materialRule.on=true;materialRule.tree={type='group',match='all',children={{type='kind',value='materials'}}}
local rules={v=2,rows={advisorRule,materialRule}}
s.c.TwichUIDB.ui.workshopJunk={rules=rules}
s.sell[id]=50;s.begin();s.Junk.Request();s.drain()
-- An independent match need not ask for Advisor data; the UI can request it.
s.advice(id);s.drain()
assert(s.assignments[id]=='Junk' and s.advice(id).action=='auction','independent matching rule was overridden')
s=Client();s.c.TwichUIDB.ui.workshopJunk={rules=rules};s.bags={s.item(id)}
s.advice(id)
s.Junk.Start();s.tick()
assert(s.assignments[id]=='Junk','unrelated rule was blocked by Workshop pricing')
s.drain()

-- Pending callbacks re-read item identity/slots; moved copies are considered at
-- their new location and removed copies cannot leave a new stale mark.
for _,removed in ipairs({false,true})do
    s=Client();s.sell[id]=100;s.bags={s.item(id)};s.Junk.Request();s.tick()
    assert(s.P.PendingCount()==1)
    s.bags=removed and {}or {s.item(9001),s.item(id)}
    s.Junk.Request();s.drain()
    assert((s.assignments[id]=='Junk')==not removed,'pending slot identity was reused after item removal/move')
end

-- Price completion during a yielded first inventory scan must restart the
-- unfinished full scan, rather than publishing a partial dependency-only scan.
s=Client();s.sell[id]=100;s.bags={s.item(id)}
for n=1,79 do s.bags[#s.bags+1]=s.item(11000+n)end
s.Junk.Request();s.tick()
assert(s.P.PendingKey(id) and not s.assignments[id],'first scan did not suspend before marking')
local staleSteps,other={},{}
for _,fn in ipairs(s.events)do
    local source=debug.getinfo(fn,'S').source
    local isScan=false
    if source:find('TwichUI_Workshop/Junk.lua',1,true)then
        for index=1,20 do
            local name,value=debug.getupvalue(fn,index)
            if not name then break end
            if name=='job' and type(value)=='thread'then isScan=true;break end
        end
    end
    if isScan then staleSteps[#staleSteps+1]=fn else other[#other+1]=fn end
end
assert(#staleSteps==1,'failed to isolate the yielded production scan continuation')
s.events=other;s.drain()
assert(s.assignments[id]=='Junk' and s.P.PendingCount()==0,'price completion stranded the initial scan')
for n=1,79 do assert(s.assignments[11000+n]=='Junk','targeted update replaced an unfinished full bag scan')end
local marked=s.marks
for _,fn in ipairs(staleSteps)do fn()end
s.drain();assert(s.marks==marked,'obsolete yielded scan resumed after a pricing completion')

-- A selected local market is part of identity even when its generation fields
-- equal another market's. Never stamp earlier reads with the replacement key.
s=Client();local low=s.localMarket(30,1);local high=s.localMarket(200,1)
high.key='Other|Horde';high.snap.seq=low.snap.seq
assert(s.W.Valuation.Generation(low)==s.W.Valuation.Generation(high))
local selected=low
s.W.Session.PriceSource=function()return {market=selected}end
s.advice(id);s.drain();assert(s.advice(id).action=='vendor')
for n=1,40 do s.bags[n]=s.item(id)end
s.Junk.Request();s.tick();assert(not s.assignments[id])
selected=high -- before any coalesced price/source notification
s.tick();assert(not s.assignments[id],'yielded Vendor reads were published under the replacement market key')
s.drain();assert(s.advice(id).action=='auction' and not s.assignments[id])

-- The same start-of-read check also applies to a Market generation replacement.
s=Client();s.sell[id]=100;s.advice(id);s.drain()
for n=1,40 do s.bags[n]=s.item(id)end
s.Junk.Request();s.tick();assert(not s.assignments[id])
s.sell[id]=50;s.begin()
s.tick();assert(not s.assignments[id],'yielded Vendor reads were published under a replacement generation')
s.drain();assert(s.advice(id).action=='auction' and not s.assignments[id])

-- Header validation is pending pricing too, before a record can be requested.
s=Client();s.W.Summary.Deactivate();s.begin()
assert(s.B.Status().loading and not s.B.Status().ready)
local metadataPending=s.advice(id)
assert(metadataPending.pending and metadataPending.action=='unknown' and s.P.PendingCount()==0,
    'initial metadata loading became a final Vendor fallback')
s.bags={s.item(id)};s.Junk.Request();s.drain()
assert(s.advice(id).action=='auction' and not s.assignments[id])

-- Pricing invalidation can obsolete a completed queue plan without directly
-- requesting a junk scan. A nonempty queue's epoch must revoke sale permission;
-- an empty queue has no such dependency and stays ready.
s=Client();s.sell[id]=100;s.bags={s.item(id)};s.Junk.Request();s.drain()
assert(s.c.EUI_Bags:SellJunk()[id])
s.W.Strategy.Bump(true)
assert(s.c.EUI_Bags:SellJunk()[id],'empty queue made unrelated pricing invalidation revoke sale permission')
assert(s.W.Queue.Add({id=777,name='Unrelated recipe',prof=171,profName='Alchemy',outItem=888,
    outMin=1,outMax=1,mats={{item=999001,qty=1}}},1))
local planEpoch=s.W.Strategy.epoch
s.W.Strategy.Last=function()return {items={},summary={}},tostring(planEpoch)..'|queue|fixture'end
s.Junk.Request();s.drain()
assert(s.c.EUI_Bags:SellJunk()[id] and s.advice(id).action=='vendor')
s.W.Strategy.Bump(true)
assert(not s.c.EUI_Bags:SellJunk()[id],'stale nonempty queue plan retained sale permission')
local _,planPending=s.W.AdvisorData.Reserved(id)
assert(planPending and s.advice(id).action=='unknown','obsolete queue plan was treated as complete')
s.Junk.Request();s.drain()
assert(s.assignments[id]=='Junk' and not s.c.EUI_Bags:SellJunk()[id],
    'pending queue plan flickered the mark or authorized a sale')

-- A single resolved dependency must not revalue unrelated carried identities.
s=Client();s.sell[id]=100
for n=1,30 do s.bags[#s.bags+1]=s.item(10000+n)end
s.bags[#s.bags+1]=s.item(id);s.Junk.Request();s.drain()
local evaluated={};local tooltip=s.W.AdvisorData.Tooltip
s.W.AdvisorData.Tooltip=function(f,...)
    evaluated[f.item]=(evaluated[f.item]or 0)+1;return tooltip(f,...)
end
s.Junk.ItemsChanged({[id]=true});s.drain()
for n=1,30 do assert(not evaluated[10000+n],'one price revalued unrelated bag items')end
assert(evaluated[id] and evaluated[id]<=2,'affected identical item valuation was duplicated')
s.addonLoaded(assert(s.loads[1]));s.drain()
for n=1,30 do assert(not evaluated[10000+n], 'Market addon loading restarted a global junk scan')end
local generation=s.P.Generation()
assert(s.cm:IsJunk(10001),'unrelated owned item was not authorized')
s.P.PrepareBucket({2653});s.drain()
assert(s.P.Generation()~=generation,'control did not complete a new prepared price')
assert(s.cm:IsJunk(10001) and not evaluated[10001],
    'one prepared completion revoked or recomputed an unrelated ready decision')
s.addonLoaded('EllesmereUIBags');s.drain()
assert(evaluated[10001] and s.cm:IsJunk(10001), 'relevant Bags lifecycle changes must still reconcile held items')

-- Valid Market evidence replaces a legitimate unavailable-data fallback while
-- vendor value stays fixed throughout the transition.
s=Client();s.sell[id]=50;s.localMarket(30,4*86400);s.bags={s.item(id)}
local status=s.B.Status
s.B.Status=function()return {ready=false,loading=false,failures=0}end
s.Junk.Request();s.drain()
assert(s.advice(id).action=='vendor' and s.assignments[id]=='Junk','unavailable Market fallback did not establish owned Vendor')
s.B.Status=status
s.P.Notify();s.tick()
assert(not s.cm:IsJunk(id),'newly available Market reused old Vendor sale authorization')
s.drain()
assert(s.advice(id).action=='auction' and not s.assignments[id] and s.clears==1,
    'valid Market auction evidence failed to correct an earlier owned fallback mark')
print('PASSED Workshop junk finality: prepared proofs, fallback, source rules, variants, generations, ownership, selling, independent rules, moves and targeted work')
