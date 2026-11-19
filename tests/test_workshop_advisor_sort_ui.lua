-- Interrupt the real view during cooperative sorting; stale jobs may not publish.
local f=dofile(TESTS .. 'test_workshop_advisor_ui.lua')
local c,W,p,g=f.client,f.workshop,f.page,f.game
local pending={}
c.C_Timer.After=function(_,fn) pending[#pending+1]=fn end
local function Pump()
    local ticks=0
    while #pending>0 do
        local batch=pending;pending={}
        for _,fn in ipairs(batch) do fn() end
        ticks=ticks+1;assert(ticks<1000,'callbacks settle')
    end
end
for id=1000,9999 do g.names[id]='Item '..id;g.bags[id]=1 end
c.C_Container={GetContainerNumSlots=function(bag) return bag==0 and 9000 or 0 end,
    GetContainerItemInfo=function(_,slot) return {itemID=999+slot,stackCount=1,isBound=false} end}
local sorting=false
c.table={};for k,v in pairs(table) do c.table[k]=v end
c.table.sort=function(rows,less)
    if rows[1] and type(rows[1])=='table' and rows[1].item then
        assert(#rows<=4096,'bounded native run');sorting=true
    end
    table.sort(rows,less)
end
local function UntilSort()
    local ticks=0
    while not sorting do
        local batch=pending;pending={};assert(#batch>0,'sort reached')
        for _,fn in ipairs(batch) do fn() end
        ticks=ticks+1;assert(ticks<1000,'sort reached promptly')
    end
end
W.Window.Show();W.Window.SetMode('advisor');Pump()
-- Hide mid-sort; queued callbacks must not restore released catalog/rows/results.
sorting=false;W.UI.Advisor.Invalidate();W.Window.Render();UntilSort()
W.Window.SetMode('overview');Pump()
assert(W.UI.Advisor.Stats().items==0 and #p.list.data==0 and p.result==nil,'no stale publication after hide')
-- Reopen and supersede a sorting generation with a different catalog.
sorting=false;W.Window.SetMode('advisor');UntilSort()
local items={[42]={},[43]={}}
W.Session.PriceSource=function() return {market={items=items,generation='replacement'}} end
W.Session.AllRecipes=function() return {} end
c.C_Container=nil
c.TwichUIDB.workshop.view.advisorTracked={}
W.UI.Advisor.Open(42);Pump()
assert(#p.list.data==2 and p.list.data[1].item==42 and p.list.data[2].item==43,'replacement only, sorted')
assert(p.result.item==42,'replacement selection')
-- Suspension closes the window; drive the child OnHide as the real frame tree does.
sorting=false
local many={};for id=1000,9999 do many[id]={} end
W.Session.PriceSource=function() return {market={items=many,generation='suspend'}} end
W.UI.Advisor.Invalidate();W.Window.Render();UntilSort()
W.Suspend();p:Hide();Pump()
assert(W.UI.Advisor.Stats().items==0 and #p.list.data==0 and p.result==nil,'suspension releases sorting generation')
print('advisor cooperative sort UI: OK')
