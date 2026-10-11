-- TwichUI: troubleshooting report, RestedXP skin
-- Reads RestedXPSkin.Snapshot(): whether RestedXP is there and which version, whether the skin is on,
-- whether it could attach, whether its theme is the one RestedXP is using, another RestedXP skin that
-- would fight it, which media fell back, and counts of what it holds and has queued. Never guide text,
-- step or quest names, the character, or the settings' values.

local R = TwichUI
local D = R.Diag

local WHY = {
    off = "turned off",
    ["restedxp-missing"] = "RestedXP isn't installed",
    ["restedxp-disabled"] = "RestedXP is turned off in the AddOns list",
    waiting = "waiting for RestedXP to finish loading",
    unsupported = "this RestedXP does not have what the skin needs",
    conflict = "another RestedXP skin is drawing",
    ["theme-not-selected"] = "RestedXP is using another theme",
    ["v2-window"] = "RestedXP's v2 guide window is on; only the theme's colours and font reach it",
    active = "active",
}

local function Snapshot()
    local S = R.RestedXPSkin
    if not (S and S.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = S.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("RestedXP: %s%s", s.addon or "unknown", s.version and (", version " .. s.version) or "")
    Line("skin switch: %s; started: %s; attached to RestedXP: %s", s.switchOn and "on" or "off", D.Flag(s.enabled), D.Flag(s.integrated))
    Line("theme registered with RestedXP: %s; selected there: %s; theme to go back to is known: %s",
        D.Flag(s.published), D.Flag(s.selected), D.Flag(s.remembered))
    Line("RestedXP's v2 guide window: %s", s.integrated and (s.v2 and "on" or "off") or "not read")
    Line("another RestedXP skin: %s", s.conflict or "none detected (only EUI-RestedXP and LiteTweaks can be recognised)")
    Line("media: LibSharedMedia %s, EllesmereUI borders %s; title font %s, body font %s",
        s.sharedMedia and "available" or "not available", s.ellesmere and "available" or "not available",
        s.fallbackTitle and "fell back to RestedXP's own" or "as chosen", s.fallbackBody and "fell back to RestedXP's own" or "as chosen")
    Line("holds: %d frames drawn on, %d hooks, %d frame hooks, %d remembered colours", s.owned or 0, s.hooks or 0, s.trayHooks or 0, s.knownColors or 0)
    Line("work: %d passes, %d RestedXP refreshes, %d held for combat; update waiting: %s; waiting for combat: %s; select theme when ready: %s; strip waiting: %s",
        s.passes or 0, s.refreshes or 0, s.skipped or 0, D.Flag(s.scheduled), D.Flag(s.waitingCombat), D.Flag(s.pendingSelect), D.Flag(s.pendingTeardown))
    local t = S.Timers and S.Timers.Snapshot()
    if t then
        Line("timer bars: %s; hooks on StartTimer %s and ShowTimers %s, stop callback %s; supported by this RestedXP: %s",
            t.switchOn and "skinning on" or "skinning off", D.Flag(t.hookStart), D.Flag(t.hookShow), D.Flag(t.stopCallback),
            D.Flag(t.supported))
        Line("timer bars: %d bars known, %d drawn now; %d drawn, %d put back, %d refreshes; fill %s, label font %s, time font %s; "
            .. "gradient fallbacks %d; height changed: %s; held for combat: %s; preview shown: %s",
            t.bars or 0, t.drawn or 0, t.styled or 0, t.restored or 0, t.refreshes or 0,
            t.fallbackFill and "fell back to RestedXP's own" or "as chosen",
            t.fallbackLabel and "fell back" or "as chosen", t.fallbackTime and "fell back" or "as chosen",
            t.gradientFallbacks or 0, D.Flag(t.heightChanged), D.Flag(t.waiting), D.Flag(t.previewShown))
    end
    local status, reason
    if s.code == "off" then status = "off"
    elseif s.code == "active" then status = "ready"
    elseif s.code == "restedxp-missing" or s.code == "restedxp-disabled" or s.code == "unsupported" then status, reason = "unavailable", s.code
    else status, reason = "waiting", s.code end
    lines[#lines + 1] = "state: " .. (WHY[s.code] or s.code)
    return {
        configured = s.switchOn, initialized = D.When(s.switchOn, s.integrated), status = status, reason = reason, lines = lines,
        limits = {
            "Only RestedXP's legacy guide window is drawn on; the v2 window, map arrow, right-click menus and tooltips are not.",
            "Other RestedXP skins can only be recognised if they are EUI-RestedXP or LiteTweaks.",
            "RestedXP gives themes no way to be removed; turning the skin off takes the entry out of its list.",
            "Timer bars: RestedXP's own bars only, and not while its v2 guide window is on. They have no spark; width is RestedXP's.",
        },
    }
end

D.Register("restedxpSkin", { title = "RestedXP skin", order = 47, snapshot = Snapshot })
