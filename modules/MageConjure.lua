-- TwichUI: Mage Conjuring
-- A data bar launcher, "TwichUI Mage Conjuring", for Mages: its icon and, by the player's choice,
-- the word "Conjure" or "Food & Water" (or no text). Clicking it opens a small menu with one row
-- each for Conjure Food and Conjure Water: the highest rank this character has learned, cast by
-- clicking it. With none learned, the row is rank 1, muted, and its tooltip says the level it is
-- trained at. Shift-left-click on the launcher conjures water and
-- shift-right-click food, each at the highest rank known. The menu, its secure rows, the
-- shortcuts, combat rules and the data object are shared with Mage Travel
-- (modules/SpellMenu.lua); this file says which spells.
-- Spells, ranks and levels: What's Training?'s Forever data (MIT), as modules/TrainingData.lua
-- carries it. Forever's data has six ranks of each, not vanilla's seven.
-- Nothing is saved but the on/off setting and the text choice (TwichUIDB.ui.mageConjureText).

local R = TwichUI
local SM = R.SpellMenu
local M = {}
R.MageConjure = M

local ICON = R.PATH .. [[media\textures\mage-conjure]]   -- a loaf and a corked blue flask (64 x 64)

-- Each rank in order, lowest first; each needs the one before it.
-- Checked against modules/TrainingData.lua by tests/test_mage_conjure.lua.
M.SPELLS = {
    food = { 587, 597, 990, 6129, 10144, 10145 },        -- Conjure Food, ranks 1-6
    water = { 5504, 5505, 5506, 6127, 10138, 10139 },    -- Conjure Water, ranks 1-6
}
M.KINDS = {
    { key = "food", label = "Food" },
    { key = "water", label = "Water" },
}
-- The data bar text: { value, label } for the option. "none" leaves only the icon.
M.TEXTS = { { "Conjure", "Conjure" }, { "Food & Water", "Food & Water" }, { "none", "None (icon only)" } }
M.DEFAULT_TEXT = "Conjure"

function M.ForPlayer() return SM.PlayerClass() == "MAGE" end

-- [spellID] = { level, req } from the training data. Built once: it doesn't change in a session.
local training
local function Training(id)
    if not training then
        local wanted = {}
        for _, list in pairs(M.SPELLS) do
            for _, spellID in ipairs(list) do wanted[spellID] = true end
        end
        training = SM.TrainingInfo("MAGE", wanted)
    end
    return training[id]
end

function M.TrainedAt(id)
    local t = Training(id)
    return t and t.level
end

-- This character's sections: { { label, kind, rows = { entry }, learned, total }, ... }, and
-- whether a name was still loading (its row is left out until it arrives). Each section has one
-- row: the highest rank this character has learned, found by walking the ranks in order and
-- asking the spellbook about each exact spell ID (never "the largest ID"). With no rank learned
-- the row is rank 1, the one to learn first, with its learning information. If the highest
-- learned rank's name hasn't loaded, the row waits for it; no other rank stands in. An entry is
-- { id, name, text (the rank), icon, known, level, note, kind, previous } where previous is the
-- rank before it, or nil for rank 1. learned and total count the ranks, for the launcher tooltip.
function M.Entries()
    local sections, loading = {}, false
    for _, kind in ipairs(M.KINDS) do
        local list = {}
        local ranks = M.SPELLS[kind.key]
        local best, learned = 1, 0
        for rank = 1, #ranks do
            if SM.Known(ranks[rank]) then best, learned = rank, learned + 1 end
        end
        local id = ranks[best]
        local name, icon = SM.Spell(id)
        if name then
            local level = M.TrainedAt(id)
            list[1] = { id = id, name = name, text = SM.RankText(id, best), icon = icon,
                known = learned > 0, level = level, note = level and ("Level " .. level), kind = kind,
                previous = ranks[best - 1] }
        else
            loading = true
        end
        sections[#sections + 1] = { label = kind.label, kind = kind, rows = list, learned = learned, total = #ranks }
    end
    return sections, loading
end

local function LearnLines(tip, e)
    local K = SM.Palette()
    if e.level then
        local level = UnitLevel and SM.Plain(UnitLevel("player"))
        local c = (level and level >= e.level) and { 0.56, 0.70, 0.35 } or K.ember
        tip:AddLine(("Trained at level %d"):format(e.level), c[1], c[2], c[3])
    else
        tip:AddLine("Training level unavailable", K.stone[1], K.stone[2], K.stone[3])
    end
    if e.previous and not SM.Known(e.previous) then
        local name = SM.Spell(e.previous)
        local rank
        for i, id in ipairs(M.SPELLS[e.kind.key]) do
            if id == e.previous then rank = i end
        end
        tip:AddLine(("Requires %s (%s) first"):format(name or "the rank before", SM.RankText(e.previous, rank)),
            K.textDim[1], K.textDim[2], K.textDim[3])
    end
    -- What's Training? lists these among a class trainer's spells, and the level-up training card
    -- says "Visit a class trainer" for them. Portals don't say this: vanilla taught them only at
    -- special portal trainers, and no local source says where Forever does.
    tip:AddLine("Taught by Mage trainers", K.stone[1], K.stone[2], K.stone[3])
end

local launcher = SM.New({
    key = "mageConjure",
    name = "TwichUI Mage Conjuring",
    label = "Mage Conjuring",
    menuName = "TwichUIMageConjureMenu",
    icon = ICON,
    page = "mage",
    textKey = "mageConjureText",
    texts = M.TEXTS,
    defaultText = M.DEFAULT_TEXT,
    hint = "Click to choose what to conjure",
    empty = "Nothing to conjure for this character.",
    forPlayer = M.ForPlayer,
    entries = M.Entries,
    learnLines = LearnLines,
    shortcuts = {
        { button = "LeftButton", label = "Conjure Water", ranks = M.SPELLS.water },
        { button = "RightButton", label = "Conjure Food", ranks = M.SPELLS.food },
    },
    -- Only while Mage refreshments (modules/Refreshments.lua, loaded after this file) is on.
    footer = {
        label = "Refreshments for your group...",
        hint = "Opens the refreshments panel: how much your party or raid needs, and who you've supplied.",
        shown = function() return R.Refreshments ~= nil and R.Refreshments.Enabled() end,
        onClick = function() if R.RefreshmentsPanel then R.RefreshmentsPanel.Open() end end,
    },
})
M.Open, M.Close, M.Toggle, M.IsOpen = launcher.Open, launcher.Close, launcher.Toggle, launcher.IsOpen
M.Available, M.Refresh = launcher.Available, launcher.Refresh
M.TextChoice, M.SetTextChoice = launcher.TextChoice, launcher.SetTextChoice
