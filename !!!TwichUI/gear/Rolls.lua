-- TwichUI: upgrade hints, loot roll marks
-- Optional, off by default: the same small mark as the bag marks, in the
-- top-left corner of the item icon on a group loot roll (Need / Greed), when
-- the item would get an upgrade line in its tooltip (fainter for "possible"
-- upgrades). It is a signal beside your own choice: it never rolls, never
-- moves the buttons and never speaks in chat.
--
-- Reads the roll's item link and tooltip data from the game, hands them to
-- the same judge the tooltips and bags use (Hints.lua), and draws the result
-- with the bag mark style. Works on Blizzard's GroupLootFrame1..N, which
-- EllesmereUI skins in place, so the mark follows the same frames.
--
-- Toggle: /twichui > "Mark upgrades on loot rolls"; style under the bag marks.

local R = TwichUI
local P, H, B = R.GearPrefs, R.GearHints, R.GearBags
local L = {}
R.GearRolls = L

-- Marks live off the Blizzard frame, in a weak table keyed by it.
local marks = setmetatable({}, { __mode = "k" })
local latest = setmetatable({}, { __mode = "k" })   -- [frame] = the newest Update's number, so an older retry can tell it was replaced
local frames = {}

-- The game may not have the item (or your own gear) loaded the moment a roll
-- opens; ask again a couple of times, then leave it unmarked.
local RETRIES = 3
local RETRY_AFTER = 0.5

local function Hide(frame)
    local icon = marks[frame]
    if icon then icon:Hide() end
end

local function Show(frame, judged)
    local parent = frame.IconFrame
    if not parent then return end
    local icon = marks[frame]
    if not icon then
        icon = parent:CreateTexture(nil, "OVERLAY", nil, 3)
        icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
        marks[frame] = icon
    end
    B.ApplyStyle(icon, P.Get("bagStyle"))
    icon:SetAlpha(judged.result.verdict == "possible" and 0.6 or 1)
    icon:Show()
end

-- Judges the roll the frame is showing and draws, or hides, its mark. The
-- tooltip data supplies the red "can't use" lines the judge needs; without
-- it the item isn't judged at all, so nothing is marked on a guess.
local function Update(frame, attempt)
    local mine = (latest[frame] or 0) + 1
    latest[frame] = mine
    local rollID = frame.rollID
    if not (R:Enabled("gearRollIcons") and rollID and frame:IsShown()) then return Hide(frame) end
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    local data = C_TooltipInfo and C_TooltipInfo.GetLootRollItem and C_TooltipInfo.GetLootRollItem(rollID)
    if type(link) ~= "string" or not (data and data.lines) then return Hide(frame) end
    local judged = H.Judge(link, data.lines)
    if judged and not judged.level and H.Noteworthy(judged) then
        Show(frame, judged)
        return
    end
    Hide(frame)
    if judged == nil and (attempt or 1) < RETRIES then
        C_Timer.After(RETRY_AFTER, function()
            if latest[frame] == mine and frame.rollID == rollID then Update(frame, (attempt or 1) + 1) end
        end)
    end
end

-- Repaints every open roll (a switch or the style changed, or your gear did).
function L.Refresh()
    for _, frame in ipairs(frames) do Update(frame) end
end

R:OnInit(function()
    H:OnChange(L.Refresh)
    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local frame = _G["GroupLootFrame" .. i]
        if frame and frame.HookScript then
            frames[#frames + 1] = frame
            -- The game fills in rollID before it shows a pooled frame, and hides it when the roll ends.
            frame:HookScript("OnShow", Update)
            frame:HookScript("OnHide", Hide)
        end
    end
end)
