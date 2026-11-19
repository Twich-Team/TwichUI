-- The rule builder's item test and bag survey: production reading and judging, nothing written.
local c=dofile(TESTS..'auction_mock.lua')
local R,W=c.TwichUI,c.TwichUI.Workshop
local L=R.WorkshopLauncher
local T=L.JunkTree
local enabled,combat,world=true,false,true
L.VendorJunkEnabled=function()return enabled end
R.Life={InWorld=function()return world end}
c.InCombatLockdown=function()return combat end
local timers={}
c.C_Timer.After=function(_,fn)timers[#timers+1]=fn end
local function Flush()
 for i=1,200 do local q=timers;timers={};for _,fn in ipairs(q)do fn()end;if #timers==0 then return end end
 error('did not settle')
end
local bags,prices,reserved,classes,quality,gearWear={},{},{},{},{},{}
local assignments,calls,repaints={},0,0
c.C_AddOns.IsAddOnLoaded=function()return true end
c.EllesmereUIDB={bagItemAssignments=assignments}
c.EUI_CategoryManager={JUNK_KEY='junk',IsJunkMarkerEnabled=function()return true end,
 IsJunk=function(_,id)return assignments[id]=='junk' end,
 AssignItem=function(_,id,key)calls=calls+1;assignments[id]=key end}
c.EUI_Bags={RefreshInventory=function()repaints=repaints+1 end,SellJunk=function()error('must not sell')end}
local function Load(path)local f=assert(loadfile(path));setfenv(f,c);f()end
Load(ROOT..'modules/EllesmereJunk.lua')
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=0
c.C_Container={GetContainerNumSlots=function()return #bags end,GetContainerItemInfo=function(_,slot)return bags[slot] end,
 GetContainerItemQuestInfo=function(_,slot)return {isQuestItem=bags[slot].quest==true}end}
c.C_Item.GetItemInfo=function(link)
 local id=tonumber(link:match('item:(%d+)'))
 return 'Item '..id,'item:'..id,quality[id] or 1,10,1,'',  '',1,'',134400,100,classes[id] or 7,0,0
end
c.C_Item.GetDetailedItemLevelInfo=function()return 10,nil,10 end
W.Session.PriceSource=function()return {}end
W.Facts.Of=function(id)return {recent=prices[id] and {value=prices[id],source='market_server'}}end
W.Disenchant.ForItem=function()return {state='unavailable'}end
W.AdvisorData.Reserved=function(id)return reserved[id] or 0,false end
local function Item(id,opt)
 local x={itemID=id,stackCount=1,isLocked=false,isBound=false,hyperlink='item:'..id}
 for k,v in pairs(opt or {})do x[k]=v end
 return x
end
Load(REPO..'TwichUI_Workshop/Junk.lua')
local J=W.Junk
J.Stop();enabled=false
local function Group(match,...) return {type='group',match=match,children={...}} end
local function Quality(a,b) return {type='quality',min=a,max=b} end
local function Rule(tree) return {on=true,tree=tree} end

-- A bag of different situations (class 7 materials unless noted; Vendor is recommended where a price is low).
bags={Item(301),Item(302),Item(303),Item(304,{quest=true}),Item(305),Item(305,{isLocked=true}),Item(211527),Item(306),Item(307)}
quality[301]=0;quality[302]=3;quality[303]=1;quality[306]=1;quality[307]=1
for _,id in ipairs({301,302,303,306,307})do prices[id]=50 end
prices[302]=500
classes[303]=2;classes[306]=2;classes[307]=2;reserved[307]=1
local rule=Rule(Group('all',{type='kind',value='materials'},Group('any',Quality(0,0),Quality(1,1))))

---------------------------------------------------------------- non-destructive
local function Snapshot() return calls..'|'..#timers..'|'..repaints end
local before=Snapshot()
local r=J.Inspect(0,1,rule)
assert(r.state=='ok' and r.item.id==301 and r.item.name=='Item 301' and r.item.icon==134400)
assert(r.verdict=='match' and r.vendor==true and r.advice=='vendor',r.verdict)
assert(r.trace[rule.tree]=='yes' and r.trace[rule.tree.children[1]]=='yes' and r.trace[rule.tree.children[2].children[1]]=='yes' and r.trace[rule.tree.children[2].children[2]]=='no')
assert(r.marker=='markable' and r.reserved==0)
assert(Snapshot()==before and next(assignments)==nil,'inspecting marks nothing, schedules nothing, repaints nothing')
assert(J.Inspect(0,1,rule).verdict=='match','repeatable')

---------------------------------------------------------------- the four answers
r=J.Inspect(0,2,rule);assert(r.verdict=='nomatch' and r.trace[rule.tree]=='no','quality 3 is outside Poor/Common')
r=J.Inspect(0,2,Rule(Group('all',{type='wearable',value=false})));assert(r.verdict=='nomatch' or r.verdict=='unknown')
-- a gear item whose wearability the tooltip could not read is "cannot determine", never a guess
r=J.Inspect(0,3,Rule(Group('all',{type='kind',value='gear'},{type='wearable',value=false})))
assert(r.verdict=='unknown' and r.trace[rule.tree]==nil)
local unknownNodes=0;for node,v in pairs(r.trace) do if v=='unknown' then unknownNodes=unknownNodes+1 end end;assert(unknownNodes>=1)
r=J.Inspect(0,4,rule);assert(r.verdict=='blocked' and r.block=='quest','quest item is never a candidate')
r=J.Inspect(0,5,rule);assert(r.verdict=='blocked' and r.block=='locked','another copy is locked: the whole ID is vetoed')
r=J.Inspect(0,7,Rule(Group('all',Quality(0,5))));assert(r.verdict=='protected' and r.why=='cozy','Cozy Sleeping Bag')
assert(L.SetJunkIgnored(301,true))
r=J.Inspect(0,1,rule);assert(r.verdict=='protected' and r.why=='never','Never mark beats a matching rule');L.SetJunkIgnored(301,false)
R.MageSell={IsExcluded=function(id)return id==302 end};r=J.Inspect(0,2,rule);assert(r.verdict=='protected' and r.why=='mage');R.MageSell=nil
R.Restock={Protects=function(id)return id==302 end};r=J.Inspect(0,2,rule);assert(r.verdict=='protected' and r.why=='restock');R.Restock=nil
assert(J.Inspect(0,99,rule).state=='empty')
assert(J.Inspect(0,1,{on=true}).state=='unavailable','no tree, no answer')
c.C_Item.GetItemInfo=function() return nil end
r=J.Inspect(0,1,rule);assert(r.verdict=='blocked' and r.block=='unknown','item data not loaded yet is reported, not guessed')
c.C_Item.GetItemInfo=function(link)
 local id=tonumber(link:match('item:(%d+)'))
 return 'Item '..id,'item:'..id,quality[id] or 1,10,1,'','',1,'',134400,100,classes[id] or 7,0,0
end

---------------------------------------------------------------- the advisor and reservations are reported, not applied to the rule
local any=Rule(Group('all',Quality(0,5)))
r=J.Inspect(0,2,any);assert(r.verdict=='match' and r.vendor==false and r.advice=='auction','rule matches but Workshop recommends the Auction House')
r=J.Inspect(0,9,any);assert(r.verdict=='match' and r.reserved==1,'reserved for crafting is shown')

---------------------------------------------------------------- the test and marking agree
-- Save the same rule, run the real scan, and compare every item.
db=c.TwichUIDB
L.JunkTemplate(1,'custom');db.ui.workshopJunk.rules.rows={L.NewJunkRule('Same')}
local saved=L.JunkRules();local row=saved[1];row.on=true;row.tree=rule.tree
assert(L.SaveJunkRule(1,row,L.JunkRules()))
bags={Item(301),Item(302),Item(303),Item(306),Item(307),Item(308)}
quality[308]=0;prices[308]=50;classes[308]=7
enabled=true;J.Start();Flush()
for slot,x in ipairs(bags) do
    local seen=J.Inspect(0,slot,rule)
    local expect=seen.verdict=='match' and seen.vendor==true and seen.reserved==0 and seen.marker~='unavailable'
    assert((assignments[x.itemID]=='junk')==expect,'item '..x.itemID..': test says '..tostring(expect)..', marking '..tostring(assignments[x.itemID]))
end
assert(assignments[301]=='junk' and assignments[308]=='junk' and not assignments[302] and not assignments[307])

---------------------------------------------------------------- survey: counts distinct items, slices work, newer cancels older
enabled=false;J.Stop()
bags={};for i=1,70 do bags[i]=Item(400+(i%7))end
for i=0,6 do quality[400+i]=i%2==0 and 0 or 3;classes[400+i]=7 end
local result;assert(J.Survey(rule,function(x)result=x end))
assert(result==nil and #timers>0,'a long bag is surveyed in slices')
Flush();assert(result and result.items==7 and result.match==4 and result.unknown==0,('items %s match %s'):format(tostring(result and result.items),tostring(result and result.match)))
assert(#result.names<=5)
local calls0=calls
result=nil;J.Survey(rule,function(x)result=x end);J.Survey(Rule(Group('all',Quality(5,5))),function(x)result=x end);Flush()
assert(result.match==0,'only the newer survey reports')
assert(calls==calls0 and next(assignments)~=nil)
L.SetJunkIgnored(400,true);result=nil;J.Survey(rule,function(x) result=x end);Flush();assert(result.protected==1,'protected items are counted apart')
result=nil;J.Survey({on=true},function(x) result=x end);assert(result.unavailable)
print('PASSED junk item test: non-destructive, four answers, protections, advisor report, agreement with marking, survey')
