-- TwichUI: troubleshooting report, Healer Watch
-- Reads the watcher's Snapshot(): whether it is on and applies here, how the healer was chosen, what kind of reading
-- each observation is, what the game restricts right now, and counts. Words and numbers only: no names, GUIDs, unit
-- tokens, mana values, phrases or anything said in chat. Nothing is asked of the game beyond what Snapshot reads.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local W = R.HealerWatcher
    if not (W and W.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = W.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; in the world: %s; scope: %s (applies here: %s); in combat: %s; events registered: %d", s.enabled and "on" or "off",
        D.Flag(s.inWorld), tostring(s.scope), D.Flag(s.scopeActive), D.Flag(s.inCombat), s.events)
    Line("selection: %s%s; chosen for this session: %s", tostring(s.source or "none"), s.problem and (" (" .. s.problem .. ")") or "", D.Flag(s.choice))
    Line("life: %s; mana: %s; band: %s; drinking: %s (%s); chat signal: %s", tostring(s.life), tostring(s.mana), tostring(s.band),
        tostring(s.drink), s.drinkEvidence and "recognized" or "-", s.chatLeft and "current" or "none")
    Line("shown: %s (%s); preview: %s; unlocked: %s", D.Flag(s.shown), tostring(s.reason), D.Flag(s.preview), D.Flag(s.positioning))
    Line("restricted now: auras %s, group chat %s; mana secrecy level: %s; restricted mana drawing refused: %s",
        D.Flag(s.aurasSecret), D.Flag(s.chatLockdown), tostring(s.manaSecrecy), D.Flag(s.secretRefused))
    Line("reads: roster %d, mana %d, aura looks %d (skipped %d); chat seen %d, matched %d, other senders %d, unreadable %d, no sender %d, repeats %d; sounds %d (held %d)",
        s.rosterReads, s.manaReads, s.auraScans, s.auraSkipped, s.chatSeen, s.chatMatched, s.chatOther, s.chatSecret, s.chatNoSender,
        s.chatDuplicates, s.sounds, s.soundsHeld)
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not s.inWorld then status, reason = "waiting", "not-in-world"
    elseif not s.scopeActive then status, reason = "idle", "out-of-scope"
    elseif s.problem then status, reason = "waiting", "no-healer" end
    return {
        configured = s.enabled, initialized = s.running, status = status, reason = reason, lines = lines,
        limits = {
            "Off, nothing is registered and no frame exists. Out of scope, only the group's roster events are.",
            "The client documents group chat as hidden from addons in dungeons and raids, and auras as hidden in combat; mana can be restricted too. Hidden values are counted, never guessed.",
            "None of this has been confirmed in the game; docs/healer-watch.md lists the checks.",
        },
    }
end

D.Register("healerWatch", { title = "Healer Watch", order = 52, snapshot = Snapshot })
