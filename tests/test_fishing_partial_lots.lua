-- Regression: uncertainty belongs to the entire queued lot after bag moves.
-- Exercise real key/loot bookkeeping; verify values, exhaustion and unsuccessful opens.
dofile(TESTS .. "fishing_mock.lua")
local c, W = FishingClient()
W.bound.F, W.bound.G = "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton"
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
W.Wear(16, POLE)
local F = c.TwichUI.Fishing
local prices = { [CLAM] = 500, [PEARL] = 10000, [CLAMMEAT] = 20 }
c.TwichUI.Workshop = {
 Active=function() return true end,
 Pricing={ Generation=function() return 'partial-lot' end,
 Source=function()return {reference=true,label='Synthetic reference',market={key='Fixture|Alliance',at=1800000000,realm='Fixture',side='Alliance'}}end,
 Reference=function(id)return {market=prices[id],at=1800000000}end, Changed=function()end },
 Market={ Value=function()error('No local mixing')end }
}
local function Catch()
 W.StartLine(); W.Loot({{CLAM,1}}, {fishing=true}); W.StopLine(); W.Settle()
end
Catch(); Catch()
local lot = F.Containers.Queue()[1]
assert(#F.Containers.Queue()==1 and lot.n==2, 'two catches form one lot')
local oldBag, oldSlot = W.Find(CLAM)
local other
for bag=0,4 do for _, e in pairs(W.bags[bag]) do if e.id==CLAM and e~=W.bags[oldBag][oldSlot] then other=e end end end
assert(other)
local realOpen = W.OpenContainer
W.OpenContainer=function(b,s)realOpen(b,s,{take=function(i)return i==1 end,keep=true})end
W.Key('G');W.Advance(3)
assert(lot.partial and lot.n==2)
-- Move the first partial shell behind the other shell, as a player can in bags.
local firstPartial
for bag=0,4 do for slot,e in pairs(W.bags[bag]) do
 if e.id==CLAM and e~=other then firstPartial=e;W.bags[bag][slot]=nil end
end end
assert(firstPartial)
W.bags[4][W.bagSize]=firstPartial;W.Settle()
local nextPlan=assert(F.Containers.Plan(false))
assert(W.bags[nextPlan.bag][nextPlan.slot]==other, 'the next press opens the other shell')
W.Key('G');W.Advance(3)
assert(lot.partial and lot.n==2)
local p=F.API.Provenance('session')
assert(p.contents[PEARL]==2 and p.containers[CLAM].partial==2)
-- Finish only the second shell. The first still contains unlooted meat.
W.OpenContainer=realOpen
W.contents[CLAM]={{CLAMMEAT,1}}
W.Key('G');W.Advance(3)
p=F.API.Provenance('session')
assert(lot.n==1 and p.containers[CLAM].opened==1 and p.contents[PEARL]==2)
F.Economy.Scope('session');W.Advance(1)
local value=F.Economy.Scope('session')
print('partial flag after one finishes:',tostring(lot.partial),'remaining provisional quantity:',p.containers[CLAM].unopened-p.containers[CLAM].partial,'economic total:',value.total)
assert(value.total==20020, 'remaining partial shell must not regain provisional value beside its already-recorded pearl')
print('PASSED partial lot remains conservative')

-- Finish the remaining shell: the lot disappears and its marker is retired.
W.Key('G'); W.Advance(3)
p=F.API.Provenance('session')
value=F.Economy.Scope('session')
assert(#F.Containers.Queue()==0 and lot.n==0 and lot.partial==nil)
assert(p.containers[CLAM].opened==2 and p.containers[CLAM].unopened==0 and p.containers[CLAM].partial==0)
assert(value.total==20040 and value.complete, 'exhausted lot values only two pearls and two meats')
-- A failed attempt with no loot window must not mark an untouched lot partial.
Catch()
local untouched=F.Containers.Queue()[1]
W.holdContainers=true; W.Key('G'); W.Advance(4); W.holdContainers=false
assert(untouched.n==1 and not untouched.partial and F.noteCounts['open-failed']==1)
value=F.Economy.Scope('session')
assert(value.total==20540 and value.complete, 'untouched clam stays provisional after a failed attempt')
-- A window yielding no items, with the shell retained, also stays untouched.
W.OpenContainer=function(b,s)realOpen(b,s,{take=function()return false end,keep=true})end
W.Key('G'); W.Advance(3); W.OpenContainer=realOpen
assert(untouched.n==1 and not untouched.partial)
assert(F.Economy.Scope('session').total==20540)
print('PASSED partial-lot exhaustion and failed-open behavior')
