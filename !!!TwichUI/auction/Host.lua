-- AH-1a only: a command-activated, 30-second anchor lease. No replacement UI,
-- requests, native Show/Hide, panel attributes or persistent enable setting.
-- docs/workshop/auction-house/lifecycle-proof.md records the client gates.
local R = TwichUI
local H = {}
R.AuctionHost = H
local Perf = R.Perf
local lease, ticker, control
local controlReady = false
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

local function Points(f)
    local p = {}
    for i = 1, f:GetNumPoints() do p[i] = { f:GetPoint(i) } end
    return p
end
local function SamePoints(f, points)
    if f:GetNumPoints() ~= #points then return false end
    for i, p in ipairs(points) do
        local now = { f:GetPoint(i) }
        for j = 1, 5 do if now[j] ~= p[j] then return false end end
    end
    return true
end
local function StopTimer()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- Keep the lease after a failed restore, including a partially applied anchor
-- list. Each SetPoint is attempted independently; retry never loses the snapshot.
local function Restore(why)
    reason = why
    StopTimer()
    if not lease then return true end
    if Combat() then reason = "restore-after-combat"; return false, reason end
    local l = lease
    local ok, err = pcall(function()
        -- A foreign anchor change ends our ownership. Do not overwrite it.
        if l.recoveryPoints then
            if not SamePoints(l.frame, l.recoveryPoints) then return end
        elseif not l.partial and not SamePoints(l.frame, l.parked) then return end
        l.partial = true
        l.frame:ClearAllPoints()
        local first
        for _, point in ipairs(l.points) do
            local good, fault = pcall(l.frame.SetPoint, l.frame, unpack(point, 1, 5))
            if not good and not first then first = fault end
        end
        if first then error(first, 0) end
        if not SamePoints(l.frame, l.points) then error("AH-1a: native anchors did not restore", 0) end
    end)
    if not ok then
        local read, points = pcall(Points, l.frame)
        if read then l.recoveryPoints = points end
        reason = "restore-failed"
        R.Fault("auction proof restore", err)
        return false, reason
    end
    lease = nil
    if control then control:Hide() end
    return true
end

function H.Restore(why)
    return Perf.Call("auction.proof", Restore, why or "disabled")
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
local function Busy(f)
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
local function Watch()
    local l = lease
    if not l then return end
    if Combat() then H.Restore("combat"); return end
    if not Available() then H.Restore("interaction-ended"); return end
    if AuctionHouseFrame ~= l.frame or not l.frame:IsVisible() then H.Restore("native-hidden"); return end
    if not control:IsVisible() or Conflict() or Busy(l.frame) or Focused(l.frame)
        or l.frame:GetParent() ~= l.parent or l.frame:GetScale() ~= l.scale
        or l.frame:IsClampedToScreen() or not SamePoints(l.frame, l.parked) or not Offscreen(l.frame) then
        H.Restore("external-change"); return
    end
    if GetTime() >= l.untilTime then H.Restore("timeout") end
end
local function Tick()
    if not lease then return end
    local ok, err = pcall(Perf.Call, "auction.proofWatch", Watch)
    if not ok then H.Restore("watch-error"); R.Fault("auction proof watch", err) end
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
    control:SetScript("OnClick", function() H.Command("off") end)
    controlReady = true -- an interrupted setup must finish before any native lease
end

local function Activate()
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
    BuildControl() -- establish recovery before touching native anchors
    control:Show()
    if not control:IsVisible() then control:Hide(); return false, "recovery-unavailable" end
    if not hooked[f] then
        f:HookScript("OnHide", function(frame)
            if lease and lease.frame == frame then H.Restore("native-hidden") end
        end)
        hooked[f] = true
    end
    lease = { frame = f, points = points, scale = f:GetScale(), parent = f:GetParent(), partial = true,
        parked = { { "TOPLEFT", UIParent, "TOPRIGHT", OFFSET, 0 } }, untilTime = GetTime() + SECONDS }
    f:ClearAllPoints()
    f:SetPoint(unpack(lease.parked[1]))
    lease.partial = false
    if not f:IsVisible() or not Available() or not SamePoints(f, lease.parked) or not Offscreen(f) then
        H.Restore("parking-refused")
        return false, reason
    end
    ticker = C_Timer.NewTicker(0.25, Tick)
    reason = "parked"
    return true
end

function H.Activate()
    local ok, good, why = pcall(Perf.Call, "auction.proof", Activate)
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
    return { mode = not lease and "blizzard" or (reason == "parked" and "parked" or "restore-pending"),
        reason = reason, leased = lease ~= nil, watching = ticker ~= nil, control = control ~= nil }
end
function H.Control() return control end -- diagnostic/test entry point; never builds
function H.Command(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "on" then
        local ok, why = H.Activate()
        R.Print(ok and "AH-1a proof active for at most 30 seconds. Restore button or /tui ahproof off."
            or ("AH-1a proof refused: " .. tostring(why) .. ". Use idle Blizzard Browse outside combat."))
    elseif arg == "off" or arg == "restore" then
        local ok, why = H.Restore("disabled")
        R.Print(ok and "AH-1a proof off; owned anchors restored (external anchors preserved)."
            or ("AH-1a restoration pending: " .. tostring(why) .. ". Leave combat, retry /tui ahproof off; Escape or leave the auctioneer, then /reload if needed."))
    elseif arg == "status" then
        local s = H.Snapshot()
        R.Print("AH-1a: " .. s.mode .. ", " .. s.reason .. ". Real-client acceptance pending.")
    else
        R.Print("AH-1a diagnostic only: /tui ahproof on | off | status. Default off; each activation lasts at most 30 seconds outside combat. No replacement pages.")
    end
end

local function Ended() if lease then H.Restore("interaction-ended") end end
R:On("AUCTION_HOUSE_CLOSED", Ended)
R:On("AUCTION_HOUSE_DISABLED", Ended)
R:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t)
    if Enum and Enum.PlayerInteractionType and t == Enum.PlayerInteractionType.Auctioneer then Ended() end
end)
R:On("PLAYER_REGEN_DISABLED", function() if lease then H.Restore("combat") end end)
R:On("PLAYER_REGEN_ENABLED", function() if lease then H.Restore("combat-ended") end end)
R:On("PLAYER_LEAVING_WORLD", Ended)
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ADDON_LOADED" }) do
    R:On(event, function() if lease then H.Restore("environment-change") end end)
end
Perf.Gauge("auction.proofLease", { label = "AH-1a presentation lease", unit = "count", kind = "state",
    read = function() return lease and 1 or 0 end })
Perf.Gauge("auction.proofTimer", { label = "AH-1a watchdog", unit = "count", kind = "state",
    read = function() return ticker and 1 or 0 end })
