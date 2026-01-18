--[[
        Reference: Colors
        Provides an in-game palette reference for UI design.
]]
local _G = _G
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

local AceGUI = (T and T.Libs and T.Libs.AceGUI)
    or (_G.LibStub and _G.LibStub("AceGUI-3.0", true))

local function NotifyElvUIOptionsChanged()
    local ACR = (T.Libs and T.Libs.AceConfigRegistry)
        or (_G.LibStub and (_G.LibStub("AceConfigRegistry-3.0-ElvUI", true) or _G.LibStub("AceConfigRegistry-3.0", true)))

    if ACR and ACR.NotifyChange then
        pcall(ACR.NotifyChange, ACR, "ElvUI")
    end
end

local function Clamp01(v)
    if type(v) ~= "number" then
        return 1
    end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function ToHexByte(v)
    v = Clamp01(v)
    local n = math.floor(v * 255 + 0.5)
    return string.format("%02X", n)
end

local function ColorToHex(r, g, b, a)
    return ToHexByte(a or 1) .. ToHexByte(r or 1) .. ToHexByte(g or 1) .. ToHexByte(b or 1)
end

local function EnsureColorEntry(entry, fallbackId)
    if type(entry) ~= "table" then
        entry = {}
    end

    if type(entry.id) ~= "number" then
        entry.id = fallbackId
    end
    entry.r = Clamp01(entry.r)
    entry.g = Clamp01(entry.g)
    entry.b = Clamp01(entry.b)
    entry.a = Clamp01(entry.a)
    if type(entry.name) ~= "string" then entry.name = "" end
    if type(entry.description) ~= "string" then entry.description = "" end
    return entry
end

local function EnsurePaletteEntry(palette, fallbackId)
    if type(palette) ~= "table" then
        palette = {}
    end
    if type(palette.id) ~= "number" then
        palette.id = fallbackId
    end
    if type(palette.name) ~= "string" or palette.name == "" then
        palette.name = "Palette " .. tostring(palette.id)
    end
    if type(palette.colors) ~= "table" then
        palette.colors = {}
    end
    if type(palette.nextColorId) ~= "number" then
        palette.nextColorId = 1
    end

    local maxId = 0
    for i, entry in ipairs(palette.colors) do
        local id = tonumber(entry and entry.id) or nil
        if type(id) ~= "number" then
            id = palette.nextColorId
            palette.nextColorId = palette.nextColorId + 1
        end
        palette.colors[i] = EnsureColorEntry(entry, id)
        if id > maxId then
            maxId = id
        end
    end

    if palette.nextColorId <= maxId then
        palette.nextColorId = maxId + 1
    end

    return palette
end

--- Ensures the profile DB tables needed for reference palettes exist.
--- @return table refTable
local function EnsureReferenceDB()
    local profile = CM:GetProfileDB()
    if type(profile) ~= "table" then
        return {}
    end

    profile.reference = profile.reference or {}
    local ref = profile.reference

    ref.palettes = ref.palettes or {}
    ref.nextPaletteId = ref.nextPaletteId or 1
    ref.selectedPaletteId = ref.selectedPaletteId or nil
    ref.ui = ref.ui or { newPaletteName = "" }

    -- Migration: older versions stored a single palette under ref.colors.
    if type(ref.colors) == "table" and #ref.colors > 0 then
        local migratedId = ref.nextPaletteId
        ref.nextPaletteId = migratedId + 1
        local palette = {
            id = migratedId,
            name = "Default",
            colors = ref.colors,
            nextColorId = ref.nextColorId or 1,
        }
        table.insert(ref.palettes, palette)
        ref.selectedPaletteId = migratedId
        ref.colors = nil
        ref.nextColorId = nil
    end

    -- Ensure at least one palette exists.
    if type(ref.palettes) ~= "table" then
        ref.palettes = {}
    end
    if #ref.palettes == 0 then
        local id = ref.nextPaletteId
        ref.nextPaletteId = id + 1
        table.insert(ref.palettes, { id = id, name = "Default", colors = {}, nextColorId = 1 })
        ref.selectedPaletteId = id
    end

    -- Sanitize palettes and selection.
    local selectedExists = false
    local maxPaletteId = 0
    for i, palette in ipairs(ref.palettes) do
        local id = tonumber(palette and palette.id) or nil
        if type(id) ~= "number" then
            id = ref.nextPaletteId
            ref.nextPaletteId = ref.nextPaletteId + 1
        end
        ref.palettes[i] = EnsurePaletteEntry(palette, id)
        if id > maxPaletteId then
            maxPaletteId = id
        end
        if ref.selectedPaletteId and id == ref.selectedPaletteId then
            selectedExists = true
        end
    end
    if ref.nextPaletteId <= maxPaletteId then
        ref.nextPaletteId = maxPaletteId + 1
    end
    if not ref.selectedPaletteId or not selectedExists then
        ref.selectedPaletteId = ref.palettes[1] and ref.palettes[1].id or nil
    end

    return ref
end

local function GetSelectedPalette()
    local ref = EnsureReferenceDB()
    if type(ref.palettes) ~= "table" then
        return nil, nil
    end

    local selectedId = ref.selectedPaletteId
    if type(selectedId) == "number" then
        for idx, palette in ipairs(ref.palettes) do
            if type(palette) == "table" and palette.id == selectedId then
                return palette, idx
            end
        end
    end

    return ref.palettes[1], 1
end

local function RemoveColorFromPaletteById(palette, id)
    if type(palette) ~= "table" or type(palette.colors) ~= "table" then
        return
    end

    for i = #palette.colors, 1, -1 do
        local entry = palette.colors[i]
        if type(entry) == "table" and tostring(entry.id) == tostring(id) then
            table.remove(palette.colors, i)
            return
        end
    end
end

local function BuildPaletteValues()
    local ref = EnsureReferenceDB()
    local values = {}
    if type(ref.palettes) ~= "table" then
        return values
    end
    for _, palette in ipairs(ref.palettes) do
        if type(palette) == "table" and type(palette.id) == "number" then
            values[palette.id] = palette.name or ("Palette " .. tostring(palette.id))
        end
    end
    return values
end

local function AddPalette(name)
    local ref = EnsureReferenceDB()
    if type(ref.palettes) ~= "table" then
        return
    end

    if type(name) ~= "string" then
        name = ""
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = "New Palette"
    end

    local id = ref.nextPaletteId or 1
    ref.nextPaletteId = id + 1
    table.insert(ref.palettes, { id = id, name = name, colors = {}, nextColorId = 1 })
    ref.selectedPaletteId = id
end

local function DeleteSelectedPalette()
    local ref = EnsureReferenceDB()
    local _, selectedIndex = GetSelectedPalette()
    if not selectedIndex or type(ref.palettes) ~= "table" or #ref.palettes <= 1 then
        return
    end
    table.remove(ref.palettes, selectedIndex)
    ref.selectedPaletteId = ref.palettes[1] and ref.palettes[1].id or nil
end

local function ShowAddColorPopup(onAccept)
    if not AceGUI or type(AceGUI.Create) ~= "function" then
        return
    end

    local nameValue = ""
    local descValue = ""
    local r, g, b, a = 1, 1, 1, 1

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Add Color")
    frame:SetStatusText("")
    frame:SetLayout("List")
    frame:SetWidth(420)
    frame:SetHeight(320)
    frame:EnableResize(false)
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Name")
    nameBox:SetText(nameValue)
    nameBox:SetFullWidth(true)
    nameBox:SetCallback("OnEnterPressed", function(_, _, text)
        nameValue = text or ""
    end)
    nameBox:SetCallback("OnTextChanged", function(_, _, text)
        nameValue = text or ""
    end)
    frame:AddChild(nameBox)

    local descBox = AceGUI:Create("MultiLineEditBox")
    descBox:SetLabel("Description")
    descBox:SetText(descValue)
    descBox:SetNumLines(4)
    descBox:SetFullWidth(true)
    descBox:SetCallback("OnTextChanged", function(_, _, text)
        descValue = text or ""
    end)
    frame:AddChild(descBox)

    local preview = AceGUI:Create("Label")
    preview:SetFullWidth(true)
    preview:SetText("Preview: |c" .. ColorToHex(r, g, b, a) .. "■■■■■■|r")
    frame:AddChild(preview)

    local pick = AceGUI:Create("Button")
    pick:SetText("Pick Color")
    pick:SetFullWidth(true)
    pick:SetCallback("OnClick", function()
        local cpf = _G.ColorPickerFrame
        if not cpf then
            return
        end

        local previousR, previousG, previousB, previousA = r, g, b, a

        local function applyColor()
            local pr, pg, pb = 1, 1, 1
            if cpf.GetColorRGB then
                pr, pg, pb = cpf:GetColorRGB()
            end

            local pa = 1
            if cpf.GetColorAlpha then
                pa = cpf:GetColorAlpha()
            elseif _G.OpacitySliderFrame and _G.OpacitySliderFrame.GetValue then
                pa = 1 - (_G.OpacitySliderFrame:GetValue() or 0)
            end
            r, g, b, a = Clamp01(pr), Clamp01(pg), Clamp01(pb), Clamp01(pa)
            preview:SetText("Preview: |c" .. ColorToHex(r, g, b, a) .. "■■■■■■|r")
        end

        local function cancelColor(prev)
            -- New API may pass previousValues; fall back to our captured values.
            if type(prev) == "table" then
                local pr = prev.r or previousR
                local pg = prev.g or previousG
                local pb = prev.b or previousB
                local pa = previousA
                if prev.opacity ~= nil then
                    pa = 1 - Clamp01(prev.opacity)
                elseif prev.a ~= nil then
                    pa = Clamp01(prev.a)
                end
                r, g, b, a = Clamp01(pr), Clamp01(pg), Clamp01(pb), Clamp01(pa)
            else
                r, g, b, a = previousR, previousG, previousB, previousA
            end
            preview:SetText("Preview: |c" .. ColorToHex(r, g, b, a) .. "■■■■■■|r")
        end

        -- Prefer modern API when available (Retail).
        if cpf.SetupColorPickerAndShow then
            cpf:SetupColorPickerAndShow({
                r = Clamp01(r),
                g = Clamp01(g),
                b = Clamp01(b),
                hasOpacity = true,
                opacity = 1 - Clamp01(a),
                swatchFunc = applyColor,
                opacityFunc = applyColor,
                cancelFunc = cancelColor,
            })
            return
        end

        -- Legacy fallback.
        cpf.func = applyColor
        cpf.opacityFunc = applyColor
        cpf.cancelFunc = cancelColor
        cpf.hasOpacity = true
        cpf.opacity = 1 - Clamp01(a)
        if cpf.SetColorRGB then
            cpf:SetColorRGB(r, g, b)
        end
        if cpf.Show then
            cpf:Show()
        end
    end)
    frame:AddChild(pick)

    local actions = AceGUI:Create("SimpleGroup")
    actions:SetFullWidth(true)
    actions:SetLayout("Flow")

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add")
    addBtn:SetWidth(120)
    addBtn:SetCallback("OnClick", function()
        if type(onAccept) == "function" then
            onAccept({
                name = nameValue,
                description = descValue,
                r = r,
                g = g,
                b = b,
                a = a,
            })
        end
        pcall(AceGUI.Release, AceGUI, frame)
    end)
    actions:AddChild(addBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(120)
    cancelBtn:SetCallback("OnClick", function()
        pcall(AceGUI.Release, AceGUI, frame)
    end)
    actions:AddChild(cancelBtn)

    frame:AddChild(actions)
end

local referenceColorsOptions = nil

local function BuildColorTableArgs()
    local args = {}

    local palette = GetSelectedPalette()
    local colors = (palette and palette.colors) or {}

    if type(colors) ~= "table" or #colors == 0 then
        args.empty = {
            type = "description",
            order = 1,
            name = "No colors yet. Use 'Add Color' to create a palette entry.",
        }
        return args
    end

    args.header = {
        type = "group",
        inline = true,
        name = "",
        order = 1,
        args = {
            swatch = { type = "description", name = "Color", order = 1, width = 0.6 },
            name = { type = "description", name = "Name", order = 2, width = 1.0 },
            desc = { type = "description", name = "Description", order = 3, width = 2.0 },
            action = { type = "description", name = "", order = 4, width = 0.6 },
        },
    }

    local order = 2
    for index, entry in ipairs(colors) do
        if type(entry) == "table" then
            local id = tonumber(entry.id) or index
            local key = "color_" .. tostring(id)

            args[key] = {
                type = "group",
                inline = true,
                name = "",
                order = order,
                args = {
                    swatch = {
                        type = "color",
                        name = "",
                        order = 1,
                        width = 0.6,
                        hasAlpha = true,
                        get = function()
                            local pal = GetSelectedPalette()
                            local c = pal and pal.colors and pal.colors[index]
                            if not c then
                                return 1, 1, 1, 1
                            end
                            return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                        end,
                        set = function(_, r, g, b, a)
                            local pal = GetSelectedPalette()
                            local c = pal and pal.colors and pal.colors[index]
                            if not c then
                                return
                            end
                            c.r, c.g, c.b, c.a = Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a)
                            NotifyElvUIOptionsChanged()
                        end,
                    },
                    name = {
                        type = "description",
                        name = (entry.name and entry.name ~= "") and entry.name or ("Color " .. tostring(index)),
                        order = 2,
                        width = 1.0,
                    },
                    desc = {
                        type = "description",
                        name = (entry.description and entry.description ~= "") and entry.description or "",
                        order = 3,
                        width = 2.0,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 4,
                        width = 0.6,
                        func = function()
                            local pal = GetSelectedPalette()
                            if pal then
                                RemoveColorFromPaletteById(pal, id)
                            end
                            if CM.RefreshReferenceColorsOptions then
                                CM:RefreshReferenceColorsOptions()
                            end
                            NotifyElvUIOptionsChanged()
                        end,
                    },
                },
            }

            order = order + 1
        end
    end

    return args
end

function CM:RefreshReferenceColorsOptions()
    if not referenceColorsOptions or not referenceColorsOptions.args or not referenceColorsOptions.args.colorsList then
        return
    end

    referenceColorsOptions.args.colorsList.args = BuildColorTableArgs()
end

function CM:CreateReferenceColorsConfiguration()
    referenceColorsOptions = {
        type = "group",
        name = "Colors",
        order = 1,
        args = {
            description = {
                type = "description",
                order = 1,
                name = "Create in-game reference color palettes for UI design.",
                fontSize = "large",
            },
            spacer1 = CM.Widgets:Spacer(2),
            palettes = {
                type = "group",
                inline = true,
                name = "Palettes",
                order = 2,
                args = {
                    select = {
                        type = "select",
                        name = "Active Palette",
                        order = 1,
                        width = 1.5,
                        values = function()
                            return BuildPaletteValues()
                        end,
                        get = function()
                            local ref = EnsureReferenceDB()
                            return ref.selectedPaletteId
                        end,
                        set = function(_, value)
                            local ref = EnsureReferenceDB()
                            if type(value) == "number" then
                                ref.selectedPaletteId = value
                            else
                                ref.selectedPaletteId = tonumber(value)
                            end
                            if CM.RefreshReferenceColorsOptions then
                                CM:RefreshReferenceColorsOptions()
                            end
                            NotifyElvUIOptionsChanged()
                        end,
                    },
                    newName = {
                        type = "input",
                        name = "New Palette Name",
                        order = 2,
                        width = 1.5,
                        get = function()
                            local ref = EnsureReferenceDB()
                            return (ref.ui and ref.ui.newPaletteName) or ""
                        end,
                        set = function(_, value)
                            local ref = EnsureReferenceDB()
                            ref.ui = ref.ui or {}
                            ref.ui.newPaletteName = value
                        end,
                    },
                    create = {
                        type = "execute",
                        name = "Create Palette",
                        order = 3,
                        width = 1.0,
                        func = function()
                            local ref = EnsureReferenceDB()
                            local name = (ref.ui and ref.ui.newPaletteName) or ""
                            AddPalette(name)
                            if ref.ui then
                                ref.ui.newPaletteName = ""
                            end
                            if CM.RefreshReferenceColorsOptions then
                                CM:RefreshReferenceColorsOptions()
                            end
                            NotifyElvUIOptionsChanged()
                        end,
                    },
                    delete = {
                        type = "execute",
                        name = "Delete Palette",
                        order = 4,
                        width = 1.0,
                        disabled = function()
                            local ref = EnsureReferenceDB()
                            return not (ref.palettes and #ref.palettes > 1)
                        end,
                        confirm = true,
                        confirmText = "Delete the active palette?",
                        func = function()
                            DeleteSelectedPalette()
                            if CM.RefreshReferenceColorsOptions then
                                CM:RefreshReferenceColorsOptions()
                            end
                            NotifyElvUIOptionsChanged()
                        end,
                    },
                },
            },
            actions = {
                type = "group",
                inline = true,
                name = "Actions",
                order = 3,
                args = {
                    add = {
                        type = "execute",
                        name = "Add Color",
                        order = 1,
                        func = function()
                            if _G.InCombatLockdown and _G.InCombatLockdown() then
                                return
                            end

                            local palette = GetSelectedPalette()
                            if not palette then
                                return
                            end

                            ShowAddColorPopup(function(payload)
                                local id = palette.nextColorId or 1
                                palette.nextColorId = id + 1
                                table.insert(palette.colors, EnsureColorEntry({
                                    id = id,
                                    name = payload.name or "",
                                    description = payload.description or "",
                                    r = payload.r,
                                    g = payload.g,
                                    b = payload.b,
                                    a = payload.a,
                                }, id))

                                if CM.RefreshReferenceColorsOptions then
                                    CM:RefreshReferenceColorsOptions()
                                end
                                NotifyElvUIOptionsChanged()
                            end)
                        end,
                    },
                },
            },
            spacer2 = CM.Widgets:Spacer(4),
            colorsList = {
                type = "group",
                name = "Palette",
                order = 5,
                args = {},
            },
        },
    }

    CM:RefreshReferenceColorsOptions()
    return referenceColorsOptions
end
