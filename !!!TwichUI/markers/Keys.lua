-- TwichUI: marker cycling, the keys
-- Six hidden buttons of the game's own secure kind (SecureActionButtonTemplate), each with a key binding in
-- Bindings.xml (Key Bindings > TwichUI), none bound until you choose a key:
--   target: mark your target with the next marker / restart the cycle / remove your target's marker
--   world:  place the next world marker at the mouse pointer / restart the cycle / remove every world marker
-- A key press is the only thing that ever marks or clears: TwichUI never presses them, and nothing here runs
-- on a timer or an event.
--
-- What the game gives (WoW: Forever UI source, Blizzard_FrameXML/SecureTemplates.lua and SlashCommands.lua):
--   * SECURE_ACTIONS.raidtarget: action "set" calls SetRaidTarget(unit, marker) only when the unit doesn't already
--     wear that marker, so a press never takes a marker off (the game's "toggle" would); "clear" sets 0.
--     /tm is not used: it is an insecure slash command there, so a button's macro can't mark with it.
--   * /wm is a secure slash command: "/wm [@cursor] N" calls PlaceRaidMarker(N, "cursor"), which places it
--     where the pointer is, with no targeting circle to confirm or cancel. SECURE_ACTIONS.worldmarker "clear"
--     with no marker calls ClearRaidMarker(nil), every world marker (as /cwm all does).
--   * Whether a mark or a placement worked (permission, range, a unit that can't be marked) is the game's to
--     decide and say; nothing a key press can read tells us, so nothing here claims it.
--
-- The cycle. Its position is an attribute of the "next" button ("twichui-step": presses since it last
-- restarted). The secure snippets below change it as a key is pressed, so cycling and restarting work in combat;
-- out of combat the settings' Restart and a new sequence set it back to 0. It is never saved. One press is one
-- step: a key binding sends a press and a release, and the snippet acts on the first it gets and lets the second
-- through untouched (the game's own button code then acts on the edge "cast on key down" chooses, with what the
-- first set). A step is taken only when the press will do something: the feature is on, at least one
-- marker is on and, for target markers, there is a unit to mark. Restart sets the step back to 0 (the next
-- press is the first marker) and removes nothing. Clearing removes markers and, if chosen, restarts too.
--
-- The order and options (markers/Markers.lua) reach the buttons as attributes, which can't be changed in
-- combat: a change made in combat is saved at once and given to the buttons when combat ends (the latest one
-- only), and MK.Pending says so meanwhile. Giving a kind a different sequence restarts its cycle.

local R = TwichUI
local M = R.Markers
local MK = {}
R.MarkerKeys = MK

local NAMES = {
    target = { next = "TwichUIMarkTargetNext", restart = "TwichUIMarkTargetRestart", clear = "TwichUIMarkTargetClear" },
    world = { next = "TwichUIMarkWorldNext", restart = "TwichUIMarkWorldRestart", clear = "TwichUIMarkWorldClear" },
}

-- The key bindings, in the order the settings list them. Their names in the game's Key Bindings list are set here.
MK.ACTIONS = {
    { id = "targetNext", kind = "target", which = "next", label = "Mark your target with the next marker",
        bindingName = "Target markers: mark your target with the next marker" },
    { id = "targetRestart", kind = "target", which = "restart", label = "Restart the target-marker cycle",
        bindingName = "Target markers: restart the cycle" },
    { id = "targetClear", kind = "target", which = "clear", label = "Remove your target's marker",
        bindingName = "Target markers: remove your target's marker" },
    { id = "worldNext", kind = "world", which = "next", label = "Place the next world marker at the mouse pointer",
        bindingName = "World markers: place the next one at the mouse pointer" },
    { id = "worldRestart", kind = "world", which = "restart", label = "Restart the world-marker cycle",
        bindingName = "World markers: restart the cycle" },
    { id = "worldClear", kind = "world", which = "clear", label = "Remove all world markers",
        bindingName = "World markers: remove all of them" },
}
local ACTION = {}
BINDING_HEADER_TWICHUI = BINDING_HEADER_TWICHUI or "TwichUI"
for _, a in ipairs(MK.ACTIONS) do
    a.button = NAMES[a.kind][a.which]
    a.binding = "CLICK " .. a.button .. ":LeftButton"
    ACTION[a.id] = a
    _G["BINDING_NAME_" .. a.binding] = a.bindingName
end

function MK.Action(id) return ACTION[id] end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- The secure snippets (restricted code: only the functions the game's restricted environment offers)
---------------------------------------------------------------------------
-- One step per key press, whichever edge arrives first.
local PRESS = [[
    if down then
        self:SetAttribute("twichui-held", true)
    elseif self:GetAttribute("twichui-held") then
        self:SetAttribute("twichui-held", nil)
        return
    end
]]
-- The unit a target-marker key acts on, or nil: your target, or (if chosen) a living enemy under the pointer first.
local UNIT = [[
    local unit
    if self:GetAttribute("twichui-unit") == "mouseover" then
        unit = SecureCmdOptionParse("[@mouseover,harm,nodead] mouseover; [@target,exists] target")
    else
        unit = SecureCmdOptionParse("[@target,exists] target")
    end
]]
-- The restart a clear may make.
local RESTART_ON_CLEAR = [[
    if self:GetAttribute("twichui-restart") then self:GetFrameRef("cycle"):SetAttribute("twichui-step", 0) end
]]

MK.SNIPPETS = {
    targetNext = PRESS .. [[
    self:SetAttribute("type", nil)
    local n = self:GetAttribute("twichui-count") or 0
    if not self:GetAttribute("twichui-on") or n < 1 then return end
]] .. UNIT .. [[
    if not unit then return end
    local step = (self:GetAttribute("twichui-step") or 0) % n + 1
    self:SetAttribute("twichui-step", step)
    self:SetAttribute("unit", unit)
    self:SetAttribute("marker", self:GetAttribute("twichui-m" .. step))
    self:SetAttribute("type", "raidtarget")
]],
    worldNext = PRESS .. [[
    self:SetAttribute("type", nil)
    local n = self:GetAttribute("twichui-count") or 0
    if not self:GetAttribute("twichui-on") or n < 1 then return end
    local step = (self:GetAttribute("twichui-step") or 0) % n + 1
    self:SetAttribute("twichui-step", step)
    self:SetAttribute("macrotext", self:GetAttribute("twichui-cmd") .. " [@cursor] " .. self:GetAttribute("twichui-m" .. step))
    self:SetAttribute("type", "macro")
]],
    targetClear = PRESS .. [[
    self:SetAttribute("type", nil)
    if not self:GetAttribute("twichui-on") then return end
]] .. UNIT .. [[
    if not unit then return end
    self:SetAttribute("unit", unit)
    self:SetAttribute("type", "raidtarget")
]] .. RESTART_ON_CLEAR,
    worldClear = PRESS .. [[
    self:SetAttribute("type", nil)
    if not self:GetAttribute("twichui-on") then return end
    self:SetAttribute("type", "worldmarker")
]] .. RESTART_ON_CLEAR,
    restart = PRESS .. [[
    if self:GetAttribute("twichui-on") then self:GetFrameRef("cycle"):SetAttribute("twichui-step", 0) end
]],
}

---------------------------------------------------------------------------
-- Telling what shows the state (the settings page): fn(what, kind), what = "press", "config" or "keys"
---------------------------------------------------------------------------
local listeners = {}
function MK.OnState(fn)
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end
local function Notify(what, kind)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what, kind)
        if not ok then R.Fault("marker cycling", err) end
    end
end

---------------------------------------------------------------------------
-- Feedback for a key press that can't do anything: one short local line where the game shows its own, never
-- chat. A press sends a click as the key goes down and another as it comes up, so the same line within half a
-- second is said once.
---------------------------------------------------------------------------
local said, saidAt = nil, 0
local function Say(text)
    local now = GetTime and GetTime() or 0
    if text == said and now - saidAt < 0.5 then return end
    said, saidAt = text, now
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end
MK.Say = Say

local NOUN = { target = "Target marker", world = "World marker" }
local active, pending = {}, {}   -- [kind]: what the buttons were last given; true while a change waits for combat

local function AfterPress(kind, which)
    local a = active[kind]
    if a and not a.on then
        Say(("TwichUI: %s cycling is off. Turn it on in TwichUI's settings, under Quality of life."):format(NOUN[kind]:lower()))
    elseif a and which ~= "clear" and #a.list == 0 then
        Say(("TwichUI: every %s is turned off, so there is nothing to place. Turn one on in TwichUI's settings."):format(NOUN[kind]:lower()))
    elseif a and which == "restart" then
        Say(("TwichUI: %s cycle restarted. Next: %s."):format(NOUN[kind]:lower(), M.Name(kind, a.list[1])))
    end
    Notify("press", kind)
end

---------------------------------------------------------------------------
-- The buttons: made once, out of combat (secure frames and their snippets can't be set up in combat)
---------------------------------------------------------------------------
local buttons, built = {}, false

local function NewButton(kind, which, snippet)
    local b = CreateFrame("Button", NAMES[kind][which], UIParent, "SecureActionButtonTemplate")
    -- Never shown on screen (no size, no place, nothing drawn); only its key binding clicks it. Both edges,
    -- so it hears a key whichever one the game sends; the snippet takes one step per press.
    b:RegisterForClicks("AnyUp", "AnyDown")
    SecureHandlerWrapScript(b, "PreClick", b, snippet)
    b:SetScript("PostClick", function() AfterPress(kind, which) end)
    return b
end

function MK.Build()
    if built then return true end
    if InCombat() or not (CreateFrame and SecureHandlerWrapScript and SecureHandlerSetFrameRef) then return false end
    for _, kind in ipairs(M.KINDS) do
        local set = {}
        set.next = NewButton(kind, "next", MK.SNIPPETS[kind .. "Next"])
        set.restart = NewButton(kind, "restart", MK.SNIPPETS.restart)
        set.clear = NewButton(kind, "clear", MK.SNIPPETS[kind .. "Clear"])
        SecureHandlerSetFrameRef(set.restart, "cycle", set.next)
        SecureHandlerSetFrameRef(set.clear, "cycle", set.next)
        if kind == "target" then
            set.next:SetAttribute("action", "set")
            set.clear:SetAttribute("action", "clear")
        else
            set.clear:SetAttribute("action", "clear")   -- no marker: every world marker
        end
        buttons[kind] = set
    end
    built = true
    return true
end

function MK.Built() return built end

-- The client's own /wm (its first alias, so it is the one this client registered), else "/wm".
local function WorldCommand()
    local c = _G.SLASH_WORLD_MARKER1
    if type(c) == "string" and c:match("^/[^%s%[%]]+$") then return c end
    return "/wm"
end

local function Wanted(kind)
    return {
        on = R:Enabled(M.SWITCH[kind]) and true or false,
        list = M.Sequence(kind),
        unit = kind == "target" and M.Get("targetUnit") or nil,
        restart = M.Get(kind .. "ClearRestarts") and true or false,
        cmd = kind == "world" and WorldCommand() or nil,
    }
end

local function Same(a, b)
    return a ~= nil and b ~= nil and a.on == b.on and a.unit == b.unit and a.restart == b.restart and a.cmd == b.cmd
        and M.SameList(a.list, b.list)
end

local function Push(kind, want)
    local set, old = buttons[kind], active[kind]
    local n = #want.list
    set.next:SetAttribute("twichui-on", want.on)
    set.next:SetAttribute("twichui-count", n)
    for i = 1, M.COUNT do set.next:SetAttribute("twichui-m" .. i, want.list[i]) end
    if kind == "target" then
        set.next:SetAttribute("twichui-unit", want.unit)
        set.clear:SetAttribute("twichui-unit", want.unit)
    else
        set.next:SetAttribute("twichui-cmd", want.cmd)
    end
    set.clear:SetAttribute("twichui-on", want.on)
    set.clear:SetAttribute("twichui-restart", want.restart)
    set.restart:SetAttribute("twichui-on", want.on)
    -- a different sequence starts from its first marker; the same one (an option changed) keeps its place
    if not (old and M.SameList(old.list, want.list)) then set.next:SetAttribute("twichui-step", 0) end
    active[kind] = want
end

local OnRegenEnabled
local waiting = false
local function WaitForCombat()
    if waiting then return end
    waiting = true
    R.Life.Note("deferred-combat")
    R:On("PLAYER_REGEN_ENABLED", OnRegenEnabled)
end

-- The buttons follow the saved order and options, for one kind or (nil) both. Safe to call any time: what is
-- already in place is left alone, and in combat the change waits (only the latest is given afterwards).
function MK.Apply(kind)
    for _, k in ipairs(M.KINDS) do
        if kind == nil or kind == k then
            local want = Wanted(k)
            if Same(active[k], want) then
                pending[k] = nil      -- changed back before combat ended: nothing waits
            elseif InCombat() then
                pending[k] = true
                WaitForCombat()
            elseif not MK.Build() then
                pending[k] = nil      -- the game's secure buttons aren't there to set up: nothing can wait for them
            else
                Push(k, want)
                pending[k] = nil
            end
        end
    end
    Notify("config", kind)
end

function MK.Refresh() MK.Apply(nil) end   -- Switches.lua

function OnRegenEnabled()
    waiting = false
    R:Off("PLAYER_REGEN_ENABLED", OnRegenEnabled)
    MK.Apply(nil)
end

---------------------------------------------------------------------------
-- Reading the state (for the settings page's preview; changes nothing)
---------------------------------------------------------------------------
-- A change of this kind's order or options is saved but waits for combat to end before the keys use it.
function MK.Pending(kind) return pending[kind] == true end

-- What the keys use now: { on, list, unit, restart } (do not change it), or nil before the buttons exist.
function MK.Active(kind) return active[kind] end

function MK.Step(kind)
    local b = buttons[kind] and buttons[kind].next
    return b and tonumber(b:GetAttribute("twichui-step")) or 0
end

-- The marker the next press of the kind's key would give, from what the keys use now (nil: none would).
function MK.NextMarker(kind)
    local a = active[kind]
    if not (a and a.on) then return nil end
    return (M.NextAfter(a.list, MK.Step(kind)))
end

-- The restart the settings page offers: the same as the restart key, out of combat only (in combat, setting a
-- secure button's attribute from here isn't allowed; the restart key works then).
function MK.Restart(kind)
    if not M.ValidKind(kind) then return false, "kind" end
    if InCombat() then return false, "combat" end
    local b = buttons[kind] and buttons[kind].next
    if not b then return false, "none" end
    b:SetAttribute("twichui-step", 0)
    Notify("press", kind)
    return true
end

-- Whether the game offers world markers here (nil when it doesn't say).
function MK.WorldMarkersAvailable()
    if type(IsRaidMarkerSystemEnabled) ~= "function" then return nil end
    local ok, on = pcall(IsRaidMarkerSystemEnabled)
    if not ok then return nil end
    return on and true or false
end

-- World Marker Cycler is loaded too. It is never called or changed; the settings say how the two live together.
function MK.OtherCycler()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WorldMarkerCycler") and true or false
end

---------------------------------------------------------------------------
-- Key bindings: only this feature's own six actions are ever bound or unbound here, and only when you ask.
-- They are the game's key bindings (saved with the game's binding set), so they are the same in every profile,
-- are never part of configuration sharing, and are kept while the feature is off (its keys then do nothing).
---------------------------------------------------------------------------
-- The keys bound to an action (up to two, as the game's list allows), as key names.
function MK.Keys(id)
    local a = ACTION[id]
    if not (a and GetBindingKey) then return end
    return GetBindingKey(a.binding)
end

function MK.KeyLabel(key)
    if type(key) ~= "string" then return nil end
    return GetBindingText and GetBindingText(key) or key
end

-- "F, Shift-F" for an action's keys, or nil when it has none.
function MK.KeyText(id)
    local k1, k2 = MK.Keys(id)
    if not k1 and not k2 then return nil end
    local list = {}
    if k1 then list[#list + 1] = MK.KeyLabel(k1) end
    if k2 then list[#list + 1] = MK.KeyLabel(k2) end
    return table.concat(list, ", ")
end

-- A binding action in words: ours by its label, another addon's button by its name, the game's by its own name.
function MK.ActionName(action)
    if type(action) ~= "string" or action == "" then return nil end
    for _, a in ipairs(MK.ACTIONS) do
        if a.binding == action then return "TwichUI: " .. a.label:sub(1, 1):lower() .. a.label:sub(2) end
    end
    local named = _G["BINDING_NAME_" .. action]
    if type(named) == "string" and named ~= "" then return named end
    local button = action:match("^CLICK ([^:]+):")
    if button then
        if button:find("^WorldMarkerCycler") or button:find("^WMC_") then return "World Marker Cycler (" .. button .. ")" end
        return "another addon's button (" .. button .. ")"
    end
    return GetBindingName and GetBindingName(action) or action
end

-- What a key does now: the action in the game's key bindings ("" or nil for none), and, when another addon has
-- taken the key over for now (an override binding, which wins), that action as well.
function MK.KeyUse(key)
    if type(key) ~= "string" or not GetBindingAction then return nil end
    local bound = GetBindingAction(key)
    local now = GetBindingAction(key, true)
    if now == bound then now = nil end
    return bound ~= "" and bound or nil, now ~= "" and now or nil
end

-- For one of our actions: its keys that another addon has taken over right now, as { key, action } entries.
function MK.TakenOver(id)
    local out = {}
    local a = ACTION[id]
    if not a then return out end
    for _, key in ipairs({ MK.Keys(id) }) do
        local _, over = MK.KeyUse(key)
        if over and over ~= a.binding then out[#out + 1] = { key = key, action = over } end
    end
    return out
end

local function Save()
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    Notify("keys")
end

-- A key chord as the game names it ("CTRL-F", "SHIFT-BUTTON4"): plain text of a sensible length.
local function ValidChord(key)
    return type(key) == "string" and #key >= 1 and #key <= 64 and not key:find("[%c%s|]")
end

-- Binds key to one of our actions, in place of its first key (a second key set in the game's list is kept).
-- Whatever had the key loses it, which the settings ask about first. Out of combat only.
function MK.SetKey(id, key)
    local a = ACTION[id]
    if not a then return false, "action" end
    if not ValidChord(key) then return false, "key" end
    if InCombat() then return false, "combat" end
    if not (SetBinding and GetBindingKey) then return false, "unsupported" end
    local first = GetBindingKey(a.binding)
    if first == key then return true end
    if first then SetBinding(first) end
    if not SetBinding(key, a.binding) then
        if first then SetBinding(first, a.binding) end
        return false, "refused"
    end
    Save()
    return true
end

-- Unbinds every key of one of our actions. Out of combat only.
function MK.RemoveKeys(id)
    local a = ACTION[id]
    if not a then return false, "action" end
    if InCombat() then return false, "combat" end
    if not SetBinding then return false, "unsupported" end
    local keys = { MK.Keys(id) }
    if #keys == 0 then return true end
    for _, key in ipairs(keys) do SetBinding(key) end
    Save()
    return true
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
M.OnChange(function(kind) MK.Apply(kind) end)
R:OnInit(function() MK.Apply(nil) end)
