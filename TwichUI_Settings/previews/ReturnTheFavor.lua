-- The standard feature-card preview, using the list's inert sample renderer.
-- Opening it works while the module is off and never casts, targets, emotes or moves the live list.
local R = TwichUI

R.SettingsPreviews.Register("buffBack.list", {
    height = 190,
    static = true,
    Sample = function()
        return { duration = R.BuffBack.Get("duration"), maxRows = R.BuffBack.Get("maxRows") }
    end,
    Create = function(stage)
        return { stage = stage, list = R.BuffBackList.CreateSettingsPreview(stage) }
    end,
    Reset = function(scene)
        scene.list.Refresh(math.max(1, scene.stage:GetWidth() - 32), 150)
    end,
    Caption = function(s)
        return ("Made-up names drawn with your appearance settings; scaled to fit. Up to %d names stay for %d seconds. Click a real name to buff them back. Use Sample under Appearance to position the list."):format(s.maxRows, s.duration)
    end,
})
