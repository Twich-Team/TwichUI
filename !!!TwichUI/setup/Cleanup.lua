-- TwichUI: Saved Data Explorer, advanced cleanup (core)
-- An opt-in way to remove entries from TwichUI's own saved data, built on the read-only explorer
-- (setup/Explorer.lua) and drawn by setup/ExplorerWindow.lua. Everything here is on demand: nothing runs
-- while the explorer is closed, nothing is scanned continuously, and nothing is deleted until the person
-- has turned advanced cleanup on and then confirmed one exact, freshly checked target.
--
-- What it will and will not remove is decided in one place, CL.Policy, by the variable and the exact path
-- (never by what a row looks like). A target is either
--   * removed by the owning module's own function (a backup by Restore's Delete, a profile by
--     Profiles.Delete, a map pin by Pins.RemoveLocal, ...), which keeps that module's own rules, or
--   * a small allow-listed entry nothing depends on (a cache, an obsolete marker, a note), removed directly.
-- Everything else is protected, and says why: the roots, the schema and profile bookkeeping, the options of
-- the profile in use, current-character structures, hand-offs between loads, entries a newer TwichUI wrote.
--
-- Safety rules this file keeps:
--   * Targets are paths of keys resolved with rawget, one step at a time, with their key types kept. No
--     text is ever turned into code.
--   * A target is described ("review"), counted by a sliced job, and then confirmed. Before anything is
--     removed it is resolved again, run through the policy again and fingerprinted again; if anything
--     differs, nothing is removed and a fresh review is needed. A batch is checked as a whole first.
--   * Suggestions are snapshots of what was looked at. They are never approvals: nothing is picked by default.
--   * Recovery is one in-memory copy of the last cleanup, bounded in size, never saved and never sent.
--     Where it cannot be kept, the review says the removal cannot be undone.
--
-- Not saved: the mode, the review, the picks and the recovery copy live only in this file's memory.

local R = TwichUI
local EX, ST, RS, SD = R.Explorer, R.Setups, R.Restore, R.StoredData
local CL = {}
R.Cleanup = CL

CL.DIGEST_VISITS = 100000     -- entries walked to fingerprint a target; also the bound of the synchronous recheck
CL.RECOVERY_VALUES = 50000    -- most entries kept for Undo (one cleanup's worth, in memory)
CL.MAX_BATCH = 200            -- most targets in one confirmation
CL.MAX_CANDIDATES = 400       -- most suggestions listed (the rest are counted)
CL.MAX_INFO = 150             -- most informational rows

local function G(name) return rawget(_G, name) end
local function Readable(t) return not (canaccesstable and not canaccesstable(t)) end
local function When(t) return type(t) == "number" and t == t and date("%b %d %Y, %H:%M", t) or nil end
local function Count(t) local n = 0 if type(t) == "table" then for _ in next, t do n = n + 1 end end return n end

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

---------------------------------------------------------------------------
-- The mode: off until a person turns it on, never saved
---------------------------------------------------------------------------
local enabled = false
local listeners = {}
function CL.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then geterrorhandler()(err) end
    end
end

function CL.Enabled() return enabled end

-- The confirmation dialog passes true after the person ticked the acknowledgment and pressed the button.
-- Nothing else turns it on: not opening the explorer, not a setting, not a scan.
function CL.Enable(acknowledged)
    if acknowledged ~= true then return false, "needs-acknowledgment" end
    if enabled then return true end
    enabled = true
    Changed("mode")
    return true
end

-- Back to read-only: pending work stops, picks are forgotten (a pick is an approval, and approvals end with
-- the mode). The recovery copy stays, but can only be used while the mode is on.
function CL.Disable()
    local was = enabled
    enabled = false
    EX.Cancel("cleanup-measure")
    CL.picks = {}
    if was then Changed("mode") end
end

-- The explorer closed: everything this module held goes, except the recovery copy of the last cleanup.
function CL.Reset()
    CL.Disable()
    EX.Cancel("cleanup-scan")
    CL.results = nil
    CL.scanning = nil
end

CL.picks = {}
CL.results = nil

-- The explorer's own Release (window closed) also ends the mode and drops the suggestions.
local baseRelease = EX.Release
function EX.Release()
    CL.Reset()
    return baseRelease()
end

---------------------------------------------------------------------------
-- Addresses: a saved variable and the keys down to an entry. Always resolved key by key with rawget.
---------------------------------------------------------------------------
-- Returns parent, value (parent is nil for the variable itself), or nil when it isn't there (any more).
function CL.Resolve(var, keys)
    local t = G(var)
    if type(t) ~= "table" then return nil end
    local parent
    for i = 1, #keys do
        if type(t) ~= "table" or not Readable(t) then return nil end
        parent = t
        t = rawget(t, keys[i])
        if t == nil then return nil end
    end
    return parent, t
end

-- The saved variable and keys a source's root is at, or nil and why.
function CL.SourceAddress(source)
    local id, kind = source.id, source.kind
    if id == "settings" then return "TwichUIDB", {} end
    if kind == "preview" then return nil, "This is built on request and isn't saved, so there is nothing to delete." end
    if kind == "restore" then
        local point, db = source.Root(), G("TwichUIRestoreDB")
        if type(point) == "table" and type(db) == "table" and type(db.points) == "table" then
            for i, p in ipairs(db.points) do
                if rawequal(p, point) then return "TwichUIRestoreDB", { "points", i } end
            end
        end
        return nil, "That backup isn't there any more."
    end
    if kind == "undo" then return "TwichUIBackupDB", { id:sub(6) } end
    if kind == "mine" then return "TwichUIShareDB", { "pack" } end
    if kind == "received" then return "TwichUIDB", { "setup", "received", id:sub(6) } end
    if kind == "chronicle" then return "TwichUIChronicleDB", {} end
    if kind == "var" then return source.label, {} end
    return nil, "That source can't be deleted from."
end

---------------------------------------------------------------------------
-- Policy: what may be removed, by what, and what follows
---------------------------------------------------------------------------
local NO_RELOAD = "No reload is needed: TwichUI reads this each time it uses it. The change reaches the saved file when you reload or log out."

local function Block(reason, dataset) return { ok = false, reason = reason, dataset = dataset } end

local function PendingSource(key)
    local p = ST.db and ST.db.pending
    return type(p) == "table" and p.source == key
end

local function PendingChar(char)
    local p = ST.db and ST.db.pending
    return type(p) == "table" and p.char == char
end

-- Redraws the views of TwichUI that list what was removed. Only ones that are open do anything.
local function RefreshSharing()
    local W = R.Window
    if W and W.Refresh then pcall(W.Refresh, W) end
end
local function RefreshSettings()
    local UI = R.SettingsUI
    if UI and UI.RefreshValues then pcall(UI.RefreshValues) end
end

local function RawRun(var, keys)
    return function()
        local parent, value = CL.Resolve(var, keys)
        if parent == nil or value == nil then return false, "It isn't there any more." end
        rawset(parent, keys[#keys], nil)
        return true
    end
end

local SETTINGS_NOTE = "These are the options of the profile this character uses. Change them in TwichUI's settings window; a page's Reset puts the defaults back through the code that owns them."

local TOP_PROTECTED = {
    schema = "The saved data's layout number. TwichUI reads it at every load to decide how to upgrade; without it the data would be treated as unversioned.",
    welcome = "The older first-run marker. TwichUI reads it to tell an existing installation from a new one.",
    onboarding = "Where the first-install layout setup has got to. It decides whether the setup is offered by itself; /tui layout firstrun reset starts it again.",
    profileState = "Says which profile is in use and which one new characters start with. Required by the profiles code.",
    modules = SETTINGS_NOTE, ui = SETTINGS_NOTE, gear = SETTINGS_NOTE,
    shareTransport = "The chosen sending method, a live setting. Change it in Share setup.",
    profiles = "Holds every profile but the one in use. Delete one profile at a time.",
    profileKeys = "Holds each character's profile choice. Forget one character's choice at a time.",
    pins = "Holds your map pins and the party session. Remove one pin at a time.",
    npcs = "Holds the vendors and trainers you noted or were sent. Forget one on the map (click it) or clear them in the Vendors and trainers options.",
    setup = "Holds the sharing records. Remove received setups and other entries one at a time.",
    storedData = "Holds what the Addon data scan noted. Forget one note at a time.",
}

local SETUP_PROTECTED = {
    recommend = "Which recommended addons are ticked for your setup.",
    pending = "A setup or backup queued to be applied at the next load. Cancel it from the sharing window, not here.",
    scanNext = "A one-shot flag for the next load.",
    restoreNext = "A one-shot flag for the next load.",
    lastScan = "When the last settings search ran.",
    eui = "EllesmereUI profile bookkeeping, owned by the sharing code.",
}

-- The facts about a table a target is, in words: counts and dates only (nothing personal).
local function PackFacts(p)
    local facts = {}
    if type(p) ~= "table" then return facts end
    local usable = 0
    for name, e in next, type(p.tables) == "table" and p.tables or {} do
        if ST.ValidEntry(name, e) then usable = usable + 1 end
    end
    facts[#facts + 1] = ("%d settings tables (%d TwichUI can use)"):format(Count(p.tables), usable)
    return facts
end

-- Returns a plan for the entry at var + keys (value is what is there now):
--   { ok, reason, dataset, what, via, effect, consequences, reload, persisted, ident, opKey, also, personal,
--     facts, restore, run, gone, refresh, restoreCheck }
-- ok = false means protected, and reason says why. Never changes anything.
function CL.Policy(var, keys, value)
    local P = R.Persist
    local n = #keys
    if P and P.IsHeld(var) then
        return Block("A newer TwichUI wrote this data, so it was set aside for this session and is handed back unchanged at logout. Nothing in it can be removed from here.")
    end
    if n == 0 then
        return Block("This is a whole saved variable, which TwichUI needs. Remove entries inside it instead.")
    end
    local k1, k2, k3 = keys[1], keys[2], keys[3]

    ---------------------------------------------------------------- backups
    if var == "TwichUIRestoreDB" then
        if k1 == "ownUndo" then return Block("The Undo copy of TwichUI's own settings from before your last restore. Remove it from Saved data, where it is listed with what it holds.", "Backups") end
        if k1 == "applyOwn" then return Block("A restore of TwichUI's settings queued for the next reload.", "Backups") end
        if k1 ~= "points" then return Block("Not an entry this version of TwichUI recognises as removable. It may belong to a newer version, so it is left alone.", "Backups") end
        if n == 1 then return Block("The list of backups. Delete one backup at a time.", "Backups") end
        if n > 2 then return Block("A backup is deleted whole, never edited.", "Backups") end
        local id = type(value) == "table" and value.id
        if type(id) ~= "string" then return Block("TwichUI can't read this entry as a backup, so it isn't offered for deletion.", "Backups") end
        if PendingSource("restore:" .. id) then
            return Block("A restore of this backup is queued for the next reload. Cancel or finish it first.", "Backups")
        end
        local label = type(value.name) == "string" and value.name or "Backup"
        return {
            ok = true, dataset = "Backups", what = ("Backup \"%s\""):format(label), via = "Backups' own Delete",
            ident = "restore:" .. id, restore = "list", refresh = RefreshSharing,
            facts = { When(value.created) and ("Made " .. When(value.created)) or "Date not recorded", unpack(PackFacts(value)) },
            effect = "Removes this backup: the addon settings and TwichUI settings copied into it.",
            consequences = {
                "You can no longer restore from it. Settings you already restored stay as they are.",
                "Other backups and Undo copies are not affected.",
            },
            reload = NO_RELOAD,
            run = function()
                if not RS.Get(id) then return false, "It isn't there any more." end
                RS:Delete(id)
                return true
            end,
        }
    end

    if var == "TwichUIBackupDB" then
        if n > 1 then return Block("An Undo copy is deleted whole, never edited.", "Backups") end
        local char = k1
        if type(char) ~= "string" or type(value) ~= "table" then return Block("TwichUI can't read this as an Undo copy.", "Backups") end
        if PendingChar(char) then
            return Block("A setup is queued for this character's next load, and that load needs its Undo copy. Let it finish first.", "Backups")
        end
        local mine = char == ST.CharKey()
        return {
            ok = true, dataset = "Backups", what = "Undo copy for one character", via = "Saved data's own Delete", personal = true,
            ident = "undo:" .. char, restore = "set", refresh = RefreshSharing,
            facts = { When(value.created) and ("Taken " .. When(value.created)) or "Date not recorded",
                ("%d settings tables"):format(Count(value.tables)) },
            effect = "Removes that character's Undo copy: the settings it had before it last applied a setup.",
            consequences = {
                mine and "This is this character's own Undo copy. Undo in Backups will not be available until the next apply makes a new one."
                    or "That character can no longer undo its last apply.",
                "Restore points are not affected.",
            },
            reload = NO_RELOAD,
            run = function()
                local b = G("TwichUIBackupDB")
                if type(b) ~= "table" or b[char] == nil then return false, "It isn't there any more." end
                ST:DeleteBackup(char)
                return true
            end,
        }
    end

    if var == "TwichUIShareDB" then
        if k1 ~= "pack" then return Block("Not an entry this version of TwichUI recognises as removable. It may belong to a newer version, so it is left alone.", "Your saved setup") end
        if n > 1 then return Block("Your saved setup is deleted whole, never edited. Save it again from Share setup to change it.", "Your saved setup") end
        if type(value) ~= "table" then return Block("TwichUI can't read this as a saved setup.", "Your saved setup") end
        return {
            ok = true, dataset = "Your saved setup", what = "Your saved setup", via = "Saved data's own Delete",
            ident = "mine", restore = "set", refresh = RefreshSharing,
            facts = { When(value.created) and ("Saved " .. When(value.created)) or "Date not recorded", unpack(PackFacts(value)) },
            effect = "Removes the setup Send shares.",
            consequences = {
                "Send has nothing to send until you press Save setup again. Friends keep the copy they already have.",
                "Nothing you have applied or restored changes.",
            },
            reload = NO_RELOAD,
            run = function()
                local s = G("TwichUIShareDB")
                if type(s) ~= "table" or s.pack == nil then return false, "It isn't there any more." end
                ST:DeleteMine()
                return true
            end,
        }
    end

    ---------------------------------------------------------------- the Chronicle
    if var == "TwichUIChronicleDB" then
        if k1 ~= "chars" then
            return Block("The Chronicle's own bookkeeping. It isn't offered for deletion.", "Journey Chronicle")
        end
        if n == 1 then return Block("Holds every character's record. Remove one character's record at a time.", "Journey Chronicle") end
        if n > 2 then
            return Block("Entries and notes are managed in the Chronicle window, where each one has its own controls. Only a whole record of another character can be removed here.", "Journey Chronicle")
        end
        local key = k2
        local C = R.Chronicle
        if type(key) ~= "string" or type(value) ~= "table" then return Block("TwichUI can't read this as a character's record.", "Journey Chronicle") end
        if C and key == C.CharKey() then
            return Block("This is the character you are playing; its record is in use. Use the Chronicle window to manage its entries.", "Journey Chronicle")
        end
        local entries, notes, latest = 0, 0, nil
        for _, e in ipairs(type(value.entries) == "table" and value.entries or {}) do
            if type(e) == "table" then
                entries = entries + 1
                if e.kind == "note" then notes = notes + 1 end
                if type(e.t) == "number" and (not latest or e.t > latest) then latest = e.t end
            end
        end
        local consequences = {
            "If that character still exists, it starts a new, empty Chronicle the next time it logs in, and its tracking progress (what it already wrote) is forgotten.",
            "Other characters' records and your settings are not affected. The Chronicle is never part of backups or sharing, so no copy of this exists elsewhere.",
        }
        if notes > 0 then
            table.insert(consequences, 1, ("This record holds %d note%s you wrote yourself. They are removed with it."):format(notes, notes == 1 and "" or "s"))
        end
        return {
            ok = true, dataset = "Journey Chronicle", what = "Another character's Chronicle record", via = "the Chronicle's own forget",
            personal = true, ident = "chronicle:" .. key, restore = "set",
            facts = { ("%d entr%s, %d of them your notes"):format(entries, entries == 1 and "y" or "ies", notes),
                latest and ("Latest entry " .. When(latest)) or "No dated entries" },
            effect = "Removes one other character's whole Chronicle record: its entries, your notes there and its tracking state.",
            consequences = consequences, reload = NO_RELOAD,
            run = function()
                local ok, why = C.Forget(key)
                if ok then return true end
                return false, ({ current = "That is the character you are playing now.", gone = "It isn't there any more.",
                    held = "A newer TwichUI's data is set aside this session." })[why] or "TwichUI declined."
            end,
        }
    end

    ---------------------------------------------------------------- settings
    if var ~= "TwichUIDB" then return Block("Not a variable TwichUI cleans up.") end

    if k1 == "profiles" then
        if n == 1 then return Block(TOP_PROTECTED.profiles, "Profiles") end
        if n > 2 then return Block("A profile is deleted whole. To change what is in one, switch to it and use the settings window.", "Profiles") end
        local PF = R.Profiles
        local name = k2
        if not PF then return Block("Profiles aren't available.", "Profiles") end
        local avail, why = PF.Available()
        if not avail then return Block(PF.Explain(why), "Profiles") end
        if type(name) ~= "string" or type(value) ~= "table" or R.Persist.ProfileName(name) ~= name then
            return Block("TwichUI can't read this as a profile. It tidies unreadable ones itself when it loads.", "Profiles")
        end
        if name == PF.Current() then return Block(PF.Explain("current"), "Profiles") end
        if name == PF.NewCharacterProfile() then return Block(PF.Explain("new-characters"), "Profiles") end
        local users = PF.UsedBy(name)
        if #users > 0 then
            return Block(("%d saved character choice%s use this profile. Switch %s to another profile, or forget %s choice, first."):format(
                #users, #users == 1 and "" or "s", #users == 1 and "that character" or "those characters", #users == 1 and "its" or "their"), "Profiles")
        end
        return {
            ok = true, dataset = "Profiles", what = ("Profile \"%s\""):format(name), via = "Profiles' own Delete",
            ident = "profile:" .. name, restore = "set", refresh = RefreshSettings,
            restoreCheck = function()
                -- names compare without regard to case, as Profiles' own do
                for _, other in ipairs(PF.List()) do
                    if other:lower() == name:lower() then return false, "A profile with that name exists now." end
                end
                return true
            end,
            facts = { "No saved character choice uses it" },
            effect = "Removes this saved set of TwichUI options.",
            consequences = {
                "Its option values (modules, appearance, gear preferences) are gone. The profile in use and every other profile are not changed.",
                "Map pins, backups and the Chronicle are not part of a profile and are not affected.",
            },
            reload = NO_RELOAD,
            run = function()
                local ok, code = PF.Delete(name)
                if ok then return true end
                return false, PF.Explain(code)
            end,
        }
    end

    if k1 == "profileKeys" then
        if n == 1 then return Block(TOP_PROTECTED.profileKeys, "Profiles") end
        if n > 2 then return Block("A character's choice is one name; there is nothing inside it to remove.", "Profiles") end
        local PF = R.Profiles
        if not PF then return Block("Profiles aren't available.", "Profiles") end
        local avail, why = PF.Available()
        if not avail then return Block(PF.Explain(why), "Profiles") end
        if k2 == PF.Character() then
            return Block("This is the character you are playing. Its choice is the profile in use; switch profile in the settings window instead.", "Profiles")
        end
        if type(k2) ~= "string" or type(value) ~= "string" then return Block("TwichUI can't read this as a character's choice.", "Profiles") end
        local char, chosen = k2, value
        local fallback = PF.NewCharacterProfile()
        return {
            ok = true, dataset = "Profiles", what = "A character's recorded profile choice", via = "Profiles' own Forget", personal = true,
            ident = "choice:" .. char, restore = "set", refresh = RefreshSettings,
            restoreCheck = function()
                if not PF.Exists(chosen) then return false, "That profile no longer exists." end
                return true
            end,
            facts = { PF.Exists(chosen) and ("Chose profile \"" .. chosen .. "\"") or ("Chose \"" .. chosen .. "\", which no longer exists") },
            effect = "Forgets which profile that character chose.",
            consequences = {
                ("If that character still exists, it uses the profile new characters start with (\"%s\") the next time it logs in."):format(fallback or "?"),
                "The profile it had chosen is not deleted. If no one else uses it, it can be deleted afterwards.",
            },
            reload = NO_RELOAD,
            run = function()
                local ok, code = PF.Forget(char)
                if ok then return true end
                return false, PF.Explain(code)
            end,
        }
    end

    if k1 == "pins" then
        if k2 ~= "list" then
            if k2 == "session" then return Block("The party session carried over a reload. It belongs to the group you are in and ends with it.", "Map pins") end
            if k2 == "nextId" then return Block("The counter that keeps pin ids from being reused. Required.", "Map pins") end
            if n == 1 then return Block(TOP_PROTECTED.pins, "Map pins") end
            return Block("Not an entry this version of TwichUI recognises as removable.", "Map pins")
        end
        if n == 2 then return Block("The list of your local pins. Remove one pin at a time.", "Map pins") end
        if n > 3 then return Block("A pin is removed whole. Edit it in the pin editor.", "Map pins") end
        local PN = R.Pins
        if not PN then return Block("Map pins aren't available.", "Map pins") end
        local usable = false
        for _, p in ipairs(PN.LocalPins()) do if rawequal(p, value) then usable = true break end end
        if not usable then
            return Block("TwichUI can't read this pin. It may have been written by a newer version, so it is left alone.", "Map pins")
        end
        local id = value.id
        if PN.IsKept(value) then
            return Block("This pin is kept (protected). Turn Keep off in the pin editor first; cleanup never overrides it.", "Map pins")
        end
        return {
            ok = true, dataset = "Map pins", what = "A local map pin", via = "Pins' own Remove", personal = false,
            ident = "pin:" .. id, restore = "list", refresh = function() if PN.Changed then PN.Changed() end end,
            facts = { type(value.name) == "string" and ("Named \"" .. value.name .. "\"") or "Unnamed",
                When(value.created) and ("Made " .. When(value.created)) or "Date not recorded" },
            effect = "Removes this pin from your saved local pins.",
            consequences = {
                "It disappears from your map and pin lists. A group copy of it, if you shared it, stays with your party; nothing is sent.",
            },
            reload = NO_RELOAD,
            run = function()
                local ok, why = PN.RemoveLocal(id)
                if ok then return true end
                return false, why == "kept" and "It is kept (protected)." or "It isn't there any more."
            end,
        }
    end

    if k1 == "setup" then
        if n == 1 then return Block(TOP_PROTECTED.setup, "Sharing records") end
        if k2 == "received" then
            if n == 2 then return Block("Holds every received setup. Remove one at a time.", "Sharing records") end
            if n > 3 then return Block("A received setup is removed whole, never edited.", "Sharing records") end
            local sender = k3
            if type(sender) ~= "string" or type(value) ~= "table" then return Block("TwichUI can't read this as a received setup.", "Sharing records") end
            if PendingSource("recv:" .. sender) then
                return Block("Applying this setup is queued for the next reload. Cancel or finish that first.", "Sharing records")
            end
            return {
                ok = true, dataset = "Sharing records", what = "A setup a friend sent you", via = "Saved data's own Delete", personal = true,
                ident = "recv:" .. sender, restore = "set", refresh = RefreshSharing,
                facts = { When(value.received) and ("Received " .. When(value.received)) or "Date received not recorded", unpack(PackFacts(value)) },
                effect = "Removes the setup kept from that friend.",
                consequences = {
                    "Settings you already applied from it stay. They can send it again if you want it back.",
                },
                reload = NO_RELOAD,
                run = function()
                    local s = ST.db
                    if not (s and type(s.received) == "table" and s.received[sender] ~= nil) then return false, "It isn't there any more." end
                    ST:RemoveReceived(sender)
                    return true
                end,
            }
        end
        if k2 == "trusted" then
            if n == 2 then return Block("The senders you let apply automatically. Remove one at a time.", "Sharing records") end
            if n > 3 then return Block("Nothing inside this entry can be removed.", "Sharing records") end
            if type(k3) ~= "string" then return Block("TwichUI can't read this entry.", "Sharing records") end
            return {
                ok = true, dataset = "Sharing records", what = "An always-accept sender", via = "a direct removal of this entry",
                personal = true, ident = "trusted:" .. k3, restore = "set", refresh = RefreshSharing,
                facts = { "A friend you chose to accept setups from without asking" },
                effect = "Stops accepting setups automatically from that friend.",
                consequences = { "The next setup they send asks first, as from anyone else. Setups you already received stay." },
                reload = NO_RELOAD,
                run = RawRun(var, keys),
            }
        end
        if k2 == "detected" or k2 == "selection" then
            if n > 2 then return Block("The last settings search is cleared as a whole.", "Sharing records") end
            local db = ST.db
            local other = k2 == "detected" and "selection" or "detected"
            return {
                ok = true, dataset = "Sharing records", what = "The last settings search", via = "Share setup's own Clear",
                ident = "search", opKey = "search", restore = "fill", refresh = RefreshSharing,
                also = { { var = var, keys = { "setup", other } } },
                facts = { ("%d addon tables found, %d ticked"):format(Count(db and db.detected), Count(db and db.selection)) },
                effect = "Clears the list of what the last \"Find my addon settings\" found and what you ticked in it.",
                consequences = {
                    "Your saved setup, backups and received setups aren't affected.",
                    "Share setup needs a new search before it can offer a choice, and your ticks are cleared.",
                },
                reload = NO_RELOAD,
                run = function()
                    if not (ST.db and (next(ST.db.detected or {}) or next(ST.db.selection or {}))) then return false, "It is already empty." end
                    ST:ClearSearch()
                    return true
                end,
                gone = function()
                    local s = ST.db
                    return s ~= nil and next(s.detected) == nil and next(s.selection) == nil
                end,
            }
        end
        if SETUP_PROTECTED[k2] then return Block(SETUP_PROTECTED[k2], "Sharing records") end
        return Block("Not an entry this version of TwichUI recognises as removable. It may belong to a newer version, so it is left alone.", "Sharing records")
    end

    if k1 == "whisperProbe" then
        if n > 1 then return Block("The direct-message check is removed as a whole.", "Direct-message check") end
        if type(value) ~= "table" then return Block("TwichUI can't read this.", "Direct-message check") end
        return {
            ok = true, dataset = "Direct-message check", what = "The direct-message check's result", via = "a direct removal of this entry",
            ident = "probe", restore = "set",
            facts = { When(value.at) and ("Checked " .. When(value.at)) or "Date not recorded",
                value.build ~= nil and ("Game build " .. tostring(value.build)) or "Build not recorded" },
            effect = "Removes the remembered result of the small test message sent to another TwichUI user.",
            consequences = { "TwichUI repeats the test once, the next time you are grouped with another TwichUI user on this game build." },
            reload = NO_RELOAD,
            run = RawRun(var, keys),
        }
    end

    if k1 == "migrated" then
        if n > 1 or type(value) == "table" then return Block("Not an entry this version of TwichUI recognises as removable.") end
        return {
            ok = true, dataset = "Obsolete marker", what = "An obsolete upgrade marker", via = "a direct removal of this entry",
            ident = "migrated", restore = "set",
            facts = { "Written by TwichUI 3.0.4 and 3.0.5 only" },
            effect = "Removes a one-time marker an earlier release wrote and no current code reads.",
            consequences = { "Nothing reads it, so nothing changes. (docs/persistence.md lists it as left alone, never used.)" },
            reload = NO_RELOAD,
            run = RawRun(var, keys),
        }
    end

    if k1 == "storedData" then
        if k2 == "found" and n == 3 then
            if type(value) ~= "table" then return Block("TwichUI can't read this note.", "Addon data scan") end
            return {
                ok = true, dataset = "Addon data scan", what = "A note from an Addon data scan", via = "Addon data's own Forget",
                ident = "found:" .. tostring(k3), restore = "set", refresh = nil,
                facts = { type(value.owner) == "string" and ("Noted for addon \"" .. value.owner .. "\"") or "Owner not recorded",
                    When(value.seen) and ("Last seen by a scan " .. When(value.seen)) or "Date not recorded" },
                effect = "Forgets what a scan noted about one saved variable of another addon. The addon's own data is not touched.",
                consequences = {
                    "Addon data stops listing that variable until the addon loads during a scan again.",
                    "The other addon's saved data on disk is not changed.",
                },
                reload = NO_RELOAD,
                run = function()
                    if not SD.Forget(k3) then return false, "It isn't there any more." end
                    return true
                end,
            }
        end
        if n == 1 then return Block(TOP_PROTECTED.storedData, "Addon data scan") end
        if k2 == "found" and n == 2 then return Block("The list of scan notes. Forget one at a time.", "Addon data scan") end
        return Block("Scan bookkeeping (when the last scan ran and what was loaded before it). Not offered for deletion.", "Addon data scan")
    end

    if TOP_PROTECTED[k1] then return Block(TOP_PROTECTED[k1]) end
    return Block("Not an entry this version of TwichUI recognises as removable. It may belong to a newer version, so it is left alone.")
end

---------------------------------------------------------------------------
-- Fingerprints: what a target was when it was looked at
-- A change detector, not a checksum: it covers identity, structure, every key and a sample of each text.
-- A change it can miss is a same-length edit to a text between its sampled bytes.
---------------------------------------------------------------------------
local MOD = 2147483629
local function Mix(h, n) return (h * 31 + n) % MOD end

local function HashText(h, s)
    local len = #s
    h = Mix(h, len)
    if len <= 8 then
        for i = 1, len do h = Mix(h, s:byte(i)) end
    else
        for j = 0, 7 do h = Mix(h, s:byte(1 + math.floor((len - 1) * j / 7))) end
    end
    return h
end

local function HashScalar(h, v)
    if EX.IsSecret(v) then return Mix(h, 5) end
    local t = type(v)
    if t == "string" then return HashText(Mix(h, 1), v) end
    if t == "number" then
        if v ~= v then return Mix(h, 11) end
        if v == math.huge then return Mix(h, 12) end
        if v == -math.huge then return Mix(h, 13) end
        return Mix(Mix(h, 2), math.floor(v * 1024) % MOD)
    end
    if t == "boolean" then return Mix(h, v and 3 or 4) end
    if t == "table" then return Mix(h, 6) end
    return Mix(h, 7)
end

-- Counts and fingerprints value: { values, tables, hash, cut, hidden }. A table is walked with the
-- explorer's own Walk (next and rawget only, each table once, depth-bounded), a slice at a time when run
-- inside a job. m: a table to fill, so a caller can show progress.
function CL.Fingerprint(value, cap, m)
    m = m or {}
    m.values, m.tables, m.hash, m.cut, m.hidden = 0, 0, 0, false, 0
    if type(value) ~= "table" then
        m.values = 1
        m.hash = HashScalar(0, value)
        return m
    end
    if not Readable(value) then m.hidden = 1 return m end
    m.tables = 1
    local depthOf = { [value] = 0 }
    local _, _, cut = EX.Walk(value, function(_, k, v, parent)
        m.values = m.values + 1
        local d = (depthOf[parent] or 0) + 1
        local h = Mix(m.hash, d)
        h = HashScalar(h, k)
        if type(v) == "table" then
            if depthOf[v] == nil then
                depthOf[v] = d
                m.tables = m.tables + 1
                if not Readable(v) then m.hidden = m.hidden + 1 end
                h = Mix(h, 8)
            else
                h = Mix(h, 9)    -- the same table seen again
            end
        else
            h = HashScalar(h, v)
        end
        m.hash = h
    end, cap or CL.DIGEST_VISITS)
    m.cut = cut
    return m
end

local function SamePrint(a, b)
    return a ~= nil and b ~= nil and a.values == b.values and a.tables == b.tables and a.hash == b.hash and a.cut == b.cut
end

---------------------------------------------------------------------------
-- Targets: one reviewed entry
---------------------------------------------------------------------------
-- A target for var + keys as it is now, or nil and why. It holds the live parent and value so a later check
-- can tell "the same entry" from "an entry at the same path".
function CL.NewTarget(var, keys)
    keys = Copy(keys)
    local parent, value = CL.Resolve(var, keys)
    if value == nil then return nil, "It isn't there any more." end
    local plan = CL.Policy(var, keys, value)
    local t = { var = var, keys = keys, parent = parent, value = value, plan = plan }
    return t
end

-- Another entry the same removal also takes (the last search's two lists).
local function AlsoTargets(t)
    local out = {}
    for _, a in ipairs(t.plan.also or {}) do
        local parent, value = CL.Resolve(a.var, a.keys)
        out[#out + 1] = { var = a.var, keys = a.keys, parent = parent, value = value }
    end
    return out
end

-- Counts the targets (and what they also take) with sliced jobs. progress is filled as it goes
-- ({ index, total, values }). done(true) when finished, done(false) when it failed or was cancelled.
function CL.Count(targets, progress, done)
    EX.Cancel("cleanup-measure")
    progress = progress or {}
    progress.total, progress.index, progress.values = #targets, 0, 0
    local current = {}
    progress.current = current
    EX.StartJob("cleanup-measure", function()
        for i, t in ipairs(targets) do
            progress.index = i
            t.print = CL.Fingerprint(t.value, nil, current)
            t.print = { values = t.print.values, tables = t.print.tables, hash = t.print.hash, cut = t.print.cut, hidden = t.print.hidden }
            progress.values = progress.values + t.print.values
            t.alsoTargets = AlsoTargets(t)
            for _, a in ipairs(t.alsoTargets) do
                local p = CL.Fingerprint(a.value, nil, current)
                a.print = { values = p.values, tables = p.tables, hash = p.hash, cut = p.cut, hidden = p.hidden }
                progress.values = progress.values + a.print.values
            end
            if coroutine.running() then coroutine.yield() end
        end
        return true, true
    end, function(result, failed)
        if failed or not result then return done(false) end
        done(true)
    end)
end

-- Marks which targets can be put back (counts known, nothing hidden or cut, within the recovery budget).
function CL.PlanRecovery(targets)
    local budget = CL.RECOVERY_VALUES
    for _, t in ipairs(targets) do
        t.recoverable = false
        if t.plan.ok and t.print then
            local total, whole = t.print.values, not t.print.cut and t.print.hidden == 0
            for _, a in ipairs(t.alsoTargets or {}) do
                if a.print then
                    total = total + a.print.values
                    whole = whole and not a.print.cut and a.print.hidden == 0
                else
                    whole = false
                end
            end
            if whole and total <= budget then
                t.recoverable = true
                budget = budget - total
            end
        end
    end
end

-- Whether an address lies at or under another's.
local function Under(var, keys, ovar, okeys)
    if var ~= ovar or #keys < #okeys then return false end
    for i = 1, #okeys do
        if not rawequal(keys[i], okeys[i]) then return false end
    end
    return true
end

-- Drops targets covered by another (a child of a picked parent, the same entry twice, the same operation
-- twice) so nothing is removed twice. Returns the kept list and a list of { target, coveredBy }.
function CL.Normalize(targets)
    local kept, covered = {}, {}
    -- Shallowest first (a parent is met before its children); equal depth keeps the order given, so the same
    -- list always normalizes the same way (the review and the removal must agree on what is kept).
    local position, order = {}, {}
    for i, t in ipairs(targets) do order[i] = t; position[t] = i end
    table.sort(order, function(a, b)
        if #a.keys ~= #b.keys then return #a.keys < #b.keys end
        return position[a] < position[b]
    end)
    local seenOps = {}
    for _, t in ipairs(order) do
        local by
        for _, k in ipairs(kept) do
            if Under(t.var, t.keys, k.var, k.keys) then by = k break end
        end
        if not by and t.plan.opKey then
            by = seenOps[t.plan.opKey]
        end
        if by then
            covered[#covered + 1] = { target = t, coveredBy = by }
        else
            kept[#kept + 1] = t
            if t.plan.opKey then seenOps[t.plan.opKey] = t end
        end
    end
    return kept, covered
end

-- Checks a target against what is there now. Returns true, or false and why.
local function Recheck(t)
    local parent, value = CL.Resolve(t.var, t.keys)
    if value == nil then return false, "It isn't there any more." end
    if not rawequal(parent, t.parent) then return false, "The table it was in has been replaced." end
    if type(value) == "table" or type(t.value) == "table" then
        if not rawequal(value, t.value) then return false, "It has been replaced by a different entry." end
    elseif value ~= t.value and not (value ~= value and t.value ~= t.value) then
        return false, "Its value changed."
    end
    local plan = CL.Policy(t.var, t.keys, value)
    if not plan.ok then return false, plan.reason end
    if plan.ident ~= t.plan.ident or plan.opKey ~= t.plan.opKey then return false, "It is a different entry now." end
    if not t.print then return false, "It hasn't been counted." end
    local now = CL.Fingerprint(value)
    if not SamePrint(now, t.print) then return false, "What is inside it changed." end
    for i, a in ipairs(t.alsoTargets or {}) do
        local aparent, avalue = CL.Resolve(a.var, a.keys)
        if avalue == nil and a.value ~= nil then return false, "A related entry is gone." end
        if not rawequal(aparent, a.parent) or not rawequal(avalue, a.value) then return false, "A related entry was replaced." end
        if not SamePrint(CL.Fingerprint(avalue), a.print) then return false, "A related entry changed." end
    end
    t.plan = plan    -- the closures of the plan in force now
    return true
end
CL.Recheck = Recheck

---------------------------------------------------------------------------
-- Removing, and putting back
---------------------------------------------------------------------------
CL.recovery = nil     -- { at, label, items = { { var, keys, copy, how, refresh, ident } } }

local function Snapshot(value)
    return R.Persist.DeepCopy(value)
end

-- Removes the targets, all or nothing as to checking: if any target no longer matches what was reviewed,
-- nothing is removed. Returns a report:
--   { status = "blocked" | "changed" | "done" | "partial" | "failed", reason, results = { { target, ok, why } },
--     removed, failed, undoable, covered }
function CL.Commit(targets)
    local report = { results = {}, removed = 0, failed = 0, undoable = 0, covered = {} }
    if not enabled then
        report.status, report.reason = "blocked", "Advanced cleanup is not turned on."
        return report
    end
    if #targets == 0 then report.status, report.reason = "blocked", "Nothing is selected." return report end
    if #targets > CL.MAX_BATCH then
        report.status, report.reason = "blocked", ("At most %d entries can be reviewed at once."):format(CL.MAX_BATCH)
        return report
    end
    local list, covered = CL.Normalize(targets)
    report.covered = covered
    CL.PlanRecovery(list)
    for _, t in ipairs(list) do
        local ok, why = Recheck(t)
        if not ok then
            report.status, report.reason, report.stale = "changed", why, t
            return report
        end
    end
    -- All still match. Copies are taken first, so a failed removal never leaves a copy of something that is
    -- still there.
    local copies = {}
    for _, t in ipairs(list) do
        if t.recoverable then
            local c = { Snapshot(t.value) }
            for _, a in ipairs(t.alsoTargets or {}) do c[#c + 1] = Snapshot(a.value) end
            copies[t] = c
        end
    end
    local items = {}
    for _, t in ipairs(list) do
        local plan = t.plan
        local result = { target = t }
        report.results[#report.results + 1] = result
        local ok, okRun, why = pcall(plan.run)
        if not ok then
            geterrorhandler()(okRun)
            result.ok, result.why = false, "It raised an error; see the error report."
        elseif okRun == false then
            result.ok, result.why = false, why or "TwichUI declined."
        else
            local gone
            if plan.gone then
                gone = plan.gone()
            else
                -- By identity: removing an earlier entry of a list moves the later ones up, so the path of this
                -- one may now name a different entry.
                local _, now = CL.Resolve(t.var, t.keys)
                if now == nil then gone = true
                elseif type(t.value) == "table" then gone = not rawequal(now, t.value)
                else gone = now ~= t.value end
            end
            result.ok = gone
            if not gone then result.why = "It is still there after the removal, so it was not removed." end
        end
        if result.ok then
            report.removed = report.removed + 1
            local c = copies[t]
            if c then
                items[#items + 1] = { var = t.var, keys = t.keys, copy = c[1], how = plan.restore, ident = plan.ident, refresh = plan.refresh, check = plan.restoreCheck }
                for i, a in ipairs(t.alsoTargets or {}) do
                    items[#items + 1] = { var = a.var, keys = a.keys, copy = c[i + 1], how = "fill", ident = plan.ident, refresh = plan.refresh }
                end
                result.undoable = true
                report.undoable = report.undoable + 1
            end
            if plan.refresh then plan.refresh() end
        else
            report.failed = report.failed + 1
        end
    end
    if report.removed > 0 then
        CL.recovery = (#items > 0) and { at = time(), count = #items, items = items } or nil
        EX.Changed("sources")
        Changed("removed")
    end
    if report.failed == 0 then report.status = "done"
    elseif report.removed == 0 then report.status = "failed"
    else report.status = "partial" end
    return report
end

-- A short description of what Undo would put back, or nil.
function CL.RecoveryInfo()
    local r = CL.recovery
    if not r then return nil end
    return { at = r.at, count = r.count, items = #r.items }
end

-- Puts one copy back where it was, only if nothing took its place meanwhile.
local function Place(item)
    local var, keys = item.var, item.keys
    local n = #keys
    local parent
    if n == 0 then return false, "It was a whole saved variable." end
    if n == 1 then
        parent = G(var)
    else
        local pk = {}
        for i = 1, n - 1 do pk[i] = keys[i] end
        local _, p = CL.Resolve(var, pk)
        parent = p
    end
    if type(parent) ~= "table" or not Readable(parent) then return false, "Where it was is gone." end
    local key = keys[n]
    local how = item.how
    if how == "list" then
        if type(item.copy) == "table" and item.copy.id ~= nil then
            for _, e in ipairs(parent) do
                if type(e) == "table" and e.id == item.copy.id then return false, "An entry with the same id is there now." end
            end
        end
        table.insert(parent, math.min(type(key) == "number" and key or #parent + 1, #parent + 1), item.copy)
        return true
    elseif how == "fill" then
        local cur = rawget(parent, key)
        if type(cur) ~= "table" or next(cur) ~= nil then return false, "Something is there now." end
        for k, v in next, item.copy do cur[k] = v end
        return true
    else
        if rawget(parent, key) ~= nil then return false, "Something new is there now." end
        if item.check then
            local ok, why = item.check()
            if not ok then return false, why end
        end
        rawset(parent, key, item.copy)
        return true
    end
end

-- Puts back what the last cleanup removed, where it can be done safely. Returns { restored, failed = { {why} } }.
function CL.Undo()
    local r = CL.recovery
    if not enabled then return { restored = 0, failed = {}, blocked = "Advanced cleanup is not turned on." } end
    if not r then return { restored = 0, failed = {}, blocked = "There is nothing to undo." } end
    local report, left = { restored = 0, failed = {} }, {}
    for _, item in ipairs(r.items) do
        local ok, placed, why = pcall(Place, item)
        if ok and placed then
            report.restored = report.restored + 1
            if item.refresh then item.refresh() end
        else
            report.failed[#report.failed + 1] = { why = ok and why or "It raised an error." }
            left[#left + 1] = item
        end
    end
    if #left == 0 then CL.recovery = nil else r.items, r.count = left, #left end
    if report.restored > 0 then
        EX.Changed("sources")
        Changed("restored")
    end
    return report
end

function CL.DiscardRecovery()
    CL.recovery = nil
    Changed("recovery")
end

---------------------------------------------------------------------------
-- Cleanup candidates: what the saved data itself lets TwichUI say, and how sure it is
---------------------------------------------------------------------------
-- Tiers: strong = TwichUI's own code can't use it (the evidence is stated); possible = worth a look, with
-- the reason it might still matter; info = a fact about the data, not a recommendation.
-- Nothing here uses an entry's age to call it unused: every date in the saved data records when
-- something was made or seen, not when it was last used.
CL.TIER_ORDER = { strong = 1, possible = 2, info = 3 }
CL.TIER_LABEL = { strong = "Evidence-backed", possible = "Worth a look", info = "For your information" }

local yield = coroutine.yield
local function Pause() if coroutine.running() then yield() end end


-- Whether a Chronicle record holds anything beyond what the Chronicle makes for a character the first time
-- it needs one ({ entries = {}, nextId = 1, tracking = false } and a journey with nothing measured).
local KNOWN_RECORD = { entries = true, unreadable = true, nextId = true, tracking = true, journey = true }
local KNOWN_JOURNEY = { baseLevel = true, baseTotal = true, lastLevel = true, riding = true, professions = true, gold = true }
local function HasProgress(rec)
    if rec.tracking == true or rec.unreadable ~= nil then return true end
    if rec.nextId ~= nil and rec.nextId ~= 1 then return true end
    for k in next, rec do
        if not KNOWN_RECORD[k] then return true end
    end
    local j = rec.journey
    if j == nil then return false end
    if type(j) ~= "table" then return true end
    if j.baseLevel ~= nil or j.baseTotal ~= nil or j.lastLevel ~= nil or j.gold ~= nil then return true end
    if type(j.riding) == "table" and next(j.riding) ~= nil then return true end
    if type(j.professions) == "table" then
        for k, v in next, j.professions do
            if k ~= "baselined" or v == true then return true end
        end
    end
    for k in next, j do
        if not KNOWN_JOURNEY[k] then return true end
    end
    return false
end

local function Candidate(c)
    c.targets = c.targets or {}
    return c
end

-- Each rule: name, what it looks at, what it can't tell. Listed in the results, so an empty result still
-- says what was checked.
CL.RULES = {
    { id = "restore-empty", label = "Backups with nothing TwichUI can restore", limit = "A backup that is restorable is never flagged, whatever its age." },
    { id = "mine-empty", label = "Your saved setup, if it holds nothing", limit = "" },
    { id = "undo", label = "Undo copies: empty ones, and other characters'", limit = "TwichUI can't tell whether another character still exists." },
    { id = "received-empty", label = "Received setups with nothing TwichUI can apply", limit = "" },
    { id = "profiles", label = "Profiles no saved character choice uses", limit = "A profile may be kept on purpose to switch to later; profiles have no dates." },
    { id = "choices", label = "Profile choices that name a profile that no longer exists", limit = "" },
    { id = "chronicle", label = "Chronicle records of other characters", limit = "TwichUI can't tell whether that character still exists. Notes are your own writing." },
    { id = "probe", label = "The direct-message check, if it was made on another game build", limit = "" },
    { id = "migrated", label = "An obsolete marker written by 3.0.4 and 3.0.5", limit = "" },
    { id = "found", label = "Addon data notes for addons that are not installed", limit = "Only addons the game reports as not installed; a disabled addon is not flagged." },
    { id = "search", label = "The last settings search", limit = "It is a cache, but it also holds your ticks." },
}

CL.NOT_DETECTED = {
    "Whether another character still exists, or will be played again: no record of that is kept.",
    "Whether data is used by another addon or by a version of TwichUI other than this one.",
    "How long ago anything was last used: the dates saved are when something was made, received or seen, never last used.",
    "Anything in the options of the profile in use, map pins and kept pins, and the Chronicle's own entries: these are yours, so they are never suggested.",
    "Data of other addons: this explorer only lists TwichUI's own saved variables.",
}

-- Runs every rule. A job: a slice at a time, cancellable, nothing changed. done(result) with
--   { list = { candidate }, checked = { { rule, count } }, extra = n (suggestions not listed), at }
-- or done(nil, "failed"). Candidates: { id, tier, group, category, title, subject (personal), reason,
-- evidence, uncertainty, date = { t, label }, inspect = { source, keys }, targets = { {var, keys} } }.
function CL.Scan(progress, done)
    EX.Cancel("cleanup-scan")
    progress = progress or {}
    CL.scanning = progress
    EX.StartJob("cleanup-scan", function()
        local P = R.Persist
        local out, checked, infoCount, extra = {}, {}, 0, 0
        local function Add(c)
            if c.tier == "info" then
                if infoCount >= CL.MAX_INFO then extra = extra + 1 return end
                infoCount = infoCount + 1
            elseif #out >= CL.MAX_CANDIDATES then
                extra = extra + 1
                return
            end
            out[#out + 1] = Candidate(c)
        end
        local function Done(rule, n) checked[#checked + 1] = { rule = rule, count = n } end
        local function Step(text) progress.step = text Pause() end
        local me = ST.CharKey()
        local meKnown = type(me) == "string" and not me:find("^%?")

        -- Backups: no table TwichUI can restore (the same test Restore's own Restore makes).
        Step("Backups")
        do
            local n = 0
            local db = G("TwichUIRestoreDB")
            if type(db) == "table" and type(db.points) == "table" and not P.IsHeld("TwichUIRestoreDB") then
                for i, p in ipairs(db.points) do
                    if type(p) == "table" and type(p.id) == "string" then
                        n = n + 1
                        local usable = 0
                        for name, e in next, type(p.tables) == "table" and p.tables or {} do
                            if ST.ValidEntry(name, e) then usable = usable + 1 end
                        end
                        if usable == 0 then
                            Add({
                                id = "restore-empty:" .. p.id, tier = "strong", group = "Backups", category = "Backup with nothing to restore",
                                title = ("Backup \"%s\""):format(type(p.name) == "string" and p.name or "Backup"),
                                reason = "This backup holds no addon settings TwichUI can restore.",
                                evidence = "Restoring it is refused with \"That backup has nothing TwichUI can restore\": none of its tables passes the same check applying a setup makes.",
                                uncertainty = "A newer TwichUI could not read it either. The backup's name and date are kept, not its contents.",
                                date = When(p.created) and { t = p.created, label = "Made" } or nil,
                                inspect = { source = "restore:" .. p.id, keys = {} },
                                targets = { { var = "TwichUIRestoreDB", keys = { "points", i }, byId = p.id } },
                            })
                        end
                    end
                    if i % 50 == 0 then Pause() end
                end
            end
            Done("restore-empty", n)
        end

        -- Your saved setup: nothing in it, so Send has nothing to send.
        Step("Your saved setup")
        do
            local pack = G("TwichUIShareDB")
            pack = type(pack) == "table" and pack.pack
            local n = 0
            if type(pack) == "table" and not P.IsHeld("TwichUIShareDB") then
                n = 1
                if not (type(pack.tables) == "table" and next(pack.tables)) and not pack.eui and not pack.twichui then
                    Add({
                        id = "mine-empty", tier = "strong", group = "Your saved setup", category = "Empty saved setup",
                        title = "Your saved setup",
                        reason = "It holds no addon settings and no EllesmereUI profile, so Send has nothing to send.",
                        evidence = "The sharing preview reports the same: \"You have no saved setup, so Send has nothing to send.\"",
                        uncertainty = "It may still carry an Edit Mode layout, which Send does not send on its own.",
                        date = When(pack.created) and { t = pack.created, label = "Saved" } or nil,
                        inspect = { source = "share:mine", keys = {} },
                        targets = { { var = "TwichUIShareDB", keys = { "pack" } } },
                    })
                end
            end
            Done("mine-empty", n)
        end

        -- Undo copies: empty ones (Undo has nothing to put back), and other characters' as information.
        Step("Undo copies")
        do
            local n = 0
            local db = G("TwichUIBackupDB")
            if type(db) == "table" and not P.IsHeld("TwichUIBackupDB") then
                local keys = {}
                for k in next, db do if type(k) == "string" then keys[#keys + 1] = k end end
                table.sort(keys)
                for _, char in ipairs(keys) do
                    local b = rawget(db, char)
                    if type(b) == "table" then
                        n = n + 1
                        local empty = not (type(b.tables) == "table" and next(b.tables))
                        local pending = PendingChar(char)
                        local mine = meKnown and char == me
                        if empty and not pending then
                            Add({
                                id = "undo-empty:" .. char, tier = "strong", group = "Backups", category = "Undo copy with nothing to restore",
                                title = "Undo copy", subject = char,
                                reason = "This Undo copy holds no settings, so Undo has nothing to put back.",
                                evidence = "Undo is only offered when the copy holds a settings table; this one holds none.",
                                uncertainty = "",
                                date = When(b.created) and { t = b.created, label = "Taken" } or nil,
                                inspect = { source = "undo:" .. char, keys = {} },
                                targets = { { var = "TwichUIBackupDB", keys = { char } } },
                            })
                        elseif not empty and not mine and meKnown then
                            Add({
                                id = "undo-other:" .. char, tier = "info", group = "Other characters", category = "Another character's Undo copy",
                                title = "Undo copy", subject = char,
                                reason = "This is another character's Undo copy: the settings it had before it last applied a setup.",
                                evidence = "It is kept under that character's name. Not being the character you are playing now says nothing about whether it is used.",
                                uncertainty = "TwichUI can't tell whether that character still exists or will apply or undo again.",
                                date = When(b.created) and { t = b.created, label = "Taken" } or nil,
                                inspect = { source = "undo:" .. char, keys = {} },
                                targets = { { var = "TwichUIBackupDB", keys = { char } } },
                            })
                        end
                    end
                end
            end
            Done("undo", n)
        end

        -- Received setups: nothing TwichUI can apply.
        Step("Received setups")
        do
            local n = 0
            local db = ST.db
            local received = type(db) == "table" and type(db.received) == "table" and not P.IsHeld("TwichUIDB") and db.received or {}
            local senders = {}
            for k in next, received do if type(k) == "string" then senders[#senders + 1] = k end end
            table.sort(senders)
            for _, sender in ipairs(senders) do
                local pack = rawget(received, sender)
                if type(pack) == "table" then
                    n = n + 1
                    local usable = 0
                    for name, e in next, type(pack.tables) == "table" and pack.tables or {} do
                        if ST.ValidEntry(name, e) then usable = usable + 1 end
                    end
                    if usable == 0 and not pack.eui and not pack.twichui and not PendingSource("recv:" .. sender) then
                        Add({
                            id = "received-empty:" .. sender, tier = "strong", group = "Received setups", category = "Received setup with nothing to apply",
                            title = "Received setup", subject = sender,
                            reason = "This setup holds no addon settings and no EllesmereUI profile TwichUI can apply.",
                            evidence = "None of its tables passes the check applying a setup makes, and it carries no EllesmereUI profile.",
                            uncertainty = "",
                            date = When(pack.received) and { t = pack.received, label = "Received" } or nil,
                            inspect = { source = "recv:" .. sender, keys = {} },
                            targets = { { var = "TwichUIDB", keys = { "setup", "received", sender } } },
                        })
                    end
                end
            end
            Done("received-empty", n)
        end

        -- Profiles nobody has chosen, and choices of profiles that are gone.
        Step("Profiles")
        do
            local PF = R.Profiles
            local n, m = 0, 0
            local avail = PF and PF.Available() and not P.IsHeld("TwichUIDB")
            local db = G("TwichUIDB")
            if avail and type(db) == "table" then
                local live, fallback = PF.Current(), PF.NewCharacterProfile()
                local profiles = type(db.profiles) == "table" and db.profiles or {}
                local names = {}
                for k, v in next, profiles do
                    if type(k) == "string" and type(v) == "table" and P.ProfileName(k) == k then names[#names + 1] = k end
                end
                table.sort(names)
                for _, name in ipairs(names) do
                    n = n + 1
                    if name ~= live and name ~= fallback and #PF.UsedBy(name) == 0 then
                        Add({
                            id = "profile:" .. name, tier = "possible", group = "Profiles", category = "Profile no character uses",
                            title = ("Profile \"%s\""):format(name),
                            reason = "No saved character choice uses this profile, and it is neither the profile in use nor the one new characters start with.",
                            evidence = "Checked against every recorded character choice (profileKeys).",
                            uncertainty = "You may have kept it to switch to later (a raid or alt set). Profiles have no dates, so nothing says when it was last used.",
                            inspect = { source = "settings", keys = { "profiles", name } },
                            targets = { { var = "TwichUIDB", keys = { "profiles", name } } },
                        })
                    end
                end
                local keys = type(db.profileKeys) == "table" and db.profileKeys or {}
                local chars = {}
                for k, v in next, keys do if type(k) == "string" and type(v) == "string" then chars[#chars + 1] = k end end
                table.sort(chars)
                for _, char in ipairs(chars) do
                    m = m + 1
                    local chosen = rawget(keys, char)
                    if char ~= PF.Character() and not PF.Exists(chosen) then
                        Add({
                            id = "choice:" .. char, tier = "strong", group = "Profiles", category = "Choice of a profile that is gone",
                            title = "A character's profile choice", subject = char,
                            reason = ("It names the profile \"%s\", which no longer exists."):format(chosen),
                            evidence = "At login TwichUI already treats a missing profile as no choice and uses the one for new characters, so forgetting it changes nothing it does.",
                            uncertainty = "The login notice \"this character's profile no longer exists\" would not be shown once.",
                            inspect = { source = "settings", keys = { "profileKeys", char } },
                            targets = { { var = "TwichUIDB", keys = { "profileKeys", char } } },
                        })
                    end
                end
            end
            Done("profiles", n)
            Done("choices", m)
        end

        -- Chronicle records of other characters.
        Step("Journey Chronicle")
        do
            local n = 0
            local db = G("TwichUIChronicleDB")
            local C = R.Chronicle
            if type(db) == "table" and type(db.chars) == "table" and C and meKnown and not P.IsHeld("TwichUIChronicleDB") then
                local meKey = C.CharKey()
                local keys = {}
                for k, v in next, db.chars do if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end end
                table.sort(keys)
                for _, char in ipairs(keys) do
                    if char ~= meKey then
                        n = n + 1
                        local rec = rawget(db.chars, char)
                        local entries, notes, latest = 0, 0, nil
                        for _, e in ipairs(type(rec.entries) == "table" and rec.entries or {}) do
                            if type(e) == "table" then
                                entries = entries + 1
                                if e.kind == "note" then notes = notes + 1 end
                                if type(e.t) == "number" and (not latest or e.t > latest) then latest = e.t end
                            end
                        end
                        local fresh = entries == 0 and not HasProgress(rec)
                        if fresh then
                            Add({
                                id = "chronicle-fresh:" .. char, tier = "strong", group = "Journey Chronicle", category = "Empty Chronicle record",
                                title = "Chronicle record", subject = char,
                                reason = "It holds nothing: no entries, no notes and no tracking progress.",
                                evidence = "It is identical to the empty record the Chronicle makes for a character the first time it needs one.",
                                uncertainty = "",
                                inspect = { source = "chronicle", keys = { "chars", char } },
                                targets = { { var = "TwichUIChronicleDB", keys = { "chars", char } } },
                            })
                        else
                            Add({
                                id = "chronicle-other:" .. char, tier = "info", group = "Other characters", category = "Another character's Chronicle record",
                                title = "Chronicle record", subject = char,
                                reason = ("It holds %d entr%s, %d of them notes you wrote."):format(entries, entries == 1 and "y" or "ies", notes),
                                evidence = "It is kept under that character's name. Not being the character you are playing now says nothing about whether it is used.",
                                uncertainty = "TwichUI can't tell whether that character still exists. Notes are your own writing and are removed with the record.",
                                date = latest and { t = latest, label = "Latest entry" } or nil,
                                inspect = { source = "chronicle", keys = { "chars", char } },
                                targets = { { var = "TwichUIChronicleDB", keys = { "chars", char } } },
                            })
                        end
                    end
                    if n % 25 == 0 then Pause() end
                end
            end
            Done("chronicle", n)
        end

        -- The direct-message check, recorded on another game build: the check ignores it.
        Step("Direct-message check")
        do
            local n = 0
            local db = G("TwichUIDB")
            local p = type(db) == "table" and not P.IsHeld("TwichUIDB") and db.whisperProbe
            if type(p) == "table" then
                n = 1
                local build = select(2, GetBuildInfo())
                if build ~= nil and p.build ~= nil and p.build ~= build then
                    Add({
                        id = "probe", tier = "strong", group = "Caches", category = "Result for another game build",
                        title = "Direct-message check result",
                        reason = ("It was recorded on game build %s; this is build %s."):format(tostring(p.build), tostring(build)),
                        evidence = "TwichUI only uses the result when its build matches the running game's, and tests again when grouped with another TwichUI user otherwise.",
                        uncertainty = "",
                        date = When(p.at) and { t = p.at, label = "Checked" } or nil,
                        inspect = { source = "settings", keys = { "whisperProbe" } },
                        targets = { { var = "TwichUIDB", keys = { "whisperProbe" } } },
                    })
                end
            end
            Done("probe", n)
        end

        -- An upgrade marker nothing reads.
        Step("Obsolete markers")
        do
            local n = 0
            local db = G("TwichUIDB")
            if type(db) == "table" and not P.IsHeld("TwichUIDB") and type(db.migrated) == "number" then
                n = 1
                Add({
                    id = "migrated", tier = "strong", group = "Caches", category = "Obsolete marker",
                    title = "Upgrade marker \"migrated\"",
                    reason = "A one-time marker TwichUI 3.0.4 and 3.0.5 wrote for a change since reversed. Nothing reads it.",
                    evidence = "No code in this version reads TwichUIDB.migrated, and docs/persistence.md lists it as left alone and unused.",
                    uncertainty = "",
                    inspect = { source = "settings", keys = { "migrated" } },
                    targets = { { var = "TwichUIDB", keys = { "migrated" } } },
                })
            end
            Done("migrated", n)
        end

        -- Scan notes for addons the game says are not installed.
        Step("Addon data notes")
        do
            local n = 0
            local db = G("TwichUIDB")
            local found = type(db) == "table" and not P.IsHeld("TwichUIDB") and type(db.storedData) == "table" and db.storedData.found
            local exists = C_AddOns and C_AddOns.DoesAddOnExist
            if type(found) == "table" and exists then
                local byOwner = {}
                for name, e in next, found do
                    if type(name) == "string" and type(e) == "table" and type(e.owner) == "string" then
                        n = n + 1
                        local ok, there = pcall(exists, e.owner)
                        if ok and there == false and e.owner ~= R.ADDON then
                            local o = byOwner[e.owner]
                            if not o then o = { names = {}, seen = nil } byOwner[e.owner] = o end
                            o.names[#o.names + 1] = name
                            if type(e.seen) == "number" and (not o.seen or e.seen > o.seen) then o.seen = e.seen end
                        end
                    end
                end
                local owners = {}
                for owner in next, byOwner do owners[#owners + 1] = owner end
                table.sort(owners)
                for _, owner in ipairs(owners) do
                    local o = byOwner[owner]
                    table.sort(o.names)
                    local targets = {}
                    for _, name in ipairs(o.names) do targets[#targets + 1] = { var = "TwichUIDB", keys = { "storedData", "found", name } } end
                    Add({
                        id = "found:" .. owner, tier = "possible", group = "Caches", category = "Notes for an addon that isn't installed",
                        title = ("Notes for \"%s\" (%d)"):format(owner, #o.names),
                        reason = "A scan noted saved variables for an addon the game reports as not installed.",
                        evidence = "C_AddOns.DoesAddOnExist reports that addon as not there. The notes hold names and an owner only.",
                        uncertainty = "These notes are how Addon data can point out leftovers of a removed addon. The addon's own file on disk is not touched either way.",
                        date = o.seen and { t = o.seen, label = "Last seen by a scan" } or nil,
                        inspect = { source = "settings", keys = { "storedData", "found", o.names[1] } },
                        targets = targets,
                    })
                end
            end
            Done("found", n)
        end

        -- The last settings search: a cache, rebuilt by searching again.
        Step("Settings search")
        do
            local n = 0
            local db = ST.db
            if type(db) == "table" and not P.IsHeld("TwichUIDB") and type(db.detected) == "table" and next(db.detected) ~= nil then
                n = 1
                local last = db.lastScan
                Add({
                    id = "search", tier = "possible", group = "Caches", category = "Last settings search",
                    title = "Last \"Find my addon settings\" result",
                    reason = ("It lists %d addon tables found by the last search."):format(Count(db.detected)),
                    evidence = "It is rebuilt by searching again; clearing it does not touch your saved setup or backups.",
                    uncertainty = "It also holds what you ticked, which is cleared with it.",
                    date = type(last) == "number" and When(last) and { t = last, label = "Last search" } or nil,
                    inspect = { source = "settings", keys = { "setup", "detected" } },
                    targets = { { var = "TwichUIDB", keys = { "setup", "detected" } } },
                })
            end
            Done("search", n)
        end

        table.sort(out, function(a, b)
            local ta, tb = CL.TIER_ORDER[a.tier], CL.TIER_ORDER[b.tier]
            if ta ~= tb then return ta < tb end
            if a.group ~= b.group then return a.group < b.group end
            return a.id < b.id
        end)
        return true, { list = out, checked = checked, extra = extra, at = time() }
    end, function(result, failed)
        CL.scanning = nil
        if failed or not result then return done(nil, "failed") end
        CL.results = result
        done(result)
    end)
end

function CL.CancelScan()
    EX.Cancel("cleanup-scan")
    CL.scanning = nil
end

---------------------------------------------------------------------------
-- Picks: a suggestion is only ever approved by being ticked, and only in advanced mode
---------------------------------------------------------------------------
function CL.Pick(id, on)
    if not enabled then return false end
    CL.picks[id] = on and true or nil
    return true
end

function CL.PickedCandidates()
    local list = {}
    if not (CL.results and enabled) then return list end
    for _, c in ipairs(CL.results.list) do
        if CL.picks[c.id] then list[#list + 1] = c end
    end
    return list
end

-- The keys of a suggestion's target as they are now. A list entry (a backup) is found again by its id: its
-- position moves when an earlier entry is removed, and the position seen by a scan must never name a
-- different entry later. nil when it is not there any more.
function CL.LocateTarget(a)
    if not a.byId then
        local _, v = CL.Resolve(a.var, a.keys)
        if v == nil then return nil end
        return a.keys
    end
    local list = G(a.var)
    list = type(list) == "table" and rawget(list, a.keys[1])
    if type(list) ~= "table" or not Readable(list) then return nil end
    for i, e in ipairs(list) do
        if type(e) == "table" and rawget(e, "id") == a.byId then return { a.keys[1], i } end
    end
    return nil
end

function CL.CandidateGone(c)
    for _, a in ipairs(c.targets) do
        if CL.LocateTarget(a) ~= nil then return false end
    end
    return true
end

-- Targets for a set of candidates, as they are now. Entries that are gone come back as nothing; protected
-- ones come back with their plan saying why, and the review lists them without ever removing them.
function CL.TargetsFor(candidates)
    local out = {}
    for _, c in ipairs(candidates) do
        for _, a in ipairs(c.targets) do
            local keys = CL.LocateTarget(a)
            local t = keys and CL.NewTarget(a.var, keys)
            if t then
                t.candidate, t.byId = c, a.byId
                out[#out + 1] = t
            end
        end
    end
    return out
end
