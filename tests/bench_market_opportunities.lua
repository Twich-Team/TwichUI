-- Opt-in audit harness. Synthetic data only; production modules are never edited.
-- From repo root: lua5.1 tests/bench_market_opportunities.lua reader alternating 32
require('bit')
REPO=REPO or './';ROOT=ROOT or './!!!TwichUI/';TESTS=TESTS or './tests/'
local mode,pattern,count=arg[1] or 'reader',arg[2] or 'single',tonumber(arg[3]) or 32
local scenario=arg[8]or 'none'
-- Optional bounded diagnostic only; never a runtime GC policy.
local gcDiagnostic=arg[9];assert(not gcDiagnostic or gcDiagnostic=='normal'or gcDiagnostic=='nogc')
local contract,requestedRows=tonumber(arg[5])or 2,tonumber(arg[6])or 32
assert(contract==2 or contract==3)
local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop;local Q,J,B,P=W.Summary,W.BridgeCodec,W.Bridge,W.Pricing
c.GetTimePreciseSec=os.clock
local function clock()return os.clock()*1000 end
local function heap()return collectgarbage('count') end
local profiling=arg[7]=='profile';local phases={}
local function probe(t,k,name)
 if not profiling or not t or not t[k] then return end
 local fn=t[k];t[k]=function(...)local at=clock();local a,b,d=fn(...);phases[name]=(phases[name]or 0)+clock()-at;return a,b,d end
end
local events,now,serial={},0,0
local callbacks,worstCallback,callbackCPU=0,0,0
local checkSettlement,activeInteraction
local callbackTimes,worstOrigin={},""
local worstBefore,worstAfter,worstPoolBefore,worstPoolAfter,gcDropMax=0,0,0,0,0
local questionMax,questionKind=0,""
local function pool()local list=W.UI.lists.opps;return list and #list.rows or 0 end
local scrollCalls,scrollCPU,scrollMax=0,0,0
local function scrollTo(list,pixels)
 list.scroll:SetVerticalScroll(pixels)
 local at=clock();local fn=list.scroll:GetScript("OnVerticalScroll")
 if fn then fn(list.scroll,pixels);scrollCalls=scrollCalls+1 end
 for _,hook in ipairs(list.scroll.hooks.OnVerticalScroll or {})do hook(list.scroll,pixels);scrollCalls=scrollCalls+1 end
 local dt=clock()-at;scrollCPU=scrollCPU+dt;scrollMax=math.max(scrollMax,dt)
end
c.C_Timer.After=function(delay,fn)
 serial=serial+1;events[#events+1]={due=now+math.max(1/60,delay),fn=fn,id=serial}
end
local peak,drops,lastHeap=heap(),0,heap()
local function sample()
 local h=heap();peak=math.max(peak,h);if h<lastHeap then drops=drops+1 end;lastHeap=h
end
local function event()
 assert(#events>0,'no scheduled work')
 table.sort(events,function(a,b)return a.due<b.due or a.due==b.due and a.id<b.id end)
 local e=table.remove(events,1);now=e.due
 local previous
 if profiling then previous={};for k,v in pairs(phases)do previous[k]=v end end
 local beforeHeap=gcDiagnostic and heap();local beforePool=gcDiagnostic and pool()
 local at=clock();e.fn();local dt=clock()-at
 local afterHeap=gcDiagnostic and heap()
 if gcDiagnostic and afterHeap<beforeHeap then gcDropMax=math.max(gcDropMax,dt)end
 callbackTimes[#callbackTimes+1]=dt
 if dt>worstCallback then
  if gcDiagnostic then worstBefore,worstAfter,worstPoolBefore,worstPoolAfter=beforeHeap,afterHeap,beforePool,pool()end
  local info=debug.getinfo(e.fn,"S");worstOrigin=info.short_src..":"..info.linedefined
  if profiling then phases._worst={};for k,v in pairs(phases)do if type(v)=='number'then phases._worst[k]=v-(previous[k]or 0)end end end
 end
 callbacks=callbacks+1;callbackCPU=callbackCPU+dt;worstCallback=math.max(worstCallback,dt);sample()
 if checkSettlement then checkSettlement()end
 if activeInteraction then activeInteraction()end
 assert(callbacks<1000000,'unbounded timer work')
end
local f=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'));local fixture=J.Parse(f:read('*a'));f:close()
local h=fixture.manifest;local row=J.Parse(fixture.parts['29'])[1]
local days=tonumber(arg[4]) or 2
if days==60 then
 local _,ending=W.BridgeValidate.Time(h.generated_at);h.observations=J.Array();row[14]=J.Array()
 for d=59,0,-1 do
  h.observations[#h.observations+1]=setmetatable({observation_id=tostring(902-d),observed_at=os.date('!%Y-%m-%dT%H:%M:%SZ',ending-d*86400),scope_complete=true,synthetic=true},J.OBJECT)
  row[14][#row[14]+1]=setmetatable({0,'100','90',5},J.ARRAY)
 end
 row[10]='100';row[11]=14;row[12]=60;row[13]=60
end
-- Same admission exercise as test_workshop_market_consumption: entirely fabricated
-- observations with ordinary admission flags. No production records or identity data.
h.synthetic=false;for _,o in ipairs(h.observations)do o.synthetic=false end
local _,stamp=W.BridgeValidate.Time(h.generated_at);c.time=function()return stamp+60 end
c.UnitFactionGroup=function()return 'Horde' end
c.GetRealmName=function()return 'Audit synthetic realm' end
c.C_Item.GetItemInfo=function(id)return 'Synthetic '..id,'item:'..id,1,1,1,'Trade Goods','',1,'',134572,0 end
h.partitions=J.Array();local rawParts,keys={},{}
local rowsPerPart= mode=='reader' and count or requestedRows
if mode=='memory' then rowsPerPart=count end
for bucket=0,63 do
 local rows=J.Array()
 for n=1,rowsPerPart do
  local id=n*64+bucket;local r=J.Copy(row);r[1]=id;r[2]=P.BaseKey(id);r[4]=tostring(120+n);r[5]=r[4]
  if n%17==0 then r[2]=J.SHA('modified:'..id) end -- missing base identities
  keys[id]=r[2];rows[#rows+1]=r
 end
 local raw=J.Encode(rows);rawParts[bucket]=raw
 h.partitions[#h.partitions+1]=setmetatable({bucket=bucket,bytes=#raw,record_count=#rows,sha256=J.SHA(raw)},J.OBJECT)
end
-- Contract 3 derives only the existing current columns; rich bytes are unchanged.
local richParts,richDescriptors=rawParts,h.partitions
local semantic={};for _,p in ipairs(richDescriptors)do semantic[#semantic+1]=p.bucket..':'..p.sha256 end
local semanticSHA=J.SHA(table.concat(semantic,';'))
local fixtureCurrentBytes,fixtureHistoryBytes=0,0
local currentParts,currentDescriptors={},J.Array()
for _,p in ipairs(richDescriptors)do
 local rich=J.ParseSummary(richParts[p.bucket],nil,1048576);local current=J.Array()
 for _,r in ipairs(rich)do local row=J.Array();for i=1,13 do row[i]=r[i]end;current[#current+1]=row end
 local raw=J.Encode(current);currentParts[p.bucket]=raw
 currentDescriptors[#currentDescriptors+1]=setmetatable({bucket=p.bucket,bytes=#raw,record_count=p.record_count,sha256=J.SHA(raw)},J.OBJECT)
 fixtureCurrentBytes=fixtureCurrentBytes+#raw;fixtureHistoryBytes=fixtureHistoryBytes+#richParts[p.bucket]
end
if contract==3 then
 h.schema_version=3;h.contract_version=3;table.remove(h.columns)
 h.history_partitioning=J.Copy(h.partitioning);h.history_partitions=richDescriptors
 h.partitioning.max_total_bytes=33554432;h.partitions=currentDescriptors;rawParts=currentParts
end
h.record_count=rowsPerPart*64;h.coverage.source_records=h.record_count;h.coverage.delivered_records=h.record_count
local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
local input={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='isolated-audit',completed_at=h.generated_at},J.OBJECT))}
local loads,historyLoads,compileMS,executeMS,decodes,repeats,seen=0,0,0,0,0,0,{}
c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts={}
c.C_AddOns.LoadAddOn=function(name)
 local b=assert(tonumber(name:match('A(%d%d)$')));loads=loads+1
 local historical=name:find('History',1,true)~=nil;if historical then historyLoads=historyLoads+1 end
 -- Compile a trusted synthetic addon assignment, never imported/untrusted Lua.
 local global=historical and 'TwichUIMarketHistoryParts' or 'TwichUIMarketParts'
 local source=global..'['..string.format('%q','A'..('%02d'):format(b))..']='..string.format('%q',(historical and richParts or rawParts)[b])
 local at=clock();local fn=assert(loadstring(source));setfenv(fn,c);compileMS=compileMS+clock()-at
 at=clock();fn();executeMS=executeMS+clock()-at;return true
end
local parse=J.ParseSummary
J.ParseSummary=function(raw,...)
 decodes=decodes+1;if seen[raw] then repeats=repeats+1 end;seen[raw]=true
 return parse(raw,...)
end
local records,prices,crafts,draws,estimatorInstances=0,0,0,0,0
local finalView,auditRecipes
local overlays={}
local synchronousLists=0
local originalRows=W.Opps.Rows
W.Opps.Rows=function(...)synchronousLists=synchronousLists+1;return originalRows(...)end
local requestedAt={}
local waiting,finished,waits={}, {}, {}
local terminalItems={}
local referenceFirst,referenceTen,referenceCount=nil,nil,0
local record=B.Record;B.Record=function(item,key,...)
 records=records+1;local id=tostring(item)..':'..tostring(key)
 local began=requestedAt[item]or waiting[id]or now
 local r,why=record(item,key,...)
 if why=='loading'then waiting[id]=began
 elseif why~='combat' and not finished[id]then
  terminalItems[item]=true
  finished[id]=true;waits[#waits+1]=now-began;waiting[id]=nil
  if r and r.current.metrics.recent_copper~=J.NULL then
   referenceCount=referenceCount+1
   referenceFirst=referenceFirst or now
   if referenceCount==10 then referenceTen=now end
  end
 end
 return r,why
end
local price=P.Price;P.Price=function(item,...)
 prices=prices+1;local value,why=price(item,...)
 if value and overlays[item]then local copy={};for k,v in pairs(value)do copy[k]=v end;copy.price=copy.price+overlays[item];return copy,why end
 return value,why
end
local oldNew=W.Estimate.New
W.Estimate.New=function(...)
 estimatorInstances=estimatorInstances+1;local est=oldNew(...);local craft=est.Craft
 if gcDiagnostic then
  for kind,fn in pairs(est.ctx)do if type(fn)=='function'then
   local name,call=kind,fn
   est.ctx[name]=function(...)local at=clock();local a,b,d=call(...);local dt=clock()-at
    if dt>questionMax then questionMax,questionKind=dt,name end;return a,b,d end
  end end
 end
 est.Craft=function(self,...)crafts=crafts+1;local at=profiling and not W.OpportunityEngine and clock();local result=craft(self,...);if at then phases.craft=(phases.craft or 0)+clock()-at end;return result end
 return est
end
if W.OpportunityEngine then
 local newEngine=W.OpportunityEngine.New
 W.OpportunityEngine.New=function(...)local engine=newEngine(...);probe(engine,'Step','engine');return engine end
end
B.Begin(input);while Q.Pending()do event()end
-- Clear header notification before measuring a workload.
while #events>0 do event()end
collectgarbage('collect');local base=heap();peak=base;lastHeap=base;drops=0
callbacks,worstCallback,callbackCPU=0,0,0
local validationStart=Q.Status().validation_ms
local baseKeyCalls,baseKeyMS=0,0
local baseKey=P.BaseKey
P.BaseKey=function(item,...)
 requestedAt[item]=requestedAt[item]or now
 local at=clock();local key=baseKey(item,...);baseKeyMS=baseKeyMS+clock()-at;baseKeyCalls=baseKeyCalls+1;return key
end
if gcDiagnostic=='nogc'then collectgarbage('stop')end
local start=clock();local startVirtual=now;local out=J.Object()
if mode=='reader' then
 local first=clock();assert(not B.Record(64,keys[64]));while Q.Pending()do event()end
 out.initial_load_decode_ms=clock()-first
 local before=decodes;local at=clock()
 for i=1,1000 do
  local b=pattern=='batched' and math.floor((i-1)*64/1000) or pattern:match('^single') and 0 or (i-1)%64
  local n=pattern:match('distinct') and (1+math.floor((i-1)/64)%rowsPerPart) or 1;local id=n*64+b
  local r,why=B.Record(id,keys[id]);while not r and why=='loading' do event();r,why=B.Record(id,keys[id])end
  assert(r and tonumber(r.current.metrics.recent_copper)==120+n);sample()
 end
 out.lookup_1000_ms=clock()-at;out.lookup_decodes=decodes-before
elseif mode=='memory' then
 -- Model retaining decoder outputs without altering the reader. Includes raw globals.
 local retain={};local parseActual=J.ParseSummary
 J.ParseSummary=function(...)local rows=parseActual(...);retain[#retain+1]=rows;return rows end
 for b=0,tonumber(pattern)-1 do
  B.Record(64+b,keys[64+b]);while Q.Pending()do event()end;sample()
 end
 collectgarbage('collect');out.retained_partition_count=#retain
 local beforeIndex=heap();local at=clock();local indexes={}
 for b,rows in ipairs(retain)do local index={};indexes[b]=index;for pos,r in ipairs(rows)do index[r[1]]=pos end end
 out.index_build_ms=clock()-at;collectgarbage('collect');out.index_retained_kib=heap()-beforeIndex
 -- Model numeric item -> position only. Multiple variants require ranges or binary search.
 out.modeled_index_partitions=#indexes
else
 local recipes={}
 for i=1,count do recipes[i]={id=i,name='Synthetic craft '..i,prof=171,filled=true,outItem=128+i%math.max(1000,count),outMin=1,outMax=1,
  mats={{item=64+i%64,qty=1+i%4},{item=64+(i*7)%64,qty=2+i%3}}} end
 W.Session.AllRecipes=function()return recipes end
 probe(W.Session,"AllRecipes","catalog");probe(W.Session,"Estimator","estimator")
 probe(W.Opps,"Rows","rows");probe(W.Opps,"Select","sort");probe(W.Opps,"Summary","summary")
 probe(W.UI.pages and W.UI.pages.opps,"Render","view");probe(W.Facts,"Chart","chart")
 probe(W.Session,"OppStrategy","strategy");probe(W.Strategy,"Bump","strategyBump")
 probe(W.Junk,"Request","junk");probe(W.WorthTip,"Refresh","tooltip");probe(W.AuctionUI,"Schedule","auction")
 local visibleCohort,last,visibleCatalog,visibleById,lastPricingRevision
 local needed={};for _,rec in ipairs(recipes)do needed[rec.outItem]=true;for _,mat in ipairs(rec.mats)do needed[mat.item]=true end end
 local target=0;for _ in pairs(needed)do target=target+1 end
 checkSettlement=function()
  if last and not out.visible_settlement_model_seconds then
   local list=pattern=='ui'and W.UI.lists.opps
   if not visibleCohort and list and #list.data>0 then
    visibleCohort={};local first=list.first or 1
    for i=first,math.min(#list.data,first+math.min(#list.rows,128)-1)do visibleCohort[#visibleCohort+1]=list.data[i].rec.id end
    out.visible_cohort_size=#visibleCohort
   end
   if visibleCohort then
    if visibleCatalog~=last.all then
     visibleCatalog=last.all;visibleById={};for _,row in ipairs(last.all)do visibleById[row.rec.id]=row end
    end
    local ready=lastPricingRevision==P.Generation()
    for _,id in ipairs(visibleCohort)do
     local row=visibleById[id];local why=row and row.est.why
     if not row or why=='calculating'or why=='loading'or why=='combat'then ready=false;break end
     if not terminalItems[row.rec.outItem]then ready=false;break end
     for _,mat in ipairs(row.rec.mats)do if not terminalItems[mat.item]then ready=false;break end end
    end
    if ready then out.visible_settlement_model_seconds=now-startVirtual;out.visible_settlement_cpu_ms=clock()-start end
   end
  end
  if not out.pricing_settlement_model_seconds and P.PendingCount()==0 and P.CacheSize()>=target then
   out.pricing_settlement_model_seconds=now-startVirtual;out.pricing_settlement_cpu_ms=clock()-start
  end
 end
 local first,ten=nil,nil
 local opportunities=W.Session.Opportunities
 W.Session.Opportunities=function(...)
  draws=draws+1;local v=opportunities(...)
  local n=v.summary.priced
  if n>0 and not first then first=now-startVirtual;out.first_cpu_ms=clock()-start end
  if n>=math.min(10,count) and not ten then ten=now-startVirtual end
  if not out.opportunities_settlement_model_seconds and P.PendingCount()==0 and P.CacheSize()>=target and not v.calculating then
   out.opportunities_settlement_model_seconds=now-startVirtual;out.opportunities_settlement_cpu_ms=clock()-start
  end
  last=v;lastPricingRevision=P.Generation();sample();return v
 end
 local initial=clock()
 if pattern=='ui' then W.Window.SetMode('opps');W.Window.Show();W.Window.Render()
 else W.UI.Redraw=function()W.Session.Opportunities()end;W.UI.Redraw() end
 out.initial_request_cpu_ms=clock()-initial
 if scenario=='scroll'and pattern=='ui'then
  activeInteraction=function()
   local list=W.UI.lists.opps
   if callbacks%10==0 and #list.data>0 then
    scrollTo(list,((callbacks*17)%#list.data)*list.rowH)
    out.active_scrolls=(out.active_scrolls or 0)+1
   end
  end
 end
 checkSettlement();while #events>0 do event()end
 activeInteraction=nil
 assert(out.pricing_settlement_model_seconds,"price identities did not settle")
 if scenario~='none'then
  local beforeCrafts,beforeViews,beforeRows=crafts,draws,synchronousLists
  local beforeRecords=records;local beforeSorts=W.Session.OpportunityStatus and(W.Session.OpportunityStatus().sorts or 0)or 0
  local at,virtual=clock(),now
  if scenario=='single'or scenario=='burst'then
   local changed={};for item=64,(scenario=='single'and 65 or 127)do if scenario~='single'or item==65 then changed[item]=true;overlays[item]=7 end end
   local expected=0;for _,rec in ipairs(recipes)do
    local hit=changed[rec.outItem];for _,mat in ipairs(rec.mats)do hit=hit or changed[mat.item]end
    if hit then expected=expected+1 end
   end
   out.scenario_expected_recipes=expected
   if W.Session.ItemsChanged then W.Session.ItemsChanged(changed)else W.Session.ForgetEstimator()end
   W.UI.Redraw()
  elseif scenario=='reopen'then
   for i=1,5 do
    if pattern=='ui'then W.Window.Hide();W.Window.Show()else if W.Session.PauseOpportunities then W.Session.PauseOpportunities()end;W.UI.Redraw()end
    while #events>0 do event()end
   end
  elseif scenario=='filters'then
   for i=1,100 do
    W.Session.opp.sort=({'profit','cost','sell','margin'})[1+i%4];W.Session.opp.desc=i%2==0
    W.Session.opp.prof=i%3==0 and 171 or nil;W.Session.opp.profitOnly=i%5==0;W.Session.opp.hideLow=i%7==0
    W.UI.Redraw()
   end
  elseif scenario=='scroll'then
   assert(pattern=='ui','scroll workload requires actual UI')
   local list=W.UI.lists.opps
   for i=1,100 do
    scrollTo(list,((i*17)%count)*list.rowH)
   end
  elseif scenario=='generation'then
   for pass=1,3 do
    h.source_watermark=tostring(9999+pass);local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
    input={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='isolated-audit',completed_at=h.generated_at},J.OBJECT))}
    B.Begin(input);W.UI.Redraw();while #events>0 do event()end
   end
   out.scenario_generations=3
  elseif scenario=='stress'then
   for pass=1,20 do
    local changed={};for item=64,127 do changed[item]=true;overlays[item]=pass end
    if W.Session.ItemsChanged then W.Session.ItemsChanged(changed)else W.Session.ForgetEstimator()end
    for i=1,5 do W.Session.opp.sort=({'profit','cost','sell','margin'})[1+(pass+i)%4];W.UI.Redraw()end
    if pattern=='ui'then
     local list=W.UI.lists.opps;scrollTo(list,((pass*37)%count)*list.rowH)
     if pass%4==0 then W.Window.Hide();W.Window.Show()end
    end
    while #events>0 do event()end
    if pass==1 or pass==10 or pass==20 then
     local gc=clock();collectgarbage('collect')
     out.scenario_gc_ms=(out.scenario_gc_ms or 0)+clock()-gc
     out['scenario_retained_pass_'..pass..'_kib']=heap()-base
    end
   end
  else error('unknown scenario')end
  while #events>0 do event()end
  W.Session.Opportunities()
  out.scenario_cpu_ms=clock()-at;out.scenario_model_seconds=now-virtual
  out.scenario_crafts=crafts-beforeCrafts;out.scenario_views=draws-beforeViews;out.scenario_full_lists=synchronousLists-beforeRows
  out.scenario_record_calls=records-beforeRecords
  out.scenario_sorts=W.Session.OpportunityStatus and(W.Session.OpportunityStatus().sorts or 0)-beforeSorts or -1
 end
 out.priced=last.summary.priced;out.unpriced=count-out.priced
 out.first_model_seconds=first or -1;out.ten_model_seconds=ten or -1
 local warmStart=clock();local beforeRecords,beforeCrafts=records,crafts
 local oldEst=last.estimator;W.Session.Opportunities();out.warm_ms=clock()-warmStart
 out.warm_record_calls=records-beforeRecords;out.warm_crafts=crafts-beforeCrafts;out.warm_estimator_reused=oldEst==last.estimator
 out.estimator_instances=estimatorInstances
 out.memo_hits=last.estimator.hits;out.memo_asked=last.estimator.asked
 finalView=last;auditRecipes=recipes
end
out.base_key_calls=baseKeyCalls;out.base_key_cpu_ms=baseKeyMS;out.cpu_ms=clock()-start;out.model_seconds=now-startVirtual
out.loads=loads;out.decodes=decodes;out.repeated_decodes=repeats;out.record_calls=records;out.price_calls=prices;out.crafts=crafts;out.view_requests=draws;out.synchronous_full_lists=synchronousLists
out.full_calculations=synchronousLists+(W.Session.OpportunityStatus and W.Session.OpportunityStatus().catalogBuilds or 0)
out.compile_ms=compileMS;out.execute_ms=executeMS;out.validation_ms=Q.Status().validation_ms-validationStart;out.lookup_calls=Q.Status().lookup_calls
out.callbacks=callbacks;out.callback_cpu_ms=callbackCPU;out.worst_callback_ms=worstCallback
out.scroll_handler_calls=scrollCalls;out.scroll_cpu_ms=scrollCPU;out.scroll_max_cpu_ms=scrollMax
if scenario=='scroll'then assert(scrollCalls>=100,'scroll benchmark did not dispatch production hooks')end
if gcDiagnostic then
 out.diagnostic_gc_mode=gcDiagnostic;out.worst_heap_before_kib=worstBefore;out.worst_heap_after_kib=worstAfter
 out.worst_pool_before=worstPoolBefore;out.worst_pool_after=worstPoolAfter;out.max_heap_drop_callback_ms=gcDropMax
 out.max_question_ms=questionMax;out.max_question_kind=questionKind
end
out.worst_callback_source=worstOrigin;table.sort(callbackTimes)
out.callback_p95_ms=callbackTimes[math.max(1,math.ceil(#callbackTimes*.95))]or 0
out.callback_p99_ms=callbackTimes[math.max(1,math.ceil(#callbackTimes*.99))]or 0
if W.Session.OpportunityStatus then for k,v in pairs(W.Session.OpportunityStatus())do if type(v)=='number'then out['engine_'..k]=v end end end
out.sampled_peak_delta_kib=peak-base;out.heap_drops=drops
local gc=clock();collectgarbage('collect');out.explicit_gc_ms=clock()-gc;out.retained_delta_kib=heap()-base
out.raw_loaded_bytes=Q.Status().bytes;out.price_cache_entries=P.CacheSize();out.decoded_partitions=Q.Status().decoded_parts
out.history_days=days;out.mode=mode;out.pattern=pattern;out.count=count;out.rows_per_partition=rowsPerPart;out.raw_fixture_bytes=0
for _,raw in pairs(rawParts)do out.raw_fixture_bytes=out.raw_fixture_bytes+#raw end
out.synthetic=true;out.real_client=false;out.timer_model='minimum one 60Hz frame per After; CPU reported separately'
table.sort(waits)
out.scenario=scenario;out.contract_version=contract;out.semantic_fixture_sha256=semanticSHA
out.fixture_current_bytes=fixtureCurrentBytes;out.fixture_history_bytes=fixtureHistoryBytes;out.history_loads=historyLoads
out.first_reference_model_seconds=referenceFirst and referenceFirst-startVirtual or -1
out.ten_references_model_seconds=referenceTen and referenceTen-startVirtual or -1
out.record_wait_p50_model_seconds=waits[math.max(1,math.ceil(#waits*.5))]or -1
out.record_wait_p95_model_seconds=waits[math.max(1,math.ceil(#waits*.95))]or -1
out.record_wait_max_model_seconds=waits[#waits]or -1
out.current_raw_loaded_bytes=Q.Status().current_bytes or 0;out.history_raw_loaded_bytes=Q.Status().history_bytes or 0
for k,v in pairs(phases)do
 if type(v)=='number'then out['profile_'..k..'_ms']=v
 else for name,ms in pairs(v)do out['worst_profile_'..name..'_ms']=ms end end
end
-- The oracle is outside workload CPU/heap timing. Every final economic field,
-- filtered order and summary must agree with one fresh full recomputation.
if finalView then
 local function canonical(v)
  if type(v)=='number'then return ('%.17g'):format(v)end
  if type(v)~='table'then return J.Encode(v)end
  local keys={};for k in pairs(v)do if k~='_est'and k~='_rec'and k~='typicalDone'and k~='typical'and k~='nowOnly'and k~='usually'then keys[#keys+1]=k end end
  table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
  local fields={};for _,k in ipairs(keys)do fields[#fields+1]=J.Encode(tostring(k))..':'..canonical(v[k])end
  return '{'..table.concat(fields,',')..'}'
 end
 local function snapshot(rows)
  local parts={};for _,row in ipairs(rows)do parts[#parts+1]=row.rec.id..':'..canonical(row.est)end
  return table.concat(parts,';')
 end
 local beforeRecords=records;local at=clock()
 local fresh=W.Estimate.New(finalView.estimator.ctx)
 local full=W.Opps.Rows(auditRecipes,finalView.lookup,finalView.rate,nil,fresh)
 assert(snapshot(full)==snapshot(finalView.all),'incremental economic results differ from full recomputation')
 local sorted=W.Opps.Select(full,W.Session.opp)
 assert(#sorted==#finalView.rows,'filtered row count differs')
 for i,row in ipairs(sorted)do assert(row.rec.id==finalView.rows[i].rec.id,'final ranking differs')end
 local summary=W.Opps.Summary(full)
 assert(summary.priced==finalView.summary.priced and summary.profitable==finalView.summary.profitable and summary.total==finalView.summary.total,'summary differs')
 out.result_sha256=J.SHA(snapshot(full));out.oracle_passed=true
 out.oracle_ms=clock()-at;out.oracle_reader_calls=records-beforeRecords
end
local fields={}
for k,v in pairs(out)do
 local value=type(v)=='number' and string.format('%.6f',v) or J.Encode(v)
 fields[#fields+1]=J.Encode(k)..':'..value
end
table.sort(fields);if not AUDIT_QUIET then print('{'..table.concat(fields,',')..'}') end
return out
