-- TwichUI: class resource bars, the controller
-- Ties the pieces together: which resources apply to the player now (Resources.lua), the style each is drawn with
-- (Config.lua), the bars that draw them (Bar.lua), the effects on them (Effects.lua), and the rules for when to show
-- them. It owns the events, the groups the bars sit in, positioning mode and the settings preview.
--
-- Lifecycle (docs/class-bars.md has the same in a table):
--   * Off (the default): no frame, no event, no timer. Turning the switch on calls Refresh; off calls it again and
--     everything is hidden, unregistered and stopped.
--   * On, before the world exists (login): only PLAYER_ENTERING_WORLD is listened for. Entering the world (login,
--     /reload, a zone, an instance) does a full Refresh.
--   * Refresh: sense the player (class, the power the client reports, state flags), choose each slot's provider,
--     read it, resolve its style, draw, lay the bars out, decide who is shown, and register exactly the events that
--     the class's providers and the current settings need (unit events are filtered to "player" by the client).
--   * A resource event: read the active providers (a handful of API calls), and touch a bar only when its numbers
--     changed. A bar redraws only what changed; text is set only when the words change.
--   * A setting change: Config.Invalidate tells this file once; it does a Refresh (quiet: effects do not play).
--
-- Why its own event frame instead of the shared bus (R:On): the shared frame cannot filter a unit event to the
-- player; the client filters RegisterUnitEvent, so power events for other units never reach Lua at all.
--
-- Nothing here is protected: the bars are plain frames that take no clicks (except the move handle in positioning
-- mode), so changing, moving and showing them is legal in combat. Positioning ends when combat starts.
--
-- Preview: a sample of the real bars (the same frames, styles and effects) with made-up numbers, for settings.
-- The sample is separate from the real values, which are kept up to date underneath, so ending it shows the truth at
-- once. It ends on its own when the settings window closes, when combat starts or the feature is switched off.

local R = TwichUI
local CB = R.ClassBars
local CBR = R.ClassBarResources
local BF = R.ClassBarFrame
local FX = R.ClassBarEffects
local A = R.ClassBarAnim

local WHITE = [[Interface\Buttons\WHITE8x8]]
local SLOTS = CBR.SLOTS
local PAD = 6   -- the move handle's margin around the bars

local ctx = CBR.Context()
local flags = { combat = false, dead = false, mounted = false, vehicle = false }
local recs = {}            -- [slot] = { slot, provider, bar, style, key, ok, cur, max, slotOn, visible, pv }
local groups = {}          -- [name] = { frame, handle, label }
local badge                -- the "Preview" tag
local evf                  -- the event frame, made when first needed
local registered, desired = {}, {}
local wanted = {}          -- power tokens whose events matter now
local running = false      -- on, in the world and drawing
local preview = { active = false, position = false, level = 70, points = 3 }
local lastEvents = 0

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Fault(err) R.Fault("class bars", err) end

-- The world is there once the game said so; our own event is also taken as the word, so the order in which two
-- frames hear PLAYER_ENTERING_WORLD does not matter.
local worldSeen = false
local function InWorld() return worldSeen or (R.Life ~= nil and R.Life.InWorld()) end

-- A restricted (secret) answer is "no": it is never tested for truth.
local function Yes(v) return CBR.Plain(v) == true end

local function SenseFlags()
    flags.combat = Yes(UnitAffectingCombat("player"))
    flags.dead = Yes(UnitIsDeadOrGhost("player"))
    flags.mounted = IsMounted ~= nil and Yes(IsMounted())
    flags.vehicle = UnitHasVehicleUI ~= nil and Yes(UnitHasVehicleUI("player"))
end

local function Rec(slot)
    local rec = recs[slot]
    if not rec then
        rec = { slot = slot, ok = false, visible = false, pv = { slot = slot, ok = true } }
        recs[slot] = rec
    end
    return rec
end

-- The numbers a slot shows now: the sample while previewing, else the provider's state.
local function View(rec)
    if preview.active then return rec.pv end
    return rec.provider and rec.provider.state or nil
end

local function Wants(rec)
    if not rec.slotOn then return false end
    if preview.active then return true end
    if not rec.provider or not rec.ok then return false end
    if flags.dead and CB.Get("hideDead") then return false end
    if flags.mounted and CB.Get("hideMounted") then return false end
    if flags.vehicle and CB.Get("hideVehicle") then return false end
    local show = rec.style and rec.style.show or CB.Get("show")
    if show == "never" then return false end
    if show == "always" or show == "fade" then return true end   -- fade: always there, its opacity follows combat
    if show == "combat" then return flags.combat end
    if flags.combat then return true end                           -- "active": in combat, or
    return not CBR.AtRest(rec.key, rec.cur, rec.max)               -- not at the resource's own resting value
end

---------------------------------------------------------------------------
-- Frames: two groups (the main bars, and the secondary ones when they have a place of their own), made when first needed
---------------------------------------------------------------------------
local function MakeGroup(name)
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("MEDIUM")
    g:SetSize(10, 10)
    g:SetClampedToScreen(true)
    g:SetMovable(true)
    if g.SetDontSavePosition then g:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    g:Hide()

    -- the move handle: takes the mouse only in positioning mode
    local h = CreateFrame("Frame", nil, g, "BackdropTemplate")
    h:SetFrameStrata("HIGH")
    h:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    h:SetBackdropColor(0.18, 0.33, 0.33, 0.55)
    h:SetBackdropBorderColor(0.58, 0.78, 0.76, 1)
    h:RegisterForDrag("LeftButton")
    h:Hide()
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", h, "TOP", 0, 3)
    label:SetText(name == "main" and "Class resource bars: drag to move, right-click to finish"
        or "Secondary bars: drag to move, right-click to finish")
    h.label = label
    h:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        g:StartMoving()
    end)
    h:SetScript("OnDragStop", function()
        g:StopMovingOrSizing()
        local cx, cy = g:GetCenter()
        local px, py = UIParent:GetCenter()
        if cx and px then
            local x, y = CB.ToOffset(cx, cy, g:GetEffectiveScale(), px, py, UIParent:GetEffectiveScale())
            if x then CB.SetPosition(name, math.floor(x + 0.5), math.floor(y + 0.5)) end
        end
        CB.PlaceGroups()   -- StartMoving re-anchored the frame: put it back on the saved place
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then CB.PositionEnd() end
    end)
    groups[name] = { frame = g, handle = h, name = name }
    return groups[name]
end

local function EnsureFrames()
    if groups.main then return end
    MakeGroup("main")
    MakeGroup("aux")
    for _, slot in ipairs(SLOTS) do
        local rec = Rec(slot)
        rec.bar = BF.New(groups.main.frame, slot)
    end
    local b = CreateFrame("Frame", nil, groups.main.frame, "BackdropTemplate")
    b:SetFrameStrata("HIGH")
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.07, 0.07, 0.07, 0.85)
    b:SetBackdropBorderColor(0.58, 0.78, 0.76, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText("Preview: sample values, not your resources")
    b:SetSize(fs:GetStringWidth() + 12, 16)
    b:Hide()
    badge = b
end

-- Puts both groups where they are saved, kept on the screen, at the chosen scale.
function CB.PlaceGroups()
    if not groups.main then return end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = CB.Get("scale") / 100
    local alpha = CB.Get("opacity") / 100
    for name, g in pairs(groups) do
        local x, y = CB.Position(name)
        x, y = CB.ClampPosition(x, y, sw, sh)
        local ox, oy = CB.FromOffset(x, y, scale)
        g.frame:SetScale(scale)
        g.frame:SetAlpha(alpha)
        g.frame:ClearAllPoints()
        g.frame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
    end
end

---------------------------------------------------------------------------
-- Layout: where each shown bar sits in its group
---------------------------------------------------------------------------
local MAIN_ORDER_ALL, AUX_ORDER, NONE = { "primary", "secondary", "tertiary" }, { "secondary", "tertiary" }, {}
local MAIN_ORDER_ONLY = { "primary" }

-- Chains one group's bars outward from its anchor bar. Returns whether anything is shown.
local function LayoutGroup(g, members, down)
    local gap = CB.Get("gap")
    local anchor
    for _, slot in ipairs(members) do
        local rec = recs[slot]
        if rec.slotOn and rec.style then anchor = rec break end
    end
    if not anchor then return false end
    local f = g.frame
    f:SetSize(anchor.style.width, anchor.style.height)
    local prev = anchor.bar.frame
    local top, bottom, width = anchor.style.height / 2, -anchor.style.height / 2, anchor.style.width
    local any = false
    for _, slot in ipairs(members) do
        local rec = recs[slot]
        if rec.bar and rec.style then
            local bf = rec.bar.frame
            if bf:GetParent() ~= f then bf:SetParent(f) end
            if rec == anchor then
                bf:ClearAllPoints()
                bf:SetPoint("CENTER", f, "CENTER", 0, 0)
                if rec.visible then any = true end
            elseif rec.visible then
                any = true
                bf:ClearAllPoints()
                if down then
                    bf:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
                    bottom = bottom - gap - rec.style.height
                else
                    bf:SetPoint("BOTTOM", prev, "TOP", 0, gap)
                    top = top + gap + rec.style.height
                end
                prev = bf
                if rec.style.width > width then width = rec.style.width end
            end
        end
    end
    -- the move handle covers all of it
    local h = g.handle
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "CENTER", -width / 2 - PAD, top + PAD)
    h:SetSize(width + 2 * PAD, top - bottom + 2 * PAD)
    return any
end

local function Layout()
    local separate = CB.Get("placement") == "separate"
    local mainAny = LayoutGroup(groups.main, separate and MAIN_ORDER_ONLY or MAIN_ORDER_ALL, CB.Get("placement") ~= "above")
    local auxAny = false
    if separate then auxAny = LayoutGroup(groups.aux, AUX_ORDER, true) end
    CB.PlaceGroups()
    groups.main.frame:SetShown(mainAny or (preview.position and recs.primary.slotOn))
    groups.aux.frame:SetShown(separate and (auxAny or false))
    local handles = preview.position
    groups.main.handle:SetShown(handles and groups.main.frame:IsShown())
    groups.main.handle:EnableMouse(handles)
    groups.aux.handle:SetShown(handles and groups.aux.frame:IsShown())
    groups.aux.handle:EnableMouse(handles)
    if badge then
        badge:ClearAllPoints()
        badge:SetPoint("BOTTOM", groups.main.handle, "TOP", 0, preview.position and 18 or 4)
        badge:SetShown(preview.active and groups.main.frame:IsShown())
    end
end

-- Fade with combat: a bar whose rule is "fade" is always there, and its own opacity eases up to full in combat and down
-- to the out-of-combat opacity (Config "fadeIdle") out of it. It is the bar's alpha, on top of the group's overall
-- opacity, so the two settings stay separate. The easing runs on the shared driver only while it is moving.
local FADE_TIME = 0.35   -- seconds for the whole way

local function FadeTarget(rec)
    if preview.active or not (rec.style and rec.style.show == "fade") or flags.combat then return 1 end
    return CB.Get("fadeIdle") / 100
end

local function FadeStep(self, dt)
    local rec = self.rec
    local target = rec.fadeTarget
    local a = rec.fadeAlpha
    local step = dt / FADE_TIME
    if a < target then a = math.min(target, a + step) else a = math.max(target, a - step) end
    rec.fadeAlpha = a
    rec.bar.frame:SetAlpha(a)
    return a == target
end

-- animate: ease (a combat change); otherwise the new opacity is taken at once (a start, a setting, a bar just shown).
local function ApplyFade(rec, animate)
    local bar = rec.bar
    if not bar then return end
    local target = FadeTarget(rec)
    rec.fadeObj = rec.fadeObj or { rec = rec, Step = FadeStep }
    if target == rec.fadeTarget and (rec.fadeObj.animating or rec.fadeAlpha == target) then return end   -- nothing new; leave a fade under way alone
    rec.fadeTarget = target
    if animate and rec.fadeAlpha and bar:IsShown() and rec.fadeAlpha ~= target and A.Add(rec.fadeObj) then return end
    A.Remove(rec.fadeObj)
    rec.fadeAlpha = target
    bar.frame:SetAlpha(target)
end

-- Decides who is shown; lays out again when that changed. animate: a combat change, so fades ease.
local function Visibility(force, animate)
    local changed = force
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        local want = Wants(rec)
        if want ~= rec.visible then
            rec.visible = want
            changed = true
        end
    end
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        if rec.bar then
            local shown = rec.visible and rec.style ~= nil
            if rec.bar:IsShown() ~= shown then
                if shown then ApplyFade(rec, false) end        -- appears at its right opacity
                rec.bar:SetShown(shown)
                if not shown then
                    A.Remove(rec.fadeObj or rec)
                    if FX then FX.Stop(rec.bar) end
                end
            elseif shown then
                ApplyFade(rec, animate)
            end
        end
    end
    if changed then Layout() end
end

---------------------------------------------------------------------------
-- Reading and drawing
---------------------------------------------------------------------------

-- Draws the numbers a slot shows. snap: no easing (a start, not a change).
local function Push(rec, snap)
    local view = View(rec)
    if not (view and rec.bar and rec.style) then return end
    if preview.active or view.ok then rec.bar:SetState(view.cur, view.max, snap) end
end

-- Lets the effects see a slot's numbers, when it is shown. quiet: a start, not a transition.
local function Effects(rec, quiet)
    local view = View(rec)
    if not (FX and view and rec.bar and rec.style and rec.visible) then return end
    if FX.Enabled() and (preview.active or view.ok) then FX.Update(rec.bar, view, ctx, quiet) end
end

-- Each slot's style from the shared settings and the player's overrides, drawn on its bar.
local function Restyle()
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        rec.slotOn = CB.Get(slot .. "On")
        local view = View(rec)
        if view and view.key and rec.bar then
            rec.style = CB.Style(slot, view, ctx.class)
            rec.bar:Configure(rec.style)
        else
            rec.style = nil
        end
    end
end

-- Sample numbers for the slots, from the live maximum where there is one.
local function PreviewFill()
    local primary, tertiary, secondary = recs.primary, recs.tertiary, recs.secondary
    local level = preview.level
    local function Continuous(rec, key)
        local pv = rec.pv
        pv.key, pv.kind, pv.token = key, "continuous", key
        pv.max = (rec.ok and rec.max and rec.max > 0) and rec.max or 100
        pv.cur = math.floor(pv.max * level / 100 + 0.5)
        pv.ok = true
    end
    Continuous(primary, ctx.token or "MANA")
    Continuous(tertiary, "MANA")
    local pv = secondary.pv
    pv.key, pv.kind, pv.token, pv.max, pv.cur, pv.ok = "COMBO_POINTS", "segmented", "COMBO_POINTS", 5, preview.points, true
end

local function ResetRec(rec)
    if rec.bar then
        rec.bar:Clear()
        if FX then FX.Reset(rec.bar) end
    end
    rec.ok, rec.cur, rec.max, rec.key = false, nil, nil, nil
end

-- Reads every active provider into its slot. Returns true when a slot's resource itself changed.
local function ReadAll()
    local switched = false
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        local p = rec.provider
        if p then
            local s = CBR.Read(p, ctx)
            if rec.key ~= s.key then
                ResetRec(rec)
                rec.key = s.key
                switched = true
            end
            rec.ok, rec.cur, rec.max = s.ok, s.cur, s.max
        end
    end
    return switched
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local HANDLERS = {}

local function Want(event, unit)
    desired[event] = unit and "unit" or "global"
end

local refused = 0   -- events the client would not register (reported; the others still work)

local function ApplyEvents()
    for event in pairs(registered) do
        if not desired[event] then
            evf:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event, kind in pairs(desired) do
        if not registered[event] then
            local ok
            if kind == "unit" then ok = pcall(evf.RegisterUnitEvent, evf, event, "player") else ok = pcall(evf.RegisterEvent, evf, event) end
            if ok then registered[event] = kind else refused = refused + 1 end
        end
    end
end

local function WantedEvents()
    for event in pairs(desired) do desired[event] = nil end
    Want("PLAYER_ENTERING_WORLD", false)
    if not running then return end
    for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do Want(e, false) end
    if CB.Get("hideMounted") then Want("PLAYER_MOUNT_DISPLAY_CHANGED", false) end
    if CB.Get("hideVehicle") then
        Want("UNIT_ENTERED_VEHICLE", true)
        Want("UNIT_EXITED_VEHICLE", true)
        Want("PLAYER_GAINS_VEHICLE_DATA", false)
        Want("PLAYER_LOSES_VEHICLE_DATA", false)
    end
    local unit, global = CBR.EventsFor(ctx.class)
    for _, e in ipairs(unit) do Want(e, true) end
    for _, e in ipairs(global) do Want(e, false) end
end

-- The power tokens that matter: those of the resources shown now.
local function WantedTokens()
    for k in pairs(wanted) do wanted[k] = nil end
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        if rec.provider and rec.key then wanted[rec.key] = true end
    end
end

-- A power value changed: read the active providers and touch only what changed.
local changedSlots = {}
local function Update(quiet)
    if not running then return end
    local n = 0
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        local p = rec.provider
        if p then
            local s = CBR.Read(p, ctx)
            if s.ok ~= rec.ok or s.cur ~= rec.cur or s.max ~= rec.max then
                rec.ok, rec.cur, rec.max = s.ok, s.cur, s.max
                if not preview.active then
                    Push(rec, false)
                    n = n + 1
                    changedSlots[n] = rec
                end
            end
        end
    end
    if n > 0 then
        Visibility(false)
        for i = 1, n do
            Effects(changedSlots[i], quiet)
            changedSlots[i] = nil
        end
    end
end

local Refresh   -- below

HANDLERS.UNIT_POWER_FREQUENT = function(_, token)
    lastEvents = lastEvents + 1
    if token and not wanted[token] then return end
    Update(false)
end
HANDLERS.UNIT_POWER_UPDATE = HANDLERS.UNIT_POWER_FREQUENT
HANDLERS.UNIT_MAXPOWER = function() Update(false) end
HANDLERS.UNIT_DISPLAYPOWER = function() Refresh(true) end              -- a form change: the resources may be others
HANDLERS.PLAYER_TARGET_CHANGED = function() Update(true) end           -- combo points belong to the target: not a transition
HANDLERS.COMBO_TARGET_CHANGED = function() Update(true) end
HANDLERS.PLAYER_ENTERING_WORLD = function()
    worldSeen = true
    Refresh(true)
end
HANDLERS.UI_SCALE_CHANGED = function() CB.Invalidate() end            -- borders are whole pixels: redraw them
HANDLERS.DISPLAY_SIZE_CHANGED = HANDLERS.UI_SCALE_CHANGED

local function StateChanged(quiet)
    SenseFlags()
    Visibility(false)
    if quiet then Update(true) end
end
HANDLERS.PLAYER_DEAD = function() StateChanged(false) end
HANDLERS.PLAYER_ALIVE = function() StateChanged(true) end
HANDLERS.PLAYER_UNGHOST = function() StateChanged(true) end
HANDLERS.PLAYER_MOUNT_DISPLAY_CHANGED = function() StateChanged(false) end
HANDLERS.UNIT_ENTERED_VEHICLE = function() StateChanged(false) end
HANDLERS.UNIT_EXITED_VEHICLE = function() StateChanged(false) end
HANDLERS.PLAYER_GAINS_VEHICLE_DATA = function() StateChanged(false) end
HANDLERS.PLAYER_LOSES_VEHICLE_DATA = function() StateChanged(false) end
HANDLERS.PLAYER_REGEN_DISABLED = function()
    flags.combat = true
    if preview.active then CB.PreviewStop() end     -- the real display takes over
    Visibility(false, true)
end
HANDLERS.PLAYER_REGEN_ENABLED = function()
    flags.combat = false
    Visibility(false, true)
end

local function OnEvent(_, event, ...)
    local h = HANDLERS[event]
    if not h then return end
    local ok, err = pcall(h, ...)
    if not ok then Fault(err) end
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe to call at any time.
---------------------------------------------------------------------------
local function Teardown()
    running = false
    preview.active, preview.position = false, false
    if evf then
        for k in pairs(desired) do desired[k] = nil end
        ApplyEvents()
    end
    A.Clear()
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        if rec and rec.bar then
            rec.bar:Clear()
            rec.bar:SetShown(false)
            rec.bar.frame:SetAlpha(1)
            rec.fadeAlpha, rec.fadeTarget = nil, nil
            rec.provider, rec.visible = nil, false
        end
    end
    if FX then FX.StopAll() end
    for _, g in pairs(groups) do
        g.handle:EnableMouse(false)
        g.handle:Hide()
        g.frame:Hide()
    end
    if badge then badge:Hide() end
end

-- quiet: effects only note the numbers (a start, not a transition).
function Refresh(quiet)
    if not R:Enabled("classBars") then
        if evf or running then Teardown() end
        return
    end
    EnsureFrames()
    if not evf then
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", OnEvent)
    end
    if not InWorld() then   -- login: nothing can be read before the world exists
        running = false
        WantedEvents()
        ApplyEvents()
        return
    end
    running = true
    CBR.Sense()
    SenseFlags()
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        local p = CBR.Resolve(slot, ctx)
        if p ~= rec.provider then
            ResetRec(rec)
            rec.provider = p
        end
    end
    ReadAll()
    if preview.active then PreviewFill() end
    WantedEvents()
    ApplyEvents()
    WantedTokens()
    Restyle()
    for _, slot in ipairs(SLOTS) do Push(recs[slot], true) end
    Visibility(true)
    if FX and not FX.Enabled() then FX.StopAll() end
    for _, slot in ipairs(SLOTS) do Effects(recs[slot], true) end
end

function CB.Refresh() Refresh(true) end

---------------------------------------------------------------------------
-- Positioning mode
---------------------------------------------------------------------------
function CB.PositioningActive() return preview.position end

-- Shows the bars with sample values and a handle to drag. Not allowed in combat.
function CB.PositionStart()
    if not running or InCombatLockdown() then return false, "combat" end
    preview.position = true
    CB.PreviewStart(true)
    Layout()
    return true
end

function CB.PositionEnd()
    if not preview.position then return end
    preview.position = false
    if running then Layout() end
end

-- The saved places forgotten (both groups when group is nil): back to the defaults.
function CB.ResetPosition(group)
    if group then CB.SetPosition(group, nil, nil)
    else
        CB.SetPosition("main", nil, nil)
        CB.SetPosition("aux", nil, nil)
    end
end

CB.SubscribeMoved(function()
    if groups.main then CB.PlaceGroups() end
end)

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------
function CB.PreviewActive() return preview.active end

function CB.PreviewLevels() return preview.level, preview.points end

-- Shows the sample. keep: leave positioning mode as it is.
function CB.PreviewStart(keep)
    if not running or (InCombatLockdown() and not keep) then return false end
    if not preview.active then
        preview.active = true
        for _, slot in ipairs(SLOTS) do
            local rec = recs[slot]
            if rec.bar then      -- the live fill, text and effects are not carried into the sample
                rec.bar:Clear()
                if FX then FX.Reset(rec.bar) end
            end
        end
        PreviewFill()
        Restyle()
        for _, slot in ipairs(SLOTS) do Push(recs[slot], true) end
        Visibility(true)
        for _, slot in ipairs(SLOTS) do Effects(recs[slot], true) end
    end
    return true
end

-- Ends the sample and shows the real values. Also ends positioning mode (its sample goes with it).
function CB.PreviewStop()
    if not preview.active then return end
    preview.active, preview.position = false, false
    if running then
        for _, slot in ipairs(SLOTS) do ResetRec(recs[slot]) end
        Refresh(true)
    end
end

-- Sample levels: a percentage for the continuous bars, a count for the segmented one. Plays effects that the new
-- numbers cross (a sample transition, so the effects can be seen without a fight).
function CB.PreviewSet(level, points)
    if not preview.active then return false end
    if type(level) == "number" then preview.level = math.max(0, math.min(100, math.floor(level + 0.5))) end
    if type(points) == "number" then preview.points = math.max(0, math.min(CBR.COMBO_CAP, math.floor(points + 0.5))) end
    PreviewFill()
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        if rec.bar and rec.style then
            rec.bar:SetState(rec.pv.cur, rec.pv.max)
            Effects(rec, false)
        end
    end
    return true
end

-- Plays the effects that belong on each shown bar once. Returns how many played, or false and a reason.
function CB.TestEffect()
    if not running then return false, "off" end
    if not (FX and FX.Enabled()) then return false, "effects-off" end
    if not preview.active and not CB.PreviewStart() then return false, "combat" end
    local n = 0
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        if rec.visible and rec.bar and rec.style then n = n + FX.Test(rec.bar, rec.pv, ctx) end
    end
    return n
end

---------------------------------------------------------------------------
-- Status, for settings, /tui diagnostics and the tests: plain values, no tables of ours handed out
---------------------------------------------------------------------------
function CB.Snapshot()
    local out = { running = running, preview = preview.active, positioning = preview.position, events = 0, refused = refused, slots = {} }
    for _ in pairs(registered) do out.events = out.events + 1 end
    for _, slot in ipairs(SLOTS) do
        local rec = recs[slot]
        out.slots[slot] = rec and { provider = rec.provider and rec.provider.id or nil, key = rec.key, shown = rec.visible,
            cur = rec.cur, max = rec.max, ok = rec.ok } or {}
    end
    return out
end

-- Whether a resource is being drawn for a slot (the settings page names it).
function CB.SlotInfo(slot)
    local rec = recs[slot]
    if not rec or not rec.provider then return nil end
    return rec.provider.state.key, rec.provider.state.label, rec.provider.kind
end

function CB.Running() return running end

-- The bar drawing a slot, for the tests and the troubleshooting report (read only: nothing outside draws on it).
function CB.Bar(slot)
    local rec = recs[slot]
    return rec and rec.bar or nil
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
CB.Subscribe(function()
    if R:Enabled("classBars") or evf then Refresh(true) end
end)

R:OnInit(function() Refresh(true) end)
R.Profiles.OnApply("layout", "class-bars", function() Refresh(true) end)
R.OnSettingsClosed(function()
    -- the sample goes away with the settings window; positioning (an explicit, visible mode) is left to its own end
    if preview.active and not preview.position then CB.PreviewStop() end
end)
