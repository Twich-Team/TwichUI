-- TwichUI: Navigation, the flight a journey has you take
-- Two things, both only while navigation is on and a journey's next step is a flight (nav/Nav.lua: NV.FlightNow):
--   * Highlight (ui.navigation.highlightFlight, on by default): when the flight master's map is open, a soft glow round the
--     flight point the journey lands at, on whichever of the game's two flight windows is showing (the flight map's pins, or
--     the older taxi frame's buttons). A texture on a child frame of the point; nothing of Blizzard's is changed or replaced,
--     and nothing is clicked. It goes when the window closes, the journey changes or the point isn't offered.
--   * Take it for me (ui.navigation.autoFlight, OFF by default, and only once the player has confirmed it in settings:
--     ui.flightAck, account-wide like the restocking confirmation): when the map opens at the flight master the journey
--     wanted (within AUTO_REACH yards of where that flight starts), the one flight is taken, once. It never opens a map,
--     talks to a flight master, picks anything the journey doesn't name, or flies in combat, mounted-on-taxi or from anywhere
--     else; a point the map doesn't offer as reachable is left alone. Taking a flight is the game's own TakeTaxiNode with the
--     slot the game gave for that point.
--     NOT KNOWN: whether this client lets an addon call TakeTaxiNode at all (the game's own windows call it from a click, and
--     the function isn't in the documented API). The call is made once per opening, guarded; if the client reports the
--     action blocked or forbidden for TwichUI, automatic flying turns itself off for the session and the settings say why.
-- No chat, no sound, no saved record but the confirmation. Counts (never places) are in the navigation diagnostics.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local FL = {}
R.NavFlight = FL

local TICK = 0.5             -- seconds between looks at the open window (it is rebuilt when its map changes)
local AUTO_DELAY = 0.4       -- seconds after the map opens before the flight is taken (the window fills in first)
local AUTO_REACH = 200       -- yards: how near the flight's own flight master you must be
local AUTO_RETRY = 30        -- seconds before the same flight may be tried again

local stats = { opens = 0, glowed = 0, notOffered = 0, tries = 0, taken = 0, skipped = 0, blocked = 0 }
local last = "nothing yet"
local open = false
local blocked = false        -- the client refused TakeTaxiNode for TwichUI: automatic flying stays off until a reload
local glow, ticker
local token = 0
local triedKey, triedAt

---------------------------------------------------------------------------
-- The choices
---------------------------------------------------------------------------
-- Whether the player has confirmed, on this account, that TwichUI may take a flight without asking.
function FL.Acknowledged()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and ui.flightAck == true
end

function FL.Acknowledge()
    if type(TwichUIDB) ~= "table" then return false end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.flightAck = true
    NP.Notify("autoFlight")
    return true
end

local function HighlightOn() return NV.Enabled() and NP.Get("highlightFlight") == true end
-- Automatic flying: chosen, confirmed on this account, and not refused by the client.
local function AutoOn() return NV.Enabled() and NP.Get("autoFlight") == true and FL.Acknowledged() and not blocked end
function FL.AutoOn() return AutoOn() end
-- chosen (by you elsewhere, a profile, a shared setup) but not confirmed here: it does nothing
function FL.AutoWaiting() return NP.Get("autoFlight") == true and not FL.Acknowledged() end
function FL.Blocked() return blocked end

---------------------------------------------------------------------------
-- Finding the point in the window that is showing
---------------------------------------------------------------------------
local function PinFor(node)
    local fm = _G.FlightMapFrame
    if not (fm and fm.IsShown and fm:IsShown() and fm.EnumeratePinsByTemplate) then return nil end
    local ok, found = pcall(function()
        for pin in fm:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            local d = pin.taxiNodeData
            if type(d) == "table" and d.nodeID == node and pin:IsShown() then return pin end
        end
    end)
    return ok and found or nil
end

local function ButtonFor(slot)
    local tf = _G.TaxiFrame
    if not (tf and tf.IsShown and tf:IsShown()) then return nil end
    local b = _G["TaxiButton" .. slot]
    if b and b:IsShown() then return b end
end

local function FrameFor(node, slot) return PinFor(node) or ButtonFor(slot) end

---------------------------------------------------------------------------
-- The glow
---------------------------------------------------------------------------
local function MakeGlow()
    if glow then return glow end
    glow = CreateFrame("Frame", nil, UIParent)
    glow:Hide()
    glow:EnableMouse(false)
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
    t:SetBlendMode("ADD")
    glow.tex = t
    local g = glow:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.8)
    glow.pulse = g
    return glow
end

local function ClearGlow()
    if not glow then return end
    glow.pulse:Stop()
    glow:Hide()
    glow:SetParent(UIParent)   -- not left on a pooled pin that the game may reuse for another point
    glow:ClearAllPoints()
end

local function Show(frame)
    local g = MakeGlow()
    if g:GetParent() ~= frame then
        g:SetParent(frame)
        g:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
    end
    local w = math.max(frame:GetWidth() or 16, 16)
    g:ClearAllPoints()
    g:SetPoint("CENTER", frame, "CENTER", 0, 0)
    g:SetSize(w * 2.4, w * 2.4)
    local r, gr, b = NP.Rgb(NP.Get("accentColor"))
    g.tex:SetVertexColor(math.min(1, r + 0.2), math.min(1, gr + 0.2), math.min(1, b + 0.2), 1)
    g:Show()
    if NP.ReducedMotion() then
        g.pulse:Stop()
        g:SetAlpha(1)
    elseif not g.pulse:IsPlaying() then
        g.pulse:Play()
    end
end

local function Apply()
    if not (open and HighlightOn()) then ClearGlow() return end
    local want = NV.FlightNow()
    local TV = R.NavTravel
    local info = want and TV and TV.Offered(want.node)
    if not info or info.state ~= 1 then      -- 1: a point you can fly to from here
        if want then stats.notOffered = stats.notOffered + 1 end
        ClearGlow()
        return
    end
    local frame = FrameFor(want.node, info.slot)
    if not frame then ClearGlow() return end
    if not (glow and glow:IsShown() and glow:GetParent() == frame) then stats.glowed = stats.glowed + 1 end
    Show(frame)
end

---------------------------------------------------------------------------
-- Taking it
---------------------------------------------------------------------------
local function TryAuto(mine)
    if mine ~= token or not open or not AutoOn() then return end
    local function Skip(why) stats.skipped = stats.skipped + 1 last = "not taken: " .. why end
    if InCombatLockdown and InCombatLockdown() then return Skip("in combat") end
    if UnitOnTaxi and UnitOnTaxi("player") then return Skip("already on a flight") end
    local want = NV.FlightNow()
    if not (want and want.current) then return Skip("the journey's step now isn't a flight") end
    local ok, cont, x, y = NV.PositionNow()
    if not ok or cont ~= want.cont or math.sqrt((x - want.x) ^ 2 + (y - want.y) ^ 2) > AUTO_REACH then
        return Skip("not at the flight master the journey meant")
    end
    local TV = R.NavTravel
    local info = TV and TV.Offered(want.node)
    if not info or info.state ~= 1 then return Skip("that point isn't offered from here") end
    local key = want.index .. ":" .. want.node
    local now = GetTime()
    if key == triedKey and triedAt and now - triedAt < AUTO_RETRY then return Skip("already tried a moment ago") end
    triedKey, triedAt = key, now
    stats.tries = stats.tries + 1
    local called, err = pcall(TakeTaxiNode, info.slot)
    if called then
        stats.taken = stats.taken + 1
        last = "taken (asked the game for the flight)"
    else
        stats.blocked = stats.blocked + 1
        last = "the call failed: " .. tostring(err):sub(1, 60)
    end
end

-- The client says an addon action was refused (a popup of its own appears): stop trying, and say why in the settings.
local function OnRefused(addon, func)
    if type(func) ~= "string" or not func:find("TakeTaxiNode", 1, true) then return end
    if type(addon) == "string" and not addon:find("TwichUI", 1, true) then return end
    blocked = true
    stats.blocked = stats.blocked + 1
    last = "the client refused TakeTaxiNode for TwichUI"
    NP.Notify("autoFlight")
end

---------------------------------------------------------------------------
-- The window opening and closing
---------------------------------------------------------------------------
local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

local function OnClosed()
    open = false
    token = token + 1
    StopTicker()
    ClearGlow()
end

local function OnOpened()
    stats.opens = stats.opens + 1
    open = true
    token = token + 1
    local mine = token
    StopTicker()
    ticker = C_Timer.NewTicker(TICK, Apply)
    C_Timer.After(0.1, Apply)
    if AutoOn() then C_Timer.After(AUTO_DELAY, function() TryAuto(mine) end) end
end

local registered, watchingRefusal = false, false
local function Sync()
    -- Turning automatic flight off abandons this opening even if highlighting
    -- stays on, or the preference is turned back on before its delay expires.
    if open and not AutoOn() then token = token + 1 end
    local want = NV.Enabled() and (NP.Get("highlightFlight") == true or NP.Get("autoFlight") == true)
    if want and not registered then
        registered = true
        R:On("TAXIMAP_OPENED", OnOpened)
        R:On("TAXIMAP_CLOSED", OnClosed)
    elseif not want and registered then
        registered = false
        R:Off("TAXIMAP_OPENED", OnOpened)
        R:Off("TAXIMAP_CLOSED", OnClosed)
        OnClosed()
    end
    local refuse = AutoOn()
    if refuse and not watchingRefusal then
        watchingRefusal = true
        R:On("ADDON_ACTION_FORBIDDEN", OnRefused)
        R:On("ADDON_ACTION_BLOCKED", OnRefused)
    elseif not refuse and watchingRefusal then
        watchingRefusal = false
        R:Off("ADDON_ACTION_FORBIDDEN", OnRefused)
        R:Off("ADDON_ACTION_BLOCKED", OnRefused)
    end
    if open then Apply() end
end

NV.Subscribe(function(event) if event == "prefs" then Sync() end end)
-- Account acknowledgement survives profiles; a pending automatic action does
-- not. Require a fresh flight-map opening after profile replacement/duplication.
R.Profiles.OnApply("views", "navigation-flight", OnClosed)
R.Profiles.OnChange(function(kind) if kind == "duplicate" then OnClosed() end end)
R:OnInit(Sync)

-- Read only, for /tui diagnostics: counts, never a place or a name.
function FL.Diagnostics()
    return { listening = registered, open = open, glowShown = glow ~= nil and glow:IsShown() or false, opens = stats.opens,
        glowed = stats.glowed, notOffered = stats.notOffered, tries = stats.tries, taken = stats.taken, skipped = stats.skipped,
        blocked = stats.blocked, refused = blocked, auto = AutoOn(), last = last }
end
