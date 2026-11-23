-- Opt-in production-validator accounting. Run from root with Lua 5.1/bitop.
-- No timing assertion, no shipped instrumentation, no client scheduling claim.
require('bit')
REPO=REPO or './';ROOT=ROOT or './!!!TwichUI/';TESTS=TESTS or './tests/'
local days,count=tonumber(arg[1]) or 60,tonumber(arg[2]) or 512
local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
local J,B,Q=W.BridgeCodec,W.Bridge,W.Summary
local f=dofile(TESTS..'market_cold_fixture.lua')(c,days,{[0]=count},arg[3]=='variants')
c.GetTimePreciseSec=os.clock
c.C_Timer.After=function()end -- explicit production Q.Step driving below
c.TwichUIMarketParts={A00=f.parts[0]}
B.Begin(f.root);while Q.Pending()do Q.Step()end;assert(B.Status().ready)
collectgarbage('collect');local base=collectgarbage('count')
local stopped=arg[4]=='gc-stopped';if stopped then collectgarbage('stop')end
local cpu,yields,net={}, {}, {};local stage,last='current_validation',nil
local dailyLines={}
do
    local file=assert(io.open(REPO..'TwichUI_Workshop/Summary.lua'))
    local line,inside=0,false
    for text in file:lines()do
        line=line+1
        if text:find('for _,p in ipairs(r[14])',1,true)then inside=true end
        if inside and text:find('end;tick()',1,true)then inside=false end
        if inside then dailyLines[line]=true end
    end
    file:close()
end
local function clock()return os.clock()*1000 end
local function charge(label)
    if last then cpu[label]=(cpu[label] or 0)+clock()-last end
    last=clock()
end
local real=c.coroutine;local co={};for k,v in pairs(real)do co[k]=v end;c.coroutine=co
-- Boundaries between actual coroutine resumes exclude suspension/scheduler CPU.
function co.resume(thread,...)
    last=clock();local ok,result=real.resume(thread,...)
    if last then charge(stage);last=nil end
    return ok,result
end
function co.yield(...)
    charge(stage);last=nil;yields[stage]=(yields[stage] or 0)+1
    local result=real.yield(...);last=clock();return result
end
local int=W.Int
W.Int=function(value,low,high)
    if (stage=='current_validation' or stage=='history_validation') and (high==2147483647 or low==0 and high==4) then
        local info=debug.getinfo(2,'Sl')
        if info and info.short_src:match('Summary.lua$') then
            local label=dailyLines[info.currentline] and 'history_validation' or 'current_validation'
            if label~=stage then charge(stage);stage=label end
        end
    end
    return int(value,low,high)
end
local function wrap(key,label)
    local fn=J[key]
    J[key]=function(...)
        charge(stage);local old=stage;stage=label
        local before=collectgarbage('count');local value=fn(...)
        charge(label);net[label]=(net[label] or 0)+collectgarbage('count')-before
        stage=old;return value
    end
end
wrap('SHA','integrity_hash');wrap('ParseSummary','json_decode');wrap('Encode','canonical_encode')
local begin=clock();local k=f.keys[0]
B.Record(k.item,k.variant);local callbacks,worst=0,0
while Q.Pending()do local at=clock();Q.Step();worst=math.max(worst,clock()-at);callbacks=callbacks+1 end
local elapsed=clock()-begin
local at=clock();local r=assert(B.Record(k.item,k.variant));local lookup=clock()-at
assert(tonumber(r.current.metrics.recent_copper)>=121)
local peak=collectgarbage('count');local gc=clock();collectgarbage('collect');gc=clock()-gc
if stopped then collectgarbage('restart')end
local stageCPU=0;for _,v in pairs(cpu)do stageCPU=stageCPU+v end
local out={synthetic=true,real_client=false,history_days=days,records=count,raw_bytes=#f.parts[0],
    cpu_ms=elapsed,stages_ms=cpu,stage_yields=yields,stage_net_heap_kib=net,
    scheduler_and_observer_ms=elapsed-stageCPU,callbacks=callbacks,worst_callback_ms=worst,
    current_record_with_history_copy_ms=lookup,retained_delta_kib=collectgarbage('count')-base,
    sampled_peak_delta_kib=peak-base,final_gc_ms=gc,gc_stopped=stopped}
-- Contract encoding is integer-only; benchmark clocks are fractional numbers.
local function encode(v)
    if type(v)=='number' then return ('%.6f'):format(v) end
    if type(v)~='table' then return J.Encode(v) end
    local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys)
    local fields={};for _,k in ipairs(keys)do fields[#fields+1]=J.Encode(k)..':'..encode(v[k])end
    return '{'..table.concat(fields,',')..'}'
end
print(encode(out))
