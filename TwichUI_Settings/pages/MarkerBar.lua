-- TwichUI settings: Quality of life › Marker bar (markers/Bar.lua). The switch and the key to hold, which markers are on
-- the bar (a frame of this window's own: eight ticks with their icons), where it appears and what it does in combat,
-- and its size and look. The bar's fixed place is moved by dragging the preview ("Show and move"), an ordinary copy
-- of the bar that marks nothing; the preview closes when this page is left, the window closes or combat starts.
-- Every change goes through Bar.lua, which gives it to the secure bars out of combat (in combat it is saved and
-- waits). Nothing here marks or clears a marker in the game.

local R = TwichUI
local K = R.SettingsKit
local B = R.MarkerBar
local M = R.Markers
local P = {}
R.MarkerBarPage = P

local W = 644                     -- the settings window's content width
local TILE_W, TILE_H, GAP = 72, 88, 6
local HOST_H = 108

local function Wg() return R.SettingsWidgets end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Which markers are on the bar
---------------------------------------------------------------------------
local f, built
local tiles = {}

local function Refresh()
    if not (f and built and f:IsVisible()) then return end
    local G = Wg()
    local pal = G.pal
    for id = 1, M.COUNT do
        local t = tiles[id]
        local on = B.Get("show" .. id)
        t.box:SetChecked(on)
        t.icon:SetDesaturated(not on)
        t.icon:SetAlpha(on and 1 or 0.45)
        G.Color(t.name, on and pal.text or pal.stone)
        local fill, edge = on and pal.surface or pal.well, on and pal.teal or pal.bronzeLo
        t:SetBackdropColor(fill[1], fill[2], fill[3], on and 0.95 or 0.9)
        t:SetBackdropBorderColor(edge[1], edge[2], edge[3], on and 0.7 or 0.5)
        t.state:SetText(on and "" or "Not on the bar")
        t.cycle:SetText(M.IsOn("target", id) and "" or "Skipped in cycle")
    end
end

local function Build()
    built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal
    f.about = G.Text(f, "small")
    f.about:SetPoint("TOPLEFT", 4, -2)
    f.about:SetWidth(W - 8)
    f.about:SetText("They come in the order of your target-marker cycle (the Target markers tab). A marker skipped in the cycle can still be on the bar, and the other way round.")
    for id = 1, M.COUNT do
        local t = CreateFrame("Button", nil, f, "BackdropTemplate")
        t:SetSize(TILE_W, TILE_H)
        t:SetPoint("TOPLEFT", 4 + (id - 1) * (TILE_W + GAP), -26)
        G.Surface(t, pal.surface, 0.95, pal.bronzeLo, 0.5)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(30, 30)
        t.icon:SetPoint("TOP", 0, -8)
        t.icon:SetTexture(M.Texture("target", id))
        t.name = G.Text(t, "small")
        t.name:SetPoint("TOP", 0, -42)
        t.name:SetWidth(TILE_W - 6)
        t.name:SetJustifyH("CENTER")
        t.name:SetText(M.Name("target", id))
        t.state = G.Text(t, "meta")
        t.state:SetPoint("BOTTOM", 0, 6)
        t.state:SetWidth(TILE_W - 6)
        t.state:SetJustifyH("CENTER")
        t.cycle = G.Text(t, "meta")
        t.cycle:SetPoint("BOTTOM", 0, 18)
        t.cycle:SetWidth(TILE_W - 6)
        t.cycle:SetJustifyH("CENTER")
        t.box = G.Checkbox(t, function(on) B.Set("show" .. id, on) end)
        t.box:SetPoint("TOP", 0, -58)
        t.box:SetSize(16, 16)
        t:SetScript("OnClick", function() B.Set("show" .. id, not B.Get("show" .. id)) end)
        I.Tip(t, M.Name("target", id), function()
            return B.Get("show" .. id) and "On the bar. Click to take it off." or "Not on the bar. Click to put it on."
        end)
        tiles[id] = t
    end
end

-- The page's frame (the settings window shows it under the section it follows). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        Refresh()
    end)
    f:SetScript("OnHide", function() B.ShowPreview(false) end)   -- leaving the page or closing the window
    return f
end

if B and M then
    B.OnState(function(what)
        Refresh()
        if what ~= "config" then K.RefreshOverview() end   -- (a setting's own change redraws the page already)
    end)
    M.OnChange(function(kind) if kind == nil or kind == "target" then Refresh() end end)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function On() return R:Enabled("markersBar") end

K.Page({
    key = "markersBar", name = "Marker bar", parent = "qol", order = 33,
    description = "Hold a key to show a bar of target markers for your target, and click one to mark it.",
    keywords = "marker markers bar raid target icon skull cross square moon triangle diamond circle star pick choose click modifier shift ctrl alt nameplate fixed combat",
    when = function() return R.Markers ~= nil and R.MarkerBar ~= nil end,
    host = function() return P.Frame() end, hostAfter = "Markers on the bar", hostHeight = HOST_H,
    build = function()
        local Header, Toggle, Under, Choice, Button, Slider, Proxy = K.Header, K.Toggle, K.Under, K.Choice, K.Button, K.Slider, K.Proxy
        local STRING, NUMBER = K.STRING, K.NUMBER

        local function Option(name, label, tooltip, varType, options)
            return Choice("markerBar" .. name:sub(1, 1):upper() .. name:sub(2), label, tooltip, varType, B.DEFAULTS[name],
                function() return B.Get(name) end, function(value) B.Set(name, value) end, options)
        end
        local function Number(name, label, tooltip)
            local setting = Proxy("markerBar" .. name:sub(1, 1):upper() .. name:sub(2), NUMBER, label, B.DEFAULTS[name],
                function() return B.Get(name) end, function(value) B.Set(name, math.floor(value + 0.5)) end)
            local lim = B.LIMITS[name]
            return Slider(setting, lim[1], lim[2], tooltip)
        end

        Header("Marker bar", "A small bar of target markers for your target. Off until you turn it on. It marks only when you click an icon, never by itself.")
        local toggle = Toggle("markersBar", "Show a marker bar while a key is held",
            "While you hold the key below and have a target, a bar of target markers appears. Click a marker to mark your target with it; click Remove, or right-click any marker, to take your target's marker off. Letting go of the key hides it. The marker your target wears now has a ring.\n\nThe game decides whether you may mark (in a group that can need the leader or an assistant). The bar is the game's own secure buttons, so its markers, size, look and place can only be changed out of combat: a change in combat is saved and reaches the bar when combat ends. The keys for cycling markers work the same with or without it.")
        K.Note(toggle, function()
            if B.Pending() then return "In combat: your changes are saved and reach the bar when combat ends.", "reload" end
        end)
        Under(Option("modifier", "Hold to show it", "The key to hold. Hold it while clicking a marker on the bar.", STRING, {
            { "shift", "Shift" }, { "ctrl", "Ctrl" }, { "alt", "Alt" } }), toggle, On)
        Under(K.ProxyToggle("markerBarRemove", "Include a Remove button",
            "A button at the end of the bar that takes the marker off your target. Right-clicking any marker does the same.",
            B.DEFAULTS.remove, function() return B.Get("remove") end, function(value) B.Set("remove", value and true or false) end), toggle, On)

        Header("Markers on the bar", "Tick the markers to offer. They are in the order of your target-marker cycle.")

        Header("Where it appears", "Above your target's nameplate, or at a place of your own. Where you put the fixed place is kept on this computer.")
        local where = Under(Option("where", "Place the bar", "Above the target's nameplate follows your target while you are out of combat. At a fixed place it is always in the same spot, which you can move.", STRING, {
            { "nameplate", "Above the target's nameplate", "Follows the nameplate of your target. If the target has none (nameplates turned off, off screen, or one the game won't let addons use), the bar appears at the fixed place instead." },
            { "fixed", "At a fixed place", "Always appears where you put it." } }), toggle, On)
        Under(Option("combat", "In combat", "A bar can't follow a new target in combat (the game doesn't allow a secure frame to move then). Choose what it does instead.", STRING, function()
            if B.Get("where") == "nameplate" then
                return { { "show", "Show it at the fixed place", "In combat the bar appears at the fixed place instead of next to the nameplate." },
                    { "hide", "Hide it", "The bar only appears out of combat." } }
            end
            return { { "show", "Show it", "The bar appears in combat too." }, { "hide", "Hide it in combat", "The bar only appears out of combat." } }
        end), toggle, On)
        local function Near() return On() and B.Get("where") == "nameplate" end
        local nearWhy = "Needs \"Place the bar\" set to above the target's nameplate."
        Under(Option("side", "Side of the nameplate", "Above or below the target's nameplate.", STRING, {
            { "above", "Above" }, { "below", "Below" } }), where, Near, nearWhy)
        Under(Number("offsetY", "Distance from the nameplate", "How far from the nameplate's top (or bottom), in screen pixels. Raise it to clear the name and health bar; lower it to sit closer."), where, Near, nearWhy)
        Under(Number("offsetX", "Sideways shift", "Moves the bar left (negative) or right of the nameplate's middle, in screen pixels."), where, Near, nearWhy)
        local move = Button("Fixed place", function() return B.Previewing() and "Done" or "Show and move" end, function()
            local ok, why = B.TogglePreview()
            if not ok and why == "combat" then R.Print("the bar can't be moved in combat.") end
        end, "Shows a copy of the bar at the fixed place; drag it where you want it, then press Done. The copy marks nothing. It closes when you leave this page, close the settings, or combat starts.")
        if move then
            move:AddModifyPredicate(function() return not InCombat() end)
            move.why = "Can't be moved in combat."
        end
        local back = Button("Put the fixed place back", "Put back", function()
            R.Interact.Confirm("TWICHUI_MARKERBAR_PLACE", "Put the marker bar's fixed place back in its default spot, a little above the middle of the screen?\n\nOnly this place changes. Its other settings and look are kept.", function() B.ResetPosition() end, { accept = "Put back" })
        end, "Moves the fixed place back to the default. Asks first.")
        if back then
            back.reset = true
            back:AddModifyPredicate(function() return not InCombat() end)
            back.why = "Can't be moved in combat."
        end

        Header("Size and look", "How big the markers are and what the bar's frame looks like.")
        Under(Number("iconSize", "Marker size", "The size of each marker, in screen pixels."), toggle, On)
        Under(Number("spacing", "Space between markers", "In screen pixels."), toggle, On)
        Under(Number("scale", "Bar scale", "Makes the whole bar bigger or smaller, in percent."), toggle, On)
        K.Appearance(B.Style, "markerBar", "bar", "Shows a copy of the bar at the fixed place, drawn with this look. The copy marks nothing; drag it to move the fixed place.",
            function() B.TogglePreview() end, "Reset the bar's look", "Puts the bar's background and border back to the default. The bar's other settings and its places are kept.", toggle, On, {
                labels = { BgTexture = "Bar background texture", BgColor = "Bar background color", BgOpacity = "Bar background opacity",
                    BorderTexture = "Bar border texture", BorderSize = "Bar border thickness", BorderColor = "Bar border color",
                    BorderOpacity = "Bar border opacity" } })
        K.Button("Reset the bar", "Reset", function()
            R.Interact.Confirm("TWICHUI_MARKERBAR_RESET", "Put every marker bar setting back to its default?\n\nWhich markers, the key, the placement, the sizes and the combat choice. Its look, its fixed place, the cycle keys and the target-marker order are kept.", function()
                B.ResetSettings()
                K.RefreshOverview()
            end, { accept = "Reset" })
        end, "Puts back the marker bar's settings, except its look and its fixed place. Asks first.").reset = true
    end,
})
