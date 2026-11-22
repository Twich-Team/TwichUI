-- Authenticated current tuples; history and economic policy stay in Summary/Pricing.
-- Immutable strings, positional proofs and bounded queues; no saved state or timers.
local R,W=TwichUI,TwichUI.Workshop
local J,S=W.BridgeCodec,W.BridgeValidate
local M={WIDTH=135,MAX_PART=4194304,MAX_TOTAL=33554432,MAX_PENDING=8192}
W.Prepared=M
local N=J.NULL
local widths={8,64,1,10,10,10,14,1,1,10,2,2,2}
local maxima={2147483647,0,4,99999999999,99999999999,99999999999,9007199254740991,0,1,99999999999,14,60,60}
local nullable={[4]=true,[5]=true,[6]=true,[7]=true,[10]=true}
local money={[4]=true,[5]=true,[6]=true,[10]=true}
local offsets={};local offset=0
for i,n in ipairs(widths)do offsets[i]=offset;offset=offset+n end
local EMPTY_ROWS=J.SHA('[]');local EMPTY_ROOT=J.SHA('empty\0')
local function need(ok)if not ok then error('invalid prepared current data',0)end end
local function digest(v)return type(v)=='string'and #v==64 and not v:find('[^0-9a-f]')end
local function tick()coroutine.yield()end
local function closed(value,keys)
    need(type(value)=='table');local n=0
    for k in pairs(value)do n=n+1;need(keys[k] and n<=32)end
    local size=0;for k in pairs(keys)do size=size+1;need(value[k]~=nil)end;need(n==size)
end
local function hex(word)
    need(not word:find('[^0-9a-f]'))
    if #word>7 then return tonumber(word:sub(1,-8),16)*268435456+tonumber(word:sub(-7),16)end
    return tonumber(word,16)
end
local function key(part,pos)
    need(pos>=1 and pos<=part.n)
    local at=(pos-1)*M.WIDTH
    local item=hex(part.data:sub(at+1,at+8));local variant=part.data:sub(at+9,at+72)
    need(W.Int(item,1,2147483647)and digest(variant));return item,variant
end
local function row(part,pos)
    need(pos>=1 and pos<=part.n);local out=J.Array();local at=(pos-1)*M.WIDTH
    for i,width in ipairs(widths)do
        local word=part.data:sub(at+offsets[i]+1,at+offsets[i]+width)
        if i==2 then need(digest(word));out[i]=word
        elseif word==string.rep('z',width)then need(nullable[i]);out[i]=N
        else
            local value=hex(word);need(W.Int(value,0,maxima[i]))
            out[i]=money[i] and ('%.0f'):format(value)or value
        end
    end
    return out
end
local function valid(r,bucket,count)
    need(W.Int(r[1],1,2147483647)and r[1]%count==bucket and digest(r[2]))
    local any=r[4]~=N or r[5]~=N or r[6]~=N or r[10]~=N
    for i in pairs(money)do need(r[i]==N or S.Money(r[i],true)and r[i]~='0')end
    if r[3]==0 then need(any and r[9]==0 and W.Int(r[7],1,9007199254740991))
    elseif r[3]==1 then need(not any and r[9]==1 and W.Int(r[7],1,9007199254740991))
    elseif r[3]==2 then need(not any and r[9]==1 and r[7]==0)
    else need(not any and r[9]==1 and r[7]==N)end
    need(r[11]<=r[12]and r[12]<=r[13]and(r[10]==N or r[12]>=3)and(r[5]==N or r[11]>0))
end
local function less(ai,ak,bi,bk)return ai<bi or ai==bi and ak<bk end
local function lower(part,item,variant)
    local a,b=1,part.n
    while a<=b do local m=math.floor((a+b)/2);local id,k=key(part,m)
        if less(id,k,item,variant)then a=m+1 else b=m-1 end
    end
    return a
end
local function flagged(part,pos)
    if part.full then return true end
    local word=math.floor((pos-1)/32)+1;return bit.band(part.bits[word]or 0,bit.lshift(1,(pos-1)%32))~=0
end
local function mark(ctx,part,pos)
    if flagged(part,pos)then return end
    local word=math.floor((pos-1)/32)+1
    if not part.bits[word]then ctx.stats.flag_words=ctx.stats.flag_words+1 end
    part.bits[word]=bit.bor(part.bits[word]or 0,bit.lshift(1,(pos-1)%32))
    part.verified=part.verified+1;ctx.stats.verified=ctx.stats.verified+1
end
local function hash(ctx,text)
    ctx.stats.hashes=ctx.stats.hashes+1;return J.SHA(text,tick)
end
function M.Begin(text,h,bank,work)
    need(type(text)=='string'and #text<=65536)
    local a=J.Parse(text,work)
    if type(a)=='table'and W.Int(a.version,2,2147483647)then error('summary newer_addon',0)end
    closed(a,{format=true,version=true,source_generation_id=true,partitions_count=true,record_width=true,hash_algorithm=true,record_count=true,partitions=true,attestation_id=true})
    need(h.contract_version==3 and a.format=='twichui-workshop-prepared-current'and a.version==1
        and(a.partitions_count==16 or a.partitions_count==32)and a.record_width==135
        and a.hash_algorithm=='sha256-canonical-13-v1'and a.source_generation_id==h.generation_id
        and a.record_count==h.record_count and digest(a.attestation_id)and J.Encode(a,work)==text)
    local body=J.Object();for k,v in pairs(a)do if k~='attestation_id'then body[k]=v end end
    need(J.SHA(J.Encode(body,work),work)==a.attestation_id)
    need(type(a.partitions)=='table'and #a.partitions==a.partitions_count)
    local descriptors,total,records={},0,0
    for i,p in ipairs(a.partitions)do
        closed(p,{bucket=true,record_count=true,bytes=true,sha256=true,merkle_root=true})
        need(p.bucket==i-1 and W.Int(p.record_count,0,150000)and W.Int(p.bytes,2,M.MAX_PART)and digest(p.sha256)and digest(p.merkle_root))
        local size=1;while size<math.max(1,p.record_count)do size=size*2 end
        local bytes=p.record_count*M.WIDTH+(2*size-1)*64;total=total+bytes;records=records+p.record_count
        need(bytes<=M.MAX_PART and total<=M.MAX_TOTAL)
        if p.record_count==0 then need(p.bytes==2 and p.sha256==EMPTY_ROWS and p.merkle_root==EMPTY_ROOT)end
        descriptors[p.bucket]=p;if work then work()end
    end
    need(records==a.record_count)
    return {manifest=a,bank=bank,count=a.partitions_count,descriptors=descriptors,parts={},pending={},pendingCount=0,
        high={},low={},priority={},dense={},epoch=0,stats={loads=0,bytes=0,hashes=0,verified=0,full=0,flag_words=0,cache_hits=0,cancelled=0}}
end
local function load(ctx,bucket)
    local part=ctx.parts[bucket];if part then return part end
    need(not(InCombatLockdown and InCombatLockdown()))
    local p=ctx.descriptors[bucket];local id=ctx.bank..('%02d'):format(bucket)
    local globals=TwichUIMarketCurrentParts;local blob=type(globals)=='table'and globals[id]
    if not blob then
        need(C_AddOns and C_AddOns.LoadAddOn)
        local function addon()return pcall(C_AddOns.LoadAddOn,'TwichUI_MarketCurrentPart'..id)end
        local ok,loaded
        if R.Perf and R.Perf.Call then ok,loaded=R.Perf.Call('workshop.preparedLoad',addon)else ok,loaded=addon()end
        need(ok and loaded);globals=TwichUIMarketCurrentParts;blob=type(globals)=='table'and globals[id]
    end
    need(type(blob)=='table'and getmetatable(blob)==nil)
    closed(blob,{version=true,layout=true,content_id=true,data=true,proofs=true})
    local size=1;while size<math.max(1,p.record_count)do size=size*2 end
    need(blob.version==1 and blob.layout==ctx.count and blob.content_id==p.sha256
        and type(blob.data)=='string'and #blob.data==p.record_count*M.WIDTH
        and type(blob.proofs)=='string'and #blob.proofs==(2*size-1)*64)
    -- Capture immutable strings, not the mutable global envelope table.
    part={data=blob.data,proofs=blob.proofs,n=p.record_count,size=size,bits={},verified=0,bucket=bucket}
    ctx.parts[bucket]=part;ctx.stats.loads=ctx.stats.loads+1;ctx.stats.bytes=ctx.stats.bytes+#part.data+#part.proofs
    need(ctx.stats.bytes<=M.MAX_TOTAL);return part
end
local function authenticate(ctx,part,pos)
    if flagged(part,pos)then return end
    local r=row(part,pos);valid(r,part.bucket,ctx.count)
    local index=part.size+pos-1;local value=hash(ctx,'row\0'..J.Encode(r,tick))
    while index>1 do
        local siblingIndex=index%2==0 and index+1 or index-1
        local sibling=part.proofs:sub((siblingIndex-1)*64+1,siblingIndex*64);need(digest(sibling))
        value=hash(ctx,'node\0'..(index%2==0 and value..sibling or sibling..value));index=math.floor(index/2)
    end
    need(value==ctx.descriptors[part.bucket].merkle_root);mark(ctx,part,pos)
end
local function locate(part,item,variant)
    local pos=lower(part,item,variant)
    if pos<=part.n then local id,k=key(part,pos);if id==item and k==variant then return pos,true end end
    return pos,false
end
local function missingBounds(part,pos,item,variant)
    if pos>1 then local id,k=key(part,pos-1);need(less(id,k,item,variant))end
    if pos<=part.n then local id,k=key(part,pos);need(less(item,variant,id,k))end
end
local function ready(part,pos,found,item,variant)
    if found then return flagged(part,pos)end
    if (pos==1 or flagged(part,pos-1))and(pos>part.n or flagged(part,pos))then
        missingBounds(part,pos,item,variant);return true
    end
end
local function prove(ctx,part,item,variant)
    local pos,found=locate(part,item,variant)
    if found then authenticate(ctx,part,pos)
    else
        if pos>1 then authenticate(ctx,part,pos-1);local id,k=key(part,pos-1);need(less(id,k,item,variant))end
        if pos<=part.n then authenticate(ctx,part,pos);local id,k=key(part,pos);need(less(item,variant,id,k))end
    end
end
local ZERO,MAXKEY=string.rep('0',64),string.rep('f',64)
local function range(part,item,limit,ctx)
    local first=lower(part,item,ZERO);local after=lower(part,item,MAXKEY)
    if after<=part.n then local id,k=key(part,after);if id==item and k==MAXKEY then after=after+1 end end
    local function check(pos)
        if pos>=1 and pos<=part.n then
            if ctx then authenticate(ctx,part,pos)else return flagged(part,pos)end
        end
        return true
    end
    if not check(first-1)or not check(after)then return end
    if first>1 then local id=key(part,first-1);need(id<item)end
    if after<=part.n then local id=key(part,after);need(id>item)end
    need(after>=first)
    local out={}
    for i=first,math.min(after-1,first+limit-1)do
        if not check(i)then return end
        local id,k=key(part,i);need(id==item);out[#out+1]=k
    end
    return out,after-first>#out
end
local function unlink(task)
    local queue=task.queue;if not queue then return end
    if task.prev then task.prev.next=task.next else queue.first=task.next end
    if task.next then task.next.prev=task.prev else queue.last=task.prev end
    task.prev,task.next,task.queue=nil,nil,nil
end
local function enqueue(ctx,task,high)
    unlink(task);local queue=high and ctx.high or ctx.low;task.queue=queue
    if high then task.next=queue.first;if queue.first then queue.first.prev=task else queue.last=task end;queue.first=task
    else task.prev=queue.last;if queue.last then queue.last.next=task else queue.first=task end;queue.last=task end
end
local function remove(ctx,task)
    unlink(task)
    if task.id and ctx.pending[task.id]==task then ctx.pending[task.id]=nil;ctx.pendingCount=ctx.pendingCount-1 end
end
local function owner(task,value)
    if not value then task.shared=true;return end
    if task.shared or task.owners[value]then return end
    local n=0;for _ in pairs(task.owners)do n=n+1 end
    if n>=8 then task.shared=true;task.owners={}else task.owners[value]=true end
end
local function reserve(ctx,id,kind,item,variant,opt)
    local task=ctx.pending[id]
    if not task then
        if ctx.pendingCount>=M.MAX_PENDING then return nil,'lookup_limit'end
        task={id=id,kind=kind,item=item,variant=variant,bucket=item%ctx.count,owners={}}
        ctx.pending[id]=task;ctx.pendingCount=ctx.pendingCount+1;enqueue(ctx,task,ctx.priority[item]or not(opt and opt.owner))
    end
    owner(task,opt and opt.owner);return task
end
function M.Record(ctx,item,variant,opt)
    local p=ctx.descriptors[item%ctx.count];if p.record_count==0 then return nil,'not_observed'end
    local part=ctx.parts[p.bucket]
    if part then
        local ok,pos,found=pcall(locate,part,item,variant);if not ok then return nil,'invalid'end
        local safe,isReady=pcall(ready,part,pos,found,item,variant);if not safe then return nil,'invalid'end
        if isReady then
            ctx.stats.cache_hits=ctx.stats.cache_hits+1
            if found then local ok,r=pcall(row,part,pos);if not ok then return nil,'invalid'end;return r end
            return nil,'not_observed'
        end
    end
    if InCombatLockdown and InCombatLockdown()then return nil,'combat'end
    local task,why=reserve(ctx,'r:'..item..':'..variant,'record',item,variant,opt)
    return nil,task and 'loading'or why
end
function M.Variants(ctx,item,limit)
    if ctx.descriptors[item%ctx.count].record_count==0 then return {},false end
    local part=ctx.parts[item%ctx.count]
    if part then
        local ok,out,truncated=pcall(range,part,item,limit)
        if not ok then return nil,'invalid'end
        if out then return out,truncated end
    end
    if InCombatLockdown and InCombatLockdown()then return nil,'combat'end
    local task,why=reserve(ctx,'v:'..item..':'..limit,'range',item,nil)
    if task then task.limit=limit end
    return nil,task and 'loading'or why
end
function M.Shared(ctx,item,variant)
    local task=ctx.pending['r:'..item..':'..variant];if task then task.shared=true end
end
function M.Plan(ctx,dependencies,visible,work,lease)
    local counts,n={},0;local epoch=ctx.epoch
    for item in pairs(dependencies)do
        local b=item%ctx.count;counts[b]=(counts[b]or 0)+1;n=n+1
        if work then work()end;if ctx.epoch~=epoch then return end
        if n>=M.MAX_PENDING then break end
    end
    ctx.planOwner=lease;ctx.dense={}
    for b,count in pairs(counts)do
        local p=ctx.descriptors[b];local size,depth=1,0
        while size<math.max(1,p.record_count)do size=size*2;depth=depth+1 end
        ctx.dense[b]=count*(depth+1)*3>p.bytes/64
    end
    M.Prioritize(ctx,visible)
end
function M.Prioritize(ctx,items)
    ctx.priority={}
    for i=math.min(#items,512),1,-1 do
        local item=items[i];ctx.priority[item]=true
        -- P's already-reserved key avoids rehashing base identities on redraw.
        local k=W.Pricing and W.Pricing.PendingKey and W.Pricing.PendingKey(item)
        local task=k and ctx.pending['r:'..item..':'..k]
        if task and not task.co then enqueue(ctx,task,true)end
    end
end
function M.Cancel(ctx)
    ctx.epoch=ctx.epoch+1;ctx.pending={};ctx.pendingCount=0;ctx.high={};ctx.low={};ctx.running=nil;ctx.bulk=nil;ctx.priority={};ctx.dense={};ctx.planOwner=nil
end
function M.Release(ctx,lease)
    for _,task in pairs(ctx.pending)do
        task.owners[lease]=nil
        if not task.shared and not next(task.owners)then task.cancelled=true;remove(ctx,task);ctx.stats.cancelled=ctx.stats.cancelled+1 end
    end
    if ctx.planOwner==lease then ctx.bulk=nil;ctx.dense={};ctx.priority={};ctx.planOwner=nil end
end
local function full(ctx,part)
    local hash=J.Hash(tick);hash:Update('[')
    for i=1,part.n do if i>1 then hash:Update(',')end;hash:Update(J.Encode(row(part,i),tick));tick()end
    hash:Update(']');need(hash:Finish()==ctx.descriptors[part.bucket].sha256)
    for _ in pairs(part.bits)do ctx.stats.flag_words=ctx.stats.flag_words-1 end
    part.full=true;part.bits={};ctx.stats.full=ctx.stats.full+1
end
function M.Pending(ctx)return ctx.pendingCount>0 or ctx.bulk~=nil end
function M.Work(ctx,completed,notify)
    local epoch=ctx.epoch
    while epoch==ctx.epoch and M.Pending(ctx)do
        local task=ctx.running
        if task and task.cancelled then ctx.running=nil;task=nil end
        if not task then
            task=ctx.high.first
            if task then unlink(task);ctx.running=task
            elseif ctx.bulk then task=ctx.bulk
            else
                task=ctx.low.first
                if task then
                    local part=ctx.parts[task.bucket]
                    if task.kind=='record'and ctx.dense[task.bucket]and not(part and part.full)then
                        task={kind='bulk',bucket=task.bucket};ctx.bulk=task
                    else unlink(task);ctx.running=task end
                end
            end
        end
        if not task then break end
        if InCombatLockdown and InCombatLockdown()then
            ctx.bulk=nil
            if task.kind=='record'then completed(task.item,task.variant,'combat')end
            remove(ctx,task);ctx.running=nil
        else
            if not task.co then task.co=coroutine.create(function()
                local part=load(ctx,task.bucket)
                if task.kind=='record'then prove(ctx,part,task.item,task.variant)
                elseif task.kind=='bulk'or task.kind=='full'then full(ctx,part)
                elseif task.kind=='range'then range(part,task.item,task.limit,ctx)
                else error('invalid prepared task',0)end
            end)end
            local ok,why=coroutine.resume(task.co);if not ok then error(why,0)end
            if coroutine.status(task.co)=='dead'then
                if task.kind=='bulk'then ctx.bulk=nil
                else remove(ctx,task);ctx.running=nil
                    if task.kind=='record'then completed(task.item,task.variant)else notify()end
                end
            end
        end
        tick()
    end
end
function M.EnsurePart(ctx,bucket)
    if ctx.descriptors[bucket].record_count==0 then return true end
    local part=ctx.parts[bucket];if part and part.full then return true end
    if InCombatLockdown and InCombatLockdown()then return nil,'combat'end
    local task,why=reserve(ctx,'f:'..bucket,'full',bucket,nil)
    return nil,task and 'loading'or why
end
function M.ItemAt(ctx,bucket,pos)return key(ctx.parts[bucket],pos)end
function M.Status(ctx)local out={};for k,v in pairs(ctx.stats)do out[k]=v end;out.pending=ctx.pendingCount;return out end
