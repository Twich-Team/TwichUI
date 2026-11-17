-- Opt-in offline Advisor callback benchmark. Uses recording frames, not native rendering.
local fixture = dofile(TESTS .. 'test_workshop_advisor_ui.lua')
local c, W, p = fixture.client, fixture.workshop, fixture.page
local count = tonumber(arg[1]) or 20000
local repeats = tonumber(arg[2]) or 5
W.UI.Advisor.Open(10007)
p:Hide()
assert(count>=1 and count%1==0 and repeats>=1 and repeats%1==0, "positive integer size/repeats")
local clock = os.clock
local originalSort = table.sort
local sorted, sortMax, sortTotal = 0, 0, 0
c.table = {}
for k,v in pairs(table) do c.table[k]=v end
c.table.sort = function(rows, less)
    local start=clock(); originalSort(rows,less); local elapsed=clock()-start
    if rows[1] and type(rows[1])=='table' and rows[1].item then
        sorted=sorted+1;sortTotal=sortTotal+elapsed;sortMax=math.max(sortMax,elapsed)
    end
end
local items={}
-- Noncontiguous integer identities; same insertion order in each fresh Lua process.
for i=count,1,-1 do items[10000+i*7]={} end
W.Session.PriceSource=function() return {market={items=items,generation='advisor-benchmark'}} end
W.Session.AllRecipes=function() return {} end
c.C_Container={GetContainerNumSlots=function() return 0 end}
c.C_Item.GetItemInfo=function(id)
    return 'Item '..id,nil,1,nil,nil,'Category '..(id%12),'Kind',20,'',5000,10,7,0,0
end
W.AdvisorData.SetSource('all')
c.TwichUIDB.workshop.view.advisorTracked={}
local pending={}
c.C_Timer.After=function(_,fn) pending[#pending+1]=fn end
local function timed(fn)
    local start=clock(); fn(); return clock()-start
end
local rawCatalog=W.AdvisorData.Catalog
local catalogMax,catalogTotal,listMax,listTotal=0,0,0,0
W.AdvisorData.Catalog=function()
    local job=rawCatalog();local step=job.Step
    job.Step=function(self)
        local start=clock();local done,err=step(self);local elapsed=clock()-start
        catalogTotal=catalogTotal+elapsed;catalogMax=math.max(catalogMax,elapsed)
        return done,err
    end
    return job
end
local setData=p.list.SetData
p.list.SetData=function(self,...)
    local start=clock();setData(self,...);local elapsed=clock()-start
    listTotal=listTotal+elapsed;listMax=math.max(listMax,elapsed)
end
for run=1,repeats do
    p:Hide(); pending={};collectgarbage('collect')
    local before=collectgarbage('count')
    sorted,sortMax,sortTotal=0,0,0
    catalogMax,catalogTotal,listMax,listTotal=0,0,0,0
    local total,maxCallback,calls,peak=0,0,0,before
    local function invoke(fn) local elapsed=timed(fn);total=total+elapsed;maxCallback=math.max(maxCallback,elapsed);calls=calls+1;peak=math.max(peak,collectgarbage("count")) end
    invoke(function() p:Show() end)
    while #pending>0 do
        local batch=pending;pending={}
        for _,fn in ipairs(batch) do invoke(fn) end
        assert(calls<20000,'bounded completion')
    end
    assert(#p.list.data==count,'result count')
    for i,row in ipairs(p.list.data) do assert(row.item==10000+i*7,'exact ID ordering') end
    collectgarbage('collect');local retained=collectgarbage('count')-before
    local pool=#p.list.rows
    p:Hide();pending={};collectgarbage('collect')
    local released=collectgarbage('count')-before
    assert(W.UI.Advisor.Stats().items==0 and #p.list.data==0,'release on hide')
    print(('BENCH n=%d run=%d total_ms=%.3f max_callback_ms=%.3f catalog_ms=%.3f catalog_max_ms=%.3f sort_ms=%.3f sort_max_ms=%.3f list_ms=%.3f list_max_ms=%.3f retained_kib=%.1f peak_sampled_kib=%.1f released_kib=%.1f callbacks=%d rows=%d pool=%d'):format(count,run,total*1000,maxCallback*1000,catalogTotal*1000,catalogMax*1000,sortTotal*1000,sortMax*1000,listTotal*1000,listMax*1000,retained,peak-before,released,calls,count,pool))
end
