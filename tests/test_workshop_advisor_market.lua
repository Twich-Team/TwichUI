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
assert(A.Tooltip(auction)=='Workshop: Auction')
assert(A.Tooltip(vendor)=='Workshop: Vendor')
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
assert(A.Tooltip(decide(1,0,{minGain=2}))==nil,'a known low gain respects the gain preference')
assert(decide(200,nil).action=='auction' and decide(200,nil).vendor.value==nil,'missing vendor value is not zero')
assert(decide(200,100,{variant='suffix'}).action=='vendor' and not decide(200,100,{variant='suffix'}).suggestion.price,'unpriced variants still have a known vendor option')
assert(decide(200,100,{bound=true}).action=='vendor','bound items cannot be auctioned')
assert(decide(200,100,{pendingPlan=true}).action=='unknown','pending crafting dependencies remain protected')
assert(decide(200,100,{crafting={reserved=1,uses={}}}).action=='craft')
for _,qty in ipairs({0,-1}) do assert(decide(200,100,{qty=qty}).action=='unknown') end
local pending=decide(nil,100)
assert(pending.action=='unknown' and pending.pending and pending.pricingState=='pending' and pending.dependencies[2589])
assert(A.Tooltip(pending)==nil,'a pending Market price must not finalize the known vendor option')
local localPending=decide(nil,100,{facts={referenceWhy='loading',comp={competing=50,age=0,complete=true},quality={level='good'}}})
assert(localPending.action=='unknown' and localPending.pending,'a provisional local Vendor comparison must wait for Market')
assert(decide(nil,100,{bound=true}).action=='vendor' and not decide(nil,100,{bound=true}).pending,'bound items do not wait for irrelevant auction prices')
assert(decide(nil,100,{variant='suffix'}).action=='vendor' and not decide(nil,100,{variant='suffix'}).pending,'unpriced variants do not wait for base prices')
assert(A.Tooltip(decide(200,100,{variant='bonus'}))=='Workshop: Vendor')
assert(A.Tooltip(decide(nil,100,{facts={}}))=='Workshop: Vendor')
assert(A.Tooltip(decide(nil,0,{facts={}}))==nil,'no eligible priced option gives no sale recommendation')
assert(A.Tooltip(decide(200,100,{pendingPlan=true}))==nil)
assert(A.Tooltip(decide(200,100,{crafting={reserved=1,uses={}}}))==nil)
-- Disenchant must be explicit in the primary line even when details are hidden.
local gear={disenchant=true,disenchantValue={state='unknown',why='No verified outcomes.'}}
local unknown=decide(200,100,gear)
assert(unknown.action=='auction' and A.Tooltip(unknown)=='Workshop: Auction')
assert(unknown.disenchant.expectedGross==nil,'missing outcomes became a number')
local de=decide(200,100,{disenchant=true,disenchantValue={state='ok',expectedGross=400}})
assert(de.action=='disenchant' and A.Tooltip(de)=='Workshop: Disenchant','verified expected value was not compared against Market evidence')
assert(not de.suggestion.price and not de.proceeds)
local materialPending=decide(120,100,{bound=true,disenchant=true,disenchantValue={state='unknown',pending=true,dependencies={[10940]=true}}})
assert(materialPending.action=='unknown' and materialPending.pending and materialPending.dependencies[10940])
assert(not materialPending.dependencies[2589] and materialPending.unknownText=='Loading disenchant material prices','bound items still wait for applicable material prices')
local complete=decide(120,100,{disenchant=true,disenchantValue={state='ok',expectedGross=50,dependencies={[10940]=true}}})
assert(complete.action=='vendor' and not complete.pending and complete.pricingState=='ready' and complete.dependencies[10940])
assert(decide(200,100,{disenchantValue={state='ok',expectedGross=250}}).action=='auction','DE margin is still required')
assert(decide(200,100,{disenchantValue={state='unavailable',expectedGross=1000}}).action=='auction','unavailable DE cannot win')
assert(decide(200,100,{pendingPlan=true,disenchantValue={state='ok',expectedGross=1000}}).action=='unknown')
local suffix=decide(nil,3294,{variant='suffix',facts={},disenchantValue={state='ok',expectedGross=2054}})
assert(suffix.action=='vendor' and A.Tooltip(suffix)=='Workshop: Vendor','reported suffix case: vendor 32s94c beats DE 20s54c')
local higher=decide(nil,3294,{variant='suffix',facts={},disenchantValue={state='ok',expectedGross=6000}})
assert(higher.action=='disenchant' and A.Tooltip(higher)=='Workshop: Disenchant' and not higher.suggestion.price)
local art={vendor='balance-scales-small',auction='gavel-small',disenchant='magic-enchanting-small'}
for _,advice in ipairs({vendor,auction,higher})do
 local lines=W.WorthLayout.Lines({advisor=advice},{},{enabled=true,lines={{id='recommend',when='always'}}},false)
 assert(#lines==1 and lines[1][1]:find(art[advice.action],1,true),'matching addon artwork missing')
 assert(lines[1][1]:find('|T',1,true) and lines[1][1]:find('|t Workshop:',1,true),'artwork and suggestion must share a line')
 assert(not lines[1][1]:find('Interface\\Icons',1,true),'recommendation must use addon artwork')
 local kind,text=W.WorthLayout.Style(lines[1])
 assert(kind==advice.action,'recommendation color must follow the action, including tentative advice')
 assert(text:find('|t Workshop: '..A.TOOLTIP[advice.action],1,true))
 local color=W.WorthLayout.COLORS[kind]
 assert(color and not (color[1]==color[2] and color[2]==color[3]),'recommendation must not be gray')
end
print('PASSED two-way Market recommendations, independent margins, qualifications, specific missing reasons and verified DE comparisons')
