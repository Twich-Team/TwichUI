-- TwichUI: Action bar glows, putting it together
-- Listens to the game, reads only what an event made stale (State.lua), asks Logic.lua what is due, keeps each due
-- reminder's timing (how long it glows, when it comes again), and has Draw.lua show the glows, the faded bars, the
-- messages and sounds. Events are gathered and looked at once, a moment later, so a burst of them costs one look.
-- It only reads and draws: it never casts, uses, targets or clicks anything, and says nothing in chat.
--
-- Timing of a reminder once it is due and allowed (its "when"): it glows for its glow time (0: until it is no longer
-- due), and its message and sound come as it starts; with a repeat, all of that comes again every so many seconds
-- while it stays due. A ready cooldown is a moment, not a state: it glows as the cooldown comes back, not merely because
-- a fight began (unless "also at the start of a fight" is on, or its glow time is "until done").
--
--   CT.Refresh()     on or off as the switch and the world say (the switch's apply, and at login)
--   CT.Due()         the reminders due now, for the settings window's preview of what is happening (read only)
--   CT.Snapshot()    counts for TwichUI_Diagnostics

local R = TwichUI
local BG, C, LG, ST, BT, D = R.BarGlows, R.BarGlowCatalog, R.BarGlowLogic, R.BarGlowState, R.BarGlowButtons, R.BarGlowDraw
local NT = R.BarGlowNotice
local Perf = R.Perf
local CT = { running = false, events = 0, evaluations = 0 }
R.BarGlowController = CT

local SETTLE = 0.05            -- events are looked at together, this long after the first
local GROUP_EVERY = 2          -- out of combat in a group: who is in range is looked at this often
local POLL_EVERY = 1           -- a cooldown whose end can't be read (a secret) is looked at again this often
local REVENGE_SECONDS = 5      -- Revenge can be used this long after a block, dodge or parry
local MEMORY_SECONDS = 8       -- a weapon buff cast this recently is the one that went on

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Now() return GetTime and GetTime() or 0 end
local function Wipe(t) for k in pairs(t) do t[k] = nil end end

local main, unitFrame, groupFrame
local generation = 0           -- bumped when stopped: every timer of before then does nothing
local pending = false
local stale = { auras = true, weapon = true, tracking = true, bags = true, group = true, book = true, ranks = true }
local cache = {}               -- auras, weapon, tracking, ranks, members, ctx
local active = {}              -- [id] = { r, style, phase, gen, alert }
local readyBefore = {}         -- [id] = true: a cooldown that was ready at the last look (allowed or not)
local wakeAt = {}              -- [spellId] = when a cooldown's end will be looked at
local polling = false
local revengeUntil, lastWeaponCast = 0, nil
local pendingBlessing = {}     -- [castGUID] = target name
local classToken

local Schedule

---------------------------------------------------------------------------
-- Messages and sounds
---------------------------------------------------------------------------
local function MessageText(r)
    if r.notOnBars then return "Missing buff (not on your action bars): " .. r.label end
    if r.text ~= r.label then return r.text end
    local info = C.TYPE_INFO[r.kind]
    return (info and info.text or "Reminder") .. ": " .. r.label
end

local function Alert(state)
    if not state.alert then return end
    local s = state.style
    if s.message then NT.Show(state.r.id, state.r) end
    if s.sound and s.sound ~= BG.NO_SOUND and PlaySoundFile then
        local path = R:ResolveSound(s.sound)
        if path then PlaySoundFile(path, "SFX") end
    end
end

---------------------------------------------------------------------------
-- Drawing: each button gets the glow of the most important reminder that wants it
---------------------------------------------------------------------------
local desired = {}
local ordered = {}

local function Render()
    Wipe(desired)
    for _, id in ipairs(ordered) do
        local state = active[id]
        if state and state.phase == "showing" then
            local r = state.r
            local function Take(list)
                for _, button in ipairs(list) do
                    if desired[button] == nil and BG.BarOn(BT.Bar(button) or "bar1") then desired[button] = state.style end
                end
            end
            for _, name in ipairs(r.spells or {}) do Take(BT.ForSpell(name)) end
            for _, item in ipairs(r.items or {}) do Take(BT.ForItem(item)) end
            if r.buttons then Take(r.buttons) end
        end
    end
    for button in pairs(D.Glowing()) do
        if not desired[button] then D.Clear(button) end
    end
    for button, style in pairs(desired) do D.Set(button, style) end
    if BG.AnyFaded() then
        local alpha = BG.Get("fadedOpacity") / 100
        BT.Each(function(button, bar)
            if BG.BarFaded(bar) and not desired[button] then D.Fade(button, alpha) else D.Unfade(button) end
        end)
    elseif next(D.Faded()) then
        D.UnfadeAll()
    end
end

---------------------------------------------------------------------------
-- Timing
---------------------------------------------------------------------------
local function After(seconds, state, fn)
    local gen, token = generation, state.gen
    C_Timer.After(seconds, function()
        if gen ~= generation or not CT.running then return end
        if active[state.r.id] ~= state or state.gen ~= token then return end
        fn()
    end)
end

local function Show(state)
    state.phase = "showing"
    Alert(state)
    local s = state.style
    if s.glowTime and s.glowTime > 0 then
        After(s.glowTime, state, function()
            state.phase = "waiting"
            Render()
        end)
    end
end

local function Start(state, quietStart)
    state.gen = (state.gen or 0) + 1
    if quietStart then
        state.phase = "spent"   -- not news: it waits, without glow or repeats, until it is used and comes back
        return
    end
    Show(state)
    local rep = state.style["repeat"]
    if rep and rep > 0 then
        local function Again()
            Show(state)
            Render()
            After(rep, state, Again)
        end
        After(rep, state, Again)
    end
end

---------------------------------------------------------------------------
-- What the game says, read again only where it went stale
---------------------------------------------------------------------------
local memo = { ready = {}, usable = {}, count = {} }

local function WakeFor(id, endsAt)
    if wakeAt[id] and math.abs(wakeAt[id] - endsAt) < 0.05 then return end
    wakeAt[id] = endsAt
    local gen = generation
    C_Timer.After(math.max(0.05, endsAt - Now() + 0.05), function()
        if gen ~= generation or wakeAt[id] ~= endsAt then return end
        wakeAt[id] = nil
        Schedule()
    end)
end

local function StartPolling()
    if polling then return end
    polling = true
    local gen = generation
    local function Poll()
        if gen ~= generation or not CT.running then polling = false return end
        if not CT.needsPoll then polling = false return end
        Schedule()
        C_Timer.After(POLL_EVERY, Poll)
    end
    C_Timer.After(POLL_EVERY, Poll)
end

-- Kept for one look (ready, usable) or until the bags change (count); UNKNOWN stands for an answer of nil.
local UNKNOWN = {}
local function Memo(t, id, read)
    local m = t[id]
    if m == UNKNOWN then return nil end
    if m ~= nil then return m end
    m = read(id)
    t[id] = m == nil and UNKNOWN or m
    return m
end

local function ReadCooldown(id)
    local ready, endsAt = ST.Cooldown(id)
    if ready == false then
        if endsAt then WakeFor(id, endsAt) else CT.needsPoll = true end
    end
    return ready
end
local function Ready(id) return Memo(memo.ready, id, ReadCooldown) end
local function Usable(id) return Memo(memo.usable, id, ST.Usable) end
local function Count(id) return Memo(memo.count, id, ST.Count) end

local function Window(key)
    if classToken ~= "WARRIOR" then return false end
    if key == "revenge" then return Now() < revengeUntil end
    if key == "overpower" then
        -- the game keeps a warrior's Overpower moment as a combo point (Classic's way)
        local cp = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
        if cp and UnitPower then
            local n = Plain(UnitPower("player", cp))
            return type(n) == "number" and n > 0
        end
    end
    return false
end

local function Observe()
    local ctx = ST.Context()
    cache.ctx = ctx
    if stale.book then ST.ReadBook(); stale.book = false; stale.ranks = true end
    if BT.dirty then BT.Map(); stale.ranks = true end
    if stale.auras then cache.auras = ST.AuraNames("player"); stale.auras = false end
    if stale.weapon then
        local before = cache.weapon
        cache.weapon = ST.Weapon()
        stale.weapon = false
        -- a hand that just got its enchant: the weapon buff cast a moment ago went on it
        local w = cache.weapon
        if w and before and lastWeaponCast and Now() - lastWeaponCast.at <= MEMORY_SECONDS then
            for _, hand in ipairs(BG.HANDS) do
                if before[hand] == false and w[hand] == true then BG.Remember("weapon" .. hand, lastWeaponCast.key) end
            end
        end
    end
    if stale.tracking then cache.tracking = ST.Tracking(); stale.tracking = false end
    if stale.ranks then cache.ranks = ST.Ranks(); stale.ranks = false end
    if ctx.group ~= "none" and not ctx.combat then
        if stale.group or not cache.members then cache.members = ST.Members(ctx.group); stale.group = false end
    else
        cache.members = nil
    end
    Wipe(memo.ready); Wipe(memo.usable)
    if stale.bags then Wipe(memo.count); stale.bags = false end
    CT.needsPoll = false
    return {
        class = classToken, ctx = ctx, auras = cache.auras, weapon = cache.weapon, tracking = cache.tracking,
        ranks = cache.ranks, members = cache.members,
        name = ST.Name, display = ST.Display, itemDisplay = ST.ItemDisplay, itemSpell = ST.ItemSpell,
        known = ST.Known, onBars = BT.HasSpell, itemOnBars = BT.HasItem, count = Count,
        ready = Ready, usable = Usable, window = Window,
        remembered = BG.Remembered, blessing = BG.Blessing,
    }
end

---------------------------------------------------------------------------
-- The look: what is due, what is allowed, what starts and stops
---------------------------------------------------------------------------
local lastDue = {}

local function StyleKey(s)
    local parts = {}
    for i, f in ipairs(BG.STYLE_ORDER) do parts[i] = tostring(s[f]) end
    return table.concat(parts, "|")
end

local function Evaluate()
    pending = false
    if not CT.running then return end
    local pt = Perf.on and Perf.Start("glows.evaluate")
    CT.evaluations = CT.evaluations + 1
    local obs = Observe()
    local due = LG.Due(obs, BG)
    lastDue = due
    local quiet = BG.Get("quietInTowns")
    local fightStart = BG.Get("cooldownsAtFightStart")
    local seen = {}
    Wipe(ordered)
    local readyNow = {}
    for _, r in ipairs(due) do
        if r.pulse then readyNow[r.id] = true end
        local style = BG.Style(r.kind, r.key)
        local glow, alert = LG.When(r.kind, style, obs.ctx, quiet)
        if glow then
            seen[r.id] = true
            ordered[#ordered + 1] = r.id
            local state = active[r.id]
            local key = StyleKey(style)
            if not state then
                state = { r = r, style = style, key = key, alert = alert }
                active[r.id] = state
                -- a cooldown that was ready before and only became allowed now (a fight started) is not news
                local quietStart = r.pulse and style.glowTime > 0 and readyBefore[r.id] and not fightStart
                Start(state, quietStart)
            elseif state.key ~= key then
                state.r, state.style, state.key, state.alert = r, style, key, alert
                Start(state, state.phase == "spent")   -- the look changed: its timing starts again
            else
                local nowAllowed = alert and not state.alert
                state.r, state.style, state.alert = r, style, alert
                -- glowing all along (Alert in town), and now in a town: the message and sound come
                if nowAllowed and state.phase ~= "spent" then Alert(state) end
            end
        end
    end
    for id in pairs(active) do
        if not seen[id] then
            active[id] = nil
            NT.Done(id)   -- its message card goes with it
        end
    end
    Wipe(readyBefore)
    for id in pairs(readyNow) do readyBefore[id] = true end
    Render()
    if CT.needsPoll then StartPolling() end
    if pt then Perf.Stop(pt) end
end

Schedule = function()
    if pending or not CT.running then return end
    pending = true
    local gen = generation
    C_Timer.After(SETTLE, function()
        if gen ~= generation then pending = false return end
        Evaluate()
    end)
end
CT.Schedule = function() Schedule() end

---------------------------------------------------------------------------
-- Group checks: out of combat, in a group; who is in range is looked at every few seconds
---------------------------------------------------------------------------
local groupTicking = false
local function GroupWanted()
    if not CT.running then return false end
    local ctx = cache.ctx or ST.Context()
    if ctx.combat or ctx.group == "none" then return false end
    if ctx.group == "party" and not BG.Get("partyBuffs") then return false end
    if ctx.group == "raid" and not BG.Get("raidBuffs") then return false end
    return BG.TypeEnabled("missingBuff")
end

local function UpdateGroupWatch()
    local want = GroupWanted()
    if groupFrame then
        if want and not groupFrame:IsEventRegistered("UNIT_AURA") then groupFrame:RegisterEvent("UNIT_AURA")
        elseif not want and groupFrame:IsEventRegistered("UNIT_AURA") then groupFrame:UnregisterEvent("UNIT_AURA") end
    end
    if want and not groupTicking then
        groupTicking = true
        local gen = generation
        local function Tick()
            if gen ~= generation or not GroupWanted() then groupTicking = false return end
            stale.group = true
            Schedule()
            C_Timer.After(GROUP_EVERY, Tick)
        end
        C_Timer.After(GROUP_EVERY, Tick)
    end
end

---------------------------------------------------------------------------
-- What you cast: remembered (an aspect, a seal, a tracking, a weapon buff, the blessing each class got)
---------------------------------------------------------------------------
local castNames            -- [lower name] = { category, key } for every exclusive group entry; built on first cast
local weaponNames          -- [lower name] = key
local blessingNames        -- [lower name] = key (single and greater)

local function BuildCastNames()
    castNames, weaponNames, blessingNames = {}, {}, {}
    for _, e in ipairs(C.ENTRIES) do
        if C.ForClass(e, classToken) then
            if e.category and e.spell then
                local n = ST.Name(e.spell)
                if n then castNames[n] = { category = e.category, key = e.key } end
            end
            if e.category == "blessing" then
                for _, id in ipairs({ e.spell, e.group and e.group.spell }) do
                    local n = id and ST.Name(id)
                    if n then blessingNames[n] = e.key end
                end
            end
            if e.type == "weaponBuff" then
                if e.spell then
                    local n = ST.Name(e.spell)
                    if n then weaponNames[n] = e.key end
                end
                for _, item in ipairs(e.items or {}) do
                    local n = ST.ItemSpell(item)
                    if n then weaponNames[n] = e.key end
                end
                weaponNames[e.label:lower()] = weaponNames[e.label:lower()] or e.key
            end
        end
    end
    for _, a in ipairs(BG.Added()) do
        local key = BG.AddedKey(a)
        if a.kind == "weaponBuff" then
            local n = a.spell and ST.Name(a.spell) or (a.item and ST.ItemSpell(a.item))
            if n then weaponNames[n] = key end
        elseif (a.kind == "missingSeal" or a.kind == "missingTracking") and a.spell then
            local n = ST.Name(a.spell)
            if n then castNames[n] = { category = a.kind == "missingSeal" and "seal" or "tracking", key = key } end
        end
    end
end

local function NameIn(name)
    if not name or not UnitExists then return nil end
    local group = IsInRaid and IsInRaid() and "raid" or "party"
    local max = group == "raid" and 40 or 4
    for i = 1, max do
        local unit = group .. i
        local n = Plain(UnitName(unit))
        if n and n == name then
            local _, class = UnitClass(unit)
            return Plain(class)
        end
    end
    return nil
end

local function OnCast(castGUID, spellId)
    spellId = Plain(spellId)
    local name = spellId and ST.Name(spellId)
    if not name then return end
    if not castNames then BuildCastNames() end
    local c = castNames[name]
    if c then BG.Remember(c.category, c.key) end
    local w = weaponNames[name]
    if w then lastWeaponCast = { key = w, at = Now() } end
    local b = blessingNames[name]
    local guid = Plain(castGUID)
    if b and guid and pendingBlessing[guid] then
        local class = NameIn(pendingBlessing[guid])
        if class then BG.SetBlessing(class, b) end
    end
    if guid then pendingBlessing[guid] = nil end
    if name == ST.Name(6572) then revengeUntil = 0 end   -- Revenge used: its moment is over
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local REMAP = {
    ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORMS = true, UPDATE_SHAPESHIFT_FORM = true, UPDATE_MACROS = true, PLAYER_ENTERING_WORLD = true,
}
local CONTEXT = {
    PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, PLAYER_TARGET_CHANGED = true, PLAYER_UPDATE_RESTING = true,
    PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true, PLAYER_CONTROL_LOST = true, PLAYER_CONTROL_GAINED = true,
    ZONE_CHANGED_NEW_AREA = true,
}
local EVENTS = {
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_UPDATE_RESTING",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "ZONE_CHANGED_NEW_AREA",
    "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE",
    "BAG_UPDATE_DELAYED", "MINIMAP_UPDATE_TRACKING", "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
}

local function OnEvent(event, a1, a2, a3, a4)
    CT.events = CT.events + 1
    if REMAP[event] then
        BT.Dirty()
    elseif event == "SPELLS_CHANGED" then
        stale.book = true
        castNames = nil
        BT.Dirty()
    elseif CONTEXT[event] then
        -- the context is read at every look; the group check starts or stops with combat
        -- (auras could not be read during the fight: read them again as it ends)
        if event == "PLAYER_REGEN_ENABLED" then stale.auras = true end
        UpdateGroupWatch()
    elseif event == "BAG_UPDATE_DELAYED" then
        stale.bags = true
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        stale.tracking = true
    elseif event == "GROUP_ROSTER_UPDATE" then
        ST.RosterChanged()
        stale.group = true
        UpdateGroupWatch()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        stale.weapon = true
    elseif event == "UNIT_AURA" then
        stale.auras = true
    elseif event == "UNIT_INVENTORY_CHANGED" then
        stale.weapon = true
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, castGUID, spellID: only kept for a blessing's target
        local target, guid = Plain(a2), Plain(a3)
        if target and guid and classToken == "PALADIN" then
            pendingBlessing[guid] = target
            local n = 0
            for _ in pairs(pendingBlessing) do n = n + 1 end
            if n > 8 then Wipe(pendingBlessing); pendingBlessing[guid] = target end   -- bounded
        end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(a2, a3)
    elseif event == "UNIT_COMBAT" then
        -- unit, action, descriptor: an attack you blocked, dodged or parried opens Revenge
        local action, descriptor = Plain(a2), Plain(a3)
        if action == "DODGE" or action == "PARRY" or action == "BLOCK"
            or (type(descriptor) == "string" and descriptor:find("BLOCK")) then
            revengeUntil = Now() + REVENGE_SECONDS
            local gen = generation
            C_Timer.After(REVENGE_SECONDS + 0.05, function() if gen == generation then Schedule() end end)
        else
            return
        end
    elseif event == "UNIT_POWER_UPDATE" then
        if a2 ~= "COMBO_POINTS" then return end
    end
    Schedule()
end

local function OnGroupAura(unit)
    if type(unit) ~= "string" then return end
    if not (unit:find("^party%d") or unit:find("^raid%d")) then return end
    ST.UnitAurasChanged(unit)
    stale.group = true
    Schedule()
end

local function Build()
    if main then return end
    main = CreateFrame("Frame")
    main:SetScript("OnEvent", Perf.Wrap("glows.event", function(_, event, ...) OnEvent(event, ...) end))
    unitFrame = CreateFrame("Frame")
    unitFrame:SetScript("OnEvent", Perf.Wrap("glows.unit", function(_, event, ...) OnEvent(event, ...) end))
    groupFrame = CreateFrame("Frame")
    groupFrame:SetScript("OnEvent", Perf.Wrap("glows.group", function(_, _, unit) OnGroupAura(unit) end))
end

local function StartRunning()
    Build()
    local _, class = UnitClass("player")
    classToken = Plain(class)
    CT.running = true
    for _, e in ipairs(EVENTS) do main:RegisterEvent(e) end
    unitFrame:RegisterUnitEvent("UNIT_AURA", "player")
    unitFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    unitFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    unitFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    if classToken == "WARRIOR" then
        unitFrame:RegisterUnitEvent("UNIT_COMBAT", "player")
        unitFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    end
    for k in pairs(stale) do stale[k] = true end
    castNames = nil
    BT.Dirty()
    UpdateGroupWatch()
    Schedule()
end

local function StopRunning()
    CT.running = false
    generation = generation + 1
    pending, polling, groupTicking = false, false, false
    if main then main:UnregisterAllEvents() end
    if unitFrame then unitFrame:UnregisterAllEvents() end
    if groupFrame then groupFrame:UnregisterAllEvents() end
    Wipe(active); Wipe(ordered); Wipe(readyBefore); Wipe(wakeAt); Wipe(pendingBlessing); Wipe(cache)
    lastDue = {}
    D.ClearAll()
    D.UnfadeAll()
    NT.HideAll()
end

function CT.Enabled() return R:Enabled("barGlows") end

function CT.Refresh()
    local want = CT.Enabled() and R.Life.InWorld()
    if want and not CT.running then StartRunning()
    elseif not want and CT.running then StopRunning()
    elseif want then Schedule() end
end

-- A setting changed: looks are read again (Config dropped its cache); what was added may need names again.
BG.Subscribe(function(what)
    if not CT.running then return end
    if what == "added" or what == "profile" then castNames = nil; stale.bags = true end
    if what == "settings" or what == "profile" then UpdateGroupWatch() end
    Schedule()
end)

R:On("PLAYER_ENTERING_WORLD", function() CT.Refresh() end)
R:On("PLAYER_LEAVING_WORLD", function() if CT.running then StopRunning() end end)

-- Read only: the reminders due at the last look, and whether each is allowed and glowing now.
function CT.Due()
    local out = {}
    for _, r in ipairs(lastDue) do
        local state = active[r.id]
        out[#out + 1] = { id = r.id, kind = r.kind, key = r.key, label = r.label, text = MessageText(r),
            allowed = state ~= nil, showing = state ~= nil and state.phase == "showing" }
    end
    return out
end

function CT.Snapshot()
    local n, showing = 0, 0
    for _, s in pairs(active) do
        n = n + 1
        if s.phase == "showing" then showing = showing + 1 end
    end
    local events = 0
    if main then for _, e in ipairs(EVENTS) do if main:IsEventRegistered(e) then events = events + 1 end end end
    local d = D.Snapshot()
    return { running = CT.running, active = n, showing = showing, events = events, overlays = d.made, glowing = d.shown,
        buttons = BT.mapped, evaluations = CT.evaluations, received = CT.events }
end
