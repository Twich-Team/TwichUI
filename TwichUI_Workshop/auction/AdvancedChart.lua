-- Market-only presentation. Typed evidence in, pooled geometry out; no saved data.
local R,W=TwichUI,TwichUI.Workshop
local UI=W.UI
local C={MAX_COLUMNS=1024}
local activeChart
if R.Perf.Gauge then
    R.Perf.Gauge('auction.chartPool',{label='Market chart pooled regions',unit='count',kind='pool',group='auction',read=function() return activeChart and #activeChart.pool+#activeChart.linePool or 0 end})
    R.Perf.Gauge('auction.chartRecords',{label='Market chart visible evidence',unit='count',kind='cache',group='auction',read=function() return activeChart and activeChart.data and #activeChart.data.points+#activeChart.data.groups or 0 end})
end
W.AdvancedChart=C
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function Day(d) return date('!%Y-%m-%d',math.floor(d*86400)) end
-- Preparation is deliberately separate from pointer work. Preserve original records.
function C.Prepare(s,from,to)
    local d={points={},groups={},gaps=s and s.gaps or {},from=from or s and s.from or 0,to=to or s and s.to or 1}
    d.to=math.max(d.from+1/86400,d.to)
    for _,p in ipairs(s and s.points or {}) do
        if p.day>=d.from and p.day<=d.to and type(p.price)=='number' then d.points[#d.points+1]=p end
    end
    table.sort(d.points,function(a,b)return a.day<b.day end)
    local lo,hi
    local function Value(v) if v then lo=math.min(lo or v,v);hi=math.max(hi or v,v) end end
    for _,p in ipairs(d.points) do Value(p.price) end
    for _,g in ipairs(s and s.groups or {}) do
        if g.to>=d.from and g.from<=d.to then d.groups[#d.groups+1]=g;Value(g.low or g.average);Value(g.high or g.average) end
    end
    local pad=math.max(1,((hi or 1)-(lo or 0))*.12,(hi or 1)*.025)
    d.low=math.max(0,(lo or 0)-pad);d.high=(hi or 1)+pad
    return d
end
function C.Nearest(points,day)
    local a,b=1,#points
    if b==0 then return nil end
    while a<b do local m=math.floor((a+b)/2);if points[m].day<day then a=m+1 else b=m end end
    if a>1 and day-points[a-1].day<=points[a].day-day then a=a-1 end
    return points[a],a
end
function C.Connected(a,b,gaps)
    if b.day-a.day>1.01 then return false end
    for _,g in ipairs(gaps) do if g.from<=b.day and g.to>=a.day then return false end end
    return true
end
function C.Geometry(d,w,h)
    local geom={};local cols=math.min(C.MAX_COLUMNS,math.max(1,math.floor(w)))
    local function X(day) return Clamp((day-d.from)/(d.to-d.from),0,1)*w end
    local function Y(v) return (v-d.low)/(d.high-d.low)*h end
    -- Dense inputs use per-pixel min/max envelopes, never averages or invented samples.
    if #d.points>cols then
        local bins={}
        for _,p in ipairs(d.points) do
            local i=math.min(cols,math.floor(X(p.day)/w*cols)+1)
            local b=bins[i]
            if b then b.lo=math.min(b.lo,p.price);b.hi=math.max(b.hi,p.price)
            else bins[i]={lo=p.price,hi=p.price} end
        end
        for i=1,cols do local b=bins[i];if b then geom[#geom+1]={x=(i-1)*w/cols,y=Y(b.lo),w=1,h=math.max(2,Y(b.hi)-Y(b.lo)),envelope=true} end end
    else
        for i,p in ipairs(d.points) do
            local a=d.points[i-1]
            if a and C.Connected(a,p,d.gaps) then geom[#geom+1]={x=X(a.day),y=Y(a.price),x2=X(p.day),y2=Y(p.price)} end
            geom[#geom+1]={x=X(p.day)-1.5,y=Y(p.price)-1.5,w=3,h=3}
        end
    end
    -- Aggregates are interval bands with a mean rule, never daily points.
    for _,g in ipairs(d.groups) do
        if g.average then
            local x,x2=X(g.from),X(g.to)
            geom[#geom+1]={x=x,y=Y(g.low or g.average),w=math.max(2,x2-x),h=math.max(3,Y(g.high or g.average)-Y(g.low or g.average)),band=true}
            geom[#geom+1]={x=x,y=Y(g.average),w=math.max(2,x2-x),h=1,band=true}
        end
    end
    return geom
end
function UI.AdvancedMarketChart(parent,w,h)
    local c=CreateFrame('Frame',nil,parent);c:SetSize(w,h);UI.Panel(c,'canvas')
    c.pool={};c.linePool={};c.guides={};c.labels={};activeChart=c
    c.plot=CreateFrame('Frame',nil,c);c.plot:SetPoint('TOPLEFT',100,-12);c.plot:SetPoint('BOTTOMRIGHT',-18,36)
    local function Text(size,color) return UI.Text(c,size,color or UI.K.textDim) end
    c.msg=Text(12);c.msg:SetPoint('CENTER');c.msg:SetWidth(w-120);c.msg:SetJustifyH('CENTER')
    c.note=Text(11);c.note:SetPoint('TOP',c.msg,'BOTTOM',0,-5)
    c.start=Text(10);c.start:SetPoint('TOPLEFT',c.plot,'BOTTOMLEFT',0,-8)
    c.finish=Text(10);c.finish:SetPoint('TOPRIGHT',c.plot,'BOTTOMRIGHT',0,-8)
    c.hint=Text(10);c.hint:SetPoint('BOTTOMLEFT',8,4);c.hint:SetText('Drag to inspect interval · right-click to reset · UTC')
    local function Solid(parent,color,alpha) return UI.L.Solid(parent,'ARTWORK',color,alpha) end
    for i=1,4 do
        c.guides[i]=Solid(c.plot,UI.K.bronzeLo,.24);c.labels[i]=Text(10);c.labels[i]:SetWidth(90);c.labels[i]:SetJustifyH('RIGHT')
    end
    c.cross=Solid(c.plot,UI.K.textDim,.5);c.marker=Solid(c.plot,UI.K.bronzeText,1)
    c.selection=Solid(c.plot,UI.K.bronzeText,.10)
    c.tip=CreateFrame('Frame',nil,c,'BackdropTemplate');UI.Panel(c.tip,'espresso');c.tip:SetSize(300,104);c.tip:SetFrameLevel(c:GetFrameLevel()+5)
    c.tip.text=UI.Text(c.tip,11,UI.K.text);c.tip.text:SetPoint('TOPLEFT',10,-9);c.tip.text:SetPoint('BOTTOMRIGHT',-10,9);c.tip.text:SetJustifyH('LEFT');c.tip.text:SetWordWrap(true)
    function c:ClearHover()
        self.plot:SetScript('OnUpdate',nil);self.cross:Hide();self.marker:Hide();self.tip:Hide();self.selection:Hide();self.hovered=nil;self.drag=nil
    end
    function c:Clear()
        self:ClearHover();self.series=nil;self.data=nil;self.drawData=nil;self.window=nil
        for i=1,4 do self.guides[i]:Hide();self.labels[i]:SetText('') end
        self.start:SetText('');self.finish:SetText('')
        for _,p in ipairs(self.pool) do p:Hide() end
        for _,p in ipairs(self.linePool) do p:Hide() end
    end
    function c:Inspect(day)
        local d=self.data;if not d then return end
        local p=C.Nearest(d.points,day)
        local g
        if not p or math.abs(p.day-day)>(d.to-d.from)*.03 then
            for _,v in ipairs(d.groups) do if day>=v.from and day<=v.to then g=v;break end end
        end
        local record=g or p
        if not record or record==self.hovered then return end
        self.hovered=record
        local x=Clamp(((g and day or p.day)-d.from)/(d.to-d.from),0,1)*self.pw
        self.cross:ClearAllPoints();self.cross:SetPoint('BOTTOMLEFT',self.plot,'BOTTOMLEFT',x,0);self.cross:SetSize(1,self.ph);self.cross:Show()
        self.marker:Hide()
        if not g then self.marker:ClearAllPoints();self.marker:SetPoint('CENTER',self.plot,'BOTTOMLEFT',x,(p.price-d.low)/(d.high-d.low)*self.ph);self.marker:SetSize(5,5);self.marker:Show() end
        local stamp=g and (Day(g.from)..' — '..Day(g.to)..' UTC\nAggregate mean · '..tostring(g.n or '?')..' observed days') or
            (p.at and (type(p.at)=='string' and p.at or date('!%Y-%m-%d %H:%M:%S',p.last or p.at)..' UTC') or Day(p.day)..' UTC · daily closing')
        local value=g and g.average or p.price
        self.tip.text:SetText(stamp..'\n'..self.format(value)..(self.data.metric=='supply' and ' items' or (' · '..string.format('%.0f',value)..' copper'))..'\n'..
            (record.provenance or 'Unknown source')..(record.partial and ' · partial observation' or '')..'\nListing evidence; not completed sales')
        self.tip:ClearAllPoints();self.tip:SetPoint('TOPLEFT',self,'TOPLEFT',Clamp(100+x+(x>self.pw/2 and -310 or 10),4,math.max(4,self:GetWidth()-304)),-12);self.tip:Show()
    end
    function c:CursorDay()
        local x=GetCursorPosition()/self.plot:GetEffectiveScale()
        return self.data.from+Clamp((x-(self.plot:GetLeft() or 0))/self.pw,0,1)*(self.data.to-self.data.from)
    end
    function c:Render()
        if not self.series or not self:IsShown() then return end
        local pw,ph=math.max(20,self.plot:GetWidth()),math.max(20,self.plot:GetHeight())
        if self.drawData==self.data and pw==self.pw and ph==self.ph then return end
        self:ClearHover();self.pw,self.ph=pw,ph;self.drawData=self.data
        local d=self.data;local geometry=C.Geometry(d,pw,ph)
        for _,p in ipairs(self.pool) do p:Hide() end;for _,p in ipairs(self.linePool) do p:Hide() end
        local nt,nl=0,0
        for _,v in ipairs(geometry) do
            if v.x2 then
                -- Rasterize the exact segment into bounded logical-pixel columns.
                -- Adjacent columns with identical coverage share one texture run.
                -- No rotation/line API or UV behavior is assumed across clients.
                local dx=v.x2-v.x
                local step=math.max(1,pw/C.MAX_COLUMNS)
                local first,last=math.floor(v.x/step),math.ceil(v.x2/step)-1
                local runX,runY,runH,runEnd
                local function Flush()
                    if not runX then return end
                    nl=nl+1;local p=self.linePool[nl]
                    if not p then p=Solid(self.plot,UI.K.bronzeText,.9);self.linePool[nl]=p end
                    p:ClearAllPoints();p:SetPoint('BOTTOMLEFT',runX,runY)
                    p:SetSize(math.max(.5,runEnd-runX),runH);p:Show()
                end
                for col=first,last do
                    local x0,x1=math.max(v.x,col*step),math.min(v.x2,(col+1)*step)
                    local y0=math.floor(v.y+(x0-v.x)/math.max(.001,dx)*(v.y2-v.y)+.5)
                    local y1=math.floor(v.y+(x1-v.x)/math.max(.001,dx)*(v.y2-v.y)+.5)
                    local y=math.min(y0,y1)-.625;local height=math.abs(y1-y0)+1.25
                    if runX and (y~=runY or height~=runH) then Flush();runX=nil end
                    if not runX then runX,runY,runH=x0,y,height end
                    runEnd=x1
                end
                Flush()
            elseif not v.x2 then
                nt=nt+1;local p=self.pool[nt];if not p then p=Solid(self.plot,UI.K.bronzeText,1);self.pool[nt]=p end
                p:ClearAllPoints();p:SetPoint('BOTTOMLEFT',v.x,v.y);p:SetSize(v.w,v.h);p:SetAlpha(v.band and .23 or .85);p:Show()
            end
        end
        for i=1,4 do local y=(i-1)*ph/3
            local g,l=self.guides[i],self.labels[i];g:ClearAllPoints();g:SetPoint('BOTTOMLEFT',0,y);g:SetSize(pw,1);g:Show()
            l:ClearAllPoints();l:SetPoint('RIGHT',self.plot,'BOTTOMLEFT',-10,y);l:SetText(self.format(d.low+(d.high-d.low)*(i-1)/3))
        end
        self.start:SetText(Day(d.from));self.finish:SetText(Day(d.to))
        self.hint:SetText(#d.groups>0 and 'Shaded intervals: aggregates · drag to select · right-click to reset' or #d.points>math.min(C.MAX_COLUMNS,pw) and 'Pixel min/max ranges · exact hover · drag to select · right-click to reset' or 'Drag to inspect interval · right-click to reset · UTC')
        if #d.points==0 and #d.groups==0 then
            for i=1,4 do self.guides[i]:Hide();self.labels[i]:SetText('') end
        end
        self.msg:SetText(#d.points==0 and #d.groups==0 and 'No supported observations in this interval.' or '')
        self.note:SetText('');self.state=#d.points==1 and 'single' or #d.points==0 and 'empty' or 'series';self.shown=#d.points
    end
    function c:Set(series,format)
        self:ClearHover();self.series=series;self.format=format or UI.Money;self.window=nil
        local pt=R.Perf.on and R.Perf.Start('auction.chartPrepare')
        self.data=C.Prepare(series);self.data.metric=series and series.metric
        if pt then R.Perf.Stop(pt) end
        if not series then self:Clear();self.msg:SetText('No supported history for this selection.');self.note:SetText('');return end
        R.Perf.Call('auction.chartDraw',self.Render,self)
    end
    function c:Select(from,to)
        if not self.series then return end
        if from and to and math.abs(to-from)>(self.data.to-self.data.from)*.01 then self.window={math.min(from,to),math.max(from,to)} else self.window=nil end
        self.data=C.Prepare(self.series,self.window and self.window[1],self.window and self.window[2]);self.data.metric=self.series.metric
        self:Render()
    end
    c.plot:EnableMouse(true)
    c.plot:SetScript('OnEnter',function(p)
        if not c.data then return end
        p:SetScript('OnUpdate',function()
            if not c.data then return end
            local day=c:CursorDay();c:Inspect(day)
            if c.drag then
                local x=(math.min(day,c.drag)-c.data.from)/(c.data.to-c.data.from)*c.pw
                c.selection:ClearAllPoints();c.selection:SetPoint('BOTTOMLEFT',x,0)
                c.selection:SetSize(math.max(1,math.abs(day-c.drag)/(c.data.to-c.data.from)*c.pw),c.ph);c.selection:Show()
            end
        end)
    end)
    c.plot:SetScript('OnLeave',function() c:ClearHover() end)
    c.plot:SetScript('OnMouseDown',function(_,button) if c.data and button=='LeftButton' then c.drag=c:CursorDay() end end)
    c.plot:SetScript('OnMouseUp',function(_,button) local from=c.drag;c.drag=nil;if button=='RightButton' then c:Select() elseif from then c:Select(from,c:CursorDay()) end end)
    c:SetScript('OnSizeChanged',function() R.Perf.Call('auction.chartDraw',c.Render,c) end)
    c:SetScript('OnHide',function() c:Clear() end)
    c:ClearHover()
    return c
end
