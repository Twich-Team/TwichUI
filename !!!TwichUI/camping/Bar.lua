-- TwichUI: camping bar
-- A row of buttons for WoW: Forever's camping: the campfire kit you hold, the camp objects your professions make
-- (the ones in your bags, and the ones you know the recipe for), and the Cozy Sleeping Bag once you have it. The
-- bar fills itself from what the character knows and carries (camping/State.lua decides what is on it); the player
-- chooses how much of that to show and how it looks. Off until turned on.
--
-- What a click does, and what it never does:
--   * an object, kit or bag in your bags: the game's own secure button uses it, as the Food and Drink buttons do.
--     TwichUI never uses an item itself;
--   * no kit in your bags but the Basic Campfire spell known: the button casts that spell;
--   * a recipe you know with none made: the button is dimmed and a click opens that recipe in your professions
--     window. It crafts nothing.
-- Nothing is ever placed, crafted or cast except by your click.
--
-- What the game gives and so how this is built (WoW: Forever UI source, API documentation):
--   * C_Item.GetItemCount for what is carried; C_SpellBook.IsSpellKnown / C_TradeSkillUI.GetRecipeInfo(...).learned
--     for a recipe; C_SkillInfo for skill. None of these has been read from a Forever client with camping in it; a
--     read the game does not answer leaves the button out rather than guessing (see State.lua).
--   * A secure button can't be changed in combat, so the buttons' items, places and looks are set out of combat
--     and a change made in combat waits for it to end (the same rule as the Food and Drink buttons). They hang from a
--     plain frame, so showing, hiding and fading the whole bar works in combat.
--
-- Events are listened for only while the bar is on; nothing runs per frame. Saved (the profile's):
-- TwichUIDB.ui.campingBar (C.DEFAULTS) and the place TwichUIDB.ui.campingBarPosition { x, y } from the middle of the
-- screen. Nothing about what is shown right now is saved.

local R = TwichUI
local D, S = R.CampingData, R.CampingState
local C = {}
R.Camping = C

local Borders = R.Borders

local DEFAULT_X, DEFAULT_Y = 0, -170
local SETTLE = 0.2                       -- seconds: a burst of events becomes one look
local UNKNOWN_ICON = 134400              -- the question mark, until the game has an item's own icon
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
C.DEFAULTS = {
    -- the look
    size = 36, spacing = 4, perLine = 12, layout = "horizontal",
    borderTexture = "solid", borderSize = 1, borderColor = "ff8c6e38", borderClass = false, borderOpacity = 100,
    zoom = 7, showCount = true, buttonOpacity = 100, mouseover = false, idleOpacity = 30,
    -- what is on it
    showFire = true, showBag = true, best = false, onlyBags = false,
    -- the eat button: buff food, eaten with a click (or a key), then sitting down
    eat = false, eatMode = "auto", eatItem = 0, eatSit = true,
    -- moved in EllesmereUI's Unlock Mode instead of Edit Mode (needs EllesmereUI; explicit true only)
    unlockMode = false,
    -- when it shows
    hideParty = false, hideRaid = false, hidePvp = false, hideResting = false, hideCombat = false, onlyNearFire = false,
}
for _, g in ipairs(D.GROUPS) do
    C.DEFAULTS["grp_" .. g.key] = true
    for _, o in ipairs(g.objects) do C.DEFAULTS["obj_" .. o.item] = true end   -- each object can be left off the bar
end

C.LIMITS = { size = { 20, 64 }, spacing = { 0, 24 }, perLine = { 1, 20 }, borderSize = { 0, 64 }, borderOpacity = { 0, 100 },
    zoom = { 0, 20 }, buttonOpacity = { 0, 100 }, idleOpacity = { 0, 100 }, eatItem = { 0, 9999999 } }
C.LAYOUTS = { horizontal = true, vertical = true }
C.EAT_MODES = { auto = true, choose = true }

-- Which setting is which, so a change redraws only what it changes.
C.LOOK_KEYS = { "size", "spacing", "perLine", "layout", "borderTexture", "borderSize", "borderColor", "borderClass",
    "borderOpacity", "zoom", "showCount", "buttonOpacity", "mouseover", "idleOpacity" }
local PAINT_KEYS = { borderTexture = true, borderSize = true, borderColor = true, borderClass = true, borderOpacity = true,
    zoom = true, showCount = true }
local ALPHA_KEYS = { buttonOpacity = true, mouseover = true, idleOpacity = true }
local WHEN_KEYS = { hideParty = true, hideRaid = true, hidePvp = true, hideResting = true, hideCombat = true, onlyNearFire = true }

local BORDER_RULES = { defaultSize = C.DEFAULTS.borderSize, defaultColor = C.DEFAULTS.borderColor,
    solidMax = 4, texturedMin = 8, texturedSeed = 12, maxSize = C.LIMITS.borderSize[2] }

local function Valid(key, value)
    local limit = C.LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif key == "layout" then return C.LAYOUTS[value] == true
    elseif key == "eatMode" then return C.EAT_MODES[value] == true
    elseif key == "borderTexture" then return Borders.ValidName(value)
    elseif key == "borderColor" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif C.DEFAULTS[key] ~= nil and type(C.DEFAULTS[key]) == "boolean" then return type(value) == "boolean" end
    return false
end
C.Valid = Valid

function C.Get(key)
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.campingBar
    local value
    if type(saved) == "table" then value = saved[key] end   -- not "and ... or": a saved false is a value
    if Valid(key, value) then return value end
    return C.DEFAULTS[key]
end

local Changed   -- (below)

function C.Set(key, value)
    if C.DEFAULTS[key] == nil or not Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.campingBar) ~= "table" then TwichUIDB.ui.campingBar = {} end
    local saved = TwichUIDB.ui.campingBar
    if saved[key] == value then return true end
    -- a new texture gets a thickness and colour that suit it, unless the player set their own
    if key == "borderTexture" then
        local size, color = C.Get("borderSize"), C.Get("borderColor")
        local newSize, newColor = Borders.Reseed(C.Get("borderTexture"), value, size, color, BORDER_RULES)
        if newSize ~= size then saved.borderSize = newSize end
        if newColor ~= color then saved.borderColor = newColor end
    end
    saved[key] = value
    Changed(key)
    return true
end

-- Puts the look back to its defaults. What is on the bar, when it shows and where it sits are kept.
function C.ResetLook()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.campingBar
    if type(saved) ~= "table" then return end
    local any = false
    for _, key in ipairs(C.LOOK_KEYS) do
        if saved[key] ~= nil then saved[key] = nil; any = true end
    end
    if any then C.Refresh() end
end

-- The settings Plan() and Visible() read.
local function Options()
    local o = { showFire = C.Get("showFire"), showBag = C.Get("showBag"), best = C.Get("best"), onlyBags = C.Get("onlyBags") }
    o.eat = C.Get("eat")
    for _, g in ipairs(D.GROUPS) do
        o["grp_" .. g.key] = C.Get("grp_" .. g.key)
        for _, obj in ipairs(g.objects) do o["obj_" .. obj.item] = C.Get("obj_" .. obj.item) end
    end
    return o
end
local function WhenOptions()
    local o = {}
    for key in pairs(WHEN_KEYS) do o[key] = C.Get(key) end
    return o
end

-- "AARRGGBB" as r, g, b, a in 0-1.
local function ParseColor(hex)
    if not Valid("borderColor", hex) then return nil end
    local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return part(3), part(5), part(7), part(1)
end

local function BorderColor()
    local opacity = C.Get("borderOpacity") / 100
    if C.Get("borderClass") then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, opacity end
    end
    local r, g, b = ParseColor(C.Get("borderColor"))
    return r, g, b, opacity
end

function C.TextureChoices() return Borders.Choices(C.Get("borderTexture")) end

---------------------------------------------------------------------------
-- Where it goes
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end
C.ValidOffset = Offset

function C.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.campingBarPosition
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return DEFAULT_X, DEFAULT_Y
end

local container, mover
local buttons = {}
local borderFrames = {}
local entries = {}                 -- the plan the buttons show now
local dirty, scheduled, loading, moveWaiting = false, false, false, false
local hovering = false
local active = {}                  -- event = handler, while listened for
local looks = 0
local lastHidden                   -- why the bar is hidden by its visibility choices, or nil
local ShowMover, EditModeActive    -- (below)

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Where the bar goes now: the saved place or, while EllesmereUI's Unlock Mode is in charge of it (camping/Unlock.lua),
-- the place its stand-in is at. Same coordinates either way.
function C.Placement()
    local U = C.Unlock
    if U then
        local x, y = U.Offset()
        if x then return x, y end
    end
    return C.Position()
end

local function Place(frame)
    local x, y = C.Placement()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function SavePosition(x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.campingBarPosition = x and { x = x, y = y } or nil
    if container then
        if InCombat() then dirty = true else Place(container) end
    end
    if mover then Place(mover) end
end
C.SetPosition = SavePosition
function C.ResetPosition()
    SavePosition(nil)
    if C.Unlock then C.Unlock.Reset() end
end

---------------------------------------------------------------------------
-- Reading the game (each read tolerates a missing or secret answer)
---------------------------------------------------------------------------
-- true / false when the game says, nil when nothing could.
local function KnownRecipe(spell)
    local answer
    local SB = C_SpellBook
    if SB and SB.IsSpellKnown then
        local ok, known = pcall(SB.IsSpellKnown, spell)
        if ok then
            known = Plain(known)
            if known == true then return true end
            if known == false then answer = false end
        end
    end
    local TS = C_TradeSkillUI
    if TS and TS.GetRecipeInfo then
        local ok, info = pcall(TS.GetRecipeInfo, spell)
        if ok and type(info) == "table" then
            local learned = Plain(info.learned)
            if learned == true then return true end
            if learned == false then answer = false end
        end
    end
    return answer
end

local function SpellKnown(spell)
    local SB = C_SpellBook
    if SB and SB.IsSpellKnown and Plain(SB.IsSpellKnown(spell)) == true then return true end
    if IsPlayerSpell and Plain(IsPlayerSpell(spell)) == true then return true end
    return false
end

-- { [skillLineID] = rank } for the lines the character has.
local function Ranks(out)
    local SI = C_SkillInfo
    if not SI then return end
    local n = SI.GetNumSkillLines and Plain(SI.GetNumSkillLines())
    if type(n) == "number" and SI.GetSkillLineInfo then
        for i = 1, n do
            local a = SI.GetSkillLineInfo(i)
            if type(a) == "table" and Plain(a.isHeader) ~= true then
                local id, rank = Plain(a.skillID), Plain(a.rank)
                if type(id) == "number" and type(rank) == "number" and rank > 0 then out[id] = rank end
            end
        end
    end
    if SI.GetSkillLineInfoByID then
        for _, line in ipairs(D.LINES) do
            if out[line] == nil then
                local a = SI.GetSkillLineInfoByID(line)
                local rank = type(a) == "table" and Plain(a.rank)
                if type(rank) == "number" and rank > 0 then out[line] = rank end
            end
        end
    end
end

-- The buff food in the bags: { { id, name, icon, amount, count }, ... }, and whether the game still has an item's text to
-- load. It asks the same question the Food button does (FoodDrink.Inspect, which reads the item's own text, never a list),
-- with buff food let in. readOnly: ask the game for nothing (the settings page's list).
function C.BuffFoods(readOnly)
    local F, out, waiting = R.FoodDrink, {}, false
    if not (F and F.Inspect and F.Vocabulary and C_Container and C_Container.GetContainerNumSlots) then return out, false end
    local names, words = F.Vocabulary()
    local level, seen = UnitLevel("player") or 0, {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and Plain(info.itemID)
            if id and not seen[id] then
                seen[id] = true
                local item, still = F.Inspect(id, names, words, readOnly, level, true)
                if still then waiting = true end
                if item and item.buff and item.kinds and item.kinds.food then
                    local count = Plain(C_Item.GetItemCount(id)) or 0
                    if count > 0 then
                        out[#out + 1] = { id = id, name = item.name, icon = item.icon, amount = item.amount, count = count }
                    end
                end
            end
        end
    end
    return out, waiting
end

local function Facts()
    local facts, waiting = { count = {}, known = {}, rank = {} }, false
    for _, id in ipairs(D.ITEMS) do facts.count[id] = Plain(C_Item.GetItemCount(id)) or 0 end
    for _, id in ipairs(D.SPELLS) do
        local known = KnownRecipe(id)
        if known ~= nil then facts.known[id] = known end
    end
    Ranks(facts.rank)
    facts.fireSpell = SpellKnown(D.FIRE_SPELL)
    if C.Get("eat") then
        local foods, still = C.BuffFoods(false)
        waiting = still
        local pick = S.ChooseFood(foods, C.Get("eatMode"), C.Get("eatItem"))
        if pick then facts.eat = { item = pick.id, name = pick.name, count = pick.count } end
    end
    return facts, waiting
end

-- The bar's size now (at least one cell), for the stand-in EllesmereUI moves.
function C.Footprint()
    return S.Footprint(math.max(1, #entries), C.Get("size"), C.Get("spacing"), C.Get("perLine"), C.Get("layout") == "vertical")
end

-- Names and icons for the plan. The second result is true when the game hasn't loaded an item yet (it is asked to).
local function Resolve(list)
    local waiting = false
    for _, e in ipairs(list) do
        if e.state == "cast" then
            e.label = (C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(e.spell))) or e.name
            e.icon = (C_Spell.GetSpellTexture and Plain(C_Spell.GetSpellTexture(e.spell))) or UNKNOWN_ICON
        else
            local name = Plain(C_Item.GetItemNameByID(e.item))
            local icon = Plain(C_Item.GetItemIconByID(e.item))
            if name == nil or icon == nil then
                waiting = true
                if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.item) end
            end
            e.itemName, e.label, e.icon = name, name or e.name, icon or UNKNOWN_ICON
        end
        if e.group then e.groupName = D.GROUP_BY_KEY[e.group].name end
    end
    return waiting
end

---------------------------------------------------------------------------
-- Fading: the bar's opacity, or the idle opacity until the mouse is over a button. The container is a plain frame,
-- so this works in combat too.
---------------------------------------------------------------------------
local HOVER_GRACE = 0.05
local FADE_IN, FADE_OUT = 0.12, 0.25
local fader, fade, alphaNow

local function AnyButtonHovered()
    for _, b in ipairs(buttons) do
        if b:IsShown() and b:IsMouseOver() then return true end
    end
    return false
end

local function ApplyAlpha(fading)
    if not container then return end
    local alpha = C.Get("buttonOpacity")
    if C.Get("mouseover") and not hovering and not (mover and mover:IsShown()) then alpha = C.Get("idleOpacity") end
    alpha = alpha / 100
    if alpha == alphaNow then return end
    local from = alphaNow
    alphaNow = alpha
    if fader then fader:Stop() end
    container:SetAlpha(alpha)
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

---------------------------------------------------------------------------
-- When it shows (plain frame: also in combat)
---------------------------------------------------------------------------
local function Context()
    local inInstance, kind = IsInInstance()
    local ctx = { instanceType = inInstance and kind or "none", resting = IsResting() and true or false,
        combat = InCombat() and true or false }
    -- Whether a campfire is near. The game may not answer in combat, so then it is "don't know", which never hides.
    if not ctx.combat and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(D.NEARBY_AURA)
        if aura == nil then ctx.nearFire = false
        elseif not (issecretvalue and issecretvalue(aura)) then ctx.nearFire = true end
    end
    return ctx
end

local function ApplyVisibility()
    if not container then return end
    local visible, why = S.Visible(WhenOptions(), Context())
    lastHidden = (not visible) and why or nil
    if not visible and mover and mover:IsShown() then visible = true end   -- Edit Mode: it can be seen to be moved
    container:SetShown(visible and #entries > 0)
end

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
local function ShowTooltip(button)
    local e = button.entry
    if not (GameTooltip and e) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local dim = 0.69
    if e.state == "have" then
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.item) else GameTooltip:SetHyperlink("item:" .. e.item) end
        GameTooltip:AddLine(" ")
        if e.kind == "fire" then
            GameTooltip:AddLine(("Your campfire kit. The fire it lights holds %d camp objects."):format(e.slots), dim, 0.66, 0.6, true)
        elseif e.kind == "object" then
            GameTooltip:AddLine(("%s camp object, tier %d."):format(e.groupName, e.tier), dim, 0.66, 0.6, true)
        elseif e.kind == "eat" then
            GameTooltip:AddLine(C.Get("eatMode") == "choose" and "The buff food you chose." or "The buff food in your bags that restores the most.", dim, 0.66, 0.6, true)
            GameTooltip:AddLine(C.Get("eatSit") and "Click to eat it and sit down." or "Click to eat it.", 0.79, 0.64, 0.29)
        end
        if e.kind ~= "eat" then GameTooltip:AddLine("Click to use it.", 0.79, 0.64, 0.29) end
    elseif e.state == "cast" then
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(e.spell) else GameTooltip:SetText(e.label, 1, 1, 1) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("No campfire kit in your bags, so this lights a basic campfire.", dim, 0.66, 0.6, true)
        GameTooltip:AddLine("Click to cast it.", 0.79, 0.64, 0.29)
    else
        GameTooltip:SetText(e.label, 1, 1, 1)
        GameTooltip:AddLine("You know this recipe but have none made.", dim, 0.66, 0.6, true)
        GameTooltip:AddLine("Click to open it in your professions window. Nothing is crafted for you.", 0.79, 0.64, 0.29, true)
    end
    if dirty then
        GameTooltip:AddLine("Your bags or recipes changed in combat. This updates when combat ends.", 0.9, 0.45, 0.38, true)
    end
    GameTooltip:Show()
end

local function RefreshTooltip(button)
    if not (GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button) then return end
    if button:IsShown() and button:IsMouseOver() and button.entry then ShowTooltip(button) else GameTooltip:Hide() end
end

local function OpenRecipe(spell)
    local TS = C_TradeSkillUI
    local ok = TS and TS.OpenRecipe and pcall(TS.OpenRecipe, spell)
    if not ok then R.Print("TwichUI: the game wouldn't open that recipe. Open your professions window to find it.") end
end

local pool = {}      -- the buttons the plan's objects use, in order; buttons holds these and the eat button
local eatButton      -- the eat button, made when first wanted, with a name so a key binding can click it
local EAT_NAME = "TwichUICampingEat"
_G["BINDING_NAME_CLICK " .. EAT_NAME .. ":LeftButton"] = "Eat buff food and sit (Camping bar)"

local function NewButton(name)
    local b = CreateFrame("Button", name, container, "SecureActionButtonTemplate")
    buttons[#buttons + 1] = b
    -- Act as the mouse button comes up whatever the game's "cast on key down" setting is, so a recipe click isn't
    -- run twice and a secure click isn't ignored (the marker bar does the same).
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    local well = b:CreateTexture(nil, "BACKGROUND")
    well:SetAllPoints()
    well:SetColorTexture(0.08, 0.06, 0.045, 0.85)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.rim = { top = b:CreateTexture(nil, "OVERLAY"), bottom = b:CreateTexture(nil, "OVERLAY"),
        left = b:CreateTexture(nil, "OVERLAY"), right = b:CreateTexture(nil, "OVERLAY") }
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    local hot = b:CreateTexture(nil, "HIGHLIGHT")
    hot:SetAllPoints()
    hot:SetColorTexture(1, 0.9, 0.6, 0.12)
    b:SetScript("OnEnter", function(self)
        hovering = true
        ApplyAlpha(true)
        ShowTooltip(self)
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
        C_Timer.After(HOVER_GRACE, RecheckHover)
    end)
    b:HookScript("OnClick", function(self) if self.recipe then OpenRecipe(self.recipe) end end)
    b:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)
    return b
end

-- How far EllesmereUI's line reaches INTO the button, so the icon stops where the line starts. EllesmereUI's BorderReach is
-- how far the line reaches outside the frame (negative: inside). Pixels Textured's line sits just outside the edge, so its
-- icon goes right up to it; insetting by the thickness setting, or by Borders.Inside (a clearance for text, not art), leaves a
-- visible gap that grows with the thickness.
local function EllesmereInset(texture, edge)
    local e, key = Borders.Ellesmere(), Borders.EllesmereKey(texture)
    if not (e and key and type(e.BorderReach) == "function") then return 0 end
    local ok, reach = pcall(e.BorderReach, e.BorderPxStep(edge, key), key, nil, nil, nil, nil, nil, nil, edge)
    if ok and type(reach) == "number" then return math.max(0, math.floor(-reach + 0.5)) end
    return 0
end

-- Size, border, zoom and count. Out of combat only: it resizes a secure button.
local function Style(button, entry)
    local size, edge = C.Get("size"), C.Get("borderSize")
    local r, g, b, a = BorderColor()
    local alpha = a * ((entry and entry.state == "craft") and 0.5 or 1)
    button:SetSize(size, size)
    local rim = button.rim
    borderFrames[button] = borderFrames[button] or {}
    local mode = Borders.Draw(borderFrames[button], button, C.Get("borderTexture"), edge, r, g, b, alpha)
    local inset = edge
    if mode == "ellesmere" then
        for _, t in pairs(rim) do t:Hide() end
        inset = EllesmereInset(C.Get("borderTexture"), edge)
    elseif mode == "texture" then
        for _, t in pairs(rim) do t:Hide() end
        inset = edge > 0 and math.max(1, math.floor(edge / 4)) or 0
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
    local z = C.Get("zoom") / 100
    button.icon:SetTexCoord(z, 1 - z, z, 1 - z)
end

local function CountText(entry)
    return (C.Get("showCount") and entry and entry.count and entry.count > 1) and entry.count or ""
end

-- The item's cooldown (camp objects share one). Readable values only.
local function Cooldown(button)
    local cd, e = button.cooldown, button.entry
    if not cd then return end
    local start, duration = 0, 0
    if e and e.state == "have" and C_Container and C_Container.GetItemCooldown then
        local s, d = C_Container.GetItemCooldown(e.item)
        s, d = Plain(s), Plain(d)
        if type(s) == "number" and type(d) == "number" and d > 1.5 then start, duration = s, d end
    end
    cd:SetCooldown(start, duration)
end

-- Points a button at an entry. Out of combat only: it sets secure attributes.
local function Fill(button, entry)
    button.entry = entry
    button.recipe = entry.state == "craft" and entry.spell or nil
    local kind, item, spell, macro
    if entry.kind == "eat" and entry.itemName and C.Get("eatSit") then
        macro = S.EatMacro(entry.itemName, true)
        if macro then kind = "macro" else kind, item = "item", entry.itemName end
    elseif entry.state == "have" and entry.itemName then kind, item = "item", entry.itemName
    elseif entry.state == "cast" then kind, spell = "spell", entry.spell end
    button:SetAttribute("type", kind)
    button:SetAttribute("item", item)
    button:SetAttribute("spell", spell)
    button:SetAttribute("macrotext", macro)
    button.icon:SetTexture(entry.icon)
    button.icon:SetDesaturated(entry.state == "craft")
    button.icon:SetAlpha(entry.state == "craft" and 0.55 or 1)
    button.count:SetText(CountText(entry))
    Style(button, entry)
    Cooldown(button)
end

local function Empty(button)
    button.entry, button.recipe = nil, nil
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("macrotext", nil)
    button.cooldown:SetCooldown(0, 0)
    button:Hide()
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
end

local function Update()
    dirty = false
    Build()
    looks = looks + 1
    local facts, factsWaiting = Facts()
    local list = S.Plan(facts, Options())
    loading = Resolve(list) or factsWaiting
    entries = list
    local size, spacing, perLine = C.Get("size"), C.Get("spacing"), C.Get("perLine")
    local vertical = C.Get("layout") == "vertical"
    local used, wantsEat = 0, false
    for i, entry in ipairs(list) do
        local b
        if entry.kind == "eat" then
            wantsEat = true
            if not eatButton then eatButton = NewButton(EAT_NAME) end
            b = eatButton
        else
            used = used + 1
            b = pool[used]
            if not b then b = NewButton(); pool[used] = b end
        end
        local col, row = S.Cell(i, perLine, vertical)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", container, "TOPLEFT", col * (size + spacing), -row * (size + spacing))
        Fill(b, entry)
        b:Show()
        RefreshTooltip(b)
    end
    for i = used + 1, #pool do Empty(pool[i]) end
    if eatButton and not wantsEat then Empty(eatButton) end
    moveWaiting = false
    if C.Unlock then C.Unlock.Sync() end
    container:SetSize(S.Footprint(#list, size, spacing, perLine, vertical))
    Place(container)
    ApplyVisibility()
    if mover and mover:IsShown() then mover:SetSize(container:GetSize()); Place(mover) end
    if not (mover and mover:IsShown()) and EditModeActive() then ShowMover(true) end
    hovering = AnyButtonHovered()
    ApplyAlpha()
end

local function Look()
    scheduled = false
    if not R:Enabled("campingBar") then return end
    if not R.Life.InWorld() then
        R.Life.Note("waiting-for-world")
        return
    end
    if InCombat() then
        dirty = true
        R.Life.Note("deferred-combat")
        for _, b in ipairs(buttons) do RefreshTooltip(b) end
    else
        R.Perf.Call("camping.look", Update)
    end
end

local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(SETTLE, Look)
end

-- An item's data arrived (GET_ITEM_INFO_RECEIVED: item, success). A load the game says failed is not asked for again,
-- so an ID this client doesn't have can't keep the bar looking.
local function OnDataLoaded(_, success) if loading and success ~= false then Schedule() end end
local function OnRegenEnabled()
    if dirty or moveWaiting then Schedule() else ApplyVisibility() end
end
local function OnVisibilityEvent() ApplyVisibility() end
local function OnAura(unit) if unit == "player" then ApplyVisibility() end end
local function OnCooldown()
    if container and container:IsShown() then
        for _, b in ipairs(buttons) do if b:IsShown() then Cooldown(b) end end
    end
end

---------------------------------------------------------------------------
-- Edit Mode: an outline stands over the bar; drag it to move the bar, right-click to put it back.
---------------------------------------------------------------------------
-- The place the bar should be at may have changed (EllesmereUI's stand-in moved). The bar's buttons are secure, so it moves
-- out of combat only; in combat the move waits and goes to wherever the place is by then. Returns whether it moved now.
function C.Reposition()
    if not container then return false end
    if InCombat() then
        moveWaiting = true
        R.Life.Note("unlock-deferred-combat")
        return false
    end
    Place(container)
    if mover and mover:IsShown() then Place(mover) end
    return true
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(C.Get("size"), C.Get("size"))
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(1000)
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    if mover.SetDontSavePosition then mover:SetDontSavePosition(true) end
    mover:Hide()
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MOVER_ATLAS) then
        fill:SetAtlas(MOVER_ATLAS)
    else
        fill:SetColorTexture(0.55, 0.43, 0.22, 0.35)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("Camping bar")
    mover:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if not (cx and cy and px and py) then Place(self) return end
        SavePosition(math.floor(cx - px + 0.5), math.floor(cy - py + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then SavePosition(nil) end end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: Camping bar", 1, 1, 1)
        GameTooltip:AddLine("Where the camping bar sits. Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mover:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)
end

function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

function ShowMover(shown)
    -- One mover for the place: when EllesmereUI's Unlock Mode is in charge of it, this outline stays away.
    local U = C.Unlock
    if shown and U and U.Drives() then shown = false end
    if shown and R:Enabled("campingBar") and container and #entries > 0 then
        if not mover then BuildMover() end
        mover:SetSize(container:GetSize())
        Place(mover)
        mover:Show()
        container:Show()
    elseif mover then
        mover:StopMovingOrSizing()
        mover:Hide()
        ApplyVisibility()
    end
    ApplyAlpha()
end

-- Shows or hides the outline to suit Edit Mode and who is in charge of the place.
function C.RefreshMover() ShowMover(EditModeActive()) end

local editHooked = false
local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, C)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, C)
end

---------------------------------------------------------------------------
-- Redrawing for a changed setting, and the events
---------------------------------------------------------------------------
local function Restyle()
    if not (container and R:Enabled("campingBar")) then return end
    if InCombat() or dirty or scheduled then Schedule() return end
    for i, b in ipairs(buttons) do
        local e = b.entry
        if e then
            b.count:SetText(CountText(e))
            Style(b, e)
        end
    end
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

-- Listens only while the bar is on, and for the visibility events only while a choice needs them. Safe to call any time.
function C.Refresh()
    local on = R:Enabled("campingBar")
    Want("BAG_UPDATE_DELAYED", Schedule, on)
    Want("SKILL_LINES_CHANGED", Schedule, on)
    Want("SPELLS_CHANGED", Schedule, on)
    Want("NEW_RECIPE_LEARNED", Schedule, on)
    Want("PLAYER_ENTERING_WORLD", Schedule, on)
    Want("GET_ITEM_INFO_RECEIVED", OnDataLoaded, on)
    Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, on)
    Want("BAG_UPDATE_COOLDOWN", OnCooldown, on)
    Want("SPELL_TEXT_UPDATE", OnDataLoaded, on and C.Get("eat"))
    Want("PLAYER_REGEN_DISABLED", OnVisibilityEvent, on and C.Get("hideCombat"))
    Want("PLAYER_UPDATE_RESTING", OnVisibilityEvent, on and C.Get("hideResting"))
    Want("UNIT_AURA", OnAura, on and C.Get("onlyNearFire"))
    if on then
        HookEditMode()
        ApplyAlpha()
        Schedule()
    else
        dirty, loading, scheduled, moveWaiting = false, false, false, false
        lastHidden = nil
        if container then container:Hide() end
        ShowMover(false)
    end
    if C.Unlock then C.Unlock.Refresh() end
end

function Changed(key)
    if ALPHA_KEYS[key] then ApplyAlpha()
    elseif PAINT_KEYS[key] then Restyle()
    elseif WHEN_KEYS[key] then C.Refresh(); ApplyVisibility()
    else C.Refresh() end
end

-- For /tui diagnostics gauges and the settings page. Read only.
function C.Snapshot()
    local events = 0
    for _ in pairs(active) do events = events + 1 end
    local shown = 0
    for _, b in ipairs(buttons) do if b:IsShown() then shown = shown + 1 end end
    return { enabled = R:Enabled("campingBar"), built = container ~= nil, shown = container ~= nil and container:IsShown() or false,
        events = events, buttons = #buttons, entries = #entries, buttonsShown = shown, looks = looks,
        deferred = dirty, loading = loading, hiddenBy = lastHidden, eat = eatButton ~= nil and eatButton:IsShown() or false }
end

-- Why the bar is hidden by its visibility choices right now, or nil.
function C.HiddenBy() return lastHidden end
function C.Entries() return entries end

R:OnInit(C.Refresh)
R.Profiles.OnApply("layout", "camping", C.Refresh)
