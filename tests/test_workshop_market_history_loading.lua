-- Production facts/pricing/detail/chart with deterministic completions, plus a
-- real synthetic Contract 3 decode. No client animation/frame timing claim.
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
local P,B,F,J=W.Pricing,W.Bridge,W.Facts,W.BridgeCodec
local events,counts={},{}
c.GetTimePreciseSec=os.clock
c.C_Timer.After=function(_,fn)events[#events+1]=fn end
c.C_Item.GetItemInfo=function(id)return 'Synthetic '..id,'item:'..id,1,1,1,'Trade Goods','',1,'',1,0 end
local function tick()local batch=events;events={};for _,fn in ipairs(batch)do fn()end end
local function drain()
    for _=1,1000 do if #events==0 then return end;tick()end
    error('history refresh did not quiesce')
end
-- Model only the native template's documented show/hide animation ownership.
local create=c.CreateFrame
c.CreateFrame=function(kind,name,parent,template)
    local frame=create(kind,name,parent,template)
    if template=='SpinnerTemplate' then
        frame.Ring=frame:CreateTexture();frame.Sparks=frame:CreateTexture()
        frame:SetScript('OnShow',function()frame.animating=true end)
        frame:SetScript('OnHide',function()frame.animating=false end)
    end
    return frame
end
local rows={};for b=1,8 do counts[b]=1;rows[b]={id=b,name='Craft '..b,prof=171,profName='Alchemy',filled=true,
    outItem=64+b,outMin=1,outMax=1,mats={{item=65,qty=1}}}end
local fixture=dofile(TESTS..'market_cold_fixture.lua')(c,2,counts);fixture.Split()
c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts={}
for b,raw in pairs(fixture.parts)do c.TwichUIMarketParts['A'..('%02d'):format(b)]=raw end
for b,raw in pairs(fixture.history_parts)do c.TwichUIMarketHistoryParts['A'..('%02d'):format(b)]=raw end
B.Begin(fixture.root);drain()
for _,r in ipairs(rows)do P.Price(r.outItem)end;drain()
-- A genuine saved local scan, including local history for item 67 only.
c.GetRealmName=function()return 'Realm' end
assert(W.Prices.Commit('Realm|Horde',{realm='Realm',side='Horde',at=c.time()-10,complete=true,
    items={[67]='777,1,1,1,0'},n=1,read=1,used=1,partial=0}))
F.CacheClear()
local history=B.History
local answers,calls={},0
B.History=function(item,...)
    calls=calls+1
    local a=answers[item];if not a then return nil,'loading' end
    return a.series,a.why
end
W.Session.AllRecipes=function()return rows end
W.Window.SetMode('opps');W.Window.Show();drain()
local detail=W.Window.Opps().detail;local chart=detail.chart
-- The generic fake's .shown is also used by the chart's legacy point count.
chart.IsShown=function()return true end
local function state(expected,hasSeries)
    assert(chart.presentationState==expected,'expected '..expected..', got '..tostring(chart.presentationState))
    assert((chart.series~=nil)==hasSeries,'unexpected observations')
    assert(chart.spinner:IsShown()==(expected=='loading'),'spinner ownership')
    assert(chart.spinner.animating==(expected=='loading'),'animation ownership')
    if expected=='loading' then assert(chart.msg:GetText()=='','loading retained an empty message')end
end
local function select(item)
    for _,row in ipairs(W.Window.Lists().opps.rows)do
        if row.rec and row.rec.outItem==item then row:GetScript('OnClick')(row);drain();assert(detail.item==item);return end
    end
    error('recipe not visible: '..item)
end
local function complete(item,a)
    answers[item]=a;P.Decoded(item%64+64);drain()
end
local day=math.floor(c.time()/86400)
local function server(item)
    return {generation=B.Status().generation,to=day,from=day-1,gaps={},basis='server observations',
        points={{from=day,v=item*10,at='2026-11-18T12:00:00Z'}}}
end

-- The real RenderDetail must forward both return values, not show a terminal
-- no-history explanation while a partition is pending.
select(65);state('loading',false)
assert(chart.statusText:GetText()=='Loading price history…')
complete(65,{series=server(65)});state('available',true)
assert(chart.series.points[1].price==650 and chart.series.metric=='recent')
assert(chart.series.points[1].provenance=='Market server' and chart.series.points[1].at=='2026-11-18T12:00:00Z')
local before=calls;W.Window.Render();drain();assert(calls==before,'unchanged detail re-requested history')

select(66);state('loading',false)
complete(66,{why='not_observed'});state('empty',false)
assert(chart.msg:GetText():find('No price history yet',1,true))
select(68);state('loading',false)
complete(68,{why='invalid'});state('unavailable',false)
assert(chart.msg:GetText():find('unavailable',1,true))

-- A local fallback carries the SERVER request reason even if local history is
-- absent. With valid local data, keep the interactive minimum-history chart.
select(67);state('loading',true)
assert(chart.series.metric=='min' and chart.series.points[1].price==777)
assert(chart.statusText:GetText():find('Showing local history',1,true))
chart:Select(day-.5,day);local window=chart.window;local data=chart.data
W.Window.Render();drain();assert(chart.window==window and chart.data==data,'pending refresh reset local zoom')
chart:Inspect(day);local hovered=chart.hovered
complete(67,{why='invalid'});state('available',true)
assert(chart.window==window and chart.data==data,'terminal fallback discarded local interaction')
assert(chart.hovered==hovered and chart.tip:IsShown(),'state-only refresh cleared local inspection')
assert(chart.statusText:GetText():find('unavailable',1,true))

-- Switch while pending; an older completion cannot publish its observations or
-- dismiss the new selection's loading state. No per-frame retry is installed.
select(69);state('loading',false)
select(70);state('loading',false)
before=calls;complete(69,{series=server(69)})
state('loading',false);assert(detail.item==70 and calls==before,'stale completion redrew another selection')
assert(not chart:GetScript('OnUpdate') and not chart.hit:GetScript('OnUpdate'))
complete(70,{series=server(70)});state('available',true)
assert(chart.series.points[1].price==700,'previous recipe observations leaked')

-- Chart hide is synchronous; reopening uses the valid pricing chart cache.
chart:GetScript('OnHide')(chart)
assert(not chart.spinner.animating and not chart.series and chart.needsRefresh)
before=calls;W.Window.Render();drain();state('available',true)
assert(calls==before,'reopening bypassed the valid chart cache')
select(71);state('loading',false)
W.Window.Hide()
-- Generic fake frames do not dispatch inherited child OnHide events.
chart:GetScript('OnHide')(chart);assert(not chart.spinner.animating and chart.msg:GetText()=='')
before=calls;complete(71,{series={generation=B.Status().generation,to=day,gaps={},points={}}})
assert(calls==before and not chart.series and not chart.spinner.animating,'hidden completion restarted presentation')
W.Window.Show();drain();select(71);state('empty',false)

-- Exercise a real reader cancellation/generation replacement with a queued
-- partition. Cancelled callbacks cannot finish or overwrite the new generation.
W.Window.Hide();B.History=history;drain()
local facts=F.Of(72);local series,why=F.Chart(facts)
assert(not series and why=='loading' and W.Summary.Pending())
B.Cancel();assert(not W.Summary.Pending())
assert(not chart.spinner.animating)
fixture.header.source_watermark='903';fixture.Seal();B.Begin(fixture.root);drain()
series,why=F.Chart(facts)
assert(not series and why=='generation_changed','old facts reused history after generation replacement')
P.Price(72);drain();facts=F.Of(72)
local perf={};c.TwichUI.Perf.on=true
c.TwichUI.Perf.Count=function(id,n)perf[id]=(perf[id]or 0)+(n or 1)end
series,why=F.Chart(facts);assert(not series and why=='loading');drain()
series=assert(F.Chart(facts));assert(series.external and #series.points>0)
local decodes=perf['workshop.summary.decodeStarts'];assert(decodes==1,'expected one real history decode')
for _=1,20 do assert(F.Chart(facts)==series)end
assert(perf['workshop.summary.decodeStarts']==decodes and not W.Summary.Pending(),'cache hit decoded or queued history')
local other=J.Copy(facts);other.referenceVariant=P.BaseKey(999)
local missing,reason=F.Chart(other);assert(not missing and reason=='not_observed','variant inherited a cached chart')
c.TwichUI.Perf.on=false

-- A completed server response with zero supported observations is truly empty.
local empty={points={},groups={},gaps={},today=day,external=true}
chart:Set(W.AdvancedChart.FromObserved(empty),W.UI.Money,'completed-empty')
state('empty',false)
-- Pending current-price facts must not turn a local no-data result into empty.
local pending={item=1,nomarket=true,referenceWhy='loading'}
series,why=F.Chart(pending);assert(not series and why=='loading')
print('PASSED: history pending/loaded/empty/error, local fallback, switching, hide/reopen, cancellation, generations and decode cache')
