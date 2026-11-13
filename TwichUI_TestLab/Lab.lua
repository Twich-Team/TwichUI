-- TwichUI Test Lab: the case registry and the case API (R.TestLab)
-- A DEVELOPMENT tool: a load-on-demand addon that is never packaged for players (.pkgmeta, tools/release.py). It runs selected TwichUI
-- code inside the game client and reports what it saw. docs/testlab.md has the whole picture; docs/workshop/testing-roadmap.md the plan.
--
-- A case is registered with TL.Case{ id, cat, class, needs, budget, run }:
--   id      a dotted name, unique ("price.unit.round-up")
--   cat     a registered category ("core", "client")
--   class   what the case may do (the registry refuses a case without one):
--             pure      calls production functions with EXPLICIT inputs only, on made-up data (never saved data, never the game)
--             readonly  reads live game state or real saved data and must leave it unchanged (bracketed by TL.Fingerprint)
--             owned     creates and reuses Lab-owned frames only (Probe.lua): never a control of the player's UI, never a click on one. Its
--                       category is opt-in (see TL.Category), and Runner releases every probe frame when a case or the run ends.
--             guided    asks the player to put the pointer somewhere and observes what the client reports, read only (Guided.lua). Its category
--                       is never part of an unqualified run: TL.Select(nil) leaves it out, and the window leaves its box unticked.
--   needs   { "workshop" } to get t.W = R.Workshop (loaded through the core's launcher, which refuses in combat)
--   budget  seconds the case may take across frames before it is abandoned (default 10, at most 60)
--   run     function(t): the case API below
--
-- THE CASE API (t):
--   t:Same(actual, expected, what)   record a failure unless they are equal (==)
--   t:Check(condition, what)         record a failure unless the condition is true
--   t:Skip(reason)                   end the case as skipped
--   t:Fact(key, value)               a reported number or word; not an assertion
--   t:Note(text)                     one line of evidence for the report, printed under the case (at most 16, each cut at 400 characters)
--   t:Yield()                        a cooperative slice boundary (never inside a pcall: Lua 5.1 cannot yield across one)
--   t:Wait(seconds)                  a pause across frames; nothing of this case is scheduled meanwhile
--   t:Bench(result)                  attach a benchmark result (Bench.lua) to the report's benchmark section (at most 4 per case)
--   t:Progress(text)                 what the running case is doing ("repetition 3 of 5"), shown while it runs
--
-- Which calls a case may never make (writes, scans, purchases, mail, trades, destruction) is enforced by tests/test_testlab.lua, which
-- scans these files; the list is in docs/testlab.md. This file never assigns to a saved-variable global.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL

TL.VERSION = "0.1.0-dev"
TL.CLASSES = { pure = true, readonly = true, owned = true, guided = true }
TL.SAVED_ROOTS = { "TwichUIDB", "TwichUIWorkshopDB", "TwichUIDiagnosticsDB" }
TL.MAX_BUDGET = 60
TL.MAX_GUIDED_BUDGET = 150   -- a person takes longer than a function
TL.DEFAULT_BUDGET = 10

TL.categories, TL.categoryOrder = TL.categories or {}, TL.categoryOrder or {}
TL.cases, TL.caseOrder, TL.rejected = TL.cases or {}, TL.caseOrder or {}, TL.rejected or {}

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
-- { id, label, blurb, guided, optin }: a group of cases the window offers as one checkbox. A guided category asks things of the player, so it
-- starts unticked and only runs when it is chosen by name. An OPT-IN category (the client API probes that build their own test frames) is the
-- same for the checkbox and for TL.Select(nil): it runs only when it is chosen by name, because it creates frames and changes their state.
function TL.Category(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or TL.categories[def.id] then return false end
    TL.categories[def.id] = { id = def.id, label = def.label or def.id, blurb = def.blurb or "", guided = def.guided == true, optin = def.optin == true or def.guided == true }
    TL.categoryOrder[#TL.categoryOrder + 1] = def.id
    return true
end

local function Reject(def, why)
    local id = type(def) == "table" and tostring(def.id) or "?"
    TL.rejected[#TL.rejected + 1] = { id = id, why = why }
    return nil, why
end

-- Returns the case, or nil and why. A refused case is listed in TL.rejected and never runs.
function TL.Case(def)
    if type(def) ~= "table" then return Reject(def, "not a table") end
    if type(def.id) ~= "string" or def.id == "" then return Reject(def, "no id") end
    if TL.cases[def.id] then return Reject(def, "duplicate id") end
    if not TL.CLASSES[def.class] then return Reject(def, "no safety class (pure, readonly, owned or guided)") end
    if not TL.categories[def.cat] then return Reject(def, "unknown category") end
    if type(def.run) ~= "function" then return Reject(def, "no run function") end
    local budget = tonumber(def.budget) or TL.DEFAULT_BUDGET
    local top = def.class == "guided" and TL.MAX_GUIDED_BUDGET or TL.MAX_BUDGET
    local case = { id = def.id, cat = def.cat, class = def.class, needs = def.needs or {}, run = def.run,
        budget = math.max(0.1, math.min(top, budget)) }
    TL.cases[case.id] = case
    TL.caseOrder[#TL.caseOrder + 1] = case.id
    return case
end

-- The registered cases of the chosen categories ({ core = true }), in registration order; nil chooses every category EXCEPT guided and opt-in
-- ones, which run only when named: nothing asks the player for anything, and no probe frame is made, unless the player (or a test) chose it.
function TL.Select(chosen)
    local out = {}
    for _, id in ipairs(TL.caseOrder) do
        local c = TL.cases[id]
        if chosen then
            if chosen[c.cat] then out[#out + 1] = c end
        elseif c.class ~= "guided" and not (TL.categories[c.cat] and TL.categories[c.cat].optin) then
            out[#out + 1] = c
        end
    end
    return out
end

function TL.Count(cat)
    local n = 0
    for _, id in ipairs(TL.caseOrder) do if TL.cases[id].cat == cat then n = n + 1 end end
    return n
end

-- What kind of evidence a case gives (the report's label):
--   synthetic  production code running in the client's Lua on made-up data
--   client     something observed in this game client
--   guided     observed with the player's help
function TL.Label(case)
    if case.class == "pure" then return "synthetic" end
    if case.class == "guided" then return "guided" end
    return "client"
end

---------------------------------------------------------------------------
-- The Workshop, loaded through the core's launcher (it refuses in combat); nil and a sentence when it cannot be had. The third answer is
-- true when THIS call loaded it (the Runner times that load apart from the case that needed it).
---------------------------------------------------------------------------
function TL.Workshop()
    local launcher = R.WorkshopLauncher
    if not launcher then return nil, "the core's Workshop launcher is not available" end
    if launcher.Loaded() then return R.Workshop, nil, false end
    local ok, why = launcher.Load()
    if ok then return R.Workshop, nil, true end
    return nil, launcher.Explain and launcher.Explain(why) or ("the Workshop could not be loaded (" .. tostring(why) .. ")")
end

---------------------------------------------------------------------------
-- A cheap fingerprint of the saved roots: how many keys, the version fields, and each market's time and size. It reads, never writes. A
-- case is bracketed by it; a difference fails the case. (It cannot tell the game's own change in that moment from a case's.)
---------------------------------------------------------------------------
function TL.Fingerprint()
    local parts = {}
    for _, name in ipairs(TL.SAVED_ROOTS) do
        local root = _G[name]
        if type(root) ~= "table" then
            parts[#parts + 1] = name .. "=none"
        else
            local n = 0
            for _ in pairs(root) do n = n + 1 end
            local s = name .. "=" .. n .. ";v=" .. tostring(root.v)
            local ws = root.workshop
            if type(ws) == "table" then s = s .. ";workshop.v=" .. tostring(ws.v) end
            if type(root.markets) == "table" then
                local keys = {}
                for k, m in pairs(root.markets) do
                    keys[#keys + 1] = tostring(k) .. ":" .. (type(m) == "table" and (tostring(m.at) .. "/" .. tostring(m.n)) or "?")
                end
                table.sort(keys)
                s = s .. ";markets=" .. table.concat(keys, ",")
            end
            parts[#parts + 1] = s
        end
    end
    return table.concat(parts, "|")
end

---------------------------------------------------------------------------
-- The case object
---------------------------------------------------------------------------
local T = {}
T.__index = T
TL.SKIP = {}   -- what t:Skip raises (a table, so no case can raise it by accident)

local MAX_FAILS = 8

local function Show(v)
    if type(v) == "string" then return ("%q"):format(v):sub(1, 80) end
    if type(v) == "number" then return ("%.14g"):format(v) end
    return tostring(v)
end

local function Fail(t, text)
    if #t.fails < MAX_FAILS then t.fails[#t.fails + 1] = text end
    t.failed = (t.failed or 0) + 1
end

function T:Same(actual, expected, what)
    self.checks = self.checks + 1
    if actual ~= expected then
        Fail(self, ("%s: expected %s, got %s"):format(what or "value", Show(expected), Show(actual)))
        return false
    end
    return true
end

function T:Check(cond, what)
    self.checks = self.checks + 1
    if not cond then Fail(self, what or "check failed") return false end
    return true
end

function T:Skip(reason)
    self.skipped = tostring(reason or "skipped")
    error(TL.SKIP, 0)
end

-- A reported value. Keys are short names ("client.lua.division_by_zero"); values are shown as text and cut short.
function T:Fact(key, value)
    local k = tostring(key):gsub("[^%w%._%-]", "_"):sub(1, 60)
    local v = tostring(value):gsub("[%c|]", " "):sub(1, 60)
    self.facts[#self.facts + 1] = { k, v }
end

function T:Note(text)
    if #self.notes < 16 then self.notes[#self.notes + 1] = tostring(text):sub(1, 400) end
end

function T:Yield()
    if coroutine.running() then coroutine.yield() end
end

-- A benchmark result for the report's benchmark section (the Runner copies it to the case's record). Bounded.
function T:Bench(result)
    self.bench = self.bench or {}
    if type(result) == "table" and #self.bench < 4 then self.bench[#self.bench + 1] = result end
end

function T:Progress(text)
    self.progress = tostring(text or ""):sub(1, 80)
end

-- A pause of about `seconds` across frames: the runner schedules no step for this case until the time has passed (the other work of the
-- frame is not affected, Stop and the budget still apply). Not inside a pcall.
function T:Wait(seconds)
    self.waitUntil = TL.Runner.Now() + math.max(0, tonumber(seconds) or 0)
    self:Yield()
end

function TL.NewT(case, W)
    return setmetatable({ id = case.id, class = case.class, W = W, R = R, fails = {}, facts = {}, notes = {}, checks = 0 }, T)
end
