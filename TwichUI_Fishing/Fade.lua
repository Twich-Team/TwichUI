-- TwichUI Fishing: fading the interface around Fishing Mode (Stage 2)
-- While Fishing Mode is immersive the parts of the interface the player doesn't need for fishing fade out, and come back as
-- they were afterwards. Never UIParent itself, never anything that carries a warning, an error, a cast bar, loot or a window
-- the player opened.
--
-- What fades (config fade.*; each group its own switch):
--   bars      the game's action, stance, pet and possess bars, the micro menu and bags bar, the experience and reputation
--             bars; with EllesmereUI (fade.ellesmere), its action bars, paging arrows, data bars and bar caps
--   units     the game's player, target, focus, pet and party frames; with EllesmereUI, all of its unit frames (through the
--             one frame they share), their 3D portraits, its party and raid frames and its resource bars
--   minimap   the minimap cluster (with EllesmereUI's minimap module, the map itself: its blips may stay)
--   panels    (off by default) the quest tracker, buff and debuff frames, the durability figure, EllesmereUI's aura bars
--   extra     frames another addon draws that the player names (/tui fish fade add <FrameName>)
--   notices   TwichUI's own notification cards, reminders and glows, through the Quiet screen's hold (QuietScreen.lua): a
--             hold of Fishing Mode's own, which never turns on, off or shows as the player's Quiet screen switch
-- EllesmereUI's frames come from Ellesmere.lua (by role, from what EllesmereUI creates); nothing else of another addon is
-- guessed. A frame is faded whether it is shown or not (a target frame that appears while fishing appears faded), as long
-- as it exists, takes an alpha, is not forbidden and is not on the never list.
--
-- Ownership (the policy). Fishing Mode owns what each faded frame SHOWS while it is on; the frame's owner (the game,
-- EllesmereUI, another addon) keeps its PREFERENCE. Only SetAlpha is ever used: nothing is hidden, shown, moved,
-- re-parented or saved, no visibility driver is touched, and no addon's function is called or replaced.
--   * Each faded frame gets one post-hook on its own SetAlpha (hooksecurefunc, installed once, never removed, inert while
--     Fishing Mode is off). When the owner writes an alpha, that value becomes the frame's preference and, in the same
--     frame of drawing, the faded alpha is put back over it: no flash, and no loop (the owner's own records, such as
--     EllesmereUI's, stay as the owner wrote them).
--   * The pointer over a frame wins: an owner's write while the pointer is on the frame (a mouse-over bar) is shown, and the
--     frame fades again once the pointer has left (checked once a second).
--   * A frame its owner writes more than CONTEST times within two seconds is left to its owner for the rest of the time
--     (counted as contested): Fishing Mode never fights a frame something else animates.
--   * Coming back, each frame returns to its owner's latest preference, not to what it had when Fishing Mode began; an owner
--     that writes during that last fade has the last word at once. A forced recovery puts every frame back regardless.
-- Bounded upkeep, once a second while faded: frames that appeared since (a module that built them late), frames rebuilt
-- under the same name (the old one is put back, the new one faded), and hovered frames to fade again. The models under
-- EllesmereUI's unit frames are looked for every fifth second. Nothing runs per frame except a fade in progress, on one
-- driver frame whose OnUpdate exists only while something moves. SetAlpha is not a protected call (EllesmereUI relies on
-- that in combat on Forever too), but Fishing Mode puts everything back before combat anyway.
--
-- Dialogue UI fades UIParent itself while a conversation is open and puts it back after; Fishing Mode never touches
-- UIParent, so the two never meet.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Fa = {}
F.Fade = Fa

Fa.GROUPS = {
    bars = { "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame",
        "PossessActionBar", "PossessBarFrame", "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar", "MainMenuExpBar",
        "ReputationWatchBar", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager" },
    units = { "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame", "CompactPartyFrame" },
    -- the cluster, and the pieces that hang around the map (each only if it exists; the cluster's own children already follow it)
    minimap = { "MinimapCluster", "MinimapBackdrop", "MiniMapTracking", "MiniMapMailFrame", "MiniMapBattlefieldFrame",
        "MiniMapWorldMapButton", "GameTimeFrame", "MinimapZoneTextButton", "TimeManagerClockButton",
        "ExpansionLandingPageMinimapButton" },
    panels = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame", "BuffFrame", "DebuffFrame", "DurabilityFrame" },
}
-- Damage meters other than EllesmereUI's (Details!, Recount, Skada), by the names their own windows carry. Looked for, never
-- required: a name that isn't there is not an error. Unverified in the real client (read from those addons' public sources).
Fa.METERS = { "DetailsBaseFrame1", "DetailsBaseFrame2", "DetailsBaseFrame3", "DetailsBaseFrame4", "Recount_MainWindow",
    "SkadaBarWindowSkada" }
-- TwichUI's own bars: the camping bar's frame (R.Camping.Frame(), it has no global name) and the sleeping bag bar's.
Fa.TWICHUI = {
    { name = "TwichUI camping bar", resolve = function() local C = R.Camping; return C and C.Frame and C.Frame() or nil end },
    { name = "TwichUICampingRest" },
}
-- Chat is never faded (Fishing Mode wants the chat to be read): by name, and by being an ancestor of a chat frame.
Fa.CHAT = { "^ChatFrame%d", "^GeneralDockManager", "^ChatAlertFrame", "^QuickJoinToastButton", "^EllesmereUIChat", "^ChatConfig",
    "^FloatingChatFrame", "^ChatMenu" }
function Fa.IsChatName(name)
    if type(name) ~= "string" then return false end
    for _, pat in ipairs(Fa.CHAT) do if name:find(pat) then return true end end
    return false
end
local function AboveChat(frame)
    local chat = rawget(_G, "ChatFrame1")
    local p = chat
    for _ = 1, 12 do
        if type(p) ~= "table" then return false end
        if p == frame then return true end
        if type(p.GetParent) ~= "function" then return false end
        local ok, up = pcall(p.GetParent, p)
        if not ok then return false end
        p = up
    end
    return false
end

-- Never faded, whatever a list says: the game's root, what carries warnings, errors, casts, loot and the player's windows,
-- and frames an addon asks never to have their alpha changed.
Fa.NEVER = { UIParent = true, WorldFrame = true, UIErrorsFrame = true, RaidWarningFrame = true, RaidBossEmoteFrame = true,
    PlayerCastingBarFrame = true, CastingBarFrame = true, LootFrame = true, StaticPopup1 = true, GameTooltip = true,
    ChatFrame1EditBox = true, MirrorTimer1 = true, TwichUIFishingCastBar = true, TwichUIFishingCatchList = true,
    TwichUIFishingToasts = true, TwichUIFishingBrand = true }
Fa.DURATION = 0.4
Fa.QUIET_OWNER = "fishing"
Fa.CONTEST = 24          -- owner writes within CONTEST_WINDOW seconds that make a frame contested
Fa.CONTEST_WINDOW = 2
Fa.TICK = 1              -- seconds between upkeep passes while faded

local entries = {}          -- the frames Fishing Mode is handling (see Add)
local byFrame = {}          -- [frame] = entry, while handling
local hooked = setmetatable({}, { __mode = "k" })   -- frames whose SetAlpha carries the post-hook
local state = "idle"        -- "idle" | "faded" | "restoring"
local revealed = false
local driver, moving = nil, false
local guard = false         -- true while Fishing Mode itself writes (the hook ignores its own writes)
local ticker, ticks = nil, 0
local skipped = {}          -- { name, why } of the last Apply
Fa.steps, Fa.covered = 0, 0 -- alpha changes made; owner writes covered (diagnostics, tests)
Fa.last = nil               -- the last fade back: { restored, owner, contested, stale, forced, at }

local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end
local function Alpha() return S.Get("fade.alpha") or 0 end
local function Smooth(t) return t * t * (3 - 2 * t) end

local function Duration()
    if S.Get("present.motion") == false then return 0 end
    if R.Enabled and R:Enabled("arrivalReducedMotion") then return 0 end
    return Fa.DURATION
end

local function Write(e, a)
    guard = true
    local ok = pcall(e.frame.SetAlpha, e.frame, a)
    guard = false
    if ok then e.set = a; Fa.steps = Fa.steps + 1 else F.Note("fade-refused", e.name) end
    return ok
end

local function Hovered(frame)
    if type(frame.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and F.Readable(over) == true
end

-- What a handled frame should show now.
local function Want(e)
    if revealed or e.hovered then return e.from end
    return math.min(e.from, Alpha())
end

---------------------------------------------------------------------------
-- The owner's writes (the post-hook)
---------------------------------------------------------------------------
local function OnOwnerAlpha(frame, a)
    if guard or state == "idle" then return end
    local e = byFrame[frame]
    if not e or e.done then return end
    a = F.Num(a)
    if not a then return end
    e.from = a
    e.ownerWrites = e.ownerWrites + 1
    local now = F.Clock()
    if now - e.window > Fa.CONTEST_WINDOW then e.window, e.burst = now, 0 end
    e.burst = e.burst + 1
    if e.contested then e.set = a return end
    if e.burst > Fa.CONTEST then
        e.contested, e.to, e.set = true, nil, a
        F.Note("fade-contested", e.name)
        return
    end
    if state == "restoring" then
        -- the owner has the last word on the way back
        e.to, e.set, e.done = nil, a, true
        return
    end
    if not revealed and Hovered(frame) then e.hovered = true end
    local want = Want(e)
    if a <= want + 0.001 then
        e.set = a
        if e.to then e.to = math.min(e.to, a) end
        return
    end
    -- cover: what was showing stays showing (a fade in progress carries on from where it was)
    Fa.covered = Fa.covered + 1
    Write(e, e.to and e.set or want)
end

local function Hook(frame)
    if hooked[frame] or not hooksecurefunc then return hooked[frame] == true end
    local ok = pcall(hooksecurefunc, frame, "SetAlpha", OnOwnerAlpha)
    hooked[frame] = ok and true or false
    return ok
end

---------------------------------------------------------------------------
-- Moving alphas
---------------------------------------------------------------------------
local function Step()
    local now = F.Clock()
    local busy = false
    for _, e in ipairs(entries) do
        if e.to ~= nil and not e.contested and not e.done then
            if not e.hooked and not Near(e.frame:GetAlpha(), e.set) then
                -- no hook on this frame: an owner's change is only seen here, and it wins
                e.from, e.contested, e.to = e.frame:GetAlpha(), true, nil
            else
                local d = e.duration or 0
                local t = d > 0 and math.min(1, (now - e.start) / d) or 1
                Write(e, e.origin + (e.to - e.origin) * Smooth(t))
                if t >= 1 then e.to = nil else busy = true end
            end
        end
    end
    return busy
end

local function Finished()
    if state == "restoring" and not moving then
        state = "idle"
        for _, e in ipairs(entries) do e.done = true end
        byFrame = {}
    end
end

local function Drive()
    if Step() then
        if not moving then
            moving = true
            if not driver and CreateFrame then driver = CreateFrame("Frame") end
            if driver then
                driver:SetScript("OnUpdate", function()
                    if not Step() then moving = false; driver:SetScript("OnUpdate", nil); Finished() end
                end)
            end
        end
    else
        if moving and driver then driver:SetScript("OnUpdate", nil) end
        moving = false
        Finished()
    end
end

-- Moves the entries chosen by `which` (all when nil) towards target(e). instant: in one step.
local function Move(target, instant, which)
    local d = instant and 0 or Duration()
    local now = F.Clock()
    for _, e in ipairs(entries) do
        if not e.contested and not e.done and (not which or which(e)) then
            local to = target(e)
            if not Near(to, e.set) or e.to then e.origin, e.to, e.start, e.duration = e.set, to, now, d end
        end
    end
    Drive()
end

---------------------------------------------------------------------------
-- What is wanted
---------------------------------------------------------------------------
Fa.SWITCHES = { "bars", "units", "minimap", "panels", "meters", "twichui" }
local function Groups()
    local g = {}
    for _, group in ipairs(Fa.SWITCHES) do g[group] = S.Get("fade." .. group) ~= false and S.Get("fade." .. group) and true or false end
    return g
end

-- The targets wanted now: { name, group, owner, label, frame? }.
function Fa.Wanted()
    local out, seen = {}, {}
    local function Add(t) if not seen[t.name] then seen[t.name] = true; out[#out + 1] = t end end
    local g = Groups()
    for _, group in ipairs({ "bars", "units", "minimap", "panels" }) do
        if g[group] then for _, n in ipairs(Fa.GROUPS[group]) do Add({ name = n, group = group, owner = "game" }) end end
    end
    if g.meters then
        for _, n in ipairs(Fa.METERS) do Add({ name = n, group = "meters", owner = "addon", optional = true }) end
    end
    if g.twichui then
        for _, t in ipairs(Fa.TWICHUI) do
            Add({ name = t.name, group = "twichui", owner = "TwichUI", resolve = t.resolve, optional = true,
                label = t.resolve and "Camping bar" or "Sleeping bag bar" })
        end
    end
    if S.Get("fade.ellesmere") ~= false and F.Ellesmere then
        for _, t in ipairs(F.Ellesmere.Targets(g)) do
            Add({ name = t.name, group = t.group, owner = "EllesmereUI", label = t.label, role = t.role, resolve = t.resolve,
                optional = t.optional })
        end
    end
    local extra = S.Get("fade.extra")
    if type(extra) == "table" then for _, n in ipairs(extra) do Add({ name = n, group = "extra", owner = "added" }) end end
    return out
end
-- compatibility: the names alone
function Fa.Names()
    local names = {}
    for i, t in ipairs(Fa.Wanted()) do names[i] = t.name end
    return names
end

-- Why a name can't be faded, or nil: "missing", "never", "forbidden", "no-alpha".
function Fa.Why(name, frame)
    if Fa.NEVER[name] or (F.Ellesmere and F.Ellesmere.NEVER[name]) then return "never" end
    if Fa.IsChatName(name) then return "chat" end
    frame = frame or rawget(_G, name)
    if frame == nil then return "missing" end
    if AboveChat(frame) then return "chat" end
    if type(frame) ~= "table" or frame == rawget(_G, "UIParent") then return "never" end
    if type(frame.GetAlpha) ~= "function" or type(frame.SetAlpha) ~= "function" then return "no-alpha" end
    if frame.IsForbidden and frame:IsForbidden() then return "forbidden" end
    return nil
end

-- Starts handling one frame (t: a Wanted entry or a model). Returns the entry or nil.
local function Lookup(t) return t.resolve and t.resolve() or rawget(_G, t.name) end

local function Add(t, frame)
    frame = frame or Lookup(t)
    local why = Fa.Why(t.name or "", frame)
    if why then
        if why ~= "missing" or not (t.owner == "game" or t.optional) then skipped[#skipped + 1] = { name = t.name, why = why, owner = t.owner } end
        return nil
    end
    if byFrame[frame] then return byFrame[frame] end
    local a = F.Num(frame:GetAlpha())
    if not a then skipped[#skipped + 1] = { name = t.name, why = "unreadable", owner = t.owner } return nil end
    local e = { frame = frame, name = t.name, group = t.group, owner = t.owner, label = t.label, role = t.role,
        kind = t.kind or "frame", resolve = t.resolve, from = a, set = a, ownerWrites = 0, window = F.Clock(), burst = 0 }
    e.hooked = Hook(frame)
    entries[#entries + 1] = e
    byFrame[frame] = e
    return e
end

local function AddModels()
    if S.Get("fade.ellesmere") == false or not S.Get("fade.units") or not F.Ellesmere then return 0 end
    local n = 0
    for i, m in ipairs(F.Ellesmere.Models()) do
        if not byFrame[m] and Add({ name = "EllesmereUI portrait " .. i, group = "units", owner = "EllesmereUI", kind = "model",
            label = "3D portrait" }, m) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Upkeep while faded (once a second)
---------------------------------------------------------------------------
local function Tick()
    if state ~= "faded" then return end
    ticks = ticks + 1
    local pt = R.Perf.on and R.Perf.Start("fishing.fade")
    -- hovered frames fade again once the pointer has left
    for _, e in ipairs(entries) do
        if e.hovered and not e.done and not Hovered(e.frame) then
            e.hovered = false
            if not revealed then Move(Want, false, function(x) return x == e end) end
        end
    end
    -- rebuilt under the same name: the old frame back to its owner's preference, the new one handled
    for _, e in ipairs(entries) do
        if e.kind == "frame" and not e.done and Lookup(e) ~= e.frame then
            if not e.contested then Write(e, e.from) end
            e.done, e.stale = true, true
            byFrame[e.frame] = nil
        end
    end
    -- frames that appeared since (or were rebuilt), and EllesmereUI's portraits every fifth pass
    local added = false
    for _, t in ipairs(Fa.Wanted()) do
        local f = Lookup(t)
        if f ~= nil and not byFrame[f] and not Fa.Why(t.name, f) then
            if Add(t, f) then added = true end
        end
    end
    if ticks % 5 == 0 and AddModels() > 0 then added = true end
    if added then Move(Want) end
    if pt then R.Perf.Stop(pt) end
end

local function StartTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticks = 0
    ticker = C_Timer.NewTicker(Fa.TICK, Tick)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

---------------------------------------------------------------------------
-- Fading and putting back
---------------------------------------------------------------------------
-- Fades what is wanted. Returns the number of frames handled.
function Fa.Apply(instant)
    if state == "faded" then return #entries end
    -- a fade back still moving is finished first, so each frame's alpha is read as its owner left it
    if moving then Fa.Finish() end
    if state == "restoring" then state = "idle" end
    entries, byFrame, skipped = {}, {}, {}
    for _, t in ipairs(Fa.Wanted()) do Add(t) end
    AddModels()
    state, revealed = "faded", false
    if S.Get("fade.minimap") and F.Conceal then F.Conceal.On() end
    if S.Get("fade.notices") and R.QuietScreen and R.QuietScreen.Hold then R.QuietScreen.Hold(Fa.QUIET_OWNER, true) end
    Move(Want, instant)
    StartTicker()
    return #entries
end

-- Everything back to its owner's latest preference. force: back regardless, contested frames too (the player's own
-- recovery). instant: no fade. Returns the number of frames put back.
function Fa.Restore(instant, force)
    if R.QuietScreen and R.QuietScreen.Hold then R.QuietScreen.Hold(Fa.QUIET_OWNER, false) end
    StopTicker()
    if F.Conceal then F.Conceal.Off(force) end
    if state == "idle" and not force then return 0 end
    local result = { restored = 0, owner = 0, contested = 0, stale = 0, forced = force and true or false, at = F.Now() }
    if force then
        for _, e in ipairs(entries) do
            if not e.stale and (Lookup(e) == e.frame or e.kind == "model") then
                e.done, e.contested, e.to = false, false, nil
                if not Near(e.frame:GetAlpha(), e.from) then Write(e, e.from) end
            end
        end
    end
    state, revealed = "restoring", false
    for _, e in ipairs(entries) do
        e.hovered = false
        if e.stale then result.stale = result.stale + 1
        elseif e.contested then result.contested = result.contested + 1
        elseif e.ownerWrites > 0 then result.owner = result.owner + 1 end
        if not e.contested and not e.stale then result.restored = result.restored + 1 end
    end
    Move(function(e) return e.from end, instant or force)
    Fa.last = result
    return result.restored
end

-- The player looks at the interface for a moment (held key, or /tui fish reveal): everything comes back to its owner's
-- preference, and fades again when they let go.
function Fa.Reveal(on)
    if state ~= "faded" then return false end
    on = on and true or false
    if on == revealed then return true end
    revealed = on
    if F.Conceal then F.Conceal.Reveal(on) end
    if R.QuietScreen and R.QuietScreen.Hold and S.Get("fade.notices") then R.QuietScreen.Hold(Fa.QUIET_OWNER, not on) end
    Move(Want)
    return true
end

function Fa.Faded() return state == "faded" end
function Fa.Revealed() return revealed end
function Fa.Moving() return moving end
function Fa.State() return state end

---------------------------------------------------------------------------
-- What happened, for people (the settings page, /tui fish fade) and for diagnostics
---------------------------------------------------------------------------
function Fa.Status()
    local kept, list, contested, hovered, ownerWrites = 0, {}, 0, 0, 0
    for _, e in ipairs(entries) do
        if e.contested then contested = contested + 1 end
        if e.hovered then hovered = hovered + 1 end
        ownerWrites = ownerWrites + e.ownerWrites
        if e.contested or e.stale then kept = kept + 1 end
        list[#list + 1] = e.name
    end
    return { faded = state == "faded", state = state, revealed = revealed, frames = #entries, kept = kept, names = list,
        moving = moving, contested = contested, hovered = hovered, ownerWrites = ownerWrites, covered = Fa.covered,
        skipped = #skipped, ticking = ticker ~= nil,
        quiet = R.QuietScreen and R.QuietScreen.Holding and R.QuietScreen.Holding(Fa.QUIET_OWNER) or false }
end

local WHY = { chat = "chat is never faded", missing = "not there", never = "never touched (safety)", forbidden = "forbidden by the game",
    ["no-alpha"] = "takes no alpha", unreadable = "alpha unreadable" }
Fa.WHY = WHY

-- One line per frame handled or skipped, plus the last fade back. Plain words, no item or player data.
function Fa.Report()
    local lines = {}
    for _, e in ipairs(entries) do
        local what
        if e.stale then what = "rebuilt by its owner: the old frame was put back"
        elseif e.contested then what = "left to " .. (e.owner == "game" and "the game" or e.owner) .. " (it kept changing it)"
        elseif e.hovered then what = "shown while your pointer is on it"
        elseif e.done then what = "back at " .. ("%.2f"):format(e.from)
        else what = ("faded (its own alpha %.2f%s)"):format(e.from, e.ownerWrites > 0 and (", changed by its owner " .. e.ownerWrites .. "x") or "") end
        lines[#lines + 1] = ("%s [%s, %s]: %s"):format(e.label or e.name, e.group, e.owner, what)
    end
    for _, s in ipairs(skipped) do
        lines[#lines + 1] = ("%s [%s]: skipped, %s"):format(s.name, s.owner or "?", WHY[s.why] or s.why)
    end
    if F.Conceal then
        local c = F.Conceal.State()
        if c.concealed then
            lines[#lines + 1] = "Minimap: hidden completely" .. (c.revealed and " (shown while you reveal)" or "")
        elseif c.waiting then lines[#lines + 1] = "Minimap: coming back when combat ends" end
    end
    local l = Fa.last
    if l then
        lines[#lines + 1] = ("last time back: %d put back, %d changed by their owner meanwhile, %d left to their owner, %d rebuilt%s")
            :format(l.restored, l.owner, l.contested, l.stale, l.forced and " (forced)" or "")
    end
    return lines
end

-- What can be faded now, by group, without fading anything: { [group] = { game, ellesmere, added } }.
function Fa.Inventory()
    local inv = {}
    for _, t in ipairs(Fa.Wanted()) do
        local g = inv[t.group] or { game = 0, EllesmereUI = 0, added = 0, missing = 0 }
        inv[t.group] = g
        if Fa.Why(t.name, t.resolve and t.resolve() or nil) then g.missing = g.missing + 1 else g[t.owner] = (g[t.owner] or 0) + 1 end
    end
    return inv
end

-- Test support: finishes any fade at once.
function Fa.Finish()
    for _, e in ipairs(entries) do if e.to ~= nil then e.duration = 0 end end
    Step()
    if driver then driver:SetScript("OnUpdate", nil) end
    moving = false
    Finished()
end
function Fa.Entries() return entries end
