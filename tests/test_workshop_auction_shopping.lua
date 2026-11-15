local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W=c.TwichUI.Workshop
local A,P,S=W.AuctionUI,W.AuctionShoppingData,W.Session
local n=0
local function same(a,b,msg) n=n+1;assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local function settle() for i=1,45 do FlushTimers() end end
local function rec(id) for _,r in ipairs(S.Current().recipes) do if r.id==id then return r end end end
local function basic(item,qty) return {reagentType=1,reagents={{itemID=item}},quantityRequired=qty,required=true} end
local function row(item,kind) for _,v in ipairs(A.Page("shopping").rows) do if v.row.item==item and (not kind or v.row.kind==kind) then return v end end end
local function digest(t)
 if type(t)~="table" then return tostring(t) end
 local keys={};for k in pairs(t) do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..":"..digest(t[k]) end
 return "{"..table.concat(out,";").."}"
end
c.time=function() return 1700000000 end;c.GetRealmName=function() return "Realm" end
c.C_AuctionHouse=setmetatable({},{__index=function(_,key)return function() error("forbidden AH operation "..key)end end})
g.names={[20]="Metal Bar",[30]="Ore",[40]="Thread",[50]="Stored Rune",[60]="Unknown Dust",[90]="Sword"}
g.recipes={[1]={name="Sword",diff=1},[500]={name="Smelt Bar",diff=1}}
g.schem[1]={outputItemID=90,quantityMin=1,quantityMax=1,reagentSlotSchematics={basic(20,4),basic(30,2),basic(40,1),basic(50,1),basic(60,1)}}
g.schem[500]={outputItemID=20,quantityMin=1,quantityMax=1,reagentSlotSchematics={basic(30,2)}}
g.filtered={1,500};g.bags={[20]=0,[30]=3,[40]=0,[50]=0,[60]=0,[90]=0}
same(S.Observe(),true);for _,r in ipairs(S.Current().recipes) do W.Observe.Fill(r) end
same(S.Add(rec(1)),true)
local b=W.Prices.NewBatch();b:Add(20,99,250*99,true);b:Add(30,99,100*99,true)
local items,count=b:Items()
c.TwichUIWorkshopDB={v=2,markets={["Realm|Alliance"]={f=2,realm="Realm",side="Alliance",scope="full",complete=true,at=c.time()-3600,items=items,n=count,read=2,used=2}}}
same(W.Vendor.Observe({{id=40,price=10,stack=1,avail=-1}},{[40]=true},1234),1)
same(W.Storage.StoreBank({ids={6},tabs={[6]={[50]=1}},incomplete=0},c.time()-7200),true)
A.Show();A.Go("shopping");settle()
local p=A.Page("shopping")
same(p.state,"ready");same(W.Strategy.ListenerCount(),1);same(W.Storage.ListenerCount(),1)
local kinds={};for _,v in ipairs(p.rows) do kinds[v.source]=true end
for _,k in ipairs({"auction","vendor","make","collect","none"}) do same(kinds[k],true,"source "..k) end
same(row(30).missing,7,"whole chain: ten Ore needed minus three in bags")
same(row(30).have,3);same(row(30).need,10)
same(row(50).have,0,"bank is not bags");same(row(50).missing,1,"collect stock separately")
same(row(60).row.cash,nil,"unknown cost is not zero")
same(p.detail.buy:IsEnabled(),false,"purchasing has no active action")
local sharedPlan,sharedCtx,state=S.ShoppingPlan()
for _,v in ipairs(p.rows) do
 local found
 for _,r in ipairs(sharedPlan.rows) do if P.Key(r)==v.key then found=r end end
 same(v.need,found.need,"shared required quantity");same(v.have,found.have,"shared bag count");same(v.missing,found.qty,"shared missing quantity")
end
local dbBefore,marketBefore=digest(c.TwichUIDB),digest(c.TwichUIWorkshopDB)
A.Render();A.Render()
same(digest(c.TwichUIDB),dbBefore,"render does not persist another plan")
same(digest(c.TwichUIWorkshopDB),marketBefore,"render does not write observations")
same(g.bags[30],3,"inventory untouched")
-- A player's existing source choice remains authoritative in both windows.
S.PickSource(20,"auction");settle()
same(S.picks[20],"auction");same(row(20).source,"auction","shared source decision")
-- A selected shopping requirement prepares a historical Browse inspection only.
for _,r in ipairs(p.list.rows) do if r.data and r.data.row.item==20 then Press.Must(r);break end end
local target=p.detail.data.row.item
local queue,picks=digest(W.Queue.Entries()),digest(S.picks)
Press.Must(p.detail.market);settle()
same(A.Mode(),"market");same(A.Page("market").selected,target,"Shopping preserves material identity")
same(digest(W.Queue.Entries()),queue,"Market inspection leaves crafting queue unchanged")
same(digest(S.picks),picks,"Market inspection leaves acquisition decisions unchanged")
A.Go("shopping");settle()
Press.Must(p.detail.browse);settle()
same(A.Mode(),"browse");same(A.Page("browse").forceItem,target)
same(W.Strategy.ListenerCount(),1,"Shopping observer released; Browse owns one visible source observer")
same(W.Storage.ListenerCount(),0)
same(W.Queue.Count(),1,"navigation does not consume requirements")
A.Go("shopping");settle()
-- Queue and bag updates refresh via the shared services.
S.SetCrafts(1,2);settle();same(row(20).missing,8,"queue change recomputes")
g.bags[20]=8;p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");settle()
same(row(20),nil,"fulfilled item disappears after actual bag observation")
same(W.Queue.Count(),1,"fulfilled rows never delete crafts")
-- Stock writes notify independently of Workshop's existing callback.
local originalCallback=W.Storage.OnChange;local called=0
W.Storage.OnChange=function() called=called+1 end
W.Storage.StoreBank({ids={6},tabs={[6]={[50]=2}},incomplete=0},c.time());settle()
same(called,1,"legacy callback preserved");same(row(50).missing,2,"new stock seen")
W.Storage.OnChange=originalCallback
-- Unknown bag counts and recipe materials never look like a fulfilled list.
local held=g.bags[40];g.bags[40]=nil
p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");settle()
same((p.plan.unknownBags or 0)>0,true,"shared planner reports unknown stock")
same(p.total:GetText():find("Known requirements only",1,true)~=nil,true,"partial stock total qualified")
g.bags[40]=held;p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");settle()
W.Queue.Add({id=999,name="Unresolved recipe",prof=171,profName="Alchemy"},1);W.Strategy.Bump();settle()
same(p.ctx.summary.unknown>0,true,"unread recipe remains unknown")
same(p.total:GetText():find("Known requirements only",1,true)~=nil,true,"unresolved recipe total qualified")
W.Queue.Remove(999);W.Strategy.Bump();settle()
same(P.Incomplete({rows={},unknownBags=1},{}),true,"unknown empty requirements are incomplete")
same(P.Total({rows={},unknownBags=1,totals={cash=0}},tostring):find("data missing",1,true)~=nil,true)
-- Planning and basic fallback are explicitly qualified by the presentation.
local real=S.ShoppingPlan
local plan,ctx=real();local stale={};for k,v in pairs(ctx) do stale[k]=v end;stale.stale=true
S.ShoppingPlan=function()return plan,stale,"planning"end
A.Render();same(p.current,false);same(p.detail.browse:IsEnabled(),false);same(p.detail.recipe:IsEnabled(),false)
same(p.status:GetText():find("Updating",1,true)~=nil,true)
S.ShoppingPlan=function()return plan,ctx,"basic"end
A.Render();same(p.status:GetText():find("Basic",1,true)~=nil,true);same(p.current,true)
S.ShoppingPlan=function()return {rows={},unknownBags=1,totals={}},ctx,"ready"end
A.Render();same(p.detail.name:GetText(),"Requirements unavailable","unknown empty list never says fulfilled")
same(p.list.empty:GetText():find("cannot be counted",1,true)~=nil,true)
S.ShoppingPlan=real
-- Group/filter projection never edits quantities or totals.
local input={rows={{item=20,need=9,have=2,qty=7,kind="buy",source="auction",cash=70},{item=50,need=4,have=nil,qty=4,kind="collect",where="bank"}},totals={cash=70,low=70,high=70,priced=1,missing=0,makes=0}}
local v=P.Rows(input,{}, {source="collect",group="purpose"})
same(#v,1);same(v[1].missing,4);same(v[1].have,nil,"unknown stays unknown");same(v[1].row,input.rows[2],"row is the shared row")
same(P.Cost(input.rows[2],tostring),"Already owned")
same(P.Cost({kind="buy",cash=5,costState="range",low=5,high=9},tostring),"from 5","uncertain range is qualified")
same(P.Total(input,tostring),"Estimated spending: 70")
same(P.State(input,{stale=true},"ready"),"Updating plan · previous quantities may be stale")
local frames=#c.testFrames
for i=1,30 do A.Go("browse");A.Go("shopping");settle() end
same(W.Strategy.ListenerCount(),1);same(W.Storage.ListenerCount(),1)
same(#c.testFrames,frames,"stable frame pool")
A.Hide();settle();same(W.Strategy.ListenerCount(),0);same(W.Storage.ListenerCount(),0)
same(p.plan,nil);same(p.ctx,nil);same(#p.list.data,0)
-- Saved queue is the existing source of truth on reopening.
W.Queue.Unload();A.Show();A.Go("shopping");settle();same(W.Queue.Entries()[1].crafts,2)
same(S.picks[20],"auction","preview lifecycle preserves shared decisions")
A.Hide()
print("PASSED: Auction Shopping "..n.." checks")
