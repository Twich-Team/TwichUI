-- TwichUI: Welcome Back bookmark
-- Logging in to a character with Chronicle history shows one small card, like a
-- ribbon left in a travel journal: "Last noted: The Barrens · 2 hours ago", with
-- Open Chronicle and a close button. It fades away by itself.
-- It only reads the newest Chronicle entry that has a place and a date; it stores
-- nothing and adds no entry. "Last noted" is the Chronicle's own last record, not
-- where the character logged out. It shows only on a real login (never after a
-- reload or a loading screen), waits until the arrival card's quiet time is over,
-- stays away from combat, flight and other banners, and gives up rather than queue.
-- No sound, no chat, nothing sent.

local R = TwichUI
local C = R.Chronicle
local B = {}
R.WelcomeBack = B

local DELAY = 7             -- seconds after login; the zone arrival card is quiet for its first 5
local RETRY = 2             -- seconds between looks when something is in the way
local RETRIES = 3           -- looks before giving up
local FADE_IN, HOLD, FADE_OUT = 0.6, 8, 1.2
local RISE = 6              -- pixels the card settles upward (0 with Reduced motion)
local WIDTH, HEIGHT = 420, 56

local pending = 0           -- bumped to drop a waiting timer; a timer only runs if it is still current
local card
local active = {}           -- [event] = handler, while registered

---------------------------------------------------------------------------
-- What to say. Pure, so it can be checked on its own.
---------------------------------------------------------------------------

-- The newest entry with a place and a readable date, or nil.
function B.Latest()
    local entries = C.Entries()
    for i = #entries, 1, -1 do
        local e = entries[i]
        if type(e.zone) == "string" and e.zone ~= "" and C.DayKey(e.t) then return e end
    end
end

local function Plural(n, word) return ("%d %s%s ago"):format(n, word, n == 1 and "" or "s") end

-- "just now", "12 minutes ago", "3 hours ago", "yesterday", or a date. nil when the time can't be trusted
-- (not a date, or in the future).
function B.Ago(t, now)
    local day, today = C.DayKey(t), C.DayKey(now)
    if not day or not today then return nil end
    local delta = now - t
    if delta < -60 then return nil end
    if delta < 60 then return "just now" end
    if delta < 3600 then return Plural(math.floor(delta / 60), "minute") end
    if delta < 86400 then return Plural(math.floor(delta / 3600), "hour") end
    if day == C.AddDays(today, -1) then return "yesterday" end
    return C.FormatDay(day)
end

local function Escape(text) return (text:gsub("|", "||")) end

local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

---------------------------------------------------------------------------
-- The card. Made the first time it is needed.
---------------------------------------------------------------------------
local function Hide()
    if not card then return end
    card.anim:Stop()
    card:Hide()
    for event, handler in pairs(active) do
        if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_LEAVING_WORLD" then
            R:Off(event, handler)
            active[event] = nil
        end
    end
end

function B.Dismiss() Hide() end

local function Open()
    if R.ChronicleWindow then R.ChronicleWindow:Show() end
    Hide()
end

local function Build()
    local S = R.ChronicleStyle
    if not S then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    card:SetSize(WIDTH, HEIGHT)
    card:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)   -- the zone card is at the top
    card:SetFrameStrata("MEDIUM")
    card:EnableMouse(true)
    card:Hide()
    card.K = K
    S.Frame(card, WIDTH, HEIGHT)

    -- A ribbon hanging from the top edge, its foot notched.
    local ribbon = card:CreateTexture(nil, "ARTWORK")
    ribbon:SetColorTexture(K.ember[1], K.ember[2], K.ember[3], 0.9)
    ribbon:SetSize(8, 34)
    ribbon:SetPoint("TOPLEFT", 14, 5)
    for i, w in ipairs({ 4, 2 }) do
        local notch = card:CreateTexture(nil, "OVERLAY")
        notch:SetColorTexture(K.bg[1], K.bg[2], K.bg[3], 1)
        notch:SetSize(w, 1)
        notch:SetPoint("BOTTOM", ribbon, "BOTTOM", 0, i - 1)
    end

    local frame = card:CreateTexture(nil, "ARTWORK")
    frame:SetColorTexture(K.bronzeLo[1], K.bronzeLo[2], K.bronzeLo[3], 1)
    frame:SetSize(30, 30)
    frame:SetPoint("LEFT", 34, 0)
    local icon = card:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(S.icons.zone)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(26, 26)
    icon:SetPoint("CENTER", frame, "CENTER", 0, 0)

    card.line = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.line:SetJustifyH("LEFT")
    card.line:SetWordWrap(false)
    card.line:SetSize(WIDTH - 72 - 36, 16)
    card.line:SetPoint("TOPLEFT", 74, -10)
    card.more = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.more:SetJustifyH("LEFT")
    card.more:SetWordWrap(false)
    card.more:SetSize(WIDTH - 72 - 120, 14)
    card.more:SetPoint("TOPLEFT", card.line, "BOTTOMLEFT", 0, -4)
    card.more:SetTextColor(K.stone[1], K.stone[2], K.stone[3])

    card.open = S.Link(card, "Open Chronicle", Open, K.gold, K.text)
    card.open:SetSize(100, 14)
    card.open:SetPoint("BOTTOMRIGHT", -10, 8)
    card.close = S.Close(card, B.Dismiss)
    card.close:SetPoint("TOPRIGHT", -8, -8)

    local anim = card:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)
    card.drop = anim:CreateAnimation("Translation")
    card.drop:SetDuration(0)
    card.drop:SetOrder(1)
    card.rise = anim:CreateAnimation("Translation")
    card.rise:SetSmoothing("OUT")
    card.rise:SetOrder(1)
    card.rise:SetDuration(FADE_IN)
    card.fadeIn = anim:CreateAnimation("Alpha")
    card.fadeIn:SetFromAlpha(0)
    card.fadeIn:SetToAlpha(1)
    card.fadeIn:SetSmoothing("OUT")
    card.fadeIn:SetDuration(FADE_IN)
    card.fadeIn:SetOrder(1)
    card.fadeOut = anim:CreateAnimation("Alpha")
    card.fadeOut:SetFromAlpha(1)
    card.fadeOut:SetToAlpha(0)
    card.fadeOut:SetSmoothing("IN")
    card.fadeOut:SetStartDelay(HOLD)
    card.fadeOut:SetDuration(FADE_OUT)
    card.fadeOut:SetOrder(2)
    anim:SetScript("OnFinished", Hide)
    card.anim = anim
    return true
end

local function Show(entry, ago)
    if not card and not Build() then return end
    Hide()   -- a card already up starts over, with its listeners set once
    local K = card.K
    card.line:SetText(("%sLast noted:|r %s%s|r %s·  %s|r"):format(
        Hex(K.stone), Hex(K.text), Escape(entry.zone), Hex(K.stone), ago))
    -- A second line for what was noted, unless it only repeats the place. Notes stay private on screen.
    local more = entry.kind ~= "note" and entry.title ~= "Arrived in " .. entry.zone and entry.title or nil
    card.more:SetText(more and Escape(more) or "")
    card.more:SetShown(more ~= nil)

    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    -- Make way for combat and a new scene; these are listened for only while the card is up.
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }) do
        if not active[event] then
            active[event] = Hide
            R:On(event, Hide)
        end
    end
end

---------------------------------------------------------------------------
-- When to show it.
---------------------------------------------------------------------------
local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

-- Anything that should have the player's attention instead.
local function InTheWay()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if R.Arrival and R.Arrival.IsShowing and R.Arrival.IsShowing() then return true end
    return Toasting()
end

local function Try(tries, mine)
    if pending ~= mine or not R:Enabled("welcomeBack") then return end
    if InTheWay() then
        if tries < RETRIES then C_Timer.After(RETRY, function() Try(tries + 1, mine) end) end
        return
    end
    local entry = B.Latest()
    local ago = entry and B.Ago(entry.t, time())
    if ago then Show(entry, ago) end
end

-- /tui welcome: shows the bookmark now, from the same data, so it can be looked at without logging in
-- again. Skips the login and in-the-way checks (the player asked) but still says nothing false.
-- Returns true, or false and a reason.
function B.Preview()
    local entry = B.Latest()
    if not entry then return false, "No Chronicle entry with a place and a date yet, so there is nothing to show." end
    local ago = B.Ago(entry.t, time())
    if not ago then return false, "The latest entry's time can't be read, so there is nothing to show." end
    Show(entry, ago)
    return true
end

-- Only a real login arms it. A reload or any other loading screen does not.
local function OnEnteringWorld(isLogin)
    if not isLogin then return end
    pending = pending + 1
    local mine = pending
    C_Timer.After(DELAY, function() Try(0, mine) end)
end

local function OnLeavingWorld()
    pending = pending + 1
    Hide()
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

-- Listens for the login only while the bookmark is on. Safe to call any time.
function B.Refresh()
    local on = R:Enabled("welcomeBack")
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    Want("PLAYER_LEAVING_WORLD", OnLeavingWorld, on)
    if not on then
        pending = pending + 1
        Hide()
    end
end

R:OnInit(B.Refresh)
