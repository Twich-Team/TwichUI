-- Source-qualified native publication benchmark. Not game/client performance.
require('bit')
local artifact=assert(os.getenv('WORKSHOP_SUMMARY_ARTIFACT'),'native-generated root required')
local parts=assert(os.getenv('WORKSHOP_SUMMARY_PARTS'),'native-generated parts required')
TwichUI={Workshop={}};GetTimePreciseSec=os.clock
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','SummarySchema','Summary','Bridge'}) do dofile(REPO..'TwichUI_Workshop/'..name..'.lua') end
local W=TwichUI.Workshop;local Q,J,B=W.Summary,W.BridgeCodec,W.Bridge
local function clock()return os.clock()*1000 end
collectgarbage('collect');local before=collectgarbage('count');local start=clock()
local compiled=assert(loadfile(artifact));local rootCompile=clock()-start;start=clock();compiled();compiled=nil;local rootExecute=clock()-start
local loadMs,worstLoad,loads=0,0,0
C_AddOns={LoadAddOn=function(name)
 assert(name:match('^TwichUI_MarketPart[AB]%d%d$'),'unexpected part name')
 local at=clock();assert(loadfile(parts..'/'..name..'/Data.lua'))();local cost=clock()-at
 loadMs=loadMs+cost;worstLoad=math.max(worstLoad,cost);loads=loads+1;return true
end}
start=clock();B.Begin(TwichUIMarketData)
while Q.Pending()do Q.Step(3)end
assert(B.Status().ready);local h=B.Manifest();assert(h.synthetic,'only synthetic benchmark input permitted')
local headerMs=clock()-start;collectgarbage('collect');local headerHeap=collectgarbage('count')-before
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
assert(key and B.Value(item,key,'recent').value==120)
local lookupStart=clock();for i=1,1000 do assert(B.Value(item,key,'recent').value==120)end;local lookups=clock()-lookupStart
collectgarbage('collect');local heap=collectgarbage('count')-before;local s=B.Status()
print(J.Encode(setmetatable({synthetic=true,real_game=false,records=h.record_count,enumerated_items=count,declared_parts=#h.partitions,loaded_parts=loads,
 root_compile_us=math.floor(rootCompile*1000),root_execute_us=math.floor(rootExecute*1000),header_validation_ms=math.floor(headerMs),
 header_retained_kib=math.floor(headerHeap),all_parts_compile_execute_ms=math.floor(loadMs),largest_part_load_us=math.floor(worstLoad*1000),
 enumeration_and_validation_ms=math.floor(enumerateMs),largest_validation_callback_us=math.floor(s.largest_slice_ms*1000),
 lookup_1000_us=math.floor(lookups*1000),retained_kib=math.floor(heap),raw_bytes=s.bytes,decoded_rows=s.cache_entries,generation=h.generation_id},J.OBJECT)))
