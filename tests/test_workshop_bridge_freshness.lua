-- Source age, in-memory identity and explicit reload; no desktop-file inference.
TwichUI={Workshop={}};TwichUIDB={keep='profile'};TwichUIWorkshopDB={keep='local history'}
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge'}) do dofile(REPO..'TwichUI_Workshop/'..name..'.lua') end
local W=TwichUI.Workshop;local J,B=W.BridgeCodec,W.Bridge
assert(B.Freshness().state=='unavailable')
local f=assert(io.open(TESTS..'fixtures/market_bridge_scoped_l1/fixtures/scoped.json'));local g=J.Parse(f:read('*a'));f:close()
local function pack(value)
    local h=J.Copy(value);h.records=nil
    local receipt=J.Object();receipt.schema_version=1;receipt.generation_id=value.generation_id;receipt.desktop_build='test';receipt.completed_at='2026-11-16T23:59:59Z'
    local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(receipt)}
    for i,r in ipairs(value.records) do raw.records[i]=J.Encode(r) end;return raw
end
local function drain(value,expected)
    B.Begin(pack(value))
    for i=1,200000 do local ok,why=B.Step();if why~='loading' then assert(ok==expected);return end end
    error('bounded validation')
end
drain(g,true)
local _,observed=W.BridgeValidate.Time(g.observations[g.current_observation_ref+1].observed_at)
assert(B.Freshness(observed).state=='ready')
assert(B.Freshness(observed+7200).state=='ready')
assert(B.Freshness(observed+7201).state=='aging')
assert(B.Freshness(observed+86400).state=='aging')
assert(B.Freshness(observed+86401).state=='stale')
assert(B.Freshness(observed-1).state=='unknown')
local fresh=B.Freshness(observed+90000)
assert(fresh.generation==g.generation_id and fresh.observed_at==g.observations[g.current_observation_ref+1].observed_at)
local tips=table.concat(fresh.tip,'\n')
assert(tips:find('not a file delivery receipt',1,true) and tips:find('cannot detect newer files',1,true))
assert(tips:find('5 exact variants',1,true) and tips:find('not whole-market',1,true))
local future=J.Copy(g);future.schema_version=999;drain(future,false)
assert(B.Status().unsupported and B.Freshness(observed).generation==g.generation_id,'last-good retained')
local combat,active,reloads,shown=false,true,0,0
W.Active=function()return active end
InCombatLockdown=function()return combat end
StaticPopupDialogs={};StaticPopup_Show=function(key)assert(key=='TWICHUI_MARKET_RELOAD');shown=shown+1 end
ReloadUI=function()reloads=reloads+1 end
assert(B.RequestReload());assert(shown==1 and reloads==0,'review only')
combat=true;StaticPopupDialogs.TWICHUI_MARKET_RELOAD.OnAccept();assert(reloads==0,'accept rechecks combat')
assert(not B.RequestReload());assert(shown==1)
combat=false;active=false;assert(not B.RequestReload());StaticPopupDialogs.TWICHUI_MARKET_RELOAD.OnAccept();assert(reloads==0)
active=true;assert(B.RequestReload());StaticPopupDialogs.TWICHUI_MARKET_RELOAD.OnAccept();assert(reloads==1)
assert(TwichUIDB.keep=='profile' and TwichUIWorkshopDB.keep=='local history')
print('PASSED loaded freshness, source/delivery separation, last-good and player reload guards')
