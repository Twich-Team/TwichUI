-- TwichUI: Battle.net friend login
-- When a Battle.net friend comes online, a small title card in the zone card's manner, with
-- no frame: their name with a Horde or Alliance mark beside it when the game says which
-- faction they play, a bronze rule, and "Online as <character>". It takes the place of the
-- game's own friend-online pop-up (BNToastFrame): while this is on, that frame is told to
-- stop listening for BN_FRIEND_ACCOUNT_ONLINE, and only that event. Its offline, broadcast,
-- friend-request and club-invite toasts, and the line in chat, are left alone. Turning this
-- off gives the event back.
-- The game's own Social options still rule: with "Show Toast Window" or "Online Friends"
-- off, nothing shows. Nothing shows for the Battle.net mobile app, at login or reload, or in
-- combat, and it waits for combat and banners to pass. It shows beside the zone, training and Welcome Back cards,
-- which sit at the top, and waits only for another card in its own place (modules/Notify.lua decides that). Several friends
-- arriving together give one card. Only the name, character and faction the game gives are
-- shown; nothing is stored but the card's place (if moved in Edit Mode) and the chime's channel. No chat,
-- nothing sent, and it takes no clicks. It plays one soft chime (media/sounds/TwichUI_Notification.mp3)
-- unless that is switched off. A sound file can't be given its own volume, so the chime follows one of
-- the game's own volume channels, chosen in the options (Sound Effects by default).
-- Scope, as it stands: Battle.net account-level logins only (BN_FRIEND_ACCOUNT_ONLINE). It does not announce
-- logoffs, character (in-game list) friends, or a Battle.net friend who was already online starting WoW.
-- /tui diagnostics (diag/Friends.lua) can show which of these a real session had.

local R = TwichUI
local N = R.Notify
local F = {}
R.FriendLogin = F

local EVENT = "BN_FRIEND_ACCOUNT_ONLINE"
local SETTLE = 1            -- seconds after the event before looking: the friend's game details arrive just after it, and a burst becomes one card
local LOGIN_QUIET = 5       -- seconds after login or reload when logins are not announced
local RETRY, RETRIES = 2, 4 -- looks for a friend's name the game hasn't given yet; then the login is let go
local TTL = 10              -- seconds a card may wait for combat, a banner or another card in its place; a login is not worth waiting minutes for
local MAX_WAITING = 20
local FADE_IN, FADE_OUT = 0.8, 1.4   -- the zone card's
local HOLD = 3.2
local SLIDE = 28            -- pixels the card flows in from the left as it fades in (0 with Reduced motion)
local WIDTH, HEIGHT = 360, 64
local ICON = 22             -- the faction mark's height
local ICON_GAP = 7
local DEFAULT_X, DEFAULT_Y = 16, 300   -- default place: near the left edge, above the lower-left where the game's pop-up sits by default
local SOUND_FILE = "TwichUI_Notification.mp3"
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"   -- Edit Mode's own highlight, when the client has it

-- Faction names are the game's English tokens, as UnitFactionGroup gives them. The mark is the
-- client's own PvP unit-frame icon, or its battleground-timer emblem when that is missing.
local FACTIONS = {
    Horde = { atlas = "UI-HUD-UnitFrame-Player-PVP-HordeIcon", texture = [[Interface\Timer\Horde-Logo]] },
    Alliance = { atlas = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", texture = [[Interface\Timer\Alliance-Logo]] },
}

local waiting = {}          -- BNet account ids that have come online and not been shown yet
local pending = 0           -- bumped to drop a waiting look; a look only runs if it is still current
local quietUntil = 0
local taken = false         -- the game's pop-up has had this event taken from it by us
local active = {}           -- [event] = handler, while registered
local card

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return nil end
    return text
end

local function Escape(text) return (text:gsub("|", "||")) end

-- Decisions, for /tui diagnostics. Why a login was skipped or let go is counted always (a handful of
-- integers, no friend is named); every decision is also traced while tracing is on, with the friend
-- shown only as an anonymous label.
local COUNTED = { skip = true, dropped = true, ["look:skipped"] = true, ["look:gave-up"] = true, ["submit:refused"] = true }
local MAX_REASONS = 24
local reasons, reasonKinds = {}, 0

local function Note(stage, id, detail)
    if COUNTED[stage] and type(detail) == "string" then
        local key = stage .. ":" .. detail
        if reasons[key] then
            reasons[key] = reasons[key] + 1
        elseif reasonKinds < MAX_REASONS then
            reasons[key], reasonKinds = 1, reasonKinds + 1
        end
    end
    local D = R.Diag
    if D then D.Trace("friend", stage, detail, id) end
end

-- The card needs the Chronicle's look and the arrival card's fonts and rule. Without them there is
-- nothing to show, and the game's own pop-up must be left alone.
local function Capable()
    local S, A = R.ChronicleStyle, R.Arrival
    return S and A and A.Rule and A.SetFont and S.color and true or false
end

---------------------------------------------------------------------------
-- What to say. Pure apart from the one call that asks the game about the friend.
---------------------------------------------------------------------------

-- "Name#1234" shown as "Name", as the game does when an account has no name to show.
local function ShortTag(tag)
    tag = Plain(tag)
    if not tag then return nil end
    local short = tag:match("^([^#]*)#")
    return Plain(short or tag)
end

-- { name, character, faction } for a Battle.net account id, or nil when the game doesn't (yet) give a name;
-- then a second value says why ("bad-id", "no-api", "no-info", "no-name").
-- faction is "Horde" or "Alliance" only; anything else (no game, or Neutral) is left out.
function F.Describe(id)
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return nil, "bad-id" end
    if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil, "no-api" end
    local info = C_BattleNet.GetAccountInfoByID(id)
    if type(info) ~= "table" then return nil, "no-info" end
    local name = Plain(info.accountName) or ShortTag(info.battleTag)
    if not name then return nil, "no-name" end
    local game = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local faction = Plain(game.factionName)
    return {
        name = name,
        character = Plain(game.characterName),
        faction = faction and FACTIONS[faction] and faction or nil,
    }
end

-- The card's second line.
function F.Subline(entries)
    local first = entries[1]
    if #entries > 1 then
        local others = #entries - 1
        return ("and %d other%s online"):format(others, others == 1 and "" or "s")
    end
    return first.character and ("Online as " .. Escape(first.character)) or "Online"
end

---------------------------------------------------------------------------
-- The chime. PlaySoundFile takes a channel but no volume of its own, so the player chooses which of
-- the game's volume sliders it follows (TwichUIDB.ui.friendLoginChannel).
---------------------------------------------------------------------------
F.CHANNELS = {
    { key = "SFX", label = "Sound Effects", tooltip = "Follows the Sound Effects volume in the game's Audio options, and is silent when sound effects are off. Like the game's own pop-up." },
    { key = "Dialog", label = "Dialog", tooltip = "Follows the Dialog volume, so you can set it apart from other sound effects." },
    { key = "Ambience", label = "Ambience", tooltip = "Follows the Ambience volume, so you can set it apart from other sound effects." },
    { key = "Master", label = "Master", tooltip = "Follows only the Master volume, so it plays even when sound effects are off." },
}
F.CHANNEL_DEFAULT = "SFX"

-- The chosen channel; the default when nothing (or something unknown) is saved.
function F.SoundChannel()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.friendLoginChannel
    for _, channel in ipairs(F.CHANNELS) do
        if channel.key == saved then return channel.key end
    end
    return F.CHANNEL_DEFAULT
end

-- Plays the chime once on the chosen channel. Returns whether the game took it.
function F.PlaySound()
    if not PlaySoundFile then return false end
    return PlaySoundFile(R:SoundPath(SOUND_FILE), F.SoundChannel()) and true or false
end

---------------------------------------------------------------------------
-- Where it goes: the card's lower-left corner, from the screen's lower-left, as moved in Edit Mode
-- (TwichUIDB.ui.friendLoginPlace), or the default.
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end

function F.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.friendLoginPlace
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return DEFAULT_X, DEFAULT_Y
end

local function Place(frame)
    local x, y = F.Position()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

---------------------------------------------------------------------------
-- The card. No frame or backdrop, like the zone card. Made the first time it is needed.
---------------------------------------------------------------------------
local function Stop()
    card.anim:Stop()
    card:Hide()
end

-- Takes the card down and tells the coordinator its place is free.
local function Hide()
    if not card then return end
    Stop()
    N.Finished("friend")
end

-- True while the card is on screen.
function F.IsShowing() return card ~= nil and card:IsShown() end

local function Build()
    if not Capable() then return false end
    local S, A = R.ChronicleStyle, R.Arrival
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, HEIGHT)
    Place(card)
    card:SetClampedToScreen(true)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K

    card.title = card:CreateFontString(nil, "OVERLAY")
    A.SetFont(card.title, A.FONT_TITLE, 20, "SubZoneTextFont")
    card.title:SetShadowColor(0, 0, 0, 0.85)
    card.title:SetShadowOffset(1, -1)
    card.title:SetWordWrap(false)
    card.title:SetTextColor(K.text[1], K.text[2], K.text[3])
    card.title:SetJustifyH("LEFT")
    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetPoint("RIGHT", card.title, "LEFT", -ICON_GAP, 0)
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(100)
    card.sub = card:CreateFontString(nil, "OVERLAY")
    A.SetFont(card.sub, A.FONT_LINE, 15, "SubZoneTextFont")
    card.sub:SetShadowColor(0, 0, 0, 0.85)
    card.sub:SetShadowOffset(1, -1)
    card.sub:SetJustifyH("LEFT")
    card.sub:SetWidth(WIDTH)
    card.sub:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    card.sub:SetPoint("TOPLEFT", card.rule, "BOTTOMLEFT", 0, -6)

    -- The zone card's motion turned sideways, as the card sits at the left edge: set back to the left at
    -- once, flowing right into place as it fades in, then fading away.
    local anim = card:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    card.setBack = anim:CreateAnimation("Translation")
    card.setBack:SetDuration(0)
    card.setBack:SetOrder(1)
    card.flow = anim:CreateAnimation("Translation")
    card.flow:SetSmoothing("OUT")
    card.flow:SetDuration(FADE_IN)
    card.flow:SetOrder(1)
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

-- Puts the faction's mark on the texture. False when there is no faction or the client has neither picture.
local function SetFactionMark(texture, faction)
    local art = faction and FACTIONS[faction]
    if not art then return false end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.atlas)
    if info and info.width and info.height and info.height > 0 then
        texture:SetAtlas(art.atlas)
        texture:SetSize(ICON * info.width / info.height, ICON)
    else
        texture:SetTexture(art.texture)
        texture:SetSize(ICON, ICON)
    end
    return true
end

-- Where the card is, for the coordinator: left, bottom, right, top in screen units. It flows in from
-- SLIDE pixels to the left, so that is counted too.
function F.Bounds()
    local x, y = F.Position()
    return x - SLIDE, y, x + WIDTH, y + HEIGHT
end

-- Draws the card; the coordinator calls this when its turn comes.
-- entries: { { name, character, faction }, ... }, the first one's name leads.
-- preview: a settings preview, drawn above the Settings panel. It touches no friend state and is not traced,
-- and plays the chime only when previews are allowed sound (or asked for it: forceSound, the diagnostics).
local function Show(entries, preview, forceSound)
    if not card and not Build() then Note("card:build-failed") return false end
    Stop()
    Place(card)
    local first = entries[1]
    local marked = SetFactionMark(card.icon, first.faction)
    card.icon:SetShown(marked)
    -- Everything lines up on the card's left edge: the mark first, the name beside it, the rule and
    -- the second line beneath, starting level with the mark.
    local indent = marked and (card.icon:GetWidth() + ICON_GAP) or 0
    card.title:SetWidth(0)
    card.title:SetText(Escape(first.name))
    card.title:SetWidth(math.min(card.title:GetStringWidth() + 2, WIDTH - indent))
    card.title:ClearAllPoints()
    card.title:SetPoint("TOPLEFT", indent, 0)
    card.rule:ClearAllPoints()
    card.rule:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", -indent, -7)
    card.sub:SetText(F.Subline(entries))

    local slide = R:Enabled("arrivalReducedMotion") and 0 or SLIDE
    card.setBack:SetOffset(-slide, 0)
    card.flow:SetOffset(slide, 0)
    card.fadeOut:SetStartDelay(HOLD)
    card:SetFrameStrata(preview and N.PREVIEW_STRATA or "LOW")
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    -- The chime goes with the card appearing, once: never for a request that was dropped, expired or repeated.
    local chime = R:Enabled("friendLoginSound")
    if not preview then Note("card:shown", nil, #entries) end
    if N.SoundWanted(preview and not forceSound, chime) then
        local accepted = F.PlaySound()
        if not preview then Note("sound:requested", nil, accepted and "accepted" or "refused") end
    elseif not preview then
        Note("sound:off")
    end
    return true
end

---------------------------------------------------------------------------
-- When to show it.
---------------------------------------------------------------------------
-- Why a login would not be shown: TwichUI's switch or the game's own Social options. nil when it would.
local function WhyNot()
    if not R:Enabled("friendLogin") then return "module-off" end
    if not GetCVarBool("showToastWindow") then return "game-toast-window-off" end
    if not GetCVarBool("showToastOnline") then return "game-online-friends-off" end
    return nil
end

local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

-- Something that should have the player's attention instead: the reason, or nil. Another TwichUI card
-- in the way is not this: the coordinator holds the card back for that.
local function External()
    if InCombatLockdown and InCombatLockdown() then return "combat" end
    if Toasting() then return "game-banner" end
    return nil
end

-- External() and the card's own earlier showing, for the diagnostics.
local function InTheWay()
    return External() or (F.IsShowing() and "own-card") or nil
end

local Schedule

-- Asks the coordinator to show a card for these friends. Who they are tells two requests apart.
local function Present(entries, ids)
    table.sort(ids)
    return N.Submit({
        kind = "friend", id = table.concat(ids, ","), ttl = TTL,
        valid = function() return R:Enabled("friendLogin") end,
        onDrop = function(reason) Note("dropped", nil, reason) end,
        payload = { entries = entries },
    })
end

local function Try(tries, mine)
    if pending ~= mine or #waiting == 0 then Note("look:stale") return end
    local why = WhyNot()
    if why then Note("look:skipped", nil, why) return end
    local entries, ids, missing = {}, {}, nil
    for _, id in ipairs(waiting) do
        local entry, reason = F.Describe(id)
        if entry then
            entries[#entries + 1] = entry
            ids[#ids + 1] = id
        else
            missing = reason
        end
    end
    if #entries > 0 then
        wipe(waiting)
        local ok, reason = Present(entries, ids)
        Note(ok and "submitted" or "submit:refused", nil, ok and #entries or reason)
        return
    end
    -- The game hasn't given a name yet: look again a few times, then let it go.
    if tries < RETRIES then
        Note("look:retry", nil, (missing or "no-entries") .. " #" .. (tries + 1))
        C_Timer.After(RETRY, function() Try(tries + 1, mine) end)
    else
        Note("look:gave-up", nil, missing or "no-entries")
        wipe(waiting)
    end
end

function Schedule(delay)
    pending = pending + 1
    local mine = pending
    C_Timer.After(delay, function() Try(0, mine) end)
end

---------------------------------------------------------------------------
-- The game's own pop-up. Told to stop listening for this one event while the card is on.
-- The game gives the event back to it when the options load and may again when the Social options
-- change, so this is repeated at login, on loading screens, on those options changing, and
-- whenever the event arrives and finds it back. Nothing is written to the frame, only its event list.
---------------------------------------------------------------------------
local function Takeover()
    local toast = _G.BNToastFrame
    if not (toast and toast.IsEventRegistered and toast.UnregisterEvent) then return end
    if not Capable() then return end   -- no card to put in its place: leave the game's pop-up as it is
    if toast:IsEventRegistered(EVENT) then
        toast:UnregisterEvent(EVENT)
        taken = true
        Note("takeover:taken")
    end
end

-- Gives the event back, as the game would register it itself: only when its own options ask for it.
local function Giveback()
    if not taken then return end
    taken = false
    local toast = _G.BNToastFrame
    if not (toast and toast.IsEventRegistered and toast.RegisterEvent) then return end
    if GetCVarBool("showToastWindow") and GetCVarBool("showToastOnline") and not toast:IsEventRegistered(EVENT) then
        toast:RegisterEvent(EVENT)
        Note("takeover:given-back")
    end
end

local function OnOnline(friendId, isCompanionApp)
    local toast = _G.BNToastFrame
    local stillTheirs = R.Diag and R.Diag.Tracing() and toast and toast.IsEventRegistered and toast:IsEventRegistered(EVENT) or false
    Takeover()   -- if the game's pop-up has the event back, it may already have shown once; this stops the next
    Note("event", friendId, isCompanionApp and "companion-app" or (stillTheirs and "game-popup-had-event" or nil))
    if isCompanionApp then Note("skip", friendId, "companion-app") return end   -- the game gives no pop-up for the mobile app either
    if type(friendId) ~= "number" or (issecretvalue and issecretvalue(friendId)) then Note("skip", nil, "bad-id") return end
    if GetTime() < quietUntil then Note("skip", friendId, "login-quiet") return end
    local why = WhyNot()
    if why then Note("skip", friendId, why) return end
    for _, id in ipairs(waiting) do
        if id == friendId then Note("skip", friendId, "duplicate") return end
    end
    if #waiting >= MAX_WAITING then Note("skip", friendId, "queue-full") return end
    waiting[#waiting + 1] = friendId
    Note("queued", friendId)
    Schedule(SETTLE)
end

local function Drop()
    if #waiting > 0 then Note("drop", nil, "loading-screen, " .. #waiting .. " waiting") end
    pending = pending + 1
    wipe(waiting)
    N.Cancel("friend")   -- one waiting or showing; a settings preview is the player's own and stays
end

-- Logging in or reloading isn't anyone arriving; loading screens only clear what was waiting.
local function OnEnteringWorld(isLogin, isReload)
    if isLogin or isReload then quietUntil = GetTime() + LOGIN_QUIET end
    Takeover()
end

local function OnCvarUpdate(name)
    if type(name) ~= "string" or not name:find("^showToast") then return end
    -- The game may re-register the event just after this; look again once it has.
    Takeover()
    C_Timer.After(0, Takeover)
end

-- The events the card needs, as F.Refresh registers them while it is on.
local WANTED_EVENTS = { EVENT, "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_LOGIN", "CVAR_UPDATE" }

-- What the module is doing right now, for /tui diagnostics. Reads only; nothing is changed.
function F.State()
    local toast = _G.BNToastFrame
    local events, onBus = {}, {}
    for event in pairs(active) do events[#events + 1] = event end
    table.sort(events)
    for _, event in ipairs(WANTED_EVENTS) do
        onBus[event] = active[event] ~= nil and R.frame.IsEventRegistered ~= nil and R.frame:IsEventRegistered(event) and true or false
    end
    return {
        enabled = R:Enabled("friendLogin"),
        notWanted = WhyNot(),
        events = events,
        wantedEvents = WANTED_EVENTS,
        registered = onBus,   -- [event] = the module asked for it and the game has it registered for TwichUI
        capable = Capable(),
        takenFromGame = taken,
        gamePopup = toast and toast.IsEventRegistered and (toast:IsEventRegistered(EVENT) and "has-event" or "event-removed") or "absent",
        waiting = #waiting,
        cardShowing = F.IsShowing(),
        quietLeft = math.max(0, quietUntil - GetTime()),
        inTheWay = InTheWay(),
        soundOn = R:Enabled("friendLoginSound"),
        channel = F.SoundChannel(),
    }
end

-- How many logins were skipped or let go, by reason, since the game started: { ["skip:login-quiet"] = 2, ... }.
function F.Counts()
    local copy = {}
    for key, n in pairs(reasons) do copy[key] = n end
    return copy
end

-- Made-up details, your own faction's mark, for the settings previews and /tui friend.
local function Sample()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return { entries = { { name = "A Friend", character = "Sample", faction = FACTIONS[faction or ""] and faction or nil } } }
end

-- /tui friend: shows the card now with made-up sample details, so it can be looked at without a friend
-- logging in. Skips the combat and options checks (the player asked). No friend state is touched.
-- withSound: play the chime as a real card would, whatever the previews' sound choice (the diagnostics).
function F.Preview(withSound)
    return N.Preview("friend", nil, withSound and { sound = true } or nil)
end

N.Register("friend", {
    label = "Friend login",
    show = function(p, ctx) return Show(p.entries, ctx.preview, p.sound) end,
    dismiss = Hide,
    bounds = F.Bounds,
    hold = function() return FADE_IN + HOLD + FADE_OUT end,
    ready = function() return External() == nil end,
    sample = Sample,
})

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
    TwichUIDB.ui.friendLoginPlace = x and { x = x, y = y } or nil
    Place(mover)
    if card then Place(card) end
    N.Poke()   -- the card is somewhere else now: waiting notices are looked at again
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(WIDTH, HEIGHT)
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
    label:SetText("Friend Login")
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, bottom = self:GetLeft(), self:GetBottom()
        if not (left and bottom) then Place(self) return end
        SavePosition(math.floor(left + 0.5), math.floor(bottom + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then SavePosition(nil) end
    end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: Friend Login", 1, 1, 1)
        GameTooltip:AddLine("Where the card appears when a Battle.net friend comes online. Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mover:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)   -- Edit Mode closing under the pointer
end

local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

-- Shows the outline while Edit Mode is open and the card is on.
local function ShowMover(shown)
    if shown and R:Enabled("friendLogin") then
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
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, F)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, F)
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

-- Listens only while the card is on, and takes the event from the game's pop-up (or gives it back).
-- Safe to call any time.
function F.Refresh()
    local on = R:Enabled("friendLogin")
    Want(EVENT, OnOnline, on)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    Want("PLAYER_LEAVING_WORLD", Drop, on)
    Want("PLAYER_REGEN_DISABLED", Hide, on)   -- makes way for combat
    Want("PLAYER_LOGIN", Takeover, on)
    Want("CVAR_UPDATE", OnCvarUpdate, on)
    if on then Takeover() else Drop() Giveback() end
    HookEditMode()
    ShowMover(on and EditModeActive())
end

R:OnInit(F.Refresh)
