-- Synthetic offline CPU measurements; not actual client/render/frame budgets.
-- Run with the normal single-test Lua command from docs/testing.md.
local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
local A,D=W.AuctionUI,W.AuctionMarketData
local native=0
c.C_AuctionHouse=setmetatable({},{__index=function() return function() native=native+1;error("native call") end end})
local function Pump()
    for _=1,2000 do FlushTimers();local p=A.Page("market");if not p or not p.job then return end end
    error("unbounded Market catalog")
end
local function Sample(label,count,fn)
    local total,maximum=0,0
    for i=1,count do local at=os.clock();fn(i);local dt=os.clock()-at;total=total+dt;maximum=math.max(maximum,dt) end
    print(("%s: n=%d total=%.3fms max=%.3fms"):format(label,count,total*1000,maximum*1000))
end
Sample("first Market open and sparse discovery",1,function() A.Show();A.OpenMarket(10,{market=m.key});Pump() end)
local p=A.Page("market")
Sample("selected-item projection",30,function(i) A.Market.Select(i%2==0 and 10 or 11) end)
Sample("chart window change",60,function(i) A.Market.Range(D.RANGES[i%#D.RANGES+1][1]) end)
local large={f=2,key=m.key,realm="Realm",side="Alliance",at=now,scope="full",complete=true,items={},n=20000}
for id=1,20000 do large.items[id]=m.items[10] end
c.TwichUIWorkshopDB.markets[m.key]=large
local job=D.Catalog({market=large});local slices,longest,total=0,0,os.clock()
repeat
    local at=os.clock();local done,err=job:Step();assert(not err,err)
    longest=math.max(longest,os.clock()-at);slices=slices+1;assert(slices<10000)
    if done then break end
until false
print(("20k catalog: items=%d slices=%d total=%.3fms maxSlice=%.3fms"):format(#job.rows,slices,(os.clock()-total)*1000,longest*1000))
Sample("20k page discovery",1,function() A.Market.Search("");Pump() end)
A.Go("shopping");A.Go("market");Pump() -- warm both lazily built pages
local frames=#c.testFrames
Sample("20k Market/Shopping switch pair",10,function() A.Go("shopping");A.Go("market");Pump() end)
assert(#c.testFrames==frames,"repeated switching grew frame pool")
A.Hide();Pump()
local s=A.Snapshot();local cache=D.Stats()
assert(s.jobs==0 and s.events==0 and cache.cache==0 and p.rows==nil and p.index==nil and p.known==nil and p.projection==nil)
assert(native==0,"Market issued an AH operation")
print(("hidden cleanup: jobs=%d events=%d selectedCache=%d pooledMarketRows=%d; nativeCalls=%d"):format(s.jobs,s.events,cache.cache,#p.list.rows,native))
print("PASSED: AH6 offline synthetic benchmark")
