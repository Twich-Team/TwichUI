-- TwichUI Fishing: the fishing key
--
-- Key Bindings > TwichUI has "Fishing: the next step" (CLICK TwichUIFishingButton:LeftButton) and "Fishing: open the next
-- container" (CLICK TwichUIFishingOpen:LeftButton); the names are set by the core's FishingLauncher.lua. No key is ever bound
-- by TwichUI. Both are hidden SecureActionButtonTemplate buttons that act once per press, on the key's release
-- (RegisterForClicks "LeftButtonUp", useOnKeyDown false: the pattern the refreshments keys use).
--
-- One press, one step. Out of combat the button's PreClick reads the game, decides (A.Decide, a pure function) and sets the
-- secure attributes; the game's own secure handler then performs that one action (SecureTemplates.lua):
--   restore  type "macro": /equipslot lines putting your own weapons and gear back (no session, restoration pending)
--   outfit   type "equipmentset": your fishing outfit (config gear.outfit)
--   equip    type "item" on the pole's bag slot: SECURE_ACTIONS.item equips an equippable item that is not worn
--   open     type "item" on a queued fishing container's bag slot (config containers.openWithKey)
--   lure     type "item" on the lure's bag slot with "target-slot" 16: the lure goes on the pole
--   cast     type "spell": Fishing
--   none     nothing; a short line says why when it is something the player can act on
-- Nothing is ever pressed by TwichUI, and nothing runs on a timer or a bite: every cast, reel and item use is a press.
--
-- Reeling. There is no secure action type for interacting (SecureTemplates.lua). While a Fishing channel is active the
-- player's own key(s) for the fishing key get an override binding to the game's INTERACTTARGET
-- (C_PlayerInteractionManager.InteractUnit("anyinteract"), Bindings_Camelot.xml), or INTERACTMOUSEOVER if chosen; when the
-- game's soft interact target is positively a unit (an NPC or a player) the key is bound to an inert button instead, so it
-- never talks to an NPC or attacks. The overrides go as the line ends. Whether the client picks the bobber as its soft
-- interact target depends on its interaction-targeting settings (SoftTargetInteract and its range and arc), which are changed
-- only if the player allows it (config interact.adjust), are put back as the line ends, and are never changed in combat.
--
-- Not casting by accident. Right after a line ends (a catch, an early reel, a timeout) the key does nothing for config
-- action.guard seconds, and nothing while a loot window is open, so a second press meant to reel never casts again.
--
-- Combat. Attributes and override bindings are changed out of combat only. As combat begins (PLAYER_REGEN_DISABLED, while the
-- game still allows it) the overrides are removed and the key is set up for the fight: with config gear.combatWeapons and the
-- pole on, a press puts your weapons back (a secure /equipslot macro); otherwise it does nothing. Normal service resumes when
-- combat ends.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local G = F.Gear
local L = F.Lure
local C = F.Containers
local Lo = F.Loot
local Ses = F.Session
local A = {}
F.Action = A

A.BUTTON, A.OPEN_BUTTON, A.IDLE_BUTTON = "TwichUIFishingButton", "TwichUIFishingOpen", "TwichUIFishingIdle"
A.BINDING = "CLICK " .. A.BUTTON .. ":LeftButton"
A.OPEN_BINDING = "CLICK " .. A.OPEN_BUTTON .. ":LeftButton"

local button, openButton, idleButton, owner
local line = nil          -- { start, guid, caught, interrupted } while a Fishing channel is active
local lastLine = nil      -- the line that ended most recently (a catch can arrive just after its channel stops)
local lastEnd = -math.huge
local looting = false
local fighting = false    -- combat began (seen at PLAYER_REGEN_DISABLED, before the lockdown may be on)
local armedForCombat = nil
local appliedSig = ""
local waiting = false
local counted = {}        -- castGUIDs already counted as failed or interrupted (runtime, bounded)
A.presses, A.last = 0, nil
A.state = "idle"

---------------------------------------------------------------------------
-- Fishing as the spellbook and the cast bar say it
---------------------------------------------------------------------------
local function Known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and F.Readable(known) == true then return true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok and F.Readable(known) == true then return true end
    end
    return false
end

local spellCache
function A.Spell()
    if spellCache ~= nil then return spellCache or nil end
    spellCache = false
    for _, id in ipairs(F.FISHING_ORDER) do
        if Known(id) then
            local name = C_Spell and C_Spell.GetSpellName and F.Readable(C_Spell.GetSpellName(id))
            spellCache = { id = id, name = type(name) == "string" and name or nil }
            break
        end
    end
    return spellCache or nil
end
function A.ForgetSpell() spellCache = nil end

local function IsFishing(spellID, name)
    spellID = F.Num(spellID)
    if spellID and F.FISHING_SPELL[spellID] then return true end
    local sp = A.Spell()
    return sp ~= nil and sp.name ~= nil and F.Readable(name) == sp.name
end

-- "fishing", "other" (a channel that is not Fishing, or one that can't be read) or nil (none).
function A.Channel()
    if not UnitChannelInfo then return line and "fishing" or nil end
    local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    if issecretvalue and issecretvalue(name) then return "other" end
    if name == nil then return nil end
    if IsFishing(spellID, name) then return "fishing" end
    return "other"
end

function A.LineOut() return line ~= nil end

---------------------------------------------------------------------------
-- The decision (pure: everything it needs is in ctx; tests call it directly)
---------------------------------------------------------------------------
A.WHY = {
    off = "TwichUI Fishing is turned off. Type /tui fish on.",
    combat = "TwichUI: not during combat.",
    ["line-out"] = "TwichUI: your line is out. Press your Interact key, or click the bobber, to reel in.",
    busy = "TwichUI: you're busy channelling something else.",
    ["bags-full"] = "TwichUI: your bags are full, so your gear can't be changed. Make room first.",
    ["no-spell"] = "TwichUI: you don't know Fishing.",
    held = nil, guard = nil, looting = nil,
}

function A.Decide(ctx)
    if not ctx.enabled then return { kind = "none", why = "off" } end
    if ctx.combat then return { kind = "none", why = "combat" } end
    if ctx.line == "fishing" then return { kind = "none", why = "line-out" } end
    if ctx.line == "other" then return { kind = "none", why = "busy" } end
    if ctx.looting then return { kind = "none", why = "looting" } end
    if ctx.guard then return { kind = "none", why = "guard" } end
    if not ctx.held then
        if ctx.restore then return { kind = "restore", macro = ctx.restore } end
        local g = ctx.gear
        if g and (g.kind == "equip" or g.kind == "outfit") then return g end
        if g and g.kind == "none" and g.why == "bags-full" then return { kind = "none", why = "bags-full" } end
        if ctx.open then return ctx.open end
        if ctx.lure then return ctx.lure end
    end
    if ctx.spell then return { kind = "cast", spell = ctx.spell } end
    return { kind = "none", why = "no-spell" }
end

-- Everything Decide needs, read from the game now.
function A.Context()
    local sp = A.Spell()
    local ctx = {
        enabled = S.Get("enabled") and true or false,
        held = S.held,
        combat = fighting or F.InCombat(),
        line = A.Channel() or (line and "fishing" or nil),
        looting = looting or Lo.Open(),
        guard = F.Clock() - lastEnd < (S.Get("action.guard") or 1),
        spell = sp and sp.id or nil,
    }
    if ctx.enabled and not ctx.held and not ctx.combat and not ctx.line and not ctx.looting and not ctx.guard then
        if not Ses.Current() and G.State() ~= "none" then ctx.restore = G.RestoreMacro(false) end
        ctx.gear = G.Plan()
        ctx.open = C.Plan(true)
        ctx.lure = L.Plan()
    end
    return ctx
end

---------------------------------------------------------------------------
-- The secure buttons
---------------------------------------------------------------------------
local ATTRS = { "type", "spell", "item", "macrotext", "equipmentset", "target-slot", "target-bag" }

local function Arm(b, action)
    for _, k in ipairs(ATTRS) do
        if b:GetAttribute(k) ~= nil then b:SetAttribute(k, nil) end
    end
    local k = action.kind
    if k == "cast" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", action.spell)
    elseif k == "equip" or k == "open" then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", action.bag .. " " .. action.slot)
    elseif k == "lure" then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", action.bag .. " " .. action.slot)
        b:SetAttribute("target-slot", F.MAINHAND)
    elseif k == "outfit" then
        b:SetAttribute("type", "equipmentset")
        b:SetAttribute("equipmentset", action.name)
    elseif k == "restore" then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", action.macro)
    end
end
A.Arm = Arm

-- The bookkeeping for the action the press is about to perform.
local function Begin(action)
    local k = action.kind
    -- a press that prepares to fish (gear, a lure, a container from fishing) is the player fishing: it begins the session,
    -- so the gear it puts on is never mistaken for a restoration still to do
    if k == "equip" or k == "outfit" or k == "lure" or k == "cast" then Ses.Ensure("key") end
    if k == "equip" or k == "outfit" then G.BeginEquip(action)
    elseif k == "lure" then L.BeginApply(action)
    elseif k == "open" then C.BeginOpen(action, "key")
    elseif k == "restore" then G.BeginMacroRestore()
    end
end

local function SetState(new)
    if new == A.state then return end
    local old = A.state
    A.state = new
    F.Emit("STATE", new, old)
end

function A.Refresh()
    local new
    if line then new = "line"
    elseif looting then new = "looting"
    elseif Ses.Current() then new = "ready"
    else new = "idle" end
    SetState(new)
end

local function PreClick(self)
    A.presses = A.presses + 1
    if F.InCombat() then
        A.last = { kind = armedForCombat or "none", why = armedForCombat and nil or "combat", combat = true }
        if armedForCombat == "restore" then G.BeginMacroRestore() end
        return
    end
    local pt = R.Perf.on and R.Perf.Start("fishing.decide")
    local action = A.Decide(A.Context())
    Arm(self, action)
    A.last = action
    Begin(action)
    if pt then R.Perf.Stop(pt) end
end

-- After the secure handler has acted: the button goes back to doing nothing, so an action armed for one press never
-- outlives it (if combat began before PLAYER_REGEN_DISABLED reached us, a press in lockdown does nothing rather than repeat
-- the last step). In combat the attributes can't change and stay as combat set them.
local function PostClick(self)
    local a = A.last
    if not F.InCombat() and a and a.kind ~= "none" then Arm(self, { kind = "none" }) end
    if a and a.kind == "none" and a.why and A.WHY[a.why] then F.Say(A.WHY[a.why]) end
    if a and a.kind == "none" and a.why then F.Note("press-" .. a.why) end
end

-- The open key: only the next queued container.
local function OpenPreClick(self)
    if F.InCombat() then self.last = { kind = "none", why = "combat" } return end
    local action
    if line or looting or Lo.Open() then action = { kind = "none", why = "busy" }
    else
        local plan, why = C.Plan(false)
        action = plan or { kind = "none", why = why or "empty" }
    end
    Arm(self, action)
    self.last = action
    if action.kind == "open" then C.BeginOpen(action, "key") end
end

local OPEN_WHY = { empty = "TwichUI: no fishing containers to open.", ["bags-full"] = "TwichUI: make room in your bags first.",
    combat = "TwichUI: not during combat.", off = "TwichUI: container opening is turned off." }
local function OpenPostClick(self)
    local a = self.last
    if not F.InCombat() and a and a.kind ~= "none" then Arm(self, { kind = "none" }) end
    if a and a.kind == "none" and OPEN_WHY[a.why] then F.Say(OPEN_WHY[a.why]) end
end

local function NewButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    return b
end

-- Made once, out of combat. Returns true when they exist.
function A.Build()
    if button then return true end
    if F.InCombat() or not CreateFrame then return false end
    button = NewButton(A.BUTTON)
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    openButton = NewButton(A.OPEN_BUTTON)
    openButton:SetScript("PreClick", OpenPreClick)
    openButton:SetScript("PostClick", OpenPostClick)
    idleButton = NewButton(A.IDLE_BUTTON)   -- no type: a press does nothing
    owner = CreateFrame("Frame")
    A.Arm(button, { kind = "none" })
    return true
end

function A.Buttons() return button, openButton, idleButton end

---------------------------------------------------------------------------
-- The player's keys and the reel overrides
---------------------------------------------------------------------------
function A.Keys(action)
    if not GetBindingKey then return {} end
    local out = {}
    local a, b = GetBindingKey(action or A.BINDING)
    if type(a) == "string" and a ~= "" then out[#out + 1] = a end
    if type(b) == "string" and b ~= "" then out[#out + 1] = b end
    return out
end

local function SoftTargetIsUnit()
    if not (UnitExists and UnitIsGameObject) then return false end
    if F.Readable(UnitExists("softinteract")) ~= true then return false end
    return F.Readable(UnitIsGameObject("softinteract")) == false
end

local function Wanted()
    if fighting or not (button and S.Get("enabled")) then return "idle" end
    if not line then return "idle" end
    if SoftTargetIsUnit() then return "hold" end
    return "reel"
end

local OnRegen
local function Wait()
    if waiting then return end
    waiting = true
    if R.Life and R.Life.Note then R.Life.Note("deferred-combat") end
    R:On("PLAYER_REGEN_ENABLED", OnRegen)
end

-- Makes the overrides match the line. Safe to call at any time. stopping: leave nothing bound.
function A.Sync(stopping)
    if not (owner and SetOverrideBinding and ClearOverrideBindings) then return end
    local want = stopping and "idle" or Wanted()
    local keys = want == "idle" and {} or A.Keys()
    local sig = want .. "|" .. table.concat(keys, "|") .. "|" .. tostring(S.Get("action.reel"))
    if sig == appliedSig then return end
    if F.InCombat() then Wait() return end
    ClearOverrideBindings(owner)
    for _, key in ipairs(keys) do
        if want == "reel" then SetOverrideBinding(owner, true, key, S.Get("action.reel") or "INTERACTTARGET")
        else SetOverrideBindingClick(owner, true, key, A.IDLE_BUTTON, "LeftButton") end
    end
    appliedSig = sig
end

---------------------------------------------------------------------------
-- Interaction targeting (only with the player's say-so: config interact.adjust)
---------------------------------------------------------------------------
A.TARGETING = {
    { name = "SoftTargetInteract", value = "3" },
    { name = "SoftTargetInteractArc", value = "2" },
    { name = "SoftTargetInteractRange", value = "60" },
}

local function CVar(name)
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local v = F.Readable(C_CVar.GetCVar(name))
    return v ~= nil and tostring(v) or nil
end

local function ClientRecord()
    local db = S.db
    local rec = db and db.client
    if type(rec) ~= "table" or type(rec.saved) ~= "table" then return nil end
    return rec
end

function A.ApplyTargeting()
    if S.held or not S.Get("interact.adjust") or F.InCombat() then return end
    if not (C_CVar and C_CVar.SetCVar) or ClientRecord() or not S.db then return end
    local saved = {}
    for _, item in ipairs(A.TARGETING) do
        local before = CVar(item.name)
        if before ~= nil and before ~= item.value and C_CVar.SetCVar(item.name, item.value) ~= false then
            saved[#saved + 1] = { name = item.name, before = before, set = item.value }
        end
    end
    if #saved > 0 then S.db.client.saved = saved end
end

-- Puts each value back unless the player changed it since. Out of combat only.
function A.RestoreTargeting()
    local rec = ClientRecord()
    if not rec or not (C_CVar and C_CVar.SetCVar) or F.InCombat() then return end
    for _, item in ipairs(rec.saved) do
        if type(item) == "table" and type(item.name) == "string" and type(item.before) == "string" and CVar(item.name) == item.set then
            C_CVar.SetCVar(item.name, item.before)
        end
    end
    rec.saved = nil
end

-- True when keyboard-and-mouse interaction targeting is on now (nil when it can't be read).
function A.InteractionOn()
    local v = tonumber(CVar("SoftTargetInteract"))
    if v == nil then return nil end
    return v >= 2
end

---------------------------------------------------------------------------
-- Events (Main.lua wires them)
---------------------------------------------------------------------------
function A.OnChannelStart(unit, guid, spellID)
    if unit ~= "player" then return end
    if not (IsFishing(spellID) or A.Channel() == "fishing") then return end
    guid = F.Readable(guid)
    if line and type(guid) == "string" and line.guid == guid then return end
    -- Dedupe before starting a session: an old start replay must not reopen completed records.
    local accepted, why = Ses.Cast(guid)
    if not accepted and why ~= "unavailable" then return end
    local s = Ses.Current()
    line = { start = F.Clock(), guid = guid, sid = s and s.id, zone = Ses.Zone() }
    A.ApplyTargeting()
    A.Sync()
    A.Refresh()
    if F.Main and F.Main.Listen then F.Main.Listen() end
end

-- Settle a line once, including a manual session stop while the channel is still out.
-- This only records observed time; it never cancels or casts a spell.
function A.FinishTiming(sid)
    local l = line
    if not l or l.timed or (sid and l.sid ~= sid) then return end
    l.timed = true
    Ses.Line(F.Clock() - l.start, l.sid, l.zone)
end

function A.OnChannelStop(unit)
    if unit ~= "player" or not line then return end
    local l = line
    A.FinishTiming(l.sid)
    line = nil
    l.stop = F.Clock()
    lastLine, lastEnd = l, l.stop
    A.Sync()
    A.RestoreTargeting()
    A.Refresh()
    if F.Main and F.Main.Listen then F.Main.Listen() end
    if C_Timer and C_Timer.After then C_Timer.After(1.5, function() A.CheckMissed(l) end) end
end

-- A line that ended with no fishing loot window after it, and was not interrupted: nothing was caught.
function A.CheckMissed(l)
    if l.caught or l.interrupted or l.checked then return end
    local s = Ses.Current()
    if not s or s.id ~= l.sid then return end
    l.checked = true
    Ses.Lost("missed")
end

local function Once(guid)
    guid = F.Readable(guid)
    if type(guid) ~= "string" then return true end
    if counted[guid] then return false end
    counted[guid] = true
    return true
end

-- Late results from a stopped line belong to its old session, never the next session's idle clock.
local function OldResult(guid)
    guid = F.Readable(guid)
    local s = Ses.Current()
    for _, l in ipairs({ line or false, lastLine or false }) do
        if l and type(guid) == "string" and l.guid == guid then
            return not s or l.sid ~= s.id
        end
    end
    return false
end

function A.OnFailed(unit, guid, spellID)
    if unit ~= "player" or not IsFishing(spellID) then return end
    if OldResult(guid) or not Once(guid) then return end
    Ses.Lost("failed")
end

function A.OnInterrupted(unit, guid, spellID)
    if unit ~= "player" or not IsFishing(spellID) then return end
    local l = line or lastLine
    if l then l.interrupted = true end
    if OldResult(guid) or not Once(guid) then return end
    Ses.Lost("interrupted")
end

function A.OnCatch()
    local l = line or lastLine
    if l then l.caught = true end
end

function A.OnLootState(open, kind)
    looting = open
    -- the guard follows a fishing window only (auto-loot can close it just after the line ends); other loot never delays
    if not open and kind == "fishing" then lastEnd = math.max(lastEnd, F.Clock()) end
    A.Refresh()
end

function A.OnSoftTarget() A.Sync() end
function A.OnBindings() A.Sync() end
function A.OnSpells() A.ForgetSpell() end

-- Combat begins: while the game still allows it, take the overrides away and set the key up for the fight.
function A.OnCombatStart()
    fighting = true
    if F.InCombat() or not button then Wait() return end
    A.Sync(true)
    local macro = S.Get("gear.combatWeapons") and G.State() ~= "none" and G.RestoreMacro(true) or nil
    if macro then
        Arm(button, { kind = "restore", macro = macro })
        armedForCombat = "restore"
    else
        Arm(button, { kind = "none" })
        armedForCombat = nil
    end
    A.RestoreTargeting()
end

function OnRegen()
    waiting = false
    R:Off("PLAYER_REGEN_ENABLED", OnRegen)
    A.OnCombatEnd()
end

function A.OnCombatEnd()
    fighting = false
    armedForCombat = nil
    if F.InCombat() then Wait() return end
    if not button then A.Build() end
    if button then Arm(button, { kind = "none" }) end
    A.Sync()
    if G.State() == "pending" and not Ses.Current() then G.Restore("combat-ended") end
end

-- Everything this file put in the game, taken out (the addon is turned off).
function A.Teardown()
    if F.InCombat() then Wait() return end
    A.Sync(true)
    if button then Arm(button, { kind = "none" }) end
    A.RestoreTargeting()
end

-- Read only, for diagnostics.
function A.Status()
    local sp = A.Spell()
    return { state = A.state, line = line ~= nil, looting = looting, combat = fighting, presses = A.presses,
        last = A.last and (A.last.kind .. (A.last.why and (":" .. A.last.why) or "")) or nil,
        keys = A.Keys(), openKeys = A.Keys(A.OPEN_BINDING), reel = appliedSig:match("^(%a+)|") or "idle",
        spell = sp and sp.id or nil, built = button ~= nil, interaction = A.InteractionOn(),
        adjusting = ClientRecord() ~= nil }
end

-- Test support: the line's runtime state (read only).
function A.Line() return line, lastLine end
