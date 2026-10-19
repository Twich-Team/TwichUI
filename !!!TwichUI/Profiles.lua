-- TwichUI: profiles
-- Named sets of TwichUI's options. Any character on the account can use any of them; each character remembers
-- its own choice; characters that choose the same profile share it, on purpose. docs/profiles.md has the
-- design, which saved fields belong to a profile, and the checks still to make in the game.
--
-- Where things are (TwichUIDB from schema 2; Persist.lua checks the shape when it loads):
--   modules, ui, gear    the profile in use, where every feature and the settings window already read and write.
--                        They stay the same tables all session, so changing profile changes what is in them,
--                        never which tables they are, and nothing holding on to one sees another profile's.
--   profiles[name]       every other profile, a copy of its own: { modules = {}, ui = {}, gear = {} }
--   profileState         { live = the profile modules, ui and gear hold, newCharacters = the one a character
--                        without a choice of its own uses }
--   profileKeys[char]    "Name - Realm" = the profile that character uses
--
-- Never part of a profile, and never changed by anything here: the account-wide entries in ACCOUNT below, the
-- gear entries not in GEAR, and the rest of TwichUIDB (map pins and kept pins, the party pin session, sharing
-- records and the sending method, the welcome marker), and the other saved variables (the Journey Chronicle,
-- backups, Undo copies, your saved setup). Other addons' settings, RestedXP's and SpeakStone's included, are
-- never touched by a profile change: TwichUI's own options for them are.
--
-- What changes the options in use (a switch, Copy settings from, Reset) is refused in combat, checked here
-- when it runs, not only by the settings window. It is done as one step: every copy is made first, then plain
-- assignments put it in place, then each feature is told once (Apply). Nothing waits for later but what
-- always does: a switch whose feature needs a reload asks for one, as it does when clicked.

local R = TwichUI
local P = R.Persist
local PF = {}
R.Profiles = PF

-- Account-wide entries inside the profile groups: left where they are by every profile operation.
PF.ACCOUNT = {
    modules = {
        restedxpSkin = true,      -- turning it on or off chooses RestedXP's own theme (a RestedXP setting)
    },
    ui = {
        showAdvanced = true,      -- removed (Persist.lua deletes it on load): kept out of profiles so an old copy never travels in one
        easyFishingClient = true, -- removed with Easy Fishing (Persist.lua deletes it on load): kept out of profiles for the same reason
        reduceSettingsMotion = true, -- how the settings window itself moves: no fades
        settingsWindow = true,    -- where the settings window sits
        restedxpSkinState = true, -- the RestedXP theme to go back to: a record of RestedXP's setting, not a choice
        mageSell = true,          -- the never-sell list: a protection, which no profile change may lift
        guideWaypoint = true,     -- the waypoint each character placed: a record per character
        guideAuto = true,         -- whether each character's RestedXP guide was hidden by TwichUI: a record per character
        guideTracker = true,      -- the quest tracker Visibility each profile had before the guide set it to Mouseover: a record, not a choice
        restockAck = true,        -- your confirmation that vendor restocking may buy without asking: no profile change may give it
        mapToolsIntro = true,     -- that the map tool bar's once-only note was seen: a record, not a choice
        navTravel = true,         -- each character's Hearthstone bind point, for navigation: a record per character
    },
}
-- The gear entries that are a profile's. The rest stay account-wide: stat weights and priorities are kept
-- per class and talent tree, and the tree choice per character.
PF.GEAR = { glancePossible = true, futureLevels = true, reveal = true, strictness = true, bagStyle = true }

local GROUPS = { "modules", "ui", "gear" }

local function InProfile(group, key)
    if group == "gear" then return PF.GEAR[key] == true end
    return not PF.ACCOUNT[group][key]
end

local function PlainKey(k) local t = type(k) return t == "string" or t == "number" end
local function PlainValue(v) local t = type(v) return t == "string" or t == "number" or t == "boolean" or t == "table" end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local available, why = false, "loading"   -- why: "loading", "future", "failed", "damaged", "no-character"
local me                                  -- "Name - Realm", once known
local missing                             -- the name of a chosen profile that was gone at login, to tell once
local generation = 0                      -- bumped by every profile change (for callbacks that must not run stale)

local function Store()
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    local state, profiles, keys = db.profileState, db.profiles, db.profileKeys
    if type(state) == "table" and type(profiles) == "table" and type(keys) == "table" and type(state.live) == "string" then
        return db, state, profiles, keys
    end
end

-- Whether a usable profile has this exact name.
local function Exists(name)
    local _, state, profiles = Store()
    if not state or type(name) ~= "string" then return false end
    if name == state.live then return true end
    return type(profiles[name]) == "table" and P.ProfileName(name) == name
end

-- Whether a profile has this name, in any case ("raid" and "Raid" are the same name). except: a name to
-- leave out (the profile being renamed).
local function Taken(name, except)
    local lower = name:lower()
    for _, other in ipairs(PF.List()) do
        if other ~= except and other:lower() == lower then return true end
    end
    return false
end

local function CharacterKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. " - " .. realm
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- Whether profiles can be used this session; when not, a reason code (see PF.Explain).
function PF.Available() return available, why end

-- The profile this character uses (nil until it is known).
function PF.Current()
    local _, state = Store()
    return available and state and state.live or nil
end

-- This character, as profiles know it: "Name - Realm".
function PF.Character() return me end

-- Every usable profile name, sorted without regard to case.
function PF.List()
    local _, state, profiles = Store()
    if not state then return {} end
    local list = { state.live }
    for name, data in pairs(profiles) do
        if type(data) == "table" and P.ProfileName(name) == name and name ~= state.live then list[#list + 1] = name end
    end
    table.sort(list, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end)
    return list
end

PF.Exists = Exists

-- The characters whose choice is name, sorted; this character left out when othersOnly.
function PF.UsedBy(name, othersOnly)
    local _, _, _, keys = Store()
    local list = {}
    if not keys then return list end
    for char, chosen in pairs(keys) do
        if chosen == name and not (othersOnly and char == me) then list[#list + 1] = char end
    end
    table.sort(list)
    return list
end

-- The profile a character with no choice of its own starts with.
function PF.NewCharacterProfile()
    local _, state = Store()
    return state and state.newCharacters
end

-- Read only, for /tui diagnostics: counts, never names.
function PF.Snapshot()
    local _, state = Store()
    local current = PF.Current()
    return {
        available = available, reason = why, profiles = state and #PF.List() or 0,
        sharedWith = current and #PF.UsedBy(current, true) or 0, generation = generation,
    }
end

---------------------------------------------------------------------------
-- Copies. Each one shares no table with what it was made from: a profile is never another's, the defaults'
-- or the live tables' alias.
---------------------------------------------------------------------------
-- What the live tables hold of the profile in use.
local function Extract()
    local db = TwichUIDB
    local out = {}
    for _, group in ipairs(GROUPS) do
        local copy, src = {}, db[group]
        if type(src) == "table" then
            for k, v in pairs(src) do
                if PlainKey(k) and PlainValue(v) and InProfile(group, k) then copy[k] = P.DeepCopy(v) end
            end
        end
        out[group] = copy
    end
    return out
end

-- What the live tables will hold for a stored profile (or for nil: a new one). What it leaves out takes its
-- default, as for a new installation.
local function Prepare(data)
    local out = {}
    for _, group in ipairs(GROUPS) do
        local copy = {}
        local src = type(data) == "table" and type(data[group]) == "table" and data[group] or nil
        if src then
            for k, v in pairs(src) do
                if PlainKey(k) and PlainValue(v) and InProfile(group, k) then copy[k] = P.DeepCopy(v) end
            end
        end
        out[group] = copy
    end
    for k, v in pairs(R.DEFAULT_MODULES or {}) do
        if InProfile("modules", k) and type(out.modules[k]) ~= "boolean" then out.modules[k] = v end
    end
    local gearDefaults = R.GearPrefs and R.GearPrefs.DEFAULTS
    for k, v in pairs(gearDefaults or {}) do
        if InProfile("gear", k) and out.gear[k] == nil then out.gear[k] = v end
    end
    return out
end

-- Puts a prepared profile into the live tables, in place. Plain assignments only; account-wide entries stay.
local function Commit(incoming)
    local db = TwichUIDB
    for _, group in ipairs(GROUPS) do
        if type(db[group]) ~= "table" then db[group] = {} end
        local live = db[group]
        for k in pairs(live) do
            if InProfile(group, k) then live[k] = nil end
        end
        for k, v in pairs(incoming[group]) do live[k] = v end
    end
end

-- This character moves to another stored profile: the one in use is stored, the other one is put in place.
local function Swap(target)
    local _, state, profiles, keys = Store()
    local outgoing = Extract()
    local incoming = Prepare(profiles[target])
    profiles[target] = nil
    profiles[state.live] = outgoing
    Commit(incoming)
    state.live = target
    keys[me] = target
end

---------------------------------------------------------------------------
-- Telling the addon. Each feature registers what a profile change means for it, once, in one of three
-- phases, after the on/off switches have been settled through the options:
--   look    colors, fonts, textures and the like of what is drawn
--   layout  sizes and places
--   views   texts and windows that show settings
-- fn reads the settings as they are now; it must not change one.
---------------------------------------------------------------------------
local PHASES = { "look", "layout", "views" }
local appliers = { look = {}, layout = {}, views = {} }
local registered = {}
local listeners = {}

function PF.OnApply(phase, name, fn)
    assert(appliers[phase], "a profile phase: look, layout or views")
    if registered[name] then return end
    registered[name] = true
    local list = appliers[phase]
    list[#list + 1] = { name = name, fn = fn }
end

-- fn(kind) after anything about profiles changed (their list, names, which one is in use), for what shows them.
function PF.OnChange(fn) listeners[#listeners + 1] = fn end

local function Changed(kind)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, kind)
        if not ok then R.Fault("profiles view", err) end
    end
end

-- Every feature follows the options now in place. Returns the names of the parts that failed (each one was
-- reported to the error handler); the others were still told.
local function Apply()
    generation = generation + 1
    local failed = {}
    for _, key in ipairs(R.Switches.Sync()) do failed[#failed + 1] = "switch " .. key end
    for _, phase in ipairs(PHASES) do
        for _, entry in ipairs(appliers[phase]) do
            local ok, err = pcall(entry.fn)
            if not ok then
                failed[#failed + 1] = entry.name
                R.Fault("profile " .. entry.name, err)
            end
        end
    end
    -- an open settings window shows the new values (one that was never opened has nothing to redraw)
    local UI = R.SettingsUI
    if UI and UI.RefreshValues then
        local ok, err = pcall(UI.RefreshValues)
        if not ok then R.Fault("profile settings window", err) end
    end
    return failed
end

local function Finish(kind)
    local failed = Apply()
    local info = { failed = failed, reload = R.Switches.ReloadPending() }
    if #failed > 0 and R.Life then R.Life.Note("profile-apply-failed") end
    Changed(kind)
    return true, kind, info
end

-- Every feature follows the options now in place, after something other than a profile operation changed
-- them as a whole (importing a shared configuration: setup/TwichConfig.lua). The same steps as a profile
-- change; the caller has already written the values, in place, with plain assignments.
-- Returns true, kind, { failed, reload }.
function PF.Refresh(kind)
    return Finish(kind or "refresh")
end

---------------------------------------------------------------------------
-- Operations. Each returns true, what was done, { failed, reload }, or false and a reason code (PF.Explain).
---------------------------------------------------------------------------
local function Guard(changesOptions)
    if not available then return false, why end
    if changesOptions and InCombatLockdown and InCombatLockdown() then return false, "combat" end
    return true
end

-- A name for a new or renamed profile: trimmed, checked, and not one already in use (in any case).
local function NewName(raw, except)
    local name, reason = P.ProfileName(raw)
    if not name then return nil, reason end
    if Taken(name, except) then return nil, "taken" end
    return name
end

-- This character uses another profile.
function PF.Switch(name)
    local ok, code = Guard(true)
    if not ok then return false, code end
    if not Exists(name) then return false, "not-found" end
    if name == PF.Current() then return false, "same" end
    Swap(name)
    return Finish("switch")
end

-- A new profile with the default options; this character uses it.
function PF.Create(raw)
    local ok, code = Guard(true)
    if not ok then return false, code end
    local name, reason = NewName(raw)
    if not name then return false, reason end
    local _, state, profiles, keys = Store()
    local outgoing = Extract()
    local incoming = Prepare(nil)
    profiles[state.live] = outgoing
    Commit(incoming)
    state.live = name
    keys[me] = name
    return Finish("create")
end

-- A new, independent copy of the profile in use; this character uses it. No option changes, so nothing is
-- applied: the one being left is stored as a copy and the live tables keep their values under the new name.
function PF.Duplicate(raw)
    local ok, code = Guard(true)
    if not ok then return false, code end
    local name, reason = NewName(raw)
    if not name then return false, reason end
    local _, state, profiles, keys = Store()
    profiles[state.live] = Extract()
    state.live = name
    keys[me] = name
    generation = generation + 1
    Changed("duplicate")
    return true, "duplicate", { failed = {}, reload = false }
end

-- The profile in use takes a copy of another's options and keeps its own name (and its other users).
function PF.CopyFrom(source)
    local ok, code = Guard(true)
    if not ok then return false, code end
    if not Exists(source) then return false, "not-found" end
    if source == PF.Current() then return false, "same" end
    local _, _, profiles = Store()
    Commit(Prepare(profiles[source]))
    return Finish("copy")
end

-- The profile in use goes back to the default options.
function PF.Reset()
    local ok, code = Guard(true)
    if not ok then return false, code end
    Commit(Prepare(nil))
    return Finish("reset")
end

-- A new name for a profile. Every character's choice, and the one for new characters, follow it. Changes no
-- option, so it is allowed in combat.
function PF.Rename(old, raw)
    local ok, code = Guard(false)
    if not ok then return false, code end
    if not Exists(old) then return false, "not-found" end
    local name, reason = NewName(raw, old)
    if not name then return false, reason end
    if name == old then return false, "unchanged" end
    local _, state, profiles, keys = Store()
    if old == state.live then
        state.live = name
    else
        profiles[name] = profiles[old]
        profiles[old] = nil
    end
    if state.newCharacters == old then state.newCharacters = name end
    for char, chosen in pairs(keys) do
        if chosen == old then keys[char] = name end
    end
    Changed("rename")
    return true, "rename", { name = name }
end

-- Removes a profile no one uses. Refused for the one in use, the one new characters start with, and one any
-- character has chosen (third value: those characters). Changes no option, so it is allowed in combat.
function PF.Delete(name)
    local ok, code = Guard(false)
    if not ok then return false, code end
    if not Exists(name) then return false, "not-found" end
    local _, state, profiles = Store()
    if name == state.live then return false, "current" end
    if name == state.newCharacters then return false, "new-characters" end
    local users = PF.UsedBy(name)
    if #users > 0 then return false, "in-use", users end
    profiles[name] = nil
    Changed("delete")
    return true, "delete"
end

-- Forgets which profile another character chose, so that a profile only it used can be deleted. The
-- character then starts with the profile new characters use, as one with no choice does. Refused for this
-- character (its choice is the profile in use), and for a name that isn't a recorded choice. Changes no
-- option, so it is allowed in combat. Used by the Saved Data Explorer's advanced cleanup.
function PF.Forget(char)
    local ok, code = Guard(false)
    if not ok then return false, code end
    local _, _, _, keys = Store()
    if type(char) ~= "string" or keys[char] == nil then return false, "not-found" end
    if char == me then return false, "this-character" end
    keys[char] = nil
    Changed("forget")
    return true, "forget"
end

---------------------------------------------------------------------------
-- Words for the codes above, for chat and the options page.
---------------------------------------------------------------------------
local EXPLAIN = {
    combat = "Profile changes are unavailable during combat.",
    loading = "Profiles aren't ready yet. Try again in a moment.",
    future = "Profiles aren't available this session: your saved settings were made by a newer TwichUI.",
    failed = "Profiles aren't available this session: TwichUI couldn't upgrade its saved settings. It will try again next time.",
    damaged = "Profiles aren't available this session: their saved data couldn't be read.",
    ["no-character"] = "Profiles aren't available this session: the game didn't say which character this is.",
    empty = "Type a name for the profile.",
    long = ("Profile names can be up to %d characters."):format(P.PROFILE_NAME_MAX),
    characters = "Profile names can't contain | or control characters.",
    taken = "There is already a profile with that name.",
    ["not-found"] = "That profile doesn't exist any more.",
    same = "This character is already using that profile.",
    unchanged = "That is already its name.",
    current = "The profile you are using can't be deleted. Switch to another one first.",
    ["new-characters"] = "New characters start with this profile, so it can't be deleted.",
    ["in-use"] = "Another character uses this profile, so it can't be deleted.",
    ["this-character"] = "This character's choice is the profile in use. Switch profile instead.",
}

function PF.Explain(code, users)
    if code == "in-use" and type(users) == "table" and #users > 0 then
        local shown = {}
        for i = 1, math.min(#users, 5) do shown[i] = users[i] end
        local more = #users > 5 and (" and %d more"):format(#users - 5) or ""
        return ("It can't be deleted while %s use%s it. Switch %s to another profile first."):format(
            table.concat(shown, ", ") .. more, #users == 1 and "s" or "", #users == 1 and "that character" or "those characters")
    end
    return EXPLAIN[code] or "That couldn't be done."
end

---------------------------------------------------------------------------
-- Choosing this character's profile when the saved variables load
---------------------------------------------------------------------------
-- The profile this character should use: its own choice, or (none yet, or gone) the one for new characters.
local function Choice()
    local _, state, _, keys = Store()
    local chosen = keys[me]
    if chosen ~= nil and not Exists(chosen) then
        missing = chosen
        chosen = nil
        P.Repair("profile-selection-missing")
    end
    return chosen or state.newCharacters
end

local SelectLate

local function AfterCombat()
    R:Off("PLAYER_REGEN_ENABLED", AfterCombat)
    SelectLate()
end

-- Known only after login (the game didn't say who this is at load): switched like any change, out of combat.
-- Until then the session runs on the profile in use, and profile actions wait ("loading").
function SelectLate()
    local target = Choice()
    local _, state, _, keys = Store()
    keys[me] = target
    if target == state.live then
        available, why = true, nil
        Changed("select")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        R:On("PLAYER_REGEN_ENABLED", AfterCombat)   -- one registration, however often this runs
        return
    end
    Swap(target)
    available, why = true, nil
    Finish("select")
end

local function OnLogin()
    if available or me then return end
    me = CharacterKey()
    if not me then why = "no-character" return end
    SelectLate()
end

-- Called once by Core.lua as soon as Persist.lua has loaded the saved variables, before any feature starts.
-- Only data moves here: the features read the result when they start, as on any load.
function PF.Load()
    local outcome = P.Report().main.outcome
    if outcome == "future" or outcome == "failed" then why = outcome return end
    if outcome ~= "fresh" and outcome ~= "current" and outcome ~= "migrated" then why = "damaged" return end
    if not Store() then why = "damaged" return end
    me = CharacterKey()
    if not me then
        R:On("PLAYER_LOGIN", OnLogin)
        return
    end
    local target = Choice()
    local _, state, _, keys = Store()
    keys[me] = target
    if target ~= state.live then Swap(target) end
    available, why = true, nil
end

-- Says once, at login, when this character's profile was gone and it now uses another.
R:On("PLAYER_LOGIN", function()
    if not missing then return end
    local now = PF.Current()
    if now then
        R.Print("this character's profile \"%s\" no longer exists, so it uses \"%s\". Choose another in /tui options (Profiles).", missing, now)
    end
    missing = nil
end)

-- For callbacks that must notice a profile change since they were scheduled.
function PF.Generation() return generation end
