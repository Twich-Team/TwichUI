-- Stable Forever item families shared by Magic Inventory and Loot Rolls.
-- Callers supply a validated, plain numeric item ID.
local Families = {}
TwichUI.ForeverItemFamilies = Families

-- Forever 1.60.1 item data. The two identified-crate ranges exclude 248700 and 248701.
-- https://eternadex.com/en/versorgungsgueter/ and https://forevercraft.ru/database/items/misc/junk/3/
function Families.IsWaylaidCrate(id)
    return id == 248549                           -- unidentified
        or (id >= 248682 and id <= 248699)        -- herbs, ore, textiles and curiosities
        or (id >= 248702 and id <= 248713)        -- fabrics, ingots and parts
        or (id >= 248765 and id <= 248779)        -- sealed turn-ins, all ranks and qualities
end

-- Forever writs from the live client catalog, including the generic and ranked sealed envelopes.
-- https://aidvir.github.io/wow-forever-favor/writs.html and https://daybreakforever.com/discoveries/items
function Families.IsCraftsmansWrit(id)
    return id == 248206
        or (id >= 262887 and id <= 262890)
        or (id >= 264011 and id <= 264160)
end
