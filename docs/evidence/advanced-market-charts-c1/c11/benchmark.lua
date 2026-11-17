-- Run from tests with the standard ROOT/REPO/TESTS globals. Baseline is an exact git blob.
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop;W.UI.Init()
local function Load(path)local chunk=assert(loadfile(path));setfenv(chunk,c);chunk() end
Load(assert(BASELINE,'pass BASELINE pointing to the exact e4e1f08 git blob'));local before=W.UI.AdvancedMarketChart
Load(REPO..'TwichUI_Workshop/auction/AdvancedChart.lua');local after=W.UI.AdvancedMarketChart
local original=c.CreateFrame;local counts
local function heap(fn,n)
 collectgarbage('collect');collectgarbage('stop');local start=collectgarbage('count')
 for i=1,n do fn(i)end
 local delta=(collectgarbage('count')-start)/n;collectgarbage('restart');collectgarbage('collect');return delta
end
c.CreateFrame=function(...)
 counts.frames=counts.frames+1;local f=original(...);local tex,font=f.CreateTexture,f.CreateFontString
 f.CreateTexture=function(...)counts.textures=counts.textures+1;return tex(...)end
 f.CreateFontString=function(...)counts.fonts=counts.fonts+1;return font(...)end
 f.CreateLine=function(parent)
  counts.lines=counts.lines+1;local p=tex(parent)
  p.SetThickness=function()end;p.SetStartPoint=function(self,_,r)self.a=r end;p.SetEndPoint=function(self,_,r)self.b=r end
  return p
 end
 return f
end
local s={from=1,to=120,points={},groups={},gaps={}}
for i=1,120 do s.points[i]={day=i,price=math.floor(1e7+math.sin(i)*9e6),provenance='synthetic'}end
local cursor=100;local down=true
c.GetCursorPosition=function()return cursor,0 end;c.IsMouseButtonDown=function()return down end
local function bench(fn,n)collectgarbage('collect');local t=os.clock();for i=1,n do fn(i)end;return (os.clock()-t)*1e6/n end
for _,mode in ipairs({'C1','C1.1-native','C1.1-raster'}) do
 counts={frames=0,textures=0,fonts=0,lines=0}
 local ctor=mode=='C1' and before or after
 local warm=ctor(c.UIParent,800,160);warm:Clear()
 local init=bench(function()ctor(c.UIParent,800,160)end,30)
 counts={frames=0,textures=0,fonts=0,lines=0}
 local chart=ctor(c.UIParent,800,160)
 chart.plot.GetWidth=function()return 682 end;chart.plot.GetHeight=function()return 112 end
 chart.plot.GetLeft=function()return 100 end;chart.plot.GetEffectiveScale=function()return 1 end
 if chart.hit then chart.hit.IsMouseOver=function()return false end end
 if mode=='C1.1-raster' then chart:SetStrokeMode('raster')end
 print(mode..' init '..string.format('%.2fus',init)..' objects '..counts.frames..'/'..counts.textures..'/'..counts.fonts..'/'..counts.lines)
 chart:Set(s,W.UI.Money)
 local full=bench(function(i)chart:Set(s,W.UI.Money,i)end,200)
 local refresh=bench(function()chart:Set(s,W.UI.Money,200)end,500)
 local prepare=bench(function()W.AdvancedChart.Prepare(s)end,500)
 local hover=bench(function(i)chart:Inspect(1+(i%120))end,2000)
 chart:Inspect(60);local idle=bench(function()chart:Inspect(60)end,2000)
 local hit=chart.hit or chart.plot
 cursor=240;hit:GetScript('OnEnter')(hit);hit:GetScript('OnMouseDown')(hit,'LeftButton')
 local update=hit:GetScript('OnUpdate');local drag=bench(function(i)cursor=250+i%400;update()end,2000)
 chart:ClearHover()
 local interval=bench(function()chart:Select(20,100);chart:Select()end,100)
 local resize=bench(function(i)chart.plot.GetWidth=function()return 680+i%3 end;chart:Render()end,100)
 local scale=bench(function()chart:Render()end,1000)
 local heapFull=heap(function(i)chart:Set(s,W.UI.Money,1000+i)end,20)
 chart:Inspect(60);local heapIdle=heap(function()chart:Inspect(60)end,1000)
 print(string.format('%s mock-heap-per-full=%.3fKiB mock-heap-per-idle=%.3fKiB',mode,heapFull,heapIdle))
 chart:Clear();collectgarbage('collect');local mem=collectgarbage('count')
 local peak={};for k,v in pairs(counts)do peak[k]=v end
 for i=1,200 do chart:Set(s,W.UI.Money,i);chart:Clear()end
 collectgarbage('collect');local retained=collectgarbage('count')-mem
 print(string.format('%s prep=%.2f full=%.2f refresh=%.2f hover=%.2f idle=%.2f drag=%.2f select-reset=%.2f resize=%.2f unchanged-scale=%.2f retained=%.3fKiB',mode,prepare,full,refresh,hover,idle,drag,interval,resize,scale,retained))
 print(mode..' peak '..counts.frames..'/'..counts.textures..'/'..counts.fonts..'/'..counts.lines..' pool='..(#chart.pool+#chart.linePool+#(chart.nativePool or {})))
 assert(counts.frames==peak.frames and counts.textures==peak.textures and counts.lines==peak.lines,'pool grew after warmup')
end
