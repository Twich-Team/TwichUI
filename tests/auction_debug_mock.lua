-- Synthetic development/native adapter. Never touches actual gold or a client.
local c,g,Press=dofile(TESTS.."auction_mock.lua")
local R,W=c.TwichUI,c.TwichUI.Workshop
local s={visit=1,state="preparing",money=1000000,qty=5,deposit=2,commodity=false,calls={},owned={},browse={},items={},commodities={}}
c.GetTime=function() return s.now or 1 end
c.GetMoney=function() return s.money end
c.GetFramerate=function() return 60 end
c.Enum.PlayerInteractionType={Auctioneer=21};c.Enum.ItemCommodityStatus={Item=1,Commodity=2}
c.C_PlayerInteractionManager={IsInteractingWithNpcOfType=function() return s.connected~=false end,IsValidNPCInteraction=function() return s.connected~=false end}
c.InCombatLockdown=function() return s.combat==true end
R.AuctionBuild={verified={}}
local presentation=R.AuctionHost.Presentation
R.AuctionHost={Presentation=presentation,ReplacementFailed=function() s.state="blizzard";W.AuctionUI.Hide() end,DebugEnabled=function() return s.debug~=false end,
 Snapshot=function() return {state=s.state,leased=true,enabled=true,visit=s.visit,reason="test",openMS=1,switchMS=1} end,
 IsCurrent=function(id) return id==s.visit and s.connected~=false end,
 InterfaceHidden=function() end,ToBlizzard=function() s.state="blizzard";W.AuctionUI.Hide();return true end}
R.AuctionWindow={LifecycleBusy=function() return s.legacyBusy end}
local f=assert(loadfile(ROOT.."auction/Price.lua"));setfenv(f,c);f()
c.hooksecurefunc=function(target,name,callback)
 local original=target[name];assert(type(original)=="function",name)
 target[name]=function(...) local result={original(...)};callback(...);return unpack(result) end
end
local function Call(name,...)
 s.calls[#s.calls+1]={name=name,args={...}}
 if name=="StartCommoditiesPurchase" and s.syncQuote then W.AuctionActions.Event("COMMODITY_PRICE_UPDATED",103,309) end
 if s.syncComplete then
  if name=="PlaceBid" then W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED",(...))
  elseif name=="ConfirmCommoditiesPurchase" then W.AuctionActions.Event("COMMODITY_PURCHASE_SUCCEEDED")
  elseif name=="CancelAuction" then W.AuctionActions.Event("AUCTION_CANCELED",(...))
  elseif name=="PostCommodity" or name=="PostItem" or name=="ConfirmPostItem" then W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501) end
 end
 if name=="PostItem" or name=="PostCommodity" then return s.warning==true end
end
c.C_AuctionHouse={
 IsThrottledMessageSystemReady=function() return s.throttle~=false end,
 GetBrowseResults=function() return s.browse end,HasFullBrowseResults=function() return s.full~=false end,
 GetNumItemSearchResults=function() return #s.items end,GetItemSearchResultInfo=function(_,i) return s.items[i] end,HasFullItemSearchResults=function() return s.full~=false end,
 GetNumCommoditySearchResults=function() return #s.commodities end,GetCommoditySearchResultInfo=function(_,i) return s.commodities[i] end,HasFullCommoditySearchResults=function() return s.full~=false end,
 GetOwnedAuctions=function() return s.owned end,HasFullOwnedAuctionResults=function() return s.full~=false end,
 GetItemKeyInfo=function(k) return {itemName=g.names[k.itemID] or "Test item",isCommodity=s.commodity} end,
 GetItemKeyFromItem=function() return {itemID=10} end,IsSellItemValid=function() return s.eligible~=false end,
 GetAvailablePostCount=function() return s.qty end,GetItemCommodityStatus=function() return s.commodity and 2 or 1 end,
 SupportsCopperValues=function() return s.copper~=false end,CalculateItemDeposit=function() return s.deposit end,CalculateCommodityDeposit=function() return s.deposit end,
 GetAuctionInfoByID=function(id) for _,r in ipairs(s.items) do if r.auctionID==id then return {itemKey=r.itemKey,buyoutAmount=r.buyoutAmount} end end end,
 CanCancelAuction=function() return s.canCancel~=false end,GetCancelCost=function() return s.cancelCost or 0 end,GetQuoteDurationRemaining=function() return s.quoteRemaining or 10 end,
}
for _,name in ipairs({"SendBrowseQuery","SendSearchQuery","QueryOwnedAuctions","RequestMoreBrowseResults","RequestMoreItemSearchResults","RequestMoreCommoditySearchResults",
 "PlaceBid","StartCommoditiesPurchase","ConfirmCommoditiesPurchase","CancelCommoditiesPurchase","CancelAuction","PostItem","PostCommodity","ConfirmPostItem","ConfirmPostCommodity"}) do
 local method=name;c.C_AuctionHouse[method]=function(...) return Call(method,...) end
end
c.ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bag=bag,slot=slot} end}
c.C_Container={GetContainerNumSlots=function(bag) return bag==0 and 1 or 0 end,
 GetContainerItemInfo=function() return {itemID=s.bagItem or 10,stackCount=s.qty,isLocked=s.locked==true,isBound=s.bound==true,hyperlink="item:"..(s.bagItem or 10)..":0:0:0:0:0:0"} end}
W.AdvisorData.Reserved=function() return s.reserved or 0,false end
c.StaticPopupDialogs={AUCTION_HOUSE_POST_WARNING={OnAccept=function() end,OnHide=function() end}};c.StaticPopup_Hide=function() end
W.AuctionReads.AttachVisit(s.visit)
assert(W.AuctionUI.Prepare());assert(W.AuctionUI.ShowIntegrated(s.visit));s.state="twichui"
function s.Item(id,qty,total)
 s.items={{auctionID=id or 31,itemKey={itemID=10},quantity=qty or 3,buyoutAmount=total or 299,containsOwnerItem=false,containsAccountItem=false}}
 assert(W.AuctionReads.Begin("item",{itemID=10}));W.AuctionReads.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});return W.AuctionReads.snapshot.rows[1]
end
function s.Owned(id)
 s.owned={{auctionID=id or 42,itemKey={itemID=10},quantity=3,buyoutAmount=299,status=0}}
 assert(W.AuctionReads.Begin("owned"));W.AuctionReads.Event("OWNED_AUCTIONS_UPDATED");return W.AuctionReads.snapshot.rows[1]
end
function s.Count(name) local n=0;for _,x in ipairs(s.calls) do if x.name==name then n=n+1 end end;return n end
return c,W,s,Press,g
