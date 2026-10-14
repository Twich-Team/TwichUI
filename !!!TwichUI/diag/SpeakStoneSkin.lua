-- TwichUI: troubleshooting report, SpeakStone skin
-- Reads SpeakStoneSkin.Snapshot(): whether SpeakStone is there and which version, whether the skin is on,
-- whether SpeakStone's speech frame has been built and drawn on, which hooks are in, which media fell back,
-- and counts of what was drawn and put back. Never the text, speaker or quest names, the character, or the
-- settings' values.

local R = TwichUI
local D = R.Diag

local WHY = {
    off = "turned off",
    ["speakstone-missing"] = "SpeakStone isn't installed",
    ["speakstone-disabled"] = "SpeakStone is turned off in the AddOns list",
    waiting = "waiting for SpeakStone to build its speech frame (it does so the first time it shows something)",
    unsupported = "this SpeakStone's speech frame does not have the pieces the skin needs; nothing was changed",
    error = "stopped after an error; the frame was put back as it was",
    active = "active",
}

local function Snapshot()
    local S = R.SpeakStoneSkin
    if not (S and S.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = S.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("SpeakStone: %s%s", s.addon or "unknown", s.version and (", version " .. s.version) or "")
    Line("skin switch: %s; started: %s; speech frame built: %s; drawn on: %s",
        s.switchOn and "on" or "off", D.Flag(s.enabled), D.Flag(s.frameBuilt), D.Flag(s.applied))
    Line("hooks: CreateFont %s, speech frame (SetScale, SetHeight) %s",
        s.createHook and "in" or "not in", s.frameHooked and "in" or "not in")
    Line("media: LibSharedMedia %s; name font %s, text font %s, time font %s, button font %s",
        s.sharedMedia and "available" or "not available",
        s.fallbackName and "fell back to SpeakStone's own" or "as chosen",
        s.fallbackText and "fell back to SpeakStone's own" or "as chosen",
        s.fallbackTime and "fell back to SpeakStone's own" or "as chosen",
        s.fallbackButton and "fell back to SpeakStone's own" or "as chosen")
    Line("work: %d draws, %d settings passes, %d layouts (%d text refills), %d height fixes, %d put back; pass waiting: %s",
        s.draws or 0, s.passes or 0, s.layouts or 0, s.refills or 0, s.heights or 0, s.restores or 0, D.Flag(s.scheduled))
    Line("native pieces: %d background pieces faded%s; progress track %s", s.hidden or 0,
        (s.applied and (s.hidden or 0) == 0) and " (none found: SpeakStone's own band stays visible)" or "",
        s.trackFound and "found" or ((s.unmatched or 0) > 0 and "not found (left as SpeakStone draws it)" or "not looked for yet"))
    local status, reason
    if s.code == "off" then status = "off"
    elseif s.code == "active" then status = "ready"
    elseif s.code == "speakstone-missing" or s.code == "speakstone-disabled" or s.code == "unsupported"
        or s.code == "error" then status, reason = "unavailable", s.code
    else status, reason = "waiting", s.code end
    lines[#lines + 1] = "state: " .. (WHY[s.code] or s.code)
    return {
        configured = s.switchOn, initialized = D.When(s.switchOn, s.applied), status = status, reason = reason, lines = lines,
        limits = {
            "Only SpeakStone Forever - Main's speech frame is drawn on; its settings window, tutorial and library are not.",
            "The frame's dark band and hairlines are every Texture of the frame except the portraits, and the progress track is the bar's one background texture; a different SpeakStone may not match.",
            "The frame is plain (no secure template), so it is restyled in combat too; whether the game agrees is checked in the game.",
            "The hooks stay installed until a reload once the skin has been on; they do nothing while it is off.",
        },
    }
end

D.Register("speakstoneSkin", { title = "SpeakStone skin", order = 49, snapshot = Snapshot })
