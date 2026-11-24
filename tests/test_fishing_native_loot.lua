-- Native-order regressions: self-loot confirmations can precede LOOT_CLOSED,
-- and item links need not be ready at LOOT_READY. Real capture/accounting code,
-- synthetic client events: not a real-client test.
dofile(TESTS .. "fishing_mock.lua")
local c, W = FishingClient()
c.TwichUI.RunCommand("fish")
local F = c.TwichUI.Fishing
W.Wear(16, POLE)
local prices = { [CLAM] = 500, [PEARL] = 10000, [CLAMMEAT] = 20 }
c.TwichUI.Workshop = {
 Active = function() return true end,
 Pricing = { Generation = function() return 'native-loot' end,
  Source = function() return { reference = true, label = 'Synthetic reference', market = {key='Fixture|Alliance', at=1800000000} } end,
  Reference = function(id) return {market=prices[id], at=1800000000} end,
  Changed = function() end },
 Market = { Value = function() error('Do not mix markets') end },
}
local function Catch()
 W.StartLine(); W.Loot({{CLAM,1}}, {fishing=true}); W.StopLine(); W.Advance(3)
end
local function Window(slots, opts)
 opts=opts or {}
 local list={}
 for i,e in ipairs(slots) do list[i]={id=e[1],q=e[2]} end
 W.loot={slots=list}
 local read=c.GetLootSlotLink
 if opts.lateLinks then c.GetLootSlotLink=function()return nil end end
 c.FireEvent('LOOT_READY',true)
 c.GetLootSlotLink=read
 c.FireEvent('LOOT_OPENED',true,true)
 -- Native self-loot messages arrive while the window is open; no clear event
 -- is required. The slot and chat paths must converge on one item attribution.
 for i,e in ipairs(list) do
  if not opts.take or opts.take(i) then
   W.Put(e.id,e.q)
   if opts.clear and not opts.chatFirst then c.FireEvent('LOOT_SLOT_CLEARED',i) end
   c.FireEvent('CHAT_MSG_LOOT',e.q>1 and c.LOOT_ITEM_SELF_MULTIPLE:format(FISH_LINK(e.id),e.q) or c.LOOT_ITEM_SELF:format(FISH_LINK(e.id)))
   if opts.clear then c.FireEvent('LOOT_SLOT_CLEARED',i) end
  end
 end
 if opts.consume then W.Take(W.Find(CLAM)) end
 c.FireEvent('LOOT_CLOSED')
 c.FireEvent('LOOT_CLOSED')
 W.loot=nil;W.Settle();W.Advance(3)
end
Catch()
local sid=F.Session.Current().id
local zone=F.Session.Current().zone
local plan=assert(F.Containers.Plan(false))
F.Containers.BeginOpen(plan,'key')
Window({{PEARL,1},{CLAMMEAT,6}}, {consume=true,lateLinks=true})
local p=F.API.Provenance('session')
assert(p.contents[PEARL]==1 and p.contents[CLAMMEAT]==6, 'open-window self-loot lines confirm real contents')
assert(p.containers[CLAM].opened==1 and p.containers[CLAM].unopened==0)
assert(p.direct[CLAM]==nil and F.Session.Current().catches==1, 'opening is not another fishing catch')
assert(F.Session.Current().ctz[zone][CLAM].got[PEARL]==1, 'contents retain catch zone')
local model=F.CatchList.Model()
local shown={}
for _,row in ipairs(model.treasures)do if row.kind=='content'then shown[row.id]=row.q end end
assert(shown[PEARL]==1 and shown[CLAMMEAT]==6, 'confirmed contents populate Today\'s Catch treasures')
assert(F.Journal.Session(sid).contents[PEARL]==1 and F.Journal.Treasures().totals.items==7, 'Journal uses the same confirmed contents')
F.Economy.Scope('session'); W.Advance(1)
assert(F.Economy.Scope('session').total==10120, 'session estimate replaces opened shell with confirmed contents')
-- Clearing a slot and receiving its chat cannot also confirm an identical stack
-- that was left behind. Taken contents keep the whole partial lot conservative.
Catch();plan=assert(F.Containers.Plan(false));F.Containers.BeginOpen(plan,'key')
Window({{CLAMMEAT,1},{CLAMMEAT,1}}, {take=function(i)return i==2 end,clear=true,chatFirst=true})
p=F.API.Provenance('session')
assert(p.contents[CLAMMEAT]==7, 'clear+chat does not count an identical unlooted stack')
assert(p.containers[CLAM].partial==1 and p.containers[CLAM].unopened==1)
local value=F.Economy.Scope('session')
assert(value.total==10140 and not value.complete, 'partial shell is excluded beside confirmed contents')
-- Finish the shell later in another zone/session after a SavedVariables round trip.
c.TwichUI.RunCommand('fish stop')
local saved=FishRoundTrip(c.TwichUIFishingDB)
local c2,W2=FishingClient({db=saved,epoch=W.epoch+60})
W2.bags=W.bags;W2.equipped=W.equipped
c2.TwichUI.RunCommand('fish')
local F2=c2.TwichUI.Fishing
W2.map,W2.zone=1411,'Durotar'
W2.StartLine();W2.StopLine();W2.Advance(2)
local newer=F2.Session.Current().id
c,W,F=c2,W2,F2
plan=assert(F.Containers.Plan(false));F.Containers.BeginOpen(plan,'key')
Window({{CLAMMEAT,1}}, {consume=true,clear=true})
p=F.API.Provenance(sid)
assert(p.contents[PEARL]==1 and p.contents[CLAMMEAT]==8)
assert(p.containers[CLAM].opened==2 and p.containers[CLAM].unopened==0)
assert(F.API.Provenance(newer).contents[CLAMMEAT]==nil, 'later session does not steal original contents')
assert(F.Session.Find(sid).ctz[zone][CLAM].got[CLAMMEAT]==8, 'reload/zone move keeps origin')
assert(F.Journal.Session(sid).contents[CLAMMEAT]==8, 'completed Journal session includes late contents')
assert(F.Session.Find(sid).ctz[1411]==nil, 'open location is not a catch location')
-- Replayed close/chat after settlement cannot add items or reopen a lot.
c.FireEvent('LOOT_CLOSED');c.FireEvent('CHAT_MSG_LOOT',c.LOOT_ITEM_SELF:format(FISH_LINK(CLAMMEAT)));W.Advance(3)
assert(F.API.Provenance(sid).contents[CLAMMEAT]==8)
assert(#F.Containers.Queue()==0)
print('PASSED native-order container accounting, treasure model, valuation and reload provenance')
