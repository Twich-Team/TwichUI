-- TwichUI: EllesmereUI profile sharing
--
-- EllesmereUI keeps everything in one saved table, EllesmereUIDB: every
-- profile, which profile each spec uses, keybinds, the Cooldown Manager spell
-- store, click-cast, and per-character data (names, gold, specs). Its other
-- saved tables are empty leftovers. Copying that table into someone else's
-- game would replace their whole EllesmereUI setup, so TwichUI never shares
-- or applies it as a table. Instead:
--   * Sharing: you pick one profile. TwichUI asks EllesmereUI to export it
--     with EllesmereUI's own export function, with the profile's look (fonts,
--     custom colours, dark mode, accent) but without the account-wide UI scale
--     or the window-skin bundle.
--   * Receiving: the profile is decoded with EllesmereUI's own decoder and
--     imported with EllesmereUI's own import into a NEW profile with an unused
--     name. Nothing that exists is overwritten or deleted. EllesmereUI makes an
--     imported profile the active one (it has no store-only import), so the
--     review says so and the friend confirms it.
--   * Older shares that carry the whole table are never applied as a table.
--     The sender's active profile is pulled out, checked, and offered the same way.
-- Imported data is only ever read as data: EllesmereUI's decoder is not Lua.

local R = TwichUI
local ST = R.Setups
local ES = {}
R.Ellesmere = ES

local LibDeflate = LibStub("LibDeflate")

ES.LIMITS = {
    string = 4 * 1048576,    -- characters of one exported profile
    data = 8 * 1048576,      -- bytes of data once decoded
    name = 30,               -- EllesmereUI's own limit for a profile name
    ident = 64,
}
local L = ES.LIMITS

local DB_NAME = "EllesmereUIDB"

-- Taken out of what is imported: things that belong to the whole account, not
-- to the one profile being shared. (The look, meaning fonts, custom colours,
-- dark mode and accent, is stored in the profile and is imported with it.)
local GLOBAL_KEYS = {
    "uiScale", "applyUIScale",                                  -- account UI scale
    "blizzSkinGlobals", "applyBlizzSkinGlobals",                -- window and tooltip skins
    "assignedSpecs",                                            -- which specs use the profile
    "clickCast", "spellAssignments",                            -- account stores
    "unlockLayoutMeta", "_importEstablishPending",              -- transport / import-window flags
}

-- What EllesmereUI itself keeps out of a shared profile (per-character data).
local PRIVATE = { EllesmereUIDataBars = "characters", EllesmereUIQoL = "chars" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Store()
    ST.db.eui = ST.db.eui or {}
    local s = ST.db.eui
    s.imports = s.imports or {}    -- [destination profile] = where it came from
    s.ids = s.ids or {}            -- [your profile name] = id that stays with it when shared
    return s
end

local function CleanName(s)
    s = type(s) == "string" and s or ""
    return (s:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Meta(field)
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, "EllesmereUI", field)
    return ok and type(v) == "string" and v or nil
end

function ES.IsTable(name)
    return type(name) == "string" and name:find("^EllesmereUI.*DB$") ~= nil
end

---------------------------------------------------------------------------
-- EllesmereUI's profile functions: present, and the Forever build
---------------------------------------------------------------------------
local REQUIRED = { "ExportProfile", "DecodeImportString", "ImportProfile", "GetProfileList", "GetActiveProfileName" }

function ES.Api()
    local E = rawget(_G, "EllesmereUI")
    if type(E) ~= "table" then return nil, "EllesmereUI isn't installed or isn't turned on." end
    for _, fn in ipairs(REQUIRED) do
        if type(E[fn]) ~= "function" then
            return nil, ("This EllesmereUI version doesn't offer the profile function TwichUI needs (%s). Update EllesmereUI."):format(fn)
        end
    end
    if E.IS_FOREVER ~= true then return nil, "This EllesmereUI isn't the WoW: Forever build." end
    return E
end

function ES.Version() return Meta("Version") end

-- Profile names in EllesmereUI's own order. Names only; the profiles stay in EllesmereUI.
function ES.ProfileNames()
    local E = ES.Api()
    if not E then return {} end
    local ok, order, profiles = pcall(E.GetProfileList)
    if not ok or type(profiles) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, n in ipairs(type(order) == "table" and order or {}) do
        if type(n) == "string" and profiles[n] ~= nil and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    local rest = {}
    for n in pairs(profiles) do
        if type(n) == "string" and not seen[n] then rest[#rest + 1] = n end
    end
    table.sort(rest)
    for _, n in ipairs(rest) do out[#out + 1] = n end
    return out
end

local function ProfileExists(name)
    for _, n in ipairs(ES.ProfileNames()) do if n == name then return true end end
    return false
end

---------------------------------------------------------------------------
-- Sharing your profile
---------------------------------------------------------------------------
function ES.ChosenProfile()
    local name = Store().share
    if name and ProfileExists(name) then return name end
end

function ES.Choose(name) Store().share = name end

-- A random id that stays with one of your profiles, so a friend's later import
-- can tell it is the same profile again even if the name is reused.
local function ShareId(name)
    local ids = Store().ids
    if not ids[name] then ids[name] = R.Share.NewId() .. ("%04d"):format(math.random(0, 9999)) end
    return ids[name]
end

-- The entry saved with your setup: nil when no profile is chosen, or nil and
-- the reason when it couldn't be made. Only called when you save.
function ES.Build()
    local name = Store().share
    if not name then return nil end
    local E, why = ES.Api()
    if not E then return nil, why end
    if not ProfileExists(name) then return nil, ("the profile \"%s\" no longer exists in EllesmereUI."):format(name) end
    -- ExportProfile(name, modules, layout, cdm, cdmSpecs, globals, overrides, windowSkins):
    -- every installed module, its layout links, Cooldown Manager spells and
    -- overrides, and the profile's look; no window skins. (The string also carries
    -- the UI scale with the look; the receiving side drops it.)
    local ok, str = pcall(E.ExportProfile, name, nil, true, true, nil, true, true, false)
    if not ok or type(str) ~= "string" or str == "" then
        return nil, "EllesmereUI couldn't export that profile."
    end
    if #str > L.string then return nil, "That profile is too large to share." end
    local okDecode, payload = pcall(E.DecodeImportString, str)
    if not okDecode or type(payload) ~= "table" or payload.type ~= "full" then
        return nil, "EllesmereUI's export of that profile didn't read back correctly."
    end
    return {
        id = ShareId(name), name = name, str = str,
        hash = LibDeflate:Adler32(str) .. ":" .. #str,
        made = time(), euiVersion = ES.Version(),
    }
end

-- Receiving side: is this a well-formed profile entry? (Cheap: no hashing.)
local function WellFormed(e)
    if type(e) ~= "table" or type(e.str) ~= "string" or #e.str < 6 or #e.str > L.string then return false end
    if e.str:sub(1, 5) ~= "!EUI_" then return false end
    if type(e.id) ~= "string" or #e.id == 0 or #e.id > L.ident or e.id:find("[%c|]") then return false end
    return CleanName(e.name) ~= ""
end

-- Keep only what a profile entry should hold. nil if it isn't one. Done once, when a setup arrives.
function ES.CleanEntry(e)
    if not WellFormed(e) then return nil end
    return {
        id = e.id, name = CleanName(e.name):sub(1, 100), str = e.str,
        hash = LibDeflate:Adler32(e.str) .. ":" .. #e.str,
        made = type(e.made) == "number" and e.made or nil,
        euiVersion = type(e.euiVersion) == "string" and e.euiVersion:sub(1, 40) or nil,
    }
end

---------------------------------------------------------------------------
-- What a received setup offers for EllesmereUI
---------------------------------------------------------------------------
-- Modules EllesmereUI recognises, in its order: canonical key -> display name.
local function ModuleNames(E)
    local names, order = {}, {}
    local map = type(E._ADDON_DB_MAP) == "table" and E._ADDON_DB_MAP or nil
    for _, e in ipairs(map or {}) do
        local canon = e.canon or ("Ellesmere" .. "UI" .. (e.suffix or ""))
        names[canon] = { display = e.display or canon, folder = e.folder }
        order[#order + 1] = canon
    end
    return names, order, map ~= nil
end

-- An older share holds the sender's whole EllesmereUIDB. Find their active
-- profile inside it, or say why that isn't possible.
local function LegacyProfile(db)
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return nil, "it doesn't hold any profiles" end
    local name = db.activeProfile
    if type(name) ~= "string" or name == "" then name = "Default" end
    local prof = db.profiles[name]
    if type(prof) ~= "table" or type(prof.addons) ~= "table" or next(prof.addons) == nil then
        return nil, "its active profile has no module settings"
    end
    return prof, name
end

-- { kind = "profile" | "legacy", name, key, made, euiVersion }, or nil and a reason
-- when an older share carries the whole database and nothing can be taken from it.
function ES.Source(pack)
    if type(pack) ~= "table" then return nil end
    local from = tostring(pack.source or pack.sender or "?")
    if pack.eui then
        local e = pack.eui
        if WellFormed(e) then
            return { kind = "profile", name = CleanName(e.name):sub(1, 100), key = from .. "|" .. e.id, made = e.made,
                euiVersion = type(e.euiVersion) == "string" and e.euiVersion or nil, entry = e }
        end
        return nil, "the profile in this setup is damaged"
    end
    local t = pack.tables and pack.tables[DB_NAME]
    if t then
        local prof, name = LegacyProfile(t.data)
        if not prof then return nil, "this older setup holds a whole EllesmereUI database and " .. tostring(name) end
        return { kind = "legacy", name = CleanName(name):sub(1, 100), key = from .. "|legacy:" .. name, made = pack.created, legacyProfile = prof }
    end
end

-- Table names a setup from someone else must never apply as tables.
function ES.Blocked(sourceKey, name)
    return ES.IsTable(name) and not (type(sourceKey) == "string" and sourceKey:find("^restore:"))
end

---------------------------------------------------------------------------
-- Decoding a profile into an import-ready payload (data only)
---------------------------------------------------------------------------
local function Sanitize(E, payload)
    if type(payload) ~= "table" or payload.type ~= "full" or type(payload.data) ~= "table" then
        return nil, "It isn't a single EllesmereUI profile."
    end
    local d = payload.data
    for _, k in ipairs(GLOBAL_KEYS) do d[k] = nil end
    if type(d.addons) ~= "table" then return nil, "It has no module settings." end
    local names, _, known = ModuleNames(E)
    local kept = 0
    for canon, blob in pairs(d.addons) do
        if type(canon) ~= "string" or type(blob) ~= "table" or (known and not names[canon]) then
            d.addons[canon] = nil
        else
            local private = PRIVATE[canon]
            if private then blob[private] = nil end
            kept = kept + 1
        end
    end
    if kept == 0 then return nil, "It has no module settings EllesmereUI recognises." end
    if ST.SizeOf(d) > L.data then return nil, "It is too large." end
    return payload
end

-- Returns a fresh payload table for source (data only, safe to hand to EllesmereUI), or nil, reason.
function ES.Payload(E, src)
    if src.kind == "profile" then
        local ok, payload, err = pcall(E.DecodeImportString, src.entry.str)
        if not ok then return nil, "EllesmereUI couldn't read it." end
        if type(payload) ~= "table" then return nil, tostring(err or "EllesmereUI couldn't read it.") end
        return Sanitize(E, payload)
    end
    -- Older share: only the module settings of the active profile. No layout
    -- links, Cooldown Manager spells or overrides: those can't be checked here.
    local data = { addons = ST.DeepCopy(src.legacyProfile.addons) }
    if type(src.legacyProfile._migrations) == "table" then data._migrations = ST.DeepCopy(src.legacyProfile._migrations) end
    return Sanitize(E, { version = 3, type = "full", data = data })
end

---------------------------------------------------------------------------
-- Naming and where it came from
---------------------------------------------------------------------------
local function Taken(name)
    local low = name:lower()
    for _, n in ipairs(ES.ProfileNames()) do if n:lower() == low then return true end end
    return false
end

-- A name no existing profile uses (case aside), within EllesmereUI's name limit.
function ES.NewName(profileName, from)
    local who = CleanName(from):sub(1, 10)
    local tail = who ~= "" and (" (" .. who .. ")") or ""
    local base = CleanName(profileName)
    if base == "" then base = "Imported" end
    local function Make(suffix)
        local room = L.name - #tail - #suffix
        return base:sub(1, math.max(1, room)) .. tail .. suffix
    end
    local name, n = Make(""), 1
    while Taken(name) do n = n + 1; name = Make(" " .. n) end
    return name
end

-- Earlier imports of this same shared profile that still exist: { { dest, at } }
function ES.PreviousImports(srcKey)
    local list, imports = {}, Store().imports
    for dest, info in pairs(imports) do
        if type(info) == "table" and info.key == srcKey then
            if ES.Api() and not ProfileExists(dest) then imports[dest] = nil   -- deleted in EllesmereUI since
            else list[#list + 1] = { dest = dest, at = info.at } end
        end
    end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return list
end

---------------------------------------------------------------------------
-- The review: everything the friend sees before anything changes
---------------------------------------------------------------------------
local summaryCache   -- one entry, the last one asked for: { key, value }

local EXCLUDED = "UI scale, window and tooltip skins, which specs use a profile, click-cast, "
    .. "and every one of your other profiles."

function ES.ReleaseCache() summaryCache = nil end

-- { ok, why, kind, sourceName, from, dest, active, modules = {display, missing}, layout, cdm,
--   overrides, look, colours, previous = {...}, excluded, notes = {...}, euiVersion, version }
function ES.Plan(pack, from)
    local plan = { from = from or "?", excluded = EXCLUDED, notes = {} }
    local src, reason = ES.Source(pack)
    if not src then
        plan.why = reason and ("EllesmereUI profile: " .. reason .. ".") or nil
        plan.none = reason == nil
        return plan
    end
    plan.kind, plan.sourceName, plan.euiVersion, plan.key = src.kind, src.name, src.euiVersion, src.key
    plan.version = ES.Version()
    local E, why = ES.Api()
    if not E then plan.why = why return plan end
    plan.active = E.GetActiveProfileName()
    plan.previous = ES.PreviousImports(src.key)
    plan.dest = ES.NewName(src.name, from)

    local cacheKey = src.key .. "|" .. tostring(src.entry and (src.entry.hash or #src.entry.str) or pack.created)
    local sum = summaryCache and summaryCache.key == cacheKey and summaryCache.value
    if not sum then
        local payload, err = ES.Payload(E, src)
        if not payload then plan.why = "This EllesmereUI profile can't be imported: " .. tostring(err); return plan end
        local names, order = ModuleNames(E)
        if #order == 0 then   -- EllesmereUI doesn't list its modules: show what the profile holds
            for canon in pairs(payload.data.addons) do
                order[#order + 1] = canon
                names[canon] = { display = canon, folder = canon }
            end
            table.sort(order)
        end
        sum = { modules = {}, layout = payload.data.unlockLayout ~= nil, overrides = false, cdm = false }
        for _, canon in ipairs(order) do
            if payload.data.addons[canon] then
                local folder = names[canon].folder
                local loaded = true
                if type(E.IsModuleAddonLoaded) == "function" then
                    local okLoaded, v = pcall(E.IsModuleAddonLoaded, folder)
                    loaded = not okLoaded or v and true or false
                end
                sum.modules[#sum.modules + 1] = { display = names[canon].display, missing = not loaded }
            end
        end
        for _, k in ipairs({ "specOverrides", "condOverrides", "specUnlockOverrides", "condUnlockOverrides" }) do
            if payload.data[k] ~= nil then sum.overrides = true end
        end
        sum.look = payload.data.fonts ~= nil or payload.data.customColors ~= nil
            or payload.data.darkMode ~= nil or payload.data.euiAccent ~= nil
        sum.colours = payload.data.customColors ~= nil
        sum.cdm = payload.data.cdmSpells ~= nil
        if sum.cdm and type(E.PayloadFromOtherClient) == "function" then
            local okClient, other = pcall(E.PayloadFromOtherClient, payload)
            if okClient and other then sum.cdm = false; sum.otherClient = true end
        end
        summaryCache = { key = cacheKey, value = sum }
    end
    plan.modules, plan.layout, plan.overrides, plan.cdm = sum.modules, sum.layout, sum.overrides, sum.cdm
    plan.look, plan.colours = sum.look, sum.colours
    if sum.colours then
        plan.notes[#plan.notes + 1] = "Its custom colours: wherever your profiles share one colour palette (Pull Colors From in EllesmereUI), they will show this profile's palette. EllesmereUI does this when it imports colours; your other profiles' own settings aren't edited."
    end
    if src.kind == "legacy" then
        plan.notes[#plan.notes + 1] = "From an older TwichUI that shared a whole EllesmereUI database. TwichUI took only the module settings of the sender's active profile, so there are no layout links, Cooldown Manager spells or overrides."
    end
    if sum.otherClient then
        plan.notes[#plan.notes + 1] = "Its Cooldown Manager spells come from the other game client and aren't imported."
    end
    plan.ok = true
    return plan
end

---------------------------------------------------------------------------
-- Importing
---------------------------------------------------------------------------
local function Snapshot(E)
    local snap = { names = {}, assign = {} }
    for _, n in ipairs(ES.ProfileNames()) do snap.names[n] = true end
    if type(E.GetProfilesDB) == "function" then
        local ok, db = pcall(E.GetProfilesDB)
        if ok and type(db) == "table" then
            snap.profiles = {}
            for n, p in pairs(db.profiles or {}) do snap.profiles[n] = p end
            for spec, n in pairs(db.specProfiles or {}) do snap.assign[spec] = n end
            snap.checkable = true
        end
    end
    return snap
end

-- After the import: nothing else about the recipient's profiles changed. Only
-- what EllesmereUI exposes can be compared; the result says what was checked.
local function Verify(E, before, dest)
    local after = Snapshot(E)
    local problems = {}
    for n in pairs(before.names) do if not after.names[n] then problems[#problems + 1] = ("profile \"%s\" is gone"):format(n) end end
    for n in pairs(after.names) do
        if not before.names[n] and n ~= dest then problems[#problems + 1] = ("unexpected new profile \"%s\""):format(n) end
    end
    if before.checkable and after.checkable then
        for n, p in pairs(before.profiles) do
            if after.profiles[n] ~= p then problems[#problems + 1] = ("profile \"%s\" was replaced"):format(n) end
        end
        for spec, n in pairs(before.assign) do
            if after.assign[spec] ~= n then problems[#problems + 1] = "a spec assignment changed" end
        end
        for spec in pairs(after.assign) do
            if before.assign[spec] == nil then problems[#problems + 1] = "a spec assignment was added" end
        end
    end
    return #problems == 0, problems, before.checkable and after.checkable
end

-- Undo a half-made import: put the previous profile back if EllesmereUI moved
-- off it, then remove the profile this import created (it didn't exist before).
local function Cleanup(E, before, dest, prevActive)
    local made = not before.names[dest] and ProfileExists(dest)
    if not made then return false end
    pcall(function()
        if E.GetActiveProfileName() ~= prevActive and before.names[prevActive] and E.SwitchProfile then
            E.SwitchProfile(prevActive)
        end
    end)
    if type(E.DeleteProfile) == "function" then pcall(E.DeleteProfile, dest) end
    return true
end

-- expectedDest is the name the friend saw in the review; if it isn't free any
-- more nothing happens. Returns true, report | false, message. On success the
-- caller reloads the UI, as EllesmereUI's import requires.
function ES.Apply(pack, from, expectedDest)
    if InCombatLockdown() then return false, "That has to wait until you're out of combat." end
    local src, reason = ES.Source(pack)
    if not src then return false, "There's no EllesmereUI profile to import" .. (reason and (": " .. reason) or "") .. "." end
    local E, why = ES.Api()
    if not E then return false, why end
    local dest = ES.NewName(src.name, from)
    if expectedDest and dest ~= expectedDest then
        return false, ("The name changed from \"%s\" to \"%s\" since you reviewed it. Review again."):format(expectedDest, dest)
    end
    -- Everything is checked before anything is touched.
    local payload, err = ES.Payload(E, src)
    if not payload then return false, "Nothing was changed. " .. tostring(err) end

    local prevActive = E.GetActiveProfileName()
    local before = Snapshot(E)
    if before.names[dest] then return false, "Nothing was changed. That profile name is already in use." end

    local ok, result, e2, status = pcall(E.ImportProfile, payload, dest)
    local good = ok and result == true
    if not good then
        local cleaned = Cleanup(E, before, dest, prevActive)
        local msg = ok and tostring(e2 or "EllesmereUI refused the import.") or "EllesmereUI hit an error during the import."
        if not ok then geterrorhandler()(result) end
        return false, msg .. (cleaned and " The half-made profile was removed and your profile put back." or " Your profiles weren't changed.")
    end

    local fine, problems, checked = Verify(E, before, dest)
    local store = Store()
    store.imports[dest] = { key = src.key, source = src.name, from = from, at = time(), kind = src.kind }
    local report = {
        dest = dest, previous = prevActive, status = status == "spec_locked" and "stored" or "active",
        verified = fine and checked or false, problems = problems, from = from, source = src.name,
    }
    store.last = { dest = dest, previous = prevActive, status = report.status, from = from, problems = #problems > 0 and problems or nil }
    ES.ReleaseCache()
    return true, report
end

---------------------------------------------------------------------------
-- Once, after the reload
---------------------------------------------------------------------------
R:On("PLAYER_LOGIN", function()
    if not ST.db then return end
    local last = ST.db.eui and ST.db.eui.last
    if not last then return end
    ST.db.eui.last = nil
    if last.status == "stored" then
        R.Print("EllesmereUI profile \"%s\" from %s was added. This spec has its own assigned profile, so \"%s\" is still the one in use.", last.dest, last.from or "?", last.previous or "?")
    else
        R.Print("EllesmereUI profile \"%s\" from %s was added and is now in use. \"%s\" is unchanged; switch back in EllesmereUI > Profiles.", last.dest, last.from or "?", last.previous or "?")
    end
    if last.problems then
        R.Print("TwichUI noticed something unexpected in EllesmereUI's profiles: %s. Check EllesmereUI > Profiles.", table.concat(last.problems, "; "))
    end
end)
