-- Dormant module, strict numeric boundary and no changes to local services/data.
REPO = REPO or "../"
TwichUI = { Workshop = { Market = { marker = true }, Prices = { marker = true } } }
local W = TwichUI.Workshop
local market, prices = W.Market, W.Prices
TwichUIWorkshopDB = { v = 2, untouched = true }
local db = TwichUIWorkshopDB
dofile(REPO .. "TwichUI_Workshop/Data.lua")
dofile(REPO .. "TwichUI_Workshop/PricingV1.lua")
local P, key = W.PricingV1, string.rep("a", 64)
local function Row(p, q) return {item_id=2589,variant_key=key,quantity=q,unit_copper=p} end
local function Snapshot(rows) return P.Snapshot(rows,2589,key,"commodities",P.ALGORITHM) end
local r = assert(Snapshot({Row("2500",5),Row("5000",20)}))
assert(r.recent_copper == "3333", "exact half-anchor is eligible")
assert(P.Snapshot({},2589,key,"commodities","future") == nil)
for _, value in ipairs({"01","-1","1e3","9007199254740993","9223372036854775807"}) do assert(P.Copper(value) == nil) end
assert(P.Copper(100) == nil)
local bad = Row("100",1); bad.variant_key=string.rep("b",64)
assert(Snapshot({bad}) == nil)
assert(Snapshot({Row("100",0/0)}) == nil)
-- Wide intermediates must be refused before multiplication, even if the final
-- price is in range. The Market/Rust exact calculation can still provide it.
local result, why = Snapshot({Row("50000000000",100000000),Row("90000000000",1000000000)})
assert(result == nil and why == "numeric_range")
result, why = Snapshot({Row("1000000000",100000),Row("2000000000",2000000)})
assert(result == nil and why == "numeric_range", "doubling a still-exact sum must be bounded too")
local function Point(id, at, value, complete, state)
    return {observation_id=id,observed_at=at,recent_copper=value,complete=complete,state=state or "listed",
        market_key="fixture",item_id=2589,variant_key=key,algorithm=P.ALGORITHM,synthetic=true,content_id="same"}
end
local now=1794744000
local points={Point(1,now-86400,"100",true),Point(2,now,"120",true)}
local h=assert(P.History(points,"fixture",2589,key,now,P.ALGORITHM))
assert(h.market_value_copper=="100" and h.historical_value_copper==nil)
points[3]=Point(3,now,nil,true,"absent")
h=assert(P.History(points,"fixture",2589,key,now,P.ALGORITHM))
assert(h.priced_days_60==1 and h.observed_days_60==2 and h.distinct_content_count==1)
points[3]=Point(3,now+1,"999",true)
assert(P.History(points,"fixture",2589,key,now,P.ALGORITHM)==nil)
assert(W.Market==market and W.Prices==prices and TwichUIWorkshopDB==db and db.untouched and db.v==2)
local toc=assert(io.open(REPO .. "TwichUI_Workshop/TwichUI_Workshop.toc")):read("*a")
assert(not toc:find("PricingV1.lua",1,true), "shadow must not load through TOC")
print("PASSED Workshop canonical shadow arithmetic and isolation")
