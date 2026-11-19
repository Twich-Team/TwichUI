-- TwichUI: Loot Rolls, the game's own roll frames
-- Lets GroupLootFrame1..N step aside for a roll while a TwichUI card is showing that roll, and puts them back at once if the card goes.
-- The game's frames are not removed, replaced or hidden with Hide(): they keep running underneath (their events, their timers, their place in
-- the container's list), so nothing of the game's own bookkeeping is touched, no Blizzard function is called or replaced, and giving a
-- frame back is only turning its alpha and mouse back on. A parked frame is invisible (alpha 0) and cannot be clicked (mouse off on the
-- frame and on every button and icon in it), so only one set of roll controls is ever live. Which frames are parked is decided one roll at
-- a time: a frame is parked only while a card exists for the roll it shows; a roll with no card (the card failed, or the feature was just
-- switched off) keeps its frame, so a roll can never be left without controls.
--
-- Evidence (Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua|xml, loaded for camelot, the Forever client; the game's START_LOOT_ROLL handler
-- is a private one, so unlike older clients nothing can unregister the event): GroupLootFrame1..4 are plain frames with .rollID, .IconFrame
-- and .LootButtonContainer.LootButtons; the roll buttons call RollOnLoot themselves. gear/Rolls.lua already hooks the same frames.

local R = TwichUI
local B = {}
R.LootBlizzard = B

local MAX_FRAMES = 8
local parked = setmetatable({}, { __mode = "k" })   -- [frame] = { alpha, mouse = { [region] = was } }
local hooked = setmetatable({}, { __mode = "k" })
local frames = {}
local enabled = false
local hasCard = function() return false end   -- (rollID) true while a card shows that roll; set by Cards.lua

function B.SetCardTest(fn) hasCard = fn end

local function Targets(frame)
    local list = { frame }
    local icon = frame.IconFrame
    if icon then list[#list + 1] = icon end
    local container = frame.LootButtonContainer
    if container then
        list[#list + 1] = container
        for _, button in ipairs(container.LootButtons or {}) do list[#list + 1] = button end
    end
    return list
end

local function Park(frame)
    if parked[frame] then return end
    local rec = { alpha = frame:GetAlpha(), mouse = {} }
    parked[frame] = rec
    frame:SetAlpha(0)
    for _, region in ipairs(Targets(frame)) do
        if region.IsMouseEnabled and region.EnableMouse then
            rec.mouse[region] = region:IsMouseEnabled()
            region:EnableMouse(false)
        end
    end
end

local function Unpark(frame)
    local rec = parked[frame]
    if not rec then return end
    parked[frame] = nil
    frame:SetAlpha(rec.alpha or 1)
    for region, was in pairs(rec.mouse) do region:EnableMouse(was) end
end

-- A frame shows (or is reused for) a roll: park it when a card has that roll, give it back when not.
local function Settle(frame)
    if not enabled then return Unpark(frame) end
    local id = frame.rollID
    if id ~= nil and frame:IsShown() and hasCard(id) then Park(frame) else Unpark(frame) end
end

local function Collect()
    for i = 1, MAX_FRAMES do
        local frame = _G["GroupLootFrame" .. i]
        if frame and frame.HookScript and not hooked[frame] then
            hooked[frame] = true
            frames[#frames + 1] = frame
            frame:HookScript("OnShow", Settle)
            frame:HookScript("OnHide", Unpark)   -- a frame that is hidden is the game's again, whatever it shows next
        end
    end
end

-- Every game frame looks at the cards again (a card appeared or left).
function B.Sync()
    if not enabled then return end
    Collect()
    for _, frame in ipairs(frames) do Settle(frame) end
end

function B.Enable()
    enabled = true
    Collect()
    B.Sync()
end

-- Gives every frame back, now (the feature is off, or the cards failed).
function B.Disable()
    enabled = false
    for _, frame in ipairs(frames) do Unpark(frame) end
end

function B.ParkedCount()
    local n = 0
    for _ in pairs(parked) do n = n + 1 end
    return n
end
function B.IsParked(frame) return parked[frame] ~= nil end
function B.FrameCount() return #frames end
