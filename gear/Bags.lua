-- TwichUI: upgrade hints, bag icons
-- Optional, off by default: a small mark in the top-left corner of bag slots
-- holding gear that would get an upgrade line in its tooltip (a fainter mark
-- for "possible" upgrades). Gear you can't wear yet isn't marked.
--
-- The marks use the game's own art: its bag upgrade arrow (as is, or gilded
-- to suit the old-world look) or the pet battle "strong against" badge.
-- Works with Blizzard's bags, separate or combined; other bag addons draw
-- their own slots and aren't marked.
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

local function Mark(button)
    local judged
    if R:Enabled("gearBagIcons") then
        local bag, slot = button:GetBagID(), button:GetID()
        local link = bag and slot and C_Container.GetContainerItemLink(bag, slot)
        judged = link and H.Judge(link, nil, nil, bag, slot)
    end
    local icon = button.TwichUIUpgradeIcon
    if judged and not judged.level and H.Noteworthy(judged) then
        if not icon then
            icon = button:CreateTexture(nil, "OVERLAY", nil, 3)
            icon:SetPoint("TOPLEFT", 1, -1)
            button.TwichUIUpgradeIcon = icon
        end
        B.ApplyStyle(icon, P.Get("bagStyle"))
        icon:SetAlpha(judged.result.verdict == "possible" and 0.6 or 1)
        icon:Show()
    elseif icon then
        icon:Hide()
    end
end

local function MarkFrame(frame)
    for _, button in frame:EnumerateValidItems() do Mark(button) end
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
    end)
end
B.Refresh = Refresh

R:OnInit(function()
    local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    if not list then return end
    for _, frame in ipairs(list) do frames[#frames + 1] = frame end
    frames[#frames + 1] = ContainerFrameCombinedBags
    for _, frame in ipairs(frames) do
        if frame.UpdateItems and frame.EnumerateValidItems then
            hooksecurefunc(frame, "UpdateItems", MarkFrame)
        end
    end
    H:OnChange(Refresh)
end)
