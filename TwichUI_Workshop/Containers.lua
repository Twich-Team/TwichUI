-- Companion-owned raw-Deflate transport only. No work or codec calls at TOC load.
-- Authentication remains in Prepared/Summary; decoded bytes are never executed.
local R,W=TwichUI,TwichUI.Workshop
local C={BLOCK_BYTES=524288,ENCODED_BYTES=700000,YIELD='market-container-block'}
W.Containers=C
local function need(ok)if not ok then error('invalid Market container',0)end end
local function clock()return GetTimePreciseSec and GetTimePreciseSec()*1000 or debugprofilestop and debugprofilestop()or 0 end
local function closed(t,fields)
    need(type(t)=='table'and getmetatable(t)==nil);local n=0
    for k in pairs(t)do need(fields[k]);n=n+1 end
    local count=0;for k in pairs(fields)do need(t[k]~=nil);count=count+1 end;need(n==count)
end
local function pause()coroutine.yield(C.YIELD)end
local function stream(blocks,bytes,stats)
    need(type(blocks)=='table'and getmetatable(blocks)==nil)
    local count=math.ceil(bytes/C.BLOCK_BYTES);local n=0
    for i in pairs(blocks)do need(W.Int(i,1,count));n=n+1 end;need(n==count)
    local out={};local remaining=bytes
    for i=1,count do
        local block=blocks[i];closed(block,{bytes=true,payload=true})
        local size=math.min(C.BLOCK_BYTES,remaining)
        need(block.bytes==size and type(block.payload)=='string'and #block.payload>0
            and #block.payload<=C.ENCODED_BYTES and #block.payload%4==0
            and not block.payload:find('[^A-Za-z0-9+/=]'))
        need(C_EncodingUtil and type(C_EncodingUtil.DecodeBase64)=='function'
            and type(C_EncodingUtil.DecompressString)=='function'
            and Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate~=nil)
        need(not(InCombatLockdown and InCombatLockdown()))
        local at=clock();local ok,raw=pcall(C_EncodingUtil.DecodeBase64,block.payload)
        local dt=math.max(0,clock()-at);stats.base64_ms=stats.base64_ms+dt
        need(ok and type(raw)=='string'and #raw>0 and #raw<=C.ENCODED_BYTES*3/4)
        at=clock();local good,value=pcall(C_EncodingUtil.DecompressString,raw,Enum.CompressionMethod.Deflate)
        dt=math.max(0,clock()-at);stats.inflate_ms=stats.inflate_ms+dt;stats.worst_inflate_ms=math.max(stats.worst_inflate_ms,dt)
        stats.inflates=stats.inflates+1
        need(good and type(value)=='string'and #value==size)
        stats.output_bytes=stats.output_bytes+#value;out[i]=value;remaining=remaining-size
        -- A native call is synchronous. Always return to the existing scheduler
        -- before another block, even if a coroutine resume budget remains.
        pause()
    end
    need(remaining==0);return table.concat(out)
end
function C.Read(ctx,kind,bucket,p)
    need(ctx.count==32 and (kind=='Current'or kind=='History')and W.Int(bucket,0,kind=='Current'and 31 or 63))
    local global=kind=='Current'and 'TwichUIMarketCompressedCurrent'or 'TwichUIMarketCompressedHistory'
    local id=ctx.bank..('%02d'):format(bucket)
    local globals=_G[global];local blob=type(globals)=='table'and globals[id]
    if not blob then
        need(not(InCombatLockdown and InCombatLockdown())and C_AddOns and C_AddOns.LoadAddOn)
        local name='TwichUI_Market'..kind..'Container'..ctx.bank..('%02d'):format(math.floor(bucket/16))
        local at=clock();local ok,loaded=pcall(C_AddOns.LoadAddOn,name);local dt=math.max(0,clock()-at)
        ctx.stats.load_ms=ctx.stats.load_ms+dt;ctx.stats.worst_load_ms=math.max(ctx.stats.worst_load_ms,dt)
        need(ok and loaded);ctx.stats.container_loads=ctx.stats.container_loads+1
        globals=_G[global];blob=type(globals)=='table'and globals[id]
        pause()
    end
    closed(blob,kind=='Current'and {version=true,generation=true,content_id=true,data=true,proofs=true}
        or {version=true,generation=true,content_id=true,data=true})
    need(blob.version==1 and blob.generation==ctx.generation and blob.content_id==p.sha256)
    if kind=='Current'then
        local size=1;while size<math.max(1,p.record_count)do size=size*2 end
        local data=stream(blob.data,p.record_count*135,ctx.stats)
        local proofs=stream(blob.proofs,(2*size-1)*64,ctx.stats)
        return data,proofs
    end
    return stream(blob.data,p.bytes,ctx.stats)
end
function C.New(generation,bank,count)
    need(count==32 and (bank=='A'or bank=='B'))
    return {generation=generation,bank=bank,count=count,stats={container_loads=0,load_ms=0,worst_load_ms=0,
        base64_ms=0,inflate_ms=0,worst_inflate_ms=0,inflates=0,output_bytes=0}}
end
