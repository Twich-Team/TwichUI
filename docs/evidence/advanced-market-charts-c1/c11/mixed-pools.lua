local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop;W.UI.Init()
local chart=W.UI.AdvancedMarketChart(c.UIParent,800,160)
chart.plot.CreateLine=function(parent)local p=parent:CreateTexture();p.SetThickness=function()end;p.SetStartPoint=function()end;p.SetEndPoint=function()end;return p end
chart.plot.GetWidth=function()return 682 end;chart.plot.GetHeight=function()return 112 end
local s={from=1,to=120,points={},groups={},gaps={}}
for i=1,120 do s.points[i]={day=i,price=math.floor(1e7+math.sin(i)*9e6)}end
chart:Set(s,W.UI.Money);local native=#chart.pool+#chart.nativePool
chart:SetStrokeMode('raster');chart:SetStrokeMode('native')
local peak=#chart.pool+#chart.nativePool+#chart.linePool
collectgarbage('collect');local memory=collectgarbage('count')
for i=1,200 do chart:SetStrokeMode('raster');chart:SetStrokeMode('native') end
collectgarbage('collect')
assert(#chart.pool+#chart.nativePool+#chart.linePool==peak)
print(string.format('native=%d mixed-pool=%d switches=400 retained-growth=%.3fKiB',native,peak,collectgarbage('count')-memory))
