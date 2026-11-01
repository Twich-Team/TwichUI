-- TwichUI: party member fallen
-- When another player in your party dies, a short title card in the zone card's manner, with no frame: "Party member
-- fallen", a small tombstone above it, a bronze rule and "<name> has died.": the name in bold and in the player's class
-- color when the game gives the class, a small role icon before it when the player's group role is known, and the realm in brackets when it gives one (a player from another realm). It plays media/sounds/LAMENT.mp3 once as the card appears, unless that is switched off. No chat,
-- nothing sent, and it takes no clicks.
--
-- What counts. Other players in a normal party (an instance party too): party1 to party4. Never yourself, a pet, an NPC
-- or anyone in a raid group. One notice per confirmed alive-to-dead change of a member, found by GUID (a unit token is
-- reused as the party changes, a name may repeat). A member first seen already dead (joining, logging in, reloading,
-- zoning) is not announced, and neither is one whose state the game has not given yet: only a member seen alive and
-- then dead is. A resurrection and a later death announce again. A Hunter feigning death is taken as alive.
--
-- How it knows. UNIT_HEALTH, UNIT_FLAGS and UNIT_CONNECTION for party1 to party4 (the events the game's own party frames
-- use, sent for group members whatever the distance, not from the combat log), plus the roster events to start and tidy
-- the tracking. No timers and no OnUpdate. Tracking is a table of at most the party's GUIDs.
--
-- Showing. The card is a notification kind (modules/Notify.lua): it queues, takes turns with the zone card where they
-- overlap, shows one death at a time and keeps each death's card. It borrows the zone card's appearance (modules/NotifyLook.lua
-- scope "arrival"). It shows during combat, as deaths happen there, and waits only for a game banner.
--
-- The scene. Behind the card hangs a brief spectral mist (modules/PartyDeathMist.lua), started and stopped with the card.
-- The role icon (tank, healer or damage, media/partydeath/role-*.tga) is the game's own group role for that exact player,
-- read from UnitGroupRolesAssigned when the death is announced and kept with the card's entry; never guessed from class or
-- gear. No role (none set, not readable) gives the text-only line with nothing reserved for an icon.
--
-- Sound. One file, on the Sound Effects channel (the game's own volume and mute apply; nothing is forced on). A second
-- death while LAMENT is still playing gets its card but not a second, overlapping copy of the sound.

local R = TwichUI
local N = R.Notify
local A = R.Arrival
local Perf = R.Perf
local P = {}
R.PartyDeath = P

local KIND = "partydeath"
local LOOK = "arrival"              -- the appearance scope it borrows
local TITLE = "Party member fallen"
local FADE_IN, FADE_OUT, HOLD, RISE = 0.8, 1.4, 6, 8
local WIDTH, HEIGHT = 560, 154
local ICON = 64                 -- the tombstone, drawn from media/partydeath/tombstone.tga (128 px)
local ICON_FILE = R.PATH .. [[media\partydeath\tombstone]]
local TOP_OFFSET = -150             -- the zone card's place, so the two take turns
local TTL = 45                      -- seconds a card may wait: four deaths one after another still all show
local NAME_FONT = R.PATH .. [[media\fonts\AlegreyaSans-Bold.ttf]]   -- the name's bold face
local SOUND_FILE = "LAMENT.mp3"
local SOUND_CHANNEL = "SFX"
local SOUND_SECONDS = 6.1           -- the file is 6.05 s long: a copy is not started over one still playing

local ROLE_ICON = 20                -- the role icon's side, beside the 18 pt name
local ROLE_GAP = 5
-- The game's group role names, mapped to our art explicitly (the damage role is "DAMAGER"; "NONE" and anything else: no icon).
local ROLE_ART = {
    TANK = R.PATH .. [[media\partydeath\role-tank]],
    HEALER = R.PATH .. [[media\partydeath\role-healer]],
    DAMAGER = R.PATH .. [[media\partydeath\role-dps]],
}
local ROLE_KEY = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local ROLE_FILE = { tank = ROLE_ART.TANK, healer = ROLE_ART.HEALER, dps = ROLE_ART.DAMAGER }

local UNIT_LIST = { "party1", "party2", "party3", "party4" }
local UNITS = { party1 = true, party2 = true, party3 = true, party4 = true }
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION" }
local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD" }

local card
local evf                   -- the private event frame, made when the feature is first on
local registered = false
local tracked = {}          -- [guid] = "alive" | "dead" | "unknown", for the members seen in the last look
local deaths = 0            -- notices made so far; keeps one death's id from being another's
local soundUntil = 0        -- until when the last LAMENT is taken as still playing

local function Secret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end
local function Plain(v) if Secret(v) then return nil end return v end

---------------------------------------------------------------------------
-- The sound
---------------------------------------------------------------------------
-- Plays LAMENT once, unless the last copy is still playing. Returns whether the game took it.
function P.PlaySound()
    if not PlaySoundFile then return false end
    local now = GetTime()
    if now < soundUntil then return false end
    local willPlay = PlaySoundFile(R:SoundPath(SOUND_FILE), SOUND_CHANNEL)
    if willPlay then soundUntil = now + SOUND_SECONDS end
    return willPlay and true or false
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function Grow() return A.Grow(LOOK) end

-- The class's color as { r, g, b }, from the token the game gave ("MAGE"); nil when it is unknown. Another addon's custom
-- class colors are honored, as the game's own frames do.
local function ClassColor(class)
    if type(class) ~= "string" then return nil end
    local colors = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if type(colors) ~= "table" or type(colors.r) ~= "number" then return nil end
    return { colors.r, colors.g, colors.b }
end
local function CardHeight() return math.ceil(HEIGHT * Grow()) end

local function Stop()
    card.anim:Stop()
    if R.PartyDeathMist then R.PartyDeathMist.Stop() end
    card:Hide()
    card.payload = nil
end

local function Hide()
    if not card then return end
    Stop()
    N.Finished(KIND)
end

local function Build()
    local S = R.ChronicleStyle
    if not (S and A and A.Rule and A.SetFont) then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, CardHeight())
    card:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K

    local function Line(path, size, fallback)
        local fs = card:CreateFontString(nil, "OVERLAY")
        A.SetFont(fs, path, size, fallback)
        fs:SetJustifyH("CENTER")
        fs:SetWidth(WIDTH)
        fs:SetShadowColor(0, 0, 0, 0.85)
        fs:SetShadowOffset(1, -1)
        return fs
    end
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("TOP", 0, 0)
    card.icon:SetTexture(ICON_FILE)
    card.role = card:CreateTexture(nil, "ARTWORK")   -- informational only: a region of the card, which takes no clicks
    card.role:SetSize(ROLE_ICON, ROLE_ICON)
    card.role:Hide()
    card.title = Line(A.FONT_TITLE, 26, "ZoneTextFont")
    card.title:SetPoint("TOP", card.icon, "BOTTOM", 0, -4)
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(140)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -7)
    -- The line is two pieces side by side, centred together: the name (bold, in the class color when known) and the rest.
    card.name = Line(NAME_FONT, 18, "SubZoneTextFont")
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    card.body = Line(A.FONT_LINE, 18, "SubZoneTextFont")
    card.body:SetJustifyH("LEFT")
    card.body:SetWordWrap(false)
    card.body:SetPoint("LEFT", card.name, "RIGHT", 0, 0)

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

-- Puts the text and the look on the card, for the look as it is now (the entrance and the sound are not touched).
local function Fill(payload)
    local K = card.K
    card.payload = payload
    card:SetHeight(CardHeight())
    A.Typeset(LOOK, card.title, { role = "title", path = A.FONT_TITLE, size = 26, fallback = "ZoneTextFont", color = K.text })
    card.title:SetText(TITLE)
    A.PaintRule(LOOK, card.rule, 1)
    A.Typeset(LOOK, card.body, { role = "detail", path = A.FONT_LINE, size = 18, fallback = "SubZoneTextFont", color = K.stone })
    local tone = ClassColor(payload.class)
    A.Typeset(LOOK, card.name, { role = "detail", path = NAME_FONT, size = 18, fallback = "SubZoneTextFont", color = tone or K.stone, fixed = tone ~= nil })
    A.Typeset(LOOK, card.body, { role = "detail", path = A.FONT_LINE, size = 18, fallback = "SubZoneTextFont", color = K.stone })
    card.name:SetText(payload.name or "")
    if payload.name then
        card.body:SetText(((payload.realm and " (" .. payload.realm .. ")") or "") .. " has died.")
    else
        card.body:SetText("A party member has died.")
    end
    -- Both pieces take their own width (neither wraps), and the pair is centred; a very long name is cut short, not the rest.
    card.name:SetWidth(0)
    card.body:SetWidth(0)
    local nameWidth, restWidth = payload.name and A.TextWidth(card.name, WIDTH) or 0, A.TextWidth(card.body, WIDTH)
    if nameWidth + restWidth > WIDTH then nameWidth = math.max(1, WIDTH - restWidth) end
    -- A known role puts its icon first in the same centred line; otherwise the icon is hidden and takes no room.
    local roleFile = payload.name and ROLE_FILE[payload.role]
    local lead = roleFile and (ROLE_ICON + ROLE_GAP) or 0
    if lead > 0 and nameWidth + restWidth + lead > WIDTH then nameWidth = math.max(1, WIDTH - restWidth - lead) end
    if payload.name then card.name:SetWidth(nameWidth) end
    local total = lead + nameWidth + restWidth
    card.name:ClearAllPoints()
    card.name:SetPoint("TOPLEFT", card.rule, "BOTTOM", -total / 2 + lead, -8)
    card.role:ClearAllPoints()
    if roleFile then
        card.role:SetTexture(roleFile)
        card.role:SetPoint("RIGHT", card.name, "LEFT", -ROLE_GAP, 0)
        card.role:Show()
    else
        card.role:Hide()
        card.role:SetTexture(nil)
    end
    local width = math.max(A.TextWidth(card.title, WIDTH), total, 140)
    A.Backdrop(LOOK, card, { top = card.icon, bottom = card.name, width = width })
end

function P.Restyle()
    if card and card:IsShown() and card.payload then Fill(card.payload) end
end

local function Show(payload, preview)
    if not card and not Build() then return false end
    Stop()
    Fill(payload)
    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card.fadeOut:SetStartDelay(HOLD)
    card:SetFrameStrata(preview and N.PREVIEW_STRATA or "LOW")
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    if R.PartyDeathMist then R.PartyDeathMist.Play(card, CardHeight(), R:Enabled("arrivalReducedMotion")) end
    -- Only now, as the card starts: not on a redraw, a duplicate or a settings change.
    if N.SoundWanted(preview, R:Enabled("partyDeathSound")) then P.PlaySound() end
    return true
end

-- Where the card is, for the coordinator: left, bottom, right, top in screen units.
local function Bounds()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" then return nil end
    local top = height + TOP_OFFSET
    return width / 2 - WIDTH / 2, top - CardHeight(), width / 2 + WIDTH / 2, top
end

local function Ready()
    local toast = EventToastManagerFrame
    return not (toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting())
end

N.Register(KIND, {
    label = "Party member fallen",
    show = function(p, ctx) return Show(p, ctx.preview) end,
    dismiss = Hide,
    bounds = Bounds,
    restyle = P.Restyle,
    hold = function() return FADE_IN + HOLD + FADE_OUT end,
    ready = Ready,
    sample = function() return { name = "Aldric Stormveil", class = "PALADIN", role = "tank" } end,
})

---------------------------------------------------------------------------
-- Who died
---------------------------------------------------------------------------
-- The unit's GUID and what is known of it: "alive", "dead" or "unknown" (not connected, or the game has not given its health
-- yet). nil when it is not a member this applies to: not a party1-4 player, yourself, or the group is a raid.
local function Read(unit)
    if not UNITS[unit] or (IsInRaid and IsInRaid()) then return nil end
    if not UnitExists(unit) or Plain(UnitIsPlayer(unit)) ~= true then return nil end
    if Plain(UnitIsUnit(unit, "player")) ~= false then return nil end
    local guid = Plain(UnitGUID(unit))
    if type(guid) ~= "string" then return nil end
    local state = "unknown"
    if Plain(UnitIsConnected(unit)) == true then
        local max = UnitHealthMax(unit)
        local dead = Plain(UnitIsDeadOrGhost(unit))
        if (Secret(max) or (type(max) == "number" and max > 0)) and type(dead) == "boolean" then
            local feigning = UnitIsFeignDeath and Plain(UnitIsFeignDeath(unit)) == true
            state = (dead and not feigning) and "dead" or "alive"
        end
    end
    return guid, state
end

-- The name, the realm (only for a player from another realm: the game gives it then) and the class token, each nil when
-- the game has not given it. No name means the card says "A party member".
local function Who(unit)
    local name, realm = UnitName(unit)
    name, realm = Plain(name), Plain(realm)
    local class
    if UnitClass then class = Plain(select(2, UnitClass(unit))) end
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return {} end
    if type(realm) ~= "string" or realm == "" then realm = nil end
    return { name = name, realm = realm, class = type(class) == "string" and class or nil }
end

-- The player's group role as "tank", "healer" or "dps", or nil. Read for this exact player: the unit must still be the GUID that
-- was just seen (a token is reused as the party changes), and only the game's own assignment counts.
local function Role(unit, guid)
    if not UnitGroupRolesAssigned or Plain(UnitGUID(unit)) ~= guid then return nil end
    return ROLE_KEY[Plain(UnitGroupRolesAssigned(unit))]
end

local function Announce(unit, guid)
    deaths = deaths + 1
    local who = Who(unit)
    who.role = who.name and Role(unit, guid) or nil   -- snapshotted now, with the card's entry: a queued card keeps its own player's role
    N.Submit({
        kind = KIND, id = guid .. ":" .. deaths, ttl = TTL,
        valid = function() return R:Enabled("partyDeath") end,
        payload = who,
    })
end

-- Looks at one member now. Announces only a change from alive to dead; anything else (first sight, unknown, already
-- dead) just records what is seen. Returns the member's GUID, or nil when this is not a member that counts.
function P.Observe(unit)
    local guid, state = Read(unit)
    if not guid then return nil end
    local before = tracked[guid]
    tracked[guid] = state
    if before == "alive" and state == "dead" then Announce(unit, guid) end
    return guid
end

-- The party as it is now: everyone is looked at, and whoever has left is forgotten. A member first seen here is only
-- recorded, so a death from before is not announced.
local function Rescan()
    if IsInRaid and IsInRaid() then tracked = {} return end
    local seen = {}
    for _, unit in ipairs(UNIT_LIST) do
        local guid = P.Observe(unit)
        if guid then seen[guid] = true end
    end
    for guid in pairs(tracked) do
        if not seen[guid] then tracked[guid] = nil end
    end
end

function P.OnEvent(event, unit)
    if event == "GROUP_ROSTER_UPDATE" then
        Rescan()
    elseif event == "PLAYER_ENTERING_WORLD" then
        tracked = {}    -- after a loading screen nobody has been seen yet: whoever is dead now was dead before
        Rescan()
    elseif event == "PLAYER_LEAVING_WORLD" then
        tracked = {}
    elseif UNITS[unit] then
        P.Observe(unit)
    end
end

---------------------------------------------------------------------------
-- Turning it on and off
---------------------------------------------------------------------------
-- Registers exactly the events that are needed. Safe to call any time.
function P.Refresh()
    local on = R:Enabled("partyDeath")
    if on and not registered then
        if not evf then
            evf = CreateFrame("Frame")
            evf:SetScript("OnEvent", Perf.Wrap("partyDeath.event", function(_, event, unit) P.OnEvent(event, unit) end))
        end
        registered = true
        for _, event in ipairs(UNIT_EVENTS) do evf:RegisterUnitEvent(event, unpack(UNIT_LIST)) end
        for _, event in ipairs(ROSTER_EVENTS) do evf:RegisterEvent(event) end
        tracked = {}
        Rescan()   -- turned on in this session: whoever is dead now is not announced
    elseif not on and registered then
        registered = false
        evf:UnregisterAllEvents()
        tracked = {}
    end
    if not on then N.Cancel(KIND) end   -- a card waiting or showing goes; a settings preview is the player's own and stays
end

-- For /tui diagnostics: counts only, no names or GUIDs. Reads only.
function P.Snapshot()
    local count = 0
    for _ in pairs(tracked) do count = count + 1 end
    return {
        enabled = R:Enabled("partyDeath"), sound = R:Enabled("partyDeathSound"),
        events = registered and (#UNIT_EVENTS + #ROSTER_EVENTS) or 0, tracked = count,
        cardShowing = card ~= nil and card:IsShown(), soundPlaying = GetTime() < soundUntil,
        mist = R.PartyDeathMist and R.PartyDeathMist.Snapshot() or nil,
    }
end

if R.OnSettingsClosed then R.OnSettingsClosed(function() N.DropPreviews(KIND) end) end   -- a preview never outlives the settings window

R:OnInit(P.Refresh)
