local R, K = TwichUI, TwichUI.SettingsKit
local C, D = R.ExecuteRange, R.ExecuteRangeDisplay
local function On() return R:Enabled("executeRange") end
K.Page({
    key = "executeRange", name = "Execute Range", icon = "diagOperations", order = 96, group = "addons",
    description = "Mark a health percentage you choose on EllesmereUI's target frame and enemy nameplates.",
    keywords = "execute range health percentage threshold marker active highlight target frame enemy nameplate ellesmereui",
    overview = { label = "Execute Range", tip = "Your own health threshold, independent of class or talents.",
        status = function() return K.OnOff(On()) end },
    when = function() return C ~= nil and D ~= nil end,
    build = function()
        K.Header("Execute Range", "Choose your own threshold. Marker mode marks your percentage even above it; Active range edge emphasizes readable health in range. Both combines them. Requires EllesmereUI's own target frame or enemy nameplates; other providers receive no overlay.")
        local main = K.Toggle("executeRange", "Enable Execute Range",
            "Off by default. Draws only on verified EllesmereUI health bars, without changing their settings, actions or mouse behavior. No health is recorded and nothing is cast or triggered.")
        local resettable = {}
        local function Setting(key, label)
            local kind = type(C.DEFAULTS[key])
            local setting = K.Proxy("executeRange" .. key:sub(1, 1):upper() .. key:sub(2),
                kind == "boolean" and K.BOOL or (kind == "string" and K.STRING or K.NUMBER), label, C.DEFAULTS[key],
                function() return C.Get(key) end, function(v) C.Set(key, v) end)
            if setting then resettable[#resettable + 1] = { setting = setting, default = C.DEFAULTS[key] } end
            return setting
        end
        K.Under(K.Slider(Setting("threshold", "Health threshold (%)"), 1, 100,
            "Any whole percentage from 1 to 100, using the slider or its number box. Defaults to 20%. At or below this percentage the active edge appears if health is readable. This is your preference, never inferred from your class, talents or spells."), main, On)
        K.Under(K.Checkbox(Setting("target", "Show on target frame"),
            "Use the actual EllesmereUI target health bar. Friendly targets and unsupported frames receive none. Movement and scale follow the bar; protected layout changes wait until combat ends."), main, On)
        K.Under(K.Checkbox(Setting("nameplates", "Show on enemy nameplates"),
            "Use each current enemy EllesmereUI nameplate health bar. Removed, hidden or recycled plates lose their old indicator. Friendly and unsupported nameplates receive none."), main, On)
        K.Under(K.Dropdown(Setting("appearance", "Indicator appearance"), function() return C.CHOICES.appearance end,
            "Threshold marker: a thin gold line at your percentage, even above it. Active range edge: a restrained warm edge at or below your threshold. Both combines them. These draw underneath EllesmereUI's text and child absorb displays; its own borders and hash line are unchanged."), main, On)
        K.Status("EllesmereUI health bars", function()
            local state, target, plates = D.Status()
            if state == "off" then return "Off" end
            return (target and "Target attached" or "No enabled enemy target bar") .. "; " .. plates .. " enemy nameplates attached"
        end, function()
            local _, _, _, unavailable, pending = D.Status()
            if pending then return "A protected bar changed layout: its indicator waits until combat ends." end
            if unavailable then return "Health is restricted: active highlighting is hidden. Choose Marker or Both to keep the threshold visible." end
            return "Only visible, recognised EllesmereUI bars attach. Missing or incompatible providers safely show nothing. Status updates when this page refreshes."
        end)
        K.Header("Protected health and combat", "The game may withhold enemy health, including during combat. The active edge is hidden whenever health is secret or unreadable; it never guesses. The marker needs no health reading. Enabling on a protected target bar or changing its layout in combat waits until combat ends. Existing unchanged markers follow their bar's position and scale.")
        K.ResetButton("Execute Range settings", resettable, C.ResetSettings,
            "Restore 20%, both locations and Marker and active edge. Keeps the main feature switch.")
    end,
})
