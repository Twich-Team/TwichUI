dofile(TESTS .. "mi_mock.lua")
local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local CORE = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua",
  "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Worth.lua", "Sell.lua", "Disenchant.lua", "Advisor.lua" }
local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
c.TwichUIWorkshopDB = { v = 2, markets = {} }
for _, f in ipairs(CORE) do local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {}) end
local W = c.TwichUI.Workshop
local F, Sh, MK = W.Facts, W.Shopping, W.Market
local DAY, D0 = 86400, 20000
local KEY = "Realm|Alliance"
local function Money(v) return tostring(v) .. "c" end

-- a saved format 3 market (as test_workshop_valuation's RawMarket): listings[id] = { { unit, count } }, days[id] = daily points
local function Dp(d, r, p) return { d = d, p = p or 50, r = r, t = 10, l = 3, n = 1, plo = p or 50, phi = p or 50, rlo = r, rhi = r, tlo = 10, thi = 10 } end
local marketSeq=0
local function Market(key, o)
  marketSeq=marketSeq+1
  local PR, H2 = W.Prices, W.History2
  local b = PR.NewBatch()
  local ids = {}
  for id in pairs(o.listings or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do for _, x in ipairs(o.listings[id]) do b:Add(id, x[2], x[1] * x[2], true) end end
  local items, n, _, _, dist = b:Items()
  local m = { f = 3, scope = "full", realm = "Realm", side = key:match("|(.*)$"), at = o.at, complete = o.complete ~= false, read = 1, used = 1, partial = 0, n = n,
    items = items, hist = o.hist or {}, hn = 0, sd = {}, key = key,
    snap = { seq = o.seq or marketSeq, kind = "full", at = o.at, alg = (not o.noDist) and 1 or nil, records = 1, used = 1, partial = 0, items = n },
    dist = (not o.noDist) and dist or nil, h2 = {}, c2 = {}, scans = {}, days = {}, v2from = (not o.legacy) and 1 or nil, h2info = (not o.legacy) and { v = 1, from = 1, at = o.at } or nil }
  for id, list in pairs(o.days or {}) do m.h2[id], m.c2[id] = H2.Encode({}, list, nil) end
  c.TwichUIWorkshopDB.markets[key] = m
  return m
end
local NOW = D0 * DAY + 12 * 3600
c.time=function() return NOW end
local function Days(from, to, r) local t = {} for d = from, to do t[#t + 1] = Dp(d, r) end return t end
local function Row(rows, id) for _, r in ipairs(rows) do if r.id == id then return r end end end

local A, Sell = W.Advisor, W.Sell
local function Decide(o)
  o = o or {}
  local ctx = { qty = 1, sell = 10, bindType = 0, now = NOW,
    facts = F.Of(100, { market = KEY, now = NOW }) }
  for k,v in pairs(o) do if v == "nil" then ctx[k] = nil else ctx[k] = v end end
  return A.Decide(100, ctx)
end
local function Healthy(o)
  o = o or {}; o.at = o.at or NOW - 60
  o.listings = o.listings or { [100] = { { 100, 20 }, { 100, 20 }, { 100, 20 }, { 110, 20 }, { 110, 20 } } }
  o.days = o.days or { [100] = Days(D0 - 10, D0, 100) }
  return Market(KEY, o)
end
Check(A.SetGain(100), "gain preference can be saved")
Same(A.Gain(), 100); Check(not A.SetGain(-1), "invalid gain refused")
Check(A.SetGain(0), "zero preference preserved")
Healthy()
local r = Decide()
A.SetGain(10000)
Same(Decide().action,r.action,"pure snapshot does not read a changing saved preference")
A.SetGain(0)
Same(r.action, "auction"); Same(r.level,"supported"); Same(r.suggestion.price, 100); Same(r.evidence, "strong")
Same(r.proceeds.gross, 100); Check(r.proceeds.net == nil and r.proceeds.deposit == nil, "unknown costs stay unknown")
Check(r.reasons[1]:find("gross"), "gross comparison is explicit")
Same(Decide({ sell = 110 }).action, "vendor")
Same(Decide({ sell = 99 }).action, "vendor", "1.5 margin")
Same(Decide({ minGain = 91 }).action, "vendor", "adjustable gain")
Same(Decide({ minGain = 90 }).action, "auction", "boundary gain")
Same(Decide({ sell = 0 }).action, "auction")
Same(Decide({ sell = "nil" }).action, "auction"); Same(Decide({sell="nil"}).vendor.value,nil)
Same(Decide({ bound = true }).action, "vendor")
Same(Decide({ bindType = 4 }).suggestion.state, "unavailable")
Same(Decide({ bound = true, sell = 0 }).action, "unknown")
Same(Decide({ bindType = "nil" }).action, "vendor")
Same(Decide({ variant = "suffix" }).action, "vendor")
Same(Decide({ disenchant = true }).action, "auction", "unknown disenchant never blocks auction")
Same(Decide({ qty = "nil" }).action,"unknown","unknown quantity")
Same(Decide({ qty = 0 }).action, "unknown", "no copies cannot sell")
Same(Decide({qty=0}).proceeds,nil,"zero copies cannot show an invented one-item gross")
Same(Decide({qty="nil"}).proceeds,nil,"unknown quantity cannot show a stack total")
Same(Decide({ qty = 100000 }).proceeds.gross, 10000000, "unit times quantity")
Same(Sell.Proceeds(W.Prices.MAX_COPPER, 2).state, "unknown", "bounded arithmetic")
Same(Sell.Suggest(100, 0).state, "uncertain", "invalid quantity")
local craft = { uses = { { id = 1 } }, reserved = 4 }
Same(Decide({ crafting = craft }).action, "craft", "plan precedes sale")
Same(Decide({ crafting = { uses = { { id = 1 } }, reserved = 0 } }).action, "auction", "uses alone cannot prove profit")
Same(Decide({ crafting = { uses = {}, reserved = 0 } }).action, "auction", "unlearned recipes not candidates")
Healthy({ at = NOW - 4 * DAY })
Same(Decide().action,"vendor","known vendor fallback: stale listings"); Same(Decide().suggestion.price,nil,"no posting price: stale listings")
Healthy({ complete = false })
r=Decide(); Same(r.action,"auction","partial current listings may support a tentative comparison")
Same(r.level,"tentative"); Same(r.evidence,"limited")
Same(r.suggestion.price,nil,"tentative observation is never a posting suggestion")
Same(r.proceeds,nil,"tentative comparison never creates sale proceeds")
Same(r.observed.role,"observedListing"); Same(r.observed.value,100)
Same(A.Tooltip(r),"Workshop: Auction"); Same(A.Short(r),"Possible Auction")
Same(W.Worth.Recommend({advisor=r}).kind,"possible","alternate tooltip path cannot promote tentative advice")
Same(W.Worth.Recommend({advisor=r}).pick,nil)
r=Decide({sell=80}); Same(r.action,"vendor","usable partial listings can favor vendoring")
Same(r.level,"tentative"); Same(A.Tooltip(r),"Workshop: Vendor")
Same(r.suggestion.price,nil); Same(r.proceeds,nil)
Same(Decide({minGain=91}).action,"vendor","tentative retains configured gain")
Same(Decide({minGain=90}).level,"tentative","tentative exact gain boundary")
Same(Decide({qty=0}).action,"unknown"); Same(Decide({qty="nil"}).action,"unknown")
Same(Decide({bindType="nil"}).action,"vendor"); Same(Decide({variant="suffix"}).action,"vendor")
Same(Decide({bound=true}).action,"vendor","known ineligible items retain vendor baseline")
Same(Decide({crafting=craft}).action,"craft"); Same(Decide({pendingPlan=true}).action,"unknown")
Same(Decide({disenchant=true}).level,"tentative","missing DE never blocks the supported tentative comparison")
Healthy({complete=false,at=NOW-86400}); Same(Decide().level,"tentative","24-hour observation boundary")
Healthy({complete=false,at=NOW-86401}); Same(Decide().action,"vendor","known vendor fallback: tentative has stricter freshness"); Same(Decide().suggestion.price,nil,"no posting price: tentative has stricter freshness")
local limitedMarket=Healthy({complete=false}); limitedMarket.cut=true
Same(Decide().action,"vendor","known vendor fallback: truncated scan cannot support even tentative advice"); Same(Decide().suggestion.price,nil,"no posting price: truncated scan cannot support even tentative advice")
limitedMarket=Healthy({complete=false}); limitedMarket.scope="recipes"
Same(Decide().action,"vendor","known vendor fallback: old recipe-only coverage is not current market evidence"); Same(Decide().suggestion.price,nil,"no posting price: old recipe-only coverage is not current market evidence")
Healthy({complete=false,noDist=true}); Same(Decide().action,"vendor","known vendor fallback: missing distribution cannot be invented"); Same(Decide().suggestion.price,nil,"no posting price: missing distribution cannot be invented")
Healthy({days={[100]=Days(D0-1,D0,100)}})
r=Decide(); Same(r.level,"supported"); Same(r.evidence,"limited","sparse history retains original fair support")
Same(r.suggestion.price,100)
Healthy({complete=false,days={[100]=Days(D0-10,D0,1000)}})
r=Decide(); Same(r.observed.value,100,"tentative never substitutes historical valuation")
Same(Decide({sell="nil"}).action,"auction","available current observation without a vendor value"); Same(Decide({sell="nil"}).vendor.value,nil)
Healthy({complete=false,listings={[100]={{100,20}}},days={}})
r=Decide(); Same(r.level,"tentative"); Same(r.observed.value,100,"stack buyout normalized to unit observation")
Same(r.suggestion.price,nil)
Healthy({complete=false,listings={[100]={{1,1},{100,1},{100,1}}}})
Same(Decide().action,"vendor","known vendor fallback: tentative cannot bypass suspicious low tiers"); Same(Decide().suggestion.price,nil,"no posting price: tentative cannot bypass suspicious low tiers")
Market(KEY,{at=NOW,listings={},days={[100]=Days(D0-10,D0,100)}})
Same(Decide().action,"vendor","known vendor fallback: history alone never creates current advice"); Same(Decide().suggestion.price,nil,"no posting price: history alone never creates current advice")
Healthy({ listings = { [100] = { { 1, 1 }, { 100, 1 }, { 100, 1 } } } })
Same(Decide().action,"vendor","known vendor fallback: sparse suspicious tier"); Same(Decide().suggestion.price,nil,"no posting price: sparse suspicious tier")
Healthy({ listings = { [100] = { { 100, 1 } } } })
Same(Decide().suggestion.price, nil, "sparse has no suggestion")
Market(KEY, { at = NOW, listings = {} })
Same(Decide().action,"vendor","known vendor fallback: no data"); Same(Decide().suggestion.price,nil,"no posting price: no data")
Same(Decide({ bound = true }).action, "vendor", "definitive vendor-only")
Healthy({ days = { [100] = Days(D0 - 10, D0, 1000) } })
r = Decide(); Same(r.suggestion.price, 100, "history never sets posting price")
Same(r.suggestion.flags[1], "belowusual")
Healthy({ days = { [100] = Days(D0 - 10, D0, 60) } })
r = Decide(); Same(r.suggestion.price, 100); Same(r.suggestion.flags[1], "aboveusual")
local f = F.Of(100, { market = KEY, now = NOW })
f.comp.notes[#f.comp.notes + 1] = "mixedvariants"
Same(Decide({ facts = f }).action,"vendor","mixed variants retain known vendor value"); Same(Decide({facts=f}).suggestion.price,nil)
Healthy()
local before = F.CacheStats()
local started = os.clock()
for i = 1, 10000 do Same(Decide().suggestion.price, 100) end
Check(F.CacheStats().hits >= before.hits + 9999, "repeated facts cached")
print(("advisor repeated 10000: %.4fs, fact entries %d"):format(os.clock()-started, F.CacheSize()))
-- Expected disenchant estimates use only complete verified Forever evidence.
local DE = W.Disenchant
local df = { item = 100, quality = 2, classID = 4, canDisenchant = true, enchantSkill = 75 }
local ds = { item = 100, verified = true, client = "forever", source = "synthetic regression only", eligible = true, requiredSkill = 50,
  outcomes = { { p = 0.75, materials = { { item = 200, qty = 2 } } }, { p = 0.25, materials = { { item = 201, qty = 1 } } } },
  values = { [200] = { value = 200, quality = "good" }, [201] = { value = 400, quality = "fair" } } }
Same(DE.Evaluate(df,ds).expectedGross,400)
Same(DE.Evaluate(df).state,"unknown", "no shipped dataset")
df.canDisenchant=false; Same(DE.Evaluate(df,ds).state,"unavailable"); df.canDisenchant=true
df.enchantSkill=10; Same(DE.Evaluate(df,ds).state,"unavailable"); df.enchantSkill=75
df.equipLoc="INVTYPE_BODY"; Same(DE.Evaluate(df,ds).state,"unavailable"); df.equipLoc=nil
ds.verified=false; Same(DE.Evaluate(df,ds).state,"unknown"); ds.verified=true
ds.client="classic"; Same(DE.Evaluate(df,ds).state,"unknown"); ds.client="forever"
ds.values[201]=nil; Same(DE.Evaluate(df,ds).state,"unknown"); ds.values[201]={value=400,quality="fair"}
ds.outcomes[2].p=0.1; Same(DE.Evaluate(df,ds).state,"unknown"); ds.outcomes[2].p=0.25
Healthy()
Same(Decide({disenchantValue=DE.Evaluate(df,ds)}).action,"disenchant")
Same(Decide({disenchantValue=DE.Evaluate(df,ds)}).proceeds,nil,"auction proceeds do not describe a disenchant recommendation")
Same(Decide({bound=true,disenchantValue=DE.Evaluate(df,ds)}).action,"disenchant")
Same(Decide({bound=true,disenchant=true}).action,"vendor", "unknown disenchant never blocks vendor")
Same(Decide({disenchantValue={state="ok",expectedGross=90}}).action,"auction", "lower expected value cannot win")
-- Adapter: supported identity sources, saved preferences and a large sliced catalog.
for _, file in ipairs({ "Worth.lua", "CraftPlanner.lua", "Strategy.lua", "Fees.lua", "Estimate.lua", "Session.lua", "AdvisorData.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. file)); setfenv(chunk,c); chunk()
end
local D, session = W.AdvisorData, W.Session
session.AllRecipes = function() return { { id = 7, outItem = 101, mats = { { item = 100, qty = 2 } } } } end
session.QueueStrategy = function() return "ready", { items = { { item = 100, need = 5, owned = { bags = 5 } } } } end
c.C_Item = { GetItemInfo = function(id) return "Material " .. id, nil, 1, nil, nil, "Trade Goods", "Cloth", 200, "", 134400, 10, 7, 1, 0 end }
W.Observe.BagCount = function(id) return id == 100 and 10 or id == 101 and 1 or 0 end
-- Native aggregate includes an equipped copy of 100 and equipped-only 101.
local bagSlots = {
  { itemID=100, stackCount=4, isBound=false },
  { itemID=100, stackCount=5, isBound=false },
  { itemID=102, stackCount=2, isBound=false }, -- bag-only, metadata pending
}
c.C_Container = {
  GetContainerNumSlots=function(bag) return bag==0 and #bagSlots or 0 end,
  GetContainerItemInfo=function(_,slot) return bagSlots[slot] end,
}
local infoReader=c.C_Item.GetItemInfo
c.C_Item.GetItemInfo=function(id) if id~=102 then return infoReader(id) end end
Check(D.Track(100)); Check(D.Tracked()[100]); Check(D.Select(100)); Same(D.Selected(),100)
local job = D.Catalog(); local steps = 0
while not job.done do local _, err = job:Step(); Check(not err, err); steps=steps+1 end
Check(job.byID[100] and job.byID[101], "market and known recipe identities")
Check(D.Matches(job.byID[100], "material", "bags", true), "bag and auctionable filters")
Check(not D.Matches(job.byID[101], "", "bags", false), "bags only")
Same(job.byID[100].count,9,"multiple stacks exclude equipped copy")
Same(D.Context(100,false,job.byID[100]).qty,9,"advice uses the bag-only quantity")
Same(job.byID[101].count,0,"equipped-only recipe identity has zero bag copies")
Check(D.Matches(job.byID[101], "", "all", false),"all-known keeps equipped identity")
Check(D.Track(101)); Check(D.Matches(job.byID[101], "", "tracked", false),"tracked keeps equipped identity"); Check(D.Track(101))
Same(D.Selected(),100,"filtering preserves selection")
Check(D.Matches(job.byID[102], "", "bags", false),"bag-only identity with pending metadata remains visible")
Same(job.byID[102].count,2); Same(job.byID[102].info.name,"Item 102")
Same(D.Decide(100,true,job.byID[100]).action, "craft", "actual planner demand is authoritative")
Same(D.Context(100,true,job.byID[100]).crafting.reserved,5)
-- A readable identity with an unreadable stack count is still a bag discovery;
-- never substitute the native aggregate or invent zero as its quantity.
bagSlots[3].stackCount=nil
local unknown=D.Catalog()
repeat local _,err=unknown:Step(); Check(not err,err) until unknown.done
Check(D.Matches(unknown.byID[102],"","bags",false))
Same(unknown.byID[102].count,nil,"unreadable bag count remains unknown")
Same(D.Context(102,false,unknown.byID[102]).qty,nil,"advice preserves unknown bag quantity")
bagSlots[3].stackCount=2
-- Exact bag-copy binding overrides a generic BoE type; all-bound copies cannot auction.
local bagrow={info={sell=10,bindType=2,quality=1,classID=7},uses={},slots=true,count=9,unbound=3}
Same(D.Context(100,false,bagrow).qty,3)
local bagAdvice=D.Decide(100,false,bagrow); Same(bagAdvice.action,"auction", table.concat(bagAdvice.reasons," ") .. table.concat(bagAdvice.missing," "))
bagrow.unbound=nil; bagrow.bound=9
Same(D.Decide(100,false,bagrow).action,"vendor")
bagrow.variant=true; bagrow.unbound=3
Same(D.Decide(100,false,bagrow).action,"vendor")
local m = Healthy(); for id = 1000, 20999 do m.items[id] = m.items[100] end
local big = D.Catalog(); local count, maxms, t = 0,0,os.clock()
repeat local t0=os.clock(); local _,err=big:Step(); Check(not err,err); maxms=math.max(maxms,(os.clock()-t0)*1000); count=count+1 until big.done
Same(#big.rows,20003); Check(count >= 250, "discovery cooperatively sliced")
print(("advisor catalog 20003: %.4fs, %d slices, max %.3fms"):format(os.clock()-t,count,maxms))
Check(D.Track(100)); Same(D.Tracked()[100],nil,"toggle tracking")
-- Cooperative final ordering: independent numeric oracle, exact row identity and
-- native-run bounds at partial/final run boundaries and non-power-of-two tails.
local savedSource, savedRecipes = session.PriceSource, session.AllRecipes
local savedTable, savedContainer = c.table, c.C_Container
local largestRun = 0
c.table = {}; for k,v in pairs(table) do c.table[k]=v end
c.table.sort = function(rows, less)
    largestRun = math.max(largestRun, #rows)
    Check(#rows <= 4096, "native sorting is bounded independently of catalog size")
    table.sort(rows, less)
end
session.AllRecipes=function() return {} end
c.C_Container=nil
c.TwichUIDB.workshop.view.advisorTracked={}
c.TwichUIDB.workshop.view.advisorItem=nil
for _,size in ipairs({0,1,4095,4096,4097,8193}) do
    for seed=1,3 do
        local items, expected={},{}
        for i=size,1,-1 do
            local id=1000+(i*7919+seed*97)%65521
            items[id]={}; expected[#expected+1]=id
        end
        table.sort(expected)
        session.PriceSource=function() return {market={items=items}} end
        local sorted=D.Catalog();local ticks=0
        repeat local _,err=sorted:Step();Check(not err,err);ticks=ticks+1;Check(ticks<1000,"sort settles") until sorted.done
        Same(#sorted.rows,#expected,"all identities retained")
        for i,id in ipairs(expected) do
            Same(sorted.rows[i].item,id,"numeric reference order")
            Same(sorted.rows[i],sorted.byID[id],"original row identity")
            Same(sorted.rows[i].info.name,"Material "..id,"metadata retained")
        end
    end
end
Check(largestRun>0,"native run sorting exercised")
session.PriceSource,session.AllRecipes=savedSource,savedRecipes
c.table,c.C_Container=savedTable,savedContainer

-- Failed item-data requests are bounded until an explicit retry.
local infoReader=c.C_Item.GetItemInfo
local metadataRequests=0
c.C_Item.GetItemInfo=function(id) if id~=999 then return infoReader(id) end end
c.C_Item.RequestLoadItemDataByID=function() metadataRequests=metadataRequests+1 end
D.Request(999); D.Request(999); Same(metadataRequests,1,"failed metadata loads cannot cause a request loop")
D.Request(999,true); Same(metadataRequests,2,"explicit selection can retry")
c.C_Item.GetItemInfo=infoReader
-- The actual tooltip renderer uses the default configurable recommendation id.
local chunk=assert(loadfile(ROOT .. "../TwichUI_Workshop/WorthLayout.lua")); setfenv(chunk,c); chunk()
local WL=W.WorthLayout
local eval=W.Worth.Evaluate({sell=10,bindType=1})
eval.advisor=A.Decide(100,{qty=1,sell=10,bindType=1})
local ctx={money=tostring,ageText=tostring}
local default=WL.Lines(eval,ctx,WL.Get(),false)
Check(table.concat(default[2]," "):find("Workshop: Vendor",1,true),"default Normal recommendation")
for _,action in ipairs({"vendor","auction","disenchant","craft","unknown"}) do
  eval.advisor.action=action
  local lines=WL.Lines(eval,ctx,{enabled=true,lines={{id="recommend",when="always"}}},false)
  if A.Tooltip(eval.advisor) then Check(lines[1][1]:find(A.Tooltip(eval.advisor),1,true),"simple primary wording " .. action) else Check(lines==nil,"non-sale action stays out of sale recommendation") end
end
Healthy({complete=false})
eval.advisor=Decide()
local tentativeLines=WL.Lines(eval,ctx,{enabled=true,lines={{id="recommend",when="always"}}},false)
Check(tentativeLines[1][1]:find("Workshop: Auction",1,true),"Normal configurable field preserves qualification")
local shifted={enabled=true,lines={{id="recommend",when="shift"}}}
local normal=WL.Lines(eval,ctx,shifted,false) or {}
for _,line in ipairs(normal) do Check(not line[1]:find("Workshop:",1,true),"Shift-only recommendation hidden normally") end
Check(WL.Lines(eval,ctx,shifted,true)~=nil,"Shift shows configured recommendation")
Check(WL.Lines(eval,ctx,{enabled=true,lines={}},true)==nil,"removed recommendation stays removed")
Check(WL.UsesAdvisor({lines={{id="advisorwhy",when="shift"}}},false)==false,"hidden detail does no advisor work")
Check(WL.UsesAdvisor({lines={{id="advisorwhy",when="shift"}}},true),"Shift detail requests advisor")
-- Enable/disable belongs to WorthTip, before the shared presentation builder.
c.time=function() return NOW end
local drawn={}
c.GameTooltip={ AddLine=function(_,s) drawn[#drawn+1]=s end, AddDoubleLine=function(_,a,b) drawn[#drawn+1]=a .. " " .. b end }
c.C_Item.GetItemLocation=function() return {IsBagAndSlot=function() return true end} end
c.C_Item.DoesItemExist=function() return true end
c.C_Item.GetItemID=function() return 100 end
c.C_Item.GetItemLink=function() return "item:100" end
c.C_Item.IsBound=function() return false end
c.C_Item.GetStackCount=function() return 20 end
c.IsShiftKeyDown=function() return false end
local tipChunk=assert(loadfile(ROOT .. "../TwichUI_Workshop/WorthTip.lua")); setfenv(tipChunk,c); tipChunk()
session.QueueStrategy=function() error("hover must never start or request a planner job") end
Healthy()
Check(WL.Set({enabled=false,lines={{id="recommend",when="always"}}}))
W.WorthTip.OnItem(c.GameTooltip,{guid="Item-100"}); Same(#drawn,0,"disabled tooltip adds nothing")
Check(WL.Set({enabled=true,lines={{id="recommend",when="always"}}}))
W.WorthTip.OnItem(c.GameTooltip,{guid="Item-100"})
Check(table.concat(drawn," "):find("Workshop: Auction",1,true),"actual Normal tooltip calls Advisor")
Healthy({complete=false})
drawn={}; W.WorthTip.OnItem(c.GameTooltip,{guid="Item-100"})
Check(table.concat(drawn," "):find("Workshop: Auction",1,true),"actual Normal renderer keeps limited evidence visible")
Check(WL.Set({enabled=true,lines={{id="recommend",when="shift"}}}))
drawn={}; W.WorthTip.OnItem(c.GameTooltip,{guid="Item-100"})
Check(not table.concat(drawn," "):find("Workshop:",1,true),"tentative respects Shift-only customization")
Check(WL.Set({enabled=true,lines={{id="vendor",when="always"}}}))
drawn={}; W.WorthTip.OnItem(c.GameTooltip,{guid="Item-100"})
Check(not table.concat(drawn," "):find("Workshop:",1,true),"removing primary is respected by the live renderer")
Same(W.WorthTip.faults,0,"live renderer has no faults")
print("advisor: OK")
