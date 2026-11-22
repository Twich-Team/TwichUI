-- Opt-in audit harness. Synthetic data only; production modules are never edited.
-- From repo root: lua5.1 tests/bench_market_opportunities.lua reader alternating 32
require('bit')
REPO=REPO or './';ROOT=ROOT or './!!!TwichUI/';TESTS=TESTS or './tests/'
local mode,pattern,count=arg[1] or 'reader',arg[2] or 'single',tonumber(arg[3]) or 32
local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop;local Q,J,B,P=W.Summary,W.BridgeCodec,W.Bridge,W.Pricing
c.GetTimePreciseSec=os.clock
local function clock()return os.clock()*1000 end
local function heap()return collectgarbage('count') end
local events,now,serial={},0,0
local callbacks,worstCallback,callbackCPU=0,0,0
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
 local at=clock();e.fn();local dt=clock()-at;callbacks=callbacks+1;callbackCPU=callbackCPU+dt;worstCallback=math.max(worstCallback,dt);sample()
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
local rowsPerPart= mode=='reader' and count or 32
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
h.record_count=rowsPerPart*64;h.coverage.source_records=h.record_count;h.coverage.delivered_records=h.record_count
local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
local input={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='isolated-audit',completed_at=h.generated_at},J.OBJECT))}
local loads,compileMS,executeMS,decodes,repeats,seen=0,0,0,0,0,{}
c.TwichUIMarketParts={}
c.C_AddOns.LoadAddOn=function(name)
 local b=assert(tonumber(name:match('A(%d%d)$')));loads=loads+1
 -- Compile a trusted synthetic addon assignment, never imported/untrusted Lua.
 local source='TwichUIMarketParts['..string.format('%q','A'..('%02d'):format(b))..']='..string.format('%q',rawParts[b])
 local at=clock();local fn=assert(loadstring(source));setfenv(fn,c);compileMS=compileMS+clock()-at
 at=clock();fn();executeMS=executeMS+clock()-at;return true
end
local parse=J.ParseSummary
J.ParseSummary=function(raw,...)
 decodes=decodes+1;if seen[raw] then repeats=repeats+1 end;seen[raw]=true
 return parse(raw,...)
end
local records,prices,crafts,draws,estimatorInstances=0,0,0,0,0
local record=B.Record;B.Record=function(...)records=records+1;return record(...)end
local price=P.Price;P.Price=function(...)prices=prices+1;return price(...)end
local oldNew=W.Estimate.New
W.Estimate.New=function(...)
 estimatorInstances=estimatorInstances+1;local est=oldNew(...);local craft=est.Craft
 est.Craft=function(self,...)crafts=crafts+1;return craft(self,...)end
 return est
end
B.Begin(input);while Q.Pending()do event()end
-- Clear header notification before measuring a workload.
while #events>0 do event()end
collectgarbage('collect');local base=heap();peak=base;lastHeap=base;drops=0
callbacks,worstCallback,callbackCPU=0,0,0
local validationStart=Q.Status().validation_ms
local baseKeyCalls,baseKeyMS=0,0
local baseKey=P.BaseKey
P.BaseKey=function(...)
 local at=clock();local key=baseKey(...);baseKeyMS=baseKeyMS+clock()-at;baseKeyCalls=baseKeyCalls+1;return key
end
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
 for i=1,count do recipes[i]={id=i,name='Synthetic craft '..i,prof=171,filled=true,outItem=128+i%1000,outMin=1,outMax=1,
  mats={{item=64+i%64,qty=1+i%4},{item=64+(i*7)%64,qty=2+i%3}}} end
 W.Session.AllRecipes=function()return recipes end
 local first,ten,last=nil,nil,nil
 local opportunities=W.Session.Opportunities
 W.Session.Opportunities=function(...)
  draws=draws+1;local v=opportunities(...)
  local n=v.summary.priced
  if n>0 and not first then first=now-startVirtual;out.first_cpu_ms=clock()-start end
  if n>=math.min(10,count) and not ten then ten=now-startVirtual end
  last=v;sample();return v
 end
 if pattern=='ui' then W.Window.SetMode('opps');W.Window.Show();W.Window.Render()
 else W.UI.Redraw=function()W.Session.Opportunities()end;W.UI.Redraw() end
 while #events>0 do event()end
 out.priced=last.summary.priced;out.unpriced=count-out.priced
 out.first_model_seconds=first or -1;out.ten_model_seconds=ten or -1
 local warmStart=clock();local beforeRecords,beforeCrafts=records,crafts
 local oldEst=last.estimator;W.Session.Opportunities();out.warm_ms=clock()-warmStart
 out.warm_record_calls=records-beforeRecords;out.warm_crafts=crafts-beforeCrafts;out.warm_estimator_reused=oldEst==last.estimator
 out.estimator_instances=estimatorInstances
 out.memo_hits=last.estimator.hits;out.memo_asked=last.estimator.asked
end
out.base_key_calls=baseKeyCalls;out.base_key_cpu_ms=baseKeyMS;out.cpu_ms=clock()-start;out.model_seconds=now-startVirtual
out.loads=loads;out.decodes=decodes;out.repeated_decodes=repeats;out.record_calls=records;out.price_calls=prices;out.crafts=crafts;out.full_calculations=draws
out.compile_ms=compileMS;out.execute_ms=executeMS;out.validation_ms=Q.Status().validation_ms-validationStart;out.lookup_calls=Q.Status().lookup_calls
out.callbacks=callbacks;out.callback_cpu_ms=callbackCPU;out.worst_callback_ms=worstCallback
out.sampled_peak_delta_kib=peak-base;out.heap_drops=drops
local gc=clock();collectgarbage('collect');out.explicit_gc_ms=clock()-gc;out.retained_delta_kib=heap()-base
out.raw_loaded_bytes=Q.Status().bytes;out.price_cache_entries=P.CacheSize();out.decoded_partitions=Q.Status().decoded_parts
out.history_days=days;out.mode=mode;out.pattern=pattern;out.count=count;out.rows_per_partition=rowsPerPart;out.raw_fixture_bytes=0
for _,raw in pairs(rawParts)do out.raw_fixture_bytes=out.raw_fixture_bytes+#raw end
out.synthetic=true;out.real_client=false;out.timer_model='minimum one 60Hz frame per After; CPU reported separately'
local fields={}
for k,v in pairs(out)do
 local value=type(v)=='number' and string.format('%.6f',v) or J.Encode(v)
 fields[#fields+1]=J.Encode(k)..':'..value
end
table.sort(fields);if not AUDIT_QUIET then print('{'..table.concat(fields,',')..'}') end
return out
