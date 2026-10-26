-- TwichUI Layouts: the ellesmereui adapter, the EllesmereUI suite (architecture.md §3, §4, §8; adapter-capabilities.md)
-- Only EllesmereUI's public functions are called: DecodeImportString, EncodePayload, ImportProfileSilent (never
-- reloads; "the caller owns the ReloadUI"), GetProfileList, GetActiveProfileName, GetProfilesDB (read), SwitchProfile,
-- DeleteProfile, and ExportProfile for a developer package built on the recipient's own profile. EllesmereUIDB is
-- never written here. Read in EllesmereUI 9.6.8 (EllesmereUI_Profiles.lua); nothing of it has been run in game yet.
--
-- An install imports into its own profile (the package's target name, cleanSlate), which EllesmereUI then makes the
-- active one. EllesmereUI's active profile is account-wide, so every character on the account sees it. The import builds
-- on the active profile and replaces whole module blobs; the payload holds every module of the base, so nothing is
-- inherited by accident. Restore switches back to the profile in use before and removes the install's profile.
--
-- Units: "ellesmereui:base" (the base layer's export string, or a developer package's { source = "active-profile" }),
-- "ellesmereui:addons.<module>" (a whole module blob from an export string), and the fields below, inside a blob. The
-- inner shape of a blob is EllesmereUI's and can change between versions, so only these fields are ever patched, and
-- after a reload only they are compared (EllesmereUI fills its defaults into a blob as it loads, so a whole blob never
-- reads back as it was imported; its presence is checked).
--
-- Not done in this phase, and refused by name when a package asks: the UI scale (it stays the recipient's:
-- applyUIScale = false), suite module enable states (disableAddons), positions and look units. Everything account-wide
-- that a profile string can carry is taken out first (EXCLUDED), so deleting the install's profile undoes the install.
--
-- Snapshot part: { active = the profile in use before, target, created, version, values = { [unit] = fingerprint } }
--
-- Phase 3 (format 2 packages) adds the author's settings as plain data instead of export strings, so a capture can be
-- reviewed line by line: root look keys ("ellesmereui:root.<key>", the ROOT allowlist), whole module blobs as tables,
-- and the layout links ("ellesmereui:layout", EllesmereUI's unlockLayout). Before encoding, the screen layer moves the
-- registered positions (POSITIONS) for this screen, sizes the components that have size fields, scales the registered
-- text sizes by the density factor (TEXT), and rewrites the offsets of links to a screen edge so EllesmereUI's own
-- anchor pass at load puts each element where the plan says. Links to another element are left alone: EllesmereUI
-- moves the child with its target. A stored position in a point format not read here is left as it is and reported.

local R = TwichUI
local LY = R.Layouts
local A = { id = "ellesmereui", contract = LY.CONTRACT, label = "EllesmereUI", effect = "reload" }
LY.EllesmereAdapter = A

local PREFIX = "ellesmereui:"
A.BASE_UNIT = PREFIX .. "base"
A.PROFILE_UNIT = PREFIX .. "profile"
A.DEV_SOURCE = "active-profile"

local function ES() return R.Ellesmere end
local function ST() return R.Setups end

local REQUIRED = { "DecodeImportString", "EncodePayload", "ImportProfileSilent", "GetProfileList", "GetActiveProfileName",
    "GetProfilesDB", "SwitchProfile", "DeleteProfile", "ExportProfile", "ImportProfile" }

-- The suite's module keys (canonical; EllesmereUI_Profiles.lua ADDON_DB_MAP).
A.MODULES = LY.Set({ "EllesmereUIActionBars", "EllesmereUINameplates", "EllesmereUIUnitFrames", "EllesmereUICooldownManager",
    "EllesmereUIResourceBars", "EllesmereUIRaidFrames", "EllesmereUIAuraBuffReminders", "EllesmereUIQoL",
    "EllesmereUIDragonRiding", "EllesmereUIBags", "EllesmereUIFriends", "EllesmereUIMythicTimer", "EllesmereUIQuestTracker",
    "EllesmereUIMinimap", "EllesmereUIDamageMeters", "EllesmereUIChat", "EllesmereUIDataBars", "EllesmereUIQuickdraw" })

-- The fields inside a module blob a package may set (the allowlist), each read in EllesmereUI 9.6.8's source:
-- EllesmereUIMinimap.lua's defaults (profile.minimap), EUI_Minimap_Info.lua GetCoordsModePos and MAP_POS_ANCHORS,
-- EUI_Minimap_Options.lua's "Show Coordinates" dropdown. A missing value reads as the default.
A.FIELDS = {
    ["minimap.coordsMode"] = { module = "EllesmereUIMinimap", path = { "minimap", "coordsMode" }, label = "Minimap > Show coordinates",
        values = LY.Set({ "never", "hover", "always" }), default = "always" },
    ["minimap.coordsPosition"] = { module = "EllesmereUIMinimap", path = { "minimap", "coordsPosition" }, label = "Minimap > Coordinates position",
        values = LY.Set({ "belowMap", "aboveMap", "topLeft", "top", "topRight", "left", "right", "bottomLeft", "bottom", "bottomRight" }),
        default = "topLeft" },
}
A.BY_UNIT = {}
for id, f in pairs(A.FIELDS) do
    f.id = id
    f.parent = PREFIX .. "addons." .. f.module
    f.unit = f.parent .. "." .. table.concat(f.path, ".")
    A.BY_UNIT[f.unit] = f
end

-- Taken out of every payload before it is imported: account-wide or personal (architecture.md §3). The UI scale, the
-- window and tooltip skins, spec assignments, the Cooldown Manager's spell layouts, the spec and condition overrides,
-- click-cast and the spell store, and the custom colours (a palette other profiles can pull from, so removing the
-- install's profile would not take it back). EllesmereUI's transport-only keys go too.
A.EXCLUDED = { "uiScale", "applyUIScale", "blizzSkinGlobals", "applyBlizzSkinGlobals", "assignedSpecs", "cdmSpells",
    "specOverrides", "specOverrideGroups", "specOverrideNextId", "condOverrides", "condOverrideGroups", "condOverrideNextId",
    "specUnlockOverrides", "condUnlockOverrides", "specBmOverrides", "condBmOverrides", "clickCast", "spellAssignments",
    "customColors", "unlockLayoutMeta", "_importEstablishPending", "overridesIncluded", "overridesExcluded", "partialImport",
    "layoutExcluded" }
-- Taken out of a module blob before it is imported, and refused in a package's blob: per-character data EllesmereUI
-- itself keeps out of a shared profile (as setup/Ellesmere.lua does), and the Cooldown Manager's per-spec records
-- (which specs the author has played and their spell mappings; EllesmereUI makes them again on demand, EUI_CDM_Spec.lua)
-- and the two keys its own import strips (ImportProfile).
A.PRIVATE = { EllesmereUIDataBars = { "characters" }, EllesmereUIQoL = { "chars" } }
A.STRIP = { EllesmereUIDataBars = { "characters" }, EllesmereUIQoL = { "chars" },
    EllesmereUICooldownManager = { "spec", "activeSpecKey", "specProfiles", "barGlows" } }

-- The profile-root keys a package may carry (the base layer): the ones EllesmereUI's import takes from a payload
-- (ImportProfile: fonts, darkMode, euiAccent; _migrations so the load-time migrations know the data's vintage).
-- customColors stays excluded (§11.5). chatBubbles and tooltipFixedPos are not taken by the import, so not managed.
A.ROOT = LY.Set({ "fonts", "darkMode", "euiAccent", "_migrations" })
A.ACCENT_UNIT = PREFIX .. "root.euiAccent"

-- EllesmereUI's accent: { useClass = true } or { custom = { r, g, b }, useClass = false } (ImportProfile copies it whole;
-- EllesmereUI_UICore.lua SetActiveProfileAccent / ResolveProfileAccent read exactly these two keys).
function A.AccentOk(v)
    if type(v) ~= "table" then return false end
    local n = 0
    for k, val in pairs(v) do
        n = n + 1
        if k == "useClass" then
            if type(val) ~= "boolean" then return false end
        elseif k == "custom" then
            if type(val) ~= "table" then return false end
            for c, x in pairs(val) do
                if not (c == "r" or c == "g" or c == "b") or type(x) ~= "number" or x ~= x or x < 0 or x > 1 then return false end
            end
            if val.r == nil or val.g == nil or val.b == nil then return false end
        else
            return false
        end
    end
    return n > 0
end

-- A signature of an accent that survives EllesmereUI's number round trip (its serializer writes numbers with tostring,
-- 14 digits, so an exact fingerprint of the floats would not match): "class", or the colour to three places.
function A.AccentSig(v)
    if type(v) ~= "table" then return "none" end
    if v.useClass == true then return "class" end
    local c = v.custom
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return ("rgb:%.3f,%.3f,%.3f"):format(c.r, c.g, c.b)
    end
    return "none"
end
A.LAYOUT_UNIT = PREFIX .. "layout"
local LAYOUT_KEYS = LY.Set({ "anchors", "widthMatch", "heightMatch", "phantomBounds", "widthMatchExtra", "heightMatchExtra" })

-- Positions the screen layer may move: where each is stored in its module blob ({ point, relPoint, x, y }, read in
-- EllesmereUI 9.6.8 and in the author's profile), its unlock key when it has a layout link, and for the components
-- whose frame this is, the size fields. check: a value that must match first (a DataBar is found by its id).
-- A package's geometry attaches each one it manages to a component (geometry.attach.ellesmereui).
local function Pos(module, path, label, extra)
    local p = { module = module, path = path, label = label }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end
local AB, UF, CDM = "EllesmereUIActionBars", "EllesmereUIUnitFrames", "EllesmereUICooldownManager"
A.POSITIONS = {
    -- the components' own frames: placed and sized from the component
    minimap = Pos("EllesmereUIMinimap", { "minimap", "position" }, "Minimap", { link = "EBS_Minimap",
        size = { w = { "minimap", "mapSize" }, square = true } }),     -- EUI_Minimap_Apply.lua: SetSize(mapSize, mapSize)
    chat = Pos("EllesmereUIChat", { "chat", "chatPosition" }, "Chat", { link = "ECHAT_MainChat",
        size = { w = { "chat", "chatSize", "w" }, h = { "chat", "chatSize", "h" } } }),   -- EUI_Chat_Position.lua
    meter = Pos("EllesmereUIDamageMeters", { "dm", "windows", 1, "position" }, "Damage meter", { link = "EDM_Win1",
        size = { w = { "dm", "windows", 1, "width" }, h = { "dm", "windows", 1, "height" } } }),   -- EUI_DamageMeters_State.lua
    -- elements that move with a component
    ["chat-toast"] = Pos("EllesmereUIChat", { "chat", "toastPosition" }, "Chat whisper toast"),
    ["bar-main"] = Pos(AB, { "barPositions", "MainBar" }, "Action bar 1", { link = "MainBar" }),
    ["bar-2"] = Pos(AB, { "barPositions", "Bar2" }, "Action bar 2", { link = "Bar2" }),
    ["bar-3"] = Pos(AB, { "barPositions", "Bar3" }, "Action bar 3", { link = "Bar3" }),
    ["bar-4"] = Pos(AB, { "barPositions", "Bar4" }, "Action bar 4", { link = "Bar4" }),
    ["bar-5"] = Pos(AB, { "barPositions", "Bar5" }, "Action bar 5", { link = "Bar5" }),
    ["bar-stance"] = Pos(AB, { "barPositions", "StanceBar" }, "Stance bar", { link = "StanceBar" }),
    ["bar-pet"] = Pos(AB, { "barPositions", "PetBar" }, "Pet bar", { link = "PetBar" }),
    ["bar-xp"] = Pos(AB, { "barPositions", "XPBar" }, "Experience bar", { link = "XPBar" }),
    ["bar-rep"] = Pos(AB, { "barPositions", "RepBar" }, "Reputation bar", { link = "RepBar" }),
    ["extra-button"] = Pos(AB, { "barPositions", "ExtraActionButton" }, "Extra action button", { link = "ExtraActionButton" }),
    ["queue-status"] = Pos(AB, { "barPositions", "QueueStatus" }, "Queue status", { link = "QueueStatus" }),
    ["uf-player"] = Pos(UF, { "positions", "player" }, "Player frame", { link = "player" }),
    ["uf-target"] = Pos(UF, { "positions", "target" }, "Target frame", { link = "target" }),
    ["uf-pet"] = Pos(UF, { "positions", "pet" }, "Pet frame", { link = "pet" }),
    ["uf-focus"] = Pos(UF, { "positions", "focus" }, "Focus frame", { link = "focus" }),
    ["uf-focustarget"] = Pos(UF, { "positions", "focustarget" }, "Focus target frame", { link = "focustarget" }),
    ["uf-targettarget"] = Pos(UF, { "positions", "targettarget" }, "Target of target frame", { link = "targettarget" }),
    ["uf-class-power"] = Pos(UF, { "positions", "classPower" }, "Class power", { link = "classPower" }),
    ["uf-boss"] = Pos(UF, { "positions", "boss" }, "Boss frames", { link = "boss" }),
    ["uf-player-cast"] = Pos(UF, { "positions", "playerCastbar" }, "Player cast bar", { link = "playerCastbar" }),
    ["uf-target-cast"] = Pos(UF, { "positions", "targetCastbar" }, "Target cast bar", { link = "targetCastbar" }),
    ["uf-focus-cast"] = Pos(UF, { "positions", "focusCastbar" }, "Focus cast bar", { link = "focusCastbar" }),
    ["uf-buffs"] = Pos(UF, { "playerAuraBars", "buffsPos" }, "Player buffs"),
    ["uf-debuffs"] = Pos(UF, { "playerAuraBars", "debuffsPos" }, "Player debuffs"),
    ["cdm-cooldowns"] = Pos(CDM, { "cdmBarPositions", "cooldowns" }, "Cooldowns bar"),
    ["cdm-buffs"] = Pos(CDM, { "cdmBarPositions", "buffs" }, "Buffs bar"),
    ["cdm-utility"] = Pos(CDM, { "cdmBarPositions", "utility" }, "Utility bar"),
    ["cdm-group-3"] = Pos(CDM, { "tbbGlobalGroups", "g3", "pos" }, "Tracked buff group 3", { link = "TBBG_g3" }),
    ["rb-cast"] = Pos("EllesmereUIResourceBars", { "castBar", "unlockPos" }, "Resource cast bar"),
    ["rb-swing"] = Pos("EllesmereUIResourceBars", { "swingTimer", "unlockPos" }, "Swing timer"),
    ["combat-text"] = Pos("EllesmereUIQoL", { "selfCombatText", "pos" }, "Combat text", { link = "EUI_SelfCombatText" }),
    ["databar-top"] = Pos("EllesmereUIDataBars", { "bars", 1, "savedPos" }, "Top data bar", { link = "EDB_3",
        check = { path = { "bars", 1, "id" }, value = 3 } }),           -- EllesmereUIDataBars.lua: key "EDB_" .. barId
    ["databar-location"] = Pos("EllesmereUIDataBars", { "bars", 2, "savedPos" }, "Minimap location text", { link = "EDB_4",
        check = { path = { "bars", 2, "id" }, value = 4 } }),
}
function A.Positions() return A.POSITIONS end

-- Text sizes the density factor scales (whole numbers, within bounds), each read by its module in 9.6.8.
A.TEXT = {
    { module = "EllesmereUIChat", path = { "chat", "chatFontSize" }, label = "Chat text size", max = 40 },
    { module = "EllesmereUIChat", path = { "chat", "tabFontSize" }, label = "Chat tab text size", max = 32 },
    { module = "EllesmereUIDamageMeters", path = { "dm", "leftFontSize" }, label = "Meter name text size", max = 32 },
    { module = "EllesmereUIDamageMeters", path = { "dm", "rightFontSize" }, label = "Meter value text size", max = 32 },
    { module = "EllesmereUIDamageMeters", path = { "dm", "hdrFontSize" }, label = "Meter title text size", max = 32 },
    { module = "EllesmereUIDamageMeters", path = { "dm", "barHeight" }, label = "Meter bar height", max = 60 },
}
for _, t in ipairs(A.TEXT) do
    local parts = {}
    for _, k in ipairs(t.path) do parts[#parts + 1] = tostring(k) end
    t.unit = PREFIX .. "addons." .. t.module .. "." .. table.concat(parts, ".")
end
A.TEXT_BY_UNIT = {}
for _, t in ipairs(A.TEXT) do A.TEXT_BY_UNIT[t.unit] = t end
local function PosUnit(id) return PREFIX .. "pos." .. id end

local function Unit(module) return PREFIX .. "addons." .. module end
local function ModuleOf(unit) return unit:match("^ellesmereui:addons%.([%w_]+)$") end

function A.Label(unit)
    if unit == A.PROFILE_UNIT then return "Active profile" end
    if unit == A.BASE_UNIT then return "Base profile" end
    if unit == A.LAYOUT_UNIT then return "Layout links" end
    local f = A.BY_UNIT[unit] or A.TEXT_BY_UNIT[unit]
    if f then return f.label end
    local root = unit:match("^ellesmereui:root%.(.+)$")
    if root == "euiAccent" then return "Accent colour" end
    if root then return "Look: " .. root end
    local pos = unit:match("^ellesmereui:pos%.(.+)$")
    if pos then return A.POSITIONS[pos] and A.POSITIONS[pos].label or pos end
    local m = ModuleOf(unit)
    return m and ("Module " .. m) or unit
end

-- A position for showing: "x, y" or "x, y, w × h".
local function ShowPos(v)
    if type(v) ~= "table" or type(v.x) ~= "number" then return nil end
    local s = ("%d, %d"):format(math.floor(v.x + 0.5), math.floor(v.y + 0.5))
    if v.w then s = s .. (", %d × %d"):format(math.floor(v.w + 0.5), math.floor(v.h + 0.5)) end
    return s
end

function A.Show(v)
    if v == nil then return "(default)" end
    if type(v) == "string" and v:sub(1, 5) == "!EUI_" then return "an EllesmereUI export" end
    if type(v) == "table" then return ShowPos(v) or (v.source and "your own profile" or "the package's settings") end
    return tostring(v)
end

function A.TargetName(name) return LY.Plain(name, R.Ellesmere and R.Ellesmere.LIMITS.name or 30) end

---------------------------------------------------------------------------
-- Detect: present, the functions this needs, the Forever build, the version the package asks for
---------------------------------------------------------------------------
local function Parts(v)
    local out = {}
    for n in tostring(v):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

function A.Older(a, b)   -- version a is older than b
    local pa, pb = Parts(a), Parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

-- { present, usable, version, why = "missing"|"no-api"|"not-forever"|"too-old", missing, untested, otherClient }, E
-- otherClient: let an EllesmereUI that isn't the Forever build through. Only a developer package asks for it (testing
-- the pipeline on another game client while Forever can't be played); what happens there proves nothing about Forever.
function A.Detect(req, otherClient)
    local E = rawget(_G, "EllesmereUI")
    local out = { present = type(E) == "table", version = ES() and ES().Version() or nil }
    if not out.present then out.why = "missing" return out end
    for _, fn in ipairs(REQUIRED) do
        if type(E[fn]) ~= "function" then out.why, out.missing = "no-api", fn return out end
    end
    if E.IS_FOREVER ~= true then
        if not otherClient then out.why = "not-forever" return out end
        out.otherClient = true
    end
    if type(req) == "table" and req.min and (not out.version or A.Older(out.version, req.min)) then out.why = "too-old" return out end
    out.usable = true
    out.untested = type(req) == "table" and req.tested ~= nil and out.version ~= req.tested or false
    return out, E
end

---------------------------------------------------------------------------
-- A fragment: { base = "<export>" | { source = "active-profile" } (base layer only; the source form only in a
--   developer package), modules = { [module] = "<export holding it>" | REMOVE }, fields = { [field id] = value | REMOVE } }
---------------------------------------------------------------------------
local NOT_YET = LY.Set({ "positions", "look", "uiScale", "disableAddons", "unlockLayout" })
local MAX_STRING = 4 * 1048576

local function ExportString(s) return type(s) == "string" and #s > 5 and #s <= MAX_STRING and s:sub(1, 5) == "!EUI_" end

-- A module blob given as data (format 2): a table with none of the keys STRIP takes out.
local function BlobOk(m, blob)
    if type(blob) ~= "table" then return false end
    for _, k in ipairs(A.STRIP[m] or {}) do if blob[k] ~= nil then return false, "not-allowed" end end
    return true
end

function A.Normalize(fragment, ctx)
    local P, units, parents = ctx.problems, {}, {}
    local data = (ctx.format or 1) >= 2   -- settings as data: root keys, table blobs, layout links
    for k in pairs(fragment) do
        if NOT_YET[k] then P.add("not-yet", ctx.where .. "." .. tostring(k))
        elseif (k == "root" or k == "layout") and not data then P.add("not-yet", ctx.where .. "." .. k)
        elseif k ~= "base" and k ~= "modules" and k ~= "fields" and k ~= "root" and k ~= "layout" then
            P.add("unknown-field", ctx.where .. "." .. tostring(k))
        end
    end
    local base = fragment.base
    if base ~= nil then
        if ctx.layer ~= "base" then P.add("base-only-in-base-layer", ctx.where .. ".base")
        elseif ExportString(base) then units[A.BASE_UNIT] = base
        elseif type(base) == "table" and base.source == A.DEV_SOURCE and next(base, next(base)) == nil then
            if ctx.dev then units[A.BASE_UNIT] = { source = A.DEV_SOURCE } else P.add("dev-source-not-allowed", ctx.where .. ".base") end
        else P.add("bad-value", ctx.where .. ".base") end
    elseif ctx.layer == "base" and not (data and fragment.root ~= nil) then
        P.add("no-base", ctx.where .. ".base")
    end
    if data and fragment.root ~= nil then
        -- the base layer carries the look; a wizard choice may carry the accent colour and nothing else of it
        if ctx.layer ~= "base" and ctx.layer ~= "choice" then P.add("base-only-in-base-layer", ctx.where .. ".root")
        elseif type(fragment.root) ~= "table" then P.add("not-table", ctx.where .. ".root")
        else
            for k, v in pairs(fragment.root) do
                if not A.ROOT[k] or (ctx.layer == "choice" and k ~= "euiAccent") then P.add("not-managed", ctx.where .. ".root." .. tostring(k))
                elseif v == nil or type(v) == "function" then P.add("bad-value", ctx.where .. ".root." .. k)
                elseif k == "euiAccent" and not A.AccentOk(v) then P.add("bad-value", ctx.where .. ".root." .. k)
                else units[PREFIX .. "root." .. k] = v end
            end
        end
    end
    if data and fragment.layout ~= nil then
        local ul = fragment.layout
        if ul == LY.REMOVE then units[A.LAYOUT_UNIT] = ul
        elseif type(ul) ~= "table" then P.add("not-table", ctx.where .. ".layout")
        else
            local ok = true
            for k, v in pairs(ul) do
                if not LAYOUT_KEYS[k] or type(v) ~= "table" then ok = false; P.add("unknown-field", ctx.where .. ".layout." .. tostring(k)) end
            end
            if ok then units[A.LAYOUT_UNIT] = ul end
        end
    end
    if fragment.modules ~= nil then
        if type(fragment.modules) ~= "table" then P.add("not-table", ctx.where .. ".modules")
        else
            for m, s in pairs(fragment.modules) do
                if not A.MODULES[m] then P.add("unknown-unit", ctx.where .. ".modules." .. tostring(m))
                elseif s == LY.REMOVE or ExportString(s) then units[Unit(m)] = s
                elseif data and type(s) == "table" then
                    local ok, why = BlobOk(m, s)
                    if ok then units[Unit(m)] = s else P.add(why or "bad-value", Unit(m)) end
                else P.add("bad-value", Unit(m)) end
            end
        end
    end
    if fragment.fields ~= nil then
        if type(fragment.fields) ~= "table" then P.add("not-table", ctx.where .. ".fields")
        else
            for id, v in pairs(fragment.fields) do
                local f = A.FIELDS[id]
                if not f then P.add("unknown-unit", ctx.where .. ".fields." .. tostring(id))
                elseif v == LY.REMOVE or (type(v) == "string" and f.values[v]) then
                    units[f.unit] = v
                    parents[f.unit] = f.parent
                else P.add("bad-value", f.unit) end
            end
        end
    end
    return units, parents
end

---------------------------------------------------------------------------
-- Reading EllesmereUI's profiles (never writing them)
---------------------------------------------------------------------------
local function Profiles(E)
    local ok, db = pcall(E.GetProfilesDB)
    if ok and type(db) == "table" and type(db.profiles) == "table" then return db.profiles end
    return {}
end

local function Active(E)
    local ok, name = pcall(E.GetActiveProfileName)
    return ok and name or nil
end

-- A field's stored value in a profile table (nil: not set, which reads as the default).
local function ReadField(profile, f)
    local t = type(profile) == "table" and type(profile.addons) == "table" and profile.addons[f.module]
    for i = 1, #f.path - 1 do
        if type(t) ~= "table" then return nil end
        t = t[f.path[i]]
    end
    if type(t) == "table" then return t[f.path[#f.path]] end
end

local function Ours(snap, target) return type(snap) == "table" and snap.created == true and snap.target == target end

function A.Capture(composed, target)
    local _, E = A.Detect(nil, true)   -- only after a plan that passed, so the client was already allowed
    local snap = { target = target, values = {}, version = ES().Version(), otherClient = E.IS_FOREVER ~= true or nil }
    snap.active = Active(E)
    local profiles = Profiles(E)
    snap.created = type(profiles[target]) ~= "table"
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then snap.values[e.unit] = LY.Fingerprint(ReadField(profiles[snap.active], f)) end
    end
    return snap
end

function A.CleanSnapshot(s)
    if type(s) ~= "table" then return false end
    if not (type(s.active) == "string" and #s.active <= 64 and A.TargetName(s.target)) then return false end
    if type(s.created) ~= "boolean" or type(s.values) ~= "table" then return false end
    if s.version ~= nil and not LY.Plain(s.version, 40) then return false end
    if s.otherClient ~= nil and type(s.otherClient) ~= "boolean" then return false end
    return true
end

---------------------------------------------------------------------------
-- The payload: decoded with EllesmereUI's own decoder, built up in a fresh table, never run
---------------------------------------------------------------------------
local function Decode(E, str)
    local ok, payload = pcall(E.DecodeImportString, str)
    if not ok or type(payload) ~= "table" or payload.type ~= "full" or type(payload.data) ~= "table"
        or type(payload.data.addons) ~= "table" then return nil end
    return payload
end

-- home: the recipient's own profile (where Restore goes back to, and what a developer base is exported from).
-- Returns payload | nil, why.
---------------------------------------------------------------------------
-- The screen layer: positions, sizes, link offsets and text sizes for this screen, written into the payload's data
---------------------------------------------------------------------------
local G = function() return LY.Geometry end

local function Read(t, path)
    for _, k in ipairs(path) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

local function Write(t, path, v)
    for i = 1, #path - 1 do
        local k = path[i]
        if t[k] == nil then t[k] = {} end
        if type(t[k]) ~= "table" then return false end
        t = t[k]
    end
    t[path[#path]] = v
    return true
end

local function Num(n) return type(n) == "number" and n == n and n > -20000 and n < 20000 end
local function PosOk(rec)
    return type(rec) == "table" and G().POINTS[rec.point] and (rec.relPoint == nil or G().POINTS[rec.relPoint])
        and Num(rec.x) and Num(rec.y)
end

-- EllesmereUI's screen-edge anchor targets: 1-unit strips just outside each edge (EUI_UnlockMode.lua, EDGES).
local function Strip(key, s)
    local W, H = s.w / 2, s.h / 2
    if key == "SCREEN_LEFT" then return { l = -W - 1, r = -W, x = -W - 0.5, b = -H, t = H, y = 0 } end
    if key == "SCREEN_RIGHT" then return { l = W, r = W + 1, x = W + 0.5, b = -H, t = H, y = 0 } end
    if key == "SCREEN_TOP" then return { l = -W, r = W, x = 0, b = H, t = H + 1, y = H + 0.5 } end
    if key == "SCREEN_BOTTOM" then return { l = -W, r = W, x = 0, b = -H - 1, t = -H, y = -H - 0.5 } end
end
A.IsScreenEdge = function(key) return Strip(key, { w = 2, h = 2 }) ~= nil end

-- Which child and target edges each link offset measures between (UM.ApplyAnchorPosition, EUI_UnlockMode_Positions.lua):
-- side LEFT: offsetX = child.r - target.l; RIGHT: child.l - target.r; TOP: offsetY = child.b - target.t;
-- BOTTOM: child.t - target.b; the other axis (and CENTER) centre to centre. The cross-axis edge pin: on a left/right
-- edge, side RIGHT: child.l - edge.r, else child.r - edge.l; on a top/bottom edge, side TOP: child.b - edge.t, else
-- child.t - edge.b.
local function LinkEdges(side)
    if side == "LEFT" then return "r", "l", "y", "y" end
    if side == "RIGHT" then return "l", "r", "y", "y" end
    if side == "TOP" then return "x", "x", "b", "t" end
    if side == "BOTTOM" then return "x", "x", "t", "b" end
    return "x", "x", "y", "y"
end
local function EdgePin(key, side)
    if key == "SCREEN_LEFT" or key == "SCREEN_RIGHT" then
        if side == "RIGHT" then return "l", "r" end
        return "r", "l"
    end
    if side == "TOP" then return "b", "t" end
    return "t", "b"
end

-- A link to a screen edge, its offsets moved by what the child's edges and the screen's edges moved.
-- dChild = { l, r, b, t, x, y } (how far each edge of the child moved). Returns the new info, or nil (left alone).
local function ShiftLink(info, dChild, canvas, screen)
    if type(info) ~= "table" or info.mode == "POINT" then return nil end
    local a, b = Strip(info.target, canvas), Strip(info.target, screen)
    if not a then return nil end
    local new = LY.Copy(info)
    local cx, tx, cy, ty = LinkEdges(info.side)
    if Num(info.offsetX) then new.offsetX = G().Round(info.offsetX + dChild[cx] - (b[tx] - a[tx])) end
    if Num(info.offsetY) then new.offsetY = G().Round(info.offsetY + dChild[cy] - (b[ty] - a[ty])) end
    local e = info.edge
    if type(e) == "table" and Num(e.offset) then
        local ea, eb = Strip(e.key, canvas), Strip(e.key, screen)
        if ea then
            local ce, te = EdgePin(e.key, e.side)
            new.edge.offset = G().Round(e.offset + dChild[ce] - (eb[te] - ea[te]))
        end
    end
    return new
end

-- Moves, sizes and relinks the registered positions in the payload's data d, and scales the text sizes.
-- Returns { [posId] = { rec, comp, label, sized } } and notes { { code, id } }.
local function Adapt(d, geo, attach)
    local placed, notes = {}, {}
    if not (geo and attach) then return placed, notes end
    local Gm = G()
    local anchors = type(d.unlockLayout) == "table" and type(d.unlockLayout.anchors) == "table" and d.unlockLayout.anchors or nil
    for _, id in ipairs(LY.SortedKeys(attach)) do
        local p = A.POSITIONS[id]
        local compId, pt = attach[id]:match("^([%w%-]+):?(%u*)$")
        local comp = geo.components[compId]
        local blob = d.addons[p.module]
        local rec = type(blob) == "table" and Read(blob, p.path) or nil
        if type(blob) ~= "table" then notes[#notes + 1] = { code = "module-absent", id = id }
        elseif p.check and Read(blob, p.check.path) ~= p.check.value then notes[#notes + 1] = { code = "not-found", id = id }
        elseif not PosOk(rec) then notes[#notes + 1] = { code = rec == nil and "not-stored" or "format", id = id }
        else
            local rel = rec.relPoint or rec.point
            local new = { point = rec.point, relPoint = rel }
            local dChild
            if p.size then
                -- the component's own frame: its place and size are the component's
                local rect = comp.rect
                new.x, new.y = Gm.Stored(rect, rec.point, rel, geo.screen)
                local w, h = math.floor(rect.w + 0.5), math.floor(rect.h + 0.5)
                Write(blob, p.size.w, w)
                if p.size.h then Write(blob, p.size.h, h) end
                new.w, new.h = w, p.size.square and w or h
                local ref = comp.ref
                dChild = { l = rect.l - ref.l, r = rect.r - ref.r, b = rect.b - ref.b, t = rect.t - ref.t, x = rect.x - ref.x, y = rect.y - ref.y }
            else
                local mv = Gm.Moved(comp, pt ~= "" and pt or nil)
                new.x, new.y = Gm.Follow({ rel = rel, x = rec.x, y = rec.y }, mv, geo.canvas, geo.screen)
                dChild = { l = mv.dx, r = mv.dx, x = mv.dx, b = mv.dy, t = mv.dy, y = mv.dy }
            end
            local stored = LY.Copy(rec)
            stored.x, stored.y = new.x, new.y
            Write(blob, p.path, stored)
            if p.link and anchors and type(anchors[p.link]) == "table" then
                local info = anchors[p.link]
                if A.IsScreenEdge(info.target) then
                    local shifted = ShiftLink(info, dChild, geo.canvas, geo.screen)
                    if shifted then anchors[p.link] = shifted else notes[#notes + 1] = { code = "link-kept", id = id } end
                end
            end
            placed[id] = { rec = new, comp = compId, label = p.label, sized = p.size ~= nil }
        end
    end
    if geo.factor ~= 1 then
        for _, t in ipairs(A.TEXT) do
            local blob = d.addons[t.module]
            local v = type(blob) == "table" and Read(blob, t.path) or nil
            if Num(v) then
                local n = math.max(6, math.min(t.max, math.floor(v * geo.factor + 0.5)))
                Write(blob, t.path, n)
                placed[t.unit] = { text = true, old = v, new = n, label = t.label }
            end
        end
    end
    return placed, notes
end
A.Adapt, A.ShiftLink = Adapt, ShiftLink   -- pure: the tests call them on captured data

-- home: the recipient's own profile (where Restore goes back to, and what a developer base is exported from).
-- geo, attach: the resolved screen and the package's attach map (nil: no screen layer).
-- Returns payload, placed, notes | nil, why.
local function BuildPayload(E, composed, home, dev, geo, attach)
    local base = composed.units[A.BASE_UNIT]
    local payload
    if base == nil then
        -- settings as data (format 2): a full payload made here, as EllesmereUI's own export shapes one
        local any = false
        for _, e in ipairs(composed.list) do if ModuleOf(e.unit) then any = true break end end
        if not any then return nil, "no-base" end
        payload = { version = 3, type = "full", data = { addons = {} } }
    else
        local str = base
        if type(base) == "table" then
            if not dev then return nil, "dev-source-not-allowed" end
            -- ExportProfile(name, modules, layout, cdm, cdmSpecs, globals, overrides, windowSkins): every module and its
            -- layout links; no Cooldown Manager spells, overrides, look, UI scale or window skins.
            local ok, s = pcall(E.ExportProfile, home, nil, true, false, nil, false, false, false)
            if not ok or not ExportString(s) then return nil, "eui-export" end
            str = s
        end
        payload = Decode(E, str)
        if not payload then return nil, "eui-decode" end
    end
    local d = payload.data
    for _, e in ipairs(composed.list) do
        local m = ModuleOf(e.unit)
        local root = e.unit:match("^ellesmereui:root%.(.+)$")
        if m then
            if type(e.value) == "table" then
                d.addons[m] = LY.Copy(e.value)
            else
                local p = Decode(E, e.value)
                if not p or type(p.data.addons[m]) ~= "table" then return nil, "eui-module-missing" end
                d.addons[m] = p.data.addons[m]
            end
        elseif root and A.ROOT[root] then
            d[root] = LY.Copy(e.value)
        elseif e.unit == A.LAYOUT_UNIT then
            d.unlockLayout = LY.Copy(e.value)
        end
    end
    for _, k in ipairs(A.EXCLUDED) do d[k] = nil end
    -- A developer base is the recipient's own profile: only the per-character data (PRIVATE) goes from its blobs.
    -- Everything the package brings loses every STRIP key.
    local own = type(base) == "table"
    local kept = 0
    for m, blob in pairs(d.addons) do
        if not A.MODULES[m] or type(blob) ~= "table" then d.addons[m] = nil
        else
            local strip = (own and composed.units[Unit(m)] == nil) and A.PRIVATE[m] or A.STRIP[m]
            for _, k in ipairs(strip or {}) do blob[k] = nil end
            kept = kept + 1
        end
    end
    if kept == 0 then return nil, "eui-no-modules" end
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then
            local t = d.addons[f.module]
            if type(t) ~= "table" then return nil, "eui-module-absent" end
            for i = 1, #f.path - 1 do
                local k = f.path[i]
                if t[k] == nil then t[k] = {} end
                if type(t[k]) ~= "table" then return nil, "eui-shape" end
                t = t[k]
            end
            t[f.path[#f.path]] = e.value
        end
    end
    local placed, notes = Adapt(d, geo, attach)
    if ST().SizeOf(d) > ES().LIMITS.data then return nil, "too-large" end
    return payload, placed, notes
end

-- What the inputs were: a short fingerprint (an export string by its checksum, not its text; a table by its
-- fingerprint), and the screen the places were worked out for.
local LibDeflate = LibStub("LibDeflate")
local function Inputs(composed, home, placed)
    local t = { home = home, placed = {} }
    for _, e in ipairs(composed.list) do
        local v = e.value
        if type(v) == "string" and #v > 64 then v = "#" .. tostring(LibDeflate:Adler32(v)) .. ":" .. #v
        elseif type(v) == "table" then v = LY.Fingerprint(v) end
        t[e.unit] = v
    end
    for id, pl in pairs(placed or {}) do t.placed[id] = pl.rec or pl.new end
    return LY.Fingerprint(t)
end

-- How a placed position reads for a plan row and what Verify expects: "@x,y" or "@x,y,w,h" (whole units).
local function Expected(rec)
    local s = ("@%d,%d"):format(math.floor(rec.x + 0.5), math.floor(rec.y + 0.5))
    if rec.w then s = s .. (",%d,%d"):format(rec.w, rec.h) end
    return s
end
A.Expected = Expected

---------------------------------------------------------------------------
-- Plan: read only. part = { adapter, target, active, home, rows, changes, nothing, reload, blocked, key, payload,
--   inputs, untested, version }. The payload is kept in memory only, for Apply.
---------------------------------------------------------------------------
function A.Plan(composed, ctx)
    local part = { adapter = A.id, effect = A.effect, rows = {}, changes = 0, reload = false }
    local det, E = A.Detect(ctx.requires, ctx.dev)
    part.version, part.untested, part.otherClient, part.dev = det.version, det.untested, det.otherClient, ctx.dev
    part.tested = type(ctx.requires) == "table" and ctx.requires.tested or nil
    if not det.usable then part.blocked = "eui-" .. det.why return part end
    -- EllesmereUI's own first-run picker is waiting to be answered this session: it ends in its own import and
    -- reload, which would replace an install made now. The flag is EllesmereUI's (read only).
    if E._firstInstallPending == true then part.blocked = "eui-first-run" return part end
    local profiles, active, target, snap = Profiles(E), Active(E), ctx.target, ctx.snapshot
    if type(active) ~= "string" then part.blocked = "eui-no-active" return part end
    local exists = type(profiles[target]) == "table"
    if exists and not Ours(snap, target) then part.blocked = "target-taken" return part end
    local home = snap and snap.active or active
    if type(profiles[home]) ~= "table" then part.blocked = "previous-gone" return part end
    local payload, placed, notes = BuildPayload(E, composed, home, ctx.dev, ctx.geometry, ctx.attach)
    if not payload then part.blocked = placed return part end
    part.payload, part.target, part.active, part.home = payload, target, active, home
    part.placed, part.notes = placed, notes
    part.inputs = Inputs(composed, home, placed)

    local from = exists and profiles[target] or profiles[active]
    local live = exists and active == target
    part.rows[1] = { unit = A.PROFILE_UNIT, label = "Active profile", old = active, new = target, change = not live,
        made = not exists }
    local modules = 0
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then
            local old = ReadField(from, f)
            part.rows[#part.rows + 1] = { unit = e.unit, label = f.label, old = old, new = e.value,
                change = not LY.Same(old, e.value), layer = e.layer }
        elseif ModuleOf(e.unit) or e.unit == A.LAYOUT_UNIT or e.unit:find("^ellesmereui:root%.") then
            modules = modules + 1
            part.rows[#part.rows + 1] = { unit = e.unit, label = A.Label(e.unit), old = nil, new = e.value, change = true,
                whole = true, layer = e.layer }
        end
    end
    -- the screen layer: each placed position (from the profile it would replace), and each scaled text size
    for _, id in ipairs(LY.SortedKeys(placed)) do
        local pl = placed[id]
        if pl.text then
            part.rows[#part.rows + 1] = { unit = id, label = pl.label, old = pl.old, new = pl.new, change = pl.old ~= pl.new, text = true }
        else
            local p = A.POSITIONS[id]
            local blob = type(from) == "table" and type(from.addons) == "table" and from.addons[p.module]
            local was = blob and Read(blob, p.path)
            local old
            if PosOk(was) then
                old = { x = was.x, y = was.y }
                if p.size then
                    old.w = Read(blob, p.size.w)
                    old.h = p.size.square and old.w or Read(blob, p.size.h)
                end
            end
            local same = old ~= nil and Num(old.x) and Expected(old) == Expected(pl.rec)
            part.rows[#part.rows + 1] = { unit = PosUnit(id), label = pl.label, old = old, new = pl.rec, change = not same,
                place = true, comp = pl.comp, sized = pl.sized }
        end
    end
    local keyRows = {}
    for _, row in ipairs(part.rows) do
        if row.change then part.changes = part.changes + 1 end
        keyRows[row.unit] = { LY.Fingerprint(row.old), row.whole and "whole" or LY.Fingerprint(row.new) }
    end
    -- Nothing to import: the install's profile is in use, every field reads as planned, and it was made from these
    -- same inputs (for a developer base, from the same profile name; that profile's later edits are not compared).
    part.nothing = part.changes == 0 and modules == 0 and ctx.lastInputs == part.inputs
    if not part.nothing and part.changes == 0 then
        part.changes = 1
        part.rows[1].change, part.rows[1].reimport = true, true
    end
    part.reload = not part.nothing
    part.key = LY.Canon({ target, active, home, part.inputs, keyRows, part.nothing })
    return part
end

---------------------------------------------------------------------------
-- Apply. Refused in combat (here, and by ImportProfileSilent). A failed import puts back the profile in use and removes
-- a profile it made. Returns { state, code, rollback, reload, stored, others }.
---------------------------------------------------------------------------
-- The recipient's profiles (by table identity) and spec assignments, read straight from EllesmereUI's profile store,
-- and the check that, the install's own profile aside, none was removed, replaced or added and no assignment changed.
-- (setup/Ellesmere.lua has the same check for sharing, but it goes through the sharing code's Forever-only gate.)
local function ProfilesSnapshot(E)
    local snap = { profiles = {}, assign = {} }
    local ok, db = pcall(E.GetProfilesDB)
    if not ok or type(db) ~= "table" or type(db.profiles) ~= "table" then return snap end
    for name, p in pairs(db.profiles) do snap.profiles[name] = p end
    for spec, name in pairs(type(db.specProfiles) == "table" and db.specProfiles or {}) do snap.assign[spec] = name end
    snap.checkable = true
    return snap
end

-- true when nothing else changed (or it could not be read: then checked = false), and how many things did.
local function OthersUnchanged(E, before, target)
    local after = ProfilesSnapshot(E)
    if not (before.checkable and after.checkable) then return true, 0, false end
    local n = 0
    for name, p in pairs(before.profiles) do if name ~= target and after.profiles[name] ~= p then n = n + 1 end end
    for name in pairs(after.profiles) do if name ~= target and before.profiles[name] == nil then n = n + 1 end end
    for spec, name in pairs(before.assign) do if after.assign[spec] ~= name then n = n + 1 end end
    for spec in pairs(after.assign) do if before.assign[spec] == nil then n = n + 1 end end
    return n == 0, n, true
end

function A.Apply(part)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat", rollback = "clean" } end
    if part.nothing then return { state = "skipped", code = "matches" } end
    local det, E = A.Detect(nil, part.dev)
    if not det.usable then return { state = "failed", code = "eui-" .. det.why, rollback = "clean" } end
    local target, home = part.target, part.home
    local before = ProfilesSnapshot(E)
    local existed = before.profiles[target] ~= nil
    local startActive = Active(E)

    local function Rollback()
        local now = Profiles(E)
        if Active(E) ~= startActive and type(now[startActive]) == "table" then pcall(E.SwitchProfile, startActive) end
        if Active(E) ~= startActive and type(now[home]) == "table" then pcall(E.SwitchProfile, home) end
        if not existed and type(Profiles(E)[target]) == "table" then pcall(E.DeleteProfile, target) end
        local clean = (Active(E) == startActive) and ((type(Profiles(E)[target]) == "table") == existed)
        return clean and "clean" or "partial"
    end

    -- Installing again: leave the install's own profile before it is replaced, so EllesmereUI never has to fall back
    -- to "Default" (what DeleteProfile does to the active profile).
    if startActive == target then
        pcall(E.SwitchProfile, home)
        if Active(E) ~= home then return { state = "failed", code = "eui-switch", rollback = Rollback() } end
    end
    local okE, str = pcall(E.EncodePayload, part.payload)
    if not okE or not ExportString(str) then return { state = "failed", code = "eui-encode", rollback = Rollback() } end
    local ok, done, err, status = pcall(E.ImportProfileSilent, { importString = str, profileName = target, cleanSlate = true,
        applyUIScale = false, autoAssignSpecs = false })
    if not ok then R.Fault("layouts: EllesmereUI import", done) end
    if not ok or done ~= true then
        return { state = "failed", code = (ok and err == "in combat") and "combat" or "eui-import", rollback = Rollback() }
    end
    -- nothing else about the recipient's profiles changed (the install's own profile aside)
    local fine, changed = OthersUnchanged(E, before, target)
    return { state = "done", reload = true, stored = status == "spec_locked", others = changed,
        code = (not fine) and "others-changed" or (status == "spec_locked" and "spec-locked" or nil) }
end

---------------------------------------------------------------------------
-- Verify: reads only (after the reload, at login). expect = { [unit] = fingerprint | "present" }.
---------------------------------------------------------------------------
function A.Verify(expect, snap)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then r.state, r.code = "unverifiable", "eui-" .. det.why return r end
    local prof = Profiles(E)[snap.target]
    if type(prof) ~= "table" then
        r.diffs[1] = { unit = A.PROFILE_UNIT, code = "target-missing" }
        r.state = "mismatch"
        return r
    end
    if Active(E) ~= snap.target then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-active" } end
    for _, unit in ipairs(LY.SortedKeys(expect)) do
        local f, m = A.BY_UNIT[unit] or A.TEXT_BY_UNIT[unit], ModuleOf(unit)
        local pos = unit:match("^ellesmereui:pos%.(.+)$")
        local root = unit:match("^ellesmereui:root%.(.+)$")
        if f then
            r.checked = r.checked + 1
            if LY.Fingerprint(ReadField(prof, f)) ~= expect[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
        elseif m then
            r.checked = r.checked + 1
            if type(prof.addons) ~= "table" or type(prof.addons[m]) ~= "table" then r.diffs[#r.diffs + 1] = { unit = unit, code = "missing" } end
        elseif pos and A.POSITIONS[pos] then
            -- a placed position: within a unit of the plan (EllesmereUI snaps positions to its pixel grid as it places them)
            r.checked = r.checked + 1
            local p = A.POSITIONS[pos]
            local blob = type(prof.addons) == "table" and prof.addons[p.module]
            local rec = blob and Read(blob, p.path)
            local want = { expect[unit]:match("^@(%-?%d+),(%-?%d+),?(%d*),?(%d*)$") }
            if not PosOk(rec) or not want[1] then r.diffs[#r.diffs + 1] = { unit = unit, code = "missing" }
            else
                local bad = math.abs(rec.x - tonumber(want[1])) > 1 or math.abs(rec.y - tonumber(want[2])) > 1
                if want[3] ~= "" and p.size then
                    local w = Read(blob, p.size.w)
                    local h = p.size.square and w or Read(blob, p.size.h)
                    bad = bad or not (Num(w) and Num(h)) or math.abs(w - tonumber(want[3])) > 1 or math.abs(h - tonumber(want[4])) > 1
                end
                if bad then r.diffs[#r.diffs + 1] = { unit = unit, code = "moved" } end
            end
        elseif unit == A.ACCENT_UNIT then
            -- the accent is the one root key read back by value: EllesmereUI doesn't rewrite it as it loads
            r.checked = r.checked + 1
            if prof.euiAccent == nil then r.diffs[#r.diffs + 1] = { unit = unit, code = "missing" }
            elseif "accent:" .. A.AccentSig(prof.euiAccent) ~= expect[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
        elseif unit == A.LAYOUT_UNIT or (root and A.ROOT[root]) then
            -- a whole table EllesmereUI rewrites as it loads (defaults merged in): its presence is checked
            r.checked = r.checked + 1
            if prof[root or "unlockLayout"] == nil then r.diffs[#r.diffs + 1] = { unit = unit, code = "missing" } end
        else
            r.unverifiable = r.unverifiable + 1
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

-- composed, part: what Verify reads back after the reload. part (the plan's) adds the placed positions and text sizes.
function A.Expect(composed, part)
    local out = {}
    for _, e in ipairs(composed.list) do
        if A.BY_UNIT[e.unit] then out[e.unit] = LY.Fingerprint(e.value)
        elseif e.unit == A.ACCENT_UNIT then out[e.unit] = "accent:" .. A.AccentSig(e.value)
        elseif ModuleOf(e.unit) or e.unit == A.LAYOUT_UNIT or e.unit:find("^ellesmereui:root%.") then out[e.unit] = "present" end
    end
    for id, pl in pairs(part and part.placed or {}) do
        if pl.text then out[id] = LY.Fingerprint(pl.new)
        else out[PosUnit(id)] = Expected(pl.rec) end
    end
    return out
end

---------------------------------------------------------------------------
-- Restore: back to the profile in use before, and the install's profile removed. Then a reload.
---------------------------------------------------------------------------
function A.PlanRestore(snap)
    local out = { adapter = A.id, actions = {} }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then out.blocked = "eui-" .. det.why return out end
    local profiles = Profiles(E)
    if Active(E) == snap.target then
        if type(profiles[snap.active]) ~= "table" then out.blocked = "previous-gone" return out end
        out.actions[#out.actions + 1] = { kind = "switch", from = snap.target, to = snap.active }
    end
    if snap.created and type(profiles[snap.target]) == "table" then out.actions[#out.actions + 1] = { kind = "delete", name = snap.target } end
    out.reload = #out.actions > 0
    out.key = LY.Canon(out.actions)
    return out
end

function A.Restore(snap)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat" } end
    local plan = A.PlanRestore(snap)
    if plan.blocked then return { state = "failed", code = plan.blocked } end
    local _, E = A.Detect(nil, snap.otherClient)
    local before = ProfilesSnapshot(E)
    for _, act in ipairs(plan.actions) do
        if act.kind == "switch" then
            pcall(E.SwitchProfile, act.to)
            if Active(E) ~= act.to then return { state = "failed", code = "eui-switch" } end
        else
            pcall(E.DeleteProfile, act.name)
            if type(Profiles(E)[act.name]) == "table" then return { state = "partial", code = "target-kept", reload = true } end
        end
    end
    local fine = OthersUnchanged(E, before, snap.target)
    return { state = "done", reload = plan.reload, code = (not fine) and "others-changed" or nil }
end

function A.VerifyRestore(snap, units)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then r.state, r.code = "unverifiable", "eui-" .. det.why return r end
    local profiles = Profiles(E)
    if snap.created and type(profiles[snap.target]) == "table" then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "target-still-there" } end
    if Active(E) ~= snap.active then
        r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-previous" }
    else
        for _, unit in ipairs(units) do
            local f = A.BY_UNIT[unit]
            -- Blobs, links, root keys, placed positions and text sizes exist only in the install's own profile, which
            -- the check above saw removed: nothing of them is left to read in the profile in use.
            local inTarget = snap.created and not f and (ModuleOf(unit) or unit == A.LAYOUT_UNIT or A.TEXT_BY_UNIT[unit]
                or unit:find("^ellesmereui:root%.") or unit:find("^ellesmereui:pos%."))
            if inTarget then
                r.checked = r.checked + 1
            elseif not f or snap.values[unit] == nil then r.unverifiable = r.unverifiable + 1
            else
                r.checked = r.checked + 1
                if LY.Fingerprint(ReadField(profiles[snap.active], f)) ~= snap.values[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
            end
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

LY.RegisterAdapter(A)
