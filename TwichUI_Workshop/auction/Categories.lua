-- Consume the loaded client's localized hierarchy, never load or mutate native UI.
local W = TwichUI.Workshop
local C = {}
W.AuctionCategories = C
local CLASS_ART={[0]="npc:bread-and-tankard",[1]="npc:leather-backpack",[2]="npc:sword-and-shield",[3]="classResources",
    [4]="npc:tabard",[5]="npc:reagent-pouch",[6]="npc:arrow-and-cartridge",[7]="npc:cloth-bolts",[8]="npc:inscribed-stone",
    [9]="npc:sealed-scroll",[11]="npc:arrow-and-cartridge",[12]="npc:sealed-scroll",[15]="npc:balance-scales",
    [16]="npc:inscribed-stone",[17]="npc:paw",[19]="npc:hammer-and-chisel"}
local SAVED_ART={all="auctionHouse",trade="npc:cloth-bolts",consumable="npc:bread-and-tankard",equipment="npc:sword-and-shield",recipe="npc:sealed-scroll",misc="npc:balance-scales"}
-- BEGIN GENERATED SUBCATEGORY ART (tools/make_auction_category_art.py)
local SUBCATEGORY_ART = {
    ["2:0"] = "weapon-one-hand-axe",
    ["2:1"] = "weapon-two-hand-axe",
    ["2:2"] = "weapon-bow",
    ["2:3"] = "weapon-gun",
    ["2:4"] = "weapon-one-hand-mace",
    ["2:5"] = "weapon-two-hand-mace",
    ["2:6"] = "weapon-polearm",
    ["2:7"] = "weapon-one-hand-sword",
    ["2:8"] = "weapon-two-hand-sword",
    ["2:10"] = "weapon-staff",
    ["2:13"] = "weapon-fist-weapon",
    ["2:14"] = "weapon-other-weapon",
    ["2:15"] = "weapon-dagger",
    ["2:16"] = "weapon-thrown",
    ["2:18"] = "weapon-crossbow",
    ["2:19"] = "weapon-wand",
    ["2:20"] = "weapon-fishing-pole",
    ["4:1"] = "armor-cloth",
    ["4:1:1"] = "cloth-head",
    ["4:1:3"] = "cloth-shoulders",
    ["4:1:5"] = "cloth-chest",
    ["4:1:6"] = "cloth-waist",
    ["4:1:7"] = "cloth-legs",
    ["4:1:8"] = "cloth-feet",
    ["4:1:9"] = "cloth-wrists",
    ["4:1:10"] = "cloth-hands",
    ["4:1:28"] = "cloth-relic",
    ["4:2"] = "armor-leather",
    ["4:2:1"] = "leather-head",
    ["4:2:3"] = "leather-shoulders",
    ["4:2:5"] = "leather-chest",
    ["4:2:6"] = "leather-waist",
    ["4:2:7"] = "leather-legs",
    ["4:2:8"] = "leather-feet",
    ["4:2:9"] = "leather-wrists",
    ["4:2:10"] = "leather-hands",
    ["4:2:28"] = "leather-relic",
    ["4:3"] = "armor-mail",
    ["4:3:1"] = "mail-head",
    ["4:3:3"] = "mail-shoulders",
    ["4:3:5"] = "mail-chest",
    ["4:3:6"] = "mail-waist",
    ["4:3:7"] = "mail-legs",
    ["4:3:8"] = "mail-feet",
    ["4:3:9"] = "mail-wrists",
    ["4:3:10"] = "mail-hands",
    ["4:3:28"] = "mail-relic",
    ["4:4"] = "armor-plate",
    ["4:4:1"] = "plate-head",
    ["4:4:3"] = "plate-shoulders",
    ["4:4:5"] = "plate-chest",
    ["4:4:6"] = "plate-waist",
    ["4:4:7"] = "plate-legs",
    ["4:4:8"] = "plate-feet",
    ["4:4:9"] = "plate-wrists",
    ["4:4:10"] = "plate-hands",
    ["4:4:28"] = "plate-relic",
    ["4:0"] = "armor-misc",
    ["4:0:2"] = "armor-neck",
    ["4:1:16"] = "armor-cloak",
    ["4:0:11"] = "armor-ring",
    ["4:0:12"] = "armor-trinket",
    ["4:0:23"] = "armor-held",
    ["4:0:4"] = "armor-shirt",
    ["4:6"] = "armor-shield",
    ["4:7"] = "armor-libram",
    ["4:8"] = "armor-idol",
    ["4:9"] = "armor-totem",
    ["1:0"] = "container-bag",
    ["1:1"] = "container-soul",
    ["1:2"] = "container-herb",
    ["1:3"] = "container-enchanting",
    ["1:4"] = "container-engineering",
    ["1:6"] = "container-mining",
    ["1:7"] = "container-leatherworking",
    ["1:9"] = "container-fishing",
    ["1:10"] = "container-cooking",
    ["1:11"] = "container-reagent",
    ["11:2"] = "container-quiver",
    ["11:3"] = "container-ammo-pouch",
    ["0:0"] = "consumable-generic",
    ["0:1"] = "consumable-potion",
    ["0:2"] = "consumable-elixir",
    ["0:3"] = "consumable-flask",
    ["0:4"] = "consumable-scroll",
    ["0:5"] = "consumable-food-drink",
    ["0:6"] = "consumable-enhancement",
    ["0:7"] = "consumable-bandage",
    ["0:8"] = "consumable-other",
    ["0:15"] = "consumable-temporary-enhancement",
    ["7:0"] = "trade-general",
    ["7:1"] = "trade-parts",
    ["7:2"] = "trade-explosives",
    ["7:3"] = "trade-devices",
    ["7:4"] = "trade-jewelcrafting",
    ["7:5"] = "trade-cloth",
    ["7:6"] = "trade-leather",
    ["7:7"] = "trade-metal-stone",
    ["7:8"] = "trade-cooking",
    ["7:9"] = "trade-herbs",
    ["7:10"] = "trade-elemental",
    ["7:11"] = "trade-other",
    ["7:12"] = "trade-enchanting",
    ["7:13"] = "trade-materials",
    ["7:14"] = "trade-armor-enchantment",
    ["7:15"] = "trade-weapon-enchantment",
    ["7:16"] = "trade-inscription",
    ["9:0"] = "recipe-book",
    ["9:1"] = "recipe-leatherworking",
    ["9:2"] = "recipe-tailoring",
    ["9:3"] = "recipe-engineering",
    ["9:4"] = "recipe-blacksmithing",
    ["9:5"] = "recipe-cooking",
    ["9:6"] = "recipe-alchemy",
    ["9:7"] = "recipe-first-aid",
    ["9:8"] = "recipe-enchanting",
    ["9:9"] = "recipe-fishing",
    ["9:10"] = "recipe-jewelcrafting",
    ["9:11"] = "recipe-inscription",
    ["6:2"] = "projectile-arrows",
    ["6:3"] = "projectile-bullets",
    ["15:0"] = "misc-junk",
    ["15:1"] = "misc-reagents",
    ["15:2"] = "misc-pets",
    ["15:3"] = "misc-holiday",
    ["15:4"] = "misc-other",
    ["15:5"] = "misc-mounts",
    ["15:6"] = "misc-mount-equipment",
    ["0:9"] = "consumable-rune",
    ["0:10"] = "consumable-utility-curio",
    ["0:11"] = "consumable-combat-curio",
    ["0:12"] = "consumable-relic",
    ["0:13"] = "consumable-draught",
    ["0:14"] = "consumable-device",
}
local GROUP_ART = {
    ["2:0,2:13,2:15,2:19,2:4,2:7"] = "group-one-handed",
    ["2:1,2:10,2:5,2:6,2:8"] = "group-two-handed",
    ["2:16,2:18,2:2,2:3"] = "group-ranged",
    ["2:14,2:20"] = "group-misc-weapons",
    ["4:7,4:8,4:9"] = "group-relics",
    ["1:0,1:1"] = "group-standard-bags",
    ["11:2,11:3"] = "group-ammo-bags",
    ["1:10,1:11,1:2,1:3,1:4,1:6,1:7,1:9"] = "group-reagent-bags",
    ["0:15,0:6"] = "group-enhancements",
    ["4:0,4:1,4:6"] = "armor-misc",
}
-- END GENERATED SUBCATEGORY ART

-- Match stable filter facts, not translated labels or the native tree's ordering.
local function SubcategoryArt(node)
    local common, slot, kinds, seen = nil, nil, {}, {}
    for _, f in ipairs(node.filters or {}) do
        if f.classID == nil or f.subClassID == nil then return end
        local key = f.classID .. ":" .. f.subClassID
        local inv = f.inventoryType == 20 and 5 or f.inventoryType -- robes share Chest
        local full = key .. ":" .. (inv or "*")
        if common == nil then common = key elseif common ~= key then common = false end
        if slot == nil then slot = full elseif slot ~= full then slot = false end
        if not seen[key] then kinds[#kinds + 1] = key; seen[key] = true end
    end
    local art = slot and SUBCATEGORY_ART[slot] or common and SUBCATEGORY_ART[common]
    if not art then table.sort(kinds); art = GROUP_ART[table.concat(kinds, ",")] end
    if art then return "auction:" .. art end
end

function C.Art(node)
    if SAVED_ART[node.key] then return SAVED_ART[node.key] end
    if (node.depth or 0) > 0 then
        local art = SubcategoryArt(node)
        if art then return art end
    end
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
