local R, K = TwichUI, TwichUI.SettingsKit
local C, D = R.ClassPortrait, R.ClassPortraitDisplay
local STATUS = {
    off = "Decoration disabled.", waiting = "Waiting for login.",
    missing = "EllesmereUI player frame not detected.",
    combat = "Changes will appear after combat ends.",
    ready = "EllesmereUI player portrait detected.",
    class = "Artwork is not available for this class.", texture = "Class artwork could not be loaded.",
}
K.Page({
    key = "classPortrait", name = "Class Portrait Decorations", icon = "classPortrait", order = 98, group = "addons",
    description = "Add a class-themed decorative frame around your EllesmereUI player portrait.",
    keywords = "class portrait decorations ellesmereui player artwork automatic fit size offset preview strata layer above front z level slim compact original artwork",
    overview = { label = "Class Portrait Decorations", tip = "Class artwork around your player portrait.",
        status = function() return K.OnOff(C.Get("enabled")) end },
    when = function() return C ~= nil and D ~= nil end,
    build = function()
        D.Refresh()
        K.Header("Class Portrait Decorations", "Add a class-themed decorative frame around your EllesmereUI player portrait.")
        local function Setting(key, label)
            local kind = type(C.DEFAULTS[key])
            local boolean = kind == "boolean"
            return K.Proxy("classPortrait" .. key, boolean and K.BOOL or (kind == "string" and K.STRING or K.NUMBER), label, C.DEFAULTS[key],
                function() return C.Get(key) end,
                function(v)
                    if boolean or kind == "string" then C.Set(key, v) else C.Set(key, math.floor(v + 0.5)) end
                end)
        end
        K.Checkbox(Setting("enabled", "Enable Class Decoration"),
            "Decorate only EllesmereUI's player portrait. Nothing appears if the portrait is unavailable. Changes made in combat wait until combat ends.")
        K.Status("Player class", function() return D.Class() or "Available after login" end)
        K.Status("EllesmereUI", function() return STATUS[D.Status()] or STATUS.missing end)
        K.Dropdown(Setting("artwork", "Artwork style"), function() return C.CHOICES.artwork end,
            "Choose Original or the alternate Slim set for your class. Mage, Warlock and Druid reuse the earlier designs in the Slim set. Each set fits its own measured portrait opening. Changes in combat wait until combat ends.")
        K.Checkbox(Setting("automatic", "Automatic Fit"),
            "Follow the portrait's size automatically. Turn off to use a fixed starting size; the artwork still follows the portrait when moved or scaled.")
        for _, row in ipairs({ { "size", "Size Adjustment", "Percent of the automatic fit. 100% uses the measured portrait opening." },
            { "x", "Horizontal Offset", "Nudge right or left from the portrait. Your adjustment follows the player frame." },
            { "y", "Vertical Offset", "Nudge up or down from the portrait. Your adjustment follows the player frame." } }) do
            K.Slider(Setting(row[1], row[2]), C.LIMITS[row[1]][1], C.LIMITS[row[1]][2], row[3])
        end
        K.Checkbox(Setting("above", "Draw above unit frame"),
            "Draw the decoration over the player frame and portrait instead of behind them. Artwork may cover text or bars, but never takes mouse clicks. Changes in combat wait until combat ends.")
        K.Dropdown(Setting("strata", "Frame strata"), function() return C.CHOICES.strata end,
            "Choose the decoration's overall screen layer. Follow unit frame keeps EllesmereUI's layer. A higher strata can place the artwork above other windows; strata takes priority over the above/behind preference. Changes in combat wait until combat ends.")
        K.Button("Reset to Automatic", "Reset", function() C.Reset(); K.RefreshOverview() end,
            "Restore Automatic Fit, 100% size and zero offsets. Keeps your enabled, artwork and layering preferences.")
        K.Button("Show Decoration Preview", "Preview", function()
            if D.PreviewActive() then D.PreviewStop() else D.PreviewStart() end
            K.RefreshOverview()
        end, "Toggle a preview on your visible EllesmereUI player portrait, even while disabled. Ends when settings close or combat begins. A hidden portrait stays hidden.")
    end,
})
