-- Real estimator and engine against full recomputation, with deterministic CPU.
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
local E,Op=W.Estimate,W.Opps
local NOW=1800000000;local ms,events,publications=0,{},0
c.time=function()return NOW end;c.GetTimePreciseSec=function()return ms/1000 end
c.C_Timer.After=function(_,fn)events[#events+1]=fn end
local queries={};local prices={};for item=1,1000 do prices[item]=100+item end
local function ask(kind,item,extra)
    ms=ms+.025;local k=kind..':'..item..':'..tostring(extra or '')
    queries[k]=(queries[k]or 0)+1
end
local loading={}
local ctx={now=NOW,cut={rate=.05,source='test'},
    price=function(item)ask('price',item);if loading[item]then return nil,'loading'end
        return prices[item]and {price=prices[item],at=NOW-60,complete=true,source='local'}end,
    cost=function(item,qty)ask('cost',item,qty);if not prices[item]then return {state='none'}end
        return {state='exact',cost=prices[item]*qty,high=prices[item]*qty,at=NOW-60,complete=true,quality='good'}end,
    quality=function()return {level='good',facts={listings=20,observedDays=20}}end,
    value=function(item)if prices[item]then return {value=prices[item]}end end,
    vendorSell=function()return 0 end}
local recipes={}
for i=1,128 do recipes[i]={id=i,name=('Craft %03d'):format(i),prof=i%2,outItem=200+i,outMin=1,outMax=1,
    mats={{item=10+i%4,qty=1+i%3}}}end
local args={key='generation-a',recipes=recipes,estimator=E.New(ctx),filter={sort='profit',desc=true},now=NOW}
local engine=W.OpportunityEngine.New(function()publications=publications+1 end)
local function tick()
    local batch=events;events={};for _,fn in ipairs(batch)do fn()end
end
local function drain()
    for _=1,3000 do if #events==0 then assert(not engine:Status().running,engine.error);return end;tick()end
    error('runaway opportunity worker')
end
local function equivalent(a,b,path)
    path=path or ''
    assert(type(a)==type(b),'type '..path)
    if type(a)~='table'then assert(a==b,path..': '..tostring(a)..' / '..tostring(b));return end
    for k,v in pairs(a)do if k~='_est'and k~='_rec'then equivalent(v,b[k],path..'.'..k)end end
    for k,v in pairs(b)do if k~='_est'and k~='_rec'then assert(a[k]~=nil,'missing '..path..'.'..k)end end
end
local function reference()
    local fresh=E.New(ctx);local rows=Op.Rows(recipes,nil,nil,nil,fresh)
    equivalent(engine.summary,Op.Summary(rows),'summary')
    for i,row in ipairs(engine.all)do equivalent(row.est,rows[i].est,'recipe '..i)end
    local sorted=Op.Select(rows,args.filter);assert(#engine.rows==#sorted)
    for i,row in ipairs(sorted)do assert(engine.rows[i].rec.id==row.rec.id,'ranking '..i)end
end
engine:Request(args);assert(#events==1,'duplicate initial workers');assert(engine:Status().running)
drain();assert(not engine.error);assert(engine.stats.crafts==128);assert(engine.stats.worstBatch<=2.06,'elapsed budget ignored')
local q=queries['cost:10:1'];assert(q==1,'shared material/quantity not memoized')
local all,rows=engine.all,engine.rows;local calls=engine.stats.crafts
engine:Request(args);assert(#events==0 and engine.all==all and engine.rows==rows and engine.stats.crafts==calls,'warm work was rebuilt')
reference()
local unaffected=engine.byId[1].est
prices[10]=999;engine:ItemsChanged({[10]=true})
assert(engine.byId[4].est.state=='unknown'and engine.byId[1].est==unaffected,'changed prices exposed old profits')
drain();assert(engine.stats.crafts==calls+32,'single material touched unrelated recipes')
assert(engine.byId[1].est==unaffected);reference()
calls=engine.stats.crafts
for _,sort in ipairs({'profit','cost','sell','margin'})do
    args.filter={sort=sort,desc=false,prof=1,hideLow=true};engine:Request(args);drain();reference()
end
args.filter={sort='profit',desc=true,profitOnly=true};engine:Request(args);drain();reference()
args.filter={sort='profit',desc=true};engine:Request(args);drain();reference()
assert(engine.stats.crafts==calls,'presentation changes recalculated recipes')
local sorts=engine.stats.sorts
args.filter={sort='profit',desc=true,prof=1};engine:Request(args);drain();reference()
assert(engine.stats.sorts==sorts,'filter-only change sorted unchanged rankings')
args.filter={sort='profit',desc=true};engine:Request(args);drain()
-- Mutable recipe objects need value snapshots, not identity-only reuse.
recipes[1].mats[1].qty=7;local copy={};for i,r in ipairs(recipes)do copy[i]=r end;recipes=copy;args.recipes=recipes
engine:Request(args);drain();assert(engine.stats.crafts==calls+1,'recipe change was lost or rebuilt everything');reference()
-- Pending price questions wait for an event; there is no polling timer chain.
loading[11]=true;engine:ItemsChanged({[11]=true});drain()
assert(engine.waiting==32 and #events==0 and not engine.co,'pending answers busy-looped')
local stableRows=engine.rows;local reused=engine.stats.partialReuses or 0
engine.presentDirty=true;engine:Request(args);drain()
assert(engine.rows==stableRows and engine.stats.partialReuses>reused,'unchanged provisional membership was rebuilt')
args.filter={sort='profit',desc=true,profitOnly=true};engine:Request(args);drain()
for _,row in ipairs(engine.rows)do assert(row.est.state=='ok'and row.est.profitLow>0,'price-dependent membership reused pending rows')end
loading[12]=true;engine:ItemsChanged({[12]=true});drain();local oldCount=#engine.rows
loading[11]=nil;engine:ItemsChanged({[11]=true});drain()
local partial=Op.Select(engine.all,args.filter)
assert(engine.waiting==32 and #partial>oldCount and #engine.rows==#partial,'partial profitable membership missed newly completed rows')
local members={};for _,row in ipairs(partial)do members[row.rec.id]=true end
for _,row in ipairs(engine.rows)do assert(members[row.rec.id],'partial membership differs');members[row.rec.id]=nil end
assert(not next(members),'partial membership omitted a completed row')
loading[12]=nil;engine:ItemsChanged({[12]=true});drain()
args.filter={sort='profit',desc=true};engine:Request(args);drain()
loading[11]=nil;engine:ItemsChanged({[11]=true});drain();reference()
-- Old callbacks and partially evaluated recipes cannot publish into a new context.
prices[12]=777;engine:ItemsChanged({[12]=true});tick()
args.key='generation-b';args.estimator=E.New(ctx);engine:Request(args);drain();reference()
local warm=engine.stats.crafts;engine:Cancel(false);engine:Request(args);drain()
assert(engine.stats.crafts==warm,'reopening discarded compatible completed results')
prices[13]=nil;engine:ItemsChanged({[13]=true});drain();reference()
assert(engine.summary.priced==96,'missing material invented a price')
assert(engine:Status().retained==128 and not engine:Status().running and publications<100,'unbounded state/refresh loop')
-- A redraw across a cooldown second touches only recipes with timed inputs.
recipes[1].cd={left=10,at=NOW};args.catalogRevision=1
engine:Request(args);drain();local before=engine.stats.crafts
ctx.now=NOW+2;args.now=NOW+2;engine:Request(args);drain()
assert(engine.stats.crafts==before+1 and engine.byId[1].est.cooldown.left==8,'cooldown time reused a stale result or invalidated unrelated rows')
reference();ctx.now=nil
-- Stop during a build and replace it before any stale scheduled resume.
args.key='generation-c';args.estimator=E.New(ctx);engine:Request(args);engine:Cancel(true);drain()
assert(#engine.all==0 and #engine.rows==0 and not engine.co)
-- A single expensive recipe is subdivided; no scope spans a yield.
local depth=0;local perf=c.TwichUI.Perf
perf.on=true;perf.Start=function()depth=depth+1;return depth end
perf.Stop=function()depth=depth-1;assert(depth>=0)end
perf.Call=function(_,fn,...)perf.Start();local a,b=fn(...);perf.Stop();return a,b end
local oldCost=ctx.cost;ctx.cost=function(...)ms=ms+1;return oldCost(...)end
local big={id=900,name='Many materials',outItem=400,outMin=1,outMax=1,mats={}}
for i=1,16 do big.mats[i]={item=i,qty=1}end
engine=W.OpportunityEngine.New();args={key='expensive',recipes={big},estimator=E.New(ctx),now=NOW}
engine:Request(args);assert(depth==0 and engine:Status().running,'single recipe blocked the first slice')
for _=1,1000 do if #events==0 then break end;tick();assert(depth==0,'CPU scope crossed a callback/yield')end
assert(engine.completed==1 and engine.stats.crafts==1 and engine.stats.batches>=5)
assert(engine.stats.worstBatch<=3.06,'slice exceeded its budget plus one measured indivisible question')
args.key='timer-old';args.estimator=E.New(ctx);engine:Request(args)
local stale=events[#events]
args.key='timer-new';args.estimator=E.New(ctx);engine:Request(args)
local batches=engine.stats.batches;stale();assert(engine.stats.batches==batches,'obsolete callback advanced a newer worker')
drain()
-- A changed source during a suspended recipe suppresses its publication.
local valid=true;args.key='obsolete';args.estimator=E.New(ctx);args.valid=function()return valid end
engine:Request(args);valid=false;drain();assert(#engine.all==0 and not engine.co)
engine:Cancel(true);assert(engine.groups==nil and engine.provisional==nil and engine.args==nil)
local broken=E.New(ctx);broken.Craft=function()error('synthetic negative control')end
local faults=0;local oldFault=c.TwichUI.Fault
c.TwichUI.Fault=function(area,why)assert(area=='opportunities'and tostring(why):find('synthetic negative control',1,true));faults=faults+1 end
args={key='failed-context',recipes={big},estimator=broken,now=NOW}
engine:Request(args);drain();assert(engine.error=='calculation_failed'and engine.stats.errors==1)
engine:Request(args);assert(#events==0 and engine.stats.errors==1,'failed work retried indefinitely')
assert(faults==1);c.TwichUI.Fault=oldFault
engine:Cancel(true)
local bounded=E.New(ctx);bounded.size=20000;bounded.memo.sentinel={true};bounded.itemVersions[42]=9
engine:Request({key='memo-capacity',recipes={big},estimator=bounded,now=NOW});drain()
assert(not bounded.memo.sentinel and bounded.size<20000,'question memo was not bounded between recipes')
engine:Cancel(true)
local excess={};for i=1,W.OpportunityEngine.MAX_RECIPES+1 do excess[i]=big end
engine:Request({key='too-large',recipes=excess,now=NOW});assert(engine.error=='recipe_limit'and #engine.all==0 and not engine.co)
print('PASSED incremental/full equivalence, shared memo, targeted prices, ranking, mutable recipes, pending, cancellation and capacity')
