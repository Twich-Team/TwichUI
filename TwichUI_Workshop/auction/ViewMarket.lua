-- AH-6: stored-market research. All reads use Workshop presentation services.
-- This page has no auction transport, scanner, transaction or import dependency.
local R,W=TwichUI,TwichUI.Workshop
local A,UI,D,AD=W.AuctionUI,W.UI,W.AuctionMarketData,W.AdvisorData
local V={}
A.Market=V
local page,Start,Detail,Paint
local function External(p) return p and (p.marketKey=='server' or p.marketKey=='auto' and W.Bridge and W.Bridge.Status().ready) end
local function Key(r) return r.item end
local function Money(n) return n and UI.Money(n) or "Unavailable" end
local function Date(day) return date("!%b %d",math.floor(day*86400)) end
local function Stamp(p,m)
    if m and m.external then local b=W.Bridge.Status();return m.key..":"..b.state..":"..tostring(b.loading)..":"..p.scope..":"..p.bags..(p.scope=="tracked" and ":"..D.TrackStamp() or "") end
    return (m and m.key..":"..W.Valuation.Generation(m) or "none")..":"..p.scope..":"..p.bags..
        (p.scope=="tracked" and ":"..D.TrackStamp() or "")
end
local function Options(p)
    return {external=External(p),market=p.market,scope=p.scope,query=p.query,category=p.category,quality=p.quality,item=p.focusItem}
end
local function Context(p,item)
    return p.context and p.context.item==item and p.context or {}
end
local function Wrap(t,height) t:SetWordWrap(true);t:SetHeight(height);t:SetJustifyV("TOP") end
local function Quality(f)
    if f.nomarket then return "No saved market" end
    if f.variant then return "Variant not priced" end
    if f.freshness=="old" or f.freshness=="stale" then return "Outdated data" end
    local q=f.quality
    return q and (q.level=="good" and "Good coverage" or q.level=="fair" and "Fair coverage" or
        q.level=="limited" and "Limited observations" or "Insufficient history") or "Unavailable"
end
local function SourceWords(source)
    return source=='local' and 'Your Auction House scans' or source=='local+legacy' and 'Your scans + imported local history' or source=='legacy' and 'Imported local history' or source
end
local function ChartWords(p,x)
    local s=x and x.series
    if not s then return "History unavailable · "..(W.Facts.WHY[x and x.why] or "no stored observations"),"" end
    local parts={}
    for _,g in ipairs(s.groups) do
        parts[#parts+1]=Date(g.from).."–"..Date(g.to)..": "..Money(g.average).." mean · "..g.n.." observed days"..
            (g.partial and " · partial" or "").." · "..(SourceWords(g.provenance) or "unknown source")
    end
    local coverage=(s.recent and (#s.points.." recorded observations") or (#s.points.." observed daily closings"))..
        " · "..#s.gaps.." stored gap ranges · "..#s.groups.." aggregate ranges"
    local sources,partial={},false
    for _,list in ipairs({s.points,s.groups}) do for _,r in ipairs(list) do
        if r.provenance then sources[r.provenance]=true end
        partial=partial or r.partial
    end end
    local names={};for name in pairs(sources) do names[#names+1]=SourceWords(name) end;table.sort(names)
    if #names>0 then coverage=coverage.." · "..table.concat(names," + ") end
    if partial then coverage=coverage.." · partial records" end
    if s.damaged then coverage=coverage.." · some history unreadable" end
    return coverage,table.concat(parts,"\n")
end
local function ServerChart(p,x)
    local h=x.header
    local formatter=p.serverMetric=="supply" and function(n)return ("%.0f"):format(n) end or UI.Money
    p.chart:Set(x.series,formatter,tostring(p.selected)..':'..p.marketKey..':'..p.serverVariant..':'..p.serverMetric..':'..p.days..':'..tostring(h and h.generation_id))
    if x.series and #x.series.points==1 then
        local point=x.series.points[1]
        local label=p.serverMetric=="supply" and "Observed supply: " or p.serverMetric=="minimum" and "Observed minimum listing: " or
            (h and h.pricing_algorithm=="asking-v1-provisional" and "Observed asking mean: " or "Observed Recent Price: ")
        p.chart.note:SetText(label..formatter(point.price).." · "..Date(point.day).." UTC")
    end
end
local function SummaryDetail(p,r)
    local B=W.Bridge
    -- Research selection only: this never resolves a native bag/equipment link.
    if r and p.serverVariant=='' then
        local variants,cut=B.Variants(r.item,2)
        if variants and #variants==1 and not cut then p.serverVariant=variants[1];p.variantDrop:Refresh() end
    end
    local x=W.ServerMarket.Project(r and r.item,p.serverVariant,p.serverMetric,p.days);p.projection=x
    local h,status=x.header,B.Status()
    local why=W.ServerMarket.AvailabilityText(x.availability.state)
    p.kind:SetText('External listing summary · exact server variants · native item equivalence unavailable')
    p.source:SetText(B.Freshness().text..' · '..x.label..(h and h.synthetic and ' · synthetic fixture' or ''))
    local rows={};for _,v in ipairs(W.ServerMarket.Rows(x,UI.Money)) do rows[v.id]=v end
    for _,tile in ipairs(p.tiles) do
        if tile.localHeading==nil then tile.localHeading=tile.heading:GetText() end
        local v=rows[tile.id];tile.value:SetText(v and v.value or 'Unavailable');tile.tip=v and v.tip or why
        tile.heading:SetText(v and v.label or tile.localHeading)
    end
    ServerChart(p,x)
    local hasHistory=h and h.contract_version==2
    p.chartCard.heading:SetText(hasHistory and 'Market history · actual daily observations' or 'History unavailable in this summary format')
    if not hasHistory then
        p.chart.msg:SetText('This update contains price references, not a daily price series.')
        p.chart.note:SetText('Update Companion and TwichUI for Market history, or choose your local scans.')
    elseif not x.series or #x.series.points==0 then
        p.chart.msg:SetText('No supported Market observations for this exact variant and period.')
        p.chart.note:SetText('Missing observations stay gaps. Your local scans are available in the source selector.')
    end
    p.coverage:SetText(h and (h.record_count..' current observed exact variants; historical-only items are excluded.') or why)
    p.axis:SetText('No synthetic daily observations or interpolated trends')
    if status.error then p.kind:SetText(status.ready and 'Replacement rejected; previous validated data retained.' or 'Summary rejected; local history is unchanged.') end
    if status.compatibility_message then p.source:SetText(status.compatibility_message) end
    if status.reload_required then p.source:SetText('Market files changed or could not be verified. Reload UI to read a complete generation.') end
    local current=x.record and x.record.current
    p.trends:SetText(why..(current and ('\n'..current.coverage.priced_days_14..' priced reference dates in 14 days; '..current.coverage.priced_days_60..' in 60 days.') or '')..'\nNo local competition or selling authorization.')
    p.contextText:SetText(h and ('Observed: '..h.source_observation.observed_at..' UTC\n'..h.market.faction..' · '..h.market.player_ruleset..' · house '..h.market.house_id..
        '\nMarket server · '..h.pricing_algorithm..'\nPartitions validate on demand: '..status.checked_parts..'/'..status.parts) or why)
    p.aggregateText=h and ('Generation: '..h.generation_id..'\nIssuer: '..h.issuer_id..'\n'..(x.record and ('Exact upstream variant: '..x.record.variant_key..'\n') or '')..
        'Summary contract 1 · current observed exact variants only\nDetailed history not delivered; missing records are unavailable, never zero.') or why
    p.chartTip='Historical reference support is genuine server evidence; summary references are not chart observations.'
    if status.loading and not p.summaryWaiting then
        p.summaryWaiting=true
        C_Timer.After(0.05,function()
            p.summaryWaiting=nil
            if A.IsShown() and A.Mode()=='market' and External(p) then Detail(p) end
        end)
    end
end
local function ServerDetail(p,r)
    p.track:SetEnabled(false);p.browse:SetEnabled(false);p.advisor:SetEnabled(false)
    p.variantDrop:Show();p.qualityDrop:Hide();p.metricDrop:Show();p.variantDrop:Refresh()
    p.name:SetText(r and r.info.name or "Choose a server item")
    p.pic.tex:SetTexture(r and r.info.icon or UI.ICON_BLANK)
    if W.Bridge.Status().summary then SummaryDetail(p,r);return end
    p.kind:SetText("External observations · choose an exact upstream variant · local prices stay separate")
    local x=W.ServerMarket.Project(r and r.item,p.serverVariant,p.serverMetric,p.days);p.projection=x
    local h=x.header;local selected=x.record
    local status=W.Bridge.Status()
    local availability=W.ServerMarket.AvailabilityText(x.availability and x.availability.state or x.why)
    if x.historyWhy=='outside_scope' then availability='Requested history dates are outside this update.' end
    p.source:SetText(W.Bridge.Freshness().text..' · '..x.label.."\n"..(h and (h.pricing_algorithm.." · "..h.history_basis..(h.synthetic and " · synthetic" or "")) or
        (status.loading and "Validating external generation…" or "Bridge unavailable; local scan data is unchanged.")))
    local rows={};for _,v in ipairs(W.ServerMarket.Rows(x,UI.Money)) do rows[v.id]=v end
    for _,tile in ipairs(p.tiles) do
        local v=rows[tile.id];tile.value:SetText(v and v.value or "Unavailable");tile.tip=v and v.tip or availability
        if tile.localHeading==nil then tile.localHeading=tile.heading:GetText() end
        tile.heading:SetText(v and v.label or tile.localHeading)
    end
    ServerChart(p,x)
    p.chartCard.heading:SetText(p.serverMetric=="supply" and "Server observed supply · daily" or p.serverMetric=="minimum" and "Server minimum listings · daily" or
        (h and h.pricing_algorithm=="asking-v1-provisional" and "Server asking mean · daily" or "Server Recent Price · daily"))
    if not x.series then p.chart.msg:SetText(status.loading and "Validating external data…" or not status.ready and "No validated bridge available." or availability);p.chart.note:SetText("Local scan history remains available from the source selector.") end
    local series=x.series
    if series and #series.points==0 then p.chart.msg:SetText(availability) end
    p.coverage:SetText(series and (#series.points.." priced/supply markers · "..series.observed_days.." observed dates · "..#series.gaps.." unavailable dates in this window") or availability)
    p.axis:SetText(series and (Date(series.from).." — "..Date(series.to).." UTC · missing days are not filled") or "Exact server observations only")
    local obs=selected and h.observations[selected.current.observation_ref+1]
    local scope=x.scope
    local scopeText=scope and scope.type=='explicit_variants' and ('Scope complete · '..scope.requested_count..' exact variants · not whole-market complete') or 'Legacy full-market generation'
    if not h then scopeText='No validated external generation' end
    local _,observedSeconds=W.BridgeValidate.Time(obs and obs.observed_at)
    local age=observedSeconds and time and time()-observedSeconds
    local ageText=age and (age>=0 and (' · '..math.floor(age/3600)..'h old') or ' · source time ahead of client') or ''
    if status.compatibility_message then
        p.kind:SetText(status.ready and 'Replacement rejected; previous compatible data retained.' or 'External data rejected; local history is unchanged.')
        p.source:SetText(status.compatibility_message)
    elseif status.error then p.kind:SetText(status.ready and 'Replacement rejected; previous validated generation retained.' or 'External generation rejected; local history is unchanged.')
    elseif status.loading then p.kind:SetText('Validating external generation; previous data remains usable.') end
    p.trends:SetText(selected and (availability.."\n"..selected.current.coverage.priced_days_14.." priced dates in the 14-day reference\n"..
        selected.current.coverage.priced_days_60.." priced dates in the 60-day reference\nNo local competition or selling authorization.") or (availability.."\nNo item-ID aggregate is substituted.\n"..(x.availability.state=="outside_scope" and "Can be selected for a future desktop update." or "")))
    local window=h and (h.coverage.history_from_day..' — '..h.coverage.history_through_day..' UTC') or 'External history unavailable'
    local requested=type(x.variant)=='string' and #x.variant==64 and not x.variant:find('[^0-9a-f]') and x.variant
    local provenance=W.Bridge.CompatibilityText()
    p.contextText:SetText((selected and ('Variant: '..selected.variant_key:sub(1,16)..' · generation: '..h.generation_id:sub(1,12)..'\nObserved: '..obs.observed_at..ageText..
        '\nUpstream: '..(obs.upstream_updated_at~=W.BridgeCodec.NULL and obs.upstream_updated_at or 'unknown')) or requested and ('Requested variant: '..requested:sub(1,16)..'\nNot delivered; provenance unavailable.') or 'Choose a variant to inspect its provenance.')..'\n'..scopeText..'\n'..window..(provenance and ('\n'..provenance) or ''))
    p.aggregateText=(selected and ('Variant SHA256: '..selected.variant_key..'\nGeneration: '..h.generation_id..'\n') or requested and ('Requested variant SHA256: '..requested..'\n') or '')..
        (scope and scope.selection_id and ('Selection: '..scope.selection_id..'\nRequest: '..scope.request_digest..'\nWatermark: '..scope.watermark_observation_id..'\n') or '')..scopeText..'\n'..window..
        (provenance and ('\n'..W.Bridge.CompatibilityText(true)) or '')
    p.chartTip=(h and h.history_basis or 'External history unavailable')..'\nExact available daily observations; no interpolation, sale proceeds or mature-window claim. The current UTC day remains provisional.'
end
Detail=function(p)
    local r=p.index and p.index[p.selected]
    p.chosen=r
    if External(p) and W.ServerMarket then ServerDetail(p,r);return end
    if p.variantDrop then p.variantDrop:Hide();p.qualityDrop:Show();p.metricDrop:Hide() end
    for _,tile in ipairs(p.tiles or {}) do if tile.localHeading then tile.heading:SetText(tile.localHeading) end end
    local ctx=Context(p,p.selected)
    p.track:SetEnabled(r~=nil)
    p.browse:SetEnabled(r~=nil and not ctx.variant)
    p.advisor:SetEnabled(r~=nil and not ctx.variant and UI.Advisor~=nil)
    p.track.text:SetText(r and AD.Tracked()[r.item] and "Untrack" or "Track Item")
    p.name:SetText(r and r.info.name or "Choose a market item")
    p.pic.tex:SetTexture(r and r.info.icon or UI.ICON_BLANK)
    p.kind:SetText(r and ((r.info.category or "Metadata unavailable")..(r.info.sub and " · "..r.info.sub or "")..
        (ctx.variant and " · variant identity preserved; base price excluded" or "")) or "Search known items or select a tracked item.")
    p.projection=r and D.Project(r.item,p.market,p.days,{variant=ctx.variant}) or nil
    local x=p.projection
    local f=x and x.facts or {nomarket=true}
    local lastDay
    for _,record in ipairs(x and x.history and x.history.points or {}) do
        local day=record.kind=="obs" and (record.last or record.at)/86400 or record.to
        if day and (not lastDay or day>lastDay) then lastDay=day end
    end
    local freshness=r and (W.Facts.Freshness(f) or (lastDay and "Newest retained record ends "..Date(lastDay).." UTC" or "No listing observation")) or
        (p.market and "Choose an item to inspect stored observations" or "No selected saved market")
    p.source:SetText((p.market and W.Prices.Label(p.market) or "No selected saved market").." · "..
        freshness.." · saved observations")
    local values={}
    for _,row in ipairs(W.Facts.Rows(f,UI.Money)) do values[row.id]=row end
    for _,tile in ipairs(p.tiles) do
        local row=values[tile.id]
        tile.value:SetText(tile.id=="quality" and (not r and p.market and "Choose an item" or Quality(f)) or row and row.value or "Unavailable")
        tile.tip=row and row.tip or "No supported value for the selected item and market."
    end
    p.chart:Set(x and x.series,UI.Money,tostring(p.selected)..':'..tostring(p.marketKey)..':'..p.days..':'..tostring(p.stamp))
    if not r then
        p.chart.msg:SetText(p.error and "Stored history unavailable." or "Choose an item to inspect history.")
        p.chart.note:SetText(p.error and "Refresh stored data to retry." or "Current auction availability is unknown.")
    end
    p.chartCard.heading:SetText(p.days==2 and "Lowest seen · recent observations" or "Lowest seen · observed daily closings")
    local coverage,groups=ChartWords(p,x)
    p.coverage:SetText(coverage)
    local s=x and x.series
    p.axis:SetText(s and (Date(s.from).." — "..Date(s.to).." UTC · gaps are not joined") or "Stored listing history")
    local tr=x and x.trend
    local trend=tr and tr.direction~="insufficient" and
        (({rising="Rising",falling="Falling",flat="Stable"})[tr.direction] or "Observed change")..
        (tr.percent and (" · %+.1f%%"):format(tr.percent) or "").."\n14-day comparison of daily minimum medians: "..
        tr.older.n.." older and "..tr.newer.n.." newer observed days."
        or "Insufficient history for a 14-day trend."
    local q=f.quality
    p.trends:SetText(not r and "Choose an item to inspect its observed trend and coverage." or trend.."\n"..Quality(f)..(q and q.n and (" · "..q.n.." / 30 observed days") or "")..
        "\n"..table.concat(W.Facts.QualityNotes(f,2),"\n"))
    local sup=f.supply
    local dist=x and x.distribution
    local lines={"Lowest observed listing / item: "..Money(f.min and f.min.value)}
    local comp=values.comp
    lines[#lines+1]="Observed competing price: "..(comp and comp.value or "Unavailable")
    lines[#lines+1]=sup and ("Observed supply: "..sup.items.." items / "..sup.listings.." listings"..
        (sup.complete and " · complete read" or " · partial read")) or "Observed supply unavailable"
    if s and #s.groups>0 then
        local g=s.groups[#s.groups]
        lines[#lines+1]="Older range "..Date(g.from).."–"..Date(g.to)..": "..Money(g.average).." mean / "..g.n.." observed days"
    end
    if dist then lines[#lines+1]="Listing quartiles: "..Money(dist.q25).." / "..Money(dist.q50).." / "..Money(dist.q75) end
    local posture=x and x.posture
    if posture and posture.posture~="unknown" then
        lines[#lines+1]="Recent vs historical: "..posture.posture..(" (%+.1f%%)"):format(posture.percent or 0)
    else lines[#lines+1]="Price context unavailable: "..(W.Facts.WHY[posture and posture.why] or posture and posture.why or "insufficient evidence") end
    p.contextText:SetText(not r and "Choose an item for saved pricing, supply and distribution context." or table.concat(lines,"\n"))
    p.aggregateText=groups
    p.chartTip=coverage.."\n"..(s and s.basis or "No supported history")..
        "\nGold markers show recorded minimums. No interpolation or sale activity is implied.\n"..
        (#groups>0 and ("Older aggregates (not daily markers):\n"..groups) or "No older aggregates in this window.")
end
Paint=function(p)
    W.AuctionBrowseData.Count("paints")
    local text=p.error and (p.error=="timed out" and "Item search timed out.\nRefresh stored data." or "Stored data unavailable.\nRefresh stored data to retry.") or
        p.job and "Loading known items…" or p.scope=="tracked" and "No tracked items match.\nTrack items in Browse\nor Item Advisor." or
        p.scope=="bags" and "No matching bag items.\nBag data may be\nunavailable." or
        p.market and "No matching known items.\nTry other filters." or "No saved market data.\nTry Tracked items\nor Items in bags."
    p.list:SetData(p.rows or {},text)
    p.status:SetText(p.job and "Discovering stored items…" or p.error and "Data unavailable" or
        (#(p.rows or {}).." known items"..(p.capped and " · limited to 20,000" or "")))
    Detail(p)
end
Start=function(p,reset)
    if p.job and p.job.discovering and W.AuctionBrowseData.SameMarket(p.market,D.Resolve(p.marketKey)) and p.stamp==Stamp(p,D.Resolve(p.marketKey)) then
        p.refilter=true
        if reset then p.list:ScrollTop();p.pendingView=nil end
        return
    end
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.token=p.token+1
    local mine=p.token
    local view=not reset and (p.pendingView or p.viewport or A.Capture(p.list,Key)) or nil
    p.viewport=nil;p.pendingView=view
    if reset then p.list:ScrollTop() end
    p.rows=p.rows or {};p.error=nil
    local ok,err=pcall(function()
        local market=D.Resolve(p.marketKey)
        local stamp=Stamp(p,market)
        local sourceKey=market and market.key or "none"
        if p.sourceKey and p.sourceKey~=sourceKey then p.rows,p.index={},{} end
        p.sourceKey=sourceKey
        local cached=W.AuctionBrowseData.SameMarket(p.market,market) and p.stamp==stamp and p.catalog or nil
        if not cached then W.AuctionBrowseData.Count("invalidations");p.catalog,p.known,p.dirty=nil,nil,nil end
        p.market,p.stamp=market,stamp
        local opt=Options(p);opt.catalog=cached
        p.job=D.Catalog(opt)
    end)
    if not ok then
        p.job,p.market=nil,nil;p.error="unavailable";Paint(p);R.Fault("auction market catalog",err);return
    end
    Paint(p)
    local function Step()
        if mine~=p.token or not A.IsShown() or A.Mode()~="market" then return end
        local good,done,why=pcall(p.job.Step,p.job)
        if not good then done,why=true,"failed" end
        if not done then C_Timer.After(0,Step);return end
        local job=p.job
        if why and job.Cancel then job:Cancel() end
        p.job=nil;p.error=why or job.unavailable;p.capped=job.capped
        if not p.error then
            p.rows,p.index,p.known,p.catalog=job.rows,job.index,job.seen,job.catalog
            W.AuctionBrowseData.Patch(p,Options(p))
            if p.refilter then p.refilter=nil;Start(p,true);return end
        else p.index=p.index or {} end
        if not p.index[p.selected] then p.selected=p.rows[1] and p.rows[1].item end
        Paint(p);A.Restore(p.list,view,Key);p.pendingView=nil
        if p.stamp~=Stamp(p,p.market) then A.Schedule() end
    end
    local Advance=Step
    Step=function()
        local ok,why=pcall(Advance)
        if ok or mine~=p.token then return end
        if p.job and p.job.Cancel then p.job:Cancel() end
        p.token=p.token+1;p.job,p.dirty,p.refilter=nil,nil,nil
        p.error="failed";W.AuctionBrowseData.Count("errors")
        p.status:SetText("Data unavailable · refresh saved data")
        pcall(Paint,p);R.Fault("auction market callback",why)
    end
    C_Timer.After(0,Step)
    C_Timer.After(15,function()
        if mine~=p.token or not p.job then return end
        if p.job.Cancel then p.job:Cancel() end
        p.token=p.token+1;p.job,p.error=nil,"timed out";Paint(p)
    end)
end
function V.Search(query)
    if not page then return end
    page.query=W.Text(query,200) or "";page.focusItem=nil
    page.search:SetText(page.query)
    page.search.hint:SetShown(page.query=="" and not page.search:HasFocus())
    Start(page,true)
end
function V.Filter(key,value)
    if not page or not ({scope=true,category=true,quality=true,marketKey=true})[key] then return end
    page[key]=value;page.focusItem=nil
    if key=="marketKey" then page.serverVariant="";D.Clear();if value=="server" then page.days=math.min(page.days,60);page.rangeDrop:Refresh() end;if value=="server" and W.Bridge then W.Bridge.Load() end end
    page.scopeDrop:Refresh();page.categoryDrop:Refresh();page.qualityDrop:Refresh();page.marketDrop:Refresh()
    Start(page,true)
    if key=="marketKey" and value=="server" then
        local mine=page.token
        local function Ready()
            if not A.IsShown() or A.Mode()~="market" or page.token~=mine then return end
            if W.Bridge.Status().loading then C_Timer.After(0.05,Ready) else Start(page,true) end
        end
        C_Timer.After(0.05,Ready)
    end
end
function V.Variant(key)
    if not page or not External(page) then return false end
    if key~="" and not W.Bridge.Record(page.selected,key) then return false end
    page.serverVariant=key;page.variantDrop:Refresh();Detail(page);return true
end
function V.Metric(metric)
    if not page or not External(page) or not ({minimum=true,recent=true,supply=true})[metric] then return false end
    page.serverMetric=metric;page.metricDrop:Refresh();Detail(page);return true
end
function V.Range(days)
    if not page or External(page) and days>60 then return end
    for _,v in ipairs(D.RANGES) do if v[1]==days then page.days=days;page.rangeDrop:Refresh();Detail(page);return end end
end
function V.Select(item)
    if not page or not page.index or not page.index[item] then return false end
    page.selected=item;page.serverVariant="";AD.Request(item);page.list:Layout();Detail(page);return true
end
function A.OpenMarket(item,opt)
    local ctx=D.Context(item,opt)
    if not ctx or not A.IsShown() then return false end
    A.Go("market")
    page.context=ctx;page.marketKey=ctx.market or "auto";page.serverVariant=ctx.serverVariant or ""
    page.scope,page.category,page.quality="all","all",-1
    page.selected,page.focusItem=ctx.item,ctx.item
    page.query=tostring(ctx.item);page.search:SetText(page.query);page.search.hint:Hide()
    page.scopeDrop:Refresh();page.categoryDrop:Refresh();page.qualityDrop:Refresh();page.marketDrop:Refresh()
    if page.marketKey=="server" and W.Bridge then
        W.Bridge.Load()
        V.Filter("marketKey","server")
        page.serverVariant=ctx.serverVariant or ""
        page.focusItem=ctx.item
    else Start(page,true) end
    return true
end
local function Build(p)
    page=p
    p.query,p.scope,p.category,p.quality,p.days,p.marketKey="","all","all",-1,14,"auto"
    if W.Bridge and W.Bridge.Status().ready then p.scope="bags" end
    p.metadata,p.bags,p.token=0,0,0
    p.serverVariant,p.serverMetric="","recent"
    p.search=UI.Search(p,292,32,"Search market items or ID…");p.search:SetPoint("TOPLEFT",0,0);p.search:SetMaxLetters(200)
    p.search:SetScript("OnEnterPressed",function(self) self:ClearFocus();V.Search(self:GetText()) end)
    p.search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    p.search:HookScript("OnTextChanged",function(self) self.hint:SetShown(self:GetText()=="" and not self:HasFocus()) end)
    local function Drop(width,choices,field)
        return A.Dropdown(p,width,choices,function() return p[field] end,function(v) V.Filter(field,v) end)
    end
    p.scopeDrop=Drop(190,function() return {{"all","All known market items"},{"tracked","Tracked items"},{"bags","Items in bags"}} end,"scope")
    p.scopeDrop:SetPoint("LEFT",p.search,"RIGHT",10,0)
    p.categoryDrop=Drop(180,function() return W.AuctionBrowseData.CATEGORIES end,"category")
    p.categoryDrop:SetPoint("LEFT",p.scopeDrop,"RIGHT",10,0)
    p.rangeDrop=A.Dropdown(p,170,function() if not External(p) then return D.RANGES end local ranges={} for _,entry in ipairs(D.RANGES)do if entry[1]<=60 then ranges[#ranges+1]={entry[1],entry[1]==2 and "2-day window" or entry[2]} end end return ranges end,function() return p.days end,V.Range)
    p.rangeDrop:SetPoint("TOPRIGHT",0,0)
    p.marketDrop=Drop(494,function()
        local entries=D.Markets()
        if p.marketKey~="auto" and not D.Resolve(p.marketKey) then entries[#entries+1]={p.marketKey,"Selected market unavailable"} end
        return entries
    end,"marketKey");p.marketDrop:SetPoint("TOPLEFT",0,-42)
    p.qualityDrop=Drop(180,function() return W.AuctionBrowseData.QUALITIES end,"quality")
    p.qualityDrop:SetPoint("LEFT",p.marketDrop,"RIGHT",10,0)
    p.variantDrop=A.Dropdown(p,180,function() return W.ServerMarket and W.ServerMarket.Variants(p.selected) or {{"","Choose exact variant"}} end,
        function()return p.serverVariant end,V.Variant)
    p.variantDrop:SetPoint("LEFT",p.marketDrop,"RIGHT",10,0);p.variantDrop:Hide()
    p.refresh=UI.Button(p,"Refresh stored data",170,"secondary",function() D.Clear();Start(p,false) end,32)
    p.refresh:SetPoint("TOPRIGHT",0,-42)
    UI.Tip(p.refresh,"Refresh stored data","Rereads only saved Workshop observations and bag metadata. It never sends an Auction House query.")
    local left=A.Card(p,"Market items",100);p.itemCard=left
    left:SetWidth(262);left:SetPoint("TOPLEFT",0,-88);left:SetPoint("BOTTOMLEFT",0,0)
    p.list=UI.List(left,60,function(parent)
        local r=CreateFrame("Button",nil,parent);UI.Hover(r)
        r.pic=UI.ItemIcon(r,34);r.pic:SetPoint("LEFT",6,0)
        r.name=A.Text(r,"",14,48,-9,-8);r.name:SetHeight(19)
        r.sub=A.Text(r,"",11,48,-32,-6,UI.K.textDim)
        r.fill=function(self,x)
            self.data=x;self.name:SetText(x.info.name);self.pic.tex:SetTexture(x.info.icon or UI.ICON_BLANK)
            local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[x.info.quality or 1]
            if color then self.name:SetTextColor(color.r,color.g,color.b) else UI.Paint(self.name,UI.K.text) end
            self.sub:SetText((AD.Tracked()[x.item] and "★ " or "")..(Context(p,x.item).variant and "Variant not priced" or x.unit and ("Lowest seen "..UI.Money(x.unit)) or "No latest listing price"))
            self:SetSelected(p.selected==x.item)
        end
        r.twichRowClick=function() if r.data then V.Select(r.data.item) end end
        UI.ItemTip(r,function() return r.data and not Context(p,r.data.item).variant and r.data.item end)
        return r
    end,420,false)
    p.list.empty:ClearAllPoints()
    p.list.empty:SetPoint("TOPLEFT",14,-14);p.list.empty:SetPoint("TOPRIGHT",-14,-14)
    Wrap(p.list.empty,132)
    p.list.box:SetPoint("TOPLEFT",4,-38);p.list.box:SetPoint("BOTTOMRIGHT",-4,50)
    p.status=A.Text(left,"",11,12,-1,-12,UI.K.textDim);p.status:ClearAllPoints();p.status:SetPoint("BOTTOMLEFT",12,12);p.status:SetPoint("RIGHT",-12,0);Wrap(p.status,30)
    local main=CreateFrame("Frame",nil,p);p.main=main
    main:SetPoint("TOPLEFT",left,"TOPRIGHT",12,0);main:SetPoint("BOTTOMRIGHT",0,0)
    UI.Panel(main,"card")
    p.pic=UI.ItemIcon(main,54);p.pic:SetPoint("TOPLEFT",12,-10)
    p.pic:EnableMouse(true)
    p.pic:SetScript("OnEnter",function()
        if not p.chosen then return end
        local variant=Context(p,p.chosen.item).variant
        UI.ItemTipLines(p.pic,not variant and p.chosen.item or nil,
            variant and {{"Variant identity preserved; base-item advice unavailable."}} or nil,p.chosen.info.name)
    end)
    p.pic:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    p.name=A.Text(main,"",20,78,-10,-424);p.name:SetWordWrap(true);p.name:SetMaxLines(2);p.name:SetJustifyV("TOP");p.name:SetHeight(48)
    p.kind=A.Text(main,"",12,78,-64,-12,UI.K.textDim)
    p.track=UI.Button(main,"Track Item",110,"secondary",function()
        if p.chosen then
            local ok=AD.Track(p.chosen.item)
            A.Note(ok and "Tracking updated in the shared Item Advisor list." or "Tracking unavailable or list full.")
            if p.scope=="tracked" then Start(p,false) else p.list:Layout();Detail(p) end
        end
    end,30)
    p.track:SetPoint("TOPRIGHT",-286,-12)
    p.browse=UI.Button(main,"Open Browse",124,"secondary",function()
        if p.chosen then A.OpenBrowse(p.chosen.item,nil,{market=p.market and p.market.key or p.marketKey}) end
    end,30);p.browse:SetPoint("LEFT",p.track,"RIGHT",8,0)
    p.advisor=UI.Button(main,"Use in Advisor",136,"secondary",function()
        local item=p.chosen and p.chosen.item
        if item and UI.Advisor then A.Hide();UI.Advisor.Open(item) end
    end,30);p.advisor:SetPoint("LEFT",p.browse,"RIGHT",8,0)
    UI.Tip(p.advisor,"Item Advisor","Opens the existing Workshop Item Advisor with this base item. Advisor uses its own existing market selection; Market's temporary research selector does not change it.")
    p.source=A.Text(main,"",11,12,-84,-12,UI.K.textDim);Wrap(p.source,32)
    p.chartCard=A.Card(main,"Lowest seen · observed daily closings",248)
    p.chartCard:SetPoint("TOPLEFT",8,-124);p.chartCard:SetPoint("TOPRIGHT",-8,-124)
    p.chart=UI.AdvancedMarketChart(p.chartCard,800,160)
    p.metricDrop=A.Dropdown(p.chartCard,190,function()return W.ServerMarket and W.ServerMarket.METRICS or {} end,
        function()return p.serverMetric end,V.Metric)
    p.metricDrop:SetPoint("TOPRIGHT",-8,-2);p.metricDrop:Hide()
    p.chart:SetPoint("TOPLEFT",10,-36);p.chart:SetPoint("TOPRIGHT",-10,-36)
    p.axis=A.Text(p.chartCard,"",11,12,-200,-12,UI.K.textDim)
    p.coverage=A.Text(p.chartCard,"",11,12,-218,-12,UI.K.textDim);Wrap(p.coverage,26)
    p.tiles={}
    local definitions={{"market","Market value · 14d"},{"recent","Recent listing"},{"hist","Historical · 60d"},
        {"supply","Observed supply"},{"comp","Competing price"},{"quality","Data quality"}}
    for _,def in ipairs(definitions) do
        local tile=A.Card(main,def[2],70);tile.id=def[1]
        UI.CL.Font(tile.heading,12)
        tile.value=A.Text(tile,"Unavailable",14,10,-30,-8,UI.K.text);Wrap(tile.value,36)
        UI.TipFn(tile,def[2],function() return tile.tip end)
        p.tiles[#p.tiles+1]=tile
    end
    p.trendCard=A.Card(main,"Trend & coverage",100)
    p.trends=A.Text(p.trendCard,"",11,12,-30,-12);Wrap(p.trends,94)
    UI.TipFn(p.trendCard,"Market quality",function()
        local f=p.projection and p.projection.facts
        return f and f.quality and (f.quality.basis.."\n"..table.concat(W.Facts.QualityNotes(f,10),"\n"))
    end)
    p.contextCard=A.Card(main,"Observed price context",100)
    p.contextText=A.Text(p.contextCard,"",11,12,-30,-12);Wrap(p.contextText,94)
    UI.TipFn(p.contextCard,"Stored context and aggregate ranges",function()
        return "Listing prices and observed supply are not sales, demand or current availability.\n"..(p.aggregateText or "")
    end)
    local function Layout()
        local w=main:GetWidth();if not w or w<100 then w=888 end
        local tileW=(w-16-5*6)/6
        for i,tile in ipairs(p.tiles) do tile:ClearAllPoints();tile:SetWidth(tileW);tile:SetPoint("TOPLEFT",8+(i-1)*(tileW+6),-382) end
        local half=(w-26)/2
        p.trendCard:SetWidth(half);p.trendCard:SetPoint("TOPLEFT",8,-462);p.trendCard:SetPoint("BOTTOMLEFT",8,8)
        p.contextCard:SetPoint("TOPLEFT",p.trendCard,"TOPRIGHT",10,0);p.contextCard:SetPoint("BOTTOMRIGHT",-8,8)
        if p.projection then p.chart:Render() end -- geometry only; keep the inspected interval
    end
    main:HookScript("OnSizeChanged",Layout);Layout()
    p:SetScript("OnEvent",function(_,event,item,ok)
        if event=="GET_ITEM_INFO_RECEIVED" then
            W.AuctionBrowseData.Metadata(p,item,ok)
        elseif event=="BAG_UPDATE_DELAYED" and p.scope=="bags" then p.bags=p.bags+1
        else return end
        A.Schedule()
    end)
end
local function Render(p)
    if not p.listening then
        W.Strategy.Listen(A.Schedule,true)
        p:RegisterEvent("GET_ITEM_INFO_RECEIVED");p:RegisterEvent("BAG_UPDATE_DELAYED")
        p.listening=true;p.eventCount=2
    end
    if p.job then return end
    local market=D.Resolve(p.marketKey)
    if not p.stamp or not W.AuctionBrowseData.SameMarket(p.market,market) or p.stamp~=Stamp(p,market) then Start(p,false)
    else
        local view=A.Capture(p.list,Key)
        local changed,structural,_,updates=W.AuctionBrowseData.Patch(p,Options(p))
        if changed and structural then Paint(p);A.Restore(p.list,view,Key)
        else
            if changed then A.PatchRows(p.list,updates) end
            Detail(p)
        end
    end
end
local function Release(p)
    p.viewport=p.pendingView or (p.rows and A.Capture(p.list,Key)) or p.viewport
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.chart:Clear()
    p.catalog,p.dirty,p.refilter=nil,nil,nil
    p.token=p.token+1;p.job,p.rows,p.index,p.known,p.market,p.projection,p.chosen,p.stamp,p.pendingView=nil,nil,nil,nil,nil,nil,nil,nil,nil
    p.list:SetData({});p:UnregisterAllEvents();p.listening=false
    W.Strategy.Listen(A.Schedule,false)
    for _,r in ipairs(p.list.rows) do r.data=nil end
    D.Clear()
end
A.Register("market",{Build=Build,Render=Render,Release=Release})
