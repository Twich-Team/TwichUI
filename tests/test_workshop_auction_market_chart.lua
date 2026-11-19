local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
W.UI.Init()
local C=W.AdvancedChart
local function check(v,m) assert(v,m) end
check(C.Axis(100000000000,'min',W.UI.Money)=='10.0M gold','large copper axis units')
check(C.Axis(100000000000,'supply',tostring)=='100000000000','quantities never become currency')
local s={from=1,to=7,points={{day=1,price=100,at=86400,provenance='local'},
 {day=2,price=140,partial=true},{day=6,price=80,at='2026-11-17T00:00:00Z',provenance='external'}},
 groups={{from=3,to=5,average=110,low=90,high=150,n=2,partial=true,provenance='local'}},gaps={{from=3,to=5}}}
local d=C.Prepare(s)
check(#d.points==3 and #d.groups==1,'typed evidence retained')
check(d.low<80 and d.high>150,'axes include extrema and aggregate range')
check(C.Nearest(d.points,1.6)==s.points[2],'nearest observation')
check(not C.Connected(s.points[2],s.points[3],s.gaps),'no gap interpolation')
check(C.Connected(s.points[1],s.points[2],s.gaps),'adjacent days connected')
local g=C.Geometry(d,400,120);local lines=0;for _,v in ipairs(g) do if v.x2 then lines=lines+1 end end
check(lines==1,'only truthful connected segment')
local chart=W.UI.AdvancedMarketChart(c.UIParent,600,176)
chart:Set(s,W.UI.Money);chart:Inspect(1)
check(chart.tip:IsShown(),'inspection shown');check((chart.tip.date:GetText()..chart.tip.value:GetText()..chart.tip.text:GetText()):find('100 copper',1,true),'exact copper')
check(chart.tip.text:GetText():find('Your Auction House scans',1,true),'local source uses an explicit player-facing label')
chart:Inspect(4);check((chart.tip.date:GetText()..chart.tip.value:GetText()..chart.tip.text:GetText()):find('Aggregate mean',1,true),'aggregate is interval')
chart:Inspect(6);check((chart.tip.date:GetText()..chart.tip.value:GetText()..chart.tip.text:GetText()):find('2026-11-17T00:00:00Z',1,true),'external exact timestamp')
chart:Select(2,6);check(chart.window and #chart.data.points==2,'drag interval')
chart:Select();check(not chart.window and #chart.data.points==3,'reset')
-- Drive the actual pointer handlers with scale-correct synthetic cursor coordinates.
local cursor=0
c.GetCursorPosition=function()return cursor,0 end
chart.plot.GetLeft=function()return 100 end
chart.plot.GetEffectiveScale=function()return .75 end
chart.plot.GetWidth=function()return 400 end
chart.plot.GetHeight=function()return 120 end
chart:Set(s,W.UI.Money)
cursor=(100+400/6)*.75
chart.hit:GetScript('OnEnter')(chart.plot)
chart.hit:GetScript('OnMouseDown')(chart.plot,'LeftButton')
cursor=(100+400*5/6)*.75
chart.hit:GetScript('OnUpdate')(chart.plot)
check(chart.selection:IsShown(),'drag preview')
chart.hit:GetScript('OnMouseUp')(chart.plot,'LeftButton')
check(chart.window and math.abs(chart.window[1]-2)<.001 and math.abs(chart.window[2]-6)<.001,'scaled drag hit testing')
local window=chart.window
chart.plot.GetWidth=function()return 450 end
chart:GetScript('OnSizeChanged')(chart)
check(chart.window==window and chart.pw==450,'resize keeps selected interval')
chart.hit:GetScript('OnMouseUp')(chart.plot,'RightButton')
check(not chart.window,'right click resets')
chart.hit:GetScript('OnLeave')(chart.plot)
check(not chart.hit:GetScript('OnUpdate') and not chart.tip:IsShown(),'leave cancels interaction')
local pool=#chart.pool;local strokes=#chart.linePool
for i=1,100 do chart:Set(s,W.UI.Money) end
check(#chart.pool==pool and #chart.linePool==strokes,'repeated redraw pool bounded')
chart:Clear();check(not chart.series and not chart.data and not chart.drawData,'release references')
check(not chart.tip:IsShown() and not chart.hit:GetScript('OnUpdate'),'hidden interaction cleared')
chart:Set({from=1,to=2,points={},groups={},gaps={}},W.UI.Money);check(chart.state=='empty','empty')
chart:Set({from=1,to=2,points={s.points[1]},groups={},gaps={}},W.UI.Money);check(chart.state=='single','single')
chart:Set(nil);check(#chart.pool==pool,'empty source reuses pool');check(not chart.tip:IsShown(),'no stale tooltip')
local dense={from=1,to=10000,points={},groups={},gaps={}}
for i=1,10000 do dense.points[i]={day=i,price=i==5000 and 999999 or i} end
local denseD=C.Prepare(dense);local denseG=C.Geometry(denseD,200,120)
check(#denseG<=200,'pixel bound');check(denseD.high>999999,'significant extrema retained')
local peak=0;for _,v in ipairs(denseG) do peak=math.max(peak,v.y+v.h) end
check(peak>100,'spike visible')
-- Texture stroke path is independent of CreateLine, including scaled frames.
chart.plot.CreateLine=nil
chart:Set(s,W.UI.Money);check(#chart.linePool>0,'stroke pool')
chart:Clear();check(not chart.linePool[1]:IsShown(),'stroke geometry cleared')
print('PASSED: Advanced Market chart preparation, integrity, interaction, fallback and pooling')
-- Offline CPU benchmark; fake regions, not client frame time.
local function bench(fn,n) collectgarbage('collect');local t=os.clock();for i=1,n do fn() end;return (os.clock()-t)*1e6/n end
for _,n in ipairs({2,7,14,30,60,120}) do
 local x={from=1,to=n,points={},groups={},gaps={}}
 for i=1,n do x.points[i]={day=i,price=100000+math.sin(i)*50000,provenance='local'} end
 local old=W.UI.PriceChart(c.UIParent,800,136,{maxDots=60,window=true,gold=true})
 local new=W.UI.AdvancedMarketChart(c.UIParent,800,176)
 old.plot.GetWidth=function()return 682 end;old.plot.GetHeight=function()return 128 end
 new.plot.GetWidth=function()return 682 end;new.plot.GetHeight=function()return 128 end

 local prep=bench(function() C.Prepare(x) end,200)
 local oldCPU=bench(function() old:Set(x,W.UI.Money,30) end,200)
 local newCPU=bench(function() new:Clear();new:Set(x,W.UI.Money) end,200)
 local hover=bench(function() C.Nearest(x.points,n/2) end,10000)
 print(string.format('C1 BENCH n=%d prepare=%.2fus old-redraw=%.2fus new-set=%.2fus hit=%.2fus markers=%d stroke-textures=%d',n,prep,oldCPU,newCPU,hover,#new.pool,#new.linePool))
end
local x={from=1,to=120,points={},groups={},gaps={}}
for i=1,120 do x.points[i]={day=i,price=math.floor(1e7+math.sin(i)*9e6),provenance='local'} end
local oldInit=bench(function()W.UI.PriceChart(c.UIParent,800,136,{maxDots=60,window=true,gold=true})end,30)
local newInit=bench(function()W.UI.AdvancedMarketChart(c.UIParent,800,160)end,30)
chart.plot.GetWidth=function()return 682 end;chart.plot.GetHeight=function()return 112 end
chart:Set(x,W.UI.Money)
local changed=bench(function()chart:ClearHover();chart:Inspect(math.random(1,120))end,1000)
local idle=bench(function()chart:Inspect(60)end,1000)
local resize=bench(function()chart.pw=nil;chart:Render()end,200)
local unchanged=bench(function()chart:Render()end,1000)
chart:Clear();collectgarbage('collect');local memory=collectgarbage('count')
for i=1,200 do chart:Set(x,W.UI.Money);chart:Clear() end
collectgarbage('collect');local retained=collectgarbage('count')-memory
print(string.format('C1 DETAIL old-init=%.2fus new-init=%.2fus changed-hover=%.2fus idle-hover=%.2fus resize=%.2fus unchanged=%.2fus reopen-growth=%.2fKiB pool=%d',oldInit,newInit,changed,idle,resize,unchanged,retained,#chart.pool+#chart.linePool))
