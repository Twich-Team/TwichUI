-- TwichUI Layout Setup: what the wizard remembers (TwichUIDB.layouts.wizard)
-- The picks the player made (which option of each choice), and a one-word note that the player started a reload from
-- the wizard, so the result can be shown when the game comes back. Nothing else: no frames, callbacks, timers or
-- settings. It lives beside the install record (TwichUIDB.layouts.install, TwichUI_Layouts' own) and never touches it.
--
--   { v = 1, picks = { [choice id] = option id }, resume = "install" | "restore" }
--
-- Reading never writes. What is read is checked narrowly: a pick that isn't an option of its choice goes back to that
-- choice's default and the rest is kept; anything that isn't a table is ignored whole. A record from a newer TwichUI
-- (v above this one) is not understood and not overwritten: the defaults are used and nothing is saved over it.

local R = TwichUI
local WZ = R.LayoutWizard
local S = {}
WZ.State = S

S.VERSION = 1
S.MAX_PICKS = 8

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

-- The saved picks, checked against the package's choices. Returns { picks, resume, repaired, newer }.
function S.Load(pkg)
    local out = { picks = S.Defaults(pkg), repaired = false, newer = false }
    local root = Root(false)
    local raw = root and root.wizard
    if raw == nil then return out end
    if type(raw) ~= "table" then out.repaired = true return out end
    if type(raw.v) ~= "number" or raw.v ~= raw.v or raw.v % 1 ~= 0 or raw.v < 1 then out.repaired = true return out end
    if raw.v > S.VERSION then out.newer = true return out end
    if raw.picks ~= nil and type(raw.picks) ~= "table" then out.repaired = true end
    local saved = type(raw.picks) == "table" and raw.picks or {}
    for _, ch in ipairs(pkg and pkg.choices or {}) do
        local pick = saved[ch.id]
        if pick ~= nil then
            if OptionOf(ch, pick) then out.picks[ch.id] = pick else out.repaired = true end
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
    if raw.resume == "install" or raw.resume == "restore" then out.resume = raw.resume
    elseif raw.resume ~= nil then out.repaired = true end
    return out
end

-- Whether a save would overwrite something newer than this version understands.
local function Newer()
    local root = Root(false)
    local raw = root and root.wizard
    return type(raw) == "table" and type(raw.v) == "number" and raw.v > S.VERSION
end

-- Remembers the picks (and a resume note, if any). Returns false when it must not (a newer record is there).
function S.Save(pkg, picks, resume)
    if Newer() then return false end
    local root = Root(true)
    if not root then return false end
    local saved = {}
    for _, ch in ipairs(pkg and pkg.choices or {}) do
        local pick = picks and picks[ch.id]
        if OptionOf(ch, pick) then saved[ch.id] = pick end
    end
    root.wizard = { v = S.VERSION, picks = saved, resume = (resume == "install" or resume == "restore") and resume or nil }
    return true
end

-- The note that a reload was started from the wizard (so the result can be shown after it), kept with the picks.
function S.SetResume(pkg, picks, kind) return S.Save(pkg, picks, kind) end

-- Reads the resume note and clears it (writes only when there was one). Returns "install", "restore" or nil.
function S.TakeResume(pkg, picks)
    local st = S.Load(pkg)
    if not st.resume then return nil end
    S.Save(pkg, picks or st.picks, nil)
    return st.resume
end
