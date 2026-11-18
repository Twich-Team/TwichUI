-- Shared auction chart presentation. Typed evidence in, pooled geometry out; no saved data.
local R,W=TwichUI,TwichUI.Workshop
local UI=W.UI
local C={MAX_COLUMNS=1024}
local charts=setmetatable({}, {__mode="k"})
if R.Perf.Gauge then
    R.Perf.Gauge('auction.chartPool',{label='Market chart pooled regions',unit='count',kind='pool',group='auction',read=function() local n=0;for chart in pairs(charts) do n=n+#chart.pool+#chart.linePool+#chart.nativePool end;return n end})
    R.Perf.Gauge('auction.chartRecords',{label='Market chart visible evidence',unit='count',kind='cache',group='auction',read=function() local n=0;for chart in pairs(charts) do if chart.data then n=n+#chart.data.points+#chart.data.groups end end;return n end})
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
-- Compact axis units prevent large copper amounts from colliding with the plot.
-- Inspection always retains exact copper and the caller's full formatter.
function C.Axis(value,metric,format)
    if metric~='supply' then
        if value>=1e10 then return ('%.1fM gold'):format(value/1e10) end
        if value>=1e8 then return ('%.1fk gold'):format(value/1e7) end
    end
    return format(value)
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
-- Projection services return fresh immutable records. Compare their values, not
-- table identity: metadata refreshes must not end an interaction or reset a zoom.
function C.Same(a,b)
    if not a or not b then return a==b end
    for k,v in pairs(a) do if type(v)~='table' and b[k]~=v then return false end end
    for k,v in pairs(b) do if type(v)~='table' and a[k]~=v then return false end end
    for _,key in ipairs({'points','groups','gaps'}) do
        local x,y=a[key] or {},b[key] or {}
        if #x~=#y then return false end
        for i=1,#x do
            for k,v in pairs(x[i]) do if y[i][k]~=v then return false end end
            for k,v in pairs(y[i]) do if x[i][k]~=v then return false end end
        end
    end
    return true
end
-- Never select an exact sample through an explicit gap or disconnected period.
function C.At(d,day,tolerance)
    for _,g in ipairs(d.groups) do if day>=g.from and day<=g.to then return nil,g end end
    for _,g in ipairs(d.gaps) do if day>=g.from and day<g.to+1 then return nil,nil,g.why or 'No observation recorded' end end
    local p,i=C.Nearest(d.points,day)
    if not p then return nil,nil,'No supported observation' end
    if math.abs(p.day-day)<=tolerance then return p end
    local a,b=d.points[i-1],d.points[i+1]
    if (a and day>=a.day and day<=p.day and C.Connected(a,p,d.gaps)) or
       (b and day>=p.day and day<=b.day and C.Connected(p,b,d.gaps)) then return p end
    return nil,nil,'No observation at this date'
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
            if a and C.Connected(a,p,d.gaps) then geom[#geom+1]={x=X(a.day),y=Y(a.price),x2=X(p.day),y2=Y(p.price),a=i-1,b=i} end
            geom[#geom+1]={x=X(p.day)-1.5,y=Y(p.price)-1.5,w=3,h=3,index=i}
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
    c.pool={};c.linePool={};c.nativePool={};c.anchors={};c.guides={};c.labels={};charts[c]=true
    c.plot=CreateFrame('Frame',nil,c);c.plot:SetPoint('TOPLEFT',100,-12);c.plot:SetPoint('BOTTOMRIGHT',-18,36)
    c.hit=CreateFrame('Button',nil,c.plot);c.hit:SetAllPoints(c.plot)
    c.hit:SetFrameLevel(c:GetFrameLevel()+12);c.hit:EnableMouse(true)
    c.hit:RegisterForClicks('LeftButtonUp','RightButtonUp')
    local function Text(size,color) return UI.Text(c,size,color or UI.K.textDim) end
    c.msg=Text(12);c.msg:SetPoint('CENTER');c.msg:SetWidth(w-120);c.msg:SetJustifyH('CENTER')
    c.note=Text(11);c.note:SetPoint('TOP',c.msg,'BOTTOM',0,-5)
    c.start=Text(10);c.start:SetPoint('TOPLEFT',c.plot,'BOTTOMLEFT',0,-8)
    c.finish=Text(10);c.finish:SetPoint('TOPRIGHT',c.plot,'BOTTOMRIGHT',0,-8)
    c.hint=Text(10);c.hint:SetPoint('BOTTOMLEFT',8,4);c.hint:SetText('Drag to zoom · Right-click to reset')
    local function Solid(parent,color,alpha) return UI.L.Solid(parent,'ARTWORK',color,alpha) end
    for i=1,4 do
        c.guides[i]=Solid(c.plot,UI.K.bronzeLo,.24);c.labels[i]=Text(10);c.labels[i]:SetWidth(90);c.labels[i]:SetJustifyH('RIGHT')
    end
    c.cross=Solid(c.plot,UI.K.textDim,.5);c.marker=Solid(c.plot,UI.K.bronzeText,1)
    c.selection=Solid(c.plot,UI.K.bronzeText,.10)
    c.halo=Solid(c.plot,UI.K.bronzeLo,.28);c.halo:SetSize(10,10)
    c.tip=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');UI.Panel(c.tip,'espresso');c.tip:SetSize(316,112);c.tip:SetFrameStrata('TOOLTIP');c.tip:SetClampedToScreen(true);c.tip:EnableMouse(false);c.tip:Hide()
    c.tip.date=UI.Text(c.tip,10,UI.K.bronzeText);c.tip.date:SetPoint('TOPLEFT',10,-8);c.tip.date:SetWidth(296);c.tip.date:SetHeight(24);c.tip.date:SetJustifyH('LEFT')
    c.tip.value=UI.Text(c.tip,13,UI.K.text);c.tip.value:SetPoint('TOPLEFT',10,-32);c.tip.value:SetWidth(296);c.tip.value:SetHeight(28);c.tip.value:SetJustifyH('LEFT');c.tip.value:SetWordWrap(true)
    c.tip.text=UI.Text(c.tip,10,UI.K.textDim);c.tip.text:SetPoint('TOPLEFT',10,-64);c.tip.text:SetWidth(296);c.tip.text:SetHeight(36);c.tip.text:SetJustifyH('LEFT');c.tip.text:SetWordWrap(true)
    for _,marker in ipairs({c.marker,c.halo}) do
        marker:SetTexture('Interface\\AddOns\\TwichUI_Workshop\\media\\chart-marker')
        marker:SetVertexColor(UI.K.bronzeText[1],UI.K.bronzeText[2],UI.K.bronzeText[3],marker==c.halo and .18 or 1)
    end
    function c:HideInspection()
        self.cross:Hide();self.marker:Hide();self.halo:Hide();self.tip:Hide();self.hovered=nil;self.gapText=nil;self.gapDay=nil
    end
    function c:ClearHover()
        self.hit:SetScript('OnUpdate',nil);self.hit:UnregisterEvent('GLOBAL_MOUSE_UP')
        self:HideInspection();self.selection:Hide();self.drag=nil;self.inside=false
    end
    function c:Clear()
        self:ClearHover();self.series=nil;self.data=nil;self.drawData=nil;self.window=nil;self.context=nil;self.anchors={}
        for i=1,4 do self.guides[i]:Hide();self.labels[i]:SetText('') end
        self.start:SetText('');self.finish:SetText('')
        for _,p in ipairs(self.pool) do p:Hide() end
        for _,p in ipairs(self.linePool) do p:Hide() end
        for _,p in ipairs(self.nativePool) do p:Hide() end
    end
    function c:Inspect(day)
        local d=self.data;if not d then return end
        local x=Clamp((day-d.from)/(d.to-d.from),0,1)*self.pw
        self.cross:ClearAllPoints();self.cross:SetPoint('BOTTOMLEFT',self.plot,'BOTTOMLEFT',x,0);self.cross:SetSize(1,self.ph);self.cross:Show()
        local p,g,why=C.At(d,day,(d.to-d.from)*6/self.pw)
        local record=g or p
        if record==self.hovered and why==self.gapText and self.tip:IsShown() and (record or self.gapDay==math.floor(day)) then return end
        self.hovered,self.gapText,self.gapDay=record,why,math.floor(day)
        self.marker:Hide();self.halo:Hide()
        local anchorX=x
        if p then
            anchorX=Clamp((p.day-d.from)/(d.to-d.from),0,1)*self.pw
            local y=(p.price-d.low)/(d.high-d.low)*self.ph
            self.marker:ClearAllPoints();self.marker:SetPoint('CENTER',self.plot,'BOTTOMLEFT',anchorX,y);self.marker:Show()
            self.halo:ClearAllPoints();self.halo:SetPoint('CENTER',self.plot,'BOTTOMLEFT',anchorX,y);self.halo:Show()
            self.marker:SetSize(5,5)
        end
        local stamp=g and (Day(g.from)..' — '..Day(g.to)..' UTC\nAggregate mean · '..tostring(g.n or '?')..' observed days') or
            (p and (p.at and (type(p.at)=='string' and p.at or date('!%Y-%m-%d %H:%M:%S',p.last or p.at)..' UTC') or Day(p.day)..' UTC · daily closing') or Day(day)..' UTC')
        self.tip.date:SetText(stamp)
        local value=g and g.average or p and p.price
        self.tip.value:SetText(value and (self.format(value)..(d.metric=='supply' and ' items' or (' · '..string.format('%.0f',value)..' copper'))) or 'No supported value at this date')
        self.tip.text:SetText(record and ((record.provenance or 'Unknown source')..(record.partial and ' · partial observation' or '')..'\nListing evidence; not completed sales') or ((why=='observed_absent' and 'Observed absent; no supported value.\nNo sale or demand is inferred.') or (why=='no_supported_buyout' and 'Listings lacked a supported buyout.\nNo price is substituted.') or (why=='unknown_variant_state' and 'Variant observation state is unknown.\nNo absence or price is inferred.') or 'No supported observation; coverage is missing or incomplete.\nNo absence or price is inferred.'))
        -- Dock outside the entire chart, never under the pointer or plot.
        -- UIParent ownership also keeps inspection clear of scroll clipping.
        local scale=self:GetEffectiveScale()
        local screenScale=UIParent:GetEffectiveScale()
        self.tip:SetScale(scale/screenScale)
        local right=(UIParent:GetRight() or UIParent:GetWidth())*screenScale/scale
        local top=(UIParent:GetTop() or UIParent:GetHeight())*screenScale/scale
        self.tip:ClearAllPoints()
        if right-(self:GetRight() or right)>=332 then
            self.tip:SetPoint('TOPLEFT',self,'TOPRIGHT',12,0)
        elseif (self:GetLeft() or 0)>=332 then
            self.tip:SetPoint('TOPRIGHT',self,'TOPLEFT',-12,0)
        elseif top-(self:GetTop() or top)>=128 then
            self.tip:SetPoint('BOTTOM',self,'TOP',0,12)
        else self.tip:SetPoint('TOP',self,'BOTTOM',0,-12) end
        self.tip:Show()
    end
    function c:CursorDay()
        local x=GetCursorPosition()/self.plot:GetEffectiveScale()
        return self.data.from+Clamp((x-(self.plot:GetLeft() or 0))/self.pw,0,1)*(self.data.to-self.data.from)
    end
    function c:Render()
        if not self.series or not self:IsShown() then return end
        local pw,ph=math.max(20,self.plot:GetWidth()),math.max(20,self.plot:GetHeight())
        if self.drawData==self.data and pw==self.pw and ph==self.ph then return end
        local replaced=self.drawData~=self.data
        self:HideInspection();self.pw,self.ph=pw,ph;self.drawData=self.data
        local d=self.data;local geometry=C.Geometry(d,pw,ph)
        for _,p in ipairs(self.pool) do p:Hide() end;for _,p in ipairs(self.linePool) do p:Hide() end
        for _,p in ipairs(self.nativePool) do p:Hide() end
        self.anchors={}
        local native=self.strokeMode~='raster' and type(self.plot.CreateLine)=='function'
        local nt,nl=0,0
        for _,v in ipairs(geometry) do
            if v.x2 and not native then
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
                if v.index then
                    p:SetTexture('Interface\\AddOns\\TwichUI_Workshop\\media\\chart-marker')
                    p:SetVertexColor(UI.K.bronzeText[1],UI.K.bronzeText[2],UI.K.bronzeText[3],1)
                    self.anchors[v.index]=p
                else p:SetColorTexture(UI.K.bronzeText[1],UI.K.bronzeText[2],UI.K.bronzeText[3],1);p:SetVertexColor(1,1,1,1) end
            end
        end
        self.backend='raster'
        if native then
            local function Native()
                local count=0
                for _,v in ipairs(geometry) do if v.x2 then
                    for layer=1,2 do
                        count=count+1;local line=self.nativePool[count]
                        if not line then
                            line=self.plot:CreateLine(nil,'ARTWORK',nil,layer-1)
                            assert(line and line.SetStartPoint and line.SetEndPoint and line.SetThickness,'line API unavailable')
                            self.nativePool[count]=line
                        end
                        local color=layer==1 and UI.K.bronzeLo or UI.K.bronzeText
                        line:SetColorTexture(color[1],color[2],color[3],layer==1 and .28 or .95)
                        line:SetThickness(layer==1 and 2.75 or 1.25)
                        -- Region anchors remove offset/effective-scale ambiguity. No point frames.
                        line:SetStartPoint('CENTER',self.anchors[v.a],0,0)
                        line:SetEndPoint('CENTER',self.anchors[v.b],0,0);line:Show()
                    end
                end end
            end
            local ok=pcall(Native)
            if ok then self.backend='native' else
                for _,line in ipairs(self.nativePool) do line:Hide() end
                self.strokeMode='raster';self.drawData=nil;return self:Render()
            end
        end
        for i=1,4 do local y=(i-1)*ph/3
            local g,l=self.guides[i],self.labels[i];g:ClearAllPoints();g:SetPoint('BOTTOMLEFT',0,y);g:SetSize(pw,1);g:Show()
            l:ClearAllPoints();l:SetPoint('RIGHT',self.plot,'BOTTOMLEFT',-10,y);l:SetText(C.Axis(d.low+(d.high-d.low)*(i-1)/3,d.metric,self.format))
        end
        self.start:SetText(Day(d.from));self.finish:SetText(Day(d.to))
        self.hint:SetText(#d.groups>0 and 'Aggregate intervals · Drag to zoom · Right-click to reset' or #d.points>math.min(C.MAX_COLUMNS,pw) and 'Pixel min/max ranges · Drag to zoom · Right-click to reset' or 'Drag to zoom · Right-click to reset')
        if #d.points==0 and #d.groups==0 then
            for i=1,4 do self.guides[i]:Hide();self.labels[i]:SetText('') end
        end
        self.msg:SetText(#d.points==0 and #d.groups==0 and 'No supported observations in this interval.' or '')
        if replaced then self.note:SetText('') end;self.state=#d.points==1 and 'single' or #d.points==0 and 'empty' or 'series';self.shown=#d.points
    end
    function c:Set(series,format,context)
        if self.data and self.context==context and C.Same(self.series,series) then
            self.series=series;self.format=format or UI.Money;self:Render();return
        end
        if not (self.data and self.context==context) then self:ClearHover();self.window=nil end
        self.context=context;self.series=series;self.format=format or UI.Money
        local pt=R.Perf.on and R.Perf.Start('auction.chartPrepare')
        self.data=C.Prepare(series,self.window and self.window[1],self.window and self.window[2]);self.data.metric=series and series.metric
        if pt then R.Perf.Stop(pt) end
        if not series then self:Clear();self.msg:SetText('No supported history for this selection.');self.note:SetText('');return end
        R.Perf.Call('auction.chartDraw',self.Render,self)
        self:Resume()
    end
    function c:Select(from,to)
        if not self.series then return end
        if from and to and from~=to then self.window={math.min(from,to),math.max(from,to)} else self.window=nil end
        self.data=C.Prepare(self.series,self.window and self.window[1],self.window and self.window[2]);self.data.metric=self.series.metric
        self:Render()
    end
    function c:SetStrokeMode(mode)
        self.strokeMode=mode;self.drawData=nil;self:Render()
    end
    function c:FinishDrag()
        local from=self.drag
        if not from then return end
        local to=self:CursorDay();self.drag=nil;self.selection:Hide();self.hit:UnregisterEvent('GLOBAL_MOUSE_UP')
        -- A six-logical-pixel threshold, independent of the selected time span.
        if math.abs(to-from)/(self.data.to-self.data.from)*self.pw>=6 then self:Select(from,to) end
        if not self.inside then self:ClearHover() end
    end
    local function Update()
        if not c.data then return end
        local day=c:CursorDay()
        if c.inside and not c.drag then c:Inspect(day) end
        if c.drag then
            local x=(math.min(day,c.drag)-c.data.from)/(c.data.to-c.data.from)*c.pw
            c.selection:ClearAllPoints();c.selection:SetPoint('BOTTOMLEFT',c.plot,'BOTTOMLEFT',x,0)
            c.selection:SetSize(math.max(1,math.abs(day-c.drag)/(c.data.to-c.data.from)*c.pw),c.ph);c.selection:Show()
            if IsMouseButtonDown and not IsMouseButtonDown('LeftButton') then c:FinishDrag() end
        end
    end
    function c:Resume()
        if self.data and self:IsShown() and self.hit:IsMouseOver()==true then
            self.inside=true;self.hit:SetScript('OnUpdate',Update);Update()
        elseif self.inside and self.data then Update() end
    end
    c.hit:SetScript('OnEnter',function()
        if not c.data then return end
        c.inside=true;c.hit:SetScript('OnUpdate',Update);Update()
    end)
    c.hit:SetScript('OnLeave',function()
        c.inside=false;c:HideInspection()
        if not c.drag then c.hit:SetScript('OnUpdate',nil) end
    end)
    c.hit:SetScript('OnMouseDown',function(_,button)
        if c.data and button=='LeftButton' then
            c:HideInspection();c.drag=c:CursorDay();c.hit:RegisterEvent('GLOBAL_MOUSE_UP');c.hit:SetScript('OnUpdate',Update)
        end
    end)
    c.hit:SetScript('OnMouseUp',function(_,button)
        if button=='RightButton' then c:ClearHover();c:Select();c:Resume()
        elseif button=='LeftButton' then c:FinishDrag() end
    end)
    c.hit:SetScript('OnEvent',function(_,event,button) if event=='GLOBAL_MOUSE_UP' and button=='LeftButton' then c:FinishDrag() end end)
    c:SetScript('OnSizeChanged',function() R.Perf.Call('auction.chartDraw',c.Render,c) end)
    c:SetScript('OnHide',function() c:Clear() end)
    c:ClearHover()
    return c
end
