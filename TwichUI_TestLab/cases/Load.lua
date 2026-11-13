-- TwichUI Test Lab: the saved-data load test (market data foundation 2.0, the A4 load gate; docs/testlab.md "Saved-data load test").
-- OPT-IN, development only. It measures how THIS client loads a large saved file, using the development-only companion addons
-- TwichUI_LoadTest (load on demand, one synthetic saved variable) and TwichUI_LoadTestClock (always loaded, remembers logout/login times).
-- Real saved data is never touched: generation goes through R.LoadTest (its own saved variable), and the three real roots stay under the
-- fingerprint like every other case. The procedure, what each number means and what none of them can tell are in docs/testlab.md.
--
-- A MANUAL group: its cases never run as a group (TL.Select leaves them out); each is started on its own, in order 1 to 5, with a /reload between.
--   loadtest.generate.<preset>   (devdata) build a synthetic version-2 market into the companion's saved variable, in 4 ms slices
--   loadtest.measure             (readonly) in a FRESH session (after /reload, before anything loaded the companion): time LoadAddOn
--   loadtest.reload              (readonly) the clock companion's record of the last /reload (total time; whether the big file was loaded)
--   loadtest.gc                  (readonly) one full garbage collection after the load: how long it took and what stayed
--   loadtest.clear               (devdata) empty the companion's saved variable (the next logout writes a small file again)

local R = TwichUI
local TL = R.TestLab
local WL, FX = TL.Workloads, TL.Fixtures

TL.Category{ id = "loadtest", label = "Saved-data load test (development)",
    blurb = "a guided workflow, one case at a time with a /reload between: it builds a large synthetic saved file in a development-only companion addon and times how the client loads it; never touches your data", manual = true }

local NAME = "TwichUI_LoadTest"
local function Api(fn) return C_AddOns and C_AddOns[fn] end
local function Exists() local f = Api("DoesAddOnExist") return f and f(NAME) == true end
local function IsLoaded() local f = Api("IsAddOnLoaded") return f and f(NAME) == true end
local clock = type(debugprofilestop) == "function" and debugprofilestop or nil

-- Set when this session generated data. A /reload starts a new Lua state, so the flag is gone exactly when the file has been written: it makes
-- loadtest.clear refuse to throw generated data away before the reload that writes it (the one mistake that silently spoils the test).
local generatedThisSession

-- dense: share of items listed every day three times (the rest are listed on about one day in eight)
local PRESETS = {
    { id = "heavy", items = 40000, dense = 1.0, about = "40,000 items, every one listed three times a day for 120 days (the upper bound of section 7.3)" },
    { id = "mixed", items = 40000, dense = 0.3, about = "40,000 items, 30% listed every day, the rest rarely (closer to section 6.3's mix)" },
    { id = "small", items = 4000, dense = 0.3, about = "4,000 items (a quick check of the procedure, not a measurement)" },
}

for _, ps in ipairs(PRESETS) do
    TL.Case{ id = "loadtest.generate." .. ps.id, cat = "loadtest", class = "devdata", needs = { "workshop" }, budget = 600, step = 1,
      about = "Step 1. Builds the synthetic market (" .. ps.about .. "). Run ONE preset, then /reload.",
      after = "Next: type /reload now (it writes the file), then run loadtest.reload, then loadtest.measure before anything else loads the companion.", run = function(t)
        if not Exists() then return t:Skip("the development-only addon TwichUI_LoadTest is not installed (copy the folder beside the Workshop)") end
        if not IsLoaded() then
            local ok, why = Api("LoadAddOn")(NAME)
            if not ok then return t:Skip("TwichUI_LoadTest could not be loaded: " .. tostring(why)) end
        end
        local LT = R.LoadTest
        generatedThisSession = ps.id
        local W = t.W
        local H2, D = W.History2, W.Dist
        local rng = FX.Rng(7640001)
        local function Make(i)
            local dense = rng:Next() < ps.dense
            local h2, c2 = WL.H2Item(H2, rng, WL.H2_T0, dense)
            local p, l = rng:Int(5, 90000), rng:Int(1, 25)
            local tiers = l >= 2 and rng:Int(2, 8) or 1
            local item = ("%.0f,1,%.0f,%.0f,%.0f"):format(p, l, l + rng:Int(0, 40), tiers > 1 and p + 7 or 0)
            local dist
            if tiers > 1 then
                local pp, qq, ll, mm = {}, {}, {}, {}
                for k = 1, tiers do pp[k], qq[k], ll[k] = p + (k - 1) * 7, 1 + rng:Int(0, 20), 1 + (k == 1 and 0 or rng:Int(0, 2)) if ll[k] > 1 then mm[k] = qq[k] end end
                local ok, text = pcall(D.Encode, pp, qq, ll, mm, tiers)
                dist = ok and text or nil
            end
            return item, dist, h2, c2
        end
        local job = assert(LT.Begin({ items = ps.items, preset = ps.id, days = 120, format = H2.FORMAT, make = Make }))
        local t0 = clock and clock()
        while not job:Step(4) do
            t:Progress(("item %d of %d"):format(job.done, job.total))
            t:Yield()
        end
        local meta = LT.Meta()
        t:Check(meta and meta.items == ps.items, "the companion's saved variable holds the generated market")
        t:Fact("loadtest.items", ps.items)
        t:Fact("loadtest.bytes_estimate", meta and meta.bytes or 0)
        if t0 then t:Fact("loadtest.generate_s", ("%.1f"):format((clock() - t0) / 1000)) end
        t:Note(ps.about .. ("; about %.1f MB of saved text (an estimate from the strings; the real file is written at logout)"):format((meta and meta.bytes or 0) / 1048576))
        t:Note("next: /reload (timed by TwichUI_LoadTestClock if installed), then run loadtest.measure FIRST, before anything else loads the companion")
    end }
end

TL.Case{ id = "loadtest.measure", cat = "loadtest", class = "readonly", budget = 60, step = 3,
  about = "Step 3. Right after the /reload, before anything else loads the companion: times loading the big file. Refused if it is already loaded.",
  after = "Next: optionally run loadtest.gc, then loadtest.clear when you are done measuring.", run = function(t)
    if not Exists() then return t:Skip("the development-only addon TwichUI_LoadTest is not installed") end
    if IsLoaded() then return t:Skip("TwichUI_LoadTest is already loaded in this session, so its load cannot be timed: /reload, then run this case before anything else") end
    if not clock then return t:Skip("debugprofilestop is not available in this client: nothing can be timed") end
    local h0, t0 = collectgarbage("count"), clock()
    local ok, why = Api("LoadAddOn")(NAME)
    local t1, h1 = clock(), collectgarbage("count")
    if not ok then return t:Skip("LoadAddOn refused: " .. tostring(why)) end
    local LT = R.LoadTest
    local meta = LT and LT.Meta()
    t:Fact("loadtest.loadaddon_ms", ("%.1f"):format(t1 - t0))
    t:Fact("loadtest.heap_before_kb", ("%.0f"):format(h0)); t:Fact("loadtest.heap_after_kb", ("%.0f"):format(h1))
    t:Fact("loadtest.items", meta and meta.items or 0); t:Fact("loadtest.bytes_estimate", meta and meta.bytes or 0)
    if LT and LT.fileAt and LT.loadedAt then
        t:Fact("loadtest.before_file_ms", ("%.1f"):format(LT.fileAt - t0))
        t:Fact("loadtest.file_to_loaded_ms", ("%.1f"):format(LT.loadedAt - LT.fileAt))
        t:Fact("loadtest.after_loaded_ms", ("%.1f"):format(t1 - LT.loadedAt))
        t:Fact("loadtest.saved_at_file", tostring(LT.dbAtFile)); t:Fact("loadtest.saved_at_loaded", tostring(LT.dbAtLoaded))
        if LT.dbAtFile == false and LT.dbAtLoaded == true then
            t:Note(("this client ran the addon's file first and read its saved variables after: %.1f ms between the file and ADDON_LOADED is the deserialization (plus nothing else of this addon)"):format(LT.loadedAt - LT.fileAt))
        elseif LT.dbAtFile == true then
            t:Note(("the saved variable existed before the file ran: the client read it first, so the deserialization is inside the %.1f ms before the file"):format(LT.fileAt - t0))
        else
            t:Note("the saved variable was not there at ADDON_LOADED: nothing was loaded (was it generated, and was the game reloaded since?)")
        end
    else
        t:Note("the companion did not record its file and load times: only the whole LoadAddOn call was timed")
    end
    t:Note(("heap %.1f MB -> %.1f MB (+%.1f MB): the loaded data, not yet collected garbage included"):format(h0 / 1024, h1 / 1024, (h1 - h0) / 1024))
    t:Check(meta ~= nil and (meta.items or 0) > 0, "the companion's saved file held generated data")
end }

TL.Case{ id = "loadtest.reload", cat = "loadtest", class = "readonly", budget = 5, step = 2,
  about = "Step 2. Shows the clock companion's record of the last /reload (how long it took, and whether the big file was written then).",
  after = "Next: run loadtest.measure now, before anything else loads the companion.", run = function(t)
    local C = R.LoadClock
    if not C then return t:Skip("the development-only addon TwichUI_LoadTestClock is not installed or not turned on") end
    local list = C.List()
    if #list == 0 then return t:Skip("no /reload has been recorded yet: /reload once with the clock turned on") end
    for i = math.max(1, #list - 4), #list do
        local r = list[i]
        local span = tonumber(r.toWorld)
        if span and span > 0 and span < 3600 then
            t:Note(("reload %d: %.2f s from logout to entering the world (%.2f s to the clock's own file); the large file was %s at that logout%s"):format(i, span,
                tonumber(r.toFile) or -1, r.loadTestLoaded and "LOADED (so written)" or "not loaded", r.items and (", " .. r.items .. " items") or ""))
        else
            t:Note(("reload %d: not measurable (span %s)"):format(i, tostring(r.toWorld)))
        end
    end
    local last = list[#list]
    if tonumber(last.toWorld) then t:Fact("loadtest.reload_s", ("%.2f"):format(last.toWorld)) end
    t:Fact("loadtest.reload_with_file", tostring(last.loadTestLoaded == true))
    t:Check(true, "")
end }

TL.Case{ id = "loadtest.gc", cat = "loadtest", class = "readonly", budget = 30, step = 4,
  about = "Step 4 (optional). One forced full garbage collection after the load: how long it took and what stayed.",
  after = "Next: loadtest.clear when you are done measuring.", run = function(t)
    if not clock then return t:Skip("debugprofilestop is not available") end
    local h0, t0 = collectgarbage("count"), clock()
    collectgarbage("collect")
    local t1, h1 = clock(), collectgarbage("count")
    t:Fact("loadtest.full_gc_ms", ("%.1f"):format(t1 - t0)); t:Fact("loadtest.heap_after_gc_kb", ("%.0f"):format(h1))
    t:Note(("one full collection: %.1f ms; heap %.1f MB -> %.1f MB. A forced collection is a hitch the game itself spreads out; this is an upper bound, not what play feels like"):format(t1 - t0, h0 / 1024, h1 / 1024))
    t:Check(true, "")
end }

TL.Case{ id = "loadtest.clear", cat = "loadtest", class = "devdata", budget = 10, step = 5,
  about = "Step 5. Only when every measurement is done: empties the synthetic saved variable. Refused in the session that generated it.",
  after = "Next: /reload so a small file is written; then delete the two companion folders if you are finished.", run = function(t)
    if generatedThisSession then
        return t:Skip(("refused: this session generated the %s data and no /reload has written it yet; clearing now would throw it away before it was measured. /reload, run loadtest.reload and loadtest.measure, then clear"):format(generatedThisSession))
    end
    if not Exists() then return t:Skip("the development-only addon TwichUI_LoadTest is not installed") end
    if not IsLoaded() then
        local ok, why = Api("LoadAddOn")(NAME)
        if not ok then return t:Skip("TwichUI_LoadTest could not be loaded: " .. tostring(why)) end
    end
    R.LoadTest.Clear()
    local meta = R.LoadTest.Meta()
    t:Check(meta and meta.items == 0, "emptied")
    t:Note("emptied: the next logout or /reload writes a small file. To remove the companions entirely, delete the two folders and WTF/.../SavedVariables/TwichUI_LoadTest*.lua")
end }
