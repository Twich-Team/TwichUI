-- Real mailbox collector + Ledger. Invoice facts and actual payments are delivered independently.
dofile(TESTS.."harness.lua")
local function Same(a,b,m) assert(a==b,(m or "").." expected "..tostring(b)..", got "..tostring(a)) end
local function Check(v,m) assert(v,m or "check failed") end
local function Copy(t) if type(t)~="table" then return t end local r={} for k,v in pairs(t) do r[k]=Copy(v) end return r end
local function Client(opts)
    opts=opts or {}
    local c=MakeClient("Rich",{"!!!TwichUI"})
    c.TwichUIDB={modules={chronicle=false,quietLogin=false,mailGoldSummary=opts.summary==true},ui={workshopEnabled=opts.on~=false}}
    c.TwichUILedgerDB=opts.db
    c.NOW,c.MONEY,c.INBOX,c.OUT=100,500000,{},{}
    c.GetServerTime=function() return 20000*86400+43200 end
    c.GetTime=function() return c.NOW end
    c.GetMoney=function() return c.MONEY end
    c.print=function(value) c.OUT[#c.OUT+1]=tostring(value) end
    local timers={}
    c.C_Timer={After=function(d,fn) timers[#timers+1]={at=c.NOW+d,fn=fn} end}
    function c.Advance(d)
        c.NOW=c.NOW+d
        local due,rest={},{}
        for _,t in ipairs(timers) do if t.at<=c.NOW then due[#due+1]=t else rest[#rest+1]=t end end
        timers=rest;for _,t in ipairs(due) do t.fn() end
    end
    c.GetInboxNumItems=function() return #c.INBOX end
    c.GetInboxHeaderInfo=function(i)
        local m=c.INBOX[i];if m then return 1,1,"PRIVATE SENDER","PRIVATE SUBJECT",m.cleared and 0 or m.money,m.cod or 0,30,0 end
    end
    c.GetInboxInvoiceInfo=function(i)
        local m=c.INBOX[i]
        if not m or not m.kind or opts.clearOnTake and m.cleared then return end
        return m.kind,m.item,"PRIVATE BUYER",m.g,m.buyout,m.d,m.f,0,1,2,m.qty
    end
    local function Take(i) if opts.clearOnTake then c.INBOX[i].cleared=true end end
    c.TakeInboxMoney,c.AutoLootMailItem=Take,Take
    c.hooksecurefunc=function(name,fn) local original=c[name];c[name]=function(...) original(...);fn(...) end end
    for _,name in ipairs({"modules/Restock.lua","WorkshopLauncher.lua","auction/Ledger.lua","auction/Mail.lua"}) do
        local f=assert(loadfile(ROOT..name));setfenv(f,c);f()
    end
    c.LOADED["!!!TwichUI"]=true;c.FireEvent("ADDON_LOADED","!!!TwichUI");c.FireEvent("PLAYER_LOGIN");c.FireEvent("PLAYER_ENTERING_WORLD",true,false)
    c.L,c.MG=c.TwichUI.Ledger,c.TwichUI.MailGold
    function c.Entries() return c.TwichUILedgerDB.chars["Rich - Forever"].entries end
    function c.Last() return c.Entries()[#c.Entries()] end
    function c.Open(inbox) c.INBOX=inbox;c.FireEvent("MAIL_SHOW") end
    function c.Move(n) c.MONEY=c.MONEY+n;c.FireEvent("PLAYER_MONEY") end
    function c.Deliver(indices,amount)
        for _,i in ipairs(indices) do c.INBOX[i].money=0;c.INBOX[i].cleared=true end
        c.Move(amount);c.Advance(0)
    end
    return c
end
local function Sale(name,qty,g,d,f,money) return {kind="seller",item=name,qty=qty,g=g,d=d,f=f,money=money,buyout=99999999} end
-- Bid, not advertised buyout: the native mail frame uses this exact invoice equation and count.
for _,clear in ipairs({false,true}) do
    local c=Client({clearOnTake=clear,summary=true})
    c.Open({Sale("Runecloth",20,100000,4500,5000,99500)})
    c.TakeInboxMoney(1);Same(#c.Entries(),0,"invoice/request alone records nothing")
    c.Deliver({1},99500)
    local e=c.Last();Same(e.a,99500);Same(e.k,"ahSale");Same(e.n,"Runecloth");Same(e.q,20);Same(e.i,nil,"no guessed item ID")
    Same(e.s.v,1);Same(e.s.g,100000);Same(e.s.f,5000);Same(e.s.d,4500);Same(e.s.c,99500)
    Same(#c.Entries(),1,"fee and returned deposit are not extra cash entries")
    local d=c.TwichUILedgerDB.chars["Rich - Forever"].days[20000];Same(d.i,99500);Same(d.o,0);Same(d.ci.ahSale,99500)
    c.FireEvent("PLAYER_MONEY");c.FireEvent("MAIL_INBOX_UPDATE");Same(#c.Entries(),1)
    c.FireEvent("MAIL_CLOSED");Same(#c.OUT,1);Check(c.OUT[1]:find("Collected",1,true))
    local serializer,codec=c.LibStub("LibSerialize"),c.LibStub("LibDeflate")
    local text=codec:EncodeForPrint(serializer:Serialize(c.TwichUILedgerDB))
    local decoded,saved=serializer:Deserialize(codec:DecodeForPrint(text));Check(decoded,"safe text round trip")
    local reload=Client({db=saved})
    Same(#reload.Entries(),1);Same(reload.Last().id,e.id);Same(reload.Last().s.f,5000);Same(reload.Last().s.d,4500)
    Check(not tostring(e.n):find("PRIVATE",1,true));Same(e.s.invoices[1].player,nil)
end
-- Mail summary enabled before the Ledger: exact classification waits for the recorder if its event listener runs second.
do
    local c=Client({on=false,summary=true});c.Open({Sale("Mooncloth",1,10000,0,500,9500)})
    c.TwichUIDB.ui.workshopEnabled=true;c.L.Refresh()
    c.TakeInboxMoney(1);c.Deliver({1},9500);Same(c.Last().k,"ahSale");Same(c.Last().s.f,500);Same(c.L.Snapshot().pending,0)
end
-- Combined sales preserve one cash entry with separately supported, bounded invoice metadata.
do
    local c=Client();c.Open({Sale("Runecloth",20,100000,4500,5000,99500),Sale("Mooncloth",1,20000,0,1000,19000)})
    c.TakeInboxMoney(1);c.TakeInboxMoney(2);c.Deliver({1,2},118500)
    Same(#c.Entries(),1);Same(c.Last().a,118500);Same(c.Last().k,"ahSale");Same(c.Last().n,nil)
    Same(#c.Last().s.invoices,2);Same(c.Last().s.g,120000);Same(c.Last().s.f,6000);Same(c.Last().s.d,4500)
    Same(c.Last().s.invoices[1].n,"Runecloth");Same(c.Last().s.invoices[2].c,19000)
end
-- Mixed payments and unsupported refund-like/temporary/buyer invoices retain their existing cash classification.
for _,kind in ipairs({"personal","refund","seller_temp_invoice","buyer","missing"}) do
    local c=Client();local m={kind=kind~="missing" and kind or nil,item="Returned item",money=700,g=700,d=0,f=0}
    c.Open({m});c.TakeInboxMoney(1);c.Deliver({1},700);Same(c.Last().k,"mail");Same(c.Last().s,nil)
end
do
    local c=Client();c.Open({Sale("Runecloth",20,100000,4500,5000,99500),{money=700}})
    c.TakeInboxMoney(1);c.TakeInboxMoney(2);c.Deliver({1,2},100200)
    Same(c.Last().k,"mail");Same(c.Last().s,nil);Same(#c.Entries(),1)
end
-- Missing/mismatched settlement values do not replace V1's functioning seller-receipt attribution or invent fee data.
for _,mode in ipairs({"missing","mismatch","negative","fractional","nan","overflow","secret"}) do
    local c=Client();local m=Sale("Runecloth",20,100000,4500,5000,99500)
    if mode=="missing" then m.f=nil elseif mode=="mismatch" then m.f=4000 elseif mode=="negative" then m.d=-1
    elseif mode=="fractional" then m.f=5000.5 elseif mode=="nan" then m.g=0/0
    elseif mode=="overflow" then m.g=c.L.MAX_MONEY
    else local secret={};c.issecretvalue=function(v) return v==secret end;m.f=secret end
    c.Open({m});c.TakeInboxMoney(1);c.Deliver({1},99500);Same(c.Last().k,"ahSale");Same(c.Last().s,nil,mode)
end
-- Duplicate requests/events and ambiguous equal amounts keep the actual money once. V5: a repeated call for the same message is a
-- spare (never matched), so the one payment keeps its invoice; when a sale and plain letters could each explain the gain, every
-- explanation is mailbox money, so it is Mail collected, never an auction sale and never a guessed invoice.
for _,mode in ipairs({"duplicate","equal","subset"}) do
    local c=Client({summary=true})
    local rows={Sale("Runecloth",1,100,0,0,100),{money=100}}
    if mode=="subset" then rows={Sale("Runecloth",1,100,0,0,100),{money=40},{money=60}} end
    c.Open(rows);c.TakeInboxMoney(1)
    if mode=="duplicate" then c.AutoLootMailItem(1) else for i=2,#rows do c.TakeInboxMoney(i) end end
    c.Deliver({1},100);Same(#c.Entries(),1)
    if mode=="duplicate" then Same(c.Last().k,"ahSale",mode);Same(c.Last().s.c,100,mode)
    else Same(c.Last().k,"mail",mode);Same(c.Last().s,nil,mode) end
    c.FireEvent("PLAYER_MONEY");c.Advance(5);Same(#c.Entries(),1)
    c.FireEvent("MAIL_CLOSED");Same(#c.OUT,1,"summary still counts actual gain once")
end
-- Failed/expired collection does not let a later identical gain borrow its invoice.
for _,mode in ipairs({"failed","expired","overdue","unrelated"}) do
    local c=Client();c.Open({Sale("Runecloth",1,100,0,0,100)});c.TakeInboxMoney(1)
    if mode=="failed" then c.FireEvent("MAIL_FAILED") elseif mode=="expired" then c.Advance(5)
    elseif mode=="overdue" then c.NOW=c.NOW+5 end
    if mode=="unrelated" then c.Move(77) end
    c.Move(100);c.Advance(0)
    if mode=="unrelated" then Same(c.Entries()[1].k,nil);Same(c.Last().k,"ahSale") else Same(c.Last().k,nil) end
end
-- More than eight invoices still identify collected sales, without an unbounded persisted breakdown.
do
    local c=Client();c.Move(100) -- an earlier equal-amount movement has no receipt
    c.Open({Sale("Cloth",1,100,0,0,100)});c.TakeInboxMoney(1)
    c.GetServerTime=function() return nil end -- recorder cannot validate this later payment's timestamp
    c.Deliver({1},100);Same(#c.Entries(),1);Same(c.Last().k,nil,"never borrow an older equal-amount entry")
end
do
    local c=Client();local rows={};for i=1,9 do rows[i]=Sale("Cloth",1,100,0,0,100) end
    c.Open(rows);for i=1,9 do c.TakeInboxMoney(i) end;c.Deliver({1,2,3,4,5,6,7,8,9},900)
    Same(#c.Entries(),1);Same(c.Last().k,"ahSale");Same(c.Last().s,nil)
end
-- Versioned extension validation is narrow; root future-schema protection remains unchanged.
do
    local c=Client();c.Open({Sale("Cloth",1,100,0,0,100)});c.TakeInboxMoney(1);c.Deliver({1},100)
    local original=c.Last().id;local saved=Copy(c.TwichUILedgerDB)
    saved.chars["Rich - Forever"].entries[1].s={v=2,future="keep"}
    local reload=Client({db=saved});Same(reload.Last().id,original);Same(reload.Last().s.future,"keep")
    Same(reload.L.Settlement(reload.Last().s,100),nil)
    saved=Copy(c.TwichUILedgerDB);saved.chars["Rich - Forever"].entries[1].s.invoices[1].f=999
    reload=Client({db=saved});Same(reload.Last().id,original);Same(reload.Last().a,100);Same(reload.Last().s,nil)
    local future={version=999,chars={sentinel={value=42}}};local held=Client({db=future});Check(held.L.Held());Same(future.chars.sentinel.value,42)
end
-- Old V1/V2 entries retain their IDs, amounts and source totals when new settlement metadata is recorded.
do
    local t=20000*86400+43200
    local db={version=1,chars={["Rich - Forever"]={name="Rich",realm="Forever",since=t,nextId=3,
        entries={{id=1,t=t,a=-36,e="balance"},{id=2,t=t,a=18,k="vendorSell",e="merchantsale",i=11,q=2}},
        days={[20000]={i=18,o=36,n=2,ci={vendorSell=18},co={other=36}}}}}}
    local c=Client({db=db});c.Open({Sale("Cloth",1,100,3,5,98)});c.TakeInboxMoney(1);c.Deliver({1},98)
    Same(c.Entries()[1].id,1);Same(c.Entries()[1].a,-36);Same(c.Entries()[1].k,nil)
    Same(c.Entries()[2].id,2);Same(c.Entries()[2].k,"vendorSell");Same(c.Entries()[2].i,11)
    Same(c.Last().id,3);Same(c.Last().s.c,98);Same(db.version,1)
    Same(db.chars["Rich - Forever"].days[20000].i,116);Same(db.chars["Rich - Forever"].days[20000].o,36)
end
-- Independent observed-cash arithmetic across varied invoice/personal payments; no fee or refund becomes cash twice.
do
    local c=Client();local total=0
    for i=1,60 do
        local m,paid
        if i%3==0 then m,paid=Sale("Cloth",1,100,3,5,98),98
        elseif i%3==1 then m,paid=Sale("Cloth",2,200,0,10,190),190
        else m,paid={money=42},42 end
        c.Open({m});c.TakeInboxMoney(1);c.Deliver({1},paid);c.FireEvent("MAIL_CLOSED")
        total=total+paid;Same(#c.Entries(),i)
        local day=c.TwichUILedgerDB.chars["Rich - Forever"].days[20000]
        Same(day.i,total);Same(day.o,0);Same(day.n,i)
        local sum=0;for _,n in pairs(day.ci) do sum=sum+n end;Same(sum,total)
    end
end
print("LEDGER SETTLEMENT OK")
