-- Actual source -> Session -> Window -> pooled rows/details, synthetic data only.
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
local events={};c.GetTimePreciseSec=os.clock
c.C_Timer.After=function(_,fn)events[#events+1]=fn end
c.C_Item.GetItemInfo=function(id)return 'Synthetic '..id,'item:'..id,1,1,1,'Trade Goods','',1,'',1,0 end
local counts={};for b=0,63 do counts[b]=4 end
local f=dofile(TESTS..'market_cold_fixture.lua')(c,2,counts);f.Split()
c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts={}
for b,raw in pairs(f.parts)do c.TwichUIMarketParts['A'..('%02d'):format(b)]=raw end
for b,raw in pairs(f.history_parts)do c.TwichUIMarketHistoryParts['A'..('%02d'):format(b)]=raw end
local function tick()local batch=events;events={};for _,fn in ipairs(batch)do fn()end end
local function drain()
    for _=1,5000 do if #events==0 then assert(not W.Session.OpportunityStatus().running);return end;tick()end
    error('runaway UI refresh')
end
W.Bridge.Begin(f.root);drain()
local recipes={};for i=1,128 do recipes[i]={id=i,name=('Craft %03d'):format(i),prof=171,profName='Alchemy',filled=true,
    outItem=128+i,outMin=1,outMax=1,mats={{item=64+i%64,qty=1+i%2}}}end
W.Session.AllRecipes=function()return recipes end
W.Window.SetMode('opps');W.Window.Show();drain()
local S=W.Session;local list=W.Window.Lists().opps;local detail=W.Window.Opps().detail
assert(#list.data==128 and S.OpportunityStatus().crafts==128 and not S.Opportunities().calculating)
local expected=W.Opps.Select(S.Opportunities().all,S.opp)
for i,row in ipairs(expected)do assert(list.data[i].rec.id==row.rec.id)end
local frames=#list.rows;local calls=S.OpportunityStatus().crafts;local sorted=S.OpportunityStatus().sorts
W.Window.Render();drain()
assert(S.OpportunityStatus().crafts==calls and S.OpportunityStatus().sorts==sorted and #list.rows==frames,'warm UI rebuilt work/frames')
local row=list.rows[2];row:GetScript('OnClick')(row);local selected=detail.rec.id
-- An unrelated price event does not replace selected details or selection.
local item=recipes[selected].outItem
local other=selected==1 and 128 or 1
S.ItemsChanged({[recipes[other].outItem]=true});drain()
assert(detail.rec.id==selected and S.OpportunityStatus().crafts==calls+1,'unrelated completion replaced selection or recalculated all')
calls=S.OpportunityStatus().crafts
for _,key in ipairs({'cost','sell','margin','profit'})do S.SortBy(key);W.Window.Render();drain()end
assert(S.OpportunityStatus().crafts==calls and detail.rec.id==selected,'sort recalculated prices or lost selection')
S.ToggleProfitOnly();W.Window.Render();drain()
for _,r in ipairs(list.data)do assert(r.est.state=='ok'and r.est.profitLow>0)end
S.ToggleProfitOnly();W.Window.Render();drain();assert(#list.data==128 and detail.rec)
-- Scroll/resize retains the pool, promotes viewport work and never starts a permanent worker.
list.scroll:SetVerticalScroll(52*30)
local scroll=list.scroll:GetScript('OnVerticalScroll');if scroll then scroll(list.scroll)end
W.Window.Render();drain();assert(#list.rows==frames and not S.OpportunityStatus().running)
-- Cancel an actual bucket reservation lease: no shared pending identities remain stuck.
local owner={};local co=coroutine.create(function()W.Pricing.PrepareBucket({320,384,448},coroutine.yield,owner)end)
W.Pricing.CancelPending();assert(coroutine.resume(co));assert(W.Pricing.PendingCount()>0)
W.Pricing.Price(384);W.Pricing.ReleasePreparation(owner);drain()
assert(W.Pricing.PendingCount()==0,'cancelled preparation stranded shared pricing')
local _,missing=W.Pricing.Price(384);drain();assert(missing=='not_observed','another consumer could not retry a released reservation')
-- New generation while work is queued cannot publish older profits.
S.ItemsChanged({[item]=true});tick()
f.header.source_watermark='903';f.Seal();W.Bridge.Begin(f.root)
W.Window.SetMode('shop');assert(W.Window.Mode()=='shop');drain();assert(not S.OpportunityStatus().running,'page switch retained a calculation worker')
W.Window.SetMode('opps');drain();assert(not S.Opportunities().calculating and W.Pricing.PendingCount()==0)
W.Window.Hide();drain();local before=S.OpportunityStatus().crafts
W.Window.Show();drain();assert(S.OpportunityStatus().crafts==before,'reopen recalculated compatible completed rows')
-- Vendor changes keep their exact dependency boundary, including a new record.
before=S.OpportunityStatus().crafts
W.Vendor.Observe({{id=65,price=5,stack=1,avail=-1}},{[65]=true},nil,c.time());drain()
assert(S.OpportunityStatus().crafts==before+2,'vendor update discarded unrelated recipes')
local rev=W.Vendor.Revision();before=S.OpportunityStatus().crafts
W.Vendor.Observe({{id=65,price=7,stack=1,avail=-1}},{[65]=true},nil,c.time());drain()
assert(W.Vendor.Revision()==rev+1 and S.OpportunityStatus().crafts==before+2,'same-count vendor replacement retained old prices')
-- Equal record counts do not imply equal deposit evidence; unrelated Ledger
-- changes that reproduce the same economic evidence preserve the context.
local originalEvidence=W.Fees.Evidence
local function evidence(per)return {invoices=0,depositCount=1,match={faction=0,neutral=0},deposits={[129]={{per=per,r=1}}}}end
local ev=evidence(5);W.Fees.Evidence=function()return ev end
W.Window.Render();drain();local est=S.Opportunities().estimator
assert(S.Opportunities().all[1].est.depositTotal==5)
before=S.OpportunityStatus().crafts;ev=evidence(5);W.Window.Render();drain()
assert(S.Opportunities().estimator==est and S.OpportunityStatus().crafts==before,'unrelated Ledger revision discarded estimates')
ev=evidence(9);W.Window.Render();drain()
assert(S.Opportunities().estimator~=est and S.Opportunities().all[1].est.depositTotal==9,'replacement fee evidence retained old deposit')
W.Fees.SetMode('off');W.Window.Render();drain();assert(S.Opportunities().all[1].est.cutWhy=='off')
W.Fees.SetMode('assumed');W.Fees.Evidence=originalEvidence;W.Window.Render();drain()
-- Admission/freshness and faction switches cannot keep old reference profits.
local now=c.time();c.time=function()return now+W.Pricing.MAX_AGE+1 end
W.Window.Render();drain();assert(S.Opportunities().summary.priced==0,'expired source retained profits')
c.time=function()return now end;W.Window.Render();drain();assert(S.Opportunities().summary.priced==128)
c.UnitFactionGroup=function()return 'Alliance'end;W.Window.Render();drain()
assert(S.Opportunities().summary.priced==0,'wrong faction retained old prices')
c.UnitFactionGroup=function()return 'Horde'end;W.Window.Render();drain()
-- Combat postpones cold data without a polling loop; regen retries the demand.
c.InCombatLockdown=function()return c.COMBAT end;c.COMBAT=true
f.header.source_watermark='905';f.Seal();W.Bridge.Begin(f.root);drain()
assert(S.OpportunityStatus().waiting==128 and W.Pricing.PendingCount()==0)
c.COMBAT=false;local frame=W.Window.Frame();frame:GetScript('OnEvent')(frame,'PLAYER_REGEN_ENABLED');drain()
assert(S.Opportunities().summary.priced==128 and S.OpportunityStatus().waiting==0)
-- A corrupt new bank restores last-good data, never its partial estimates.
local good=W.Bridge.Status().generation
for b,raw in pairs(f.parts)do c.TwichUIMarketParts['B'..('%02d'):format(b)]=raw end
c.TwichUIMarketParts.B01=c.TwichUIMarketParts.B01..' '
f.header.source_watermark='906';f.root.bank='B';f.Seal();W.Bridge.Begin(f.root);drain()
assert(W.Bridge.Status().generation==good and S.Opportunities().summary.priced==128 and W.Pricing.PendingCount()==0,'corrupt context escaped last-good rollback')
W.Suspend();drain();assert(S.OpportunityStatus().retained==0 and W.Pricing.PendingCount()==0)
-- A complete bucket demand is registered before its handoff can advance to an
-- unrelated consumer. This deliberately pauses preparation across many frames.
do
    local cc=dofile(TESTS..'auction_mock.lua');local ww=cc.TwichUI.Workshop
    local ff=dofile(TESTS..'market_cold_fixture.lua')(cc,2,{[0]=1,[1]=1});ff.Split()
    cc.GetTimePreciseSec=os.clock;local timers={}
    cc.C_Timer.After=function(_,fn)timers[#timers+1]=fn end;ww.UI.Redraw=function()end
    cc.TwichUIMarketParts={A00=ff.parts[0],A01=ff.parts[1]};cc.TwichUIMarketHistoryParts={}
    local function frame()local batch=timers;timers={};for _,fn in ipairs(batch)do fn()end end
    local function finish()for _=1,1000 do if #timers==0 then return end;frame()end;error('lease loop')end
    ww.Bridge.Begin(ff.root);finish()
    local demand={};for i=1,64 do demand[i]=i*64 end
    local lease={};local prep=coroutine.create(function()ww.Pricing.PrepareBucket(demand,coroutine.yield,lease)end)
    assert(coroutine.resume(prep));ww.Pricing.Price(65)
    for _=1,20 do frame()end
    assert(ww.Summary.Status().checked_parts==1 and ww.Pricing.PendingCount()==2,'handoff escaped an unfinished demand batch')
    for _=1,100 do if coroutine.status(prep)=='dead'then break end;assert(coroutine.resume(prep));frame()end
    finish();assert(ww.Pricing.PendingCount()==0 and ww.Summary.Status().checked_parts==2)
    assert(ww.Pricing.Price(64).price==121 and ww.Pricing.Price(65).price==121,'shared consumer lost its completion')
end
print('PASSED actual Opportunities ranking, filters, selected details, pooled scrolling, lease cancellation, page/generation switching and warm reopen')
