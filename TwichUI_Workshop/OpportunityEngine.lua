-- One transient Opportunities catalog. No prices, history, or saved data live here.
-- Estimate remains the economic authority; item versions guard even suspended work.
local R,W=TwichUI,TwichUI.Workshop
local Op=W.Opps
local E={BUDGET_MS=2,MAX_STEPS=1024,MAX_RECIPES=10000}
W.OpportunityEngine=E
local Engine={};Engine.__index=Engine
local function clock()return GetTimePreciseSec and GetTimePreciseSec()*1000 or debugprofilestop and debugprofilestop()or 0 end
local function count(id,n)if R.Perf and R.Perf.on then R.Perf.Count('workshop.opportunities.'..id,n)end end
local function same(a,b)
    for _,k in ipairs({'id','outItem','outMin','outMax'})do if a[k]~=b[k]then return false end end
    if #(a.mats or {})~=#(b.mats or {})then return false end
    for i,m in ipairs(a.mats or {})do local n=b.mats[i];if m.item~=n.item or m.qty~=n.qty then return false end end
    for _,k in ipairs({'left','at','charges','max'})do if (a.cd and a.cd[k])~=(b.cd and b.cd[k])then return false end end
    return true
end
function Engine:InputsValid(row,serial)
    if row.context~=self.context then return false end
    serial=serial or row.serial
    for _,item in ipairs(row.dependencies)do if (self.versions[item]or 0)>serial then return false end end
    if row.inputs and row.inputs.cd and row.calculatedAt~=self.now then return false end
    return true
end
function Engine:Valid(row,serial)return self.byId[row.rec.id]==row and self:InputsValid(row,serial)end
local Row={__index=function(row,key)
    if key=='est'then return row._est and row.owner:Valid(row)and row._est or row.placeholder end
end}
function E.New(changed)
    return setmetatable({context=0,serial=0,token=0,all={},rows={},byId={},dependencies={},versions={},incoming={},
        summary={total=0,priced=0,profitable=0},waiting=0,pending=0,completed=0,changed=changed,stats={}},Engine)
end
function Engine:Add(row,front)
    if row.queued then
        if not front or self.head==row then return end
        if row.prev then row.prev.next=row.next else self.head=row.next end
        if row.next then row.next.prev=row.prev else self.tail=row.prev end
    else row.queued=true;self.pending=self.pending+1 end
    if front then row.prev=nil;row.next=self.head;if self.head then self.head.prev=row else self.tail=row end;self.head=row
    else row.next=nil;row.prev=self.tail;if self.tail then self.tail.next=row else self.head=row end;self.tail=row end
end
function Engine:Pop()
    local row=self.head;if not row then return end
    self.head=row.next;if self.head then self.head.prev=nil else self.tail=nil end
    row.prev,row.next,row.queued=nil,nil,false;self.pending=self.pending-1;return row
end
function Engine:Remove(row)
    if not row.queued then return end
    if row.prev then row.prev.next=row.next else self.head=row.next end
    if row.next then row.next.prev=row.prev else self.tail=row.prev end
    row.prev,row.next,row.queued=nil,nil,false;self.pending=self.pending-1
end
function Engine:Prioritize(ids)
    self.visible=ids
    for i=math.min(#ids,128),1,-1 do local row=self.byId[ids[i]];if row and row.queued then self:Add(row,true)end end
end
function Engine:RetryWaiting()
    if not self.args or self.paused then return end
    self.retry=true;self:EnsureWorker();self:Schedule()
end
function Engine:Work()coroutine.yield()end
function Engine:Metric(id,n)self.stats[id]=(self.stats[id]or 0)+(n or 1);count(id,n)end
function Engine:Dirty(row)
    if not row.dirty then
        row.dirty=true;row.displayRevision=row.displayRevision+1
        self.rankValid=false
        if row.counted then
            self.summary.priced=self.summary.priced-1
            if row._est.profitLow>0 then self.summary.profitable=self.summary.profitable-1 end
            row.counted=false
        end
        row._est=nil
        if row.done then row.done=false;self.completed=self.completed-1 end
        if row.waiting then row.waiting=false;self.waiting=self.waiting-1 end
        self:Metric('invalidations')
    end
    self:Add(row)
end
function Engine:ItemsChanged(items)
    if not self.args then return end
    local touched=false
    for item in pairs(items or {})do
        if self.building or self.dependencies[item]then
            self.serial=self.serial+1;self.versions[item]=self.serial;self.incoming[item]=self.serial;touched=true
            if self.args.estimator then self.args.estimator:InvalidateItem(item)end
        end
    end
    if touched then self.presentDirty=true;self:EnsureWorker();self:Schedule()end
end
function Engine:ApplyIncoming()
    while true do
        local item,version=next(self.incoming);if not item then return end
        self.incoming[item]=nil
        for _,row in ipairs(self.dependencies[item]or {})do
            if row.serial<version then self:Dirty(row)end
            self:Work()
        end
    end
end
function Engine:Notify()
    if self.notifying or not(C_Timer and C_Timer.After)then return end
    self.notifying=true;local token=self.token
    C_Timer.After(.1,function()
        if token~=self.token then return end
        self.notifying=false;if self.changed and not self.paused then self.changed()end
    end)
end
function Engine:Cancel(clear)
    local hadWork=self.co~=nil or self.pending>0
    if self.args and self.args.release then self.args.release()end
    self.token=self.token+1;self.co=nil;self.scheduled=false;self.notifying=false;self.paused=true
    if self.args and self.args.estimator then self.args.estimator.work=nil;self.args.estimator.worker=nil end
    if hadWork then self:Metric('cancelled')end
    if self.building or self.preparing then self.recipes=nil end
    if clear then
        self.args=nil;self.recipes=nil;self.context=self.context+1;self.all={};self.rows={};self.byId={};self.dependencies={};self.versions={};self.incoming={}
        self.head,self.tail=nil,nil;self.pending,self.waiting,self.completed=0,0,0;self.summary={total=0,priced=0,profitable=0}
        self.timed={};self.timeDirty=false;self.presentDirty=false;self.groups=nil;self.groupOrder=nil
        self.provisional=nil;self.positions=nil;self.old=nil;self.buildRecipes=nil;self.visible=nil
        self.presentedCatalog,self.presentedFilter=nil,nil
        self.failedKey,self.failedRecipes,self.failedRevision=nil,nil,nil
    end
end
function Engine:Build(recipes,old)
    self.building=true
    local groups,groupOrder={},{}
    for i,rec in ipairs(recipes)do
        local previous=old and old[rec.id]
        local reusable=previous and previous._est and self:InputsValid(previous)and same(previous.inputs,rec)
        local row=setmetatable({owner=self,context=self.context,rec=rec,serial=self.serial,dependencies={},displayRevision=1,
            placeholder={state='unknown',why='calculating',mats={},outMin=rec.outMin,outMax=rec.outMax}},Row)
        row.inputs={id=rec.id,outItem=rec.outItem,outMin=rec.outMin,outMax=rec.outMax,mats={}}
        if rec.cd then row.inputs.cd={left=rec.cd.left,at=rec.cd.at,charges=rec.cd.charges,max=rec.cd.max}end
        local seen={}
        local function dep(item)
            if item and not seen[item]then
                seen[item]=true;row.dependencies[#row.dependencies+1]=item
                local list=self.dependencies[item]
                if not list then
                    list={};self.dependencies[item]=list
                    local bucket=item%64
                    if not groups[bucket]then groups[bucket]={};groupOrder[#groupOrder+1]=bucket end
                    groups[bucket][#groups[bucket]+1]=item
                end
                list[#list+1]=row
            end
        end
        dep(rec.outItem);for i,m in ipairs(rec.mats or {})do dep(m.item);row.inputs.mats[i]={item=m.item,qty=m.qty};self:Work()end
        self.all[i]=row;self.byId[rec.id]=row
        if rec.cd then self.timed[#self.timed+1]=row end
        row.calculatedAt=self.now
        if reusable then
            row._est=previous._est;row.serial=previous.serial;row._est._rec=rec;self:Metric('reused')
            row.done=true;self.completed=self.completed+1
            if row._est.state=='ok'then row.counted=true;self.summary.priced=self.summary.priced+1;if row._est.profitLow>0 then self.summary.profitable=self.summary.profitable+1 end end
        else row.dirty=true;self:Add(row)end
        self:Work()
    end
    self.building=false;self.presentDirty=true;self.provisional=self.all
    self.groups,self.groupOrder=groups,groupOrder
    if self.args.prefetch then
        self.preparing=true
        local prepared={};local position=1
        local defaults={};for i=1,math.min(12,#self.all)do defaults[i]=self.all[i].rec.id end
        while true do
            local bucket
            local visible=self.visible and #self.visible>0 and self.visible or defaults
            for _,id in ipairs(visible)do
                local row=self.byId[id]
                if row then for _,item in ipairs(row.dependencies)do if not prepared[item%64]then bucket=item%64;break end end end
                if bucket then break end
            end
            if not bucket then
                while groupOrder[position]and prepared[groupOrder[position]]do position=position+1 end
                bucket=groupOrder[position]
            end
            if not bucket then break end
            prepared[bucket]=true
            self.args.prefetch(groups[bucket],function()self:Work()end)
            self:ApplyIncoming()
            local useful=false
            for _,id in ipairs(visible)do
                local row=self.byId[id];local ready=row and row.queued
                if row then
                for _,item in ipairs(row.dependencies)do if not self.args.settled(item)then ready=false;break end end
                if ready then self:Remove(row);self:Calculate(row);useful=true end
                self:Work()
                end
            end
            if useful then self:Present()end
        end
        self.preparing=false
    end
end
function Engine:Calculate(row)
    local args=self.args;local est=args.estimator;local serial=self.serial;local when=self.now
    local waiting=false
    if est then
        if est.size>=20000 then est:ClearMemo()end
        for _,item in ipairs(row.dependencies)do
            if args.ready and not args.ready(item)then waiting=true
            else
            local _,why=est:Ask('price',item);if why=='loading'or why=='combat'then waiting=true end
            if est.ctx.reference then local _,reason=est:Ask('reference',item);if reason=='loading'or reason=='combat'then waiting=true end end
            end
            self:Work()
        end
    end
    local result
    if not waiting then
        self:Metric('crafts')
        result=est and est:Craft(row.rec,1)or W.Prices.Estimate(row.rec,args.lookup,args.rate)
    end
    row.calculatedAt=when
    if not self:Valid(row,serial)then self:Add(row);return end
    row.serial=serial;row.dirty=false;row._est=result;row.displayRevision=row.displayRevision+1
    self.rankValid=false
    if waiting then row.waiting=true;self.waiting=self.waiting+1
    else
        row.done=true;self.completed=self.completed+1
        if result and result.state=='ok'then row.counted=true;self.summary.priced=self.summary.priced+1;if result.profitLow>0 then self.summary.profitable=self.summary.profitable+1 end end
    end
    self:Metric('calculated');self.presentDirty=true
end
function Engine:Present()
    if self.args.current and not self.args.current()then self.obsolete=true;return end
    local serial,filterKey=self.serial,self.filterKey
    local partial=self.pending>0 or self.waiting>0 or self.building
    -- These filters depend only on recipe metadata. Stable row objects already
    -- expose new estimates; rebuilding their membership on every 128 results
    -- makes large bursts quadratic. Price/confidence filters must be rebuilt.
    if partial and not self.filter.profitOnly and not self.filter.hideLow
        and self.presentedCatalog==self.all and self.presentedFilter==filterKey then
        self.final=false;self.presentDirty=false;self.viewRevision=(self.viewRevision or 0)+1
        self:Metric('partialReuses');self:Metric('partialPublications');self:Notify();return
    end
    local ordered,rows,positions={},{},{}
    for _,row in ipairs(self.provisional or self.all)do
        ordered[#ordered+1]=row
        self:Work();if serial~=self.serial or filterKey~=self.filterKey then return end
    end
    local rankKey=(self.filter.sort or 'profit')..':'..tostring(self.filter.desc~=false)
    if not partial and(not self.rankValid or self.rankKey~=rankKey)then
        self:Metric('sorts')
        local less=Op.Comparator(self.filter)
        local source,dest=ordered,{};local width=1
        while width<#ordered do
            for start=1,#ordered,2*width do
                local a,b=start,start+width;local ae,be=math.min(start+width-1,#ordered),math.min(start+2*width-1,#ordered)
                for at=start,be do
                    if a<=ae and(b>be or less(source[a],source[b]))then dest[at]=source[a];a=a+1 else dest[at]=source[b];b=b+1 end
                    self:Work();if serial~=self.serial or filterKey~=self.filterKey then return end
                end
            end
            source,dest=dest,source;width=width*2
        end
        ordered=source;self.provisional=ordered;self.rankValid=true;self.rankKey=rankKey
    end
    for _,row in ipairs(ordered)do
        if Op.Keep(row,self.filter)then rows[#rows+1]=row end
        self:Work();if serial~=self.serial or filterKey~=self.filterKey then return end
    end
    for i,row in ipairs(rows)do positions[row.rec.id]=i;self:Work();if serial~=self.serial or filterKey~=self.filterKey then return end end
    self.rows,self.positions=rows,positions;self.final=not partial;self.presentDirty=false
    self.presentedCatalog,self.presentedFilter=self.all,filterKey
    self.viewRevision=(self.viewRevision or 0)+1;self:Metric(partial and 'partialPublications'or 'fullPublications');self:Notify()
end
function Engine:EnsureWorker()
    if self.co or self.paused or not self.args then return end
    if not self.buildRecipes and not self.head and not next(self.incoming)and not self.presentDirty and not self.timeDirty and not self.retry then return end
    self.co=coroutine.create(function()
        if self.buildRecipes then local recipes,old=self.buildRecipes,self.old;self.buildRecipes,self.old=nil,nil;self:Build(recipes,old)end
        local since=0
        while true do
            if self.retry then
                self.retry=false
                for _,row in ipairs(self.all)do if row.waiting then self:Dirty(row)end;self:Work()end
                if self.args.prefetch then
                    self.preparing=true
                    for _,bucket in ipairs(self.groupOrder or {})do self.args.prefetch(self.groups[bucket],function()self:Work()end)end
                    self.preparing=false
                end
            end
            if self.timeDirty then
                self.timeDirty=false
                for _,row in ipairs(self.timed or {})do self:Dirty(row);self:Work()end
            end
            self:ApplyIncoming()
            local row=self:Pop()
            if row then self:Calculate(row);since=since+1;self:Work()end
            if self.presentDirty and(not self.head or since>=128)then self:Present();since=0 end
            if self.obsolete then return end
            if not self.head and not next(self.incoming)and not self.presentDirty then return end
        end
    end)
end
function Engine:RecordBatch(at,pt)
    local elapsed=math.max(0,clock()-at)
    self.stats.worstBatch=math.max(self.stats.worstBatch or 0,elapsed);self:Metric('batches')
    if pt then R.Perf.Stop(pt)end
end
function Engine:Step()
    if self.stepping or not self.co or self.paused then return end
    local at=clock();local perf=R.Perf
    local pt=perf and perf.on and perf.Start('workshop.opportunityBatch')
    local valid=true
    if self.args.valid then
        if perf and perf.on then valid=perf.Call('workshop.opportunitySource',self.args.valid)
        else valid=self.args.valid()end
    end
    if not valid then self:Cancel(true);self.paused=false;self:Notify();self:RecordBatch(at,pt);return end
    self.stepping=true;local n=0
    local est=self.args.estimator
    if est then est.worker=self.co;est.work=function()self:Work()end end
    local limit=(GetTimePreciseSec or debugprofilestop)and E.MAX_STEPS or 32
    repeat
        local ok,why=coroutine.resume(self.co);n=n+1
        if not ok then
            local key,recipes,revision=self.key,self.recipes,self.catalogRevision
            self:Cancel(true);self.failedKey,self.failedRecipes,self.failedRevision=key,recipes,revision
            self.error='calculation_failed';self:Metric('errors');if R.Fault then R.Fault('opportunities',why)end;break
        end
        if coroutine.status(self.co)=='dead'then self.co=nil;break end
    until n>=limit or clock()-at>=E.BUDGET_MS
    self:RecordBatch(at,pt)
    if not self.co and est then est.work=nil;est.worker=nil end
    self.stepping=false
    if self.obsolete then self.obsolete=false;self:Cancel(true);self.paused=false;self:Notify()end
end
function Engine:Schedule()
    if self.scheduled or not self.co or self.paused or not(C_Timer and C_Timer.After)then return end
    self.scheduled=true;local token=self.token
    C_Timer.After(0,function()
        if token~=self.token then return end
        local pt=R.Perf and R.Perf.on and R.Perf.Start('workshop.opportunityCallback')
        self.scheduled=false;self:Step();self:Schedule()
        if pt then R.Perf.Stop(pt)end
    end)
end
function Engine:Request(args)
    if #args.recipes>E.MAX_RECIPES then self:Cancel(true);self.error='recipe_limit';return end
    if self.failedKey==args.key and self.failedRecipes==args.recipes and self.failedRevision==args.catalogRevision then return end
    local reset=not self.args or self.key~=args.key
    local catalog=self.recipes~=args.recipes or self.catalogRevision~=args.catalogRevision
    if reset or catalog then
        self.error=nil
        self:Metric('catalogBuilds')
        local old=not reset and self.byId or nil
        self:Cancel(false);self.paused=false
        if reset then self.context=self.context+1;self.versions={};self.incoming={};self:Metric('fullInvalidations')end
        self.all={};self.rows={};self.byId={};self.dependencies={};self.head,self.tail=nil,nil;self.timed={}
        self.presentedCatalog,self.presentedFilter=nil,nil
        self.summary={total=#args.recipes,priced=0,profitable=0};self.pending,self.waiting,self.completed=0,0,0
        self.recipes=args.recipes;self.buildRecipes=args.recipes;self.old=old;self.building=true;self.final=false
        self.rankValid=false
    elseif self.paused then
        self.paused=false
        for _,row in ipairs(self.all)do if row.waiting or row.dirty or not self:Valid(row)or row._est and row._est.vendorSellWhy=='loading'then self:Dirty(row)end end
    else self:Metric('cacheHits')end
    self.args=args
    self.key,self.catalogRevision=args.key,args.catalogRevision
    if self.now~=args.now then self.now=args.now;if #(self.timed or {})>0 then self.timeDirty=true end end
    local f=args.filter or Op.DEFAULTS
    local key=table.concat({f.sort or 'profit',tostring(f.desc~=false),tostring(f.prof),tostring(f.profitOnly==true),tostring(f.hideLow==true)},':')
    if key~=self.filterKey then
        self.filterKey=key;self.filter={sort=f.sort,desc=f.desc,prof=f.prof,profitOnly=f.profitOnly,hideLow=f.hideLow}
        self.rows={};self.positions={};self.presentDirty=true;self.final=false
    end
    self:EnsureWorker();if reset or catalog then self:Step()end;self:Schedule()
end
function Engine:Status()
    local out={};for k,v in pairs(self.stats)do out[k]=v end
    out.known=self.summary.total;out.pending=self.pending;out.waiting=self.waiting;out.settled=self.completed;out.running=self.co~=nil
    out.retained=#self.all;out.refreshing=self.co~=nil or self.pending>0 or self.waiting>0 or self.presentDirty==true
    return out
end
