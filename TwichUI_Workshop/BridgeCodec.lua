-- Strict bounded JSON and incremental SHA-256 for the data-only bridge.
-- This parses data; it never compiles/executes downloaded text. No saved writes.
local W=TwichUI.Workshop
local J={NULL={},OBJECT={},ARRAY={}}
W.BridgeCodec=J
local floor,char,byte,sub=math.floor,string.char,string.byte,string.sub
local simple={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
local escapes={[34]='\\"',[92]='\\\\',[8]='\\b',[12]='\\f',[10]='\\n',[13]='\\r',[9]='\\t'}
local function fail() error("invalid bridge encoding",0) end
local function utf(n)
    if n<128 then return char(n) elseif n<2048 then return char(192+floor(n/64),128+n%64)
    elseif n<65536 then return char(224+floor(n/4096),128+floor(n/64)%64,128+n%64)
    else return char(240+floor(n/262144),128+floor(n/4096)%64,128+floor(n/64)%64,128+n%64) end
end
function J.Parse(raw,tick)
    if type(raw)~="string" or #raw>65536 then fail() end
    local i,n,steps=1,#raw,0
    local function step() steps=steps+1 if tick and steps%128==0 then tick() end end
    local function ws() while i<=n and raw:find("^[ \t\r\n]",i) do i=i+1;step() end end
    local function str()
        if sub(raw,i,i)~='"' then fail() end
        i=i+1;local out={}
        while i<=n do
            local at=raw:find('["\\%z\001-\031\127-\255]',i)
            if not at then fail() end
            if at>i then
                for p=i,at-1,128 do
                    out[#out+1]=sub(raw,p,math.min(p+127,at-1))
                    if tick and p+127<at then tick() end
                end
                i=at
            end
            step();local c=byte(raw,i);i=i+1
            if c==34 then return table.concat(out) end
            if c==92 then
                local e=sub(raw,i,i);i=i+1
                if simple[e] then out[#out+1]=simple[e]
                elseif e=='u' then
                    local hex=sub(raw,i,i+3);if #hex~=4 or hex:find('[^0-9a-fA-F]') then fail() end
                    local cp=tonumber(hex,16);i=i+4
                    if cp>=55296 and cp<=56319 then
                        if sub(raw,i,i+1)~='\\u' then fail() end;i=i+2
                        local low=sub(raw,i,i+3);if #low~=4 or low:find('[^0-9a-fA-F]') then fail() end
                        low=tonumber(low,16);i=i+4;if low<56320 or low>57343 then fail() end
                        cp=65536+(cp-55296)*1024+low-56320
                    elseif cp>=56320 and cp<=57343 then fail() end
                    out[#out+1]=utf(cp)
                else fail() end
            elseif c<32 or c>=127 then fail() -- canonical source strings are ASCII; Unicode must be escaped
            else out[#out+1]=char(c) end
        end
        fail()
    end
    local value
    value=function(depth)
        if depth>12 then fail() end;ws();step();local c=sub(raw,i,i)
        if c=='"' then return str()
        elseif c=='{' then
            i=i+1;local out=setmetatable({},J.OBJECT);ws();if sub(raw,i,i)=='}' then i=i+1;return out end
            while true do ws();local k=str();if out[k]~=nil then fail() end;ws();if sub(raw,i,i)~=':' then fail() end;i=i+1;out[k]=value(depth+1);ws();local nextc=sub(raw,i,i);i=i+1;if nextc=='}' then return out elseif nextc~=',' then fail() end end
        elseif c=='[' then
            i=i+1;local out=setmetatable({},J.ARRAY);ws();if sub(raw,i,i)==']' then i=i+1;return out end
            while true do out[#out+1]=value(depth+1);ws();local nextc=sub(raw,i,i);i=i+1;if nextc==']' then return out elseif nextc~=',' then fail() end end
        elseif sub(raw,i,i+3)=='null' then i=i+4;return J.NULL
        elseif sub(raw,i,i+3)=='true' then i=i+4;return true
        elseif sub(raw,i,i+4)=='false' then i=i+5;return false
        else
            local start=i;if c=='-' then i=i+1 end
            if sub(raw,i,i)=='0' then i=i+1
            else if not sub(raw,i,i):match('[1-9]') then fail() end;while sub(raw,i,i):match('%d') do i=i+1;step() end end
            local text=sub(raw,start,i-1);local abs=text:gsub('^-','')
            if #abs>16 or (#abs==16 and abs>'9007199254740991') then fail() end
            local number=tonumber(text);if not number or text=='-0' then fail() end;return number
        end
    end
    local out=value(0);ws();if i~=n+1 then fail() end;return out
end
local function quote(s,tick)
    if #s<=128 and not s:find('[%z\001-\031"\\\127-\255]') then return '"'..s..'"' end
    local out={'"'};local i,units=1,0
    while i<=#s do
        local at=s:find('[%z\001-\031"\\\127-\255]',i) or #s+1
        if at>i then
            for p=i,at-1,128 do
                out[#out+1]=sub(s,p,math.min(p+127,at-1))
                if tick and p+127<at then tick() end
            end
            i=at
            if i>#s then break end
        end
        local c=byte(s,i);i=i+1
        if escapes[c] then out[#out+1]=escapes[c]
        elseif c>=32 and c<127 then out[#out+1]=char(c)
        else
            local cp=c
            if c>=194 and c<=244 then
                local count=c<224 and 1 or c<240 and 2 or 3
                cp=c%(2^(6-count))
                for _=1,count do local b=byte(s,i);i=i+1;if not b or b<128 or b>191 then fail() end;cp=cp*64+b-128 end
                if cp<(count==1 and 128 or count==2 and 2048 or 65536) or cp>1114111 or (cp>=55296 and cp<=57343) then fail() end
            elseif c>=128 then fail() end
            if cp<=65535 then out[#out+1]=('\\u%04x'):format(cp)
            else cp=cp-65536;out[#out+1]=('\\u%04x\\u%04x'):format(55296+floor(cp/1024),56320+cp%1024) end
        end
        units=units+1;if tick and units%32==0 then tick() end
    end
    out[#out+1]='"';return table.concat(out)
end
function J.Encode(v,tick,depth)
    local parts={}
    local function emit(value,level)
        if level>12 then fail() end;if tick then tick() end
        if value==J.NULL then parts[#parts+1]='null';return end
        local kind=type(value)
        if kind=='string' then parts[#parts+1]=quote(value,tick)
        elseif kind=='boolean' then parts[#parts+1]=value and 'true' or 'false'
        elseif kind=='number' then
            if not W.Int(value,-9007199254740991,9007199254740991) then fail() end
            parts[#parts+1]=('%.0f'):format(value)
        elseif kind=='table' then
            local mt=getmetatable(value)
            if mt==J.ARRAY then
                parts[#parts+1]='['
                for i=1,#value do if i>1 then parts[#parts+1]=',' end;emit(value[i],level+1) end
                parts[#parts+1]=']'
            elseif mt==J.OBJECT then
                local keys={};for k in pairs(value) do if type(k)~='string' then fail() end;keys[#keys+1]=k end;table.sort(keys)
                parts[#parts+1]='{'
                for i,k in ipairs(keys) do
                    if i>1 then parts[#parts+1]=',' end
                    parts[#parts+1]=quote(k,tick);parts[#parts+1]=':';emit(value[k],level+1)
                end
                parts[#parts+1]='}'
            else fail() end
        else fail() end
    end
    emit(v,depth or 0);return table.concat(parts)
end
function J.Copy(v)
    if type(v)~='table' or v==J.NULL then return v end
    local out=setmetatable({},getmetatable(v));for k,x in pairs(v) do out[k]=J.Copy(x) end;return out
end
function J.Object() return setmetatable({},J.OBJECT) end
function J.Array() return setmetatable({},J.ARRAY) end

-- SHA-256 as specified by FIPS 180-4; unsigned modular additions stay below 2^36.
local bit=bit
local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
function J.Hash(tick)
    if not(bit and bit.bxor and bit.band and bit.bor and bit.bnot and bit.lshift and bit.rshift) then error('bridge SHA-256 unavailable',0) end
    local bxor,band,bor,shl,shr=bit.bxor,bit.band,bit.bor,bit.lshift,bit.rshift
    -- Forever exposes shifts and binary bit operations; rotate/variadic helpers are not required.
    local function ror(v,n) return bor(shr(v,n),shl(v,32-n)) end
    local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local buffer,n,finished='',0,false;local ctx={};local w={}
    local function block(s,start)
        for i=0,15 do local p=start+i*4;w[i+1]=byte(s,p)*16777216+byte(s,p+1)*65536+byte(s,p+2)*256+byte(s,p+3) end
        for i=17,64 do
            local a,b=w[i-15],w[i-2];w[i]=(w[i-16]+bxor(bxor(ror(a,7),ror(a,18)),shr(a,3))+w[i-7]+bxor(bxor(ror(b,17),ror(b,19)),shr(b,10)))%4294967296
            if tick and i%16==0 then tick() end
        end
        local a,b,c,d,e,f,g,z=unpack(h)
        for i=1,64 do
            -- Ch(e,f,g) = g xor (e and (f xor g)).
            -- Maj(a,b,c) = (a and b) or (c and (a or b)).
            local t1=(z+bxor(bxor(ror(e,6),ror(e,11)),ror(e,25))+bxor(g,band(e,bxor(f,g)))+K[i]+w[i])%4294967296
            local t2=(bxor(bxor(ror(a,2),ror(a,13)),ror(a,22))+bor(band(a,b),band(c,bor(a,b))))%4294967296
            z,g,f,e,d,c,b,a=g,f,e,(d+t1)%4294967296,c,b,a,(t1+t2)%4294967296
            if tick and i%16==0 and i<64 then tick() end
        end
        h[1],h[2],h[3],h[4]=(h[1]+a)%4294967296,(h[2]+b)%4294967296,(h[3]+c)%4294967296,(h[4]+d)%4294967296
        h[5],h[6],h[7],h[8]=(h[5]+e)%4294967296,(h[6]+f)%4294967296,(h[7]+g)%4294967296,(h[8]+z)%4294967296
        if tick then tick() end
    end
    function ctx:Update(s)
        if finished or type(s)~='string' then fail() end;n=n+#s
        local data=buffer..s;local full=#data-#data%64
        for i=1,full,64 do block(data,i) end;buffer=sub(data,full+1);return self
    end
    function ctx:Finish()
        if finished then fail() end
        local hi,lo=floor(n/536870912),(n*8)%4294967296
        local function word(v) return char(floor(v/16777216)%256,floor(v/65536)%256,floor(v/256)%256,v%256) end
        self:Update(char(128)..string.rep(char(0),(55-n)%64)..word(hi)..word(lo));finished=true
        local out={};for _,v in ipairs(h) do for shift=24,0,-8 do out[#out+1]=('%02x'):format(floor(v/2^shift)%256) end end
        return table.concat(out)
    end
    return ctx
end
function J.SHA(s,tick) return J.Hash(tick):Update(s):Finish() end
