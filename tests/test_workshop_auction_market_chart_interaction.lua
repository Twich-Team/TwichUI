-- Real chart handlers plus the existing Press eligibility dispatcher. Native input remains a client gate.
local c,_,Press=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop;W.UI.Init()
c.UIParent.GetParent=function()return nil end
c.UIParent.IsShown=function()return true end
local C=W.AdvancedChart
local chart=W.UI.AdvancedMarketChart(c.UIParent,800,160)
-- The generic fake uses .shown as visibility; the chart's legacy .shown is a count.
chart.IsShown=function()return true end
local px,py,down=0,0,false
c.GetCursorPosition=function()return px,py end
c.IsMouseButtonDown=function()return down end
chart.plot.GetLeft=function()return 100 end
chart.plot.GetEffectiveScale=function()return .8 end
chart.plot.GetWidth=function()return 600 end
chart.plot.GetHeight=function()return 112 end
local function move(day,y)px=(100+(day-1)/6*600)*.8;py=y or 0 end
local function fire(event,...)
 for _,frame in ipairs(c.testFrames) do
  if frame.events and frame.events[event] then local fn=frame:GetScript('OnEvent');if fn then fn(frame,event,...) end end
 end
end
local s={from=1,to=7,metric='min',points={{day=1,price=100},{day=2,price=500},{day=6,price=50},{day=7,price=900}},groups={},gaps={{from=3,to=5,why='observed_absent'}}}
local function set()chart:Set(s,W.UI.Money,'item:source:metric')end
local function enter(day)move(day,9999);local result=Press.Hover(chart.hit);assert(result.invoked,result.text) end
local function press(button,phase)assert(Press.Click(chart.hit,{button=button,script=phase}).invoked) end
local function start(day)enter(day);down=true;press('LeftButton','OnMouseDown')end
local function leave()chart.hit:GetScript('OnLeave')(chart.hit)end

set();assert(chart.hit:IsMouseEnabled() and not chart.tip:IsMouseEnabled())

enter(1.5);assert(chart.tip:IsShown(),'off-line hover activates complete plot')
local update=chart.hit:GetScript('OnUpdate');local tip=chart.tip
for i=1,50 do move(1.5+i/1000);update() end
assert(chart.tip==tip and tip:IsShown(),'no tooltip rebuild or flicker')
local copy=W.BridgeCodec.Copy(s)
chart:Set(copy,W.UI.Money,'item:source:metric')
assert(chart.hit:GetScript('OnUpdate')==update and tip:IsShown(),'fresh equivalent projection preserves hover')
local shifted=W.BridgeCodec.Copy(s);shifted.to=7.001
start(2);chart:Set(shifted,W.UI.Money,'item:source:metric')
assert(chart.drag and chart.hit:GetScript('OnUpdate')==update,'moving recent window does not cancel owned input')
chart:ClearHover();set();enter(1.5);update=chart.hit:GetScript('OnUpdate')
move(4);update();assert(chart.hovered==nil and not chart.marker:IsShown(),'gap never snaps to distant sample')
assert(chart.tip.value:GetText():find('No supported value') and chart.tip.text:GetText():find('Observed absent'),'gap coverage exposed')
local gapDate=chart.tip.date:GetText();move(5.1);update();assert(chart.tip.date:GetText()~=gapDate,'gap date follows UTC day changes')
move(6);update();assert(chart.hovered.day==6 and chart.marker:IsShown(),'inspection resumes after gap')
start(2);
move(6);update();assert(chart.selection:IsShown());leave()
assert(chart.drag and chart.hit.events.GLOBAL_MOUSE_UP and chart.hit:GetScript('OnUpdate'),'leaving retains owned drag')
move(8);down=false;fire('GLOBAL_MOUSE_UP','LeftButton')
assert(chart.window[1]==2 and chart.window[2]==7,'outside release clamps and commits')
assert(not chart.drag and not chart.hit.events.GLOBAL_MOUSE_UP and not chart.hit:GetScript('OnUpdate'),'outside release cleans monitor')
press('RightButton','OnMouseUp');assert(not chart.window)
start(6);move(2);down=false;fire('GLOBAL_MOUSE_UP','LeftButton')
assert(chart.window[1]==2 and chart.window[2]==6,'reverse selection')
-- Tiny drag does not reset an existing interval.
local window=chart.window;start(3);px=px+2;down=false;fire('GLOBAL_MOUSE_UP','LeftButton');assert(chart.window==window)
start(3);chart:Set(copy,W.UI.Money,'another-item');assert(not chart.drag and not chart.hit.events.GLOBAL_MOUSE_UP,'item replacement cancels capture')
start(2);chart:GetScript('OnHide')(chart);assert(not chart.series and not chart.drag and not chart.hit:GetScript('OnUpdate'),'hide cancels all input')
set();start(2);leave();move(5);down=false;chart.hit:GetScript('OnUpdate')();assert(not chart.drag,'button-state fallback releases without event')
set();enter(1.5)
-- A replacement while the cursor remains physically over the hit plane reacquires motion.
chart.hit.IsMouseOver=function()return true end
chart:Set(copy,W.UI.Money,'new-source');assert(chart.hit:GetScript('OnUpdate'),'stationary pointer resumes after replacement')
chart.hit.IsMouseOver=function()return false end
start(2);leave();press('RightButton','OnMouseUp');assert(not chart.drag and not chart.hit:GetScript('OnUpdate'),'reset outside cancels monitor')
chart:Clear()
-- Native endpoint ownership and bounded layered pool; missing or rejected APIs fall back.
local allocated=0
chart.plot.CreateLine=function(parent)
 allocated=allocated+1;local line=parent:CreateTexture()
 line.SetThickness=function(self,n)self.thickness=n end
 line.SetStartPoint=function(self,point,relative,x,y)assert(relative.kind=='Texture' and x==0 and y==0);self.a=relative end
 line.SetEndPoint=function(self,point,relative,x,y)assert(relative.kind=='Texture' and x==0 and y==0);self.b=relative end
 return line
end
chart:SetStrokeMode('native');set();assert(chart.backend=='native' and #chart.nativePool==4,'two layers per truthful segment')
local peak=allocated
for i=1,100 do chart.drawData=nil;chart:Render() end
assert(allocated==peak,'native pool bounded')
for _,line in ipairs(chart.nativePool) do assert(line.a and line.b) end
chart:SetStrokeMode('raster');assert(chart.backend=='raster')
chart.plot.CreateLine=function()error('unsupported API')end
chart.nativePool={};chart:SetStrokeMode('native');assert(chart.backend=='raster' and #chart.linePool>0,'API failure preserves fallback')
chart:Clear();assert(not chart.data and next(chart.anchors)==nil,'no retained anchor references')
print('PASSED: chart hit plane, refresh, gaps, capture routing, reverse/tiny drag, hide, source replacement and native fallback')
