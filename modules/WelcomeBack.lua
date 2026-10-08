-- TwichUI: Welcome Back bookmark
-- Logging in to a character with Chronicle history shows one short title card in the
-- zone card's manner, with no frame: "Welcome Back" over its bronze rule, then
-- "Last noted: The Barrens · 2 hours ago" and an Open Chronicle link. It sits near the
-- top of the screen, can be moved in Edit Mode, and fades away by itself.
-- It only reads the newest Chronicle entry that has a place and a date; it adds no
-- entry and stores only the card's own screen position, if the player moves it in Edit Mode. "Last noted" is the Chronicle's own last record, not
-- where the character logged out. It shows only on a real login (never after a
-- reload or a loading screen), waits until the arrival card's quiet time is over,
-- stays away from combat, flight and other banners, and gives up rather than queue.
-- It is a bookmark, not an alert: modules/Notify.lua gives it the lowest real priority and has it
-- give way to any other TwichUI card that needs its place, so it never holds one up.
-- No sound, no chat, nothing sent.

local R = TwichUI
local N = R.Notify
local C = R.Chronicle
local B = {}
R.WelcomeBack = B

local DELAY = 7             -- seconds after login; the zone arrival card is quiet for its first 5
local TTL = 8               -- seconds it may wait for combat, flight, a banner or another card before giving up
local FADE_IN, HOLD, FADE_OUT = 0.8, 8, 1.4   -- fades are the zone card's
local RISE = 8              -- pixels the card settles upward, as the zone card does (0 with Reduced motion)
local WIDTH, HEIGHT = 520, 96
local TOP_OFFSET = -260     -- default place: upper centre, below the error text, raid warnings and the zone card
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"   -- Edit Mode's own highlight, when the client has it

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
-- Where it goes: the top edge's offset from the top centre of the screen, as moved in Edit
-- Mode (TwichUIDB.ui.welcomeBackPlace), or the default. The card grows downward from there.
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end

function B.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.welcomeBackPlace
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return 0, TOP_OFFSET
end

local function Place(frame)
    local x, y = B.Position()
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", x, y)
end

---------------------------------------------------------------------------
-- The card. Made the first time it is needed.
---------------------------------------------------------------------------
local function Stop()
    card.anim:Stop()
    card:Hide()
    for event, handler in pairs(active) do
        if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_LEAVING_WORLD" then
            R:Off(event, handler)
            active[event] = nil
        end
    end
end

-- Takes the card down and tells the coordinator its place is free.
local function Hide()
    if not card then return end
    Stop()
    N.Finished("welcome")
end

function B.Dismiss() Hide() end

local function Open()
    if card and card.preview then return end   -- a settings preview does nothing when clicked
    if R.ChronicleWindow then R.ChronicleWindow:Show() end
    Hide()
end

-- A line of text with the zone card's shadow, which keeps it readable without a backdrop.
local function Text(parent, path, size, fallback, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    R.Arrival.SetFont(fs, path, size, fallback)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetWidth(WIDTH)
    return fs
end

-- No frame or backdrop, like the zone card. Only the Open Chronicle link takes clicks, so the
-- world beneath the card stays clickable.
local function Build()
    local S, A = R.ChronicleStyle, R.Arrival
    if not (S and A and A.Rule and A.SetFont) then return false end
    local K = S.color
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, HEIGHT)
    Place(card)
    card:SetClampedToScreen(true)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    card.K = K

    card.title = Text(card, A.FONT_TITLE, 18, "SubZoneTextFont", K.text)
    card.title:SetPoint("TOP", 0, 0)
    card.title:SetText("Welcome Back")
    card.rule = A.Rule(card, K)
    card.rule:SetWidth(110)
    card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -6)
    card.line = Text(card, A.FONT_LINE, 15, "GameFontHighlight", K.text)
    card.line:SetPoint("TOP", card.rule, "BOTTOM", 0, -10)
    card.more = Text(card, A.FONT_LINE, 13, "GameFontHighlightSmall", K.stone)
    card.more:SetPoint("TOP", card.line, "BOTTOM", 0, -4)

    card.open = S.Link(card, "Open Chronicle", Open, K.stone, K.gold)
    card.open:SetSize(120, 16)
    A.SetFont(card.open.text, A.FONT_LINE, 13, "GameFontNormalSmall")
    card.open.text:SetJustifyH("CENTER")
    card.open:SetPoint("TOP", card.more, "BOTTOM", 0, -6)

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

-- Where the card is, for the coordinator: left, bottom, right, top in screen units.
function B.Bounds()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" then return nil end
    local x, y = B.Position()
    local top = height + y
    return width / 2 + x - WIDTH / 2, top - HEIGHT, width / 2 + x + WIDTH / 2, top
end

-- Draws the card; the coordinator calls this when its turn comes.
-- p: { zone, ago, more } as Present worked them out. preview: a settings preview, drawn above the
-- Settings panel, whose Open Chronicle link does nothing and which does not listen for combat or a new zone.
local function Show(p, preview)
    if not card and not Build() then return false end
    Stop()   -- a card already up starts over, with its listeners set once
    Place(card)
    local K = card.K
    card.preview = preview and true or false
    card.open:EnableMouse(not preview)
    card.line:SetText(("%sLast noted:|r %s%s|r %s·  %s|r"):format(
        Hex(K.stone), Hex(K.text), Escape(p.zone), Hex(K.stone), p.ago))
    local more = p.more
    card.more:SetText(more and Escape(more) or "")
    card.more:SetShown(more ~= nil)
    card.open:ClearAllPoints()
    card.open:SetPoint("TOP", more and card.more or card.line, "BOTTOM", 0, -6)

    local rise = R:Enabled("arrivalReducedMotion") and 0 or RISE
    card.drop:SetOffset(0, -rise)
    card.rise:SetOffset(0, rise)
    card:SetFrameStrata(preview and N.PREVIEW_STRATA or "LOW")
    card:SetAlpha(0)
    card:Show()
    card.anim:Play()
    -- Make way for combat and a new scene; these are listened for only while the card is up.
    -- (A preview makes way for combat through the coordinator, and a new zone isn't a reason for it to go.)
    if not preview then
        for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }) do
            if not active[event] then
                active[event] = Hide
                R:On(event, Hide)
            end
        end
    end
    return true
end

-- What the card says for a Chronicle entry and how long ago it was: the place and time, and a second
-- line for what was noted unless it only repeats the place. Notes stay private on screen.
local function Lines(entry, ago)
    local more = entry.kind ~= "note" and entry.title ~= "Arrived in " .. entry.zone and entry.title or nil
    return { zone = entry.zone, ago = ago, more = more }
end

-- Asks the coordinator to show the card. Only copies of what it says are kept, not the entry itself.
local function Present(entry, ago, preview)
    return N.Submit({
        kind = "welcome", id = preview and "preview-latest" or "login", ttl = preview and nil or TTL,
        priority = N.PRIORITY.low, preview = preview,
        valid = not preview and function() return R:Enabled("welcomeBack") end or nil,
        payload = Lines(entry, ago),
    })
end

---------------------------------------------------------------------------
-- When to show it.
---------------------------------------------------------------------------
local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

-- Anything that should have the player's attention instead. Another TwichUI card in the way is not this:
-- the coordinator makes the bookmark give way to one.
local function InTheWay()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    return Toasting()
end

local function Try(mine)
    if pending ~= mine or not R:Enabled("welcomeBack") then return end
    local entry = B.Latest()
    local ago = entry and B.Ago(entry.t, time())
    if ago then Present(entry, ago) end
end

-- /tui welcome: shows the bookmark now, from the same data, so it can be looked at without logging in
-- again. Skips the login and in-the-way checks (the player asked) but still says nothing false.
-- Shown as a preview: its link does nothing. Returns true, or false and a reason.
function B.Preview()
    local entry = B.Latest()
    if not entry then return false, "No Chronicle entry with a place and a date yet, so there is nothing to show." end
    local ago = B.Ago(entry.t, time())
    if not ago then return false, "The latest entry's time can't be read, so there is nothing to show." end
    N.DropPreviews("welcome")
    Present(entry, ago, true)
    return true
end

N.Register("welcome", {
    label = "Chronicle welcome back",
    show = function(p, ctx) return Show(p, ctx.preview) end,
    dismiss = Hide,
    bounds = function() return B.Bounds() end,
    hold = function() return FADE_IN + HOLD + FADE_OUT end,
    ready = function() return not InTheWay() end,
    yields = true,
    -- Made up: no Chronicle entry is read.
    sample = function() return { zone = "Sample Vale", ago = "2 hours ago", more = "A made-up entry for previews" } end,
})

-- Only a real login arms it. A reload or any other loading screen does not.
local function OnEnteringWorld(isLogin)
    if not isLogin then return end
    pending = pending + 1
    local mine = pending
    C_Timer.After(DELAY, function() Try(mine) end)
end

local function OnLeavingWorld()
    pending = pending + 1
    N.Cancel("welcome")
end

---------------------------------------------------------------------------
-- Moving it in Edit Mode. The game's Edit Mode has no place for addon frames, so while it is
-- open a TwichUI outline stands where the card appears, even when the card isn't showing: drag
-- it to move the card, right-click it to put it back. The place is kept at once, whatever Edit
-- Mode's own Save or Revert does with its layouts, and is the same for every character.
---------------------------------------------------------------------------
local mover
local editHooked = false

local function SavePosition(x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.welcomeBackPlace = x and { x = x, y = y } or nil
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
        local S = R.ChronicleStyle
        local c = S and S.color and S.color.bronze or { 0.55, 0.43, 0.22 }
        fill:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText("Chronicle Welcome Back")
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
        GameTooltip:SetText("TwichUI: Chronicle Welcome Back", 1, 1, 1)
        GameTooltip:AddLine("Where the Welcome Back card appears at login. Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

-- Shows the outline while Edit Mode is open and the bookmark is on.
local function ShowMover(shown)
    if shown and R:Enabled("welcomeBack") then
        if not mover then BuildMover() end
        Place(mover)
        mover:Show()
    elseif mover then
        mover:StopMovingOrSizing()
        mover:Hide()
    end
end

local function OnEditModeEnter() ShowMover(true) end
local function OnEditModeExit() ShowMover(false) end

-- Listens to Edit Mode opening and closing only while the bookmark is on. Registered at most once.
local function HookEditMode(wanted)
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end
    if wanted and not editHooked then
        editHooked = true
        EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, B)
        EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, B)
    elseif not wanted and editHooked then
        editHooked = false
        EventRegistry:UnregisterCallback("EditMode.Enter", B)
        EventRegistry:UnregisterCallback("EditMode.Exit", B)
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

-- Listens for the login only while the bookmark is on. Safe to call any time.
function B.Refresh()
    local on = R:Enabled("welcomeBack")
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    Want("PLAYER_LEAVING_WORLD", OnLeavingWorld, on)
    if not on then
        pending = pending + 1
        N.Cancel("welcome")   -- one waiting or showing; a settings preview is the player's own and stays
    end
    HookEditMode(on)
    ShowMover(on and EditModeActive())
end

R:OnInit(B.Refresh)
