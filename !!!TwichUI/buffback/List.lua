-- TwichUI: Return the Favor, the list on screen
-- Draws Watch.lua's list: one row per player who just buffed you, with the buff's icon, their name in their class
-- color, the buff's name and a small icon of what a click gives back. A left click casts that back on them; a
-- right click takes the row away. Nothing is cast, targeted or said unless you click.
--
-- What the game allows (WoW: Forever UI source, SecureTemplates.lua) and so how this is built:
--   * Casting from a click needs a secure button: each row is a SecureActionButtonTemplate button running a macro
--     (Spells.lua's S.Macro: [@Name] for a group member, else /target, /cast, and your own target handed back).
--     It acts as the mouse button comes up whatever "cast on key down" says (useOnKeyDown false), as the marker bar.
--   * A protected frame can't be shown, hidden, moved, sized or given new attributes from addon code in combat. So
--     the rows are laid out, armed and shown out of combat only; in combat what arrives waits, a row that runs out or
--     is dismissed is dimmed, and everything is brought up to date when combat ends. Hiding the list in combat
--     (when you choose it) is the secure state driver's job: RegisterStateDriver(list, "visibility", "[combat] hide; show").
--   * Everything drawn is on a plain child of each row (its skin), never on the secure button itself: the look
--     (MenuStyle, with EllesmereUI's borders drawn on frames of their own), the icons and the text. Opacity and
--     dimming are the skin's, so they change in combat too.
--   * The sample (Preview) is a separate, ordinary list of made-up names that does nothing when clicked. While it is
--     shown, and EllesmereUI's Unlock Mode isn't in charge of the place, you drag it to move the list. It closes when
--     combat starts.
-- The place is the list's centre (BB.Place) or, while EllesmereUI's Unlock Mode is in charge, wherever its stand-in
-- is (Unlock.lua); the list is always as tall as its most rows, so it does not jump as names come and go.

local R = TwichUI
local BB, S, W = R.BuffBack, R.BuffBackSpells, R.BuffBackWatch
local MS = R.MenuStyle
local Perf = R.Perf
local L = {}
R.BuffBackList = L

local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow = "" }
local FADED = 0.4          -- a row that ran out (or was dismissed) in combat
local MAX = BB.LIMITS.maxRows[2]
local STRATA = "MEDIUM"

local list                 -- the secure list (built once, out of combat)
local rows = {}            -- its rows, made as needed (at most MAX)
local sample               -- the preview list (not secure)
local sampleRows = {}
local previewing = false
local dirty = false        -- something waits for combat to end
local cond                 -- the visibility condition the list is driven by now
local driven = false
local armQueued = false    -- a re-arm is waiting for the next moment (target, group and spell changes come in bursts)
local counts = { renders = 0, arms = 0, built = 0 }

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local Plain = W.Plain
local function Unlock() return R.BuffBackUnlock end

---------------------------------------------------------------------------
-- Colors, fonts, icons
---------------------------------------------------------------------------
local function Color(hex)
    local r, g, b = BB.Look.ParseColor(hex)
    if not r then return 1, 1, 1 end
    return r, g, b
end

local function ClassColor(class)
    local t = (rawget(_G, "CUSTOM_CLASS_COLORS") and CUSTOM_CLASS_COLORS[class]) or (rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[class])
    if type(t) == "table" and type(t.r) == "number" then return t.r, t.g, t.b end
    return nil
end

local function Font(fs, size)
    local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    local outline = BB.Get("outline")
    local file = MS.Fonts.Resolve(BB.Get("font"), fallback)
    local flags = FLAGS[outline] or ""
    if fs:SetFont(file, size, flags) == false then fs:SetFont(fallback, size, flags) end
    if outline == "shadow" then
        fs:SetShadowColor(0, 0, 0, 0.85)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local QUESTION = 134400   -- the game's question-mark icon
local function SpellIcon(id)
    if type(id) ~= "number" then return nil end
    local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    if not get then return nil end
    local ok, v = pcall(get, id)
    if ok then return Plain(v) end
end

---------------------------------------------------------------------------
-- What a click on a row does
---------------------------------------------------------------------------
local function PlayerClass()
    local _, class = UnitClass("player")
    return Plain(class)
end

local function Known(id) return R.SpellMenu.Known(id) end

-- For one entry: the family a click gives, the reason when none, the macro text and the spell's name.
function L.Plan(entry)
    if type(entry) ~= "table" then return nil, "none" end
    local inParty = UnitInParty and Plain(UnitInParty(entry.name))
    local inRaid = UnitInRaid and Plain(UnitInRaid(entry.name))
    if inParty ~= nil or inRaid ~= nil then
        entry.inParty = inParty and true or false
        entry.inGroup = (inParty or inRaid) and true or false
    end
    local unit = W.FindUnit(entry.name)
    local fam, why = S.Pick(PlayerClass(), entry, Known, unit and W.Wearing(unit) or nil)
    if not fam then return nil, why end
    local spell = S.SpellName(fam.ranks[1])
    local has = Plain(UnitExists("target")) and true or false
    local macro = S.Macro(entry, fam, spell, { has = has, isThem = has and W.FullName("target") == entry.name,
        token = entry.inGroup and W.GroupUnit(entry.name) or nil })
    if not macro then return nil, "spell" end
    return fam, nil, macro, spell
end

local WHY = {
    nothing = "Your class has nothing from this list to give back.",
    unknown = "You haven't learned anything to give back yet.",
    party = "Your shout reaches only your own party, and they aren't in it.",
    mana = "All you can give is for players who use mana.",
    spell = "The game hasn't said the spell's name yet; try again in a moment.",
    none = "Nothing to give back.",
}
L.WHY = WHY

local function Arm(row, entry)
    counts.arms = counts.arms + 1
    local fam, why, macro, spell = L.Plan(entry)
    row.entry, row.fam, row.why, row.spell = entry, fam, why, spell
    row:SetAttribute("*type1", macro and "macro" or nil)
    row:SetAttribute("*macrotext1", macro)
end

local function Disarm(row)
    row.entry, row.fam, row.why, row.spell = nil, nil, nil, nil
    row:SetAttribute("*type1", nil)
    row:SetAttribute("*macrotext1", nil)
end

---------------------------------------------------------------------------
-- A row
---------------------------------------------------------------------------
local function Tooltip(row)
    local e = row.entry
    if not (e and GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local r, g, b = ClassColor(e.class)
    GameTooltip:SetText(e.short or e.name, r or 1, g or 1, b or 1)
    local ago = math.max(0, math.floor(GetTime() - (e.at or GetTime()) + 0.5))
    GameTooltip:AddLine(("Buffed you with %s %s."):format(table.concat(e.buffs or { e.spellName or "a buff" }, ", "),
        ago < 2 and "just now" or (ago .. " seconds ago")), 0.85, 0.8, 0.7, true)
    if row.sample then
        GameTooltip:AddLine("A sample. Clicking it does nothing.", 0.6, 0.6, 0.6, true)
    elseif row.fam then
        GameTooltip:AddLine(("Click: cast %s on them."):format(row.spell or "your buff"), 0.56, 0.75, 0.42, true)
        if not e.inGroup then GameTooltip:AddLine("It targets them, casts, and gives you your own target back.", 0.6, 0.6, 0.6, true) end
    else
        GameTooltip:AddLine(WHY[row.why or "none"] or WHY.none, 0.9, 0.62, 0.4, true)
    end
    if e.faded then GameTooltip:AddLine("Its time has run out; it goes when combat ends.", 0.6, 0.6, 0.6, true) end
    if not row.sample then GameTooltip:AddLine("Right-click: remove it from the list.", 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

local function OnEnter(row)
    if row.skin.hot then row.skin.hot:Show() end
    Tooltip(row)
end

local function OnLeave(row)
    if row.skin.hot then row.skin.hot:Hide() end
    R.Interact.HideTip(row)
end

local function PostClick(row, button)
    if row.sample or not row.entry then return end
    if button == "RightButton" then
        W.Dismiss(row.entry)
    elseif row.fam then
        W.Clicked(row.entry, row.fam)
    end
end

local function NewRow(parent, secure, index)
    local row = CreateFrame("Button", secure and ("TwichUIReturnTheFavorRow" .. index) or nil, parent,
        secure and "SecureActionButtonTemplate" or nil)
    row.sample = not secure
    if secure then
        row:RegisterForClicks("AnyUp")
        row:SetAttribute("useOnKeyDown", false)
        row:SetScript("PostClick", PostClick)
    else
        row:EnableMouse(false)   -- the sample's rows let the drag reach the list behind them
    end
    local skin = CreateFrame("Frame", nil, row, "BackdropTemplate")
    skin:SetAllPoints(row)
    skin:EnableMouse(false)
    row.skin = skin
    skin.icon = skin:CreateTexture(nil, "ARTWORK")
    skin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    skin.back = skin:CreateTexture(nil, "ARTWORK")
    skin.back:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    skin.name = skin:CreateFontString(nil, "OVERLAY")
    skin.name:SetJustifyH("LEFT")
    skin.name:SetWordWrap(false)
    skin.spell = skin:CreateFontString(nil, "OVERLAY")
    skin.spell:SetJustifyH("LEFT")
    skin.spell:SetWordWrap(false)
    skin.hot = skin:CreateTexture(nil, "OVERLAY")   -- shown by hand: a plain frame has no highlight of its own
    skin.hot:SetAllPoints(skin)
    skin.hot:SetColorTexture(1, 0.9, 0.6, 0.08)
    skin.hot:Hide()
    row:SetScript("OnEnter", OnEnter)
    row:SetScript("OnLeave", OnLeave)
    row:HookScript("OnHide", function(self) OnLeave(self) end)
    counts.built = counts.built + 1
    return row
end

-- The look, sizes and fonts. Out of combat for a secure row (it is sized); the skin alone at any time.
local function Style(row)
    local width, h = BB.Get("width"), BB.Get("rowHeight")
    row:SetSize(width, h)
    local skin = row.skin
    local inset = BB.Look.ApplyInset(skin)
    local pad = math.floor(inset + 0.5) + 3
    local size = math.max(8, math.min(BB.Get("iconSize"), h - 2 * pad + 4))
    skin.icon:ClearAllPoints()
    skin.icon:SetSize(size, size)
    skin.icon:SetPoint("LEFT", skin, "LEFT", pad, 0)
    local back = BB.Get("showReturn")
    local small = math.max(8, math.floor(size * 0.75 + 0.5))
    skin.back:ClearAllPoints()
    skin.back:SetSize(small, small)
    skin.back:SetPoint("RIGHT", skin, "RIGHT", -pad, 0)
    skin.back:SetShown(back)
    local textSize = BB.Get("textSize")
    Font(skin.name, textSize)
    Font(skin.spell, math.max(7, textSize - 2))
    local right = back and (-pad - small - 4) or -pad
    local two = BB.Get("showSpellName")
    skin.name:ClearAllPoints()
    skin.spell:ClearAllPoints()
    if two then
        skin.name:SetPoint("BOTTOMLEFT", skin.icon, "RIGHT", 6, 1)
        skin.name:SetPoint("RIGHT", skin, "RIGHT", right, 0)
        skin.spell:SetPoint("TOPLEFT", skin.icon, "RIGHT", 6, -1)
        skin.spell:SetPoint("RIGHT", skin, "RIGHT", right, 0)
    else
        skin.name:SetPoint("LEFT", skin.icon, "RIGHT", 6, 0)
        skin.name:SetPoint("RIGHT", skin, "RIGHT", right, 0)
    end
    skin.spell:SetShown(two)
end

-- What the row shows for its entry. Text, icons and alpha only, so it runs in combat too.
local function Fill(row)
    local e, skin = row.entry, row.skin
    if not e then return end
    skin.icon:SetTexture(e.icon or SpellIcon(e.spellId) or QUESTION)
    local r, g, b
    if BB.Get("classColor") then r, g, b = ClassColor(e.class) end
    if not r then r, g, b = Color(BB.Get("nameColor")) end
    skin.name:SetText(e.short or e.name)
    skin.name:SetTextColor(r, g, b)
    skin.spell:SetText(e.spellName or "")
    skin.spell:SetTextColor(Color(BB.Get("textColor")))
    if row.fam then
        skin.back:SetTexture(SpellIcon(row.fam.ranks[1]) or QUESTION)
        skin.back:SetDesaturated(false)
        skin.back:SetAlpha(1)
    else
        skin.back:SetTexture(SpellIcon(e.spellId) or QUESTION)
        skin.back:SetDesaturated(true)
        skin.back:SetAlpha(0.35)
    end
    skin:SetAlpha(BB.Get("opacity") / 100 * ((e.faded or e.dismissed) and FADED or 1))
end

---------------------------------------------------------------------------
-- The lists and their place
---------------------------------------------------------------------------
local function Offset()
    local U = Unlock()
    if U and U.Offset then
        local x, y = U.Offset()
        if x then return x, y end
    end
    return BB.Place()
end

local function Place(frame)
    local scale = BB.Get("scale") / 100
    frame:SetScale(scale)
    frame:SetSize(BB.Footprint())
    local x, y = Offset()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

local function Stack(frame, set, count)
    local h, gap = BB.Get("rowHeight"), BB.Get("spacing")
    local down = BB.Get("growth") == "down"
    for i = 1, count do
        local row = set[i]
        row:ClearAllPoints()
        local step = (i - 1) * (h + gap)
        if down then row:SetPoint("TOP", frame, "TOP", 0, -step)
        else row:SetPoint("BOTTOM", frame, "BOTTOM", 0, step) end
    end
end

local function Build()
    if list then return true end
    if InCombat() then return false end
    list = CreateFrame("Frame", "TwichUIReturnTheFavor", UIParent, "SecureHandlerStateTemplate")
    list:SetFrameStrata(STRATA)
    list:SetClampedToScreen(true)
    list:Hide()
    return true
end

local function Drive(c)
    if cond == c then return end
    cond = c
    if c == "hide" then
        if driven then UnregisterStateDriver(list, "visibility") end
        driven = false
        list:Hide()
    else
        RegisterStateDriver(list, "visibility", c)
        driven = true
    end
end

-- The condition the list is shown under: hidden while it is off, paused, empty or the sample stands in for it.
local function Condition(count)
    if not W.Enabled() or previewing or count == 0 or W.Paused() then return "hide" end
    if BB.Get("hideCombat") then return "[combat] hide; show" end
    return "show"
end

-- Brings the secure list up to date: its place, rows, what each click does, and whether it shows. Out of combat.
local function Render()
    if InCombat() then dirty = true return false end
    local entries = W.Entries()
    local count = math.min(#entries, BB.Get("maxRows"), MAX)
    if not list then
        if count == 0 then return true end
        if not Build() then dirty = true return false end
    end
    local pt = Perf.on and Perf.Start("buffback.render")
    dirty = false
    counts.renders = counts.renders + 1
    Place(list)
    for i = 1, count do
        local row = rows[i]
        if not row then
            row = NewRow(list, true, i)
            rows[i] = row
        end
        Style(row)
        Arm(row, entries[i])
        Fill(row)
        row:Show()
    end
    for i = count + 1, #rows do
        Disarm(rows[i])
        rows[i]:Hide()
    end
    Stack(list, rows, count)
    Drive(Condition(count))
    if pt then Perf.Stop(pt) end
    return true
end
L.Render = Render

-- Only what can change in combat: the rows' text, icons and dimming.
local function Refill()
    for _, row in ipairs(rows) do
        if row.entry and row:IsShown() then Fill(row) end
    end
end

---------------------------------------------------------------------------
-- The sample
---------------------------------------------------------------------------
local SAMPLES = {
    { name = "Aldren", class = "PRIEST", spellId = 10938 },
    { name = "Brisa", class = "DRUID", spellId = 9885 },
    { name = "Corwyn", class = "MAGE", spellId = 10157 },
    { name = "Daelin", class = "PALADIN", spellId = 25291 },
    { name = "Eshvar", class = "WARLOCK", spellId = 5697 },
}

local function SaveDrag(frame)
    frame:StopMovingOrSizing()
    local cx, cy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    local s, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if cx and cy and px and py and s and us and us > 0 then
        BB.SetPlace((cx * s - px * us) / us, (cy * s - py * us) / us)
    end
    Place(frame)
end

local function BuildSample()
    if sample then return end
    sample = CreateFrame("Frame", nil, UIParent)
    sample:SetFrameStrata(STRATA)
    sample:SetClampedToScreen(true)
    sample:SetMovable(true)
    sample:EnableMouse(true)
    sample:RegisterForDrag("LeftButton")
    if sample.SetDontSavePosition then sample:SetDontSavePosition(true) end
    sample:Hide()
    sample.frame = sample:CreateTexture(nil, "BACKGROUND")
    sample.frame:SetAllPoints()
    sample.frame:SetColorTexture(0.58, 0.78, 0.76, 0.08)
    sample.hint = sample:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sample.hint:SetPoint("BOTTOM", sample, "TOP", 0, 4)
    sample:SetScript("OnDragStart", function(self)
        local U = Unlock()
        if InCombat() or (U and U.Drives()) then return end
        self:StartMoving()
    end)
    sample:SetScript("OnDragStop", SaveDrag)
end

local function DrawSample()
    if not (sample and previewing) then return end
    Place(sample)
    local U = Unlock()
    local moving = not (U and U.Drives())
    sample.hint:SetText(moving and "Return the Favor (a sample): drag to move it" or "Return the Favor (a sample): move it in EllesmereUI's Unlock Mode")
    local count = math.min(#SAMPLES, BB.Get("maxRows"))
    local now = GetTime()
    for i = 1, count do
        local row = sampleRows[i]
        if not row then
            row = NewRow(sample, false, i)
            sampleRows[i] = row
        end
        local s = SAMPLES[i]
        local name = S.SpellName(s.spellId)
        row.entry = { name = s.name, short = s.name, class = s.class, spellId = s.spellId, spellName = name,
            buffs = { name or "a buff" }, at = now - i * 7, expires = now + 60 }
        row.fam = S.BY_ID[s.spellId]
        Style(row)
        Fill(row)
        row:Show()
    end
    for i = count + 1, #sampleRows do sampleRows[i]:Hide() end
    Stack(sample, sampleRows, count)
end

-- Shows or hides the sample. Out of combat only. Returns true, or false and a reason code ("combat").
function L.Preview(on)
    on = on and true or false
    if on and InCombat() then return false, "combat" end
    if on == previewing then return true end
    previewing = on
    if on then
        BuildSample()
        sample:Show()
        DrawSample()
    elseif sample then
        sample:Hide()
    end
    Render()
    return true
end

function L.Previewing() return previewing end

---------------------------------------------------------------------------
-- Being told
---------------------------------------------------------------------------
-- what: "entries", "fade", "combat", "combatStart", "arm", "where", "switch", "settings" (from Watch.lua) or a BB change.
function L.Changed(what)
    if what == "switch" then
        local U = Unlock()
        if U and U.Refresh then U.Refresh() end
        if previewing and not W.Enabled() then L.Preview(false) end
    end
    if what == "combatStart" then
        if previewing then L.Preview(false) end   -- the sample is not secure: it can go any time
        return
    end
    if what == "arm" then
        -- what a click does may have changed (your target, group or spells): once, a moment later
        if armQueued then return end
        armQueued = true
        C_Timer.After(0.1, function()
            armQueued = false
            if InCombat() then dirty = true return end
            Render()
        end)
        return
    end
    if what == "fade" or InCombat() then
        if what ~= "fade" then dirty = true end
        Refill()
        return
    end
    if previewing then DrawSample() end
    Render()
end

-- The place may have changed (EllesmereUI's stand-in moved). Out of combat; in combat it waits.
function L.Reposition()
    if previewing and sample then Place(sample) end
    if not list then return true end
    if InCombat() then dirty = true return false end
    Place(list)
    return true
end

BB.Subscribe(function(what)
    local U = Unlock()
    if U and U.Refresh then U.Refresh() end
    if what == "place" then L.Reposition() return end
    L.Changed("settings")
end)

-- An EllesmereUI border is only drawn once every addon has loaded (docs/dev-rules.md): draw again then.
R:On("PLAYER_LOGIN", function() if list or previewing then L.Changed("settings") end end)

---------------------------------------------------------------------------
-- For the options page, the tests and /tui perf. Read only.
---------------------------------------------------------------------------
function L.Snapshot()
    local shown = 0
    for _, row in ipairs(rows) do if row:IsShown() then shown = shown + 1 end end
    return {
        built = list ~= nil, rows = #rows, shown = shown, sampleRows = #sampleRows, previewing = previewing,
        waiting = dirty, condition = cond, renders = counts.renders, arms = counts.arms, made = counts.built,
    }
end

function L.Rows() return rows end
function L.Frame() return list end
