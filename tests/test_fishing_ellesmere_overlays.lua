-- Native-acceptance regressions, source-modelled from EllesmereUI 9.9.3 d84a1e19:
-- ResourceBars' ERB_CastBarFrame is a UIParent child, outside UnitFrames_Hider.
-- Forever's custom tracker has a separate item layer which its alpha hook mirrors.
-- This proves Fishing's ownership bookkeeping, not native protected-input behaviour.
dofile(TESTS .. "fishing_mock.lua")
dofile(TESTS .. "ellesmere_mock.lua")
local failures = 0
local function Check(ok, message) if not ok then failures = failures + 1; print("FAIL: " .. message) end end
local function Fresh(db)
    local c, W = FishingClient({ db = db })
    W.Camera()
    local EUI = EllesmereStandIn(c, W)
    EUI.modules.EllesmereUIResourceBars, EUI.modules.EllesmereUIQuestTracker = true, true
    local function Frame(name, alpha)
        local f = W.UI.Create("Frame", name, c.UIParent)
        f:SetSize(180, 30); f:SetAlpha(alpha or 1)
        return f
    end
    local cast = Frame("ERB_CastBarFrame", 0) -- idle owner-hidden bar: a channel will raise it
    local tracker, stock, bg = Frame("EUI_CustomQuestTracker", .8), Frame("ObjectiveTrackerFrame"), Frame("EllesmereUIQTBackground", .6)
    local items = Frame(nil, .8)
    c.hooksecurefunc(tracker, "SetAlpha", function(_, alpha) items:SetAlpha(alpha) end)
    local chat = Frame("ChatFrame1")
    W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
    c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
    return c, W, c.TwichUI.Fishing, cast, tracker, stock, bg, items, chat
end
local function Settle(W) W.Frames(1) end
local function Enter(c, W) c.TwichUI.RunCommand("fish mode"); Settle(W) end

do
    local c, W, F, cast, tracker, stock, bg, items, chat = Fresh()
    Check(F.Store.Get("fade.panels") == false, "optional aura/durability panels retain their existing default")
    Enter(c, W)
    Check(cast:GetAlpha() == 0 and tracker:GetAlpha() == 0 and stock:GetAlpha() == 0 and bg:GetAlpha() == 0,
        "immersive mode covers the real castbar and both quest-tracker variants plus the separate background")
    Check(items:GetAlpha() == 0, "the tracker's own alpha hook carries concealment to its secure item layer")
    Check(chat:GetAlpha() == 1, "chat remains visible")
    cast:SetAlpha(1) -- ResourceBars.SetElementVisibility(true) at channel start
    tracker:SetAlpha(1) -- tracker visibility edge on QUEST_LOG_UPDATE
    Check(cast:GetAlpha() == 0 and tracker:GetAlpha() == 0 and items:GetAlpha() == 0,
        "owner visibility edges remain covered without per-frame polling")
    F.Fade.Reveal(true); Settle(W)
    Check(cast:GetAlpha() == 1 and tracker:GetAlpha() == 1 and bg:GetAlpha() == .6 and items:GetAlpha() == 1,
        "reveal returns overlays and external item layer to each owner's latest alpha")
    F.Fade.Reveal(false); Settle(W)
    Check(tracker:GetAlpha() == 0 and items:GetAlpha() == 0, "releasing reveal covers the tracker again")
    -- Owner stops casting before Fishing Mode ends: do not resurrect that bar.
    cast:SetAlpha(0)
    tracker:SetAlpha(.45)
    c.TwichUI.RunCommand("fish mode"); Settle(W)
    Check(cast:GetAlpha() == 0 and tracker:GetAlpha() == .45 and bg:GetAlpha() == .6 and items:GetAlpha() == .45,
        "mode exit restores each owner's latest preference and preserves the stopped castbar")
    cast:SetAlpha(1)
    Check(cast:GetAlpha() == 1 and not F.Fade.Status().ticking, "castbar visibility works normally outside Fishing Mode; no upkeep survives")
    -- Re-entering, stopping, and recovery all use the same bounded owner lifecycle.
    for _, ending in ipairs({ "fish stop", "fish recover", "fish off" }) do
        F.Session.Ensure("manual")
        Enter(c, W)
        Check(cast:GetAlpha() == 0 and tracker:GetAlpha() == 0, "overlays concealed before " .. ending)
        c.TwichUI.RunCommand(ending); Settle(W)
        Check(cast:GetAlpha() == 1 and tracker:GetAlpha() == .45 and items:GetAlpha() == .45,
            "overlays restored after " .. ending)
        if ending == "fish off" then c.TwichUI.RunCommand("fish on") end
    end
end

do
    local c, W, F, cast, tracker, stock, bg, items, chat = Fresh()
    Enter(c, W)
    cast:SetAlpha(1)
    W.Fight()
    Check(cast:GetAlpha() == 1 and tracker:GetAlpha() == .8 and stock:GetAlpha() == 1 and bg:GetAlpha() == .6 and items:GetAlpha() == .8,
        "combat restores overlays and the tracker item layer immediately")
    cast:SetAlpha(.7); tracker:SetAlpha(.3)
    Check(cast:GetAlpha() == .7 and tracker:GetAlpha() == .3 and items:GetAlpha() == .3,
        "combat owner writes land unchanged once Fishing Mode releases the frames")
    W.Peace()
    Enter(c, W)
    local saved = FishRoundTrip(c.TwichUIFishingDB)
    c.FireEvent("PLAYER_LOGOUT")
    Check(cast:GetAlpha() == .7 and tracker:GetAlpha() == .3, "logout restores overlays")
    local c2, W2, F2, cast2, tracker2 = Fresh(saved)
    Check(cast2:GetAlpha() == 0 and tracker2:GetAlpha() == .8 and not F2.Fade.Faded(),
        "reload retains no concealment or alpha preference in saved data")
end

do
    local c, W, F, cast, tracker = Fresh()
    F.Store.Set("fade.ellesmere", false)
    Enter(c, W)
    cast:SetAlpha(1)
    Check(cast:GetAlpha() == 1 and tracker:GetAlpha() == .8, "explicitly disabled optional integration leaves Ellesmere overlays alone")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_ellesmere_overlays")
