local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m=dofile(TESTS.."auction_market_fixture.lua")(c)
local A,D,Q=W.AuctionUI,W.AuctionBrowseData,W.AuctionReads
local n=0
local function same(a,b,why) n=n+1;assert(a==b,(why or "")..": "..tostring(a).." ~= "..tostring(b)) end
local function Settle() for i=1,3000 do FlushTimers();local p=A.Page("browse");if not p or not p.job then return end end;error("catalog timeout") end
c.AuctionCategories={{name="Weapons and exceptionally long native category labels",filters={{classID=2}},
 subCategories={{name="One-handed weapons",filters={{classID=2,subClassID=0}},subCategories={{name="Swords",filters={{classID=2,subClassID=7}}}}}}}}
local calls=0
c.C_AuctionHouse=setmetatable({GetItemKeyInfo=function() return nil end},{__index=function() return function() calls=calls+1;error("unexpected native request") end end})
A.Show();Settle();local p=A.Page("browse")
same(p.submit.text:GetText(),"Search Saved Data","saved search has an honest action label")
same(p.filters:GetWidth(),222);same(p.categoryList.rowH,42)
same(p.categoryList.rows[2].arrow:GetText(),"›","collapsed category chevron")
A.Browse.Filter("category","native:1.1.1");Settle()
same(p.expanded["native:1"],true);same(p.expanded["native:1.1"],true)
same(p.categoryList.rows[2].arrow:GetText(),"▾","expanded category chevron")
same(p.categoryList.data[#p.categoryList.data].name,"Swords","dropdown selection reveals the side-tree path")
same(p.categoryDrop.text:GetText():find("Swords",1,true)~=nil,true)
same(p.category,"native:1.1.1")
same(p.categoryTree[1].name,c.AuctionCategories[1].name,"native names retained intact")
same(p.categoryList.rows[#p.categoryList.data].data.name,"Swords","subcategory row is populated")
local texture={SetTexture=function(self,file) self.file=file end,SetTexCoord=function(self,...) self.coords={...} end}
W.UI.Art(texture,"auction:weapon-one-hand-sword",28)
same(texture.file,c.TwichUI.PATH..[[media\auction\categories\weapon-one-hand-sword]],"28px Browse row uses full subcategory art")
same(table.concat(texture.coords,","),"0,1,0,1","subcategory artwork is not cropped")
W.UI.Art(texture,"auction:cloth-head",22)
same(texture.file,c.TwichUI.PATH..[[media\auction\categories\cloth-head-small]],"small consumers use the 32px artwork")
local rows={
 [10]={item=10,info={name="Cedar"},unit=100},
 [11]={item=11,info={name="Birch"},unit=200},
 [12]={item=12,info={name="Aspen"}},
}
for _,case in ipairs({{{reverse=true},{11,10,12}},{{sort="Name"},{12,11,10}},{{},{10,11,12}}}) do
    local opt=case[1];opt.catalog=rows
    local job=D.Job(opt);while not job:Step() do end
    for i,id in ipairs(case[2]) do same(job.rows[i].item,id,"sort and unknown-price placement") end
end
same(Q.BrowseQuery({text=string.rep("a",201)}),nil)
same(Q.BrowseQuery({minLevel=20,maxLevel=10}),nil)
same(Q.BrowseQuery({minLevel="bad"}),nil)
local secret={};c.issecretvalue=function(v) return v==secret end
same(Q.Key({itemID=10,itemSuffix=secret}),nil,"secret suffix is not collapsed to zero")
same(Q.Key({itemID=secret}),nil)
same(Q.Listing({auctionID=1,itemKey={itemID=10},quantity=1,buyoutAmount=10,containsOwnerItem=secret,containsAccountItem=false}).ownershipKnown,false)
c.issecretvalue=nil
Press.Must(p.live);same(calls,0,"preparing a gated query never sends an automatic request")
local available=Q.Available;Q.Available=function() return true end
local begin=Q.Begin;Q.Begin=function() return true end
A.Browse.Search("");local abandoned=p.job
assert(abandoned,"local projection is still pending")
Press.Must(p.live)
same(abandoned.done,true,"switching to explicit live mode cancels the pending saved job")
same(p.job,nil);same(D.Stats().active,0,"abandoned live-switch discovery is accounted for")
A.Browse.Filter("quality",2);Settle()
same(p.liveMode,false,"local filters return to explicitly labeled saved research")
Q.Begin=begin
A.Browse.Filter("quality",-1);A.Browse.Filter("category","all");Settle()
Q.snapshot={kind="item",epoch=Q.epoch,at=c.GetTime(),complete=true,rows={{auctionID=71,item=10,
 itemKey={itemID=10,itemLevel=0,itemSuffix=4,battlePetSpeciesID=0},qty=3,total=299,unit=100}}}
Q.state="results";p.liveMode=true;A.Render()
same(p.list.rows[1].total:GetText(),W.UI.Money(299),"exact totals survive normalized unit rounding")
same(Q.snapshot.rows[1].info,nil,"view metadata never mutates the broker snapshot")
same(p.detail.recommendation.text,"Variant-specific advice unavailable")
same(p.detail.buy:IsEnabled(),false)
local selected=p.selected
local info=c.C_Item.GetItemInfo
c.C_Item.GetItemInfo=function() return "Late live name",nil,1,nil,nil,"Trade Goods","Herb",nil,nil,134572,40,7,nil,0 end
p:GetScript("OnEvent")(p,"ITEM_KEY_ITEM_INFO_RECEIVED",10)
A.Render();same(p.rows[1].info.name,"Late live name");same(p.selected,selected)
c.C_Item.GetItemInfo=info
Q.epoch=Q.epoch+1;A.Render();same(#p.rows,0,"previous-session snapshots cannot reappear")
same(p.detail.buy:IsEnabled(),false);same(calls,0)
Q.Available=available;A.Hide()
print("PASSED: Browse controls "..n.." checks")
