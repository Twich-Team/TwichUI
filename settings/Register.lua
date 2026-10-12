-- TwichUI: options, put together once the saved variables are in (see settings/Kit.lua).
-- Pages are made first, in their order, so the category list keeps it; then each is built. A page that
-- fails to build is reported and the rest are still there: one broken page never takes the others with it.

local R = TwichUI
local K = R.SettingsKit

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory) then return end
    local VarType = Settings.VarType or {}
    K.BOOL = VarType.Boolean or "boolean"
    K.STRING = VarType.String or "string"
    K.NUMBER = VarType.Number or "number"

    TwichUIDB.ui = TwichUIDB.ui or {}
    if TwichUIDB.ui.showAdvanced == nil then TwichUIDB.ui.showAdvanced = false end

    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = root
    R.settingsCategories = { overview = root }   -- R:OpenSettings(key)
    K.pages.overview = { category = root, layout = rootLayout }

    local defs, overview = {}, nil
    for _, def in ipairs(K.Ordered()) do
        if def.key == "overview" then
            overview = def
        elseif def.when == nil or def.when() then
            -- parent: a page of its own under another page (the list shows it indented, under that page)
            local parent = def.parent and K.pages[def.parent] and K.pages[def.parent].category or root
            local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, def.name)
            K.pages[def.key] = { category = category, layout = layout, def = def }
            R.settingsCategories[def.key] = category
            if parent ~= root and category.SetExpanded and parent.SetExpanded then parent:SetExpanded(true) end
            defs[#defs + 1] = def
        end
    end

    -- The overview is filled in last, once each page's status is known.
    if overview then defs[#defs + 1] = overview end
    for _, def in ipairs(defs) do
        K.Use(def.key)
        local ok, err = pcall(def.build, K.pages[def.key])
        if not ok then R.Fault("options page " .. def.key, err) end
        if K.advancedPages[def.key] then
            K.Use(def.key)   -- a page may build another's rows on the way; the hint goes on its own
            K.AdvancedHint()
        end
    end

    Settings.RegisterAddOnCategory(root)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
