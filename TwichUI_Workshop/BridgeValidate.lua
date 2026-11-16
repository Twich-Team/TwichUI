-- Frozen contract 1: schema/semantic checks shared by the cooperative reader.
local W=TwichUI.Workshop
local J=W.BridgeCodec
local S={}
W.BridgeValidate=S
local N=J.NULL
local function need(ok) if not ok then error('invalid bridge contract',0) end end
local function array(v) return type(v)=='table' and getmetatable(v)==J.ARRAY end
local function object(v) return type(v)=='table' and getmetatable(v)==J.OBJECT end
local function money(v,positive)
    return type(v)=='string' and #v>0 and #v<=19 and not v:find('[^0-9]') and (v=='0' or v:sub(1,1)~='0')
        and (#v<19 or v<='9223372036854775807') and (not positive or v~='0')
end
local function cmp(a,b) if #a~=#b then return #a<#b and -1 or 1 end;if a==b then return 0 end;return a<b and -1 or 1 end
S.Money=money;S.CompareMoney=cmp
function S.Date(v)
    if type(v)~='string' then return nil end
    local y,m,d=v:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$');y,m,d=tonumber(y),tonumber(m),tonumber(d)
    if not y or y<1 or m<1 or m>12 then return nil end
    local leap=y%4==0 and (y%100~=0 or y%400==0)
    local days={31,leap and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    if d<1 or d>days[m] then return nil end
    local previous=y-1;local n=previous*365+math.floor(previous/4)-math.floor(previous/100)+math.floor(previous/400)
    for i=1,m-1 do n=n+days[i] end
    return n+d-1-719162
end
function S.Time(v)
    if type(v)~='string' then return nil end
    local day,h,m,s,f=v:match('^(%d%d%d%d%-%d%d%-%d%d)T(%d%d):(%d%d):(%d%d)(.*)Z$')
    local number=day and S.Date(day);h,m,s=tonumber(h),tonumber(m),tonumber(s)
    if not number or not h or h>23 or m>59 or s>59 or (f~='' and (#f<2 or #f>7 or not f:match('^%.%d+$'))) then return nil end
    local fraction=f=='' and '' or f:sub(2)
    return day..'T'..('%02d:%02d:%02d'):format(h,m,s)..'.'..fraction..string.rep('0',6-#fraction),number*86400+h*3600+m*60+s,number
end
local function pattern(p,v)
    if p=='^[0-9a-f]{64}$' then return #v==64 and not v:find('[^0-9a-f]')
    elseif p=='^(0|[1-9][0-9]{0,18})$' then return money(v,false)
    elseif p=='^[1-9][0-9]{0,18}$' then return money(v,true)
    elseif p=='^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return S.Date(v)~=nil
    elseif p:find('T[0-9]',1,true) then return S.Time(v)~=nil and (not p:find('\\\\.',1,true) or not v:find('.',1,true)) end
    return false
end
local function schema(plan,v,tick)
    if tick then tick() end
    if plan.type then
        local types=type(plan.type)=='table' and plan.type or {plan.type};local valid=false
        for _,kind in ipairs(types) do valid=valid or kind=='null' and v==N or kind=='object' and object(v) or kind=='array' and array(v)
            or kind=='string' and type(v)=='string' or kind=='boolean' and type(v)=='boolean'
            or kind=='integer' and W.Int(v,-9007199254740991,9007199254740991)~=nil end
        need(valid)
    end
    if plan.const~=nil then need(type(plan.const)=='table' and J.Encode(v,tick)==J.Encode(plan.const,tick) or v==plan.const) end
    if plan.enum then local found=false;for _,x in ipairs(plan.enum) do found=found or v==x end;need(found) end
    if plan.anyOf then local found=false;for _,p in ipairs(plan.anyOf) do if pcall(schema,p,v,nil) then found=true;break end end;need(found) end
    if plan.allOf then for _,p in ipairs(plan.allOf) do schema(p,v,tick) end end
    if plan['if'] then local yes=pcall(schema,plan['if'],v,nil);if yes and plan['then'] then schema(plan['then'],v,tick) elseif not yes and plan['else'] then schema(plan['else'],v,tick) end end
    if object(v) then
        for _,key in ipairs(plan.required or {}) do need(v[key]~=nil) end
        for key,x in pairs(v) do if plan.properties and plan.properties[key] then schema(plan.properties[key],x,tick) elseif plan.additionalProperties==false then need(false) end end
    elseif array(v) then
        need((not plan.minItems or #v>=plan.minItems) and (not plan.maxItems or #v<=plan.maxItems))
        local seen={};for _,x in ipairs(v) do if plan.uniqueItems then local k=J.Encode(x);need(not seen[k]);seen[k]=true end;if plan.items then schema(plan.items,x,tick) end end
    elseif type(v)=='string' then
        local _,len=v:gsub('[^\128-\191]','');need((not plan.minLength or len>=plan.minLength) and (not plan.maxLength or len<=plan.maxLength))
        if plan.pattern then need(pattern(plan.pattern,v)) end
        if plan.format then
            local f=plan.format
            need(f=='copper-i64' and money(v,false) or f=='positive-i64' and money(v,true) or f=='date' and S.Date(v)~=nil or f=='date-time' and S.Time(v)~=nil
                or f=='uuid' and #v==36 and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil)
        end
    elseif type(v)=='number' then need((not plan.minimum or v>=plan.minimum) and (not plan.maximum or v<=plan.maximum)) end
end
S.Schema=schema
local function without(h)
    local out=J.Object();for k,v in pairs(h) do if k~='generation_id' and k~='integrity' and k~='records' then out[k]=v end end;return out
end
S.ManifestBody=without
function S.Header(h,tick)
    need(object(h) and h.records==nil)
    local plan=W.BridgeSchemas[h.schema_version];need(plan~=nil)
    local g=J.Object();for k,v in pairs(h) do g[k]=v end;g.records=J.Array();schema(plan,g,tick)
    local scoped=h.schema_version==3;local headerLimit=scoped and 256*1024 or 65536
    need(h.coverage.generation_complete==(not scoped) and #J.Encode(h,tick)<=headerLimit)
    local manifest=J.Encode(without(h),tick);need(#manifest<=headerLimit and J.SHA(manifest,tick)==h.integrity.manifest_sha256)
    local at=S.Time(h.generated_at);need(at~=nil)
    if h.desktop_sync_completed_at~=N then need(S.Time(h.desktop_sync_completed_at)<=at) end
    if h.server_checked_at~=N then need(S.Time(h.server_checked_at)<=at) end
    need(S.Date(h.as_of_utc_day)<=S.Date(h.generated_at:sub(1,10)))
    local c=h.coverage;local from,to,today=S.Date(c.history_from_day),S.Date(c.history_through_day),S.Date(h.as_of_utc_day)
    need(from<=to and to<=today and today-from>=0 and today-from<60)
    need(c.delivered_observed_days<=c.available_observed_days and (not c.history_complete or not c.history_truncated and c.delivered_observed_days==c.available_observed_days))
    if c.history_truncated then local found=false;for _,v in ipairs(c.omitted_sections) do found=found or v=='older_daily_history' end;need(found) end
    need((h.market.source_kind=='auctions')==(c.scope=='house_auctions'))
    if h.market.mapping_verified then need(h.market.player_ruleset~=N and h.market.mapping_evidence_sha256~=N) end
    local ctx={header=h,plan=plan,from=from,to=to,today=today,observations={},closes={},observedDays={}}
    local ids,delivered={},{};local latest
    for i,o in ipairs(h.observations) do
        local tk,seconds,day=S.Time(o.observed_at)
        need(tk and tk<=at and day==S.Date(o.utc_day) and not ids[o.observation_id] and cmp(o.observation_id,h.watermark_observation_id)<=0)
        ids[o.observation_id]=true;ctx.observedDays[day]=true
        if o.upstream_updated_at~=N then need(S.Time(o.upstream_updated_at)<=at) end
        need(not o.synthetic or h.synthetic)
        local entry={key=tk,seconds=seconds,day=day,id=o.observation_id,source=o,index=i-1};ctx.observations[i]=entry
        local function newer(a,b) return not b or a.key>b.key or a.key==b.key and cmp(a.id,b.id)>0 end
        if newer(entry,latest) then latest=entry end
        if o.scope_complete and newer(entry,ctx.closes[o.utc_day]) then ctx.closes[o.utc_day]=entry end
        if day>=from and day<=to then delivered[day]=true end
    end
    local n=0;for _ in pairs(delivered) do n=n+1 end;need(n==c.delivered_observed_days)
    if h.current_observation_ref~=N then
        local o=ctx.observations[h.current_observation_ref+1]
        need(o~=nil and o==latest and o.source.scope_complete==c.current_complete)
    else need(h.record_count==0) end
    if scoped then
        local scope,request=h.scope,h.scope.request
        local function same(a,b) return J.Encode(a,tick)==J.Encode(b,tick) end
        need(request.issuer_id==h.issuer_id and same(request.market,h.market))
        need(request.pricing_algorithm==h.pricing_algorithm and request.history_basis==h.history_basis)
        need(request.history_from_day==c.history_from_day and request.history_through_day==c.history_through_day)
        local requestText=J.Encode(request,tick);need(#requestText<=128*1024)
        need(scope.request_digest==J.SHA(requestText,tick))
        local stable=J.Object();for k,v in pairs(request) do if k~='history_from_day' and k~='history_through_day' then stable[k]=v end end
        need(scope.selection_id==J.SHA(J.Encode(stable,tick),tick))
        need(h.record_count==scope.requested_count and h.record_count==#request.variants and #scope.record_sha256==h.record_count)
        need(same(scope.included,request.variants))
        need(h.desktop_sync_completed_at==N and h.producer.desktop_build=='not-applicable-server-export')
        local lastItem,lastKey=0,''
        for _,v in ipairs(request.variants) do
            need(v.item_id>lastItem or v.item_id==lastItem and v.variant_key>lastKey)
            lastItem,lastKey=v.item_id,v.variant_key
        end
        need(#scope.date_coverage==to-from+1)
        ctx.calendar={};ctx.recordPosition=0
        for i,d in ipairs(scope.date_coverage) do
            need(S.Date(d.day)==from+i-1)
            local winner,complete
            for _,o in ipairs(ctx.observations) do
                if o.day==from+i-1 then
                    local function newer(old) return not old or o.key>old.key or o.key==old.key and cmp(o.id,old.id)>0 end
                    if newer(winner) then winner=o end
                    if o.source.scope_complete and newer(complete) then complete=o end
                end
                if tick then tick() end
            end
            local chosen=complete or winner
            need(d.state==(complete and 'complete_close' or winner and 'incomplete_only' or 'no_observation'))
            need(d.observation_ref==(chosen and chosen.index or N))
            ctx.calendar[from+i-1]=d
        end
    end
    return ctx
end
local function supported(v) return v==N or money(v,true) and (#v<12 or #v==11 and v<='99999999999') end
-- Avoid any count addition beyond the exact-double integer domain.
local function add(a,b) need(a<=9007199254740991-b);return a+b end
local function counts(x,prices,source,model)
    if x.state=='unknown' then need(x.supply==N and x.priced_supply==N and x.listing_count==N);for _,v in ipairs(prices) do need(v==N) end
    else
        need(x.supply~=N and x.priced_supply~=N and x.listing_count~=N and x.priced_supply<=x.supply)
        if x.state=='absent' then need(source.scope_complete and x.supply==0 and x.priced_supply==0 and x.listing_count==0);for _,v in ipairs(prices) do need(v==N) end end
        if x.priced_supply==0 then for _,v in ipairs(prices) do need(v==N) end end
    end
    if x.arithmetic_status=='unsupported' then for _,v in ipairs(prices) do need(v==N) end end
    if model then for _,v in ipairs(prices) do need(supported(v)) end end
end
function S.Record(ctx,r,tick)
    local h=ctx.header;schema(ctx.plan.properties.records.items,r,tick)
    local text=J.Encode(r,tick);need(#text<=65536)
    if h.schema_version==3 then
        ctx.recordPosition=ctx.recordPosition+1
        local v=h.scope.request.variants[ctx.recordPosition]
        need(v and v.item_id==r.item_id and v.variant_key==r.variant_key)
        need(h.scope.record_sha256[ctx.recordPosition]==J.SHA(text,tick))
    end
    if r.identity_basis=='exact_upstream' then
        need(r.variant_json~=N and J.SHA(r.variant_json,tick)==r.variant_key)
        local d=J.Parse(r.variant_json,tick);need(object(d) and d.id==r.item_id and J.Encode(d,tick)==r.variant_json)
    else need(r.variant_json==N) end
    local model=h.pricing_algorithm=='twichui-pricing-v1';local c=r.current;local obs=ctx.observations[c.observation_ref+1]
    need(obs and c.observation_ref==h.current_observation_ref and c.algorithm==h.pricing_algorithm and c.metric_basis==(model and 'lower_band_mean' or 'quantity_weighted_mean') and (not c.complete or obs.source.scope_complete))
    counts(c,{c.metrics.minimum_copper,c.metrics.recent_copper},obs.source,model)
    local cov=c.coverage;need(cov.priced_days_14<=cov.priced_days_60 and cov.priced_days_60<=cov.observed_days_60)
    if model then
        need(cov.priced_days_14<=14 and cov.priced_days_60<=60)
        for _,k in ipairs({'minimum_copper','recent_copper','market_value_copper','historical_value_copper'}) do need(supported(c.metrics[k])) end
        need(c.metrics.historical_value_copper==N or cov.priced_days_60>=3)
    end
    local last=''
    for _,d in ipairs(r.daily) do
        local o=ctx.observations[d.observation_ref+1];need(o~=nil)
        need(o.source.utc_day>last and o.day>=ctx.from and o.day<=ctx.to and d.algorithm==h.pricing_algorithm);last=o.source.utc_day
        if model then need(o.source.scope_complete and ctx.closes[o.source.utc_day]==o) end
        counts(d,{d.minimum_copper,d.recent_copper},o.source,model)
    end
    if h.coverage.history_complete then
        local expected,actual={},{}
        for _,o in ipairs(ctx.observations) do if o.day>=ctx.from and o.day<=ctx.to and (not model or o.source.scope_complete) then expected[o.source.utc_day]=true end end
        for _,d in ipairs(r.daily) do actual[ctx.observations[d.observation_ref+1].source.utc_day]=true end
        for day in pairs(expected) do need(actual[day]) end;for day in pairs(actual) do need(expected[day]) end
    end
    local d=r.distribution;need((d~=N)==(r.distribution_status=='available'))
    if h.coverage.distribution_complete and c.priced_supply~=N and c.priced_supply>0 then need(d~=N) end
    if d~=N then
        need(c.state=='listed' and d.algorithm==(model and 'canonical-tiers-v1' or 'linear-unit-price-bands-v1') and d.priced_supply==c.priced_supply
            and add(d.priced_supply,d.unpriced_supply)==c.supply and add(d.priced_listing_count,d.unpriced_listing_count)==c.listing_count and (not d.complete or not d.truncated))
        if model then
            local q=d.quartiles;need(q~=N and #d.bands==0)
            local a,b,e,f=tonumber(q.q25_copper),tonumber(q.q50_copper),tonumber(q.q75_copper),tonumber(q.high_copper)
            for _,v in pairs(q) do need(v~=N and supported(v)) end
            need(a<=b and b<=e and e<=f and tonumber(q.anchor_copper)>=a and tonumber(q.anchor_copper)<=b)
            need(c.metrics.minimum_copper~=N and c.metrics.recent_copper~=N and cmp(c.metrics.minimum_copper,c.metrics.recent_copper)<=0 and tonumber(c.metrics.recent_copper)<=b)
            local previous,quantity,listings=0,d.tail_quantity,d.tail_listing_count
            for _,t in ipairs(d.tiers) do
                need(supported(t.unit_copper));local p=tonumber(t.unit_copper)
                need(previous<p and t.listing_count<=t.quantity and t.largest_listing<=t.quantity);previous=p
                quantity=add(quantity,t.quantity);listings=add(listings,t.listing_count)
            end
            need(quantity==d.priced_supply and listings==d.priced_listing_count)
        else
            need(d.quartiles==N and #d.tiers==0 and d.tail_quantity==0 and d.tail_listing_count==0)
            local quantity,listings=0,0;for _,b in ipairs(d.bands) do need(cmp(b.minimum_copper,b.maximum_copper)<=0);quantity=add(quantity,b.supply);listings=add(listings,b.listing_count) end
            need(quantity==d.priced_supply and listings==d.priced_listing_count)
        end
    end
    return r,text
end
