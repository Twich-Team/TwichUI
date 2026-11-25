-- Source-qualified native publication benchmark. Not game/client performance.
require('bit')
local artifact=assert(os.getenv('WORKSHOP_SUMMARY_ARTIFACT'),'native-generated root required')
local expected=tonumber(os.getenv('WORKSHOP_SUMMARY_EXPECTED_RECENT')) or 120
local parts=assert(os.getenv('WORKSHOP_SUMMARY_PARTS'),'native-generated parts required')
TwichUI={Workshop={}};GetTimePreciseSec=os.clock
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','SummarySchema','Summary','Bridge'}) do dofile(REPO..'TwichUI_Workshop/'..name..'.lua') end
local W=TwichUI.Workshop;local Q,J,B=W.Summary,W.BridgeCodec,W.Bridge
local function clock()return os.clock()*1000 end
collectgarbage('collect');local before=collectgarbage('count');local start=clock()
local peak=before
local function sample()peak=math.max(peak,collectgarbage('count'))end
local step=Q.Step;Q.Step=function(...)local a,b=step(...);sample();return a,b end
local compiled=assert(loadfile(artifact));local rootCompile=clock()-start;start=clock();compiled();compiled=nil;local rootExecute=clock()-start
local loadMs,worstLoad,loads,historyLoads=0,0,0,0
C_AddOns={LoadAddOn=function(name)
 assert(name:match('^TwichUI_MarketPart[AB]%d%d$')or name:match('^TwichUI_MarketHistoryPart[AB]%d%d$'),'unexpected part name')
 if name:find('History',1,true)then historyLoads=historyLoads+1 end
 local at=clock();assert(loadfile(parts..'/'..name..'/Data.lua'))();local cost=clock()-at
 loadMs=loadMs+cost;worstLoad=math.max(worstLoad,cost);loads=loads+1;return true
end}
start=clock();B.Begin(TwichUIMarketData)
while Q.Pending()do Q.Step(3)end
assert(B.Status().ready);local h=B.Manifest();assert(h.synthetic,'only synthetic benchmark input permitted')
local headerMs=clock()-start;collectgarbage('collect');local headerHeap=collectgarbage('count')-before
local currentStart=clock()
local count=0
local co=coroutine.create(function()assert(B.EachItem(function()count=count+1 end,function()coroutine.yield()end))end)
start=clock();local resumes=0
while coroutine.status(co)~='dead' do
 if Q.Pending()then Q.Step(3)end
 local ok,why=coroutine.resume(co);assert(ok,why);resumes=resumes+1;assert(resumes<3000000,'unbounded enumeration')
end
while Q.Pending()do Q.Step(3)end
local enumerateMs=clock()-start
local item=tonumber(os.getenv('WORKSHOP_SUMMARY_EXPECTED_ITEM')) or 10000
local variants=B.Variants(item)
while not variants and Q.Pending() do Q.Step(3);variants=B.Variants(item) end
local key=variants and variants[1]
assert(key and B.Value(item,key,'recent').value==expected)
local lookupStart=clock();for i=1,1000 do assert(B.Value(item,key,'recent').value==expected)end;local lookups=clock()-lookupStart
local beforeHistory=Q.Status();local currentCPU=clock()-currentStart
local currentLoad,currentPeak=loadMs,peak-before
collectgarbage('collect')
local currentHeap=collectgarbage('count')-before
local historyStart=clock()
if h.contract_version==3 then
 assert(historyLoads==0 and Q.Status().history_bytes==0,'current queries loaded historical payloads')
 local series,why=B.History(item,key,'recent',{days=60})
 while not series and why=='loading' do Q.Step(3);series,why=B.History(item,key,'recent',{days=60})end
 assert(series and series.source=='market_server' and #series.points>0,'native-produced history did not survive split delivery: '..tostring(why)..' / '..tostring(Q.Status().error))
 assert(historyLoads==1 and Q.Status().decoded_parts==1)
end
local historyMs=clock()-historyStart
collectgarbage('collect');local heap=collectgarbage('count')-before;local s=B.Status()
print(J.Encode(setmetatable({synthetic=true,real_game=false,records=h.record_count,enumerated_items=count,declared_parts=#h.partitions,loaded_parts=loads,
 root_compile_us=math.floor(rootCompile*1000),root_execute_us=math.floor(rootExecute*1000),header_validation_ms=math.floor(headerMs),
 header_retained_kib=math.floor(headerHeap),all_parts_compile_execute_ms=math.floor(loadMs),largest_part_load_us=math.floor(worstLoad*1000),
 enumeration_and_validation_ms=math.floor(enumerateMs),largest_validation_callback_us=math.floor(s.largest_slice_ms*1000),
 lookup_1000_us=math.floor(lookups*1000),retained_kib=math.floor(heap),raw_bytes=s.bytes,decoded_rows=s.cache_entries,
 history_loads=historyLoads,current_bytes=s.current_bytes or 0,history_bytes=s.history_bytes or 0,
 current_queries_retained_kib=math.floor(currentHeap),sampled_peak_kib=math.floor(peak-before),
 current_queries_cpu_ms=math.floor(currentCPU),current_queries_load_ms=math.floor(currentLoad),current_sampled_peak_kib=math.floor(currentPeak),
 explicit_history_ms=math.floor(historyMs),raw_bytes_before_history=beforeHistory.bytes,
 history_bytes_before_history=beforeHistory.history_bytes or 0,generation=h.generation_id},J.OBJECT)))
