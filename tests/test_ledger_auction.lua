-- Real Ledger + auction action controller on the existing synthetic AH adapter. No real game operations.
local function Check(x, message) assert(x, message or "check failed") end
local function Same(a,b,message) assert(a==b,(message or "").." expected "..tostring(b)..", got "..tostring(a)) end
local function Setup()
    local c,W,s=dofile(TESTS.."auction_debug_mock.lua")
    local R=c.TwichUI
    c.TwichUIDB.ui.workshopEnabled=true
    c.UnitName=function() return "Rich" end
    c.GetServerTime=function() return 20000*86400+43200 end
    s.now=100
    local timers={}
    c.C_Timer={NewTimer=function(d,fn)
        local t={at=s.now+d,fn=fn};function t:Cancel() self.cancelled=true end
        timers[#timers+1]=t;return t
    end}
    c.C_Timer.After=function(d,fn) c.C_Timer.NewTimer(d,fn) end
    function s.Advance(d)
        local target=s.now+d
        for _=1,1000 do
            local index
            for i,t in ipairs(timers) do if t.at<=target and (not index or t.at<timers[index].at) then index=i end end
            if not index then s.now=target;return end
            local t=table.remove(timers,index);s.now=math.max(s.now,t.at)
            if not t.cancelled then t.fn() end
        end
        error("unbounded timers")
    end
    for _,name in ipairs({"auction/Ledger.lua","auction/LedgerAuction.lua"}) do
        local f=assert(loadfile(ROOT..name));setfenv(f,c);f()
    end
    local L=R.Ledger
    L.Init();L.Refresh();c.FireEvent("PLAYER_ENTERING_WORLD",true,false)
    function s.Entries() return c.TwichUILedgerDB.chars["Rich - Forever"].entries end
    function s.Move(n) s.money=s.money+n;c.FireEvent("PLAYER_MONEY") end
    function s.Expect(kind,amount,qty,auction)
        local e=s.Entries()[#s.Entries()];Check(e,"observed change exists")
        Same(e.k,kind,"classification");Same(e.a,amount)
        Same(e.q,qty);Same(e.u,auction)
    end
    function s.Post(mode,qty)
        R.AuctionBuild.verified[mode]=true;s.commodity=mode=="postCommodity"
        local id=W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1],qty,100,1)
        Check(id,"post review");Same(#s.Entries(),0,"preview records nothing")
        Check(W.AuctionActions.Confirm(id));return id
    end
    return c,W,s,L,R.AuctionLedger
end
for _,mode in ipairs({"postItem","postCommodity"}) do
    for _,moneyFirst in ipairs({false,true}) do
        local c,W,s,L,A=Setup();local qty=mode=="postItem" and 1 or 5
        s.Post(mode,qty);Same(#s.Entries(),0)
        if moneyFirst then s.Move(-2);s.Advance(0) end
        W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
        if not moneyFirst then Same(#s.Entries(),0);s.Move(-2) end
        s.Advance(0);s.Expect("ahDeposit",-2,qty,501);Same(#s.Entries(),1)
        W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501);c.FireEvent("PLAYER_MONEY");s.Advance(1)
        Same(#s.Entries(),1);Same(A.Snapshot().attributed,1)
        Same(s.Count(mode=="postItem" and "PostItem" or "PostCommodity"),1,"one explicit native action")
    end
end
-- Full multisell can identify one combined charge. Partial outcomes and several money changes cannot be split or guessed.
do
    local c,W,s=Setup();s.Post("postItem",3);s.Move(-2)
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501);s.Advance(0);s.Expect(nil,-2)
    W.AuctionActions.Event("AUCTION_MULTISELL_UPDATE",3,3);s.Advance(0);s.Expect("ahDeposit",-2,3)
end
for _,mode in ipairs({"partial","wrongTotal","severalDebits","failed","foreign","noCompletion","noDebit","wrongDebit","interrupted","overdue"}) do
    local c,W,s,L,A=Setup();s.Post("postItem",(mode=="partial" or mode=="wrongTotal") and 3 or 1)
    if mode=="partial" then W.AuctionActions.Event("AUCTION_MULTISELL_UPDATE",1,3);s.Move(-2);W.AuctionActions.Event("AUCTION_MULTISELL_FAILURE")
    elseif mode=="wrongTotal" then s.Move(-2);W.AuctionActions.Event("AUCTION_MULTISELL_UPDATE",3,4)
    elseif mode=="severalDebits" then s.Move(-1);s.Move(-1);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    elseif mode=="failed" then s.Move(-2);W.AuctionActions.Event("AUCTION_HOUSE_POST_ERROR")
    elseif mode=="foreign" then c.C_AuctionHouse.PostItem({},1,1,nil,100);s.Move(-2);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    elseif mode=="noCompletion" then s.Move(-2)
    elseif mode=="noDebit" then W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    elseif mode=="wrongDebit" then s.Move(-3);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    elseif mode=="interrupted" then c.FireEvent("AUCTION_HOUSE_CLOSED");s.Move(-2);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    elseif mode=="overdue" then s.now=s.now+9;s.Move(-2);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501) end
    s.Advance(0)
    for _,e in ipairs(s.Entries()) do Same(e.k,nil,mode.." before expiry") end
    s.Advance(9)
    for _,e in ipairs(s.Entries()) do Same(e.k,nil,mode) end
    Same(#s.Entries(),mode=="noDebit" and 0 or mode=="severalDebits" and 2 or 1)
    Same(A.Snapshot().pending,0)
end
-- Earlier equal-amount spending is not the deposit of a later successful posting with no debit.
do
    local c,W,s=Setup();s.Move(-2);c.TwichUI.AuctionBuild.verified.postItem=true
    local id=W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1],1,100,1)
    Check(W.AuctionActions.Confirm(id));W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501)
    s.Advance(0);s.Expect(nil,-2);s.Advance(9);s.Expect(nil,-2)
end
-- Native warnings: no pending cash candidate while waiting; acceptance starts after intervening unrelated money.
for _,accept in ipairs({false,true}) do
    local c,W,s,L,A=Setup();s.warning=true;s.Post("postItem",1)
    Same(A.Snapshot().pending,0);Same(s.Count("ConfirmPostItem"),0)
    s.Move(-2)
    if accept then
        c.StaticPopupDialogs.AUCTION_HOUSE_POST_WARNING.OnAccept()
        W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",502);s.Move(-2)
    else W.AuctionActions.Cancel() end
    s.Advance(0);Same(s.Entries()[1].k,nil)
    if accept then s.Expect("ahDeposit",-2,1,502) else Same(#s.Entries(),1) end
end
for _,when in ipairs({"review","warning"}) do
    local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.postItem=true
    local id=W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1],1,100,1)
    if when=="warning" then s.warning=true;Check(W.AuctionActions.Confirm(id)) end
    s.deposit=3
    if when=="warning" then c.StaticPopupDialogs.AUCTION_HOUSE_POST_WARNING.OnAccept() else W.AuctionActions.Confirm(id) end
    s.Move(-3);W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",501);s.Advance(0);s.Expect(nil,-3)
    Same(s.Count("ConfirmPostItem"),0,"changed quote is not confirmed")
end
-- Synchronous completion and money are captured before native post-hooks return.
do
    local c,W,s=Setup();local native=c.C_AuctionHouse.PostItem
    c.C_AuctionHouse.PostItem=function(...) s.Move(-2);return native(...) end
    s.syncComplete=true;s.Post("postItem",1);s.Advance(0);s.Expect("ahDeposit",-2,1,501)
end
-- Cancellation: exact reviewed ID and cost, native completion and actual debit. No zero entries or automatic repost.
for _,moneyFirst in ipairs({false,true}) do
    local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.cancel=true;s.cancelCost=1200
    local id=W.AuctionActions.PrepareCancel(s.Owned(42));Check(id);Check(W.AuctionActions.Confirm(id))
    if moneyFirst then s.Move(-1200) end
    W.AuctionActions.Event("AUCTION_CANCELED",43);s.Advance(0)
    if moneyFirst then s.Expect(nil,-1200) end
    W.AuctionActions.Event("AUCTION_CANCELED",42)
    if not moneyFirst then s.Move(-1200) end
    s.Advance(0);s.Expect("ahCancelFee",-1200,3,42)
    W.AuctionActions.Event("AUCTION_CANCELED",42);s.Advance(0);Same(#s.Entries(),1);Same(s.Count("CancelAuction"),1);Same(s.Count("PostItem"),0)
end
for _,mode in ipairs({"zero","refused","sold","stale","changed","missing","overlap"}) do
    local c,W,s,L,A=Setup();c.TwichUI.AuctionBuild.verified.cancel=true;s.cancelCost=mode=="zero" and 0 or 1200
    local id=W.AuctionActions.PrepareCancel(s.Owned(42));Check(id)
    if mode=="sold" then s.owned[1].status=1 elseif mode=="stale" then s.owned={}
    elseif mode=="changed" then s.cancelCost=1300 end
    W.AuctionActions.Confirm(id)
    if mode=="refused" then W.AuctionActions.Event("AUCTION_HOUSE_SHOW_ERROR")
    elseif mode=="overlap" then c.C_AuctionHouse.CancelAuction(43) end
    if mode~="zero" then s.Move(-1200) end
    if mode~="missing" then W.AuctionActions.Event("AUCTION_CANCELED",42) end
    s.Advance(0)
    for _,e in ipairs(s.Entries()) do Same(e.k,nil,mode.." before expiry") end
    s.Advance(9)
    if mode=="zero" then Same(#s.Entries(),0) else s.Expect(nil,-1200) end
end
-- The shared adapter also defends core Sell from Bags, whose multisell completion has a separate event owner.
do
    local c,W,s,L,A=Setup()
    local a=A.Begin("postItem",2,10,3);Check(a)
    Same(A.Complete(a,nil,4,3),false);s.Move(-2);s.Advance(0);s.Expect(nil,-2)
    Check(A.Complete(a,nil,3,3));s.Advance(0);s.Expect("ahDeposit",-2,3)
end
do
    local c,W,s,L,A=Setup();local a=A.Begin("cancel",1200,10,1,42);Check(a)
    Same(A.Complete(a,43),false);s.Move(-1200);s.Advance(0);s.Expect(nil,-1200)
    Check(A.Complete(a,42));s.Advance(0);s.Expect("ahCancelFee",-1200,1,42)
end
do
    local c,W,s,L,A=Setup();local a=A.Begin("postItem",2,10,1);Check(a)
    c.C_AuctionHouse.CancelAuction(99);s.Move(-2);A.Complete(a,501);s.Advance(0);s.Expect(nil,-2)
end
-- Overlapping owned evidence attempts are poisoned until the next auctioneer visit.
do
    local c,W,s,L,A=Setup()
    local a=A.Begin("postItem",2,10,1);Check(a)
    Same(A.Begin("cancel",2,10,1,42),nil);s.Move(-2);A.Complete(a,501);s.Advance(0);s.Expect(nil,-2)
    Same(A.Begin("postItem",2,10,1),nil)
    c.FireEvent("AUCTION_HOUSE_CLOSED");c.FireEvent("AUCTION_HOUSE_SHOW")
    local b=A.Begin("postItem",2,10,1);Check(b);s.Move(-2);A.Complete(b,502);s.Advance(0);s.Expect("ahDeposit",-2,1,502)
    Same(#s.calls,0,"evidence methods never send an auction operation")
    Same(L.Snapshot().listeners,0)
    local d=c.TwichUILedgerDB.chars["Rich - Forever"].days[20000];Same(d.o,4);Same(d.co.ahDeposit,2);Same(d.co.other,2)
end
-- An observer failure cannot prevent the existing native action from being sent.
do
    local c,W,s,L,A=Setup();L.Record=function() error("unreadable accounting record") end
    s.Post("postItem",1);Same(s.Count("PostItem"),1);Same(A.Snapshot().observerError,1)
end
-- Instant diagnostics contain reason counters, not player, mail, auction IDs or copper values.
do
    local c,W,s,L,A=Setup();s.Post("postItem",1);s.Move(-7);s.Advance(0)
    for _,name in ipairs({"diag/Diagnostics.lua","diag/Lifecycle.lua"}) do
        local f=assert(loadfile(ROOT..name));setfenv(f,c);f()
    end
    local report=c.TwichUI.Diag.Build()
    Check(report:find("Gold Ledger evidence",1,true));Check(report:find("mismatch=1",1,true))
    Check(not report:find("auctionID",1,true));Check(not report:find("1000000",1,true));Check(not report:find("Rich",1,true))
end
print("LEDGER AUCTION OK")
