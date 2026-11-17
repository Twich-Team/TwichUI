local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop;W.UI.Init()
local original=c.CreateFrame
local counts={frames=0,textures=0,fonts=0,lines=0}
c.CreateFrame=function(...)
 counts.frames=counts.frames+1;local f=original(...)
 local tex,font=f.CreateTexture,f.CreateFontString
 f.CreateTexture=function(...)counts.textures=counts.textures+1;return tex(...)end
 f.CreateFontString=function(...)counts.fonts=counts.fonts+1;return font(...)end
 f.CreateLine=function(parent)counts.lines=counts.lines+1;local t=tex(parent);t.SetStartPoint=function()end;t.SetEndPoint=function()end;t.SetThickness=function()end;return t end
 return f
end
local function report(name)print(name,counts.frames,counts.textures,counts.fonts,counts.lines)end
local old=W.UI.PriceChart(c.UIParent,800,136,{maxDots=60,window=true,gold=true});report('old init')
counts={frames=0,textures=0,fonts=0,lines=0}
local chart=W.UI.AdvancedMarketChart(c.UIParent,800,160);report('new init')
chart.plot.GetWidth=function()return 682 end;chart.plot.GetHeight=function()return 112 end
local s={from=1,to=120,points={},groups={},gaps={}}
for i=1,120 do s.points[i]={day=i,price=math.floor(1e7+math.sin(i)*9e6)} end
chart:Set(s,W.UI.Money);report('new 120')
for i=1,200 do chart:Set(s,W.UI.Money);chart:Clear()end;report('new repeated')
