-- TwichUI: border textures
-- The border textures TwichUI's own frames can be drawn with, shared by the Food and Drink
-- buttons and the combo points so both offer the same list and draw it the same way:
--   "solid"     a plain line, drawn by the caller with its own textures;
--   "<name>"    any border LibSharedMedia has (any addon's), as a backdrop edge file;
--   "eui:<key>" one of EllesmereUI's own, drawn by its ApplyBorderStyle on a frame of ours so it
--               matches its bars. Listed and drawn only while EllesmereUI is installed; a saved
--               choice whose addon has gone falls back to the line and stays listed.
-- Nothing here is saved; each feature keeps its own choice.

local R = TwichUI
local B = {}
R.Borders = B

B.EUI_PREFIX = "eui:"

-- EllesmereUI's border API when it is installed and has what is used here, else nil. Optional:
-- everything works without it.
function B.Ellesmere()
    local e = EllesmereUI
    if type(e) == "table" and e.PP and e.ApplyBorderStyle and e.GetBorderTextureList and e.ResolveBorderTexture
        and e.BorderPxStep and e.BorderLegacyPx then
        return e
    end
end

-- The EllesmereUI key in a saved texture name ("eui:pixels-textured" -> "pixels-textured").
function B.EllesmereKey(name)
    local prefix = B.EUI_PREFIX
    if type(name) == "string" and name:sub(1, #prefix) == prefix then return name:sub(#prefix + 1) end
end

-- Whether a value can be a saved texture name.
function B.ValidName(value)
    return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]")
end

-- What choosing an EllesmereUI texture seeds: { size = px (nil if unknown), color = "ffRRGGBB" },
-- or nil for any other choice (or if EllesmereUI is absent). maxSize: the largest size allowed.
function B.Seed(name, maxSize)
    local key, e = B.EllesmereKey(name), B.Ellesmere()
    if not (key and e) then return nil end
    local step = e.GetBorderDefaultSize and e.GetBorderDefaultSize(nil, key) or 2
    local ok, px = pcall(e.BorderLegacyPx, step, key)
    local seed = { size = ok and type(px) == "number" and math.min(math.max(px, 1), maxSize) or nil }
    if e.GetBorderStyleSelectDefaults then
        local good, c = pcall(e.GetBorderStyleSelectDefaults, key)
        if good and type(c) == "table" and type(c.r) == "number" then
            seed.color = ("ff%02x%02x%02x"):format(c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5)
        end
    end
    return seed
end

-- Choosing another texture gives it a thickness and colour that suit it, unless the player has
-- set their own: a texture is drawn at a size of its own and unreadable at 1 px, a plain line is
-- wrong at 12; EllesmereUI says what colour its textures are meant to be tinted.
-- rules: { defaultSize, defaultColor, solidMax, texturedMin, texturedSeed, maxSize }.
-- Returns the size and colour to use with the new texture.
function B.Reseed(old, new, size, color, rules)
    if new == old then return size, color end
    local seed = B.Seed(new, rules.maxSize)
    if new == "solid" then
        if size > rules.solidMax then size = rules.defaultSize end
    elseif size < rules.texturedMin then
        size = seed and seed.size or rules.texturedSeed
    end
    local function SeedColor(name)
        local s = B.Seed(name, rules.maxSize)
        return s and s.color or rules.defaultColor
    end
    if color == SeedColor(old) then color = SeedColor(new) end
    return size, color
end

local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- The edge file of a LibSharedMedia border, or nil: "solid", an EllesmereUI name, and a name
-- LibSharedMedia no longer has (an addon that registered it is gone) all draw the line.
function B.TexturePath(name)
    if name == "solid" or B.EllesmereKey(name) then return nil end
    local LSM = SharedMedia()
    local path = LSM and LSM:Fetch("border", name, true)
    if type(path) == "string" and path ~= "" then return path end
end

-- { { value, label }, ... } for a texture choice: Solid, EllesmereUI's own textures (when it is
-- installed), then every LibSharedMedia border (any addon's, sorted by name, leaving out a name
-- EllesmereUI already lists). current stays listed, marked, if it has gone.
function B.Choices(current)
    local list, labelled = { { "solid", "Solid" } }, { solid = true }
    local e = B.Ellesmere()
    if e then
        local ok, entries = pcall(e.GetBorderTextureList)
        for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
            local key, name = entry.key, entry.name
            -- "sm:" ones are LibSharedMedia's, listed below; shadow is drawn behind its host
            -- by EllesmereUI itself, which a plain border can't do
            if type(key) == "string" and type(name) == "string" and key ~= "solid" and key ~= "shadow"
                and key:sub(1, 3) ~= "sm:" and e.ResolveBorderTexture(key) then
                list[#list + 1] = { B.EUI_PREFIX .. key, name }
                labelled[name] = true
            end
        end
    end
    local LSM = SharedMedia()
    local names = LSM and LSM:HashTable("border")
    local sorted = {}
    for name in pairs(names or {}) do
        if name ~= "None" and not labelled[name] and B.ValidName(name) then sorted[#sorted + 1] = name end
    end
    table.sort(sorted)
    for _, name in ipairs(sorted) do list[#list + 1] = { name, name } end
    local found = false
    for _, choice in ipairs(list) do if choice[1] == current then found = true end end
    if not found then list[#list + 1] = { current, (B.EllesmereKey(current) or current) .. " (not available)" } end
    return list
end

-- Draws a textured border round host, or says the caller should draw its plain line.
-- store: a table kept for this host (the frames made for it live there). name: the texture;
-- edge: its thickness in pixels (0 for none); outset: how far a LibSharedMedia edge reaches
-- out past host (EllesmereUI places its own). Returns "ellesmere", "texture" or "line".
function B.Draw(store, host, name, edge, r, g, b, a, outset)
    local mode, path = "line", nil
    local key, e = B.EllesmereKey(name), B.Ellesmere()
    local level = (host:GetFrameLevel() or 1) + 2
    if key and e and edge > 0 and e.ResolveBorderTexture(key) then
        mode = "ellesmere"
    else
        path = B.TexturePath(name)
        if path then mode = "texture" end
    end

    if mode == "ellesmere" then
        local frame = store.ellesmere
        if not frame then
            frame = CreateFrame("Frame", nil, host)
            frame:SetAllPoints(host)
            store.ellesmere = frame
        end
        frame:SetFrameLevel(level)
        frame:Show()
        -- ApplyBorderStyle(frame, step, r, g, b, a, texture, then its offset/shift/addon overrides, unused here, and the exact edge in pixels)
        local ok = pcall(e.ApplyBorderStyle, frame, e.BorderPxStep(edge, key), r, g, b, a, key,
            nil, nil, nil, nil, nil, nil, nil, edge)
        if not ok then mode = "line"; frame:Hide() end
    elseif store.ellesmere then
        store.ellesmere:Hide()
    end

    if mode == "texture" then
        local frame = store.texture
        if not frame then
            frame = CreateFrame("Frame", nil, host, "BackdropTemplate")
            store.texture = frame
        end
        outset = outset or 0
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", host, "TOPLEFT", -outset, outset)
        frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", outset, -outset)
        frame:SetFrameLevel(level)
        frame:SetBackdrop({ edgeFile = path, edgeSize = math.max(edge, 1) })
        frame:SetBackdropBorderColor(r, g, b, a)
        frame:SetShown(edge > 0)
    elseif store.texture then
        store.texture:Hide()
    end
    return mode
end

-- Hides whatever B.Draw made for a host.
function B.Hide(store)
    if store.ellesmere then store.ellesmere:Hide() end
    if store.texture then store.texture:Hide() end
end
