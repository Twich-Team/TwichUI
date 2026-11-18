-- Real core command/event routing and Host over a synthetic native frame. No
-- server, combat protection, taint, actual input or reload persistence proof.
dofile(TESTS .. "harness.lua")
local count = 0
local function Same(a, b, label)
    count = count + 1
    assert(a == b, (label or "check") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local Setup = dofile(TESTS .. "auction_host_mock.lua")(Same)

do
    local t = Setup(); local c, H = t.c, t.H
    Same(t.frames, 0, "disabled builds no frames")
    for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "ADDON_LOADED" }) do c.FireEvent(e, "Blizzard_AuctionHouseUI") end
    Same(t.mutations, 0, "opening/login/load never opt in")
    Same(H.Control(), nil)
    c.SlashCmdList.TWICHUI("ahproof on")
    Same(H.Snapshot().mode, "parked", "real slash router")
    Same(t.f:IsShown(), true, "root stays shown")
    Same(t.f.shows, nil, "Host never calls Show")
    Same(H.Control():IsVisible(), true)
    H.Control():Click(); t.Restored()
    Same(H.Control():IsShown(), false)
    for i = 1, 100 do
        Same(H.Activate(), true)
        Same(H.Activate(), false, "no nested lease")
        Same(H.Restore(), true); t.Restored()
    end
    Same(#t.f.hooks.OnHide, 1, "one native hide hook")
    Same(t.frames, 1, "reuse recovery button")
    Same(t.loads, 0)
    Same(#t.faults, 0)
end

-- Capability and idle-state refusals leave the native anchors untouched.
for _, gate in ipairs({ "combat", "available", "valid", "hidden", "parent", "clamp", "protected", "focus", "owner", "posting", "searching", "workshopscan", "sell", "dialog", "missing", "api" }) do
    local t = Setup(); local c, f = t.c, t.f
    if gate == "combat" then t.combat = true
    elseif gate == "available" then t.available = false
    elseif gate == "valid" then t.valid = false
    elseif gate == "hidden" then f.shown = false
    elseif gate == "parent" then f.parent = t.Frame(c.UIParent)
    elseif gate == "clamp" then f.clamped = true
    elseif gate == "protected" then f.protected = true
    elseif gate == "focus" then t.Frame(f).focus = true
    elseif gate == "owner" then c.LOADED.TradeSkillMaster = true
    elseif gate == "posting" then t.posting = true
    elseif gate == "searching" then t.searching = true
    elseif gate == "workshopscan" then t.R.Workshop = { Scan = { Busy = function() return true end } }
    elseif gate == "sell" then f.mode = {}
    elseif gate == "dialog" then f.BuyDialog = t.Frame(f)
    elseif gate == "missing" then f.points = {}
    elseif gate == "api" then c.C_PlayerInteractionManager = nil end
    Same(t.H.Activate(), false, gate)
    Same(t.mutations, 0, "refusal never mutates: " .. gate)
    Same(t.H.Snapshot().leased, false)
end

for _, event in ipairs({ "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED", "PLAYER_LEAVING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ADDON_LOADED" }) do
    local t = Setup(); Same(t.H.Activate(), true)
    t.c.FireEvent(event); t.Restored()
    t.c.FireEvent(event); t.Restored() -- duplicate close/disabled cleanup
    t.Open(); t.Restored() -- reopening never reactivates
end
do
    local t = Setup(); Same(t.H.Activate(), true)
    t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 4); Same(t.H.Snapshot().leased, true)
    t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21); t.Restored()
    Same(t.H.Activate(), true); t.f:Hide(); t.Restored()
    Same(t.f:IsShown(), false, "never resurrect closed interaction")
    t.Open(); t.Restored()
end

-- External writers: restore our anchors when still owned, preserve their anchors.
for _, change in ipairs({ "anchors", "scale", "parent", "focus", "geometry", "control", "owner", "context", "replacement", "timeout" }) do
    local t = Setup(); Same(t.H.Activate(), true)
    if change == "anchors" then t.f.points = { { "CENTER", t.c.UIParent, "CENTER", 11, 22 } }
    elseif change == "scale" then t.f.scale = 0.6
    elseif change == "parent" then t.f.parent = t.Frame(t.c.UIParent)
    elseif change == "focus" then t.Frame(t.f).focus = true
    elseif change == "geometry" then t.f.badGeometry = true
    elseif change == "control" then t.H.Control():Hide()
    elseif change == "owner" then t.c.LOADED.Auctionator = true
    elseif change == "context" then t.valid = false
    elseif change == "replacement" then t.c.AuctionHouseFrame = t.Frame(t.c.UIParent)
    elseif change == "timeout" then t.now = 30 end
    t.Tick()
    Same(t.H.Snapshot().leased, false, change)
    Same(t.H.Snapshot().watching, false, "cancel watchdog")
    if change == "anchors" then Same(select(4, t.f:GetPoint(1)), 11, "preserve foreign anchors")
    else Same(select(4, t.f:GetPoint(1)), 27, "restore owned anchors") end
    if change == "scale" then Same(t.f.scale, 0.6, "preserve external scale") end
    if change == "parent" then Same(t.f.parent == t.c.UIParent, false, "preserve external parent") end
end

do
    local t = Setup(); Same(t.H.Activate(), true)
    local writes = t.mutations
    t.combat = true; t.c.FireEvent("PLAYER_REGEN_DISABLED")
    Same(t.H.Snapshot().mode, "restore-pending")
    Same(t.mutations, writes, "combat event makes no frame mutation")
    Same(t.H.Restore(), false); Same(t.H.Activate(), false)
    Same(t.mutations, writes)
    t.c.FireEvent("AUCTION_HOUSE_CLOSED"); Same(t.mutations, writes)
    t.combat = false; t.c.FireEvent("PLAYER_REGEN_ENABLED"); t.Restored()
    t.Open(); t.Restored()
end

-- Failure injection: partial activation, partial recovery and watchdog API errors.
do
    local t = Setup()
    local create = t.c.CreateFrame
    t.c.CreateFrame = function(...)
        local button = create(...)
        local setText = button.SetText
        button.SetText = function(self)
            self.SetText = setText
            error("injected recovery-control setup failure")
        end
        return button
    end
    Same(t.H.Activate(), false, "incomplete recovery control refuses takeover")
    t.Restored()
    Same(t.H.Control():IsShown(), false)
    Same(#t.faults, 1)
    Same(t.H.Activate(), true, "retry finishes recovery setup")
    Same(t.frames, 1, "retry reuses recovery frame")
    t.H.Control():Click(); t.Restored()
end
for _, method in ipairs({ "failClear", "failPoint", "badGeometry" }) do
    local t = Setup(); t.f[method] = true
    Same(t.H.Activate(), false, method); t.Restored()
    Same(t.H.Control():IsShown(), false)
    Same(#t.faults, method == "badGeometry" and 0 or 1, "own errors reported")
end
do
    local t = Setup(); Same(t.H.Activate(), true)
    t.f.failPoint = true
    Same(t.H.Restore(), false)
    Same(t.H.Snapshot().leased, true, "failed restore retains snapshot")
    Same(t.H.Control():IsVisible(), true)
    Same(#t.faults, 1)
    Same(t.H.Restore(), true); t.Restored()
    Same(t.H.Activate(), true)
    t.c.C_PlayerInteractionManager.IsValidNPCInteraction = function() error("injected read failure") end
    t.Tick(); t.Restored(); Same(#t.faults, 2)
end
do
    local t = Setup(); Same(t.H.Activate(), true)
    t.f.failPoint = true
    Same(t.H.Restore(), false)
    t.f.points = { { "CENTER", t.c.UIParent, "CENTER", 99, 0 } }
    Same(t.H.Restore(), true)
    Same(select(4, t.f:GetPoint(1)), 99, "foreign move after failed restore is preserved")
    Same(t.H.Snapshot().leased, false)
end
do
    local t = Setup(); Same(t.H.Activate(), true)
    -- A reload builds fresh frames/globals, regardless of the old in-memory mode.
    local fresh = Setup(); Same(fresh.H.Snapshot().leased, false); Same(fresh.frames, 0)
    Same(fresh.loads, 0); Same(fresh.mutations, 0)
    t.H.Restore()
end
print("PASSED: Auction Host " .. count .. " synthetic lifecycle checks")
