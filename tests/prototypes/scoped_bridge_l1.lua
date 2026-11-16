-- Offline L1 proof only. Not in any TOC. No installation, networking or saved data.
-- `plan` is the expanded authoritative schema supplied by the test harness.
local W=TwichUI.Workshop
local J,S=W.BridgeCodec,W.BridgeValidate
local P={}
local function need(ok) if not ok then error('invalid scoped proof',0) end end
local function same(a,b) return J.Encode(a)==J.Encode(b) end
local function hash(v) return J.SHA(J.Encode(v)) end
local function body(g) local v=J.Copy(g);v.generation_id=nil;v.integrity=nil;return v end
local function seal(g)
    local b=body(g);local h=J.Copy(b);h.records=nil
    g.generation_id=hash(b)
    g.integrity=J.Object();g.integrity.records_bytes=#J.Encode(g.records)
    g.integrity.records_sha256=hash(g.records);g.integrity.manifest_sha256=hash(h)
    return g
end
function P.Validate(g,plan,expected,budget)
    S.Schema(plan,g)
    need(#J.Encode(g)<=32*1024*1024 and same(g.integrity,seal(J.Copy(g)).integrity) and g.generation_id==seal(J.Copy(g)).generation_id)
    local h=J.Copy(g);h.records=nil;need(#J.Encode(h)<=256*1024)
    local scope,request=g.scope,g.scope.request
    need(same(request,expected) and request.issuer_id==g.issuer_id and same(request.market,g.market))
    need(request.pricing_algorithm==g.pricing_algorithm and request.history_basis==g.history_basis)
    need(request.history_from_day==g.coverage.history_from_day and request.history_through_day==g.coverage.history_through_day)
    need(scope.request_digest==hash(request))
    local stable=J.Copy(request);stable.history_from_day=nil;stable.history_through_day=nil
    need(scope.selection_id==hash(stable))
    need(same(g.required_features,J.Parse('["exact_copper","current_summaries","daily_history","scoped_selection"]')))
    need(#g.records==g.record_count and g.record_count==scope.requested_count and #request.variants==g.record_count)
    need(same(scope.included,request.variants) and #scope.record_sha256==g.record_count)
    need(g.desktop_sync_completed_at==J.NULL and g.producer.desktop_build=='not-applicable-server-export')
    -- Private validation view only; never return or activate it as full-market data.
    local view=J.Copy(g);view.scope=nil;view.schema_version=2
    view.required_features=J.Parse('["exact_copper","current_summaries","daily_history"]')
    view.coverage.generation_complete=true;seal(view)
    local header=J.Copy(view);header.records=nil
    local ctx=S.Header(header)
    local lastItem,lastKey=0,''
    for i,r in ipairs(g.records) do
        need(r.item_id>lastItem or r.item_id==lastItem and r.variant_key>lastKey)
        need(request.variants[i].item_id==r.item_id and request.variants[i].variant_key==r.variant_key)
        need(scope.record_sha256[i]==hash(r));S.Record(ctx,r)
        lastItem,lastKey=r.item_id,r.variant_key
    end
    local from,to=S.Date(request.history_from_day),S.Date(request.history_through_day)
    need(from and to and to>=from and to-from<60 and #scope.date_coverage==to-from+1)
    for i,d in ipairs(scope.date_coverage) do
        need(S.Date(d.day)==from+i-1)
        local winner,complete
        local function newer(o,old) return not old or o.key>old.key or o.key==old.key and S.CompareMoney(o.id,old.id)>0 end
        for _,o in ipairs(ctx.observations) do
            if o.source.utc_day==d.day then
                if newer(o,winner) then winner=o end
                if o.source.scope_complete and newer(o,complete) then complete=o end
            end
        end
        local chosen=complete or winner
        need(d.state==(complete and 'complete_close' or winner and 'incomplete_only' or 'no_observation'))
        need(d.observation_ref==(chosen and chosen.index or J.NULL))
    end
    local limits=budget or {canonical_bytes=2*1024*1024,records=1000}
    need(not limits.canonical_bytes or #J.Encode(g)<=limits.canonical_bytes)
    need(not limits.records or #g.records<=limits.records)
    return g
end
function P.Lookup(g,item,key)
    for _,r in ipairs(g.records) do if r.item_id==item and r.variant_key==key then return r,'included' end end
    return nil,'outside_scope'
end
function P.Value(r,metric)
    local v=r.current.metrics[metric]
    if v==J.NULL then return nil,'unavailable' end
    if not S.Money(v,true) or #v>11 or #v==11 and v>'99999999999' then return nil,'unsupported' end
    return tonumber(v)
end
function P.Accept(state,g,plan,expected,budget)
    P.Validate(g,plan,expected,budget)
    if not state.active or state.active.generation_id~=g.generation_id then
        state.previous,state.active=state.active,J.Copy(g)
    end
end
return P
