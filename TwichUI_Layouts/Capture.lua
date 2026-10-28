-- TwichUI Layouts: capturing an author's settings through the adapters' allowlists (docs/layouts/publishing.md)
-- The one implementation of "what a layout may carry out of a profile". tools/layout_capture.lua (offline, from saved files)
-- and the authoring workspace (in game, from the live profiles the author names) both call it, so they cannot drift apart.
-- Pure: it reads the tables it is given and changes none of them; no game calls. The result holds copies.
--
--   Capture.Read(euiProfile, twichuiSlot) -> capture, report
--     euiProfile: one EllesmereUI profile table (profile.addons[...], profile root keys, unlockLayout), or nil
--     twichuiSlot: one TwichUI profile's table (TwichUIDB itself for the live profile), or nil
--     capture = { ellesmereui = { root, modules, layout } | nil, twichui = { groups, places } | nil }  (package fragments)
--     report  = { left = { { where, why } }, notes = { text }, counts = { fields, switches, defaults } }
--   Capture.Scan(capture, names, realms) -> found = { name, realm, guid, link, battletag }, where = { text }
--   Capture.Units(capture) -> { [adapter] = { units, parents } }, problems   (the capture as units, as the adapters read it)
--   Capture.Put(layer, unit, value) / Capture.Clear(layer, unit) / Capture.Locate(unit)
--     write or remove one unit in a layer's fragments (a package layer: { ellesmereui = {...}, twichui = {...} })
--
-- Kept for EllesmereUI: the profile-root keys in the adapter's ROOT, the module blobs in MODULES (less the STRIP keys) and
-- the layout links. Kept for TwichUI: the places in PLACES, and every managed field whose value differs from TwichUI's
-- default, but never a feature's on/off switch (a layout never turns a feature on or off). Everything else is listed in
-- `report.left` with the reason.

local R = TwichUI
local LY = R.Layouts
local C = {}
LY.Capture = C

local function Copy(v) return LY.Copy(v) end

local LAYOUT_TABLES = LY.Set({ "anchors", "widthMatch", "heightMatch", "phantomBounds", "widthMatchExtra", "heightMatchExtra" })

local function ReadPath(t, at, key)
    for _, k in ipairs(at) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) == "table" then return t[key] end
end

function C.Read(prof, slot)
    local EA, TA = LY.EllesmereAdapter, LY.TwichUIAdapter
    local report = { left = {}, notes = {}, counts = { fields = 0, switches = 0, defaults = 0 } }
    local function Left(where, why) report.left[#report.left + 1] = { where = where, why = why } end
    local capture = {}

    if type(prof) == "table" then
        local eui = { root = {}, modules = {}, layout = nil }
        for k, v in pairs(prof) do
            if k == "unlockLayout" then
                if type(v) == "table" then
                    eui.layout = {}
                    for lk, lv in pairs(v) do
                        if type(lv) == "table" and LAYOUT_TABLES[lk] then eui.layout[lk] = Copy(lv)
                        else Left("unlockLayout." .. tostring(lk), "not a layout link table") end
                    end
                end
            elseif EA.ROOT[k] then eui.root[k] = Copy(v)
            elseif k ~= "addons" then   -- the module blobs are taken below, one by one
                Left("profile." .. tostring(k), k == "customColors" and "custom colours stay the recipient's (architecture.md §1)"
                    or "not a key EllesmereUI's import takes, or not managed (AdapterEllesmere.lua ROOT)")
            end
        end
        for m, blob in pairs(type(prof.addons) == "table" and prof.addons or {}) do
            if not EA.MODULES[m] then Left("addons." .. tostring(m), "not in EllesmereUI's profile module map (ADDON_DB_MAP)")
            elseif type(blob) ~= "table" then Left("addons." .. m, "not a table")
            else
                local b = Copy(blob)
                for _, k in ipairs(EA.STRIP[m] or {}) do
                    if b[k] ~= nil then b[k] = nil; Left("addons." .. m .. "." .. k, "per-character or per-spec record (STRIP)") end
                end
                eui.modules[m] = b
            end
        end
        capture.ellesmereui = eui
    end

    if type(slot) == "table" then
        local groups = {}
        for _, f in pairs(TA.Fields()) do
            local v = ReadPath(slot, f.at, f.key)
            if v ~= nil and not R.TwichConfig.ValueOk(f, v) then v = nil end
            if f.switch then report.counts.switches = report.counts.switches + 1
            elseif v == nil or LY.Same(v, f.default) then report.counts.defaults = report.counts.defaults + 1
            else
                report.counts.fields = report.counts.fields + 1
                groups[f.group] = groups[f.group] or {}
                groups[f.group][f.slot] = groups[f.group][f.slot] or {}
                groups[f.group][f.slot][f.key] = Copy(v)
            end
        end
        local places = {}
        for id, p in pairs(TA.PLACES) do
            local t = slot
            for _, k in ipairs(p.path) do t = type(t) == "table" and t[k] or nil end
            if type(t) == "table" and type(t.x) == "number" and type(t.y) == "number" then
                places[id] = p.kind == "point" and { point = t.point, x = t.x, y = t.y } or { x = t.x, y = t.y }
            else report.notes[#report.notes + 1] = "TwichUI place " .. id .. ": not set in the profile (the feature's default)" end
        end
        capture.twichui = { groups = groups, places = places }
    end
    return capture, report
end

---------------------------------------------------------------------------
-- Nothing personal: the character and realm names of the account, GUIDs, links and BattleTags, as whole words
---------------------------------------------------------------------------
local function Word(s, w) return s:find("%f[%w]" .. w:gsub("%p", "%%%0") .. "%f[%W]") ~= nil end

-- names, realms: sets { [text] = true }. Counts only; the names themselves are never put in a result.
function C.Scan(capture, names, realms)
    local found = { name = 0, realm = 0, guid = 0, link = 0, battletag = 0 }
    local where = {}
    local function Walk(v, path)
        if type(v) == "table" then
            for k, x in pairs(v) do
                if type(k) == "string" then Walk(k, path .. "[key]") end
                Walk(x, path .. "." .. tostring(k))
            end
        elseif type(v) == "string" then
            local hit
            for nm in pairs(names or {}) do if Word(v, nm) then found.name = found.name + 1; hit = "name" end end
            for rl in pairs(realms or {}) do if Word(v, rl) then found.realm = found.realm + 1; hit = "realm" end end
            if v:find("Player%-%d+%-%x+") then found.guid = found.guid + 1; hit = "guid" end
            if v:find("|H", 1, true) then found.link = found.link + 1; hit = "link" end
            if v:find("[%a]#%d%d%d%d") then found.battletag = found.battletag + 1; hit = "battletag" end
            if hit and #where < 20 then where[#where + 1] = hit .. " at " .. path end
        end
    end
    Walk(capture, "capture")
    return found, where
end

-- The names and realms of every character TwichUI knows ("Name - Realm" keys of TwichUIDB.profileKeys), as two sets.
-- A client with no realms (WoW: Forever, where a character has a first and a last name) has nothing to find in a realm, and
-- its "realm" is a word that legitimately appears in settings, so the realm set is empty there.
function C.KnownNames()
    local names, realms = {}, {}
    local realmless = R.Share and R.Share.Realmless and R.Share.Realmless()
    local keys = type(TwichUIDB) == "table" and type(TwichUIDB.profileKeys) == "table" and TwichUIDB.profileKeys or {}
    for key in pairs(keys) do
        local nm, realm = tostring(key):match("^(.-) %- (.+)$")
        if nm then names[nm] = true; if not realmless then realms[realm] = true end end
    end
    -- the character in play, by its whole name and by each word of it (on Forever the keys above hold only the first name)
    local full = R.Share and R.Share.SelfName and R.Share.SelfName()
    if type(full) == "string" and full ~= "" then
        names[full] = true
        for word in full:gmatch("%S+") do if #word >= 3 then names[word] = true end end
    end
    return names, realms
end

---------------------------------------------------------------------------
-- A capture as units (the adapters read it as a base layer, so every unit they allow is seen)
---------------------------------------------------------------------------
function C.Units(capture)
    local out, problems = {}, LY.Problems()
    for _, id in ipairs(LY.ADAPTER_ORDER) do
        local frag = capture[id]
        if frag ~= nil then
            local ctx = { problems = problems, dev = false, format = LY.FORMAT, layer = "base", where = "capture." .. id }
            local units, parents = LY.ADAPTERS[id].Normalize(frag, ctx)
            out[id] = { units = units or {}, parents = parents or {} }
        end
    end
    return out, problems
end

---------------------------------------------------------------------------
-- A unit's place in a layer's fragments
---------------------------------------------------------------------------
-- adapter id, path (keys to walk inside the adapter's fragment) | nil for a unit that is not a capturable one
function C.Locate(unit)
    if type(unit) ~= "string" then return nil end
    local EA, TA = LY.EllesmereAdapter, LY.TwichUIAdapter
    local root = unit:match("^ellesmereui:root%.([%w_]+)$")
    if root and EA.ROOT[root] then return "ellesmereui", { "root", root } end
    local mod = unit:match("^ellesmereui:addons%.([%w_]+)$")
    if mod and EA.MODULES[mod] then return "ellesmereui", { "modules", mod } end
    if unit == EA.LAYOUT_UNIT then return "ellesmereui", { "layout" } end
    local place = TA.PlaceOf(unit)
    if place then return "twichui", { "places", place } end
    local f = TA.FieldOf(unit)
    if f and not f.switch then return "twichui", { "groups", f.group, f.slot, f.key } end
    return nil
end

-- A layer's reset list (format 4): drops the unit from it. true when it was there.
local function Unreset(frag, unit)
    local list = type(frag) == "table" and frag.reset
    if type(list) ~= "table" then return false end
    for i = #list, 1, -1 do
        if list[i] == unit then
            table.remove(list, i)
            if #list == 0 then frag.reset = nil end
            return true
        end
    end
    return false
end

-- Writes a copy of value at the unit's place in the layer (making the tables on the way). false when the unit has no place.
-- A reset of the same unit in that layer is dropped: the layer now sets a value.
function C.Put(layer, unit, value)
    local adapter, path = C.Locate(unit)
    if not adapter then return false end
    layer[adapter] = layer[adapter] or {}
    Unreset(layer[adapter], unit)
    local t = layer[adapter]
    for i = 1, #path - 1 do
        if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
        t = t[path[i]]
    end
    t[path[#path]] = Copy(value)
    return true
end

-- Removes the unit from the layer, and the tables it leaves empty on the way up (never the adapter's own fragment, nor
-- the first table under it: a base layer's `root` stays).
function C.Clear(layer, unit)
    local adapter, path = C.Locate(unit)
    local frag = adapter and layer[adapter]
    if type(frag) ~= "table" then return false end
    local chain, t = { frag }, frag
    for i = 1, #path - 1 do
        t = type(t) == "table" and t[path[i]] or nil
        if type(t) ~= "table" then return false end
        chain[#chain + 1] = t
    end
    if chain[#chain][path[#path]] == nil then return false end
    chain[#chain][path[#path]] = nil
    for i = #chain, 3, -1 do
        if next(chain[i]) == nil then chain[i - 1][path[i - 1]] = nil else break end
    end
    return true
end

-- Puts the unit back to its addon's default in the layer (format 4): any value the layer sets is cleared and the unit goes in
-- the layer's reset list. Only a unit the adapter can reset (a TwichUI setting); false otherwise.
function C.Reset(layer, unit)
    local adapter = C.Locate(unit)
    if adapter ~= "twichui" or not LY.TwichUIAdapter.FieldOf(unit) then return false end
    C.Clear(layer, unit)
    layer[adapter] = layer[adapter] or {}
    local frag = layer[adapter]
    Unreset(frag, unit)
    frag.reset = frag.reset or {}
    frag.reset[#frag.reset + 1] = unit
    table.sort(frag.reset)
    return true
end

-- Drops the unit from the layer: its value and any reset of it. true when there was either.
function C.Forget(layer, unit)
    local adapter = C.Locate(unit)
    local cleared = C.Clear(layer, unit)
    return (adapter and Unreset(layer[adapter], unit)) or cleared
end

-- The value stored for the unit in the layer's fragments (not a copy), or nil.
function C.Get(layer, unit)
    local adapter, path = C.Locate(unit)
    local t = adapter and layer[adapter]
    for _, k in ipairs(path or {}) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end
