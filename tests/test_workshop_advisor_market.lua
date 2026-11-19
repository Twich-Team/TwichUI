-- Shared policy over supplied evidence; no actions or invented live listings.
local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local A=W.Advisor
local function decide(value,sell,opt)
 local facts={recent=value and {value=value,source='market_server',at=100,generation='fixture'},key='pricing:fixture',referenceWhy=not value and 'loading'}
 local ctx={qty=1,sell=sell,bindType=0,now=160,minGain=0,facts=facts}
 for k,v in pairs(opt or {}) do ctx[k]=v end
 return A.Decide(2589,ctx)
end
local auction=decide(200,100)
assert(auction.action=='auction' and auction.level=='tentative')
local vendor=decide(120,100)
assert(vendor.action=='vendor' and vendor.level=='tentative','usable Market price must compare in both directions')
assert(A.Tooltip(auction)=='Workshop: Auction (Market estimate)')
assert(A.Tooltip(vendor)=='Workshop: Vendor (Market comparison)')
assert(A.Short(vendor):find('Vendor',1,true) and not A.Short(vendor):find('Auction',1,true))
assert(vendor.text:find('Vendor',1,true) and vendor.reference.value==120)
for _,r in ipairs({auction,vendor}) do
 assert(r.evidence=='limited' and not r.suggestion.price and not r.proceeds,'reference guidance became a posting suggestion or proceeds')
 local rec=W.Worth.Recommend({advisor=r})
 assert(rec.kind=='possible' and not rec.pick,'reference guidance became a proven winner')
 assert(r.alternatives[2].state=='reference' and r.alternatives[2].value==r.reference.value)
end
-- Independent integer arithmetic: at least half the vendor amount in extra
-- gross value, AND the user's required gain. Equal vendor value favors vendor.
for seed=1,128 do
 local sell=2*(1+seed%17);local value=1+(seed*43)%160;local gain=seed%37
 local extra=value-sell
 local expected=extra>0 and 2*extra>=sell and extra>=gain and 'auction' or 'vendor'
 local r=decide(value,sell,{minGain=gain})
 assert(r.action==expected,'reference comparison differs from the independent margin model at '..seed)
 assert(not r.suggestion.price and not r.proceeds and r.level=='tentative')
end
assert(decide(150,100).action=='auction','exact relative margin')
assert(decide(149,100).action=='vendor','below relative margin')
assert(decide(200,100,{minGain=101}).action=='vendor','gain preference')
assert(decide(200,100,{minGain=100}).action=='auction','exact gain')
assert(decide(1,0).action=='auction','zero vendor value is known')
assert(A.Tooltip(decide(1,0,{minGain=2}))=='Workshop: Auction gain below preference','a known low gain is not missing evidence')
assert(decide(200,nil).action=='unknown','missing vendor value is not zero')
assert(decide(200,100,{variant='suffix'}).action=='unknown','reference cannot price a native variant')
assert(decide(200,100,{bound=true}).action=='vendor','bound items cannot be auctioned')
assert(decide(200,100,{pendingPlan=true}).action=='unknown','pending crafting dependencies remain protected')
assert(decide(200,100,{crafting={reserved=1,uses={}}}).action=='craft')
for _,qty in ipairs({0,-1}) do assert(decide(200,100,{qty=qty}).action=='unknown') end
assert(A.Tooltip(decide(nil,100))=='Workshop: Loading Market price','pending validation should say what is pending')
assert(A.Tooltip(decide(200,100,{variant='bonus'}))=='Workshop: Check variant price')
assert(A.Tooltip(decide(nil,100,{facts={}}))=='Workshop: Auction price unavailable')
-- Disenchant must be explicit in the primary line even when details are hidden.
local gear={disenchant=true,disenchantValue={state='unknown',why='No verified outcomes.'}}
local unknown=decide(200,100,gear)
assert(unknown.action=='auction' and A.Tooltip(unknown):find('disenchant unpriced',1,true))
assert(unknown.disenchant.expectedGross==nil,'missing outcomes became a number')
local de=decide(200,100,{disenchant=true,disenchantValue={state='ok',expectedGross=400}})
assert(de.action=='disenchant' and A.Tooltip(de)=='Workshop: Disenchant (expected value)','verified expected value was not compared against Market evidence')
assert(not de.suggestion.price and not de.proceeds)
assert(decide(200,100,{disenchantValue={state='ok',expectedGross=250}}).action=='auction','DE margin is still required')
assert(decide(200,100,{disenchantValue={state='unavailable',expectedGross=1000}}).action=='auction','unavailable DE cannot win')
assert(decide(200,100,{pendingPlan=true,disenchantValue={state='ok',expectedGross=1000}}).action=='unknown')
print('PASSED two-way Market recommendations, independent margins, qualifications, specific missing reasons and verified DE comparisons')
