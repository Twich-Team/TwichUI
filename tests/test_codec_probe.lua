-- Fast deterministic tool tests. Fake decoders are NOT native codec evidence.
local root=REPO..'tools/codec-probe/TwichUI_CodecProbe/'
local function loadfileIn(file,env,P)
    local fn=assert(loadfile(root..file));setfenv(fn,env);fn('TwichUI_CodecProbe',P)
end
local function setup(kind)
    local env=setmetatable({},{__index=_G});env._G=env
    local P={Payloads={}}
    -- Engine logic uses explicit doubles; Python independently generates and
    -- decodes the actual package fixtures with zlib AND vendored LibDeflate.
    for name,size in pairs({small=4600,current=200263,history336=336400,history512=524288}) do
        P.Payloads[name]={expected=string.rep(name=='small' and 's' or 'p',size),raw='BASE64-RAW-'..name,
            zlib='BASE64-ZLIB-'..name,rawBytes='RAW-'..name,zlibBytes='ZLIB-'..name,zlibPrefix='HEADER',zlibSuffix='TRAILER'}
    end
    loadfileIn('Build.lua',env,P);loadfileIn('Engine.lua',env,P)
    local decode,inflate={},{};local time,calls,heap=0,0,1000
    for name,payload in pairs(P.Payloads) do
        for _,mode in ipairs({'raw','zlib'}) do
            local binary
            if name=='small' then binary=payload[mode..'Bytes'];decode[payload[mode]]=binary
            else
                binary='raw:'..name;decode[payload.raw]=binary
                if mode=='zlib' then binary=payload.zlibPrefix..binary..payload.zlibSuffix end
            end
            inflate[binary]=payload.expected
        end
    end
    local api={method=0,clockName='fake seconds',clock=function()return time end,heap=function()return heap end,
        decode=function(s)calls=calls+1;return kind=='identity' and s or assert(decode[s])end,
        inflate=function(s,method)
            assert(method==0);calls=calls+1;time=time+.001;heap=heap-.25
            if kind=='identity' then return s end
            if kind=='error' then error('synthetic decoder failure') end
            if kind=='zlib' and (s==P.Payloads.small.rawBytes or s:sub(1,4)=='raw:') then return nil end
            if kind=='slow' and #s<50 and s:find('current',1,true) then time=time+.060 end
            if kind=='wrong-large' and s:find('current',1,true) then return 'wrong bytes' end
            if inflate[s] then return inflate[s] end
            if kind=='accept-invalid' then return 'unexpected' end
            error('synthetic malformed refusal')
        end}
    return P,env,api,function()return calls end,function(v)time=v end
end
local function finish(run)
    for _=1,40 do if run:Step() then return end end
    error('probe exceeded deterministic operation bound')
end
local P,env,api,calls=setup()
assert(calls()==0,'loading vectors/engine must never run a codec')
local run=P.NewRun(api);finish(run)
assert(#run.rows==27 and run:Counts().PASSED==27 and run.largestExact==524288)
assert(run.rows[6].heap_delta_kib<0,'natural negative heap samples must not be clamped')
assert(run:Report():find('NOT a client%-enforced') and run:Report():find('zero heap delta does NOT mean zero allocation',1,true))
for _,kind in ipairs({'identity','error'}) do
    local p,_,a=setup(kind);local r=p.NewRun(a);finish(r)
    assert(r:Counts().FAILED>=2 and r.largestExact<524288)
    if kind=='identity' then assert(r:Counts().PASSED==0,'identity stubs produced a false pass') end
end
do
    local p,_,a=setup('zlib');local r=p.NewRun(a);finish(r)
    assert(r.mode=='zlib' and r:Counts().UNSUPPORTED==1 and r:Counts().FAILED==0)
end
do
    local p,_,a=setup('accept-invalid');local r=p.NewRun(a);finish(r);assert(r:Counts().FAILED==2)
end
do
    local p,_,a=setup('slow');local r=p.NewRun(a);finish(r)
    assert(r.stopReason and r:Counts().NOT_PERFORMED>0 and r.largestExact<524288)
end
do
    local p,_,a=setup('wrong-large');local r=p.NewRun(a);finish(r)
    assert(r:Counts().FAILED==1 and r:Counts().NOT_PERFORMED>0 and r.stopReason=='stopped after failed larger fixture')
end
do
    local p,_,a=setup();a.decode=nil;a.inflate=nil;local r=p.NewRun(a);finish(r)
    assert(r:Counts().UNSUPPORTED==3 and r:Counts().PASSED==0)
end
do
    local p,_,a=setup();a.clock=nil;local r=p.NewRun(a);finish(r)
    assert(r:Counts().NOT_PERFORMED==22 and r:Report():find('worst_decompress_ms=unavailable',1,true))
end
do
    local p,_,a,n,setTime=setup();local r=p.NewRun(a);setTime(11);r:Step();assert(r.done and n()==0)
    a.inCombat=function()return true end;r=p.NewRun(a);r:Step();assert(r.done and n()==0)
end
do
    local p,_,a,n=setup();local r=p.NewRun(a);r:Step();local before=n();r:Cancel('hidden');r:Step();assert(n()==before)
end

-- Minimal UI doubles, scoped to this test. Real API construction is also checked
-- separately in the existing simulator, whose decoder cannot qualify the codec.
local p,c,a,n=setup()
local timers={};local frames=0;local printed={}
local function widget()
    local f={scripts={},shown=false}
    function f:SetScript(k,fn)self.scripts[k]=fn end
    function f:Show()self.shown=true end
    function f:Hide()local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self)end end
    function f:IsShown()return self.shown end
    function f:SetText(s)self.text=s end
    function f:GetText()return self.text end
    function f:CreateFontString()return widget()end
    for _,k in ipairs({'SetSize','SetPoint','SetFrameStrata','SetClampedToScreen','SetDontSavePosition','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetTextColor','SetWidth','SetJustifyH','SetMultiLine','SetAutoFocus','SetMaxLetters','SetFontObject','SetTextInsets','SetScrollChild','SetFocus','HighlightText'})do f[k]=function()end end
    return f
end
c.CreateFrame=function(_,name)frames=frames+1;local f=widget();if name then c[name]=f end;return f end
c.C_Timer={NewTimer=function(_,fn)local t={fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t end}
c.UIParent=widget();c.UISpecialFrames={};c.SlashCmdList={};local delegated
c.SlashCmdList.TWICHUI=function(msg)delegated=msg;return 42 end
c.SLASH_TWICHUI1='/twichui';c.SLASH_TWICHUI2='/tui'
c.GetTimePreciseSec=a.clock;c.collectgarbage=function(mode)assert(mode=='count','probe changed global GC');return a.heap()end
c.C_EncodingUtil={DecodeBase64=a.decode,DecompressString=a.inflate};c.Enum={CompressionMethod={Deflate=0}}
c.GetBuildInfo=function()return '1.60.1','fixture','date',16001 end
c.print=function(s)printed[#printed+1]=s end
c.TwichUIDB={sentinel=true};c.TwichUIMarketData={sentinel=true}
loadfileIn('Probe.lua',c,p)
assert(frames==0 and #timers==0 and n()==0,'probe ran at login')
assert(c.SlashCmdList.TWICHUI('workshop')==42 and delegated=='workshop')
c.SlashCmdList.TWICHUI('codecprobe');local first=p.frame
assert(#timers==1 and n()==0)
local active=p.run;c.SlashCmdList.TWICHUI('codecprobe');assert(p.run==active and #timers==1,'explicit reentry duplicated active work')
local timer=table.remove(timers,1);timer.fn();first:Hide()
assert(p.run.done and p.timer==nil)
for _,t in ipairs(timers)do if not t.cancelled then t.fn()end end;timers={}
local before=n();assert(p.run:Counts().NOT_PERFORMED>0)
c.SlashCmdList.TWICHUI('codecprobe show');assert(n()==before and p.frame==first)
c.SlashCmdList.TWICHUI('codecprobe')
for _=1,35 do local t=table.remove(timers,1);if not t then break end;if not t.cancelled then t.fn()end end
assert(p.run.done and p.run:Counts().FAILED==0 and p.report:find('source_commit=',1,true))
assert(p.frame==first and c.TwichUIDB.sentinel and c.TwichUIMarketData.sentinel)
assert(#timers==0 and #printed>=2)
local beforeMissing=n();c.C_Timer={};c.SlashCmdList.TWICHUI('codecprobe')
assert(p.run.done and n()==beforeMissing and p.report:find('C_Timer.NewTimer missing',1,true))
do
    local q,d=setup();d.SlashCmdList={};loadfileIn('Probe.lua',d,q)
    assert(d.SLASH_TWICHUICPROBE2=='/tui' and type(d.SlashCmdList.TWICHUICPROBE)=='function')
    local other=function()end
    q,d=setup();d.SlashCmdList={OTHER=other};d.SLASH_OTHER1='/tui';loadfileIn('Probe.lua',d,q)
    assert(d.SLASH_TWICHUICPROBE2==nil and d.SlashCmdList.OTHER==other,'probe replaced another addon root command')
end
print('CODEC PROBE TEST PASSED: deterministic compatibility/error/budget/cancellation/UI/delegation; no native-game claim')
