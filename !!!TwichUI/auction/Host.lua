-- One native presentation owner: AH-1a proof and AH-7A supervised integration.
-- No persisted opt-in, transactions, queries or panel-manager overrides.
-- docs/workshop/auction-house/lifecycle-proof.md records the client gates.
local R = TwichUI
local H = {}
R.AuctionHost = H
local Perf = R.Perf
local lease, ticker, control
local controlReady = false
local enabled, confirmed, visiting = false, false, false
local visit, request, pending = 0, 0, nil
local state = "blizzard"
local stateCodes = { blizzard = 0, preparing = 1, twichui = 2, restoring = 3, recovery = 4 }
local openedAt
local stats = { activations = 0, failed = 0, restoreFailed = 0, switches = 0 }
local UpdateControl, Failed
local failedVisit
local opening = {}
local function UI() return R.Workshop and R.Workshop.AuctionUI end
local function CancelPending()
    request = request + 1
    if pending then pending:Cancel(); pending = nil end
end
local function HideUI()
    local a = UI()
    if a and a.Context() == "auctioneer" then a.Hide() end
end
local reason = "disabled"
local hooked = setmetatable({}, { __mode = "k" })
local OWNERS = { "TradeSkillMaster", "Auctionator", "Auctioneer", "AuctionLite", "aux-addon" }
local OFFSET, SECONDS = 4096, 30

local function Combat() return InCombatLockdown() end
local function Available()
    local t = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer
    local p = C_PlayerInteractionManager
    return t and p and p.IsInteractingWithNpcOfType and p.IsValidNPCInteraction
        and p.IsInteractingWithNpcOfType(t) == true and p.IsValidNPCInteraction(t) == true or false
end

-- Frame coordinates are in each frame's effective-scale units, not UIParent's.
-- IsVisible includes ancestors but says nothing about alpha or viewport overlap.
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function Presentation(f, full)
    local s = { usable = false, why = "missing-frame" }
    if not f or not UIParent then return s end
    s.shown, s.visible = f:IsShown(), f:IsVisible()
    s.scale, s.strata = f:GetEffectiveScale(), f:GetFrameStrata()
    local ancestor, alpha, depth, ancestorsShown = f, 1, 0, true
    while ancestor and depth < 32 do
        if not ancestor:IsShown() then ancestorsShown = false end
        alpha = alpha * ancestor:GetAlpha()
        ancestor, depth = ancestor:GetParent(), depth + 1
    end
    s.alpha, s.ancestors = alpha, depth
    local scale, viewportScale = s.scale, UIParent:GetEffectiveScale()
    if not Finite(scale) or scale <= 0 or not Finite(viewportScale) or viewportScale <= 0 then
        s.why = "invalid-scale"; return s
    end
    local function Bounds(frame, k)
        local l, b, r, t = frame:GetLeft(), frame:GetBottom(), frame:GetRight(), frame:GetTop()
        if not (Finite(l) and Finite(b) and Finite(r) and Finite(t)) then return end
        return { left = l*k, bottom = b*k, right = r*k, top = t*k }
    end
    s.bounds, s.viewport = Bounds(f, scale), Bounds(UIParent, viewportScale)
    local b, v = s.bounds, s.viewport
    if not b or not v or b.right <= b.left or b.top <= b.bottom or v.right <= v.left or v.top <= v.bottom then
        s.why = "invalid-geometry"; return s
    end
    if ancestor or not ancestorsShown or not s.shown or not s.visible or not Finite(alpha) or alpha <= 0 then
        s.why = "invisible-frame"; return s
    end
    if full then
        s.usable = b.left >= v.left-1 and b.bottom >= v.bottom-1 and b.right <= v.right+1 and b.top <= v.top+1
    else
        s.usable = math.min(b.right,v.right)-math.max(b.left,v.left) >= 48
            and math.min(b.top,v.top)-math.max(b.bottom,v.bottom) >= 48
    end
    s.why = s.usable and "visible" or "offscreen"
    return s
end
function H.Presentation(f, full)
    local ok, s = pcall(Presentation, f, full)
    return ok and s or { usable = false, why = "geometry-error" }
end
local function NativeStatus()
    local s = H.Presentation(AuctionHouseFrame)
    opening.native = s
    return s.usable
end

local function Points(f)
    local p = {}
    for i = 1, f:GetNumPoints() do p[i] = { f:GetPoint(i) } end
    return p
end
-- SetPoint/GetPoint can round coordinates through the client's UI scale.
-- Allow that only when validating a write; ownership checks use the exact
-- returned snapshot so a later foreign anchor change still relinquishes it.
local POINT_EPSILON = 0.01
local function ComparePoints(actual, expected, tolerance)
    if #actual ~= #expected then return false, "anchor-count" end
    for i, point in ipairs(expected) do
        local now = actual[i]
        for j = 1, 3 do
            if now[j] ~= point[j] then return false, "anchor-field-" .. j end
        end
        for j = 4, 5 do
            if not Finite(now[j]) or not Finite(point[j]) or math.abs(now[j] - point[j]) > (tolerance or 0) then
                return false, "offset-" .. (j == 4 and "x" or "y")
            end
        end
    end
    return true
end
local function SamePoints(f, points, tolerance)
    return ComparePoints(Points(f), points, tolerance)
end
local function DescribePoints(points)
    local text = {}
    for i = 1, math.min(#points, 4) do
        local p = points[i]
        local relative = p[2] == UIParent and "UIParent" or p[2] == nil and "nil" or "other-frame"
        local x = Finite(p[4]) and ("%.9f"):format(p[4]) or "invalid"
        local y = Finite(p[5]) and ("%.9f"):format(p[5]) or "invalid"
        text[i] = tostring(p[1]) .. "/" .. relative .. "/" .. tostring(p[3]) .. " x=" .. x .. " y=" .. y
    end
    return table.concat(text, "; ")
end
local function StopTimer()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function HideSafely()
    local ok, err = pcall(HideUI)
    if not ok then R.Fault("auction replacement cleanup", err) end
end
local function KeepVisibleOrHide()
    local a = UI()
    local ok, s = pcall(function() return a and a.Presentation and a.Presentation() end)
    -- Keep an already working interface until native recovery is possible.
    -- Host's recovery state blocks reads/actions; do not create our own blank.
    if not enabled or not visiting or not ok or not s or not s.usable then HideSafely() end
end

-- Keep the lease after a failed restore, including a partially applied anchor
-- list. Each SetPoint is attempted independently; retry never loses the snapshot.
local function Restore(why)
    reason = why
    opening.restoreReason = why
    StopTimer()
    CancelPending()
    state = "restoring"
    if not lease then
        HideSafely()
        local usable = NativeStatus()
        local ended = not visiting or (not usable and not Available())
        state = (usable or ended) and "blizzard" or "recovery"
        opening.restoration = usable and "visible" or ended and "session-ended" or "native-unavailable"
        if UpdateControl then UpdateControl() end
        return usable or ended, opening.restoration
    end
    if Combat() then
        reason = "restore-after-combat"; state = "recovery"; opening.restoration = reason
        KeepVisibleOrHide()
        if UpdateControl then UpdateControl() end
        return false, reason
    end
    local l = lease
    local ok, err = pcall(function()
        -- A foreign anchor change ends our ownership. Do not overwrite it.
        if l.recoveryPoints then
            if not SamePoints(l.frame, l.recoveryPoints) then l.foreign = true; return end
        elseif not l.partial and not SamePoints(l.frame, l.parked) then l.foreign = true; return end
        -- Protection may have changed since parking. Never bypass a new owner.
        if l.frame:IsProtected() then error("native frame became protected", 0) end
        l.foreign = false
        l.partial = true
        l.frame:ClearAllPoints()
        local first
        for _, point in ipairs(l.points) do
            local good, fault = pcall(l.frame.SetPoint, l.frame, unpack(point, 1, 5))
            if not good and not first then first = fault end
        end
        if first then error(first, 0) end
        if not SamePoints(l.frame, l.points, POINT_EPSILON) then error("AH-1a: native anchors did not restore", 0) end
        l.recoveryPoints = Points(l.frame)
    end)
    local usable = NativeStatus()
    local ended = not usable and not Available()
    if ok and not usable and not ended then
        ok, err = false, l.foreign and "foreign native anchors remain unavailable" or "native presentation remains unavailable"
    end
    if not ok then
        local read, points = pcall(Points, l.frame)
        if read and not l.foreign then l.recoveryPoints = points end
        reason = l.foreign and "restore-blocked-owner" or "restore-failed"
        opening.restoration = reason
        state = "recovery"
        stats.restoreFailed = stats.restoreFailed + 1
        KeepVisibleOrHide()
        if UpdateControl then UpdateControl() end
        if l.foreign and opening.parkingMismatch then
            err = tostring(err) .. " (" .. opening.parkingMismatch .. "; requested " .. opening.parkExpected
                .. "; returned " .. opening.parkActual .. ")"
        end
        R.Fault("auction proof restore", err)
        return false, reason
    end
    opening.restoration = usable and (l.foreign and "foreign-visible" or "visible") or "session-ended"
    lease = nil
    state = "blizzard"
    HideSafely() -- native is usable (or the genuine session ended) before hiding
    if control then control:Hide() end
    if UpdateControl then UpdateControl() end
    return true
end

function H.Restore(why)
    local start = debugprofilestop and debugprofilestop()
    local ok, good, whyNot = pcall(Perf.Call, "auction.proof", Restore, why or "disabled")
    if start then stats.restoreMS = math.max(0, debugprofilestop() - start) end
    if not ok then
        state, reason = "recovery", "restore-failed"
        stats.restoreFailed = stats.restoreFailed + 1
        StopTimer()
        CancelPending()
        opening.restoration = "restore-failed"
        if UpdateControl then pcall(UpdateControl) end
        R.Fault("auction proof restore", good)
        return false, reason
    end
    return good, whyNot
end

-- Search-box focus is not the only possible focus: check all descendants, with
-- a hard bound. Unknown/oversize hierarchies fail open instead of hiding input.
local function Focused(f)
    local queue, i = { f }, 1
    while i <= #queue do
        local child = queue[i]
        if child.HasFocus and child:HasFocus() then return true end
        for _, v in ipairs({ child:GetChildren() }) do
            if #queue >= 1024 then return true end
            queue[#queue + 1] = v
        end
        i = i + 1
    end
    return false
end

local function Conflict()
    for _, name in ipairs(OWNERS) do
        if C_AddOns.IsAddOnLoaded(name) then return true end
    end
    return false
end
local function Busy(f, allowOwnedWarning)
    -- Native confirmations/progress can live outside the root's geometry.
    -- Observe them, never dismiss a player's transaction to take presentation.
    for _, key in ipairs({ "BUYOUT_AUCTION", "BID_AUCTION", "CANCEL_AUCTION", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR", "PURCHASE_AUCTION_UNIQUE" }) do
        if StaticPopup_Visible and StaticPopup_Visible(key) then
            local t=R.Workshop and R.Workshop.AuctionActions
            if not (allowOwnedWarning and key=="AUCTION_HOUSE_POST_WARNING" and t and t.OwnsNativeWarning()) then return true end
        end
    end
    if AuctionHouseMultisellProgressFrame and AuctionHouseMultisellProgressFrame:IsShown() then return true end
    local w = R.Workshop
    return (R.AuctionWindow and R.AuctionWindow.LifecycleBusy())
        or (R.AuctionScan and R.AuctionScan.Busy())
        or (w and w.Scan and w.Scan.Busy())
        or (f.DialogOverlay and f.DialogOverlay:IsShown())
        or (f.BuyDialog and f.BuyDialog:IsShown())
        or not AuctionHouseFrameDisplayMode
        or not f.GetDisplayMode or f:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy
end
local function Offscreen(f)
    local left, right = f:GetLeft(), UIParent:GetRight()
    return left and right and left * f:GetEffectiveScale() > right * UIParent:GetEffectiveScale()
end
local function WatchRestore(why)
    opening.watchdog = why
    if lease and lease.integrated then return Failed(why) end
    return H.Restore(why)
end
local function Watch()
    local l = lease
    if not l then return end
    if Combat() then WatchRestore("combat"); return end
    if not Available() then WatchRestore("interaction-ended"); return end
    if AuctionHouseFrame ~= l.frame or not l.frame:IsVisible() then WatchRestore("native-hidden"); return end
    if not control:IsVisible() or Conflict() or Busy(l.frame, l.integrated) or Focused(l.frame)
        or l.frame:GetParent() ~= l.parent or l.frame:GetScale() ~= l.scale
        or l.frame:IsClampedToScreen() or not SamePoints(l.frame, l.parked) or not Offscreen(l.frame) then
        WatchRestore("external-change"); return
    end
    if l.integrated then
        local a, launcher = UI(), R.WorkshopLauncher
        local presentation = a and a.Presentation and a.Presentation()
        opening.custom = presentation
        if not enabled or not launcher or not launcher.Enabled() or not a or not presentation or not presentation.usable
            or a.Context() ~= "auctioneer" then WatchRestore("replacement-unavailable") end
    elseif GetTime() >= l.untilTime then WatchRestore("timeout") end
end
local function Tick()
    if not lease then return end
    local ok, err = pcall(Perf.Call, "auction.proofWatch", Watch)
    if not ok then WatchRestore("watch-error"); R.Fault("auction proof watch", err) end
end

local function BuildControl()
    if controlReady then return end
    control = control or CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    control:Hide()
    control:SetSize(330, 28)
    control:ClearAllPoints()
    control:SetPoint("TOP", UIParent, "TOP", 0, -20)
    control:SetClampedToScreen(true)
    control:SetFrameStrata("DIALOG")
    control:SetText("AH-1a proof: Restore Blizzard (30s limit)")
    control:SetScript("OnClick", function()
        if R.PlayMenuSound then R:PlayMenuSound() end
        if lease or state == "recovery" then H.Restore("player-switch")
        elseif enabled and visiting then H.SwitchToTwichUI()
        else H.Command("off") end
    end)
    controlReady = true -- an interrupted setup must finish before any native lease
end

local function Prerequisites()
    if lease then return false, "restore-first" end
    if Combat() then return false, "combat" end
    if not Available() then return false, "no-auctioneer" end
    local f = AuctionHouseFrame
    if not f or not f:IsShown() or not f:IsVisible() then return false, "native-not-ready" end
    if f:GetParent() ~= UIParent or f:IsClampedToScreen() or f:IsProtected() then return false, "frame-owned-or-protected" end
    if Conflict() then return false, "other-auction-addon" end
    if Busy(f) then return false, "return-to-idle-browse" end
    if Focused(f) then return false, "clear-native-focus" end
    local points = Points(f)
    if #points == 0 then return false, "missing-anchors" end
    return true, f, points
end

local function Activate(integrated)
    local good, f, points = Prerequisites()
    if not good then return false, f end
    BuildControl() -- establish recovery before touching native anchors
    if integrated then
        control:ClearAllPoints(); control:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 24)
        control:SetText("Blizzard Auction House")
    else
        control:ClearAllPoints(); control:SetPoint("TOP", UIParent, "TOP", 0, -20)
        control:SetText("AH-1a proof: Restore Blizzard (30s limit)")
    end
    control:Show()
    if not control:IsVisible() then control:Hide(); return false, "recovery-unavailable" end
    if not hooked[f] then
        f:HookScript("OnHide", function(frame)
            if lease and lease.frame == frame then
                if lease.integrated then H.Ended() else H.Restore("native-hidden") end
            elseif enabled and visiting and AuctionHouseFrame == frame then
                H.Ended() -- also release the return action while Blizzard is active
            end
        end)
        hooked[f] = true
    end
    lease = { frame = f, points = points, scale = f:GetScale(), parent = f:GetParent(), partial = true,
        parked = { { "TOPLEFT", UIParent, "TOPRIGHT", OFFSET, 0 } }, untilTime = GetTime() + SECONDS,
        integrated = integrated, visit = visit }
    opening.parking = "attempted"
    opening.parkExpected = DescribePoints(lease.parked)
    f:ClearAllPoints()
    f:SetPoint(unpack(lease.parked[1]))
    local actual = Points(f)
    local matched, mismatch = ComparePoints(actual, lease.parked, POINT_EPSILON)
    opening.parkActual, opening.parkingMismatch = DescribePoints(actual), mismatch
    -- Snapshot only a verified version of our write, never arbitrary foreign
    -- anchors. Retaining the requested numbers mistakes rounding for ownership.
    if matched then lease.parked = actual end
    lease.partial = false
    local refusal = not f:IsVisible() and "native-hidden" or not Available() and "interaction-ended"
        or not matched and mismatch or not SamePoints(f, lease.parked) and "anchors-changed"
        or not Offscreen(f) and "still-onscreen"
    if refusal then
        opening.parking = "refused-" .. refusal
        H.Restore("parking-refused")
        return false, reason
    end
    opening.parking = "verified"
    local owned = lease
    ticker = C_Timer.NewTicker(0.25, function()
        if lease == owned and (not owned.integrated or (visiting and visit == owned.visit)) then Tick() end
    end)
    reason = "parked"
    return true
end

function H.Activate(integrated)
    -- Only the integrated controller may request an unbounded visit lease.
    if integrated and (not enabled or not confirmed or state ~= "preparing" or not visiting) then return false, "test-gate" end
    local ok, good, why = pcall(Perf.Call, "auction.proof", Activate, integrated)
    if not ok then
        H.Restore("activation-error")
        if not lease and control and not Combat() then control:Hide() end
        R.Fault("auction proof activate", good)
        return false, reason
    end
    if not good and not lease then reason = why end
    return good, why
end

function H.Snapshot()
    return { mode = state == "recovery" and "restore-pending" or not lease and "blizzard" or (reason == "parked" and "parked" or "restore-pending"),
        reason = reason, leased = lease ~= nil, watching = ticker ~= nil, control = control ~= nil,
        state = state, stateCode = stateCodes[state], enabled = enabled, nativeConfirmed = confirmed, visit = visit, visiting = visiting,
        opening = opening, failedVisit = failedVisit, nativeUsable = opening.native and opening.native.usable,
        pending = pending and 1 or 0, activations = stats.activations, failed = stats.failed,
        restoreFailed = stats.restoreFailed, switches = stats.switches, openMS = stats.openMS,
        loadMS = stats.loadMS, firstLoadMS = stats.firstLoadMS, activateMS = stats.activateMS, restoreMS = stats.restoreMS, switchMS = stats.switchMS }
end
function H.Control() return control end -- diagnostic/test entry point; never builds
function H.Command(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "confirm-native" then
        confirmed = true
        R.Print("Native proof acknowledged for this reload only. After completing Phase A, use /tui ahproof replacement on for supervised testing.")
    elseif arg == "replacement on" or arg == "replacement off" then
        local ok, why = H.SetTestEnabled(arg == "replacement on")
        if not ok and arg == "replacement off" then
            R.Print("Test mode off; Blizzard restoration pending: " .. tostring(why) .. ". Leave combat and retry /tui ahproof off.")
        else
            R.Print(ok and (enabled and "Auction House test mode enabled for this reload. Visit an auctioneer normally." or "Auction House test mode off.")
                or ("Auction House test mode refused: " .. tostring(why) .. ". Complete Phase A first; /tui ahproof confirm-native acknowledges your result."))
        end
    elseif arg == "twichui" then
        local ok, why = H.SwitchToTwichUI()
        R.Print(ok and "TwichUI Auction House opened." or ("Blizzard's Auction House is being used: " .. tostring(why)))
    elseif arg == "on" then
        local ok, why = H.Activate()
        R.Print(ok and "AH-1a proof active for at most 30 seconds. Restore button or /tui ahproof off."
            or ("AH-1a proof refused: " .. tostring(why) .. ". Use idle Blizzard Browse outside combat."))
    elseif arg == "off" or arg == "restore" then
        if arg == "off" then
            enabled = false
            if type(TwichUIDB) == "table" and type(TwichUIDB.ui) == "table" and not (R.Persist and R.Persist.IsHeld("TwichUIDB")) then TwichUIDB.ui.auctionDebug = false end
        end -- emergency stop also disarms future visits
        local ok, why = H.Restore("disabled")
        R.Print(ok and "AH-1a proof off; owned anchors restored (external anchors preserved)."
            or ("AH-1a restoration pending: " .. tostring(why) .. ". Leave combat, retry /tui ahproof off; Escape or leave the auctioneer, then /reload if needed."))
    elseif arg == "status" then
        local s = H.Snapshot()
        R.Print("Auction House: " .. s.state .. ", " .. s.reason .. "; test mode " .. (enabled and "on" or "off") .. ". Native acceptance must be recorded separately.")
    else
        R.Print("AH-1a diagnostic only: /tui ahproof on | off | status. Default off; each activation lasts at most 30 seconds outside combat. Integrated testing after Phase A: confirm-native | replacement on | replacement off | twichui. Opt-ins reset on reload.")
    end
end

-- Return action exists only for an explicitly enabled, genuine current visit.
-- It is independent of the native root so it remains reachable during recovery.
UpdateControl = function()
    if not control or not controlReady then return end
    if lease or state == "recovery" then
        control:SetText("Restore Blizzard Auction House · Retry")
        control:Show()
        return
    end
    if enabled and visiting and not Combat() and NativeStatus() then
        control:ClearAllPoints(); control:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 24)
        local failed = reason == "other-auction-addon" or reason:find("failed", 1, true) or reason == "activation-error"
        control:SetText(failed and "TwichUI unavailable · Retry" or "TwichUI Auction House")
        if R.Interact then
            R.Interact.Tip(control, "TwichUI Auction House", reason == "other-auction-addon"
                and "Another Auction House addon is controlling this window. Blizzard's window is available."
                or failed and "TwichUI couldn't open its Auction House. Blizzard's window is available. Click to retry."
                or "Switch interfaces during this auctioneer visit. Transactions remain unavailable in TwichUI.")
        end
        control:Show()
    else control:Hide() end
end
function H.DebugEnabled()
    local ui = type(TwichUIDB) == "table" and TwichUIDB.ui
    return not (R.Persist and R.Persist.IsHeld("TwichUIDB"))
        and type(ui) == "table" and ui.auctionDebug == true
        and R.WorkshopLauncher and R.WorkshopLauncher.Enabled() or false
end
function H.SetDebug(on)
    if type(on) ~= "boolean" then return false, "Invalid option." end
    if on and Combat() then return false, "Blizzard's Auction House is being used during combat." end
    if on and not (R.WorkshopLauncher and R.WorkshopLauncher.Enabled()) then return false, "Enable Workshop — Experimental first." end
    if type(TwichUIDB) ~= "table" or R.Persist and R.Persist.IsHeld("TwichUIDB") then
        if not on then enabled=false;return H.Restore("debug-disabled") end
        return false, "Saved settings are read-only."
    end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.auctionDebug = on
    -- Auction House presentation requires genuine native state, not a procedural proof.
    if on then
        confirmed, enabled = true, true
        if visiting and not lease then H.SwitchToTwichUI() end
        return true
    end
    enabled = false
    return H.Restore("debug-disabled")
end
function H.ApplyDebug()
    if H.DebugEnabled() then enabled, confirmed = true, true
    else
        enabled = false; H.Restore("debug-disabled")
    end
end
function H.DebugCommand(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "on" or arg == "off" then
        local ok, why = H.SetDebug(arg == "on")
        R.Print(ok and (arg == "on" and "TwichUI Auction House replacement on. Visit an auctioneer normally." or "Auction House replacement off; Blizzard restored.")
            or tostring(why or "Restoration is pending; leave combat and retry /tui ahdebug off."))
    elseif arg == "status" then
        R.Print("Auction House replacement " .. (H.DebugEnabled() and "on" or "off") .. "; interface " .. state .. "; " .. reason .. ".")
    else R.Print("/tui ahdebug on | off | status. Off restores Blizzard.") end
end
R:OnInit(H.ApplyDebug)
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views", "auction-debug", H.ApplyDebug) end

function H.IsCurrent(id) return enabled and visiting and visit == id and Available() end
function H.ToBlizzard() return H.Restore("player-switch") end

Failed = function(why)
    local first = failedVisit ~= visit
    failedVisit = visit
    stats.failed = stats.failed + 1
    pcall(BuildControl) -- recovery is independent even if opening failed before a lease
    local a = UI()
    if a and a.Presentation then
        local ok, s = pcall(a.Presentation)
        if ok then opening.custom = s end
    end
    opening.failure, opening.failureState = why or "replacement-failed", state
    -- Activate already attempted recovery on a refused native write. A second
    -- automatic Restore repeats the same fault without new state or ownership.
    local restored = false
    if state == "recovery" then CancelPending(); StopTimer()
    else restored = H.Restore(why or "replacement-failed") end
    if first then
        R.Print(NativeStatus() and "TwichUI Auction House couldn't open. Blizzard's Auction House is available."
            or "TwichUI Auction House couldn't open. Blizzard recovery is pending; use Restore Blizzard Auction House or /tui ahdebug off.")
    end
    return false, why or reason, restored
end
function H.ReplacementFailed(id, why)
    if visiting and visit == id and (state == "preparing" or state == "twichui") then return Failed(why) end
end
local function Switch()
    if not enabled or not confirmed then return false, "test-gate" end
    if not visiting or not Available() then return false, "no-auctioneer" end
    if state == "twichui" then return true end
    CancelPending()
    local id, token = visit, request
    opening = { visit = id, state = "preparing", load = "pending", build = "pending", parking = "untouched" }
    NativeStatus()
    local good, why = Prerequisites()
    if not good then return Failed(why) end
    state = "preparing"
    BuildControl()
    control:SetText("Blizzard Auction House")
    control:Show()
    if not control:IsVisible() then return Failed("recovery-unavailable") end
    -- Load through the existing consent/error/performance boundary. Defer the
    -- optional scan-button attachment exactly as for the standalone preview.
    local launcher = R.WorkshopLauncher
    if not launcher or not launcher.Load then return Failed("missing-workshop") end
    local loadAt = debugprofilestop and debugprofilestop()
    local ok, loaded, loadWhy = pcall(launcher.LoadAuctionUI)
    if loadAt then
        stats.loadMS = math.max(0, debugprofilestop() - loadAt)
        if not stats.firstLoadMS then stats.firstLoadMS = stats.loadMS end
    end
    if not H.IsCurrent(id) or token ~= request or state ~= "preparing" then return false, "visit-ended" end
    opening.load = ok and (loaded and "loaded" or tostring(loadWhy or "failed")) or "exception"
    if not ok then R.Fault("auction replacement load", loaded); return Failed("workshop-load-error") end
    if not loaded then return Failed(loadWhy or "workshop-load-failed") end
    local reads = R.Workshop and R.Workshop.AuctionReads
    if reads and reads.AttachVisit then reads.AttachVisit(id) end
    local actions = R.Workshop and R.Workshop.AuctionActions
    if actions then actions.Visit(id) end
    local a = UI()
    if not a or not a.Prepare then return Failed("missing-auction-ui") end
    -- A currently open preview must finish its own jobs before presentation changes.
    if a.IsShown() and a.Context() == "preview" then a.Hide() end
    local prepared, built = pcall(a.Prepare)
    if not prepared then R.Fault("auction replacement build", built) end
    if not H.IsCurrent(id) or token ~= request or state ~= "preparing" then return false, "visit-ended" end
    opening.build = prepared and built and "built" or "failed"
    if not prepared or not built then return Failed("window-build-failed") end
    -- Render while Blizzard is still usable. Show alone is not a render receipt.
    local shown, result = pcall(a.ShowIntegrated, id)
    opening.custom = a.Presentation and a.Presentation()
    if not shown then R.Fault("auction replacement show", result) end
    if not H.IsCurrent(id) or token ~= request or state ~= "preparing" then return false, "visit-ended" end
    if not shown or result ~= true or not opening.custom or not opening.custom.usable then return Failed("window-show-failed") end
    opening.presented = opening.custom
    local start = debugprofilestop and debugprofilestop()
    local parked, parkWhy = H.Activate(true) -- rechecks every guard after loading/building
    if start then stats.activateMS = math.max(0, debugprofilestop() - start) end
    if not parked then return Failed(parkWhy) end
    if not H.IsCurrent(id) or token ~= request or not lease then return false, "visit-ended" end
    opening.custom = a.Presentation()
    if not opening.custom.usable then return Failed("window-commit-failed") end
    state, reason = "twichui", "parked"
    opening.state = state
    stats.activations, stats.switches = stats.activations + 1, stats.switches + 1
    if openedAt then stats.openMS = math.max(0, (GetTime() - openedAt) * 1000); openedAt = nil end
    return true
end
function H.SwitchToTwichUI()
    local id = visit
    local start = debugprofilestop and debugprofilestop()
    local ok, good, why = pcall(Perf.Call, "auction.switch", Switch)
    if start then stats.switchMS = math.max(0, debugprofilestop() - start) end
    if not ok then
        R.Fault("auction replacement", good)
        if not visiting or visit ~= id then return false, "visit-ended" end
        return Failed("activation-error")
    end
    return good, why
end
function H.InterfaceHidden(id)
    if state ~= "twichui" or visit ~= id then return end
    -- Escape/close ends the visit using Blizzard's normal close path, after
    -- restoration. HideUIPanel is never used to perform presentation switching.
    local f = lease and lease.frame
    local readable, current = pcall(H.IsCurrent, id)
    local restored = H.Restore("player-close")
    if restored and readable and current and not Combat() and AuctionHouseFrame == f and f:IsVisible() then
        local ok, err = pcall(HideUIPanel, f)
        if not ok then R.Fault("auction close", err) end
    end
end
function H.SetTestEnabled(on)
    if on and not confirmed then return false, "native-proof-required" end
    if on and Combat() then return false, "combat" end
    enabled = on == true
    if not enabled then return H.Restore("test-disabled") end
    return true
end
local function Ended()
    visiting, openedAt = false, nil
    CancelPending()
    H.Restore("interaction-ended")
end
local Look
local function ScheduleLook(id, token, tries, delay)
    pending = C_Timer.NewTimer(delay, function()
        if not enabled or not visiting or visit ~= id or request ~= token then return end
        local ok, err = pcall(Look, id, token, tries)
        if not ok and visiting and visit == id and request == token then
            Failed("initialization-error")
            R.Fault("auction replacement initialize", err)
        end
    end)
end
Look = function(id, token, tries)
    if not enabled or not visiting or visit ~= id or request ~= token or failedVisit == id then return end
    pending = nil
    if Combat() then reason = "combat"; state = "blizzard"; return end
    if not Available() or not AuctionHouseFrame or not AuctionHouseFrame:IsVisible() then
        if tries < 20 then
            ScheduleLook(id, token, tries + 1, 0.1)
        else Failed("native-not-ready") end
        return
    end
    H.SwitchToTwichUI() -- one attempt; never retry load/build/guard failures automatically
end
local function Opened()
    if visiting then return end
    visiting = true; visit = visit + 1; failedVisit = nil
    if H.DebugEnabled() then enabled, confirmed = true, true end
    if not enabled then return end
    CancelPending()
    local id, token = visit, request
    openedAt = GetTime()
    state = "preparing"
    ScheduleLook(id, token, 0, 0)
end
H.Opened, H.Ended = Opened, Ended -- same event handlers for synthetic simulator boundaries
R:On("AUCTION_HOUSE_SHOW", Opened)
R:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(t)
    if Enum and Enum.PlayerInteractionType and t == Enum.PlayerInteractionType.Auctioneer then Opened() end
end)
R:On("AUCTION_HOUSE_CLOSED", Ended)
R:On("AUCTION_HOUSE_DISABLED", Ended)
R:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t)
    if Enum and Enum.PlayerInteractionType and t == Enum.PlayerInteractionType.Auctioneer then Ended() end
end)
R:On("PLAYER_REGEN_DISABLED", function() H.Restore("combat") end)
R:On("PLAYER_REGEN_ENABLED", function() if lease then H.Restore("combat-ended") end end)
R:On("PLAYER_LEAVING_WORLD", Ended)
R:On("PLAYER_LOGOUT", function() enabled = false; Ended() end)
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ADDON_LOADED" }) do
    R:On(event, function() if lease then H.Restore("environment-change") end end)
end
Perf.Gauge("auction.proofLease", { label = "AH-1a presentation lease", unit = "count", kind = "state",
    read = function() return lease and 1 or 0 end })
Perf.Gauge("auction.proofTimer", { label = "AH-1a watchdog", unit = "count", kind = "state",
    read = function() return ticker and 1 or 0 end })
