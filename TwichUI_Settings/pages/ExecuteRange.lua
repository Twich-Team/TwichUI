local R, K = TwichUI, TwichUI.SettingsKit
local C, D = R.ExecuteRange, R.ExecuteRangeDisplay
local function On() return R:Enabled("executeRange") end
-- Inline, non-animated sample using the live decoration renderer. Never joins
-- provider discovery or changes health/settings; hidden pages do no preview work.
local preview
local function RefreshPreview()
    if not preview or not preview:IsShown() or not preview.samples then return end
    local width = math.max(80, math.min(430, preview:GetWidth() - 24))
    local threshold = C.Get("threshold") / 100
    local fractions = { math.min(1, threshold + 0.15), threshold, threshold / 2 }
    for i, sample in ipairs(preview.samples) do
        sample.bar:SetSize(width, 22)
        sample.health:SetWidth(width * fractions[i])
        sample.label:SetText((i == 1 and "Higher health" or i == 2 and "At threshold" or "Below threshold")
            .. (" — %.1f%%"):format(fractions[i] * 100))
        D.Preview(sample.decoration, width, 22, fractions[i])
    end
end
local function Preview()
    if preview then return preview end
    preview = CreateFrame("Frame")
    preview:Hide()
    preview:SetScript("OnShow", function()
        if not preview.samples then
            preview.samples = {}
            local W = R.SettingsWidgets
            for i = 1, 3 do
                local bar = CreateFrame("Frame", nil, preview)
                bar:SetPoint("TOPLEFT", 12, -24 - (i - 1) * 50)
                local back = bar:CreateTexture(nil, "BACKGROUND")
                back:SetAllPoints(); back:SetColorTexture(0.10,0.07,0.06,1)
                local health = bar:CreateTexture(nil, "BORDER")
                health:SetPoint("BOTTOMLEFT"); health:SetHeight(22)
                health:SetColorTexture(0.34,0.15,0.12,1)
                local label = W.Text(preview, "meta")
                label:SetPoint("BOTTOMLEFT",bar,"TOPLEFT",0,3)
                preview.samples[i] = { bar=bar, health=health, label=label, decoration=D.CreateDecoration(bar) }
            end
        end
        RefreshPreview()
    end)
    preview:SetScript("OnSizeChanged", RefreshPreview)
    return preview
end
C.Subscribe(RefreshPreview)
if R.MenuStyle and R.MenuStyle.StatusBars then R.MenuStyle.StatusBars.Subscribe(RefreshPreview) end
R.Profiles.OnApply("layout", "executeRangePreview", RefreshPreview)
R.Profiles.OnChange(RefreshPreview)
K.Page({
    key = "executeRange", name = "Execute Range", icon = "executeRange", order = 96, group = "addons",
    description = "Mark a health percentage you choose on EllesmereUI's target frame and enemy nameplates.",
    keywords = "execute range health percentage threshold marker active highlight target frame enemy nameplate ellesmereui",
    overview = { label = "Execute Range", tip = "Your own health threshold, independent of class or talents.",
        status = function() return K.OnOff(On()) end },
    when = function() return C ~= nil and D ~= nil end,
    host = Preview, hostAfter = "Appearance preview", hostHeight = 178,
    build = function()
        K.Header("Execute Range", "Choose your own threshold. Keep a threshold marker or active edge, shade the execute zone, or highlight only the remaining active health. Requires EllesmereUI's own target frame or enemy nameplates; other providers receive no overlay.")
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
        K.Header("Appearance", "The original marker and edge keep their colors. Fill controls customize the zone and active health styles. Only one fill is drawn at once.")
        K.Under(K.Dropdown(Setting("appearance", "Indicator style"), function() return C.CHOICES.appearance end,
            "Marker and Active range edge retain their original appearance. Execute zone shades 0% to your threshold even above range. Active health highlight shades only remaining readable health while in range. Combined choices add a marker and optionally the original active edge."), main, On)
        local function Fill() local _,_,zone,highlight = C.Style(C.Get("appearance")); return On() and (zone or highlight) end
        local whyFill = function() return "Enable Execute Range and choose a style with a zone or active health fill." end
        K.Under(K.Swatch(Setting("color", "Fill color"),
            "Tint of the fill texture. The color picker's alpha and Fill opacity multiply. Marker and edge keep their original colors."), main, Fill, whyFill)
        K.Under(K.Slider(Setting("opacity", "Fill opacity (%)"), 0, 100,
            "25% by default, for a restrained translucent fill. Zero hides the fill without changing your style."), main, Fill, whyFill)
        K.Under(K.Dropdown(Setting("texture", "Fill texture"), function()
            local media = R.MenuStyle and R.MenuStyle.StatusBars
            return media and media.Choices(C.Get("texture")) or { { "solid", "Flat color" } }
        end, "Existing EllesmereUI and registered bar textures, including subtle shaded or patterned fills where available. Missing textures remain selected and draw flat. No decorative animation."), main, Fill, whyFill)
        K.Header("Appearance preview", "Static sample health bars, drawn with your choices even while the feature is off. At a 100% threshold all samples are in range. No unit is changed and no preview timer runs.")
        K.Status("EllesmereUI health bars", function()
            local state, target, plates = D.Status()
            if state == "off" then return "Off" end
            return (target and "Target attached" or "No enabled enemy target bar") .. "; " .. plates .. " enemy nameplates attached"
        end, function()
            local _, _, _, unavailable, pending = D.Status()
            if pending then return "A protected fill or bar needs layout: it waits until combat ends." end
            if unavailable then return "Health is restricted: active highlighting is hidden. Choose Marker or Both to keep the threshold visible." end
            return "Only visible, recognised EllesmereUI bars attach. Missing or incompatible providers safely show nothing. Status updates when this page refreshes."
        end)
        K.Header("Protected health and combat", "The game may withhold enemy health, including during combat. The active edge and health highlight hide whenever health is secret or unreadable; they never guess. The marker and execute zone need no health reading. When a protected active fill needs resizing in combat, it falls back to the existing active edge until safe layout is possible. The unchanged marker and zone remain available. Enabling on a protected target bar or changing its layout in combat waits until combat ends. Existing unchanged markers follow their bar's position and scale.")
        K.ResetButton("Execute Range settings", resettable, C.ResetSettings,
            "Restore 20%, both locations, Marker and active edge, warm fill color, 25% opacity and flat texture. Keeps the main feature switch.")
    end,
})
