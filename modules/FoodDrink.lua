-- TwichUI: Food and Drink buttons
-- Two small buttons, Food and Drink. Each holds the food or drink in your bags that restores the
-- most, and eats or drinks it when you click it. TwichUI never uses an item itself: the click
-- is yours, through the game's own secure button.
-- There is no item list. An item is offered only when the game calls it Food & Drink, its
-- use-spell is the game's plain "Food" or "Drink" spell, and that spell's description is
-- nothing but the restore sentence ("Restores 420 mana over 21 sec. Must remain seated ...",
-- read as two numbers, or three for one that restores health and mana). Anything with more to
-- say (buff food, feasts) or that can't be read is skipped. "Best" is the amount restored, as
-- the description states it; ties go to the smaller stack, so a part stack is finished first.
-- An empty button says so. Whether an item can be used at this moment (dead, a ghost) is not
-- part of choosing: the game decides that when the button is clicked.
-- Optionally (Prefer Mage-conjured food and water, off by default) a Mage-conjured item beats an
-- ordinary one even when the ordinary one restores more; see F.CONJURED. It is a preference
-- among items already eligible: it never lets in an item the rules above leave out.
-- The choice is refreshed when bags change. A secure button can't be changed in combat, so a
-- change during a fight waits until it ends. Move them in Edit Mode.
-- Their look is the player's to set (Food and drink options page): size, spacing, layout, border
-- (texture, thickness, colour or class colour, opacity), icon zoom and the stack count, and how
-- solid the buttons are, with an option to fade them until the mouse is over them. Border
-- textures: a plain line, any LibSharedMedia border, and (only while EllesmereUI is installed)
-- EllesmereUI's own, drawn by its ApplyBorderStyle on a frame of ours so they match its bars; the
-- list and drawing are shared with the Mage menus (modules/Borders.lua). Saved in TwichUIDB.ui.foodDrink.

local R = TwichUI
local F = {}
R.FoodDrink = F

local DEFAULT_X, DEFAULT_Y = 0, -220   -- from the centre of the screen
local SETTLE = 0.2                     -- seconds: a burst of bag events becomes one look
local CONSUMABLE, FOOD_AND_DRINK = 0, 5   -- item class and subclass the game must report
local FOOD_SPELL, DRINK_SPELL = 434, 431     -- the use-spells of plain food and drink (seen in the game with /tui probe); their names are the game's own, in any language
-- The items the Mage's Conjure Food and Conjure Water make: the six ranks of each that WoW:
-- Forever has (modules/MageConjure.lua's spells 587 ... 10145 and 5504 ... 10139), lowest rank
-- first. An item ID, so it holds in any language. The game exposes no "conjured" flag to read
-- instead (nothing in the Forever UI source or API documentation), and the use-spell is the
-- same plain Food or Drink spell as for ordinary items, so the ID is what tells them apart.
-- The IDs are those of the Classic-era game's conjured items; they were not read from the Forever
-- client, which this repository doesn't carry. /tui probe prints an item's ID, to check them
-- against conjured items in the bags (the list is a plain table, so a correction is one line).
F.CONJURED = {
    [5349] = true, [1113] = true, [1114] = true, [1487] = true, [8075] = true, [8076] = true,   -- Conjured Muffin ... Sweet Roll
    [5350] = true, [2288] = true, [2136] = true, [3772] = true, [8077] = true, [8078] = true,   -- Conjured Water ... Sparkling Water
}
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"   -- Edit Mode's own highlight, when the client has it

local KINDS = {
    { key = "food", label = "Food", use = "Click to eat it.", setting = "foodDrinkFood", rule = "The food in your bags that restores the most health." },
    { key = "drink", label = "Drink", use = "Click to drink it.", setting = "foodDrinkDrink", rule = "The drink in your bags that restores the most mana." },
}

local container, mover
local ShowMover, EditModeActive   -- below
local buttons = {}
local borderFrames = {}       -- [button] = the frames a border texture is drawn on (Borders.Draw)
local dirty = false           -- something changed in combat; look again when it ends
local scheduled = false
local loading = false         -- the last look found an item or spell text the game hadn't loaded yet
local active = {}             -- [event] = handler, while registered
local editHooked = false

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Choosing. Pure, so it can be checked on its own.
---------------------------------------------------------------------------

-- candidates: { { id, amount, count, conjured }, ... }. The most restored wins; then the smaller
-- stack; then the lower item ID, so the answer doesn't depend on bag order. With preferConjured,
-- only the conjured candidates compete when there are any; with none, all of them do. Without
-- it, `conjured` is not looked at.
function F.Pick(candidates, preferConjured)
    local only = false
    if preferConjured then
        for _, c in ipairs(candidates) do
            if c.conjured then only = true break end
        end
    end
    local best
    for _, c in ipairs(candidates) do
        if (c.conjured or not only) and (not best or c.amount > best.amount
            or (c.amount == best.amount and (c.count < best.count or (c.count == best.count and c.id < best.id)))) then
            best = c
        end
    end
    return best
end

-- What an item restores, from its use-spell's name and description: the kinds it counts as
-- ({ food = true } and/or { drink = true }) and the amount, or nil when it isn't plain food or
-- drink. names: { food, drink } the game's names for the two plain use-spells; words: { health,
-- mana } the game's words for the resources. Two numbers (amount, seconds) is a plain item;
-- three, with both words, restores health and mana. Any other number or a second paragraph
-- means more than a restore (a buff, a feast), so it is left out.
function F.Classify(spellName, text, names, words)
    if not (spellName and text) or text == "" or text:find("\n", 1, true) then return nil end
    local plain = (spellName == names.food and "food") or (spellName == names.drink and "drink") or nil
    if not plain then return nil end
    local first, count = nil, 0
    for n in text:gmatch("%d+") do
        count = count + 1
        first = first or tonumber(n)
    end
    if count == 2 then return { [plain] = true }, first end
    if count == 3 and words.health and words.mana then
        local lower = text:lower()
        if lower:find(words.health:lower(), 1, true) and lower:find(words.mana:lower(), 1, true) then
            return { food = true, drink = true }, first
        end
    end
    return nil
end

-- One item in the bags as a candidate, or nil when it can't be offered: not food and drink as
-- the game classifies it, not plain, above the character's level, or none left.
-- The second result is true when the game hasn't loaded the item or its text yet (a look is
-- asked for). The third says why there is no candidate, as a code, for /tui diagnostics.
-- readOnly: ask the game for nothing (a report must not change what the game loads).
local function Candidate(id, names, words, readOnly)
    local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(id)
    if classID ~= CONSUMABLE or subClassID ~= FOOD_AND_DRINK then return nil, false, "not-food-and-drink" end
    local name, _, _, _, minLevel = C_Item.GetItemInfo(id)
    name = Plain(name)
    if not name then
        if not readOnly and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil, true, "item-data-pending"
    end
    if (minLevel or 0) > (UnitLevel("player") or 0) then return nil, false, "level-too-high" end
    local spellName, spellID = C_Item.GetItemSpell(id)
    spellName, spellID = Plain(spellName), Plain(spellID)
    if not (spellName and spellID) then return nil, false, "no-use-spell" end
    local text = Plain(C_Spell.GetSpellDescription(spellID))
    if not text or text == "" then
        if not readOnly and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
        return nil, true, "spell-text-pending"
    end
    local kinds, amount = F.Classify(spellName, text, names, words)
    if not kinds then return nil, false, "not-plain-food-or-drink" end
    -- Not C_Item.IsUsableItem: it is false while dead or a ghost, which would drop every item from
    -- the choice and leave it empty after resurrection (no bag event follows). Whether the item
    -- can be used right now is the game's to enforce when the player clicks.
    local count = C_Item.GetItemCount(id) or 0
    if count < 1 then return nil, false, "none-left" end
    return { id = id, name = name, icon = icon, kinds = kinds, amount = amount, count = count, conjured = F.CONJURED[id] ~= nil }
end

-- The best food and the best drink in the bags: { food = candidate|nil, drink = candidate|nil }.
-- Also whether anything was still loading.
-- summary: when given, this is a read-only look for /tui diagnostics; it is filled with the candidates
-- by kind, how many items were left out and why, and whether the game's names for the plain spells were read.
local function Scan(summary)
    local names = { food = Plain(C_Spell.GetSpellName(FOOD_SPELL)), drink = Plain(C_Spell.GetSpellName(DRINK_SPELL)) }
    local words = { health = Plain(HEALTH), mana = Plain(MANA) }
    if summary then
        summary.spellNamesRead = names.food ~= nil and names.drink ~= nil
        summary.wordsRead = words.health ~= nil and words.mana ~= nil
    end
    local found, byKind, waiting = {}, { food = {}, drink = {} }, false
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and Plain(info.itemID)
            if id and not found[id] then
                found[id] = true
                local candidate, still, why = Candidate(id, names, words, summary ~= nil)
                if candidate then
                    for kind in pairs(candidate.kinds) do table.insert(byKind[kind], candidate) end
                end
                if still then waiting = true end
                if summary then
                    summary.items = summary.items + 1
                    if why then summary.excluded[why] = (summary.excluded[why] or 0) + 1 end
                end
            end
        end
    end
    local prefer = F.Get("preferConjured")
    local chosen = { food = F.Pick(byKind.food, prefer), drink = F.Pick(byKind.drink, prefer) }
    for _, c in pairs(chosen) do c.preferred = prefer and c.conjured end   -- so the tooltip can say why
    if summary then
        summary.candidates, summary.chosen = byKind, chosen
    end
    return chosen, waiting
end

---------------------------------------------------------------------------
-- Look. Saved values are read through F.Get, which keeps each within its range and falls back
-- to the default for anything invalid, so a bad saved value can't break the buttons.
---------------------------------------------------------------------------
F.DEFAULTS = {
    size = 36, spacing = 4, layout = "horizontal",
    borderTexture = "solid",   -- "solid", a LibSharedMedia border's name, or "eui:<key>" for one of EllesmereUI's
    borderSize = 1, borderColor = "ff8c6e38", borderClass = false,   -- the Chronicle's bronze
    borderOpacity = 100,
    zoom = 7, showCount = true,
    buttonOpacity = 100,
    mouseover = false, idleOpacity = 30,   -- fade to idleOpacity while the mouse is away
    preferConjured = false,   -- not a look: which item is chosen
}
F.LIMITS = { size = { 24, 64 }, spacing = { 0, 24 }, borderSize = { 0, 64 }, borderOpacity = { 0, 100 }, zoom = { 0, 20 },
    buttonOpacity = { 0, 100 }, idleOpacity = { 0, 100 } }
local BORDER_RULES = { defaultSize = F.DEFAULTS.borderSize, defaultColor = F.DEFAULTS.borderColor,
    solidMax = 4, texturedMin = 8, texturedSeed = 12, maxSize = F.LIMITS.borderSize[2] }   -- a texture needs room to draw
F.LAYOUTS = { horizontal = true, vertical = true }

local Borders = R.Borders   -- the border textures, shared with the Mage menus (modules/Borders.lua)

local function Valid(key, value)
    local limit = F.LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif key == "layout" then return F.LAYOUTS[value] == true
    elseif key == "borderTexture" then return Borders.ValidName(value)
    elseif key == "borderColor" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif key == "borderClass" or key == "showCount" or key == "mouseover" or key == "preferConjured" then return type(value) == "boolean" end
    return false
end

function F.Get(key)
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.foodDrink
    local value
    if type(saved) == "table" then value = saved[key] end
    if Valid(key, value) then return value end
    return F.DEFAULTS[key]
end

-- Saves one setting (an invalid value is refused) and redraws.
function F.Set(key, value)
    if not Valid(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.foodDrink = TwichUIDB.ui.foodDrink or {}
    local saved = TwichUIDB.ui.foodDrink
    -- a new texture gets a thickness and colour that suit it, unless the player set their own
    if key == "borderTexture" then
        local size, color = F.Get("borderSize"), F.Get("borderColor")
        local newSize, newColor = Borders.Reseed(F.Get("borderTexture"), value, size, color, BORDER_RULES)
        if newSize ~= size then saved.borderSize = newSize end
        if newColor ~= color then saved.borderColor = newColor end
    end
    saved[key] = value
    F.Refresh()
    return true
end

-- "AARRGGBB" as r, g, b, a in 0-1.
function F.ParseColor(hex)
    if not Valid("borderColor", hex) then return nil end
    local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return part(3), part(5), part(7), part(1)
end

-- The border's colour and opacity: the class colour or the chosen colour, at the chosen opacity
-- (the swatch's own alpha is not used; Opacity is the one control for it).
local function BorderColor()
    local opacity = F.Get("borderOpacity") / 100
    if F.Get("borderClass") then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, opacity end
    end
    local r, g, b = F.ParseColor(F.Get("borderColor"))
    return r, g, b, opacity
end

-- { { value, label }, ... } for the texture choice (see modules/Borders.lua).
function F.TextureChoices() return Borders.Choices(F.Get("borderTexture")) end

---------------------------------------------------------------------------
-- Where they go: the centre's offset from the centre of the screen, as moved in Edit Mode
-- (TwichUIDB.ui.foodDrinkPosition), or the default.
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end

function F.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.foodDrinkPosition
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return DEFAULT_X, DEFAULT_Y
end

local function Place(frame)
    local x, y = F.Position()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- The buttons. A plain frame holds them, so showing and hiding the set never touches a
-- protected frame; each button's own attributes and visibility change only out of combat.
---------------------------------------------------------------------------
local function Color(name, fallback)
    local S = R.ChronicleStyle
    return S and S.color and S.color[name] or fallback
end

local function ShowTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button.itemID then
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(button.itemID)
        else GameTooltip:SetHyperlink("item:" .. button.itemID) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(button.rule, 0.69, 0.66, 0.6, true)
        if button.preferred then
            GameTooltip:AddLine("Mage-conjured, which your options prefer over ordinary " .. button.label:lower() .. ".", 0.69, 0.66, 0.6, true)
        end
        GameTooltip:AddLine(button.use, 0.79, 0.64, 0.29)
    else
        GameTooltip:SetText(button.label, 1, 1, 1)
        GameTooltip:AddLine("Nothing in your bags that TwichUI can tell is plain " .. button.label:lower() .. " you can use.", nil, nil, nil, true)
    end
    -- The choice only changes out of combat; say so while a change is waiting.
    if dirty then
        GameTooltip:AddLine("Your bags changed in combat. This updates when combat ends.", 0.9, 0.45, 0.38, true)
    end
    GameTooltip:Show()
end

-- The choice under the pointer can change (an item used up, combat ending): the tooltip is redrawn
-- for the new choice, or taken down if the button is gone, instead of describing something old.
local function RefreshTooltip(button)
    if not (GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button) then return end
    if button:IsShown() and button:IsMouseOver() then ShowTooltip(button) else GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- How solid the set is: the button opacity, or, with the mouseover option on, the idle opacity
-- until the mouse is over a button. The mouse coming or going is a brief fade (a fade is all
-- Reduced motion leaves, so it applies to it as it is); a setting changed in the options, or
-- Edit Mode opening, is instant. A button at 0 still takes clicks. The container is a plain
-- frame, so this works in combat too.
---------------------------------------------------------------------------
local hovering = false
local HOVER_GRACE = 0.05   -- seconds: moving from one button to the other isn't leaving

local function AnyButtonHovered()
    for _, button in pairs(buttons) do
        if button:IsShown() and button:IsMouseOver() then return true end
    end
    return false
end

local FADE_IN, FADE_OUT = 0.12, 0.25   -- seconds: quick to appear under the mouse, easing away
local fader, fade                       -- the container's alpha animation, when the client has them
local alphaNow                          -- the alpha the container is at, or fading to

-- Edit Mode shows them at full strength, so the outline and the buttons can be seen together.
-- fading: the change is the mouse coming or going; anything else is instant.
local function ApplyAlpha(fading)
    if not container then return end
    local alpha = F.Get("buttonOpacity")
    if F.Get("mouseover") and not hovering and not (mover and mover:IsShown()) then alpha = F.Get("idleOpacity") end
    alpha = alpha / 100
    if alpha == alphaNow then return end
    local from = alphaNow
    alphaNow = alpha
    if fader then fader:Stop() end
    container:SetAlpha(alpha)   -- where it ends up; the animation only plays on the way
    if fading and fader and from and container:IsShown() then
        fade:SetFromAlpha(from)
        fade:SetToAlpha(alpha)
        fade:SetDuration(alpha > from and FADE_IN or FADE_OUT)
        fader:Play()
    end
end

local function RecheckHover()
    hovering = AnyButtonHovered()
    ApplyAlpha(true)
end

local function OnButtonEnter(button)
    hovering = true
    ApplyAlpha(true)
    ShowTooltip(button)
end

local function OnButtonLeave()
    if GameTooltip then GameTooltip:Hide() end
    C_Timer.After(HOVER_GRACE, RecheckHover)
end

local function BuildButton(kind)
    local b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")   -- the game's setting for use on key down decides which fires
    b.label, b.rule, b.use = kind.label, kind.rule, kind.use

    local well = b:CreateTexture(nil, "BACKGROUND")
    well:SetAllPoints()
    well:SetColorTexture(0.08, 0.06, 0.045, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.rim = { top = b:CreateTexture(nil, "OVERLAY"), bottom = b:CreateTexture(nil, "OVERLAY"),
        left = b:CreateTexture(nil, "OVERLAY"), right = b:CreateTexture(nil, "OVERLAY") }
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetPoint("CENTER")
    b.name:SetText(kind.label)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hot = b:CreateTexture(nil, "HIGHLIGHT")
    hot:SetAllPoints()
    hot:SetColorTexture(1, 0.9, 0.6, 0.12)
    b:SetScript("OnEnter", OnButtonEnter)
    b:SetScript("OnLeave", OnButtonLeave)
    b:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)   -- turned off or hidden under the pointer
    return b
end

-- Size, border, zoom and count to the player's settings. Out of combat only: it resizes a
-- secure button. An empty button's border is drawn at half strength.
local function Style(button, choice)
    local size, edge = F.Get("size"), F.Get("borderSize")
    local r, g, b, a = BorderColor()
    local alpha = a * (choice and 1 or 0.5)
    button:SetSize(size, size)
    local rim = button.rim

    -- EllesmereUI's own texture or a LibSharedMedia one, drawn on a frame over the button (never
    -- on the secure button itself); otherwise the plain line, drawn here
    borderFrames[button] = borderFrames[button] or {}
    local mode = Borders.Draw(borderFrames[button], button, F.Get("borderTexture"), edge, r, g, b, alpha)

    local inset = edge
    if mode == "ellesmere" then
        for _, t in pairs(rim) do t:Hide() end
        inset = math.max(1, math.floor(edge / 4))   -- the border straddles the edge, so the icon goes only a little in
    elseif mode == "texture" then
        for _, t in pairs(rim) do t:Hide() end
        inset = edge > 0 and math.max(1, math.floor(edge / 4)) or 0   -- the texture overlaps the icon's edge a little
    else
        for _, t in pairs(rim) do
            t:SetColorTexture(r, g, b, alpha)
            t:SetShown(edge > 0)
            t:ClearAllPoints()
        end
        rim.top:SetPoint("TOPLEFT"); rim.top:SetPoint("TOPRIGHT"); rim.top:SetHeight(math.max(edge, 1))
        rim.bottom:SetPoint("BOTTOMLEFT"); rim.bottom:SetPoint("BOTTOMRIGHT"); rim.bottom:SetHeight(math.max(edge, 1))
        rim.left:SetPoint("TOPLEFT"); rim.left:SetPoint("BOTTOMLEFT"); rim.left:SetWidth(math.max(edge, 1))
        rim.right:SetPoint("TOPRIGHT"); rim.right:SetPoint("BOTTOMRIGHT"); rim.right:SetWidth(math.max(edge, 1))
    end
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    local z = F.Get("zoom") / 100
    button.icon:SetTexCoord(z, 1 - z, z, 1 - z)
end

-- Points a button at a choice (or at nothing). Out of combat only: it sets secure attributes.
local function Fill(button, choice)
    local filled = choice ~= nil
    button:SetAttribute("type", filled and "item" or nil)
    button:SetAttribute("item", filled and choice.name or nil)
    button.itemID = filled and choice.id or nil
    button.choice = choice
    button.preferred = filled and choice.preferred or nil
    if filled then button.icon:SetTexture(choice.icon) end
    button.icon:SetShown(filled)
    button.name:SetShown(not filled)
    button.count:SetText(F.Get("showCount") and filled and choice.count > 1 and choice.count or "")
    Style(button, choice)
end

local function Build()
    if container then return end
    container = CreateFrame("Frame", nil, UIParent)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:Hide()
    fader = container.CreateAnimationGroup and container:CreateAnimationGroup()
    fade = fader and fader:CreateAnimation("Alpha")
    if fade then fade:SetSmoothing("IN_OUT") else fader = nil end
    for _, kind in ipairs(KINDS) do buttons[kind.key] = BuildButton(kind) end
end

local function Trace(code, detail)
    local D = R.Diag
    if D then D.Trace("food", code, detail) end
end

local function Update()
    dirty = false
    Build()
    local best, waiting = Scan()
    loading = waiting
    if waiting then
        -- An item or spell text the game has unloaded is not evidence the item is gone: keep the
        -- current choice for a kind while it is still in the bags, and look again when data arrives.
        for _, kind in ipairs(KINDS) do
            local old = rawget(buttons[kind.key], "choice")
            local count = old and C_Item.GetItemCount(old.id) or 0
            if not best[kind.key] and count > 0 then
                best[kind.key] = { id = old.id, name = old.name, icon = old.icon, kinds = old.kinds,
                    amount = old.amount, count = count, conjured = old.conjured, preferred = old.preferred }
            end
        end
    end
    local shown = 0
    local size, step, vertical = F.Get("size"), F.Get("size") + F.Get("spacing"), F.Get("layout") == "vertical"
    for _, kind in ipairs(KINDS) do
        local button = buttons[kind.key]
        if R:Enabled(kind.setting) then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", container, "TOPLEFT", vertical and 0 or shown * step, vertical and -shown * step or 0)
            button:Show()
            Fill(button, best[kind.key])
            RefreshTooltip(button)
            shown = shown + 1
        else
            button:Hide()
        end
    end
    local length = math.max(size, shown * step - F.Get("spacing"))
    if vertical then container:SetSize(size, length) else container:SetSize(length, size) end
    Place(container)
    container:SetShown(shown > 0)
    if mover and mover:IsShown() then mover:SetSize(container:GetSize()); Place(mover) end
    if not (mover and mover:IsShown()) and EditModeActive() then ShowMover(true) end
    hovering = AnyButtonHovered()
    ApplyAlpha()
    if R.Diag and R.Diag.Tracing() then
        Trace("updated", ("food=%s drink=%s waiting-for-data=%s"):format(
            best.food and best.food.id or "none", best.drink and best.drink.id or "none", tostring(waiting and true or false)))
    end
end

-- A look soon, once for a burst of events; deferred to the end of combat when in combat.
local function Look()
    scheduled = false
    if not R:Enabled("foodDrink") then return end
    if InCombat() then
        dirty = true
        Trace("deferred", "in combat; buttons keep their last choice until it ends")
        for _, button in pairs(buttons) do RefreshTooltip(button) end   -- now says it is waiting
    else
        Update()
    end
end

local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(SETTLE, Look)
end

local function OnDataLoaded() if loading then Schedule() end end
local function OnRegenEnabled()
    if dirty then
        Trace("combat-ended", "running the deferred look")
        Schedule()
    end
end

---------------------------------------------------------------------------
-- For /tui diagnostics (diag/Food.lua). Read only: nothing is requested from the game or changed.
---------------------------------------------------------------------------

-- Whether a button's secure attributes are those of the choice it shows. A secure button can't be
-- changed in combat, so after a deferred look the two can differ until combat ends.
local function SecureMatches(button)
    local choice = rawget(button, "choice")
    local kind, item = button:GetAttribute("type"), button:GetAttribute("item")
    if choice then return kind == "item" and item == choice.name end
    return kind == nil and item == nil
end

-- A short state line and whether data is still loading, for the trace of events that matter here
-- (dying, resurrecting, bags, combat). No bag scan.
function F.Brief()
    local parts = {}
    for _, kind in ipairs(KINDS) do
        local button = buttons[kind.key]
        local choice = button and rawget(button, "choice")
        parts[#parts + 1] = ("%s=%s%s"):format(kind.key, choice and choice.id or "none",
            (button and not SecureMatches(button)) and "(secure action differs)" or "")
    end
    parts[#parts + 1] = ("deferred=%s"):format(tostring(dirty))
    parts[#parts + 1] = ("loading=%s"):format(tostring(loading))
    parts[#parts + 1] = ("combat=%s"):format(tostring(InCombat() and true or false))
    return table.concat(parts, " "), loading
end

-- The state of the buttons, and what a fresh look at the bags would choose, for the report.
function F.Snapshot()
    local out = {
        enabled = R:Enabled("foodDrink"), built = container ~= nil, shown = container ~= nil and container:IsShown() or false,
        deferred = dirty, scheduled = scheduled, loading = loading, inCombat = InCombat() and true or false,
        preferConjured = F.Get("preferConjured"), conjuredKnown = 0, buttons = {}, apiMissing = nil,
    }
    for _ in pairs(F.CONJURED) do out.conjuredKnown = out.conjuredKnown + 1 end
    local events = {}
    for event in pairs(active) do events[#events + 1] = event end
    table.sort(events)
    out.events = events
    for _, kind in ipairs(KINDS) do
        local button = buttons[kind.key]
        local choice = button and rawget(button, "choice")
        local matches   -- nil until the button exists; false is a real answer
        if button then matches = SecureMatches(button) end
        out.buttons[#out.buttons + 1] = {
            key = kind.key, switchOn = R:Enabled(kind.setting), built = button ~= nil,
            shown = button ~= nil and button:IsShown() or false,
            id = choice and choice.id, count = choice and choice.count, amount = choice and choice.amount,
            conjured = choice and choice.conjured or false,
            secureMatches = matches,
        }
    end
    if out.enabled then
        if not (C_Item and C_Container and C_Spell) then
            out.apiMissing = true
        else
            local summary = { candidates = { food = {}, drink = {} }, excluded = {}, items = 0 }
            local ok = pcall(Scan, summary)
            if ok then out.scan = summary else out.scanFailed = true end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Edit Mode: an outline stands over the buttons; drag it to move them, right-click to put
-- them back. Edit Mode can't be opened in combat, and nothing here moves in combat.
---------------------------------------------------------------------------
local function SavePosition(x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.foodDrinkPosition = x and { x = x, y = y } or nil
    if container and not InCombat() then Place(container) end
    if mover then Place(mover) end
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(F.Get("size") * 2 + F.Get("spacing"), F.Get("size"))
    mover:SetFrameStrata("HIGH")
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
        local c = Color("bronze", { 0.55, 0.43, 0.22 })
        fill:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("Food and Drink")
    mover:SetScript("OnDragStart", function(self)
        if not InCombat() then self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if not (cx and cy and px and py) then Place(self) return end
        SavePosition(math.floor(cx - px + 0.5), math.floor(cy - py + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then SavePosition(nil) end
    end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: Food and Drink", 1, 1, 1)
        GameTooltip:AddLine("Where the Food and Drink buttons sit. Drag to move them; right-click to put them back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mover:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)   -- Edit Mode closing under the pointer
end

function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

function ShowMover(shown)
    if shown and R:Enabled("foodDrink") and container and container:IsShown() then
        if not mover then BuildMover() end
        mover:SetSize(container:GetSize())
        Place(mover)
        mover:Show()
    elseif mover then
        mover:StopMovingOrSizing()
        mover:Hide()
    end
    ApplyAlpha()
end

local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, F)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, F)
end

---------------------------------------------------------------------------
local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Listens only while the feature is on. Safe to call any time.
function F.Refresh()
    local on = R:Enabled("foodDrink")
    Want("BAG_UPDATE_DELAYED", Schedule, on)
    Want("GET_ITEM_INFO_RECEIVED", OnDataLoaded, on)
    Want("SPELL_TEXT_UPDATE", OnDataLoaded, on)
    Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, on)
    Want("PLAYER_LEVEL_UP", Schedule, on)
    Want("PLAYER_ENTERING_WORLD", Schedule, on)
    if on then
        HookEditMode()
        ApplyAlpha()   -- opacity changes at once, even in combat
        Schedule()
    else
        dirty, loading = false, false
        if container then container:Hide() end
        ShowMover(false)
    end
end

R:OnInit(F.Refresh)
