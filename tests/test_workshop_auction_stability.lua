-- Keep delivering metadata AFTER completion: the old finish-then-restart fix
-- passed finite storms but cleared/reloaded forever under sustained delivery.
local c,g=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
local A,D=W.AuctionUI,W.AuctionBrowseData
local checks=0
local function same(a,b,why) checks=checks+1;assert(a==b,(why or "")..": "..tostring(a).." ~= "..tostring(b)) end
local raw={f=2,realm="Realm",side="Alliance",at=now,scope="full",complete=true,items={},n=6000,read=6000,used=6000}
for id=1,6000 do raw.items[id]=m.items[10] end
c.TwichUIWorkshopDB.markets[m.key]=raw
local info=c.C_Item.GetItemInfo
local late={}
c.C_Item.GetItemInfo=function(id)
    if late[id] then return late[id],nil,1,nil,nil,"Trade Goods","Herb",nil,nil,134572,40,7,nil,0 end
    return info(id)
end
local function Events(p,id)
    for i=1,6 do p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",id,true) end
    p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",9000000,true)
end
local function Settle(p,pressure)
    local ticks=0
    repeat
        if pressure then
            local known=p.job and p.job.seen or p.known
            local id=known and next(known)
            if id then Events(p,id) end
            A.Render()
        end
        FlushTimers();ticks=ticks+1;assert(ticks<3000,"eventual completion despite sustained metadata")
    until not p.job
    for i=1,10 do FlushTimers() end
    same(p.job,nil,"completion remains terminal")
end
for _,mode in ipairs({"browse","market"}) do
    A.Show();A.Go(mode)
    local p=A.Page(mode)
    if mode=="market" then A.Market.Filter("marketKey",m.key) end
    local starts=D.Stats().starts
    local job=p.job
    if mode=="browse" then A.Browse.Search("Item");A.Browse.Search("")
    else A.Market.Search("Item");A.Market.Search("") end
    same(p.job,job,"filters during discovery retain the catalog job")
    Settle(p,true)
    same(D.Stats().starts,starts,"filtering does not rediscover identities")
    same(#p.rows,6000)
    local token,rows=p.token,p.rows
    p.list.scroll:SetVerticalScroll(p.list.rowH*100+17);p.list:Layout()
    local top=p.rows[101].item
    A[mode=="browse" and "Browse" or "Market"].Select(p.rows[500].item)
    local selected=p.selected
    local paints=D.Stats().paints
    for i=1,100 do
        Events(p,10);p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");A.Render();FlushTimers()
        same(p.job,nil,"duplicate event pressure never reopens loading")
        same(p.rows,rows,"completed result ownership is stable")
    end
    same(p.token,token,"metadata does not create generations")
    same(D.Stats().paints,paints,"duplicate events do not reconstruct visible rows")
    local presentations,rowUpdates=D.Stats().paints,D.Stats().rowUpdates
    late[10]="Late Herb"
    Events(p,10);A.Render();FlushTimers()
    same(p.catalog[10].info.name,"Late Herb","affected row refreshed")
    same(p.selected,selected,"late metadata keeps selection")
    same(p.rows[math.floor(p.list.scroll:GetVerticalScroll()/p.list.rowH)+1].item,top)
    same(p.list.scroll:GetVerticalScroll()%p.list.rowH,17)
    same(D.Stats().paints,presentations,"offscreen metadata does not reconstruct visible rows")
    same(D.Stats().rowUpdates,rowUpdates,"offscreen metadata does not repaint unrelated rows")
    late[top]="Renamed visible item";Events(p,top);A.Render();FlushTimers()
    same(p.list.rows[1].name:GetText(),"Renamed visible item","only the affected visible frame is refreshed")
    same(D.Stats().paints,presentations,"visible row patches also avoid list reconstruction")
    local search=A[mode=="browse" and "Browse" or "Market"].Search
    search("Not Yet Known");Settle(p)
    same(#p.rows,0)
    late[11]="Not Yet Known";Events(p,11);A.Render();FlushTimers()
    same(#p.rows,1,"filtered-out identities can enter on late metadata")
    same(p.rows[1].item,11)
    -- A new saved generation keeps rows visible while refreshing once.
    raw.at=raw.at+1
    A.Render();same(p.list.data,p.rows,"refresh retains its viewport data")
    Settle(p,true)
    local completed=p.token
    for i=1,30 do Events(p,11);A.Render();FlushTimers() end
    same(p.token,completed,"generation refresh does not loop")
    for i=1,5 do A.Go("shopping");A.Go(mode);Settle(p,true) end
    A.Hide();same(p.catalog,nil);same(p.job,nil);same(D.Stats().active,0,"abandoned jobs released")
    late={}
end
-- Cancellation releases the coroutine and stale timer cannot adopt its rows.
A.Show();local p=A.Page("browse");local job=p.job
A.Go("shopping");same(job.done,true);same(job.error,"canceled")
for i=1,30 do FlushTimers() end
same(p.job,nil);same(#p.list.data,0)
A.Hide();same(D.Stats().active,0)
-- Exceptions after coroutine completion (late-row patching/painting) must also
-- reach a visible terminal state, not leave the old loading label stranded.
for _,mode in ipairs({"browse","market"}) do
    A.Show();A.Go(mode)
    local p=A.Page(mode);Settle(p)
    p.dirty={[10]=true}
    local info,fault=W.AdvisorData.Info,c.TwichUI.Fault
    local faults=0
    W.AdvisorData.Info=function() error("completion metadata failure") end
    c.TwichUI.Fault=function() faults=faults+1 end
    A[mode=="browse" and "Browse" or "Market"].Search("")
    Settle(p)
    same(p.error,"failed","completion callback terminates visibly")
    same(p.job,nil);same(faults,1,"callback fault reported once")
    W.AdvisorData.Info,c.TwichUI.Fault=info,fault
    A.Hide();same(D.Stats().active,0)
end
-- A late name enters between differently priced rows; membership preserves sort.
late={[10]="target",[11]="hidden",[12]="target"}
local catalog={}
for id=10,12 do catalog[id]=D.Row(id,m);catalog[id].unit=(id-9)*10 end
local projection={catalog=catalog,rows={catalog[10],catalog[12]},dirty={[11]=true},selected=10}
late[11]="target"
same(D.Patch(projection,{query="target"}),true)
same(projection.rows[2].item,11,"late filtered row inserted in unit-price order")
print("PASSED: Auction stability "..checks.." checks; 6000 items per page, sustained duplicate/late events")
