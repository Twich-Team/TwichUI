-- Real Advisor + EllesmereJunk adapter over synthetic bags and timer events.
local c=dofile(TESTS..'auction_mock.lua')
local R,W=c.TwichUI,c.TwichUI.Workshop
local enabled,combat,world,available=false,false,true,true
local L=R.WorkshopLauncher
L.VendorJunkEnabled=function()return enabled end
R.Life={InWorld=function()return world end}
c.InCombatLockdown=function()return combat end
local timers={}
c.C_Timer.After=function(_,fn)timers[#timers+1]=fn end
local function Flush()
 for i=1,100 do local q=timers;timers={};for _,fn in ipairs(q)do fn()end;if #timers==0 then return end end
 error('junk marking did not settle')
end
local bags,prices,des,reserved,classes={},{},{},{},{}
local assignments,calls,repaints={},0,0
c.C_AddOns.IsAddOnLoaded=function()return available end
c.EllesmereUIDB={bagItemAssignments=assignments}
c.EUI_CategoryManager={JUNK_KEY='junk',IsJunkMarkerEnabled=function()return true end,
 IsJunk=function(_,id)return assignments[id]=='junk' end,
 AssignItem=function(_,id,key)calls=calls+1;assignments[id]=key end}
c.EUI_Bags={RefreshInventory=function()repaints=repaints+1 end, SellJunk=function()error('must not sell')end}
local function Load(path)local f=assert(loadfile(path));setfenv(f,c);f()end
Load(ROOT..'modules/EllesmereJunk.lua')
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=0
c.C_Container={GetContainerNumSlots=function()return #bags end,GetContainerItemInfo=function(_,slot)return bags[slot]end,
 GetContainerItemQuestInfo=function(_,slot)return {isQuestItem=bags[slot].quest==true}end}
c.C_Item.GetItemInfo=function(link)
 local id=tonumber(link:match('item:(%d+)'))
 return 'Fixture','item:'..id,1,10,1,'Trade Goods','',1,'',1,100,classes[id] or 7,0,0
end
c.C_Item.GetDetailedItemLevelInfo=function()return 10,nil,10 end
W.Session.PriceSource=function()return {}end
W.Facts.Of=function(id)return {recent=prices[id] and {value=prices[id],source='market_server'}}end
W.Disenchant.ForItem=function(f)return des[f.item] or {state='unavailable'}end
W.AdvisorData.Reserved=function(id)return reserved[id] or 0,false end
local function Item(id,opt)
 local x={itemID=id,stackCount=1,isLocked=false,isBound=false,hyperlink='item:'..id}
 for k,v in pairs(opt or {})do x[k]=v end
 return x
end
Load(REPO..'TwichUI_Workshop/Junk.lua')
local J=W.Junk
assert(J.Events()==0 and #timers==0 and calls==0,'off by default must do no work')
bags={Item(101),Item(102),Item(103),Item(104,{quest=true}),Item(105,{isLocked=true}),Item(106),Item(107)}
prices[101]=50;prices[102]=500;prices[103]=50;prices[106]=50;prices[107]=50
des[103]={state='ok',expectedGross=1000,value=1000}
assignments[106]='my-category';reserved[107]=1
enabled=true;J.Start();Flush()
assert(assignments[101]=='junk' and calls==1,'only Vendor should be marked')
assert(not assignments[102] and not assignments[103],'Auction and Disenchant must not be marked')
assert(not assignments[104] and not assignments[105] and not assignments[107],'quest, locked and reserved items must remain')
assert(assignments[106]=='my-category' and repaints==1,'custom categories must remain and repaint only after marking')
J.Request();Flush();assert(calls==1 and #timers==0,'idle must settle without repeat marks')
assignments[101]=nil;J.Request();Flush();assert(not assignments[101] and calls==1,'respect manual unmarking')
bags={Item(108),Item(108,{isLocked=true})};J.Request();Flush()
assert(not assignments[108],'one unsafe copy vetoes the whole item ID')
bags={Item(109)};combat=true;J.Request();Flush();assert(not assignments[109])
combat=false;J.Request();Flush();assert(assignments[109]=='junk','resume after combat')
bags={Item(110)};available=false;J.Request();Flush();assert(not assignments[110])
available=true;world=false;J.Request();Flush();assert(not assignments[110])
world=true;J.Request();J.Stop();Flush();assert(not assignments[110] and J.Events()==0,'stop cancels pending work')
J.Start();J.Stop();J.Start();Flush();assert(assignments[110]=='junk','restart discards older timer callbacks')
bags={};for i=1,80 do bags[i]=Item(111)end
J.Request();local q=timers;timers={};for _,fn in ipairs(q)do fn()end
assert(not assignments[111] and #timers>0,'inventory work must yield before marking')
bags[1].isLocked=true;J.Request();Flush();assert(not assignments[111],'changed bags invalidate an in-flight scan')
enabled=false;J.Stop();J.Request();Flush();assert(J.Events()==0 and #timers==0)
assert(assignments[109]=='junk','disabling never unmarks existing EllesmereUI marks')
enabled=true;bags={Item(112),Item(113)}
R.MageSell={IsExcluded=function(id)return id==112 end}
R.Restock={Protects=function(id)return id==113 end}
J.Start();Flush();assert(not assignments[112] and not assignments[113],'never-sell and restock protections apply')
R.MageSell=nil;R.Restock=nil
bags={Item(114)};W.suspended=true;J.Start();Flush();assert(not assignments[114] and J.Events()==0,'Workshop suspension stops marking')
W.suspended=nil;J.Start();Flush();assert(assignments[114]=='junk')
-- Ignore IDs and type filters veto all copies, including new arrivals after reload.
bags={Item(201),Item(201),Item(211527),Item(202),Item(203),Item(204),Item(205)}
classes[202]=9;classes[203]=0;classes[204]=15;classes[205]=2
assert(L.SetJunkIgnored(201,true));Flush()
assert(not assignments[201] and not assignments[211527], 'ignored and Cozy Sleeping Bag must never be marked')
assert(not assignments[202] and not assignments[203] and not assignments[204], 'recipes, consumables and other types default off')
assert(assignments[205]=='junk','gear remains eligible')
assert(L.SetJunkFilter('recipes',true));Flush();assert(assignments[202]=='junk')
assert(L.SetJunkFilter('other',true));Flush();assert(assignments[204]=='junk' and not assignments[211527])
assert(L.SetJunkFilter('consumables',true));Flush();assert(assignments[203]=='junk')
assert(L.SetJunkIgnored(201,false));Flush();assert(assignments[201]=='junk')
bags={Item(206),Item(207),Item(208)};classes[206]=12;classes[207]=13;classes[208]=2
assert(L.SetJunkFilter('gear',false));Flush()
assert(not assignments[206] and not assignments[207] and not assignments[208],'quest classes, keys and disabled gear protected')
-- A settings edit during a yielded inventory scan invalidates the old candidate job.
bags={};for i=1,80 do bags[i]=Item(209)end
J.Request();local q=timers;timers={};for _,fn in ipairs(q) do fn() end
assert(L.SetJunkIgnored(209,true));Flush();assert(not assignments[209],'ignore cancels stale slices')
assert(L.SetJunkFilter('materials',false));bags={Item(210)};J.Request();Flush();assert(not assignments[210])
print('PASSED Workshop junk: actual sale policy, adapter, all-copy veto, opt-in, categories, manual unmark, combat, lifecycle and stale slices')
