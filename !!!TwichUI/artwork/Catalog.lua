-- TwichUI: curated artwork catalog. Pure metadata, references and drawing; no feature state or frames.
-- Art/ArtTexture/ART and Entries/Reset also support the existing Reminders compatibility wrappers.
local R = TwichUI
local A = {}
R.Artwork = A

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- Copy only bounded scalar identity. Unknown well-formed IDs are deliberately retained.
function A.Check(ref)
    if type(ref) ~= "table" or getmetatable(ref) ~= nil then return nil, "invalid_ref" end
    for k, v in pairs(ref) do
        local kt, vt = type(k), type(v)
        if (kt ~= "string" and kt ~= "number") or (vt ~= "string" and vt ~= "number" and vt ~= "boolean") then
            return nil, "invalid_ref"
        end
    end
    local kind, id = ref.kind, ref.id
    if kind == "automatic" then
        if id ~= nil then return nil, "invalid_ref" end
        return { kind = kind }
    elseif kind == "art" then
        if type(id) ~= "string" or #id < 1 or #id > 40 or not id:match("^[a-z0-9-]+$") then return nil, "invalid_ref" end
    elseif kind == "icon" then
        if type(id) ~= "string" or #id < 1 or #id > 64 or not id:match("^[A-Za-z0-9_-]+$") then return nil, "invalid_ref" end
    elseif kind == "item" then
        if not Finite(id) or id % 1 ~= 0 or id < 1 or id > 2147483647 then return nil, "invalid_ref" end
    else
        return nil, "invalid_ref"
    end
    return { kind = kind, id = id }
end

-- Approved UX02 first slice: hand-maintained mappings to existing bundled files.
-- Provenance: docs/design/shared-artwork-inventory.md; generated ArtData stays unchanged.
-- kind, stable target, name, category, description, keywords, optional art path under media/.
local ADDITIONS = {
    { "art", "art-herbs", "Herbs", "Supplies", "A bundle of herbs: plants and alchemy reagents.", "herb plant reagent alchemy materials", [[icons\magic-herbs]] },
    { "art", "art-leather", "Leather", "Supplies", "Rolled leather: hides and crafting materials.", "leather hide skin material leatherworking", [[icons\magic-leather]] },
    { "art", "art-parts", "Engineering parts", "Supplies", "A cog and components: engineering supplies.", "engineering parts cog components crafting supplies", [[icons\magic-parts]] },
    { "art", "art-elemental", "Elemental material", "Supplies", "A blue elemental spiral: magical materials.", "elemental essence material reagent blue spiral", [[icons\magic-elemental]] },
    { "art", "art-shipping-crate", "Shipping crate", "Supplies", "A wooden crate: cargo and stored supplies.", "crate cargo container supplies shipping waylaid", [[icons\magic-waylaid-crate]] },
    { "art", "art-cloth", "Cloth bolts", "Supplies", "Folded bolts of cloth: tailoring materials.", "cloth bolts fabric tailoring material", [[npcs\cloth-bolts]] },
    { "art", "art-tabard", "Tabard", "Equipment", "A tabard: guild colors and equipment.", "tabard guild shirt equipment colors", [[npcs\tabard]] },
    { "art", "art-paw", "Paw", "Adventure", "An animal paw: pets and companions.", "pet companion animal paw beast", [[npcs\paw]] },
    { "icon", "auctionHouse", "Merchant scales", "General", "Merchant scales: auctions and trade.", "auction trade sell balance merchant scales commerce" },
    { "icon", "vendors", "Market stall", "General", "A market stall: vendors and trading.", "vendor market stall trade merchant shop" },
    { "icon", "appearance", "Palette and brush", "General", "A painter's palette and brush: customization and craft.", "palette brush paint appearance customization crafting" },
    { "icon", "navigation", "Compass", "Adventure", "A compass: navigation and travel.", "compass navigation direction travel journey" },
    { "icon", "mapPins", "Map pin", "Adventure", "A map pin with a ripple: a chosen location.", "map pin marker location destination ripple" },
    { "icon", "markers", "Pennant", "Adventure", "A pennant: a place or a rally point.", "pennant flag marker rally location banner" },
    { "icon", "summons", "Portal", "Adventure", "A portal: travel and summoning.", "portal summon summoning travel magic" },
    { "icon", "resurrection", "Resurrection", "Character", "A winged ankh: resurrection and recovery.", "resurrection revive ankh wings recovery life" },
    { "art", "art-dice", "Dice", "General", "A pair of dice: chance and random rolls.", "dice random chance roll luck", [[loot\dice]] },
    { "art", "art-crown", "Crown", "General", "A crown: leadership and victory.", "crown king queen winner leadership victory", [[loot\crown]] },
    { "icon", "lootGreed", "Coins", "Supplies", "A stack of coins: money and trade.", "coins money gold silver currency greed trade" },
    { "icon", "lootQuality", "Green gem", "Supplies", "A green gem: a crystal or a precious material.", "green gem crystal jewel material quality" },
}

local ART_PATH = R.PATH .. [[media\reminders\]]
A.ART = {
    shield = { label = "Shield", size = 256, width = 182, height = 256, smallSize = 64, smallWidth = 46, smallHeight = 64 },
    ammo = { label = "Arrows", size = 256, width = 217, height = 256, smallSize = 64, smallWidth = 54, smallHeight = 64 },
    wellfed = { label = "Plate and cutlery", size = 256, width = 256, height = 186, smallSize = 64, smallWidth = 64, smallHeight = 47 },
    enchant = { label = "Weapon oil", size = 256, width = 129, height = 256, smallSize = 64, smallWidth = 33, smallHeight = 64 },
}
local GALLERY_PATH = R.PATH .. [[media\reminders\gallery\]]
local DATA = R.ReminderArtData
if DATA then
    for _, e in ipairs(DATA.gallery) do
        A.ART[e[1]] = { label = e[2], dir = GALLERY_PATH, size = DATA.large, width = DATA.large, height = DATA.large,
            smallSize = DATA.small, smallWidth = DATA.small, smallHeight = DATA.small }
    end
end

-- New standalone art uses its whole existing canvas and the 26-unit small threshold.
for _, e in ipairs(ADDITIONS) do
    if e[1] == "art" then
        local file = R.PATH .. [[media\]] .. e[7]
        A.ART[e[2]] = { label = e[3], file = file, small = file .. "-small", smallAt = 26,
            size = 64, width = 64, height = 64, smallSize = 32, smallWidth = 32, smallHeight = 32 }
    end
end

function A.Art(id) return type(id) == "string" and A.ART[id] or nil end

-- Preserve the shipped one-pixel crop, aspect and <=64 small-file threshold.
function A.ArtTexture(id, drawn)
    local a = A.Art(id)
    if not a then return nil end
    local small = drawn and drawn <= (a.smallAt or 64)
    local file = (a.dir or ART_PATH) .. id
    if a.file then
        return small and a.small or a.file, 0, 1, 0, 1, 1
    end
    local side, w, h = a.size, a.width, a.height
    if small then side, w, h, file = a.smallSize, a.smallWidth, a.smallHeight, file .. "-small" end
    return file, 1 / side, (w - 1) / side, 1 / side, (h - 1) / side, (a.width - 2) / (a.height - 2)
end

local list, byRef, categories
local function Build()
    list, byRef, categories = {}, {}, { "All" }
    local data = R.ReminderArtData
    if not data then return end
    for _, c in ipairs(data.categories) do categories[#categories + 1] = c end
    local function Add(kind, id, name, category, description, keywords, related, legacy)
        local key = kind == "art" and id or "icon-" .. id
        local entry = { key = key, ref = { kind = kind, id = id }, name = name, category = category,
            description = description, keywords = keywords, related = related or {},
            id = key, kind = kind, target = id, legacy = legacy,
            nameLower = name:lower(), haystack = (name .. " " .. category .. " " .. (keywords or "")):lower(), rank = #list + 1 }
        list[#list + 1] = entry
        byRef[kind .. ":" .. id] = entry
    end
    for _, c in ipairs(data.categories) do
        for _, e in ipairs(data.legacy) do
            local kind, id = e[1], e[2]
            local usable = kind == "art" and A.Art(id) or (kind == "icon" and R.Icons and R.Icons.Get(id))
            if e[4] == c and usable then Add(kind, id, e[3], c, e[5], e[6], nil, true) end
        end
        for _, e in ipairs(data.gallery) do
            if e[3] == c and A.Art(e[1]) then Add("art", e[1], e[2], c, e[4], e[5], e[6]) end
        end
        -- Additive choices follow all shipped entries in their existing category.
        for _, e in ipairs(ADDITIONS) do
            local usable = e[1] == "art" and A.Art(e[2]) or (e[1] == "icon" and R.Icons and R.Icons.Get(e[2]))
            if e[4] == c and usable then Add(e[1], e[2], e[3], c, e[5], e[6]) end
        end
    end
end
local function Ensure() if not list then Build() end end

-- Returned snapshots share no mutable references with the catalog or other callers.
local function Copy(entry)
    if not entry then return nil end
    local out = {}
    for k, v in pairs(entry) do out[k] = v end
    out.ref = { kind = entry.kind, id = entry.target }
    out.related = {}
    for i, id in ipairs(entry.related) do out.related[i] = id end
    return out
end
function A.Reset() list, byRef, categories = nil, nil, nil end
function A.Categories()
    Ensure()
    local out = {}
    for i, c in ipairs(categories) do out[i] = c end
    return out
end
function A.Get(ref)
    local checked = A.Check(ref)
    if not checked or (checked.kind ~= "art" and checked.kind ~= "icon") then return nil end
    Ensure()
    return Copy(byRef[checked.kind .. ":" .. checked.id])
end
function A.Search(query, category)
    Ensure()
    local words = {}
    for w in (type(query) == "string" and query or ""):lower():gmatch("%S+") do
        if #words < 8 then words[#words + 1] = w end
    end
    local out = {}
    for _, e in ipairs(list) do
        if not category or category == "All" or e.category == category then
            local score = 0
            for _, w in ipairs(words) do
                if not e.haystack:find(w, 1, true) then score = nil; break end
                if not e.nameLower:find(w, 1, true) then score = 1 end
            end
            if score then out[#out + 1] = { e, score } end
        end
    end
    if #words > 0 then
        table.sort(out, function(a, b)
            if a[2] ~= b[2] then return a[2] < b[2] end
            return a[1].rank < b[1].rank
        end)
    end
    local result = {}
    for i, pair in ipairs(out) do result[i] = Copy(pair[1]) end
    return result
end
function A.Entries() return A.Search("") end

local function Plain(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
function A.Draw(texture, ref, size)
    local function Fail(reason) texture:SetTexture(nil); return false, reason end
    if not Finite(size) or size <= 0 then return Fail("invalid_size") end
    local checked = A.Check(ref)
    if not checked then return Fail("invalid_ref") end
    if checked.kind == "automatic" then return Fail("automatic") end
    if checked.kind ~= "item" and not A.Get(checked) then return Fail("unavailable") end
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetAlpha(1)
    if checked.kind == "art" then
        local file, l, r, t, b, aspect = A.ArtTexture(checked.id, size)
        if not file or texture:SetTexture(file) == false then return Fail("unavailable") end
        texture:SetTexCoord(l, r, t, b)
        texture:SetSize(size * math.min(1, aspect), size / math.max(1, aspect))
    elseif checked.kind == "icon" then
        if not R.Icons or not R.Icons.Get(checked.id) then return Fail("unavailable") end
        texture:SetSize(size, size)
        if R.Icons.Apply(texture, checked.id, size) == "fallback" then return Fail("unavailable") end
    else
        local icon = C_Item and C_Item.GetItemIconByID and Plain(C_Item.GetItemIconByID(checked.id))
        if not icon then return Fail("loading") end
        if texture:SetTexture(icon) == false then return Fail("unavailable") end
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        texture:SetSize(size, size)
    end
    return true, "ready"
end
