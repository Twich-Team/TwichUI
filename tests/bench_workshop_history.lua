-- Actual native-produced synthetic payload through the production Lua reader.
-- Desktop CPU/heap measurements only; not native Forever acceptance.
require('bit')
local artifact=assert(os.getenv('WORKSHOP_SUMMARY_ARTIFACT'))
local parts=assert(os.getenv('WORKSHOP_SUMMARY_PARTS'))
TwichUI={Workshop={}};GetTimePreciseSec=os.clock
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','SummarySchema','Summary','Bridge'})do dofile(REPO..'TwichUI_Workshop/'..name..'.lua')end
local W=TwichUI.Workshop;local B,Q,J=W.Bridge,W.Summary,W.BridgeCodec
local function clock()return os.clock()*1000 end
collectgarbage('collect');local before=collectgarbage('count')
local started=clock();assert(loadfile(artifact))();local rootMs=clock()-started
local loadMs,loads=0,0
C_AddOns={LoadAddOn=function(name)
 assert(name:match('^TwichUI_MarketPart[AB]%d%d$'))
 local start=clock();assert(loadfile(parts..'/'..name..'/Data.lua'))();loadMs=loadMs+clock()-start;loads=loads+1;return true
end}
started=clock();B.Begin(TwichUIMarketData);while Q.Pending()do Q.Step(3)end
assert(B.Status().ready and B.Manifest().contract_version==2 and B.Manifest().synthetic)
local headerMs=clock()-started
local item=tonumber(os.getenv('WORKSHOP_SUMMARY_EXPECTED_ITEM')) or 10000
started=clock();local variants=B.Variants(item)
while not variants and Q.Pending()do Q.Step(3);variants=B.Variants(item)end
assert(variants and variants[1]);local history=assert(B.History(item,variants[1],'recent',{days=60}))
assert(#history.points==60 and #history.gaps==0 and history.points[1].v==100 and history.points[60].v==120)
local focusMs=clock()-started
local look=clock();for i=1,100 do assert(B.History(item,variants[1],'recent',{days=60}).points[60].v==120)end;local lookupMs=clock()-look
collectgarbage('collect');local s=B.Status()
assert(loads==1 and s.decoded_parts==1)
print(J.Encode(setmetatable({synthetic=true,real_game=false,records=B.Manifest().record_count,history_days=60,
 root_compile_execute_us=math.floor(rootMs*1000),header_validation_us=math.floor(headerMs*1000),
 focused_validation_ms=math.floor(focusMs),focused_parts=loads,compile_execute_us=math.floor(loadMs*1000),
 largest_validation_callback_us=math.floor(s.largest_slice_ms*1000),history_100_us=math.floor(lookupMs*1000),
 retained_kib=math.floor(collectgarbage('count')-before),loaded_raw_bytes=s.bytes,decoded_rows=s.cache_entries},J.OBJECT)))
