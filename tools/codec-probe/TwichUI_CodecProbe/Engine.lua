-- Development-only, fixed trusted fixtures. No custom codec, IO or price access.
local _, P = ...
local MAX, SLOW_MS, MAX_SECONDS = 524288, 50, 10
local function number(fn)
    if type(fn) ~= 'function' then return nil end
    local ok, v = pcall(fn)
    if ok and type(v) == 'number' and v == v and v >= 0 then return v end
end
local function text(v) return tostring(v or ''):gsub('[%c]', '?'):sub(1, 240) end
local function ms(a, b) return a and b and b >= a and (b-a)*1000 or nil end
local function fmt(v) return type(v)=='number' and ('%.3f'):format(v) or 'unavailable' end

function P.NewRun(api)
    local run = { api=api, rows={}, index=0, worst=0, worstCallback=0, largest=0,
        largestExact=0, timed=0, started=number(api.clock), queue={}, done=false }
    local q=run.queue
    q[#q+1]={id='base64-known',kind='base64'}
    for _, mode in ipairs({'raw','zlib'}) do q[#q+1]={id='external-'..mode,kind='small',mode=mode} end
    q[#q+1]={id='malformed-reserved-block',kind='malformed'}
    q[#q+1]={id='truncated-small-stream',kind='truncated'}
    for _, name in ipairs({'current','history336','history512'}) do
        for repeatIndex=1,2 do q[#q+1]={id=name..'-'..repeatIndex,kind='performance',payload=name} end
    end
    for i=1,16 do q[#q+1]={id='history-group-'..i,kind='performance',payload='history336',group=true} end

    function run:Cancel(reason)
        if self.done then return end
        self.stopReason=text(reason)
        for i=self.index+1,#q do self.rows[#self.rows+1]={id=q[i].id,group=q[i].group,status='NOT_PERFORMED',reason=self.stopReason} end
        self.index=#q;self.done=true
    end
    function run:Inflate(input, expected, row, refusal)
        if type(api.inflate)~='function' or api.method==nil then row.status='UNSUPPORTED';row.reason='Deflate API/method missing';return end
        row.input=#input;row.expected=expected and #expected or nil
        self.largest=math.max(self.largest,row.expected or 0)
        local heap=number(api.heap);local at=number(api.clock)
        local ok, output=pcall(api.inflate,input,api.method)
        row.decompress_ms=ms(at,number(api.clock))
        if row.decompress_ms then self.timed=self.timed+1 end
        local after=number(api.heap);row.heap_delta_kib=heap and after and after-heap or nil
        row.output=ok and type(output)=='string' and #output or nil
        row.error=not ok and text(output) or nil
        if refusal then
            row.status=(not ok or output==nil) and 'PASSED' or 'FAILED'
            row.reason=row.status=='PASSED' and 'small invalid stream refused' or 'invalid stream returned non-nil output'
        elseif not ok or output==nil then
            row.status='REFUSED';row.reason='valid external encoding refused'
        elseif type(output)=='string' and output==expected then
            row.status='PASSED';row.exact=true;self.largestExact=math.max(self.largestExact,#expected)
        else row.status='FAILED';row.reason='exact byte equality failed (identity stubs cannot pass)' end
        self.worst=math.max(self.worst,row.decompress_ms or 0)
        if row.decompress_ms and row.decompress_ms>SLOW_MS then self.slow=true end
    end
    function run:Step()
        if self.done then return true end
        if api.inCombat and api.inCombat() then self:Cancel('not performed in combat');return true end
        local callbackAt=number(api.clock)
        if self.started and callbackAt and callbackAt-self.started>MAX_SECONDS then self:Cancel('ten-second wall budget reached');return true end
        self.index=self.index+1
        local task=q[self.index];local row={id=task.id,group=task.group}
        local small=P.Payloads.small
        if task.kind=='base64' then
            if type(api.decode)~='function' then row.status='UNSUPPORTED';row.reason='DecodeBase64 missing'
            else
                local ok, value=pcall(api.decode,small.raw)
                self.base64OK=ok and value==small.rawBytes
                row.status=self.base64OK and 'PASSED' or 'FAILED'
                row.reason=not self.base64OK and 'known Base64 bytes differ/refused' or nil
                row.error=not ok and text(value) or nil
            end
        elseif task.kind=='small' then
            self:Inflate(small[task.mode..'Bytes'],small.expected,row)
            if row.status=='PASSED' then self.mode=self.mode or task.mode end
        elseif task.kind=='malformed' or task.kind=='truncated' then
            if not self.mode then row.status='NOT_PERFORMED';row.reason='no compatible external decoder established'
            else
                local input=small[self.mode..'Bytes']
                if task.kind=='truncated' then input=input:sub(1,math.floor(#input/2))
                else input=self.mode=='raw' and '\007' or '\120\156\007\000\000\000\001' end
                self:Inflate(input,nil,row,true)
            end
        else
            local payload=P.Payloads[task.payload]
            if not self.mode or not self.base64OK then row.status='NOT_PERFORMED';row.reason='compatible decoder and exact Base64 prerequisite required'
            elseif not callbackAt then row.status='NOT_PERFORMED';row.reason='timing unavailable; larger calls withheld'
            elseif #payload.expected>MAX then row.status='NOT_PERFORMED';row.reason='fixture output exceeds hard bound'
            else
                local at=number(api.clock);local ok,input=pcall(api.decode,payload.raw)
                row.base64_ms=ms(at,number(api.clock))
                if not ok or type(input)~='string' then row.status='FAILED';row.reason='Base64 fixture refused';row.error=not ok and text(input) or nil
                else
                    if self.mode=='zlib' then input=payload.zlibPrefix..input..payload.zlibSuffix end
                    self:Inflate(input,payload.expected,row);if row.status=='REFUSED' then row.status='FAILED' end
                end
                if row.base64_ms and row.base64_ms>SLOW_MS then self.slow=true end
            end
        end
        self.rows[#self.rows+1]=row
        if self.index==3 then
            for _, previous in ipairs(self.rows) do
                if previous.status=='REFUSED' then previous.status=self.mode and 'UNSUPPORTED' or 'FAILED' end
            end
        end
        row.callback_ms=ms(callbackAt,number(api.clock))
        self.worstCallback=math.max(self.worstCallback,row.callback_ms or 0)
        if row.callback_ms and row.callback_ms>100 then self.slow=true end
        if self.slow then self:Cancel('stopped after slow synchronous call (>50 ms native or >100 ms callback)')
        elseif task.kind=='performance' and row.status=='FAILED' then self:Cancel('stopped after failed larger fixture')
        elseif self.index==#q then self.done=true end
        return self.done
    end
    function run:Counts()
        local c={PASSED=0,UNSUPPORTED=0,FAILED=0,NOT_PERFORMED=0}
        for _, row in ipairs(self.rows) do c[row.status]=(c[row.status] or 0)+1 end
        return c
    end
    function run:Summary()
        local c=self:Counts()
        return ('Forever codec: %d passed, %d unsupported, %d failed; %d not performed'):format(c.PASSED,c.UNSUPPORTED,c.FAILED,c.NOT_PERFORMED)
    end
    function run:Report()
        local grouped,groupPassed,groupMs,groupBytes=0,0,0,0
        for _,row in ipairs(self.rows) do if row.group then
            if row.decompress_ms then grouped=grouped+1;groupMs=groupMs+row.decompress_ms end
            if row.exact then groupPassed=groupPassed+1;groupBytes=groupBytes+(row.output or 0) end
        end end
        local lines={self:Summary(),'TwichUI Codec Probe DEV — report format 1',
            'source_commit='..text(P.Build and P.Build.commit),'client='..text(api.build),
            'fixture_file_sha256='..text(P.Build and P.Build.files and P.Build.files['Vectors.lua']),
            'fixture_generator_sha256='..text(P.Build and P.Build.generator_sha256)..'; generator_zlib='..text(P.Build and P.Build.zlib_runtime),
            'APIs: DecompressString='..type(api.inflate)..'; DecodeBase64='..type(api.decode)..'; Deflate='..tostring(api.method),
            'clock='..text(api.clockName)..'; synchronous elapsed time, not exclusive CPU',
            'compatible_external_wrapper='..tostring(self.mode or 'NONE'),
            'DecodeBase64_exact='..tostring(self.base64OK==true),
            'largest_fixture_attempted_bytes='..self.largest..'; largest_exact_output_bytes='..self.largestExact,
            'worst_decompress_ms='..fmt(self.timed>0 and self.worst or nil)..'; worst_callback_ms='..fmt(self.started and self.worstCallback or nil),
            ('history_group: timed_calls=%d/16 exact=%d native_sum_ms=%s exact_output_sum_bytes=%d'):format(grouped,groupPassed,fmt(grouped>0 and groupMs or nil),groupBytes),
            'stop_reason='..tostring(self.stopReason or 'completed'),
            'DATA: generated synthetic fixtures only; no account, Market, character or realm data.',
            'LIMIT: max trusted fixture output 524288 bytes/call; this is NOT a client-enforced decoder limit.',
            'LIMIT: Lua heap before/after only; not allocation peak, native buffers, RSS or retained-memory proof.',
            'CALLBACK: engine step (Base64, codec, heap query, equality); excludes export formatting, rendering and other addons.',
            'LIMIT: resident expected strings can be interned/reused; zero heap delta does NOT mean zero allocation.',
            'LIMIT: no forced GC or GC settings changes. Background/game GC can produce negative heap deltas.',
            'NOT PERFORMED: decompression bombs, arbitrary inputs, unknown expansion, client limit discovery.',
            'NOT PERFORMED: 13-addon TOC loading/full pricing/migration/rollback certification.',
            'GROUP MODEL: repeated same 336400-byte/60-day history fixture, 16 separate callbacks; not one container load.',
            'FIXTURE STORAGE: raw Deflate Base64; zlib mode joins literal external header/trailer. No Lua encoder/checksum.',
            'CASES: id | result | input bytes | output bytes | expected bytes | base64 ms | decompress ms | heap delta KiB | callback ms | detail'}
        for _, row in ipairs(self.rows) do
            lines[#lines+1]=table.concat({row.id,row.status,tostring(row.input or '-'),tostring(row.output or '-'),tostring(row.expected or '-'),fmt(row.base64_ms),fmt(row.decompress_ms),fmt(row.heap_delta_kib),fmt(row.callback_ms),text(row.reason)..(row.error and '; error='..row.error or '')},' | ')
        end
        return table.concat(lines,'\n')
    end
    return run
end
