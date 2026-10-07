-- TwichUI: new training at level-up
-- Reaching a level that opens up class spells or ranks you don't know yet shows a short
-- title card in the zone card's manner, with no frame: "New Training Available" over its
-- bronze rule, the spells and ranks beneath, and "Visit a class trainer". It says what a
-- trainer will offer; it never trains anything.
-- The spells come from modules/TrainingData.lua (What's Training?'s Forever data). Every
-- spell up to your new level that you could train and don't know is listed, including ones
-- from earlier levels you haven't been to a trainer for; when several ranks of one spell are
-- waiting, only the highest is shown. Only spells for your class, faction and race are
-- listed, and only when you have their required talent and earlier ranks (or those are
-- waiting too). Quick level-ups give one card. Nothing shows when there is nothing to train,
-- nothing at login or reload, and only the card's place (if moved) is stored. It waits for combat, banners and the zone card to pass and fades by itself.
-- It sits near the top of the screen, below the game's messages and the zone card, and
-- can be moved in Edit Mode. No sound, no chat.

local R = TwichUI
local T = {}
R.Training = T

local SETTLE = 2            -- seconds after a level-up before looking: quick level-ups become one card, and the spellbook catches up
local RETRY, RETRIES = 2, 5 -- while a banner or the zone card is up; then the card shows anyway (it sits below them)
local LOAD_WAIT = 3         -- seconds to wait for spell names the game hasn't loaded yet
local FADE_IN, FADE_OUT = 0.8, 1.4   -- the zone card's
local HOLD_BASE, HOLD_PER_ROW = 4, 0.6   -- seconds it stays: longer for a longer list (at most about 11)
local RISE = 8              -- pixels the card settles upward, as the zone card does (0 with Reduced motion)
local WIDTH = 520
local FONT_ROW = R.PATH .. [[media\fonts\AlegreyaSans-Bold.ttf]]   -- the spell lines; Alegreya itself has no bold cut
local ROW_HEIGHT = 20
local COLUMNS_FROM = 7      -- this many spells or more: two columns
local COLUMN_WIDTH = 230
local MAX_SHOWN = 12        -- more than this: "and N more"
local TOP_OFFSET = -260     -- default place: upper centre, below the error text, raid warnings and the zone card
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"   -- Edit Mode's own highlight, when the client has it

local pending = 0           -- bumped to drop a waiting look; a look only runs if it is still current
local pendingLevel          -- the level a waiting look is for
local lastLevel             -- the level last seen, so a repeated event adds nothing
local card
local active = {}           -- [event] = handler, while registered
local ev = CreateFrame("Frame")   -- the card's own short-lived events, apart from the shared bus

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return nil end
    return text
end

local function Escape(text) return (text:gsub("|", "||")) end

local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

---------------------------------------------------------------------------
-- What's new. Pure, so it can be checked on its own.
---------------------------------------------------------------------------

-- Spells the character could train at level `to` and doesn't know: those of every level up to
-- `to`, so ones from earlier levels that were never trained are included.
-- levels, ranks: as modules/TrainingData.lua builds them. who: { faction = "Alliance"|"Horde"|nil,
-- race = raceID|nil }; a spell limited to a faction or race is left out when that isn't known.
-- known(spellID): true when the game says the character has it.
-- Returns { { id = spellID, level = level }, ... } by level, each spell once. Every rank waiting
-- is returned; Rows() keeps only the highest of each spell for the card.
function T.Select(levels, ranks, to, who, known)
    local later = {}   -- [spellID] = { group, index }: a later rank in the group means this one is known
    for _, group in ipairs(ranks or {}) do
        for i, id in ipairs(group) do later[id] = { group, i } end
    end
    local function Direct(id)
        if known(id) then return true end
        local place = later[id]
        if not place then return false end
        for i = place[2] + 1, #place[1] do
            if known(place[1][i]) then return true end
        end
        return false
    end
    -- A spell is known too when one that needs it is: a rank can't be learned without the one before it,
    -- even if the spellbook stops listing the earlier rank.
    local implied, needs, stack = {}, {}, {}
    for _, list in pairs(levels) do
        for _, e in ipairs(list) do
            if e.req then
                needs[e[1]] = e.req
                if Direct(e[1]) then
                    for _, req in ipairs(e.req) do stack[#stack + 1] = req end
                end
            end
        end
    end
    while #stack > 0 do
        local id = table.remove(stack)
        if not implied[id] then
            implied[id] = true
            for _, req in ipairs(needs[id] or {}) do stack[#stack + 1] = req end
        end
    end
    local function Has(id) return implied[id] or Direct(id) end
    local function Fits(e)
        if e.faction and e.faction ~= who.faction then return false end
        if e.race then
            local match = false
            for _, race in ipairs(e.race) do
                if race == who.race then match = true end
            end
            if not match then return false end
        end
        if e.talent and not Has(e.talent) then return false end
        return not Has(e[1])
    end

    local picked, listed = {}, {}
    for level = 1, to do
        for _, e in ipairs(levels[level] or {}) do
            if not listed[e[1]] and Fits(e) then
                listed[e[1]] = true
                picked[#picked + 1] = { id = e[1], level = level, req = e.req }
            end
        end
    end
    -- Each earlier rank or prerequisite must be known, or waiting too (trained first, same visit).
    local changed = true
    while changed do
        changed = false
        for i = #picked, 1, -1 do
            for _, req in ipairs(picked[i].req or {}) do
                if not listed[req] and not Has(req) then
                    listed[picked[i].id] = nil
                    table.remove(picked, i)
                    changed = true
                    break
                end
            end
        end
    end
    for _, p in ipairs(picked) do p.req = nil end
    return picked
end

---------------------------------------------------------------------------
-- The game's side: who the character is and what it knows.
---------------------------------------------------------------------------
local function Known(id)
    local book = C_SpellBook
    if book and book.IsSpellKnown then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if bank then
            return book.IsSpellKnown(id, bank) or (book.IsSpellInSpellBook and book.IsSpellInSpellBook(id, bank, false)) or false
        end
        return book.IsSpellKnown(id) or false
    end
    return IsSpellKnown and IsSpellKnown(id) or false
end

local function Who()
    local faction = UnitFactionGroup and Plain((UnitFactionGroup("player")))
    local race = UnitRace and select(3, UnitRace("player"))
    if type(race) ~= "number" or (issecretvalue and issecretvalue(race)) then race = nil end
    return { faction = faction, race = race }
end

local function CurrentLevel()
    local level = UnitLevel and UnitLevel("player")
    if type(level) == "number" and level > 0 then return level end
end

-- What the bundled data says this character could train at the level, or {}.
-- The class's table is built for this look only and let go afterwards.
function T.ForLevel(level)
    local data = R.TrainingData
    local class = UnitClass and Plain((select(2, UnitClass("player"))))
    local build = data and class and data[class]
    if type(build) ~= "function" or type(level) ~= "number" or level < 1 then return {} end
    local levels, ranks = build()
    return T.Select(levels, ranks, level, Who(), Known)
end

-- Name, rank ("Rank 4", or nil) and icon, or nil when the game doesn't give a name.
local function Describe(id)
    local spell = C_Spell
    local name = spell and spell.GetSpellName and Plain(spell.GetSpellName(id))
    if not name then return nil end
    local rank = spell.GetSpellSubtext and Plain(spell.GetSpellSubtext(id))
    local icon = spell.GetSpellTexture and spell.GetSpellTexture(id)
    if type(icon) ~= "number" and type(icon) ~= "string" then icon = nil end
    return name, rank, icon
end

-- Ranks of one spell share its name; a few (poisons) add a numeral, "Instant Poison II".
local function SpellKey(name)
    return name:match("^(.-)%s+[IVX]+$") or name
end

-- Rows for the card: only spells the game can name, and one row per spell, its highest rank
-- waiting (entries come by level, so a later one is a higher rank). Listed by level.
local function Rows(entries)
    local rows, at = {}, {}
    for _, e in ipairs(entries) do
        local name, rank, icon = Describe(e.id)
        if name then
            local key = SpellKey(name)
            if at[key] then rows[at[key]] = false end
            rows[#rows + 1] = { id = e.id, level = e.level, name = name, rank = rank, icon = icon }
            at[key] = #rows
        end
    end
    local out = {}
    for _, row in ipairs(rows) do
        if row then out[#out + 1] = row end
    end
    return out
end

-- Asks for the names the game hasn't loaded, then calls done() once: when all have arrived
-- (a frame later, as a rank's text can lag its name) or after LOAD_WAIT, whichever is first.
local loadToken = 0
local waiting, waitingCount = {}, 0
local function LoadNames(entries, done)
    loadToken = loadToken + 1
    local mine = loadToken
    wipe(waiting)
    waitingCount = 0
    local function Finish()
        if loadToken ~= mine then return end
        loadToken = loadToken + 1
        ev:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
        wipe(waiting)
        done()
    end
    ev.onLoaded = function(id)
        if loadToken ~= mine or not waiting[id] then return end
        waiting[id] = nil
        waitingCount = waitingCount - 1
        if waitingCount == 0 then C_Timer.After(0, Finish) end
    end
    local spell = C_Spell
    if spell and spell.IsSpellDataCached and spell.RequestLoadSpellData then
        for _, e in ipairs(entries) do
            if not waiting[e.id] and not spell.IsSpellDataCached(e.id) then
                waiting[e.id] = true
                waitingCount = waitingCount + 1
            end
        end
        if waitingCount > 0 then
            ev:RegisterEvent("SPELL_DATA_LOAD_RESULT")   -- the result can arrive during the request itself
            for id in pairs(waiting) do spell.RequestLoadSpellData(id) end
        end
    end
    C_Timer.After(waitingCount > 0 and LOAD_WAIT or 0, Finish)
end

---------------------------------------------------------------------------
-- Where it goes: the top edge's offset from the top centre of the screen, as moved in Edit
-- Mode (TwichUIDB.ui.trainingPosition), or the default. The card grows downward from there.
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end

function T.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.trainingPosition
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return 0, TOP_OFFSET
end

local function Place(frame)
    local x, y = T.Position()
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", x, y)
end

---------------------------------------------------------------------------
-- The card. No frame or backdrop, like the zone card: the heading, the bronze rule, the
-- spells, and a quiet line saying where to learn them. It takes no clicks, so the world
-- beneath it stays clickable. Made the first time it is needed.
---------------------------------------------------------------------------
local function Hide()
    if not card then return end
    card.anim:Stop()
    card:Hide()
    card.rows = nil
    ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

-- True while the card is on screen (the Welcome Back bookmark waits for it).
function T.IsShowing() return card ~= nil and card:IsShown() end

-- How long it stays: a little longer for each spell, so a long list can be read.
local function Hold(rows) return HOLD_BASE + HOLD_PER_ROW * rows end

-- "Frostbolt  Rank 3", the rank in stone; with the level after it when several levels were crossed.
local function Label(row, multiLevel)
    local stone = Hex(card.K.stone)
    local text = Escape(row.name)
    if row.rank then text = text .. "  " .. stone .. Escape(row.rank) .. "|r" end
    if multiLevel then text = text .. stone .. ("  ·  level %d"):format(row.level) .. "|r" end
    return text
end

-- A line of text with the zone card's shadow, which keeps it readable without a backdrop.
local function Text(parent, path, size, fallback, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    R.Arrival.SetFont(fs, path, size, fallback)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Width(fs)
    local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    return type(width) == "number" and width or 0
end

local function Row(i)
    local row = card.rowFrames[i]
    if row then return row end
    row = CreateFrame("Frame", nil, card.list)
    row:SetHeight(ROW_HEIGHT)
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetColorTexture(0, 0, 0, 0.6)   -- a dark edge keeps the icon clear over bright ground
    edge:SetSize(18, 18)
    edge:SetPoint("LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("CENTER", edge, "CENTER", 0, 0)
    row.text = Text(row, FONT_ROW, 15, "GameFontHighlight", card.K.text)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.text:SetPoint("LEFT", edge, "RIGHT", 6, 0)
    card.rowFrames[i] = row
    return row
end

-- Lays out the spells: one centred column, or two when there are many. Returns how many are shown.
local function Layout(rows)
    local shown = math.min(#rows, MAX_SHOWN)
    local columns = #rows >= COLUMNS_FROM and 2 or 1
    local perColumn = math.ceil(shown / columns)
    local multiLevel = rows[1].level ~= rows[#rows].level
    for _, row in ipairs(card.rowFrames) do row:Hide() end
    for i = 1, shown do
        local data, row = rows[i], Row(i)
        local column, line = math.floor((i - 1) / perColumn), (i - 1) % perColumn
        row.icon:SetTexture(data.icon)
        row.text:SetWidth(0)
        row.text:SetText(Label(data, multiLevel))
        row:ClearAllPoints()
        if columns == 1 then
            local width = math.min(Width(row.text), WIDTH - 60)
            row.text:SetWidth(width)
            row:SetWidth(24 + width)
            row:SetPoint("TOP", card.list, "TOP", 0, -line * ROW_HEIGHT)
        else
            row.text:SetWidth(COLUMN_WIDTH - 24)
            row:SetWidth(COLUMN_WIDTH)
            row:SetPoint("TOPLEFT", card.list, "TOP", column == 0 and -COLUMN_WIDTH - 6 or 6, -line * ROW_HEIGHT)
        end
        row:Show()
    end
    card.list:SetHeight(perColumn * ROW_HEIGHT)
    card:SetHeight(64 + perColumn * ROW_HEIGHT)
    return shown
end

local function Build()
    local S, A = R.ChronicleStyle, R.Arrival
    if not (S and A and A.Rule and A.SetFont) then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, 120)
    Place(card)
    card:SetClampedToScreen(true)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K
    card.rowFrames = {}

    card.title = Text(card, A.FONT_TITLE, 18, "SubZoneTextFont", K.text)
    card.title:SetPoint("TOP", 0, 0)
    card.title:SetText("New Training Available")
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(110)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -6)
    card.list = CreateFrame("Frame", nil, card)
    card.list:SetSize(WIDTH, ROW_HEIGHT)
    card.list:SetPoint("TOP", card.rule, "BOTTOM", 0, -10)
    card.foot = Text(card, A.FONT_LINE, 13, "GameFontHighlightSmall", K.stone)
    card.foot:SetPoint("TOP", card.list, "BOTTOM", 0, -8)

    -- The zone card's motion: lowered at once, rising into place as it fades in, then fading away.
    local anim = card:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    card.drop = anim:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = anim:CreateAnimation("Translation")
    card.rise:SetSmoothing("OUT")
    card.rise:SetDuration(FADE_IN)
    card.rise:SetOrder(1)
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetSmoothing("OUT")
    fadeIn:SetDuration(FADE_IN)
    fadeIn:SetOrder(1)
    card.fadeOut = anim:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1)
    card.fadeOut:SetToAlpha(0)
    card.fadeOut:SetSmoothing("IN")
    card.fadeOut:SetDuration(FADE_OUT)
    card.fadeOut:SetOrder(2)
    anim:SetScript("OnFinished", Hide)
    card.anim = anim
    return true
end

local function Show(rows)
    if not card and not Build() then return end
    Hide()
    Place(card)
    card.rows = rows
    local shown = Layout(rows)
    local more = #rows - shown
    card.foot:SetText(more > 0 and ("and %d more  ·  Visit a class trainer"):format(more) or "Visit a class trainer")

    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card.fadeOut:SetStartDelay(Hold(shown))
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")   -- makes way for combat
end

---------------------------------------------------------------------------
-- When to look, and when to show it.
---------------------------------------------------------------------------
local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

-- A banner or the zone card is up: let it finish first.
local function Busy()
    if R.Arrival and R.Arrival.IsShowing and R.Arrival.IsShowing() then return true end
    return Toasting()
end

local Schedule

local function Try(tries, mine)
    if pending ~= mine or not R:Enabled("trainingNotice") or not pendingLevel then return end
    if InCombatLockdown and InCombatLockdown() then
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if Busy() and tries < RETRIES then
        C_Timer.After(RETRY, function() Try(tries + 1, mine) end)
        return
    end
    local entries = T.ForLevel(pendingLevel)
    if #entries == 0 then
        pendingLevel = nil
        return
    end
    LoadNames(entries, function()
        if pending ~= mine then return end
        pendingLevel = nil
        local rows = Rows(entries)
        if #rows > 0 then Show(rows) end
    end)
end

function Schedule(delay)
    pending = pending + 1
    local mine = pending
    ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.After(delay, function() Try(0, mine) end)
end

ev:SetScript("OnEvent", function(_, event, id)
    if event == "PLAYER_REGEN_DISABLED" then
        Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Schedule(1)
    elseif event == "SPELL_DATA_LOAD_RESULT" and ev.onLoaded then
        ev.onLoaded(id)
    end
end)

local function OnLevelUp(level)
    if type(level) ~= "number" then return end
    if lastLevel and level <= lastLevel then return end   -- already seen
    lastLevel = level
    pendingLevel = level   -- a card still up is replaced by the new one, which lists everything waiting
    Schedule(SETTLE)
end

-- Drops anything waiting and takes the card down.
local function Drop()
    pending = pending + 1
    loadToken = loadToken + 1
    pendingLevel = nil
    ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ev:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
    Hide()
end

-- A login, reload or loading screen is never a level-up; it only says where the level now stands.
local function OnEnteringWorld()
    lastLevel = CurrentLevel() or lastLevel
end

-- /tui training [level]: shows the card as it would be on reaching a level now (your own by default),
-- from the same data and checks, so it can be looked at without levelling. Skips the combat and
-- banner checks (the player asked) but still lists only what applies. Returns true, or false and a reason.
function T.Preview(level)
    level = level or CurrentLevel()
    if not level or level < 1 then return false, "That isn't a level TwichUI can look at." end
    local entries = T.ForLevel(level)
    if #entries == 0 then
        return false, ("Nothing to train up to level %d that you don't already know."):format(level)
    end
    LoadNames(entries, function()
        local rows = Rows(entries)
        if #rows > 0 then Show(rows) else R.Print("The game didn't give names for the training up to level %d, so there is nothing to show.", level) end
    end)
    return true
end

---------------------------------------------------------------------------
-- Moving it in Edit Mode. The game's Edit Mode has no place for addon frames, so while it is
-- open a TwichUI outline stands where the card appears: drag it to move the card, right-click
-- it to put it back. The place is kept at once, whatever Edit Mode's own Save or Revert does
-- with its layouts, and is the same for every character.
---------------------------------------------------------------------------
local mover
local editHooked = false

local function SavePosition(x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.trainingPosition = x and { x = x, y = y } or nil
    Place(mover)
    if card then Place(card) end
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(WIDTH, 120)   -- about the size of a card with a few spells
    mover:SetFrameStrata("MEDIUM")
    mover:SetFrameLevel(1000)
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    if mover.SetDontSavePosition then mover:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    mover:Hide()
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MOVER_ATLAS) then
        fill:SetAtlas(MOVER_ATLAS)
    else
        local K = R.ChronicleStyle and R.ChronicleStyle.color
        local c = K and K.bronze or { 0.55, 0.43, 0.22 }
        fill:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText("New Training")
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top, width = self:GetLeft(), self:GetTop(), self:GetWidth()
        local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
        if not (left and top and width and parentWidth and parentHeight) then Place(self) return end
        SavePosition(math.floor(left + width / 2 - parentWidth / 2 + 0.5), math.floor(top - parentHeight + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then SavePosition(nil) end
    end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: New Training", 1, 1, 1)
        GameTooltip:AddLine("Where the card appears after a level-up. Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

-- Shows the outline while Edit Mode is open and the notice is on.
local function ShowMover(shown)
    if shown and R:Enabled("trainingNotice") then
        if not mover then BuildMover() end
        Place(mover)
        mover:Show()
    elseif mover then
        mover:StopMovingOrSizing()
        mover:Hide()
    end
end

local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, T)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, T)
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Listens for level-ups only while the notice is on. Safe to call any time.
function T.Refresh()
    local on = R:Enabled("trainingNotice")
    if on and not active.PLAYER_LEVEL_UP then lastLevel = CurrentLevel() end
    Want("PLAYER_LEVEL_UP", OnLevelUp, on)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    Want("PLAYER_LEAVING_WORLD", Drop, on)
    if not on then Drop() end
    HookEditMode()
    ShowMover(on and EditModeActive())
end

R:OnInit(T.Refresh)
