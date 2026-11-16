local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
local D=W.AuctionMarketData
local n=0
local function same(a,b,msg) n=n+1;assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local native=0
c.C_AuctionHouse=setmetatable({},{__index=function(_,k) return function() native=native+1;error("forbidden "..k) end end})
local function Finish(j)
    local steps,longest,start=0,0,os.clock()
    repeat
        local t=os.clock();local done,err=j:Step();assert(not err,err)
        longest=math.max(longest,os.clock()-t);steps=steps+1;assert(steps<10000)
        if done then break end
    until false
    return steps,longest,os.clock()-start
end
same(D.Resolve("Realm|Alliance").key,m.key)
same(D.Resolve("absent"),nil,"explicit missing market never falls back")
same(D.Project(10,nil,14,{now=now}).facts.min,nil,"no market never uses automatic prices")
local j=D.Catalog({market=m});Finish(j)
same(#j.rows,2,"union includes history-only item")
same(j.index[11].unit,nil,"history-only item has no latest listing")
same(j.index[10].unit,20200,"current minimum via shared normalization")
local p=D.Project(10,m,14,{now=now})
same(p.facts.min.value,20200);same(p.facts.supply.items,50);same(p.facts.supply.listings,2)
same(p.market,m.key);same(p.facts.mval~=nil,true);same(p.facts.hist~=nil,true)
same(#p.series.points>2,true);same(#p.series.gaps>0,true,"missing days retained")
local cached=p.history
same(D.Project(10,m,60,{now=now}).history,cached,"range changes reuse selected projection")
local long=D.Project(10,m,120,{now=now})
same(#long.series.groups>0,true,"older aggregates preserved separately")
for _,v in ipairs(long.series.points) do same(v.kind=="day" or v.kind=="legacy-day",true,"no aggregate daily samples") end
for _,v in ipairs(long.series.groups) do same(v.to>v.from,true);same(v.provenance,"local") end
local recent=D.Project(10,m,2,{now=now}).series
same(#recent.points>0,true);same(recent.points[1].day%1~=0,true,"true observation time")
for _,v in ipairs(recent.points) do same(v.kind,"obs") end
local variant=D.Project(10,m,14,{now=now,variant=true})
same(variant.facts.min,nil);same(variant.history,nil);same(variant.why,"variant")
local horde=D.Project(10,D.Resolve("Realm|Horde"),14,{now=now})
same(horde.facts.min.value,900,"market isolation");same(horde.facts.supply.complete,false)
local stale=D.Project(10,m,14,{now=now+30*86400});same(stale.facts.freshness,"old");same(stale.facts.quality.level=="good",false)
same(D.Context(10,{itemKey={itemID=11}}),nil,"identity mismatch rejected")
same(D.Context(10,{itemKey={itemID=10,itemSuffix=4}}).variant,true)
local empty=D.Catalog({market=nil});Finish(empty);same(#empty.rows,0)
local track=W.AdvisorData.Tracked
W.AdvisorData.Tracked=function() return {[12]=true,[14]=true} end
local tracked=D.Catalog({market=m,scope="tracked",query="14"});Finish(tracked)
same(#tracked.rows,1);same(tracked.rows[1].item,14,"ID search with missing metadata")
local bags={ [1]={itemID=12},[2]={itemID=10} }
c.C_Container={GetContainerNumSlots=function(b) return b==0 and 2 or 0 end,
 GetContainerItemInfo=function(_,s) return bags[s] end}
local bag=D.Catalog({market=m,scope="bags",quality=3});Finish(bag)
same(#bag.rows,1);same(bag.rows[1].item,12,"quality filter uses metadata")
W.AdvisorData.Tracked=track
-- Independent sparse typed-history projection, with a boundary-overhanging bucket.
local h={points={{kind="day",from=19998,to=19998,v=17,partial=true,provenance="local"},
 {kind="fortnight",from=19980,to=19993,v=12,n=3,provenance="legacy"},
 {kind="obs",at=now-100,last=now-50,v=18,provenance="local"}},gaps={{from=19994,to=19997}}}
local s=D.Series(h,7,now)
same(#s.points,1);same(s.points[1].price,17);same(s.points[1].partial,true);same(#s.groups,0)
s=D.Series(h,14,now);same(#s.groups,1);same(s.groups[1].from,19980,"bucket boundary not clipped into invented evidence")
same(s.groups[1].n,3);same(s.groups[1].provenance,"legacy")
-- Catalog never computes a history/valuation per row. Cooperative union deduplicates.
local large={key=m.key,at=now,scope="full",complete=true,items={},h2={}}
for id=1,20005 do large.items[id]=m.items[10];large.h2[id]=m.h2[10] end
local hist=W.Market.History;W.Market.History=function() error("history per catalog row") end
local big=D.Catalog({market=large});local steps,longest,total=Finish(big)
W.Market.History=hist
same(#big.rows,20000);same(big.capped,true);same(steps>10,true)
local prev=0;for _,r in ipairs(big.rows) do same(r.item>prev,true,"stable identity tie order");prev=r.item end
print(("AH6 20k union catalog: %d slices, %.3fs, %.3fms max (offline CPU, not client frame time)"):format(steps,total,longest*1000))
W.UI.Init()
local default=W.UI.PriceChart(c.UIParent,400,100)
local chart=W.UI.PriceChart(c.UIParent,400,100,{maxDots=30,window=true,gold=true})
same(#default.dots,8);same(#chart.dots,30,"bounded optional adapter leaves old chart unchanged")
chart:Set(p.series,W.UI.Money);same(chart.fromDay,p.series.from);same(chart.toDay,p.series.to)
local all=W.UI.PriceChart(c.UIParent,800,136,{maxDots=60,window=true,gold=true})
local dense={points={},from=1,to=60};for day=1,60 do dense.points[day]={day=day,price=100+day} end
all:Set(dense,W.UI.Money);same(all.shown,60,"complete external daily window is rendered")
for i=1,60 do same(all.dots[i]:IsShown(),true,"external marker hidden") end
all:Set(dense,W.UI.Money,30);same(all.shown,30,"local marker cap preserved")
for i=31,60 do same(all.dots[i]:IsShown(),false,"local view leaked older external markers") end
same(#default.dots,8,"default chart unchanged")
D.Clear();same(D.Stats().cache,0);same(D.Stats().points,0);same(native,0)
print("PASSED: Auction Market adapter "..n.." checks")
