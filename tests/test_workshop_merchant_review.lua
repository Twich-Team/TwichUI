-- Synthetic live quote and lifecycle; never authorizes or simulates a purchase.
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local W = {}
TwichUI = { Workshop = W }
dofile(REPO .. 'TwichUI_Workshop/Data.lua')
local active, held, combat, shown = true, false, false, true
W.Active = function() return active end
W.Queue = { Held = function() return held end }
local callbacks, frames, listeners = {}, {}, {}
C_Timer = { After = function(_, fn) callbacks[#callbacks+1] = fn end }
local function flush()
    local c = callbacks; callbacks = {}; for _, fn in ipairs(c) do fn() end
end
local function fake()
    local f = { shown = false, scripts = {}, events = {} }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:RegisterEvent(k) self.events[k] = true end
    function f:UnregisterAllEvents() self.events = {} end
    function f:Show() self.shown = true end
    function f:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide() end end
    function f:IsShown() return self.shown end
    function f:SetText(v) self.text = v end
    function f:SetTexture(v) self.texture = v end
    for _, k in ipairs({'SetPoint','SetSize','SetWidth','SetWordWrap','SetFrameStrata','SetClampedToScreen','EnableMouse'}) do f[k] = function() end end
    return f
end
CreateFrame = function(_, name) local f=fake();frames[#frames+1]=f; if name then _G[name]=f end; return f end
UIParent, UISpecialFrames = {}, {}
MerchantFrame = { IsShown = function() return shown end }
InCombatLockdown = function() return combat end
local guid = 'Creature-0-0-0-0-1-000'
UnitGUID = function() return guid end
GetMoney = function() return 10 end
local live = {
    {id=10,price=5,stackCount=2,numAvailable=-1,isPurchasable=true,hasExtendedCost=false},
    {id=11,price=7,stackCount=1,numAvailable=0,isPurchasable=false,hasExtendedCost=false},
    {id=12,price=9,stackCount=1,numAvailable=-1,isPurchasable=true,hasExtendedCost=true},
}
GetMerchantNumItems = function() return #live end
GetMerchantItemID = function(i) return live[i].id end
C_MerchantFrame = { GetItemInfo = function(i) return live[i] end }
GetMerchantItemCostInfo = function() return 0 end
BuyMerchantItem = function() error('No purchase API may be called by a quote') end
local plan = { rows = {{kind='buy',have=0,item=10,qty=5},{kind='buy',have=0,item=11,qty=3},{kind='buy',have=0,item=12,qty=2},{kind='buy',have=0,item=13,qty=4},{kind='make',item=14,qty=9}} }
local state = 'ready'
W.Session = { ShoppingPlan = function() return plan, {}, state end }
local bumped = 0
W.Strategy = { Bump = function() bumped = bumped + 1 end, Listen = function(fn,on) listeners[fn] = on and true or nil end }
W.Observe = { ItemFacts = function(id) return 'Material '..id, 134400, 2 end }
W.UI = { K = {text={},textDim={},bronzeText={}}, ICON_BLANK=134400, Init=function() end, Panel=function() end,
    Text=function() return fake() end, Button=function() return fake() end, Money=tostring,
    Paint=function() end, ItemQuality=function() end, ItemIcon=function() local f=fake(); f.tex=fake(); return f end,
    List=function(parent, _, make)
        local list={box=fake(),rows={}}
        function list:SetData(rows)
            for i,r in ipairs(rows) do self.rows[i]=self.rows[i] or make(parent); self.rows[i]:fill(r) end
            self.data=rows
        end
        return list
    end }
dofile(REPO .. 'TwichUI_Workshop/MerchantReview.lua')
local M=W.MerchantReview
flush()
local q=M.Quote(plan,assert(M.Read()),state)
eq(#q.rows,4);eq(q.total,10);eq(q.rows[1].qty,4);eq(q.rows[2].status,'Sold out');eq(q.rows[3].qty,0);eq(q.rows[4].qty,0)
eq(TwichUIWorkshopMerchantQuote:IsShown(),true)
eq(TwichUIWorkshopMerchantQuote.quote.total,10)
-- Limited stock counted conservatively as units; never round beyond need.
live[1].numAvailable=3
q=M.Quote(plan,M.Read(),state);eq(q.rows[1].qty,2);eq(q.total,5)
plan.rows[1].qty=1
q=M.Quote(plan,M.Read(),state);eq(q.rows[1].qty,0)
-- Pending needs and unknown bags do not quote old plans.
eq(#M.Quote(plan,M.Read(),'planning').rows,0)
plan.unknownBags=1;eq(#M.Quote(plan,M.Read(),'ready').rows,0);plan.unknownBags=0
-- Unknown nested ownership (including a made intermediate) refuses the whole quote.
plan.rows[1].have=nil;eq(#M.Quote(plan,M.Read(),'ready').rows,0);plan.rows[1].have=0
plan.rows[5].line={countsUnknown=true};eq(#M.Quote(plan,M.Read(),'ready').rows,0);plan.rows[5].line=nil
-- Secret or missing money metadata refuses quote for that listing.
issecretvalue=function(v) return v == 'SECRET' end
live[1].price='SECRET';eq(M.Read()[10].eligible,false);live[1].price=5
live[1].currencyID='SECRET';eq(M.Read()[10].eligible,false);live[1].currencyID=nil
live[1].hasExtendedCost=nil;eq(M.Read()[10].eligible,false);live[1].hasExtendedCost=false
-- Merchant identity changed during live read: no quote.
local original=C_MerchantFrame.GetItemInfo
C_MerchantFrame.GetItemInfo=function(i) guid='other';return original(i) end
guid='original';eq(M.Read(),nil);C_MerchantFrame.GetItemInfo=original
-- Rows are capped and truncation explicit.
local big={rows={}};for i=1,520 do big.rows[i]={kind='buy',have=0,item=i,qty=1} end
q=M.Quote(big,{},'ready');eq(#q.rows,512);eq(q.truncated,true)
-- Close/combat/consent and cancellation invalidate scheduled callbacks.
local eventFrame=frames[1]
eventFrame.scripts.OnEvent(eventFrame,'BAG_UPDATE_DELAYED');eq(bumped,1);flush()
eventFrame.scripts.OnEvent(eventFrame,'MERCHANT_UPDATE')
shown=false;eventFrame.scripts.OnEvent(eventFrame,'MERCHANT_CLOSED');flush();eq(M.Stats().shown,false)
shown=true;combat=true;eq(M.Read(),nil);combat=false;held=true;eq(M.Read(),nil);held=false
active=false;eq(M.Read(),nil);M.Stop();eq(next(eventFrame.events),nil);eq(next(listeners),nil)
active=true;M.Start();eq(eventFrame.events.MERCHANT_SHOW,true)
-- Explicit refresh after dismissal uses fresh outstanding needs.
plan.rows[1].qty=4;live[1].numAvailable=-1
M.Refresh(true);eq(M.Stats().shown,true);eq(TwichUIWorkshopMerchantQuote.quote.rows[1].qty,4)
M.Stop();flush();eq(M.Stats().shown,false)
shown=false;M.Start();flush();eq(next(listeners),nil);M.Stop()
print('PASSED Workshop merchant review: live-only quotes, bounds and cleanup passed')
