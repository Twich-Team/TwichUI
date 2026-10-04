-- TwichUI: new training at level-up
-- Reaching a level that opens up class spells or ranks you don't know yet shows one
-- small card: "New Training Available" over the arrival card's bronze rule, then
-- "Fireball  Rank 4  ·  Visit a class trainer" (or "4 spells  ·  ..." with a list to
-- open). It says what a trainer will offer; it never trains anything.
-- The spells come from modules/TrainingData.lua (What's Training?'s Forever data). Only
-- spells for your class, faction and race are listed, and only when you have their
-- required talent and earlier ranks (or those are on the same card) and don't already
-- know them. Gaining several levels at once gives one card covering every level crossed.
-- Nothing shows when no new training applies, nothing at login or reload, and nothing
-- is stored. It waits for combat, banners and the zone card to pass and fades by itself.
-- It sits near the top of the screen, below the game's messages and the zone card, and
-- can be moved in Edit Mode. No sound, no chat.

local R = TwichUI
local T = {}
R.Training = T

local SETTLE = 2            -- seconds after a level-up before looking: quick level-ups become one card, and the spellbook catches up
local RETRY, RETRIES = 2, 5 -- while a banner or the zone card is up; then the card shows anyway (it sits below them)
local LOAD_WAIT = 3         -- seconds to wait for spell names the game hasn't loaded yet
local FADE_IN, FADE_OUT = 0.6, 1.2
local HOLD = 12             -- seconds the card stays
local READ_HOLD = 20        -- ... with its list open
local LEAVE_HOLD = 4        -- ... after the pointer leaves it, list closed
local RISE = 6              -- pixels the card settles upward (0 with Reduced motion)
local WIDTH = 400
local ROW_HEIGHT = 18
local COLUMNS_FROM = 9      -- this many spells or more: two columns
local MAX_SHOWN = 16        -- more than this: "and N more"
local TOP_OFFSET = -260     -- default place: upper centre, below the error text, raid warnings and the zone card
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"   -- Edit Mode's own highlight, when the client has it

local pending = 0           -- bumped to drop a waiting look; a look only runs if it is still current
local rangeFrom, rangeTo    -- levels waiting to be looked at: above rangeFrom, up to rangeTo
local lastLevel             -- the level last seen, so a repeated event adds nothing
local shownFrom             -- while a level-up card is up: the level it starts above
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

-- Spells that become trainable on reaching `to` from `from` (every level above `from`, up to `to`).
-- levels, ranks: as modules/TrainingData.lua builds them. who: { faction = "Alliance"|"Horde"|nil,
-- race = raceID|nil }; a spell limited to a faction or race is left out when that isn't known.
-- known(spellID): true when the character has it.
-- Returns { { id = spellID, level = level }, ... } by level, each spell once.
function T.Select(levels, ranks, from, to, who, known)
    local later = {}   -- [spellID] = { group, index }: a later rank in the group means this one is known
    for _, group in ipairs(ranks or {}) do
        for i, id in ipairs(group) do later[id] = { group, i } end
    end
    local function Has(id)
        if known(id) then return true end
        local place = later[id]
        if not place then return false end
        for i = place[2] + 1, #place[1] do
            if known(place[1][i]) then return true end
        end
        return false
    end
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
    for level = from + 1, to do
        for _, e in ipairs(levels[level] or {}) do
            if not listed[e[1]] and Fits(e) then
                listed[e[1]] = true
                picked[#picked + 1] = { id = e[1], level = level, req = e.req }
            end
        end
    end
    -- Each earlier rank or prerequisite must be known, or on this card too (trained first, same visit).
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

-- What the bundled data says is new for this character between the two levels, or {}.
-- The class's table is built for this look only and let go afterwards.
function T.ForRange(from, to)
    local data = R.TrainingData
    local class = UnitClass and Plain((select(2, UnitClass("player"))))
    local build = data and class and data[class]
    if type(build) ~= "function" or type(from) ~= "number" or type(to) ~= "number" or to <= from then return {} end
    local levels, ranks = build()
    return T.Select(levels, ranks, from, to, Who(), Known)
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

-- Rows for the card: only spells the game can name, and no two that read the same.
local function Rows(entries)
    local rows, seen = {}, {}
    for _, e in ipairs(entries) do
        local name, rank, icon = Describe(e.id)
        local key = name and (name .. "\n" .. (rank or ""))
        if key and not seen[key] then
            seen[key] = true
            rows[#rows + 1] = { id = e.id, level = e.level, name = name, rank = rank, icon = icon }
        end
    end
    return rows
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
-- The card. Made the first time it is needed.
---------------------------------------------------------------------------
local Hover   -- defined below; every part of the card that takes the pointer calls it

local function Linger(seconds)
    card.exit:Stop()
    card:SetAlpha(1)
    card.fadeOut:SetStartDelay(seconds)
    card.exit:Play()
end

-- The pointer on the card (or anything on it) holds it; leaving starts the countdown again.
function Hover()
    if not (card and card:IsShown()) or card.enter:IsPlaying() then return end
    if card:IsMouseOver() then
        card.exit:Stop()
        card:SetAlpha(1)
    elseif not card.exit:IsPlaying() then
        Linger(card.listOpen and READ_HOLD or LEAVE_HOLD)
    end
end

local function Hide()
    if not card then return end
    card.enter:Stop()
    card.exit:Stop()
    card:Hide()
    card.rows = nil
    shownFrom = nil
    ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

function T.Dismiss() Hide() end

-- True while the card is on screen (the Welcome Back bookmark waits for it).
function T.IsShowing() return card ~= nil and card:IsShown() end

local function Label(row)
    local text = Escape(row.name)
    if row.rank then text = text .. "  " .. Hex(card.K.stone) .. Escape(row.rank) .. "|r" end
    return text
end

local function Row(i)
    local row = card.rowFrames[i]
    if row then return row end
    local A, K = R.Arrival, card.K
    row = CreateFrame("Button", nil, card.list)
    row:SetHeight(ROW_HEIGHT)
    local frame = row:CreateTexture(nil, "ARTWORK")
    frame:SetColorTexture(K.bronzeLo[1], K.bronzeLo[2], K.bronzeLo[3], 1)
    frame:SetSize(16, 16)
    frame:SetPoint("LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    row.level = row:CreateFontString(nil, "OVERLAY")
    A.SetFont(row.level, A.FONT_LINE, 12, "GameFontHighlightSmall")
    row.level:SetJustifyH("RIGHT")
    row.level:SetPoint("RIGHT", -2, 0)
    row.level:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    row.text = row:CreateFontString(nil, "OVERLAY")
    A.SetFont(row.text, A.FONT_LINE, 13, "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.text:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.text:SetTextColor(K.text[1], K.text[2], K.text[3])
    row:SetScript("OnEnter", function(self)
        if GameTooltip and self.id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.id)
            GameTooltip:Show()
        end
        Hover()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        Hover()
    end)
    card.rowFrames[i] = row
    return row
end

-- Closed: the heading and one line. Open: the list beneath it as well, in two columns when long.
local function Layout(open)
    local rows = card.rows
    local many = #rows > 1
    card.listOpen = open and many
    card.toggle:SetShown(many)
    card.toggle.text:SetText(card.listOpen and "Hide list" or "Show list")
    for _, row in ipairs(card.rowFrames) do row:Hide() end
    if not card.listOpen then
        card.list:Hide()
        card:SetHeight(many and 86 or 72)
        return
    end
    local shown = math.min(#rows, MAX_SHOWN)
    local columns = #rows >= COLUMNS_FROM and 2 or 1
    local perColumn = math.ceil(shown / columns)
    local listWidth = WIDTH - 48
    local columnWidth = math.floor(listWidth / columns)
    local multiLevel = rows[1].level ~= rows[#rows].level
    for i = 1, shown do
        local data, row = rows[i], Row(i)
        local column, line = math.floor((i - 1) / perColumn), (i - 1) % perColumn
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card.list, "TOPLEFT", column * columnWidth, -line * ROW_HEIGHT)
        row:SetWidth(columnWidth - 8)
        row.id = data.id
        row.icon:SetTexture(data.icon)
        row.text:SetText(Label(data))
        row.level:SetText(multiLevel and ("Level %d"):format(data.level) or "")
        row:Show()
    end
    local more = #rows - shown
    card.more:SetText(more > 0 and ("and %d more at your trainer"):format(more) or "")
    card.more:SetShown(more > 0)
    card.list:SetHeight(perColumn * ROW_HEIGHT + (more > 0 and 16 or 0))
    card.list:Show()
    card:SetHeight(100 + perColumn * ROW_HEIGHT + (more > 0 and 16 or 0))
end

local function ToggleList()
    if not card.rows then return end
    Layout(not card.listOpen)
    Hover()
end

local function Build()
    local S, A = R.ChronicleStyle, R.Arrival
    if not (S and A and A.Rule and A.SetFont) then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    card:SetSize(WIDTH, 86)
    Place(card)
    card:SetClampedToScreen(true)
    card:SetFrameStrata("MEDIUM")
    card:EnableMouse(true)
    card:Hide()
    card.K = K
    card.rowFrames = {}
    S.Frame(card, WIDTH, 72)   -- the collapsed size; the frame grows downward from its top

    card.title = card:CreateFontString(nil, "OVERLAY")
    A.SetFont(card.title, A.FONT_TITLE, 15, "GameFontNormal")
    card.title:SetPoint("TOP", 0, -14)
    card.title:SetTextColor(K.text[1], K.text[2], K.text[3])
    card.title:SetShadowColor(0, 0, 0, 0.85)
    card.title:SetShadowOffset(1, -1)
    card.title:SetText("New Training Available")
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(110)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -6)
    card.summary = card:CreateFontString(nil, "OVERLAY")
    A.SetFont(card.summary, A.FONT_LINE, 14, "GameFontHighlight")
    card.summary:SetWidth(WIDTH - 60)
    card.summary:SetWordWrap(false)
    card.summary:SetJustifyH("CENTER")
    card.summary:SetPoint("TOP", card.rule, "BOTTOM", 0, -6)
    card.summary:SetTextColor(K.stone[1], K.stone[2], K.stone[3])

    card.list = CreateFrame("Frame", nil, card)
    card.list:SetWidth(WIDTH - 48)
    card.list:SetPoint("TOP", card.summary, "BOTTOM", 0, -10)
    card.more = card.list:CreateFontString(nil, "OVERLAY")
    A.SetFont(card.more, A.FONT_LINE, 12, "GameFontHighlightSmall")
    card.more:SetPoint("BOTTOMLEFT", 22, 0)
    card.more:SetTextColor(K.stone[1], K.stone[2], K.stone[3])

    card.toggle = S.Link(card, "Show list", ToggleList, K.gold, K.text)
    card.toggle:SetSize(80, 14)
    card.toggle:SetPoint("BOTTOMRIGHT", -12, 9)
    card.close = S.Close(card, T.Dismiss)
    card.close:SetPoint("TOPRIGHT", -8, -8)
    card:SetScript("OnEnter", Hover)
    card:SetScript("OnLeave", Hover)
    for _, button in ipairs({ card.toggle, card.close }) do
        button:HookScript("OnEnter", Hover)
        button:HookScript("OnLeave", Hover)
    end

    -- Settles in as the other TwichUI cards do: lowered at once, then rising into place as it fades in.
    local enter = card:CreateAnimationGroup()
    enter:SetToFinalAlpha(true)
    card.drop = enter:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = enter:CreateAnimation("Translation")
    card.rise:SetSmoothing("OUT")
    card.rise:SetDuration(FADE_IN)
    card.rise:SetOrder(1)
    local fadeIn = enter:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetSmoothing("OUT")
    fadeIn:SetDuration(FADE_IN)
    fadeIn:SetOrder(1)
    enter:SetScript("OnFinished", function()
        card:SetAlpha(1)
        if not card:IsMouseOver() then Linger(HOLD) end
    end)
    card.enter = enter
    -- Stays a while, then fades; kept apart from the entrance so the pointer can hold it.
    local exit = card:CreateAnimationGroup()
    exit:SetToFinalAlpha(true)
    card.fadeOut = exit:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1)
    card.fadeOut:SetToAlpha(0)
    card.fadeOut:SetSmoothing("IN")
    card.fadeOut:SetDuration(FADE_OUT)
    exit:SetScript("OnFinished", Hide)
    card.exit = exit
    return true
end

-- fold: the level the card starts above, for a real level-up; a newer level-up while it is up adds to it.
local function Show(rows, fold)
    if not card and not Build() then return end
    Hide()
    Place(card)
    card.rows = rows
    local K = card.K
    if #rows == 1 then
        card.summary:SetText(Hex(K.text) .. Label(rows[1]) .. "|r  ·  Visit a class trainer")
    else
        card.summary:SetText(("%d spells  ·  Visit a class trainer"):format(#rows))
    end
    Layout(false)

    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card:SetAlpha(0)
    card:Show()
    card.enter:Play()
    shownFrom = fold
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
    if pending ~= mine or not R:Enabled("trainingNotice") or not rangeTo then return end
    if InCombatLockdown and InCombatLockdown() then
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if Busy() and tries < RETRIES then
        C_Timer.After(RETRY, function() Try(tries + 1, mine) end)
        return
    end
    local from, to = rangeFrom, rangeTo
    local entries = T.ForRange(from, to)
    if #entries == 0 then
        rangeFrom, rangeTo = nil, nil
        return
    end
    LoadNames(entries, function()
        if pending ~= mine then return end
        rangeFrom, rangeTo = nil, nil
        local rows = Rows(entries)
        if #rows > 0 then Show(rows, from) end
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
    local from = lastLevel or level - 1
    if level <= from then return end   -- already seen
    lastLevel = level
    if shownFrom then from = math.min(from, shownFrom) end   -- a card still up is folded into the new one
    rangeFrom = math.min(rangeFrom or from, from)
    rangeTo = math.max(rangeTo or level, level)
    Schedule(SETTLE)
end

-- Drops anything waiting and takes the card down.
local function Drop()
    pending = pending + 1
    loadToken = loadToken + 1
    rangeFrom, rangeTo = nil, nil
    ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ev:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
    Hide()
end

-- A login, reload or loading screen is never a level-up; it only says where the level now stands.
local function OnEnteringWorld()
    lastLevel = CurrentLevel() or lastLevel
end

-- /tui training [level | from-to]: shows the card for reaching a level now (your own by default),
-- from the same data and checks, so it can be looked at without levelling. Skips the combat and
-- banner checks (the player asked) but still lists only what applies. Returns true, or false and a reason.
function T.Preview(from, to)
    to = to or CurrentLevel()
    from = from or (to and to - 1)
    if not to or not from or from < 0 or to <= from then return false, "That isn't a level range TwichUI can look at." end
    local entries = T.ForRange(from, to)
    local span = to - from == 1 and ("level %d"):format(to) or ("levels %d to %d"):format(from + 1, to)
    if #entries == 0 then
        return false, ("Nothing new to train for %s, or you already know it."):format(span)
    end
    LoadNames(entries, function()
        local rows = Rows(entries)
        if #rows > 0 then Show(rows) else R.Print("The game didn't give names for the training at %s, so there is nothing to show.", span) end
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
    mover:SetSize(WIDTH, 86)
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
