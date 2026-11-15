-- Consume the loaded client's localized hierarchy, never load or mutate native UI.
local W = TwichUI.Workshop
local C = {}
W.AuctionCategories = C
function C.Tree()
    local out = {}
    local function Copy(nodes, prefix, depth)
        local rows = {}
        for i, node in ipairs(nodes or {}) do
            if #rows >= 100 then break end
            local key = prefix .. i
            local r = {key=key, name=W.Text(node.name,200) or "Category unavailable", filters={},
                implicit=node.implicitFilter, depth=depth}
            for j, f in ipairs(node.filters or {}) do
                if j > 100 then break end
                r.filters[#r.filters+1]={classID=f.classID,subClassID=f.subClassID,inventoryType=f.inventoryType}
            end
            if depth < 3 then r.children=Copy(node.subCategories,key..".",depth+1) end
            out[key]=r; rows[#rows+1]=r
        end
        return rows
    end
    return Copy(AuctionCategories,"native:",0), out
end
function C.Matches(info, node)
    if node.implicit then return false end -- unavailable from saved item metadata
    local inventory,read=info.inventoryType,false
    for _,f in ipairs(node.filters) do
        if (not f.classID or f.classID==info.classID) and
            (not f.subClassID or f.subClassID==info.subClassID) then
            if not f.inventoryType then return true end
            if inventory==nil and not read then
                read=true
                if C_Item and C_Item.GetItemInventoryTypeByID then
                    inventory=W.Int(C_Item.GetItemInventoryTypeByID(info.item),0,100)
                end
            end
            if f.inventoryType==inventory then return true end
        end
    end
    return false
end
