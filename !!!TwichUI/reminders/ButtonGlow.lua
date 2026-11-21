-- TwichUI: Reminders, action button glows
-- A reminder can light the action buttons holding a spell the player chose while it shows. This file only draws that:
-- the controller (Controller.lua) decides when a reminder shows, with its delay and minimum, and tells this file which
-- reminders are up (GW.Set). Nothing here reads a condition, an aura or a cooldown, and there is no second rule
-- evaluator: a reminder's glow is exactly its visibility.
--
-- The buttons and the drawing are Action bar glows' (glows/Buttons.lua finds Blizzard's and EllesmereUI's buttons and
-- what each holds, by spell name so every rank and a macro that casts it count; glows/Draw.lua owns the one overlay a
-- button has). Reminders draws as its own owner ("reminders"), so neither feature clears the other's glows and neither
-- needs the other switched on. Of several reminders wanting one button, the first in the list gives its look; a
-- Reminder's look shows over Action bar glows' on the same button (Draw.lua's ranks).
--
-- It only reads and draws: it never casts, uses, picks up or places anything, never changes a button or its action and
-- hooks nothing. A spell that is on no button glows nothing; the reminder's own display and sound go on as usual.
--
--   GW.Set(id, on)          the controller: this reminder shows (on) or no longer does
--   GW.Clear()              the controller: Reminders switched off, nothing shows
--   GW.Prune(present)       reminders that are gone (deleted, another profile) let go of their glows
--   GW.Update(id)           a reminder's glow setting changed, or (nil) anything may have: drawn again
--   GW.SetPreview(id)       Display.lua's on-screen preview: its glow shows as well, whatever the rules say (nil: ends)
--   GW.Buttons(spell)       how many action buttons hold that spell now (the editor's line)
--   GW.Sample(frame, glow)  the editor's sample button shows that look (nil: stops); never an action button
--   GW.Snapshot()           counts for /tui diagnostics and the tests
--
-- Events: only while a glow is wanted (a showing reminder with a glow, or a preview of one), the bar, page, form, macro
-- and spell events that move spells between buttons; a burst is looked at once, SETTLE seconds after the first. When
-- it starts listening it reads the buttons once at once, since nothing may have kept them current meanwhile. No
-- OnUpdate, no polling: the glows are Draw.lua's animation groups.
--
-- The Quiet screen (QuietScreen.lua) holds back a live reminder's glow, as it does the reminder; turning it off brings
-- back the glows of the reminders still showing. A preview is the player asking to see it and ignores it.

local R = TwichUI
local RM = R.Reminders
local Perf = R.Perf
local GW = { renders = 0, maps = 0, events = 0 }
R.ReminderGlow = GW

GW.OWNER = "reminders"
GW.SAMPLE_OWNER = "reminderSample"
local SETTLE = 0.05
local EVENTS = {
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
}

local function BT() return R.BarGlowButtons end
local function Draw() return R.BarGlowDraw end
local function Quiet() local q = R.QuietScreen return q ~= nil and q.On() end
local function Wipe(t) for k in pairs(t) do t[k] = nil end end

local live = {}          -- [id] = true while the controller shows that reminder
local previewId
local styles = {}        -- [id] = { key, style }: the look a reminder's glow is drawn with, made again only when it changes
local desired = {}       -- [button] = style, rebuilt at each drawing
local frame
local listening = false
local pending = false
local gen = 0

-- The look Draw.lua draws, from a reminder's glow (RM.ReadGlow). Size, opacity, speed and thickness are the defaults.
function GW.Style(g)
    return { look = g.look, color = g.color, opacity = 100, size = 100, speed = 100, motion = g.motion, thickness = 2 }
end

local function StyleFor(v)
    local g = v.glow
    local key = g.look .. "|" .. g.color .. "|" .. g.motion
    local c = styles[v.id]
    if c and c.key == key then return c.style end
    c = { key = key, style = GW.Style(g) }
    styles[v.id] = c
    return c.style
end

local function Map()
    local bt = BT()
    if not bt then return end
    bt.Map()
    GW.maps = GW.maps + 1
end

local Render

local function Schedule()
    if pending then return end
    pending = true
    local mine = gen
    C_Timer.After(SETTLE, function()
        if mine ~= gen then return end
        pending = false
        Render()
    end)
end

local function OnEvent()
    GW.events = GW.events + 1
    local bt = BT()
    if bt then bt.Dirty() end
    Schedule()
end

local function Listen(on)
    if on == listening then return end
    listening = on
    if on then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", Perf.Wrap("reminders.glow.event", function() OnEvent() end))
        end
        for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
        Map()   -- nothing may have kept the buttons current while no glow was wanted
    else
        gen, pending = gen + 1, false
        if frame then frame:UnregisterAllEvents() end
    end
end

-- The reminders whose glow should show now, first-ranked first: the preview, then the showing ones in list order.
local function Wanted(out)
    local quiet = Quiet()
    if previewId then
        local v = RM.Get(previewId)
        if v and v.glow.on then out[#out + 1] = v end
    end
    for _, v in ipairs(RM.List()) do
        if live[v.id] and not quiet and v.id ~= previewId and v.glow.on then out[#out + 1] = v end
    end
    return out
end

local wanted = {}
Render = function()
    local bt, D = BT(), Draw()
    if not (bt and D) then return end
    local pt = Perf.on and Perf.Start("reminders.glow")
    GW.renders = GW.renders + 1
    for id in pairs(live) do
        if not RM.Get(id) then live[id] = nil; styles[id] = nil end
    end
    Wipe(wanted)
    Wanted(wanted)
    Listen(#wanted > 0)
    if #wanted > 0 and bt.dirty then Map() end
    Wipe(desired)
    for _, v in ipairs(wanted) do
        local name = bt.SpellName(v.glow.spell)
        if name then
            for _, button in ipairs(bt.ForSpell(name)) do
                if desired[button] == nil then desired[button] = StyleFor(v) end
            end
        end
    end
    D.Sync(GW.OWNER, desired)
    if pt then Perf.Stop(pt) end
end

function GW.Set(id, on)
    if not id then return end
    on = on and true or nil
    if live[id] == on then return end
    live[id] = on
    Render()
end

function GW.Clear()
    Wipe(live)
    Render()
end

function GW.Prune(present)
    local changed = false
    for id in pairs(live) do
        if not present[id] then live[id] = nil; changed = true end
    end
    for id in pairs(styles) do
        if not present[id] then styles[id] = nil end
    end
    if previewId and not present[previewId] then previewId = nil; changed = true end
    if changed then Render() end
end

function GW.Update(id)
    if id == nil or live[id] or previewId == id then Render() end
end

function GW.SetPreview(id)
    if previewId == id then return end
    previewId = id
    Render()
end

-- How many action buttons hold the spell now (any rank, or a macro casting it), or nil when the game has no name for it.
function GW.Buttons(spell)
    local bt = BT()
    if not (bt and RM.ValidSpell(spell)) then return nil end
    if not listening or bt.dirty or bt.generation == 0 then Map() end
    local name = bt.SpellName(spell)
    if not name then return nil end
    return #bt.ForSpell(name)
end

-- The editor's sample button: a frame of the settings window, never an action button.
function GW.Sample(f, g)
    local D = Draw()
    if not (D and f) then return end
    if g then D.Request(GW.SAMPLE_OWNER, f, GW.Style(g)) else D.Release(GW.SAMPLE_OWNER, f) end
end

if R.QuietScreen then
    R.QuietScreen.OnChange(function()
        if next(live) or previewId then Render() end
    end)
end

function GW.Snapshot()
    local n, glowing = 0, 0
    for _ in pairs(live) do n = n + 1 end
    local D = Draw()
    if D then for _ in pairs(D.Owned(GW.OWNER)) do glowing = glowing + 1 end end
    local events = 0
    if frame then for _, e in ipairs(EVENTS) do if frame:IsEventRegistered(e) then events = events + 1 end end end
    return { live = n, glowing = glowing, listening = listening, events = events, preview = previewId ~= nil,
        renders = GW.renders, maps = GW.maps, received = GW.events }
end
