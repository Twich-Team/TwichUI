-- TwichUI: RestedXP guide on a data bar
-- A LibDataBroker data source, "TwichUI RestedXP Guide", for a data bar (for example EllesmereUI's
-- "Broker Plugin" block). Its text says whether RestedXP's guide is on ("Guide on" / "Guide off"); a click
-- turns it on or off. Made only when RestedXP is loaded. TwichUI doesn't bundle LibDataBroker: nothing
-- happens without a data bar addon that provides it.
--
-- What RestedXP gives us (RXPGuides v4.11.22 source, SettingsPanel.lua; not a public interface, checked
-- on every use): its addon object is registered with AceAddon as "RXPGuides". settings.ToggleActive()
-- flips settings.profile.showEnabled and shows or hides every RestedXP frame (the guide window, arrow,
-- item and target buttons, flight timers). It is what RestedXP's own minimap button, its menu's
-- Show/Hide and "/rxp toggle" call, so a click here does exactly what those do, combat included (RestedXP
-- itself leaves its secure buttons alone in combat). Nothing else of RestedXP's is changed.
-- ToggleActive and settings:RefreshProfile (a RestedXP profile change) are hooked, once, so the text
-- follows a toggle made anywhere.

local R = TwichUI
local B = {}
R.RestedXPBroker = B

local NAME = "TwichUI RestedXP Guide"
local ADDON = "RXPGuides"
local ICON = [[Interface\AddOns\RXPGuides\Textures\rxp_logo-64]]
local obj
local rxp
local hooked = false
local loggedIn = false

local function FindRestedXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil end
    local ok, addon = pcall(ace.GetAddon, ace, ADDON, true)
    if ok and type(addon) == "table" then return addon end
end

local function Usable(addon)
    local settings = type(addon) == "table" and addon.settings
    return type(settings) == "table" and type(settings.ToggleActive) == "function" and type(settings.profile) == "table"
end

-- true / false, or nil when RestedXP can't be read.
function B.GuideOn()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.showEnabled and true or false
end

local function BarText()
    local on = B.GuideOn()
    if on == nil then return "Guide" end
    return on and "Guide on" or "Guide off"
end

function B.Update()
    if obj then obj.text = BarText() end
end

local function GuideName()
    local guide = rxp and rxp.currentGuide
    if type(guide) ~= "table" or type(rxp.GetGuideName) ~= "function" then return nil end
    local ok, name = pcall(rxp.GetGuideName, guide)
    if ok and type(name) == "string" and name ~= "" then return guide.title or name end
end

local function Color()
    local K = R.ChronicleStyle and R.ChronicleStyle.color
    return K or { text = { 1, 1, 1 }, textDim = { 0.8, 0.8, 0.8 }, stone = { 0.6, 0.6, 0.6 }, gold = { 0.8, 0.7, 0.3 } }
end

local function OnTooltipShow(tip)
    local K = Color()
    B.Update()
    tip:AddLine("RestedXP guide", 1, 1, 1)
    local on = B.GuideOn()
    if on == nil then
        tip:AddLine("RestedXP can't be read (a version this wasn't written for?).", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    tip:AddDoubleLine("Guide", on and "On" or "Off", K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    local name = GuideName()
    if name then tip:AddDoubleLine("Current", name, K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3]) end
    if on and rxp.settings.profile.hideGuideWindow then
        tip:AddLine("The guide window is hidden in RestedXP's options.", K.stone[1], K.stone[2], K.stone[3])
    end
    tip:AddLine(" ")
    tip:AddLine(on and "Click to turn the guide off" or "Click to turn the guide on", K.gold[1], K.gold[2], K.gold[3])
end

local function OnClick()
    if not Usable(rxp) then return end
    if GameTooltip then GameTooltip:Hide() end   -- its "Click to turn ..." line would be out of date
    rxp.settings.ToggleActive()
    B.Update()
end

local function Hook()
    if hooked then return end
    hooked = true
    hooksecurefunc(rxp.settings, "ToggleActive", B.Update)
    if type(rxp.settings.RefreshProfile) == "function" then hooksecurefunc(rxp.settings, "RefreshProfile", B.Update) end
end

-- Once, when RestedXP is loaded and a data bar addon provides LibDataBroker.
local function Create()
    if obj then return end
    rxp = rxp or FindRestedXP()
    if not Usable(rxp) then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    Hook()
    obj = LDB:NewDataObject(NAME, {
        type = "data source",   -- not "launcher": many data bars show text only for a data source
        label = "RestedXP",
        text = BarText(),
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false without RestedXP or LibDataBroker).
function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    Create()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn then Create() end end)
