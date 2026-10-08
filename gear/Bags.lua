-- TwichUI: upgrade hints, bag icons
-- Optional, off by default: a small mark in the top-left corner of bag slots
-- holding gear that would get an upgrade line in its tooltip (a fainter mark
-- for "possible" upgrades). Gear you can't wear yet isn't marked.
--
-- The marks use the game's own art: its bag upgrade arrow (as is, or gilded
-- to suit the old-world look) or the pet battle "strong against" badge.
-- Works with Blizzard's bags, separate or combined, and with EllesmereUI Bags
-- (through its item overlay API; see the end of this file). Other bag addons
-- draw their own slots and aren't marked.
--
-- Toggle: /twichui > "Mark upgrades in my bags"; style under advanced options.

local R = TwichUI
local P, H = R.GearPrefs, R.GearHints
local B = {}
R.GearBags = B

B.STYLES = {
    { key = "gilded", label = "Gilded arrow", atlas = "bags-greenarrow", desaturate = true, color = { 0.98, 0.80, 0.40 } },
    { key = "green",  label = "Green arrow", atlas = "bags-greenarrow" },
    { key = "badge",  label = "Badge", file = [[Interface\PetBattles\BattleBar-AbilityBadge-Strong]], size = 18 },
}
local STYLE = {}
for _, style in ipairs(B.STYLES) do STYLE[style.key] = style end

-- Paints a texture in one of the styles (also used for the preview in the window).
function B.ApplyStyle(texture, key)
    local style = STYLE[key] or STYLE.gilded
    if texture.twichStyle == style then return end
    texture.twichStyle = style
    if style.atlas then
        texture:SetAtlas(style.atlas, true)
    else
        texture:SetTexture(style.file)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetSize(style.size, style.size)
    end
    texture:SetDesaturated(style.desaturate or false)
    local c = style.color
    texture:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1)
end

-- Draws, or hides, the mark on a slot. Bag and slot say which item is there;
-- store holds the marks keyed by the slot's button; without one, the mark is
-- kept on the button itself (Blizzard's buttons are ours to write to).
local function Paint(button, store, parent, bag, slot, link, corner)
    local judged
    if link and R:Enabled("gearBagIcons") then
        judged = H.Judge(link, nil, nil, bag, slot)
    end
    local icon = store and store[button] or button.TwichUIUpgradeIcon
    if judged and not judged.level and H.Noteworthy(judged) then
        if not icon then
            icon = parent:CreateTexture(nil, "OVERLAY", nil, 3)
            corner = corner or "TOPLEFT"
            icon:SetPoint(corner, button, corner, corner == "TOPRIGHT" and -1 or 1, -1)
            if store then store[button] = icon else button.TwichUIUpgradeIcon = icon end
        end
        B.ApplyStyle(icon, P.Get("bagStyle"))
        icon:SetAlpha(judged.result.verdict == "possible" and 0.6 or 1)
        icon:Show()
    elseif icon then
        icon:Hide()
    end
end

local function Mark(button)
    local bag, slot = button:GetBagID(), button:GetID()
    local link = bag and slot and C_Container.GetContainerItemLink(bag, slot)
    Paint(button, nil, button, bag, slot, link)
end

-- Hooked on every bag redraw. With bag marks off (the default) it only hides marks left from when they were on,
-- without asking the game about each slot's item.
local function MarkFrame(frame)
    if R:Enabled("gearBagIcons") then
        for _, button in frame:EnumerateValidItems() do Mark(button) end
    else
        for _, button in frame:EnumerateValidItems() do
            local icon = button.TwichUIUpgradeIcon
            if icon then icon:Hide() end
        end
    end
end

-- EllesmereUI Bags draws its own slots and calls the painters registered with
-- EUI_Bags.RegisterItemOverlayIcon(name, fn) for every slot it paints, in the
-- bags, reagent bag and bank. fn(button, data): data.bag, data.slot and
-- data.itemLink (nil for an empty slot) are only valid during the call. Its
-- notes ask for state to be kept off the button, so the marks live in a weak
-- table, parented to the button's text overlay. The mark goes top right there:
-- its item level text takes the top left.
local ellesmereMarks = setmetatable({}, { __mode = "k" })
local ellesmereRegistered = false

local function PaintEllesmere(button, data)
    local link = data and data.itemLink
    Paint(button, ellesmereMarks, button._textOverlay or button, data and data.bag, data and data.slot, link, "TOPRIGHT")
end

local function InstallEllesmere()
    local bags = _G.EUI_Bags
    if ellesmereRegistered or type(bags) ~= "table" or type(bags.RegisterItemOverlayIcon) ~= "function" then return end
    ellesmereRegistered = true
    bags.RegisterItemOverlayIcon("TwichUI", PaintEllesmere)
end

-- Asks EllesmereUI Bags to repaint its open frames (which runs the painter).
local function RefreshEllesmere()
    local bags = _G.EUI_Bags
    if not ellesmereRegistered or type(bags) ~= "table" then return end
    if bags:IsVisible() and bags.RefreshInventory then bags:RefreshInventory() end
    local reagent = _G.EUI_BagsReagent
    if reagent and reagent:IsVisible() and reagent.RefreshInventory then reagent:RefreshInventory() end
end

local frames = {}

-- Re-mark open bags after anything that changes the answers, at most a few
-- times a second (skill-ups and talent changes can come in bursts).
local queued = false
local function Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        for _, frame in ipairs(frames) do
            if frame:IsShown() then MarkFrame(frame) end
        end
        RefreshEllesmere()
    end)
end
B.Refresh = Refresh

R:OnInit(function()
    R:On("ADDON_LOADED", function(name)
        if name == "EllesmereUIBags" then InstallEllesmere() end
    end)
    InstallEllesmere()   -- already loaded
    H:OnChange(Refresh)
    local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    if not list then return end
    for _, frame in ipairs(list) do frames[#frames + 1] = frame end
    frames[#frames + 1] = ContainerFrameCombinedBags
    for _, frame in ipairs(frames) do
        if frame.UpdateItems and frame.EnumerateValidItems then
            hooksecurefunc(frame, "UpdateItems", MarkFrame)
        end
    end
end)
