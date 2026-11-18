-- Consume the loaded client's localized hierarchy, never load or mutate native UI.
local W = TwichUI.Workshop
local C = {}
W.AuctionCategories = C
local CLASS_ART={[0]="npc:bread-and-tankard",[1]="npc:leather-backpack",[2]="npc:sword-and-shield",[3]="classResources",
    [4]="npc:tabard",[5]="npc:reagent-pouch",[6]="npc:arrow-and-cartridge",[7]="npc:cloth-bolts",[8]="npc:inscribed-stone",
    [9]="npc:sealed-scroll",[11]="npc:arrow-and-cartridge",[12]="npc:sealed-scroll",[15]="npc:balance-scales",
    [16]="npc:inscribed-stone",[17]="npc:paw",[19]="npc:hammer-and-chisel"}
local SAVED_ART={all="auctionHouse",trade="npc:cloth-bolts",consumable="npc:bread-and-tankard",equipment="npc:sword-and-shield",recipe="npc:sealed-scroll",misc="npc:balance-scales"}
function C.Art(node)
    if SAVED_ART[node.key] then return SAVED_ART[node.key] end
    local function Find(n,depth)
        for _,filter in ipairs(n.filters or {}) do
            if filter.classID==2 and (filter.subClassID==2 or filter.subClassID==3 or filter.subClassID==18) then return "npc:arrow-and-cartridge" end
            if CLASS_ART[filter.classID] then return CLASS_ART[filter.classID] end
        end
        if depth<4 then for _,child in ipairs(n.children or {}) do local art=Find(child,depth+1);if art then return art end end end
    end
    return Find(node,0) or "npc:balance-scales"
end
function C.Tree()
    local out = {}
    local function Copy(nodes, prefix, depth)
        local rows = {}
        for i, node in ipairs(nodes or {}) do
            if #rows >= 100 then break end
            local token=node.flags and node.flags.WOW_TOKEN_FLAG or (TOKEN_FILTER_LABEL and node.name==TOKEN_FILTER_LABEL)
            for _,filter in ipairs(node.filters or {}) do
                if ITEM_CLASS_WOW_TOKEN and filter.classID==ITEM_CLASS_WOW_TOKEN then token=true end
            end
            if not token then
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
