-- Actual producer fixture + production reader/pricing. All payloads fabricated.
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
local J,B,Q,P=W.BridgeCodec,W.Bridge,W.Summary,W.Pricing
local file=assert(io.open(TESTS..'fixtures/workshop_summary_v3/synthetic.json'))
local fixture=J.Parse(file:read('*a'));file:close()
file=assert(io.open(TESTS..'fixtures/workshop_summary_v3/manifest.schema.json'))
assert(J.Encode(J.Parse(file:read('*a')))==J.Encode(W.SummaryCurrentSchema));file:close()
local h=fixture.manifest;local key=P.BaseKey(2589)
h.synthetic=false;for _,o in ipairs(h.observations)do o.synthetic=false end
local _,at=W.BridgeValidate.Time(h.generated_at);local now=at+60
c.time=function()return now end;c.UnitFactionGroup=function()return 'Horde'end
local events,loads,wall={}, {},0
c.GetTimePreciseSec=function()return wall end
c.C_Timer.After=function(_,fn)events[#events+1]=fn end
W.UI.Redraw=function()end
c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts=nil
local function loader(name)
    loads[#loads+1]=name
    local bank,bucket=name:match('Part([AB])(%d%d)$');assert(bank and bucket)
    local history=name:find('History',1,true)~=nil
    local raw=fixture.parts[tostring(tonumber(bucket)+(history and 64 or 0))]
    if not raw then return false end
    if history then
        c.TwichUIMarketHistoryParts=c.TwichUIMarketHistoryParts or {};c.TwichUIMarketHistoryParts[bank..bucket]=raw
    else c.TwichUIMarketParts[bank..bucket]=raw end
    return true
end
c.C_AddOns.LoadAddOn=loader
local function drain()
    for _=1,10000 do
        if #events==0 then assert(not Q.Pending());return end
        local batch=events;events={};wall=wall+1/60
        for _,fn in ipairs(batch)do fn()end
    end
    error('unbounded split queue')
end
local function tick()
    local batch=events;events={};wall=wall+1/60;for _,fn in ipairs(batch)do fn()end
end
local function seal()
    local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
end
local function begin(bank)
    seal()
    B.Begin({summary_version=1,bank=bank or 'A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({
        schema_version=1,generation_id=h.generation_id,desktop_build='split-test',completed_at=h.generated_at},J.OBJECT))})
    drain();assert(B.Status().ready)
end
local captured,observed={},{}
c.TwichUI.Perf.on=true;c.TwichUI.Perf.captureID=1
c.TwichUI.Perf.Count=function(id,n)captured[id]=(captured[id]or 0)+(n or 1)end
c.TwichUI.Perf.Observe=function(id,ms)observed[id]=observed[id]or {};table.insert(observed[id],ms)end
begin();assert(#loads==0,'header eagerly loaded projections')
for _=1,30 do P.Price(2589);P.Reference(2589)end
assert(P.PendingCount()==1)
drain();assert(P.Price(2589).price==120 and P.PendingCount()==0)
assert(#loads==1 and loads[1]=='TwichUI_MarketPartA29')
assert(B.Status().history_bytes==0 and B.Status().history_loaded_parts==0)
assert(c.TwichUIMarketHistoryParts==nil,'cold current pricing loaded raw history')
assert(captured['workshop.pricing.readerCalls']==2 and captured['workshop.pricing.baseKeys']==1)
assert(#observed['workshop.priceWait']==1 and observed['workshop.priceWait'][1]>0)
assert(observed['workshop.partitionQueueWait'] and observed['workshop.currentValidationWait'])
local ref=P.Reference(2589);assert(ref.market==100 and ref.historical==nil and ref.supply==10)
assert(B.Record(2589,key,{current=true}).daily==nil and B.Value(2589,key,'recent').value==120)
assert(not P.Price(2589,{variant=true}),'modified native variant inherited base pricing')
local variants=B.Variants(2589);assert(#variants==1 and variants[1]==key and B.Value(2589,key,'recent').value==120)
-- History is independent and keeps the exact original observations and copies.
assert(not B.History(2589,key,'recent',{days=14}));drain()
local series=assert(B.History(2589,key,'recent',{days=14}))
assert(series.points[1].v==100 and series.points[2].v==120 and #series.gaps==12)
assert(#loads==2 and loads[2]=='TwichUI_MarketHistoryPartA29')
assert(B.Status().decoded_parts==1 and B.Status().history_loaded_parts==1)
assert(observed['workshop.historyValidationWait'])
local record=B.Record(2589,key);record.daily[1][2]='999'
assert(B.History(2589,key,'recent',{days=14}).points[1].v==100)
local generation=B.Status().generation
-- Independently valid, rehashed rich records must still match current bytes.
local rich=J.Parse(fixture.parts['93']);rich[1][4]='999'
local bad=J.Encode(rich);fixture.parts['93']=bad
h.history_partitions[1].sha256=J.SHA(bad);h.history_partitions[1].bytes=#bad
begin('B');assert(P.Price(2589)==nil);drain();assert(P.Price(2589).price==120)
B.History(2589,key);drain()
assert(B.Status().generation==generation and P.PendingCount()==0,'mismatched pair escaped whole-generation rollback')
P.Price(2589);drain()
assert(P.Price(2589).price==120 and B.Status().reload_required)
-- New-capture waits never import timings from earlier captures.
c.TwichUI.Perf.captureID=2;P.BeginView()
local rows={};for i=1,12 do rows[i]={rec={id=i,outItem=2589,mats={}},est={state='ok'}}end
local list={scroll={GetVerticalScroll=function()return 0 end,GetHeight=function()return 240 end},rowH=20,minH=240,data=rows}
P.ObserveView(rows,list)
assert(observed['workshop.tenVisiblePrices'] and observed['workshop.visibleSettled'] and observed['workshop.opportunitiesSettled'])
-- First generation with missing current payload refuses it and leaves no retry.
Q.Deactivate();c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts={}
c.C_AddOns.LoadAddOn=function()return false end
begin('A');P.Price(2589);drain()
assert(not B.Status().ready and P.PendingCount()==0,'missing split payload stranded pricing')
-- Many exact variants of one item, including the base, search both array ends.
Q.Deactivate();c.C_AddOns.LoadAddOn=loader
local generated=dofile(TESTS..'market_cold_fixture.lua')(c,2,{[0]=128,[1]=1,[2]=1},true);generated.Split()
for b,raw in pairs(generated.parts)do c.TwichUIMarketParts['A'..('%02d'):format(b)]=raw end
for b,raw in pairs(generated.history_parts)do c.TwichUIMarketHistoryParts['A'..('%02d'):format(b)]=raw end
B.Begin(generated.root);drain()
B.Variants(64,100);drain()
local vv,cut=B.Variants(64,100);assert(#vv==100 and cut)
for _,variant in ipairs({vv[1],vv[#vv]})do
    local value=assert(B.Value(64,variant,'recent'));assert(value.value>=121 and value.value<=248)
end
P.Price(64);drain();assert(P.Price(64).price==121 and P.PendingCount()==0)
-- A long, already-running chart never blocks a new current-price request.
generated.header.source_watermark='903';generated.Seal();B.Begin(generated.root);drain()
local histories=captured['workshop.summary.historyDecodes']or 0
B.History(64,P.BaseKey(64));tick()
P.Price(65);assert(Q.Status().parked_history,'current request did not preempt the history job')
local price
for _=1,100 do price=P.Price(65);if price then break end;tick()end
assert(price and price.price==121 and Q.Status().history_checked_parts==0,'current waited for full history')
drain();assert((captured['workshop.summary.historyDecodes']or 0)==histories+1,'preemption restarted history')
-- Cancel and replace release the one parked decoder and stale scheduled resumes.
generated.header.source_watermark='904';generated.Seal();B.Begin(generated.root);drain()
B.History(64,P.BaseKey(64));tick();P.Price(66);assert(Q.Status().parked_history)
Q.Cancel();drain();assert(not Q.Status().parked_history and P.PendingCount()==0)
generated.header.source_watermark='905';generated.Seal();B.Begin(generated.root);drain()
B.History(64,P.BaseKey(64));tick();P.Price(66);assert(Q.Status().parked_history)
generated.header.source_watermark='906';generated.Seal();B.Begin(generated.root);drain()
assert(not Q.Status().parked_history and P.PendingCount()==0 and B.Status().generation==generated.header.generation_id)
print('PASSED split current/history laziness, exact prices/variants, pair integrity, rollback, latency and missing-data refusal')
