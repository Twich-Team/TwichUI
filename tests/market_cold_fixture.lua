-- Shared opt-in cold-path fixture. Fabricated contract data, never a live export.
return function(c,days,counts,variants)
    local W=c.TwichUI.Workshop;local J,P=W.BridgeCodec,W.Pricing
    local file=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
    local f=J.Parse(file:read('*a'));file:close()
    local h,row=f.manifest,J.Parse(f.parts['29'])[1]
    local _,ending=W.BridgeValidate.Time(h.generated_at)
    if days==60 then
        h.observations=J.Array();row[14]=J.Array()
        for d=59,0,-1 do
            h.observations[#h.observations+1]=setmetatable({observation_id=tostring(902-d),
                observed_at=os.date('!%Y-%m-%dT%H:%M:%SZ',ending-d*86400),scope_complete=true,synthetic=true},J.OBJECT)
            row[14][#row[14]+1]=setmetatable({0,'100','90',5},J.ARRAY)
        end
        row[10]='100';row[11]=14;row[12]=60;row[13]=60
    end
    -- Ordinary admission exercises only; every record remains fabricated.
    h.synthetic=false;for _,o in ipairs(h.observations)do o.synthetic=false end
    c.time=function()return ending+60 end;c.UnitFactionGroup=function()return 'Horde' end
    h.partitions=J.Array();h.record_count=0
    local parts,keys={},{}
    for b=0,63 do
        local rows=J.Array()
        for n=1,(counts[b] or 0) do
            local r=J.Copy(row);r[1]=variants and 64+b or n*64+b
            r[2]=variants and J.SHA('variant:'..n) or P.BaseKey(r[1])
            r[4]=tostring(120+n);r[5]=r[4];rows[#rows+1]=r
        end
        table.sort(rows,function(a,b)return a[1]<b[1] or a[1]==b[1] and a[2]<b[2] end)
        if #rows>0 then
            local raw=J.Encode(rows);parts[b]=raw;keys[b]={item=rows[1][1],variant=rows[1][2]}
            h.partitions[#h.partitions+1]=setmetatable({bucket=b,bytes=#raw,record_count=#rows,sha256=J.SHA(raw)},J.OBJECT)
            h.record_count=h.record_count+#rows
        end
    end
    h.coverage.source_records=h.record_count;h.coverage.delivered_records=h.record_count
    local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
    local root={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({
        schema_version=1,generation_id=h.generation_id,desktop_build='cold-path-fixture',completed_at=h.generated_at},J.OBJECT))}
    return {header=h,parts=parts,keys=keys,root=root,days=days}
end
