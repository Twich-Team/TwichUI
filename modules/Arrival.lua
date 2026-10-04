-- TwichUI: zone arrival card
-- Arriving in a new zone shows its name as a short title card: a thin bronze
-- rule and the zone name settle in, stay a moment, then fade away. While it is
-- on it takes the place of the game's own zone text (ZoneTextFrame and
-- SubZoneTextFrame, plain unprotected frames), which is hidden as it appears.
-- Nothing shows at login or reload, nothing while on a flight path (where you
-- land is looked at once), and only the latest place is shown when zones are
-- crossed quickly. Walking into a dungeon or raid shows its name with "Dungeon" or
-- "Raid" beneath it instead of the zone text. Only names the game gives are shown.
-- No sound, no chat.

local R = TwichUI
local A = {}
R.Arrival = A

local SETTLE = 0.6          -- seconds a zone change waits, so quick crossings show only the last place
local LOGIN_QUIET = 5       -- seconds after login or reload when zone changes only note where you are
local RISE = 8              -- pixels the card settles upward (0 with Reduced motion)
local NAME_RETRIES = 2        -- extra looks for an instance's name when the game hasn't given it yet

-- Instance types that get an entry card, and the game's own word for each.
local INSTANCE_LABEL = { party = "LFG_TYPE_DUNGEON", raid = "LFG_TYPE_RAID" }

local TIMING = {
    zone    = { fadeIn = 0.8, fadeOut = 1.4 },
    subzone = { fadeIn = 0.6, fadeOut = 1.0 },
}

-- How long the name stays at full strength between fading in and out: the advanced
-- "How long the card stays" option, kept in TwichUIDB.ui.arrivalHold. A subzone card
-- stays a little shorter.
A.HOLDS = {
    { key = "brief", label = "Brief", seconds = 1.5 },
    { key = "standard", label = "Standard", seconds = 2.2 },
    { key = "long", label = "Long", seconds = 4 },
    { key = "longer", label = "Longer", seconds = 7 },
}
A.HOLD_DEFAULT = "standard"

-- The chosen key and its seconds; the default when nothing (or something unknown) is saved.
function A.HoldChoice()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.arrivalHold
    local fallback
    for _, hold in ipairs(A.HOLDS) do
        if hold.key == saved then return hold.key, hold.seconds end
        if hold.key == A.HOLD_DEFAULT then fallback = hold end
    end
    return fallback.key, fallback.seconds
end

local function Hold(kind)
    local _, seconds = A.HoldChoice()
    if kind == "subzone" then return math.max(1, seconds - 0.8) end
    return seconds
end

local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
local FONT_LINE = R.PATH .. [[media\fonts\Alegreya-Regular.ttf]]
-- The bundled fonts only have Western letters; these clients use the game's zone text font instead.
local NON_WESTERN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

local lastZone, lastSubZone, lastPvP   -- the place last shown or noted, so repeats and login are quiet
local lastInstance            -- "party" or "raid" while inside one (as last noted), so only walking in counts
local nameTries = 0           -- looks already spent waiting for the instance's name
local entryName               -- the name on the entry card just shown, until the game's zone text catches up to it
local quietUntil = 0
local controlLost = false   -- between PLAYER_CONTROL_LOST and PLAYER_CONTROL_GAINED (flight takeoff to landing)
local pending = 0           -- counts zone changes; a waiting check only runs if no newer change came
local active = {}           -- [event] = handler, while registered
local hooked = false
local card

local Schedule   -- defined below; an instance whose name is not known yet looks again

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return nil end
    return text
end

local function Zone() return Plain(GetZoneText and GetZoneText()) end

-- The subzone, or nil when there is none or it is just the zone's own name.
local function SubZone(zone)
    local sub = Plain(GetSubZoneText and GetSubZoneText())
    if sub == zone then return nil end
    return sub
end

-- "party" (dungeon) or "raid" while inside one that gets an entry card, otherwise nil.
local function Instance()
    if not IsInInstance then return nil end
    local inside, kind = IsInInstance()
    if not inside then return nil end
    kind = Plain(kind)
    return INSTANCE_LABEL[kind or ""] and kind or nil
end

local function InstanceName()
    return Plain(GetInstanceInfo and (GetInstanceInfo()))
end

local function OnTaxi()
    return controlLost or (UnitOnTaxi and UnitOnTaxi("player")) or false
end

local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

---------------------------------------------------------------------------
-- PvP territory line, from the game's own strings (the native zone text shows it too).
---------------------------------------------------------------------------
local TINT = {
    sanctuary = { 0.55, 0.70, 0.78 },
    friendly  = { 0.56, 0.70, 0.35 },
    contested = { 0.79, 0.64, 0.29 },
    hostile   = { 0.74, 0.40, 0.32 },
    arena     = { 0.74, 0.40, 0.32 },
    combat    = { 0.74, 0.40, 0.32 },
}

local function Global(name)
    local text = _G[name]
    return type(text) == "string" and text or nil
end

-- Returns the pvp type (or nil) and the line to show for it (or nil).
local function PvP()
    if not (C_PvP and C_PvP.GetZonePVPInfo) then return nil end
    local pvpType, _, factionName = C_PvP.GetZonePVPInfo()
    pvpType = Plain(pvpType)
    if not pvpType then return nil end
    local text
    if pvpType == "sanctuary" then text = Global("SANCTUARY_TERRITORY")
    elseif pvpType == "arena" then text = Global("FREE_FOR_ALL_TERRITORY")
    elseif pvpType == "contested" then text = Global("CONTESTED_TERRITORY")
    elseif pvpType == "combat" then text = Global("COMBAT_ZONE")
    elseif pvpType == "friendly" or pvpType == "hostile" then
        local format = Global("FACTION_CONTROLLED_TERRITORY")
        factionName = Plain(factionName)
        if format and factionName then text = format:format(factionName) end
    end
    return pvpType, text
end

---------------------------------------------------------------------------
-- The card. Made the first time it is needed.
---------------------------------------------------------------------------
local function Palette()
    local style = R.ChronicleStyle and R.ChronicleStyle.color
    return style or {
        text = { 0.93, 0.88, 0.76 }, textDim = { 0.78, 0.74, 0.66 }, stone = { 0.62, 0.58, 0.51 },
        bronze = { 0.55, 0.43, 0.22 }, bronzeLo = { 0.30, 0.23, 0.13 }, gold = { 0.79, 0.64, 0.29 },
    }
end

-- fallback: the game's font object to borrow from when ours can't be used.
local function SetFont(fs, path, size, fallback)
    local locale = GetLocale and GetLocale()
    if NON_WESTERN[locale] or not fs:SetFont(path, size) then
        local font = _G[fallback]
        local file = font and font.GetFont and font:GetFont()
        fs:SetFont(file or STANDARD_TEXT_FONT, size)
    end
end

local function Line(parent, path, size, fallback)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFont(fs, path, size, fallback)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(600)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- A 1px bronze line over a darker 1px shadow, its ends stepping down in pixel blocks.
local STEPS = { 0.55, 0.30, 0.12 }
local STEP_WIDTH = 10

local function Rule(parent, K)
    local rule = CreateFrame("Frame", nil, parent)
    rule:SetSize(160, 2)
    local line = rule:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(K.bronze[1], K.bronze[2], K.bronze[3], 0.9)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    local shadow = rule:CreateTexture(nil, "ARTWORK")
    shadow:SetColorTexture(K.bronzeLo[1], K.bronzeLo[2], K.bronzeLo[3], 0.6)
    shadow:SetHeight(1)
    shadow:SetPoint("BOTTOMLEFT")
    shadow:SetPoint("BOTTOMRIGHT")
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local inner = side == "LEFT" and "TOPRIGHT" or "TOPLEFT"
        local outer = "TOP" .. side
        local anchor = line
        for _, a in ipairs(STEPS) do
            local t = rule:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(K.bronze[1], K.bronze[2], K.bronze[3], a)
            t:SetSize(STEP_WIDTH, 1)
            t:SetPoint(inner, anchor, outer)
            anchor = t
        end
    end
    local mark = rule:CreateTexture(nil, "OVERLAY")
    mark:SetColorTexture(K.gold[1], K.gold[2], K.gold[3], 0.9)
    mark:SetSize(3, 1)
    mark:SetPoint("TOP")
    return rule
end

-- Shared with the level-up training card (modules/Training.lua), so the two cards share one look.
A.FONT_TITLE, A.FONT_LINE = FONT_TITLE, FONT_LINE
A.SetFont = SetFont
A.Rule = Rule

local function Build()
    local K = Palette()
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(600, 120)
    card:SetPoint("TOP", UIParent, "TOP", 0, -150)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K

    card.title = Line(card, FONT_TITLE, 30, "ZoneTextFont")
    card.title:SetPoint("TOP", 0, 0)
    card.rule = Rule(card, K)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -7)
    card.sub = Line(card, FONT_LINE, 17, "SubZoneTextFont")
    card.sub:SetPoint("TOP", card.rule, "BOTTOM", 0, -6)
    card.pvp = Line(card, FONT_LINE, 13, "SubZoneTextFont")

    local anim = card:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    -- Lower the card at once, then let it rise back to its place as it fades in.
    -- The two moves add to nothing, so it ends exactly where it is anchored.
    card.drop = anim:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = anim:CreateAnimation("Translation")
    card.rise:SetSmoothing("OUT")
    card.rise:SetOrder(1)
    card.fadeIn = anim:CreateAnimation("Alpha")
    card.fadeIn:SetFromAlpha(0)
    card.fadeIn:SetToAlpha(1)
    card.fadeIn:SetSmoothing("OUT")
    card.fadeIn:SetOrder(1)
    card.fadeOut = anim:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1)
    card.fadeOut:SetToAlpha(0)
    card.fadeOut:SetSmoothing("IN")
    card.fadeOut:SetOrder(2)
    anim:SetScript("OnFinished", function() card:Hide() end)
    card.anim = anim
end

-- Stops and hides the card at once.
function A.Clear()
    if not card then return end
    card.anim:Stop()
    card:Hide()
end

-- True while a card is on screen (the Welcome Back bookmark waits for it).
function A.IsShowing() return card ~= nil and card:IsShown() end

-- kind: "zone" (title, smaller subzone line, PvP line) or "subzone" (one quieter line, PvP line if it changed).
function A.Show(kind, title, sub, pvpText, pvpType)
    if not card then Build() end
    local K, t = card.K, TIMING[kind]
    A.Clear()

    local subzone = kind == "subzone"
    local c = subzone and K.textDim or K.text
    SetFont(card.title, FONT_TITLE, subzone and 20 or 30, "ZoneTextFont")
    card.title:SetTextColor(c[1], c[2], c[3])
    card.title:SetText(title)
    card.rule:SetWidth(subzone and 80 or 160)
    card.rule:SetAlpha(subzone and 0.6 or 1)
    card.sub:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    card.sub:SetText(sub or "")
    card.sub:SetShown(sub ~= nil)
    local tint = TINT[pvpType] or K.stone
    card.pvp:ClearAllPoints()
    card.pvp:SetPoint("TOP", sub and card.sub or card.rule, "BOTTOM", 0, -4)
    card.pvp:SetTextColor(tint[1], tint[2], tint[3], 0.9)
    card.pvp:SetText(pvpText or "")
    card.pvp:SetShown(pvpText ~= nil)

    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card.rise:SetDuration(t.fadeIn)
    card.fadeIn:SetDuration(t.fadeIn)
    card.fadeOut:SetStartDelay(Hold(kind))
    card.fadeOut:SetDuration(t.fadeOut)

    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
end

---------------------------------------------------------------------------
-- Deciding what is an arrival.
---------------------------------------------------------------------------
local function Note()
    lastZone = Zone()
    lastSubZone = SubZone(lastZone)
    lastPvP = PvP()
    lastInstance = Instance()
    nameTries = 0
    entryName = nil
end

-- Walking into a dungeon or raid from outside: one card with its name. Returns true when
-- the check is finished (a card was shown, or the name is still being waited for). Otherwise
-- the ordinary zone path goes on, as it does when this card is off or the name never comes.
local function CheckInstance(kind)
    if not kind then
        lastInstance, nameTries, entryName = nil, 0, nil
        return false
    end
    if lastInstance then return false end   -- already inside: an internal change, not an entry
    local name = InstanceName()
    if not name and nameTries < NAME_RETRIES then
        nameTries = nameTries + 1
        Schedule()
        return true
    end
    lastInstance, nameTries = kind, 0
    if not name or not R:Enabled("arrivalDungeons") then return false end
    -- This place is the arrival, so the zone path must not show it a second time.
    lastZone, lastSubZone, lastPvP = Zone(), SubZone(Zone()), PvP()
    local label = Global(INSTANCE_LABEL[kind])
    entryName = name
    if not Toasting() then A.Show("zone", name, label) end
    return true
end

-- Looks at where the player is once things have settled, and shows at most one card.
local function Check()
    if not R:Enabled("arrival") or OnTaxi() then return end
    local zone = Zone()
    if not zone then return end
    if GetTime() < quietUntil then Note() return end
    if CheckInstance(Instance()) then return end
    local sub = SubZone(zone)
    local pvpType, pvpText = PvP()
    if entryName and zone ~= lastZone and zone == entryName then
        -- The game's zone text only now says where the entry card already put you: the same arrival.
        entryName = nil
        lastZone, lastSubZone, lastPvP = zone, sub, pvpType
    elseif zone ~= lastZone then
        lastZone, lastSubZone, lastPvP = zone, sub, pvpType
        if not Toasting() then A.Show("zone", zone, sub, pvpText, pvpType) end
    elseif sub ~= lastSubZone then
        lastSubZone = sub
        local pvpChanged = pvpType ~= lastPvP
        lastPvP = pvpType
        if sub and R:Enabled("arrivalSubzones") and not Toasting() then
            A.Show("subzone", sub, nil, pvpChanged and pvpText or nil, pvpType)
        end
    end
end

-- Waits a moment before looking; a newer zone change replaces the waiting one.
function Schedule()
    pending = pending + 1
    local mine = pending
    C_Timer.After(SETTLE, function() if pending == mine then Check() end end)
end

local function OnZoneChanged()
    if OnTaxi() then return end
    Schedule()
end

local function OnControlLost()
    controlLost = true
    pending = pending + 1   -- drop a check that was waiting
end

local function OnControlGained()
    controlLost = false
    Schedule()
end

-- Logging in or reloading isn't arriving anywhere. Other loading screens
-- (a dungeon, a hearthstone) are, and the zone is looked at once they end.
local function OnEnteringWorld(isLogin, isReload)
    if isLogin or isReload then
        controlLost = false
        quietUntil = GetTime() + LOGIN_QUIET
        Note()
    else
        Schedule()
    end
end

local function OnLeavingWorld()
    pending = pending + 1
    A.Clear()
end

---------------------------------------------------------------------------
-- The game's own zone text. Hidden as it appears while the card is on; while
-- off, the hooks do nothing. Added only once the card has been on.
---------------------------------------------------------------------------
local function HideNative(frame)
    if R:Enabled("arrival") then frame:Hide() end
end

local function Hook()
    if hooked then return end
    hooked = true
    if ZoneTextFrame and ZoneTextFrame.HookScript then ZoneTextFrame:HookScript("OnShow", HideNative) end
    if SubZoneTextFrame and SubZoneTextFrame.HookScript then SubZoneTextFrame:HookScript("OnShow", HideNative) end
    -- Make way, as the native zone text does, for event toasts and other banners at the top of the screen.
    if EventToastManagerFrame and EventToastManagerFrame.HookScript then EventToastManagerFrame:HookScript("OnShow", A.Clear) end
    if ZoneText_Clear and hooksecurefunc then hooksecurefunc("ZoneText_Clear", A.Clear) end
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

-- Registers exactly the events that are needed. Safe to call any time.
function A.Refresh()
    local on = R:Enabled("arrival")
    local subzones = on and R:Enabled("arrivalSubzones")
    -- Turned on in this session: where you are now isn't an arrival.
    if on and not active.ZONE_CHANGED_NEW_AREA then Note() end
    if subzones and not active.ZONE_CHANGED then lastSubZone = SubZone(lastZone) end
    if on then Hook() end
    Want("ZONE_CHANGED_NEW_AREA", OnZoneChanged, on)
    Want("ZONE_CHANGED", OnZoneChanged, subzones)
    Want("ZONE_CHANGED_INDOORS", OnZoneChanged, subzones)
    Want("PLAYER_CONTROL_LOST", OnControlLost, on)
    Want("PLAYER_CONTROL_GAINED", OnControlGained, on)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    Want("PLAYER_LEAVING_WORLD", OnLeavingWorld, on)
    if not on then
        controlLost = false
        pending = pending + 1
        A.Clear()
    end
end

R:OnInit(A.Refresh)
