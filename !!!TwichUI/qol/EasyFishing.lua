-- TwichUI: Quality of Life, Easy Fishing
-- One key to cast your line and, while it is out, to reel in. Off until turned on, and no key is bound until
-- the player picks one. Every cast and every reel is the player's own key press: nothing here casts, reels or
-- interacts by itself, and nothing watches for a bite.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   Casting. Bindings.xml has `CLICK TwichUIEasyFishingCast:LeftButton`, a normal entry in Key Bindings >
--   TwichUI. The button is a SecureActionButtonTemplate with type "spell" and the localized Fishing name
--   (SECURE_ACTIONS.spell casts by name, so the highest rank is used). It acts on the key press only
--   (useOnKeyDown, registered for LeftButtonDown), so its release does nothing, whatever the player's
--   "cast on key down" option says. Its attributes are set out of combat only.
--   Reeling. There is no secure action type for interacting. The game's only keyboard way to interact with
--   the thing the client has picked is the INTERACTTARGET binding (Bindings_Camelot.xml:
--   C_PlayerInteractionManager.InteractUnit("anyinteract")). Blizzard's own soft-target-only binding,
--   INTERACTSOFTTARGET, returns at once unless the gamepad UI is on, so it can't be used with a keyboard.
--   While a fishing channel is active, this file sets override bindings (SetOverrideBinding, protected in
--   combat, used by Blizzard_GamepadSharedUtility the same way) that put INTERACTTARGET on the key the player
--   gave Easy Fishing, and takes them away when the channel ends. So one key means two things, chosen by
--   what the game says right now: no fishing channel -> cast; fishing channel -> interact.
--   Detecting it. UnitChannelInfo("player") (spell id is its eighth result) and the
--   UNIT_SPELLCAST_CHANNEL_START / _STOP events. Their values can be secret in restricted contexts, so they
--   are read through Readable and an unreadable value never counts as fishing. A fishing channel is a
--   channel whose spell id is a known Fishing id, or whose name is the localized Fishing name.
--   Which object. While a fishing channel is active the key reels (INTERACTTARGET) unless the game's soft
--   interact target is positively a unit: UnitExists("softinteract") true and UnitIsGameObject("softinteract")
--   false (Blizzard's gamepad action bar asks both the same way). Then, and while the player channels something
--   that is not Fishing, the key is bound to an inert secure button, so it does nothing: it never attacks or
--   talks to an NPC, and it never casts Fishing again over a line that is out. A target the game hasn't picked
--   yet, or one that can't be read, still reels: the bobber is picked a moment after the cast starts, and a
--   key that does nothing in that moment is what made reeling unreliable.
--
-- What can't be known (needs the game; see docs/easy-fishing.md):
--   * That the soft interact target is *your bobber*. The API says "a world object", nothing more: a chest
--     or a mailbox the game prefers would be the one reeled, and with no target picked INTERACTTARGET
--     picks whatever the client resolves at the press. Nothing here can see a bite either, so a press
--     before the bite pulls the line in empty, as clicking the bobber early does.
--   * That the client picks the bobber as its soft interact target at all. That needs the soft-target
--     settings below; whether they are enough is unverified.
--   * The spell ids and the three setting values come from the BetterFishing reference addon (data only),
--     not from the client's own files.
--
-- Client settings. Reeling needs the game's interaction targeting (CVar SoftTargetInteract; the values are
-- Enum SoftTargetEnableFlags: 2 keyboard and mouse, 3 any) with a range and arc wide enough to include the
-- bobber. They are not changed unless the player allows it (Quality of life > Fishing). Allowed, they are
-- set when a fishing channel begins and put back when it ends, when the feature is turned off, at logout
-- and, if the game was closed meanwhile, at the next login. A value is put back only if it is still what we
-- set, so a change the player made in between is never overwritten. The record is TwichUIDB.ui.easyFishingClient.
--
-- Combat. Bindings, overrides and attributes change out of combat only; a change that comes in combat waits
-- and is made from the state of the moment combat ends. Entering combat takes the overrides away if the game
-- still allows it, so a stale reel binding can't act on something else; if it doesn't, they go when combat
-- ends and the key is the game's own INTERACTTARGET until then (fishing does not continue in combat).

local R = TwichUI
local Q = R.QoL
local E = {}
R.QoLEasyFishing = E

E.ACTION = "CLICK TwichUIEasyFishingCast:LeftButton"
E.SWITCH = "qolEasyFishing"
local CAST_NAME, IDLE_NAME = "TwichUIEasyFishingCast", "TwichUIEasyFishingIdle"
local REEL = "INTERACTTARGET"

_G.BINDING_HEADER_TWICHUI = _G.BINDING_HEADER_TWICHUI or "TwichUI"
_G["BINDING_NAME_" .. E.ACTION] = "Easy Fishing (cast and reel in)"

-- Fishing's spell ids, in the order they are tried for a known one (ranks of each era, then the later
-- expansions'). From BetterFishing's list; not checked against the client.
local FISHING_ORDER = { 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474, 131490, 131476, 158743, 377895, 1224771 }
local FISHING = {}
for _, id in ipairs(FISHING_ORDER) do FISHING[id] = true end

-- The soft-target settings reeling needs, as BetterFishing sets them while a line is out.
local TARGETING = {
    { name = "SoftTargetInteract", value = "3" },
    { name = "SoftTargetInteractArc", value = "2" },
    { name = "SoftTargetInteractRange", value = "60" },
}
E.TARGETING = TARGETING

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local cast, idle, owner          -- the two secure buttons, and the plain frame the overrides belong to
local appliedSig = ""            -- what the overrides on the keys are now: state and keys
local state = "idle"             -- "idle" | "hold" | "reel": what the key does while the line is out
local waiting = false            -- something came in combat: PLAYER_REGEN_ENABLED is registered to make it again
local fighting = false           -- combat has begun (seen before the game's lockdown may be): the key does nothing special
local fishName                   -- the localized Fishing name (from a known rank)
local Wait, Resync               -- defined below

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function Readable(value)
    if value ~= nil and issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Supported()
    return SetOverrideBinding ~= nil and ClearOverrideBindings ~= nil and GetBindingKey ~= nil and CreateFrame ~= nil
end
E.Supported = Supported

---------------------------------------------------------------------------
-- Fishing, as the player's spellbook and cast bar say it
---------------------------------------------------------------------------
-- The localized name of Fishing, from any rank the player knows; nil when none is known.
function E.FishingName()
    local book, spells = C_SpellBook, C_Spell
    if not (book and book.IsSpellKnown and spells and spells.GetSpellName) then return nil end
    for _, id in ipairs(FISHING_ORDER) do
        if book.IsSpellKnown(id) then
            local name = Readable(spells.GetSpellName(id))
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    return nil
end

-- "fishing", "other" (a channel that is not Fishing, or one that can't be read) or nil (no channel).
function E.Channel()
    if not UnitChannelInfo then return nil end
    local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    if issecretvalue and issecretvalue(name) then return "other" end
    if name == nil then return nil end
    if issecretvalue and issecretvalue(spellID) then return "other" end
    if type(spellID) == "number" and FISHING[spellID] then return "fishing" end
    if type(name) == "string" and name ~= "" and name == (fishName or E.FishingName()) then return "fishing" end
    return "other"
end

-- True only when the game's soft interact target is positively a unit (an NPC or a player) and not a world
-- object. A missing target, or a value that can't be read, is not "a unit": the line's bobber may not have been
-- picked yet at the moment of the press, and refusing then is what made reeling unreliable.
local function SoftTargetIsUnit()
    if UnitExists == nil or UnitIsGameObject == nil then return false end
    if Readable(UnitExists("softinteract")) ~= true then return false end
    return Readable(UnitIsGameObject("softinteract")) == false
end

---------------------------------------------------------------------------
-- The player's key
---------------------------------------------------------------------------
local function Context()
    local k = C_KeyBindings
    return k and k.GetBindingContextForAction and k.GetBindingContextForAction(E.ACTION) or nil
end

-- The keys bound to Easy Fishing (0 to 2), in the game's order.
function E.Keys()
    if not GetBindingKey then return {} end
    local out = {}
    local a, b = GetBindingKey(E.ACTION, nil, Context())
    if type(a) == "string" and a ~= "" then out[#out + 1] = a end
    if type(b) == "string" and b ~= "" then out[#out + 1] = b end
    return out
end

function E.KeyText(key)
    return GetBindingText and GetBindingText(key) or key
end

-- What else is on the key: the action's key-binding name, or nil when it is free (or already ours).
function E.Conflict(key)
    if not (GetBindingAction and type(key) == "string" and key ~= "") then return nil end
    local action = GetBindingAction(key, nil, Context())
    if type(action) ~= "string" or action == "" or action == E.ACTION then return nil end
    local name = GetBindingName and GetBindingName(action)
    return action, (type(name) == "string" and name ~= "" and name) or action
end

-- Gives Easy Fishing the key, as the game's own Key Bindings does: the key's old action loses only that
-- key, Easy Fishing's first key is replaced and a second one stays, and nothing else is touched. A key
-- that is in use is not taken unless replace is true. Returns "ok", "same", "conflict" (and the action's
-- name), "combat", "unsupported", "invalid" or "failed".
function E.Assign(key, replace)
    if not (SetBinding and GetBindingKey and SaveBindings and GetCurrentBindingSet) then return "unsupported" end
    if type(key) ~= "string" or key == "" or #key > 64 or key == "ESCAPE" then return "invalid" end
    if InCombat() then return "combat" end
    local action, name = E.Conflict(key)
    if action and not replace then return "conflict", name end
    local ctx = Context()
    local first, second = GetBindingKey(E.ACTION, nil, ctx)
    if first == key and not second then return "same" end
    if first and first ~= key then SetBinding(first, nil, ctx) end
    if not SetBinding(key, E.ACTION, ctx) then
        if first and first ~= key then SetBinding(first, E.ACTION, ctx) end
        return "failed"
    end
    SaveBindings(GetCurrentBindingSet())
    return "ok"
end

-- Takes Easy Fishing's own keys off it. Nothing else's binding is touched.
function E.ClearKeys()
    if not (SetBinding and SaveBindings and GetCurrentBindingSet) then return "unsupported" end
    if InCombat() then return "combat" end
    local ctx = Context()
    for _, key in ipairs(E.Keys()) do SetBinding(key, nil, ctx) end
    SaveBindings(GetCurrentBindingSet())
    return "ok"
end

-- Keys that BetterFishing (if it is there) has on its own binding: the same key on both is a conflict only
-- the player can settle, since the later override wins. Read only; its state is never touched.
function E.OtherFishingKeys()
    if not GetBindingKey then return {} end
    local out = {}
    local a, b = GetBindingKey("BETTERFISHINGKEY")
    if type(a) == "string" and a ~= "" then out[#out + 1] = a end
    if type(b) == "string" and b ~= "" then out[#out + 1] = b end
    return out
end

---------------------------------------------------------------------------
-- The client's interaction settings (only ever with the player's say-so)
---------------------------------------------------------------------------
local function GetValue(name)
    local c = C_CVar
    if not (c and c.GetCVar) then return nil end
    local v = c.GetCVar(name)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return tostring(v)
end

local function Record()
    local ui = TwichUIDB and TwichUIDB.ui
    local rec = type(ui) == "table" and ui.easyFishingClient or nil
    if type(rec) ~= "table" or type(rec.saved) ~= "table" then return nil end
    return rec
end

local function ClearRecord()
    local ui = TwichUIDB and TwichUIDB.ui
    if type(ui) == "table" then ui.easyFishingClient = nil end
end

function E.TargetingAllowed() return Q.Get("easyFishingTargeting") == "fishing" end

-- True when keyboard-and-mouse interaction targeting is on in the game now; nil when the setting can't be read.
function E.InteractionOn()
    local v = tonumber(GetValue("SoftTargetInteract"))
    if v == nil then return nil end
    return v >= 2
end

-- Sets the three values (only those that differ), keeping what each was so it can be put back.
local function ApplyTargeting()
    if not E.TargetingAllowed() or InCombat() then return end
    local c = C_CVar
    if not (c and c.SetCVar) or Record() then return end
    local saved = {}
    for _, item in ipairs(TARGETING) do
        local before = GetValue(item.name)
        if before ~= nil and before ~= item.value then
            if c.SetCVar(item.name, item.value) ~= false then
                saved[#saved + 1] = { name = item.name, before = before, set = item.value }
            end
        end
    end
    if #saved > 0 then
        TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
        TwichUIDB.ui.easyFishingClient = { saved = saved }
    end
end

-- Puts each value back unless it is no longer what we set (the player changed it since).
local function RestoreTargeting()
    local rec = Record()
    if not rec then return end
    local c = C_CVar
    if not (c and c.SetCVar) or InCombat() then return end
    for _, item in ipairs(rec.saved) do
        if type(item) == "table" and type(item.name) == "string" and type(item.before) == "string"
            and GetValue(item.name) == item.set then
            c.SetCVar(item.name, item.before)
        end
    end
    ClearRecord()
end
E.RestoreTargeting = RestoreTargeting

-- The player's answer to "adjust them while I fish". Off puts anything we changed back at once.
function E.SetTargeting(on)
    Q.Set("easyFishingTargeting", on and "fishing" or "leave")
    if not on then RestoreTargeting() end
    Resync()
    if on and state ~= "idle" then ApplyTargeting() end   -- a line already out gets them now
end

---------------------------------------------------------------------------
-- The secure buttons and what they hold
---------------------------------------------------------------------------
local function Ensure()
    if cast then return true end
    if InCombat() or not Supported() then return false end
    cast = CreateFrame("Button", CAST_NAME, UIParent, "SecureActionButtonTemplate")
    cast:RegisterForClicks("LeftButtonDown")
    cast:SetAttribute("useOnKeyDown", true)
    -- No type: a click does nothing. The key goes here while it must do nothing at all.
    idle = CreateFrame("Button", IDLE_NAME, UIParent, "SecureActionButtonTemplate")
    idle:RegisterForClicks("LeftButtonDown")
    idle:SetAttribute("useOnKeyDown", true)
    owner = CreateFrame("Frame")
    return true
end

-- Makes the cast button hold Fishing while the feature is on and the player knows it, nothing otherwise.
function E.Refresh()
    if not Ensure() then
        if not cast and R:Enabled(E.SWITCH) then Wait() end
        return
    end
    if InCombat() then Wait() return end
    fishName = E.FishingName()
    local want = R:Enabled(E.SWITCH) and fishName or nil
    if cast:GetAttribute("spell") ~= want then
        cast:SetAttribute("type", want and "spell" or nil)
        cast:SetAttribute("spell", want)
    end
end

---------------------------------------------------------------------------
-- The key while a line is out
---------------------------------------------------------------------------
local function Wanted()
    if fighting or not (cast and R:Enabled(E.SWITCH)) then return "idle" end
    local channel = E.Channel()
    if channel == nil then return "idle" end
    if channel == "fishing" and not SoftTargetIsUnit() then return "reel" end
    return "hold"
end

local function Signature(want, keys)
    return want .. "|" .. table.concat(keys, "|")
end

-- Makes the keys match what the game says now. Safe to call at any time and as often as you like.
-- stopping: leave nothing bound (the feature went off, or combat is starting).
-- Returns true when the key went from doing nothing special to something else, or back: the caller then
-- brings the listening in line (the soft-target event is wanted only while a line is out).
function E.Sync(stopping)
    if not cast then return false end
    local want = stopping and "idle" or Wanted()
    local keys = want == "idle" and {} or E.Keys()
    local sig = Signature(want, keys)
    if sig == appliedSig then return false end
    if InCombat() then Wait() return false end
    ClearOverrideBindings(owner)
    for _, key in ipairs(keys) do
        if want == "reel" then SetOverrideBinding(owner, true, key, REEL)
        else SetOverrideBindingClick(owner, true, key, IDLE_NAME, "LeftButton") end
    end
    appliedSig = sig
    local before = state
    state = want
    if want ~= "idle" then ApplyTargeting() else RestoreTargeting() end
    return (before == "idle") ~= (want == "idle")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Syncs, and re-reads which events are wanted when the line went out or came in.
function Resync(stopping)
    if E.Sync(stopping) and E.feature then Q.Apply(E.feature) end
end

local function OnChannel(unit)
    if unit == "player" then Resync() end
end

local function OnState() Resync() end

local function OnSpells() E.Refresh() end

local function OnWorld()
    E.Refresh()
    Resync()
    if state == "idle" then RestoreTargeting() end   -- a game closed mid-line left them set
end

local function OnLogout() RestoreTargeting() end

local function OnCombatStart()
    fighting = true
    if state ~= "idle" and not InCombat() then Resync() end
end

local function OnCombatEnd()
    fighting = false
    E.Refresh()
    Resync()
end

local function AfterCombat()
    fighting = false
    waiting = false
    R:Off("PLAYER_REGEN_ENABLED", AfterCombat)
    if R:Enabled(E.SWITCH) then
        E.Refresh()
        Resync()
    else
        E.Teardown()
    end
end

-- Something has to be made again when combat ends; the feature's own listening may be off by then.
function Wait()
    if R.Life and R.Life.Note then R.Life.Note("deferred-combat") end
    if not waiting then
        waiting = true
        R:On("PLAYER_REGEN_ENABLED", AfterCombat)
    end
end

-- Everything this file put in the game, taken out: overrides, client settings and the cast button's spell.
function E.Teardown()
    if cast then
        if InCombat() then Wait() return end
        E.Sync(true)
        if cast:GetAttribute("spell") ~= nil then
            cast:SetAttribute("type", nil)
            cast:SetAttribute("spell", nil)
        end
    end
    RestoreTargeting()
end

E.feature = Q.Add({
    key = E.SWITCH,
    Events = function()
        E.Refresh()
        E.Sync()
        local events = {
            UNIT_SPELLCAST_CHANNEL_START = OnChannel,
            UNIT_SPELLCAST_CHANNEL_STOP = OnChannel,
            PLAYER_ENTERING_WORLD = OnWorld,
            PLAYER_DEAD = OnState,
            PLAYER_REGEN_DISABLED = OnCombatStart,
            PLAYER_REGEN_ENABLED = OnCombatEnd,
            UPDATE_BINDINGS = OnState,
            SPELLS_CHANGED = OnSpells,
            PLAYER_LOGOUT = OnLogout,
        }
        -- Only while a line is out: the soft interact target changes all the time otherwise.
        if state ~= "idle" then events.PLAYER_SOFT_INTERACT_CHANGED = OnState end
        return events
    end,
    Stop = function() E.Teardown() end,
})

-- A record left by a game that closed mid-line: at start nobody is fishing, so it is put back as soon as the
-- saved data is in (if the line is still out after a reload, the world-entry sync sets them again).
R:OnInit(RestoreTargeting)

---------------------------------------------------------------------------
-- What the settings page shows
---------------------------------------------------------------------------
-- A code and the keys, for the page: "off", "unsupported", "not-learned", "no-key", "needs-targeting",
-- "ready". Reads only.
function E.Status()
    if not R:Enabled(E.SWITCH) then return "off" end
    if not Supported() then return "unsupported" end
    if not E.FishingName() then return "not-learned" end
    if #E.Keys() == 0 then return "no-key" end
    if not E.TargetingAllowed() and E.InteractionOn() == false then return "needs-targeting" end
    return "ready"
end
