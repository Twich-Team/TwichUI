-- TwichUI Layout Setup: what the wizard remembers (TwichUIDB.layouts.wizard)
-- The layout the player chose (Classic or Compact Adventure), the picks they made (which option of each choice), and a
-- one-word note that the player started a reload from the wizard, so the result can be shown when the game comes back.
-- Nothing else: no frames, callbacks, timers or settings. It lives beside the install record (TwichUIDB.layouts.install,
-- TwichUI_Layouts' own) and never touches it. The scenario the preview shows and whether the full-size preview is open
-- are not remembered: they are how the preview looks right now, not a choice.
--
--   { v = 1, package = "<package id>", variant = "<variant id>", picks = { [choice id] = option id }, resume = "install" | "restore" }
--
-- (`variant` was added in Phase 5 and `package` in Phase 6, both without a new version: a record without a variant reads as
-- the first layout, and one without a package belongs to the package included with TwichUI; an older TwichUI that saves over
-- it simply forgets them. Picks and layout are only read for the package they were made for; another package starts from
-- its own defaults and its own first layout. The resume note belongs to no package.) Reading never writes. What is read is checked narrowly: a
-- pick that isn't an option of its choice goes back to that choice's default (and is reported, so the wizard can say the option is
-- gone and ask) and the rest is kept; a variant that isn't
-- one of the package's goes back to the first; anything that isn't a table is ignored whole. A record from a newer
-- TwichUI (v above this one) is not understood and not overwritten: the defaults are used and nothing is saved over it.

local R = TwichUI
local WZ = R.LayoutWizard
local S = {}
WZ.State = S

S.VERSION = 1
S.MAX_PICKS = 8             -- a package may ask up to LY.MAX_CHOICES (6) choices: the Adventure package asks five
S.INCLUDED = "twichui-adventure"   -- the package a record without a package id belongs to (the one included with TwichUI)

local function Root(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local l = TwichUIDB.layouts
    if type(l) ~= "table" then
        if not create then return nil end
        l = {}
        TwichUIDB.layouts = l
    end
    return l
end

local function OptionOf(choice, id)
    if type(id) ~= "string" then return nil end
    for _, o in ipairs(choice.options or {}) do if o.id == id then return o end end
end

-- The defaults of a package's choices: { [choice id] = option id }.
function S.Defaults(pkg)
    local out = {}
    for _, ch in ipairs(pkg and pkg.choices or {}) do out[ch.id] = ch.default end
    return out
end

local function VariantOk(variants, id)
    if type(id) ~= "string" then return false end
    for _, v in ipairs(variants or {}) do if v == id then return true end end
    return false
end

-- The saved layout and picks, checked against the package's variants (ids, the first being the default) and choices.
-- Returns { variant, picks, resume, repaired, newer, saved, dropped }. dropped = { [choice id] = option id }: a pick of an option
-- the package no longer offers (an author removed it). The default is used in its place, and the wizard says so and asks the
-- player to choose (Model.lua): it never quietly applies another option, whatever its name.
function S.Load(pkg, variants)
    local out = { variant = variants and variants[1] or nil, picks = S.Defaults(pkg), repaired = false, newer = false, saved = {}, dropped = {} }
    local root = Root(false)
    local raw = root and root.wizard
    if raw == nil then return out end
    if type(raw) ~= "table" then out.repaired = true return out end
    if type(raw.v) ~= "number" or raw.v ~= raw.v or raw.v % 1 ~= 0 or raw.v < 1 then out.repaired = true return out end
    if raw.v > S.VERSION then out.newer = true return out end
    if raw.resume == "install" or raw.resume == "restore" then out.resume = raw.resume
    elseif raw.resume ~= nil then out.repaired = true end
    -- picks and layout were made for one package; another package starts from its own defaults
    local owner = raw.package
    if owner == nil then owner = S.INCLUDED end
    if type(owner) ~= "string" then out.repaired = true owner = S.INCLUDED end
    if pkg and pkg.id ~= owner then out.other = true return out end
    if raw.variant ~= nil then
        if VariantOk(variants, raw.variant) then out.variant = raw.variant else out.repaired = true end
    end
    if raw.picks ~= nil and type(raw.picks) ~= "table" then out.repaired = true end
    local saved = type(raw.picks) == "table" and raw.picks or {}
    out.saved = {}   -- the choices the player made (not left at their default), for a choice added after they set up
    for _, ch in ipairs(pkg and pkg.choices or {}) do
        local pick = saved[ch.id]
        if pick ~= nil then
            if OptionOf(ch, pick) then out.picks[ch.id] = pick out.saved[ch.id] = true
            else
                out.repaired = true
                if type(pick) == "string" and #pick <= 64 then out.dropped[ch.id] = pick end
            end
        end
    end
    for id in pairs(saved) do
        if type(id) ~= "string" then out.repaired = true
        else
            local known = false
            for _, ch in ipairs(pkg and pkg.choices or {}) do if ch.id == id then known = true end end
            if not known then out.repaired = true end
        end
    end
    return out
end

-- Whether a save would overwrite something newer than this version understands.
local function Newer()
    local root = Root(false)
    local raw = root and root.wizard
    return type(raw) == "table" and type(raw.v) == "number" and raw.v > S.VERSION
end

-- Remembers the layout, the picks (and a resume note, if any). Returns false when it must not (a newer record is there).
-- variant nil keeps the layout already remembered (a writer that only has picks to save must not forget it).
function S.Save(pkg, picks, resume, variant)
    if Newer() then return false end
    local root = Root(true)
    if not root then return false end
    if variant == nil and type(root.wizard) == "table" and (root.wizard.package or S.INCLUDED) == (pkg and pkg.id) then variant = root.wizard.variant end
    if type(variant) ~= "string" or #variant > 32 or not variant:match("^[%w%-]+$") then variant = nil end
    local saved = {}
    for _, ch in ipairs(pkg and pkg.choices or {}) do
        local pick = picks and picks[ch.id]
        if OptionOf(ch, pick) then saved[ch.id] = pick end
    end
    root.wizard = { v = S.VERSION, package = pkg and pkg.id or nil, variant = variant, picks = saved,
        resume = (resume == "install" or resume == "restore") and resume or nil }
    return true
end

-- The note that a reload was started from the wizard (so the result can be shown after it), kept with the picks.
function S.SetResume(pkg, picks, kind, variant) return S.Save(pkg, picks, kind, variant) end

-- Reads the resume note and clears it (writes only when there was one). Returns "install", "restore" or nil.
function S.TakeResume(pkg, picks, variant)
    local st = S.Load(pkg, variant and { variant } or nil)
    if not st.resume or Newer() then return nil end
    local root = Root(false)
    -- only the note goes; the picks and the layout stay as they were, whichever package they were made for
    if root and type(root.wizard) == "table" then root.wizard.resume = nil end
    return st.resume
end
