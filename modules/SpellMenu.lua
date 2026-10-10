-- TwichUI: spell menus on a data bar
-- The shared part of the class spell launchers (Mage Travel, Mage Conjuring): a LibDataBroker
-- data object that opens a small menu of spells in sections. Learned spells are cast by clicking
-- them; ones not yet learned stay readable but muted, and their tooltip says how they are learned.
-- TwichUI never casts by itself: each row is the game's own secure action button, and the click
-- is the player's.
-- Each row's spell is set only out of combat, so a menu doesn't open in combat and closes as
-- combat starts. Its contents are read from the game each time it opens, and again while it is
-- open when spells are learned, the character levels up or spell data arrives; it listens only
-- while open.
-- A launcher can also have shift-click shortcuts that cast a spell straight from the data bar.
-- A data bar's click handler is ordinary addon code, which can't cast, so while the mouse is on
-- the launcher a secure button of TwichUI's lies exactly over it: shift-clicks cast through it,
-- and any other click goes on to the launcher as before. It is placed, filled and shown only out
-- of combat, and put away as combat starts.
-- TwichUI doesn't bundle LibDataBroker: a launcher is made once a data bar addon provides it, and
-- nothing happens when none does. The data bar text is the player's choice, saved in TwichUIDB.ui.
-- The menu's background and border are the player's too (modules/MenuStyle.lua, shared by every
-- menu). They are drawn when the menu opens, and again while it is open when they change, never in
-- combat (the rows are anchored to the menu, so its size and padding change only out of combat).

local R = TwichUI
local MenuStyle = R.MenuStyle
local SM = {}
R.SpellMenu = SM

local WIDTH = 220
local PAD = 8
local TITLE_HEIGHT = 26
local HEADER_HEIGHT = 20
local ROW_HEIGHT = 24
local ICON_SIZE = 18
local SECTION_GAP = 6
local SETTLE = 0.2   -- seconds: a burst of spellbook events becomes one redraw
local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
local FONT_HEADER = R.PATH .. [[media\fonts\AlegreyaSansSC-Bold.ttf]]
local FONT_ROW = R.PATH .. [[media\fonts\AlegreyaSans-Medium.ttf]]
local FONT_NOTE = R.PATH .. [[media\fonts\AlegreyaSans-Regular.ttf]]

-- A muted arcane violet for the small accents; everything else is the Chronicle's palette.
local ARCANE = { 0.56, 0.50, 0.78 }

function SM.Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local Plain = SM.Plain

local function InCombat() return InCombatLockdown and InCombatLockdown() end

function SM.Palette()
    local style = R.ChronicleStyle and R.ChronicleStyle.color
    return style or {
        bg = { 0.150, 0.115, 0.082 }, well = { 0.112, 0.084, 0.060 }, band = { 0.200, 0.150, 0.100 },
        text = { 0.93, 0.88, 0.76 }, textDim = { 0.78, 0.74, 0.66 }, stone = { 0.62, 0.58, 0.51 },
        bronze = { 0.55, 0.43, 0.22 }, bronzeLo = { 0.30, 0.23, 0.13 }, gold = { 0.79, 0.64, 0.29 },
        ember = { 0.74, 0.40, 0.32 },
    }
end
local Palette = SM.Palette

function SM.PlayerClass()
    local _, class = UnitClass("player")
    return Plain(class)
end

-- The same test modules/Training.lua uses.
function SM.Known(id)
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

-- What the training data (modules/TrainingData.lua) says about some of a class's spells:
-- { [spellID] = { level = trained at, req = { spellIDs } or nil } } for the IDs in `wanted`
-- ({ [spellID] = true }). The class's whole table is built for this and let go afterwards.
function SM.TrainingInfo(class, wanted)
    local info = {}
    local build = R.TrainingData and R.TrainingData[class]
    local ok, levels = false, nil
    if type(build) == "function" then ok, levels = pcall(build) end
    if ok and type(levels) == "table" then
        for level, list in pairs(levels) do
            for _, e in ipairs(list) do
                if wanted[e[1]] then info[e[1]] = { level = level, req = e.req } end
            end
        end
    end
    return info
end

-- The game's name and icon for a spell, or nil when its name hasn't loaded yet (then it is
-- asked for, and the open menu redraws when it arrives).
function SM.Spell(id)
    local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
    if not name then
        if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
        return nil
    end
    local icon = C_Spell.GetSpellTexture and Plain(C_Spell.GetSpellTexture(id))
    return name, icon
end

-- The game's rank text ("Rank 3") when it gives one, otherwise "Rank <rank>" (nil without one).
function SM.RankText(id, rank)
    local sub = C_Spell and C_Spell.GetSpellSubtext and Plain(C_Spell.GetSpellSubtext(id))
    if type(sub) == "string" and sub ~= "" then return sub end
    return rank and ("Rank %d"):format(rank) or nil
end

-- A frame's place on screen in UIParent's units: left, bottom, width, height, or nil.
local function ScreenRect(frame)
    local left, bottom, width, height
    if frame and frame.GetRect then left, bottom, width, height = frame:GetRect() end
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    local ui = UIParent:GetEffectiveScale()
    if not (left and bottom and width and height and scale and ui and ui > 0) then return nil end
    local k = scale / ui
    return left * k, bottom * k, width * k, height * k
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local function SetFont(fs, path, size, fallback)
    if R.Arrival and R.Arrival.SetFont then
        R.Arrival.SetFont(fs, path, size, fallback)
    else
        local font = _G[fallback]
        local file = font and font.GetFont and font:GetFont()
        fs:SetFont(file or STANDARD_TEXT_FONT, size)
    end
end

local function Text(parent, path, size, fallback)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFont(fs, path, size, fallback)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- A short local message where the game shows its own "can't do that" messages. Never chat.
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

---------------------------------------------------------------------------
-- A sample menu for the options page, to judge the appearance settings by: the same look on a
-- frame that does nothing. It has no secure rows, takes no mouse and casts nothing, and is shown
-- only when asked for, until it is asked away or Esc closes it.
---------------------------------------------------------------------------
local preview
local SAMPLE = { { "Stormwind", true }, { "Ironforge", true }, { "Darnassus", false, "Level 20" } }

local function BuildPreview()
    local K = Palette()
    preview = CreateFrame("Frame", "TwichUIMenuPreview", UIParent, "BackdropTemplate")
    preview:SetWidth(WIDTH)
    preview:SetFrameStrata("DIALOG")
    preview:SetClampedToScreen(true)
    preview:Hide()
    preview.title = Text(preview, FONT_TITLE, 13, "GameFontNormal")
    preview.title:SetText("Menu preview")
    preview.title:SetTextColor(K.text[1], K.text[2], K.text[3])
    preview.header = Text(preview, FONT_HEADER, 12, "GameFontNormalSmall")
    preview.header:SetText("Teleports")
    preview.header:SetTextColor(K.gold[1], K.gold[2], K.gold[3])
    preview.rows = {}
    for i, sample in ipairs(SAMPLE) do
        local row = CreateFrame("Frame", nil, preview)
        row:SetHeight(ROW_HEIGHT)
        local rim = Solid(row, "ARTWORK", sample[2] and ARCANE or K.bronzeLo, sample[2] and 0.75 or 1)
        rim:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
        rim:SetPoint("LEFT", 4, 0)
        local well = Solid(row, "ARTWORK", K.well)
        well:SetDrawLayer("ARTWORK", 1)
        well:SetSize(ICON_SIZE, ICON_SIZE)
        well:SetPoint("CENTER", rim, "CENTER")
        local note = Text(row, FONT_NOTE, 12, "GameFontNormalSmall")
        note:SetPoint("RIGHT", -6, 0)
        note:SetJustifyH("RIGHT")
        note:SetText(sample[3] or "")
        note:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
        local name = Text(row, FONT_ROW, 14, "GameFontNormal")
        name:SetPoint("LEFT", rim, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", note, "LEFT", -6, 0)
        name:SetText(sample[1])
        local c = sample[2] and K.text or K.stone
        name:SetTextColor(c[1], c[2], c[3])
        preview.rows[i] = row
    end
    if UISpecialFrames then tinsert(UISpecialFrames, "TwichUIMenuPreview") end
end

-- The look and layout of the real menu (the border can widen the margin).
local function DrawPreview()
    local pad = math.max(PAD, math.ceil(MenuStyle.Apply(preview)))
    preview.title:ClearAllPoints()
    preview.title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
    local y = -(pad + TITLE_HEIGHT)
    preview.header:ClearAllPoints()
    preview.header:SetPoint("TOPLEFT", preview, "TOPLEFT", pad + 4, y - 4)
    y = y - HEADER_HEIGHT - 2
    for _, row in ipairs(preview.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", preview, "TOPLEFT", pad, y)
        row:SetPoint("RIGHT", preview, "RIGHT", -pad, 0)
        y = y - ROW_HEIGHT
    end
    preview:SetHeight(-(y - SECTION_GAP) + pad)
end

function SM.PreviewShown() return preview ~= nil and preview:IsShown() end

-- Shows the sample beside the options window, or puts it away.
function SM.TogglePreview()
    if SM.PreviewShown() then preview:Hide() return end
    if not preview then BuildPreview() end
    DrawPreview()
    preview:ClearAllPoints()
    if SettingsPanel and SettingsPanel:IsShown() then
        preview:SetPoint("TOPLEFT", SettingsPanel, "TOPRIGHT", 8, -48)
    else
        preview:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    preview:Show()
end

MenuStyle.Subscribe(function() if SM.PreviewShown() then DrawPreview() end end)

---------------------------------------------------------------------------
-- One launcher and its menu.
-- spec:
--   key          the module switch in TwichUIDB.modules ("mageTravel")
--   name         the data object's name ("TwichUI Mage Travel")
--   label        the feature's name, used for the label, the menu title and messages
--   menuName     the menu frame's global name (for UISpecialFrames, so Esc closes it)
--   icon         the data object's icon (a path or file ID), or a function returning one
--   page         the options page right-click opens
--   textKey      where the data bar text choice is saved in TwichUIDB.ui
--   texts        { { value, label }, ... }; the value "none" leaves only the icon
--   defaultText  the value used until one is chosen
--   hint         the launcher tooltip's line for what a click does
--   empty        the menu's text when there is nothing to list
--   forPlayer()  true when this character's class has the spells
--   entries()    sections, loading: { { label, rows = { entry, ... } }, ... } (nil for none) and
--                whether a name was still loading. entry: { id, text, icon, known, note }; note
--                is shown at the right of an unlearned row. A section may give learned and
--                total for the launcher tooltip's count, when its rows aren't every spell.
--   learnLines(tip, entry)  adds the lines under an unlearned spell's tooltip
--   shortcuts    optional: { { button = "LeftButton"|"RightButton", label, ranks = { spellIDs,
--                lowest first } }, ... }; shift and that button casts the highest rank known
--   footer       optional: { label, hint, shown(), onClick() }: a plain (not secure) entry under the
--                spells, while shown() is true; clicking it closes the menu and calls onClick
-- Returns the launcher's functions: Open(frame), Close(), Toggle(frame), IsOpen(), Available(),
-- Refresh(), ApplyAppearance(), TextChoice(), SetTextChoice(value).
---------------------------------------------------------------------------
function SM.New(spec)
    local L = {}
    local obj
    local loggedIn = false
    local menu, title, empty
    local pad = PAD                   -- the menu's inner margin: PAD, or more to clear a thick border
    local headers, rows = {}, {}
    local owner                       -- the data bar frame the menu was opened from
    local waiting = false             -- the last look found a spell the game hadn't loaded yet
    local closeAfterCombat = false    -- combat began before the menu could close
    local scheduled = false
    local active = {}                 -- [event] = handler, while registered
    local COMBAT_TEXT = spec.label .. " can't be opened in combat."
    local OFF_TEXT = spec.label .. " is turned off in TwichUI options."
    local Listen, Best   -- below

    local function Enabled() return spec.forPlayer() and R:Enabled(spec.key) end

    local function ShowRowTooltip(row)
        local e = row.entry
        if not (e and GameTooltip) then return end
        local K = Palette()
        GameTooltip:SetOwner(row, "ANCHOR_NONE")
        local right = (menu:GetRight() or 0) < (UIParent:GetWidth() or 0) * 0.66
        GameTooltip:ClearAllPoints()
        if right then GameTooltip:SetPoint("TOPLEFT", menu, "TOPRIGHT", 4, 0)
        else GameTooltip:SetPoint("TOPRIGHT", menu, "TOPLEFT", -4, 0) end
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(e.id)
        else GameTooltip:SetText(e.text, 1, 1, 1) end
        GameTooltip:AddLine(" ")
        if e.known then
            GameTooltip:AddLine("Click to cast", K.gold[1], K.gold[2], K.gold[3])
        else
            GameTooltip:AddLine("Not yet learned", K.gold[1], K.gold[2], K.gold[3])
            spec.learnLines(GameTooltip, e)
        end
        GameTooltip:Show()
    end

    local function HideRowTooltip(row)
        if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end

    -- After the click is done with: close the menu. Only on the release, so the press still
    -- reaches the row whichever of the two the game casts on (its "cast on key down" setting).
    local function AfterClick(row, _, down)
        if down or not (row.entry and row.entry.known) then return end
        if not InCombat() then menu:Hide() end
    end

    local function NewRow()
        local K = Palette()
        local row = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
        row:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        row:SetHeight(ROW_HEIGHT)
        local hover = Solid(row, "HIGHLIGHT", K.gold, 0.08)
        hover:SetAllPoints()
        row.rim = Solid(row, "ARTWORK", K.bronzeLo)
        row.rim:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
        row.rim:SetPoint("LEFT", 4, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("CENTER", row.rim, "CENTER")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.note = Text(row, FONT_NOTE, 12, "GameFontNormalSmall")
        row.note:SetPoint("RIGHT", -6, 0)
        row.note:SetJustifyH("RIGHT")
        row.name = Text(row, FONT_ROW, 14, "GameFontNormal")
        row.name:SetPoint("LEFT", row.rim, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", HideRowTooltip)
        row:SetScript("PostClick", AfterClick)
        return row
    end

    -- Out of combat only: it sets a secure button's attributes. A row gets a spell only when
    -- the character knows it; without one, a click does nothing.
    local function Fill(row, e)
        local K = Palette()
        row.entry = e
        row:SetAttribute("type", e.known and "spell" or nil)
        row:SetAttribute("spell", e.known and e.id or nil)
        row.icon:SetTexture(e.icon or 134400)   -- the question-mark icon when the game gives none
        row.icon:SetDesaturated(not e.known)
        row.icon:SetAlpha(e.known and 1 or 0.75)
        local rim = e.known and ARCANE or K.bronzeLo
        row.rim:SetColorTexture(rim[1], rim[2], rim[3], e.known and 0.75 or 1)
        row.name:SetText(e.text)
        local c = e.known and K.text or K.stone
        row.name:SetTextColor(c[1], c[2], c[3])
        row.note:SetText(e.known and "" or (e.note or "Not learned"))
        row.note:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    end

    local function Clear(row)
        row.entry = nil
        row:SetAttribute("type", nil)
        row:SetAttribute("spell", nil)
        row:Hide()
    end

    local footerRow   -- spec.footer's entry, made the first time it is shown

    local function NewFooter()
        local K = Palette()
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(ROW_HEIGHT)
        local hover = Solid(b, "HIGHLIGHT", K.gold, 0.08)
        hover:SetAllPoints()
        b.text = Text(b, FONT_NOTE, 13, "GameFontNormalSmall")
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetText(spec.footer.label)
        b.text:SetTextColor(K.gold[1], K.gold[2], K.gold[3])
        b:SetScript("OnClick", function()
            if InCombat() then return end
            menu:Hide()
            spec.footer.onClick()
        end)
        if spec.footer.hint then R.Interact.Tip(b, spec.footer.label, spec.footer.hint) end
        return b
    end

    local function NewHeader()
        local K = Palette()
        local h = CreateFrame("Frame", nil, menu)
        h:SetHeight(HEADER_HEIGHT)
        h.text = Text(h, FONT_HEADER, 12, "GameFontNormalSmall")
        h.text:SetPoint("BOTTOMLEFT", 4, 4)
        h.text:SetTextColor(K.gold[1], K.gold[2], K.gold[3])
        local line = Solid(h, "ARTWORK", K.bronzeLo, 0.8)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", 4, 1)
        line:SetPoint("BOTTOMRIGHT", -4, 1)
        local accent = Solid(h, "ARTWORK", ARCANE, 0.55)   -- a short arcane mark under the label
        accent:SetDrawLayer("ARTWORK", 1)
        accent:SetSize(18, 1)
        accent:SetPoint("BOTTOMLEFT", 4, 1)
        return h
    end

    local function BuildMenu()
        if menu then return end
        local K = Palette()
        menu = CreateFrame("Frame", spec.menuName, UIParent, "BackdropTemplate")
        menu:SetWidth(WIDTH)
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:Hide()
        title = Text(menu, FONT_TITLE, 13, "GameFontNormal")
        title:SetText(spec.label)
        title:SetTextColor(K.text[1], K.text[2], K.text[3])
        empty = Text(menu, FONT_NOTE, 13, "GameFontNormalSmall")
        empty:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
        empty:Hide()
        menu:SetScript("OnHide", function()
            owner = nil
            closeAfterCombat = false
            Listen(false)
            for _, row in ipairs(rows) do HideRowTooltip(row) end
        end)
        if UISpecialFrames then tinsert(UISpecialFrames, spec.menuName) end
    end

    -- Draws the player's background and border (modules/MenuStyle.lua) and moves the margin out
    -- if the border is thicker than it. Out of combat only: the rows are anchored to the menu.
    local function Restyle()
        pad = math.max(PAD, math.ceil(MenuStyle.Apply(menu)))
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", pad + 4, -(pad + TITLE_HEIGHT))
    end

    -- Out of combat only.
    local function Render()
        local sections, loading = spec.entries()
        waiting = loading
        local y = -(pad + TITLE_HEIGHT)
        local used = 0
        for _, h in ipairs(headers) do h:Hide() end
        empty:SetShown(not sections)
        if not sections then
            empty:SetText(spec.empty)
            y = y - ROW_HEIGHT
        end
        for i, section in ipairs(sections or {}) do
            local h = headers[i] or NewHeader()
            headers[i] = h
            h.text:SetText(section.label)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
            h:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
            h:Show()
            y = y - HEADER_HEIGHT - 2
            for _, e in ipairs(section.rows) do
                used = used + 1
                local row = rows[used] or NewRow()
                rows[used] = row
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
                row:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
                Fill(row, e)
                row:Show()
                y = y - ROW_HEIGHT
            end
            y = y - SECTION_GAP
        end
        if spec.footer and spec.footer.shown() then
            footerRow = footerRow or NewFooter()
            footerRow:ClearAllPoints()
            footerRow:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
            footerRow:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
            footerRow:Show()
            y = y - ROW_HEIGHT
        elseif footerRow then
            footerRow:Hide()
        end
        for i = used + 1, #rows do Clear(rows[i]) end
        menu:SetHeight(-y + pad)
    end

    -- Next to the data bar frame, on the side with room. Positioned against UIParent at the
    -- frame's place on screen rather than anchored to it, so the data bar's frame never joins
    -- the secure rows' anchor chain.
    local function Place(frame)
        menu:ClearAllPoints()
        local left, bottom, width, height = ScreenRect(frame)
        if not left then
            menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            return
        end
        local below = bottom + height / 2 > UIParent:GetHeight() / 2   -- a bar near the top: open downward
        local alignRight = left + width / 2 > UIParent:GetWidth() / 2
        local point = (below and "TOP" or "BOTTOM") .. (alignRight and "RIGHT" or "LEFT")
        local x = alignRight and (left + width) or left
        local y = below and (bottom - 2) or (bottom + height + 2)
        menu:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
    end

    function L.IsOpen() return menu ~= nil and menu:IsShown() end

    function L.Open(frame)
        if not Enabled() then Notice(OFF_TEXT) return false end
        if InCombat() then Notice(COMBAT_TEXT) return false end
        BuildMenu()
        owner = frame
        Restyle()
        Render()
        Place(frame)
        menu:Show()
        Listen(true)
        return true
    end

    -- Closes the menu, unless combat has already begun; then it closes when combat ends.
    function L.Close()
        if not L.IsOpen() then return true end
        if InCombat() then closeAfterCombat = true return false end
        menu:Hide()
        return true
    end

    function L.Toggle(frame)
        if L.IsOpen() then L.Close() else L.Open(frame) end
    end

    -- After an appearance setting changes, or the UI scale does: an open menu is redrawn at once.
    -- In combat nothing changes (the menu is closing); it is drawn afresh when next opened.
    function L.ApplyAppearance()
        if not menu or InCombat() then return end
        Restyle()
        if menu:IsShown() then Render() end
    end

    -----------------------------------------------------------------------
    -- Listening, only while the menu is open.
    -----------------------------------------------------------------------
    local function Redraw()
        scheduled = false
        if not L.IsOpen() or InCombat() then return end   -- open in combat only on its way to closing
        Render()
    end

    local function Schedule()
        if scheduled then return end
        scheduled = true
        C_Timer.After(SETTLE, Redraw)
    end

    local function OnDataLoaded() if waiting then Schedule() end end

    -- Just before combat lockdown begins: the last moment the menu can be closed.
    local function OnCombatStart() L.Close() end

    local function OnCombatEnd()
        if closeAfterCombat and L.IsOpen() then menu:Hide() end
    end

    -- A click anywhere but the menu or the launcher closes it.
    local function OnMouseDown()
        if not L.IsOpen() or menu:IsMouseOver() then return end
        if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
        L.Close()
    end

    local HANDLERS = {
        SPELLS_CHANGED = Schedule,
        LEARNED_SPELL_IN_SKILL_LINE = Schedule,
        PLAYER_LEVEL_UP = Schedule,
        SPELL_DATA_LOAD_RESULT = OnDataLoaded,
        PLAYER_REGEN_DISABLED = OnCombatStart,
        PLAYER_REGEN_ENABLED = OnCombatEnd,
        GLOBAL_MOUSE_DOWN = OnMouseDown,
        UI_SCALE_CHANGED = L.ApplyAppearance,   -- a border is a whole number of screen pixels
        DISPLAY_SIZE_CHANGED = L.ApplyAppearance,
    }

    function Listen(on)
        for event, handler in pairs(HANDLERS) do
            if on and not active[event] then
                active[event] = handler
                R:On(event, handler)
            elseif not on and active[event] then
                R:Off(event, active[event])
                active[event] = nil
            end
        end
    end

    -----------------------------------------------------------------------
    -- The launcher.
    -----------------------------------------------------------------------
    local function ValidText(value)
        for _, choice in ipairs(spec.texts) do
            if choice[1] == value then return true end
        end
        return false
    end

    function L.TextChoice()
        local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui[spec.textKey]
        return ValidText(saved) and saved or spec.defaultText
    end

    local function BarText()
        local choice = L.TextChoice()
        return choice == "none" and "" or choice
    end

    -- Saves the choice (an unknown one is refused); a data bar showing it updates at once.
    function L.SetTextChoice(value)
        if not ValidText(value) then return false end
        TwichUIDB.ui = TwichUIDB.ui or {}
        TwichUIDB.ui[spec.textKey] = value
        if obj then obj.text = BarText() end
        return true
    end

    -- A shortcut's highest known rank, and its place in the list; nil when none is known.
    function Best(shortcut)
        for rank = #shortcut.ranks, 1, -1 do
            if SM.Known(shortcut.ranks[rank]) then return shortcut.ranks[rank], rank end
        end
    end

    local function OnTooltipShow(tip)
        local K = Palette()
        tip:AddLine(spec.label, 1, 1, 1)
        if not R:Enabled(spec.key) then
            tip:AddLine(OFF_TEXT, K.stone[1], K.stone[2], K.stone[3])
            return
        end
        local sections = spec.entries()
        for _, section in ipairs(sections or {}) do
            local known, total = section.learned, section.total
            if not known then
                known, total = 0, #section.rows
                for _, e in ipairs(section.rows) do if e.known then known = known + 1 end end
            end
            tip:AddDoubleLine(section.label, ("%d of %d learned"):format(known, total),
                K.textDim[1], K.textDim[2], K.textDim[3], K.textDim[1], K.textDim[2], K.textDim[3])
        end
        if InCombat() then
            tip:AddLine(COMBAT_TEXT, K.ember[1], K.ember[2], K.ember[3])
        else
            tip:AddLine(spec.hint, K.gold[1], K.gold[2], K.gold[3])
        end
        if spec.shortcuts and #spec.shortcuts > 0 then
            tip:AddLine(" ")
            for _, s in ipairs(spec.shortcuts) do
                local id, rank = Best(s)
                tip:AddLine(("Shift-%s-click: %s, %s"):format(s.button == "LeftButton" and "left" or "right", s.label,
                    id and SM.RankText(id, rank) or "not learned yet"), K.stone[1], K.stone[2], K.stone[3])
            end
        end
    end

    local function OnClick(frame, button)
        if spec.shortcuts and IsShiftKeyDown and IsShiftKeyDown() then
            -- the secure cover would have taken it; it can't be put over the launcher in combat
            if InCombat() then Notice("Shift-click shortcuts can't be used in combat.") end
            return
        end
        if button == "RightButton" then
            if not InCombat() then R:OpenSettings(spec.page) end
            return
        end
        if GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
        L.Toggle(frame)
    end

    -----------------------------------------------------------------------
    -- Shift-click shortcuts: the secure cover over the launcher.
    -----------------------------------------------------------------------
    local cover, under   -- the secure button, and the data bar frame it lies over
    local covering = {}  -- [event] = handler, while the cover is up

    -- The tooltip belongs to the data bar's frame, never the secure cover, so the game's tooltip
    -- is never tied to a protected frame. A bar in the top half drops it below, else above.
    local function ShowLauncherTooltip(frame)
        if not GameTooltip then return end
        GameTooltip:SetOwner(frame, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        local _, bottom, _, height = ScreenRect(frame)
        if bottom and bottom + height / 2 > (UIParent:GetHeight() or 0) / 2 then
            GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -6)
        else
            GameTooltip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 6)
        end
        OnTooltipShow(GameTooltip)
        GameTooltip:Show()
    end

    local Cover   -- below

    -- Out of combat only; in combat the cover waits until it ends.
    local function Uncover()
        if GameTooltip and under and GameTooltip:IsOwned(under) then GameTooltip:Hide() end
        if not (cover and cover:IsShown()) or InCombat() then return end
        cover:Hide()
        under = nil
        Cover(false)
    end

    local function OnCoverRegenEnabled()
        if cover and cover:IsShown() and not cover:IsMouseOver() then Uncover() end
    end

    function Cover(on)
        local handlers = { PLAYER_REGEN_DISABLED = Uncover, PLAYER_REGEN_ENABLED = OnCoverRegenEnabled }
        for event, handler in pairs(handlers) do
            if on and not covering[event] then
                covering[event] = handler
                R:On(event, handler)
            elseif not on and covering[event] then
                R:Off(event, covering[event])
                covering[event] = nil
            end
        end
    end

    -- After the cover is clicked: a shift-click was the game's to cast (or to refuse); any other
    -- click is the launcher's own. Only on the release, as the press may be the one that casts.
    local function AfterCoverClick(_, button, down)
        if down then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            for _, s in ipairs(spec.shortcuts) do
                if s.button == button and not Best(s) then Notice(s.label .. " isn't learned yet.") end
            end
            return
        end
        if under then OnClick(under, button) end
    end

    local function BuildCover()
        cover = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        cover:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
        cover:Hide()
        cover:SetScript("OnLeave", Uncover)
        cover:SetScript("PostClick", AfterCoverClick)
    end

    -- Lays the cover over the launcher's frame, with the best known rank of each shortcut.
    -- Placed against UIParent at the frame's place on screen, not anchored to it, so the data
    -- bar's frame never joins a secure frame's anchor chain. Out of combat only.
    local function PutCover(frame)
        local left, bottom, width, height = ScreenRect(frame)
        if not left then return end
        if not cover then BuildCover() end
        under = frame
        for _, s in ipairs(spec.shortcuts) do
            local suffix = s.button == "LeftButton" and "1" or "2"
            local id = Best(s)
            cover:SetAttribute("shift-type" .. suffix, id and "spell" or nil)
            cover:SetAttribute("shift-spell" .. suffix, id)
        end
        if frame.GetFrameStrata then cover:SetFrameStrata(frame:GetFrameStrata()) end
        if frame.GetFrameLevel then cover:SetFrameLevel((frame:GetFrameLevel() or 0) + 10) end
        cover:ClearAllPoints()
        cover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        cover:SetSize(width, height)
        cover:Show()
        Cover(true)
    end

    local function OnEnter(frame)
        if not InCombat() and Enabled() then PutCover(frame) end
        ShowLauncherTooltip(frame)
    end

    local function OnLeave(frame)
        if cover and cover:IsShown() and cover:IsMouseOver() then return end   -- the cover took the mouse
        if GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    end

    -- The launcher, once: for the class, with the feature on, when a data bar addon provides
    -- LibDataBroker. With shortcuts it handles hovering itself (OnEnter), to lay the cover.
    local function Create()
        if obj or not Enabled() then return end
        local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
        if not LDB then return end
        local icon = spec.icon
        if type(icon) == "function" then icon = icon() end
        obj = LDB:NewDataObject(spec.name, {
            type = "data source",   -- not "launcher": many data bars show text only for a data source
            label = spec.label,
            text = BarText(),
            icon = icon or R.ICON,
            OnClick = OnClick,
            OnTooltipShow = not spec.shortcuts and OnTooltipShow or nil,
            OnEnter = spec.shortcuts and OnEnter or nil,
            OnLeave = spec.shortcuts and OnLeave or nil,
        })
    end

    -- Whether the launcher is on a data bar's list (false while no addon provides LibDataBroker).
    function L.Available() return obj ~= nil end

    -- After the option changes.
    function L.Refresh()
        if R:Enabled(spec.key) then Create() else L.Close() end
    end

    MenuStyle.Subscribe(L.ApplyAppearance)

    R:On("PLAYER_LOGIN", function()
        loggedIn = true
        Create()
    end)
    -- A data bar addon loaded on demand after login can still bring LibDataBroker.
    R:On("ADDON_LOADED", function() if loggedIn then Create() end end)

    return L
end
