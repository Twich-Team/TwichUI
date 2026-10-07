-- TwichUI: Mage Travel
-- A data bar launcher, "TwichUI Mage Travel", for Mages: its icon and, by the player's choice,
-- the word "Travel" or "Portals" (or no text). Clicking it opens a small menu of the teleports
-- and portals WoW: Forever teaches the character's faction, in two sections. The menu, its
-- secure rows, combat rules and the data object are shared with Mage Conjuring
-- (modules/SpellMenu.lua); this file says which spells and how to describe them.
-- Spells, factions and levels: What's Training?'s Forever data (MIT), as modules/TrainingData.lua
-- carries it. No local source records where Forever teaches these spells, so an unlearned one's
-- tooltip says so rather than naming a trainer.
-- Nothing is saved but the on/off setting and the text choice (TwichUIDB.ui.mageTravelText).

local R = TwichUI
local SM = R.SpellMenu
local M = {}
R.MageTravel = M

local ICON = R.PATH .. [[media\textures\mage-travel]]   -- a swirling blue portal in a gold ring (64 x 64)

-- The teleports and portals Forever teaches, by faction, in one city order so the two
-- sections line up. Forever has no Theramore, Stonard, Shattrath or later destinations.
-- Checked against modules/TrainingData.lua by tests/test_mage_travel.lua.
M.SPELLS = {
    Alliance = {
        teleport = { 3561, 3562, 3565 },     -- Stormwind, Ironforge, Darnassus
        portal = { 10059, 11416, 11419 },
    },
    Horde = {
        teleport = { 3567, 3563, 3566 },     -- Orgrimmar, Undercity, Thunder Bluff
        portal = { 11417, 11418, 11420 },
    },
}
M.KINDS = {
    { key = "teleport", label = "Teleports", one = "Teleport" },
    { key = "portal", label = "Portals", one = "Portal" },
}
-- The data bar text: { value, label } for the option. "none" leaves only the icon.
M.TEXTS = { { "Travel", "Travel" }, { "Portals", "Portals" }, { "none", "None (icon only)" } }
M.DEFAULT_TEXT = "Travel"

function M.ForPlayer() return SM.PlayerClass() == "MAGE" end

local function Faction() return UnitFactionGroup and SM.Plain((UnitFactionGroup("player"))) end

-- [spellID] = the level a trainer teaches it at. Built once: it doesn't change in a session.
local training
function M.TrainedAt(id)
    if not training then
        local wanted = {}
        for _, set in pairs(M.SPELLS) do
            for _, list in pairs(set) do
                for _, spellID in ipairs(list) do wanted[spellID] = true end
            end
        end
        training = SM.TrainingInfo("MAGE", wanted)
    end
    return training[id] and training[id].level
end

-- "Teleport: Stormwind" -> "Stormwind". The game's own localized name; when a locale writes it
-- some other way, the whole name is kept.
function M.Destination(name)
    return name:match("^[^:]+:%s*(.+)$") or name
end

-- This character's sections: { { label, kind, rows = { entry, ... } }, ... }, and whether a
-- name was still loading (its row is left out until it arrives). An entry is { id, name, text
-- (the destination), icon, known, level, note, kind }. nil when the faction isn't known.
function M.Entries()
    local set = M.SPELLS[Faction() or ""]
    if not set then return nil, false end
    local sections, loading = {}, false
    for _, kind in ipairs(M.KINDS) do
        local list = {}
        for _, id in ipairs(set[kind.key]) do
            local name, icon = SM.Spell(id)
            if name then
                local level = M.TrainedAt(id)
                list[#list + 1] = { id = id, name = name, text = M.Destination(name), icon = icon,
                    known = SM.Known(id), level = level, note = level and ("Level " .. level), kind = kind }
            else
                loading = true
            end
        end
        sections[#sections + 1] = { label = kind.label, kind = kind, rows = list }
    end
    return sections, loading
end

local function LearnLines(tip, e)
    local K = SM.Palette()
    tip:AddLine(e.kind.one .. ", " .. (Faction() or "") .. " only", K.textDim[1], K.textDim[2], K.textDim[3])
    if e.level then
        local level = UnitLevel and SM.Plain(UnitLevel("player"))
        local c = (level and level >= e.level) and { 0.56, 0.70, 0.35 } or K.ember
        tip:AddLine(("Trained at level %d"):format(e.level), c[1], c[2], c[3])
    else
        tip:AddLine("Training level unavailable", K.stone[1], K.stone[2], K.stone[3])
    end
    tip:AddLine("Learning location unavailable", K.stone[1], K.stone[2], K.stone[3])
end

local launcher = SM.New({
    key = "mageTravel",
    name = "TwichUI Mage Travel",
    label = "Mage Travel",
    menuName = "TwichUIMageTravelMenu",
    icon = ICON,
    page = "mage",
    textKey = "mageTravelText",
    texts = M.TEXTS,
    defaultText = M.DEFAULT_TEXT,
    hint = "Click to choose a destination",
    empty = "No destinations for this character.",
    forPlayer = M.ForPlayer,
    entries = M.Entries,
    learnLines = LearnLines,
})
M.Open, M.Close, M.Toggle, M.IsOpen = launcher.Open, launcher.Close, launcher.Toggle, launcher.IsOpen
M.Available, M.Refresh = launcher.Available, launcher.Refresh
M.TextChoice, M.SetTextChoice = launcher.TextChoice, launcher.SetTextChoice
