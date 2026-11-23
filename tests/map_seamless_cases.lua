-- Additional production-path regressions and a reproducible mixed navigation course.
-- This receives the existing synthetic MapCanvas fixture, not a second implementation of the map.
return function(t)
  local c, R, VM, MV, MW, MA, MD, MCV, MXP = t.c, t.R, t.VM, t.MV, t.MW, t.MA, t.MD, t.MCV, t.MXP
  local SC, VIEW = t.SC, t.VIEW
  local function near(a, b, message, eps) assert(math.abs(a - b) < (eps or 1e-8), message) end
  local function finiteView()
    local u, v, z = MV.View()
    assert(VM.Finite(u) and VM.Finite(v) and VM.Finite(z) and z >= 1 and z <= 288 + 1e-8, "finite bounded view")
    assert(VM.Finite(SC.st.scale) and SC.st.scale > 0, "positive canvas scale")
    return u, v, z
  end
  -- Internal native host changes must not publish a temporary reset camera or
  -- clear/rebind an interior that remains visible in the same world viewport.
  do
    t.tidy(); t.closeMap(); t.openMap(1415); MXP.Set("smooth", false)
    local u, v = MW.ToWorld(1455, .5, .5)
    MV.GlideTo(u, v, 48); t.Tick()
    local city = MA.City(1455)
    local before = R.MapPictures.Snapshot(city.pictures)
    assert(before.active > 0, "interior visible before host handoff")
    local original, observed = t.WMF.SetMapID, 0
    t.WMF.SetMapID = function(self, id)
      original(self, id)
      observed = observed + 1
      local x, y, z = MV.View()
      near(x, u, "native callback sees stable world x")
      near(y, v, "native callback sees stable world y")
      near(z, 48, "native callback sees stable zoom")
      assert(R.MapPictures.Snapshot(city.pictures).active == before.active, "no transient interior clear")
    end
    t.settle(); t.WMF.SetMapID = original
    local after = R.MapPictures.Snapshot(city.pictures)
    assert(observed == 1 and MV.MapID() == 1455 and after.binds == before.binds, "host handoff reuses interior bindings")
  end
  t.tidy(); t.closeMap(); t.openMap(1429)
  MXP.Set("smooth", false)
  local u, v = t.WorldOf(1429, 0.5, 0.5)
  MV.GlideTo(u, v, 20)
  t.wheel(0)
  local _, _, z = MV.View(); near(z, 20, "zero wheel does nothing")
  t.pointAt(u, v); t.wheel(2.5)
  _, _, z = MV.View(); near(z, 20 * 1.25 ^ 2.5, "wheel magnitude and fraction preserved")
  local before = SC.calls.instant
  for _, bad in ipairs({ 0/0, math.huge, -math.huge, "bad", false }) do
    assert(not MV.ZoomBy(bad) and not MV.GlideTo(bad, v, 20) and not MV.GlideTo(u, v, bad), "invalid motion rejected")
  end
  assert(not MV.FrameWorldRect(1, 0, 0, 1) and SC.calls.instant == before, "malformed motion never touches canvas")

  -- Inward and outward events after leaving a deep context must both remain ordinary wheel steps.
  local originalMax = MV.MaxZoomAt
  MV.MaxZoomAt = function() return 192 end
  MXP.Set("smooth", false); MV.GlideTo(u, v, 40); MXP.Set("smooth", true)
  MV.ZoomBy(7, 0, 0); t.Tick(0.02)
  MV.MaxZoomAt = function() return 48 end
  MV.ZoomBy(1, 10, 0); t.Run(0.3)
  local pending = 40 * 1.25 ^ 7
  _, _, z = MV.View(); near(z, pending, "inward scroll retains pending deeper target")
  MV.ZoomBy(-1, 10, 0); t.Run(0.3)
  _, _, z = MV.View(); near(z, pending / 1.25, "outward scroll never snaps to the new context limit")
  MV.MaxZoomAt = originalMax
  MXP.Set("smooth", false); MV.GlideTo(u, v, 10); MXP.Set("smooth", true)
  MV.ZoomBy(5, 0, 0); t.Tick(0.01)
  MXP.Set("maxZoom", 16); t.Run(0.3)
  local _, _, limited = MV.View()
  near(limited, 16, "live maximum preference also limits the pending destination")
  MXP.Set("maxZoom", 48)

  -- Reversing a pending wheel sequence at the same cursor is reversible away from boundaries.
  MXP.Set("smooth", false); MV.GlideTo(u, v, 20); MXP.Set("smooth", true)
  for i = 1, 40 do
    local sx, sy = (i % 3 - 1) * 440, (i % 2 - 0.5) * 600
    MV.ZoomBy(2, sx, sy); t.Tick(0.03)
    MV.ZoomBy(-2, sx, sy); t.Run(0.3)
    local ru, rv, rz = MV.View()
    near(ru, u, "reversible wheel x"); near(rv, v, "reversible wheel y"); near(rz, 20, "reversible wheel zoom")
  end
  -- The native cursor API converts physical pixels by effective UI scale before view arithmetic.
  local cursor = SC.GetCursorPosition
  for _, scale in ipairs({ 0.65, 1.25, 2 }) do
    t.pointAt(u + 0.002, v - 0.001)
    local rawX, rawY = SC.cursor.x * scale, SC.cursor.y * scale
    SC.GetCursorPosition = function() return rawX / scale, rawY / scale end
    local ax, ay = MV.CursorWorld()
    MV.ZoomBy(1); t.Run(0.3)
    local bx, by = MV.CursorWorld()
    near(ax, bx, "scaled cursor x"); near(ay, by, "scaled cursor y")
    SC.GetCursorPosition = cursor
  end

  -- A changed/temporarily zero viewport retains the last rendered world view, including mid-animation.
  MXP.Set("smooth", false); MV.GlideTo(u, v, 30); t.Tick()
  MXP.Set("smooth", true); MV.ZoomBy(1, 40, -30); t.Tick()
  local bu, bv, bz = MV.View()
  VIEW.w, VIEW.h = 0, 0
  t.Providers("OnCanvasSizeChanged")
  before = SC.calls.instant
  t.Run(0.2)
  assert(not MV.Ready() and not MV.Animating() and SC.calls.instant == before, "zero-size layout writes nothing")
  VIEW.w, VIEW.h = 460, 900
  t.Providers("OnCanvasSizeChanged"); t.Tick()
  local au, av, az = finiteView()
  near(au, bu, "resize center x"); near(av, bv, "resize center y"); near(az, bz, "resize zoom")
  VIEW.w, VIEW.h = 1000, 666
  t.Providers("OnCanvasSizeChanged"); t.Tick()
  MXP.Set("smooth", false)

  -- Invalid saved values are read as defaults without deleting unrelated profile data.
  local saved = c.TwichUIDB.ui
  for _, ui in ipairs({ true, 1, "bad" }) do
    c.TwichUIDB.ui = ui
    assert(MXP.Get("maxZoom") == 48, "malformed saved UI container")
  end
  c.TwichUIDB.ui = saved
  local pref = saved.mapExplore
  for _, bad in ipairs({ 0/0, math.huge, "48", false, {} }) do
    pref.maxZoom = bad
    assert(MXP.Get("maxZoom") == 48, "malformed saved zoom reads as default")
  end
  pref.maxZoom = nil

  -- Realistic native refresh ordering: refreshed paintings hide again; unrelated markers never hide.
  t.nativeBase:Show(); t.nativeExploration:Show()
  t.WMF:RefreshAllDataProviders()
  assert(not t.nativeBase.shown and not t.nativeExploration.shown and t.nativeQuest.shown, "refresh cannot cover close detail")
  -- A hidden/released native pool object must not be resurrected on detach.
  local pool = t.WMF.detailLayerPool
  local enumerate, replacement = pool.EnumerateActive, t.Obj()
  pool.EnumerateActive = function()
    local done = false
    return function() if not done then done = true return replacement end end
  end
  MA.SyncNative(true); MA.SyncNative(false)
  assert(replacement.shown and not t.nativeBase.shown, "released native layer is not restored")
  pool.EnumerateActive = enumerate; t.nativeBase:Show(); MA.SyncNative(true)

  before = SC.calls.instant
  t.SetCombat(true)
  assert(not MV.ZoomBy(1) and not MV.GlideTo(u, v, 20), "combat motion leaves the native canvas alone")
  R:SetEnabled("mapExplore", false)
  assert(MV.Installed() and SC.calls.instant == before, "combat disable defers native changes")
  t.SetCombat(false); c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(not MV.Installed(), "deferred disable completes out of combat")
  R:SetEnabled("mapExplore", true)
  -- Opening at zero size then receiving a different native map must not frame the stale pending map.
  t.closeMap(); VIEW.w, VIEW.h = 0, 0; t.openMap(1429)
  assert(not MV.Ready(), "zero-size open waits for layout")
  VIEW.w, VIEW.h = 1000, 666; t.WMF:SetMapID(1436); t.Tick()
  local wl, wr, wt, wb = MW.Rect(1436)
  local pu, pv, pz = MV.View()
  near(pu, (wl + wr) / 2, "new native map owns pending layout x")
  near(pv, (wt + wb) / 2, "new native map owns pending layout y")
  near(pz, MV.FitZoom(1436), "stale zero-size map does not restore its zoom")

  -- WMO-only cave actually uses the production picture renderer and releases it on exit.
  local cave = MCV.Get("wmo:1")
  assert(cave and cave.floors[1].pictures, "WMO cave registered")
  MV.GlideTo((cave.u0 + cave.u1) / 2, (cave.v0 + cave.v1) / 2, MV.MaxZoomAt((cave.u0 + cave.u1) / 2, (cave.v0 + cave.v1) / 2))
  t.Run(0.2)
  assert(MCV.Surfaced(), "WMO interior surfaces")
  -- Check the production picture renderer's texture bindings directly as well.
  local set = R.MapPictures.Create(t.Obj())
  R.MapPictures.Set(set, cave.floors[1].pictures)
  local l, top, r, bottom = MV.ViewRect()
  R.MapPictures.Update(set, l, top, r, bottom, 0.8)
  local tex = set.used[1]
  assert(tex and tex.tex == 91001 and tex.rotation == 0.7 and tex.alpha == 0.8, "correct WMO texture and rotation")
  local made, binds = set.made, set.binds
  R.MapPictures.Update(set, l, top, r, bottom, 0.7)
  assert(set.made == made and set.binds == binds, "alpha update does not recreate or rebind")
  R.MapPictures.Update(set, 0, 0, 0.01, 0.01, 0.7)
  assert(not next(set.used) and tex.tex == nil and not tex.point, "culled pictures release textures and anchors")
  R.MapPictures.Clear(set)
  -- Native asynchronous readiness: retain the painting, fade the loaded resource,
  -- and bound waiting when an asset never becomes available.
  local loading, ready = t.Obj(), false
  loading.IsObjectLoaded = function() return ready end
  R.MapPictures.Show(loading, 0.8)
  t.Run(0.1)
  assert(not loading.shown and R.MapPictures.Snapshot().pending == 1, "unloaded picture does not obscure painted fallback")
  ready = true; t.Tick(0.05)
  assert(loading.alpha > 0 and loading.alpha < 0.8, "ready picture fades in")
  t.Run(0.2)
  near(loading.alpha, 0.8, "loaded texture reaches requested opacity")
  assert(R.MapPictures.Snapshot().pending == 0, "loaded texture stops polling")
  ready = false; R.MapPictures.Show(loading, 0.5); t.Run(10.1)
  assert(not loading.shown and R.MapPictures.Snapshot().pending == 0, "missing texture has bounded readiness work")
  R.MapPictures.Show(loading, 0.5); R.MapPictures.Forget(loading)
  assert(R.MapPictures.Snapshot().pending == 0, "released texture cannot reappear after a late load")

  -- More than 80 valid tiles in a tall viewport: fade toward the painting before the cap.
  local tiles, added = MD.Tiles(0), {}
  local savedStrength = MXP.Get("detailStrength")
  MXP.Set("detailStrength", 70) -- explicit old blend cap remains honored at every budget boundary
  for col = 20, 50 do for row = 20, 50 do
    local key = col * 64 + row
    if not tiles[key] then tiles[key] = 950000 + key; added[#added + 1] = key end
  end end
  VIEW.w, VIEW.h = 360, 1600; t.Providers("OnCanvasSizeChanged"); t.Tick()
  MXP.Set("smooth", false)
  local over, partial = false, false
  for zoom = 22, 48 do
    MV.GlideTo(u, v, zoom); t.Tick()
    local s = MD.Snapshot()
    assert(s.tiles <= 80 and s.made <= 80, "dense/tall terrain budget remains bounded")
    if s.requested > 80 then over = true; assert(s.tiles == 0, "over-budget view retains the painted fallback") end
    if s.requested > 56 and s.requested < 80 and s.alpha > 0 then
      partial = true
      assert(s.alpha < VM.Fade(zoom, 20, 36) * 0.7, "detail fades before reaching budget")
    end
  end
  assert(over and partial, "dense course crosses both budget fade and cap")
  MXP.Set("detailStrength", savedStrength)
  for _, key in ipairs(added) do tiles[key] = nil end
  VIEW.w, VIEW.h = 1000, 666; t.Providers("OnCanvasSizeChanged"); t.Tick()

  -- No missing-data case can request limitless magnification of painted art.
  local cap = MV.MaxZoomAt(0.5, 0.8)
  assert(cap <= 4 and not MD.HasAt(0.5, 0.8), "ocean/missing detail uses a bounded painted fallback")
  -- The same view yields identical cave/terrain blending regardless of listener order.
  local a0, b0, a1, b1 = cave.u0, cave.v0, cave.u1, cave.v1
  local span = (a1 - a0) / 0.33
  local cu, cv = (a0 + a1) / 2, (b0 + b1) / 2
  local _, strength = MCV.StrengthAt(cu - span / 2, cv - span / 3, cu + span / 2, cv + span / 3)
  assert(strength > 0 and strength < 1, "partial cave blend exists")

  if MAP_PREVIEW_FILE then
    local f = assert(io.open(MAP_PREVIEW_FILE, "w"))
    local function capture(name, x, y, zoom)
      MV.GlideTo(x, y, zoom); t.Tick(); t.Tick()
      local l, top, r, bottom = MV.ViewRect()
      f:write(("scene\t%s\t%.12g\t%.12g\t%.12g\t%.12g\n"):format(name, l, top, r, bottom))
      local W, H = MW.Size()
      for _, obj in ipairs(t.OBJECTS) do
        if type(obj.tex) == "number" and obj.point and obj.point[1] == "TOPLEFT" and obj.point[2] == MA.Root() then
          local alpha, p = 1, obj
          while p do
            if not p.shown then alpha = 0 break end
            alpha = alpha * (p.alpha or 1)
            p = p.parent
          end
          if alpha > 0.001 then
            f:write(("texture\t%d\t%.12g\t%.12g\t%.12g\t%.12g\t%.6g\t%.6g\t%d\n")
              :format(obj.tex, obj.point[4] / W, -obj.point[5] / H, obj.width / W, obj.height / H, alpha, obj.rotation or 0,
                obj.parent and obj.parent.level or 0))
          end
        end
      end
    end
    MXP.Set("smooth", false)
    capture("World overview", 0.5, 0.5, 1)
    local function mapScene(name, id, x, y, zoom)
      local wu, wv = t.WorldOf(id, x, y)
      capture(name, wu, wv, zoom)
    end
    mapScene("Zone border and terrain", 1429, 0, 0.5, 40)
    mapScene("City plan and interior", 1455, 0.5, 0.5, 60)
    local painted = MCV.Get("cave:101")
    local pu, pv = (painted.u0 + painted.u1) / 2, (painted.v0 + painted.v1) / 2
    capture("Painted cave", pu, pv, MV.MaxZoomAt(pu, pv))
    capture("WMO interior", cu, cv, MV.MaxZoomAt(cu, cv))
    capture("Missing-detail fallback", 0.5, 0.8, cap)
    f:close()
  end

  local seed, operations = 73471, 4000
  local function random(n) seed = seed * 16807 % 2147483647; return seed % n end
  MV.GlideTo(u, v, 24); t.Tick()
  local startMade, maxTiles = MD.Snapshot().made, 0
  local startTime = os.clock()
  for i = 1, operations do
    local op = random(10)
    if op < 6 then
      MXP.Set("smooth", i % 3 ~= 0)
      local sx, sy = (random(3) - 1) * VIEW.w * 0.49, (random(3) - 1) * VIEW.h * 0.49
      local _, _, oldZ = MV.View()
      local l0, t0, r0, b0 = MV.ViewRect()
      local au0 = (l0 + r0) / 2 + sx / VIEW.w * (r0 - l0)
      local av0 = (t0 + b0) / 2 + sy / VIEW.h * (b0 - t0)
      MV.ZoomBy(random(2) == 0 and 1 or -1, sx, sy)
      t.Tick(0.01 + random(4) * 0.01)
      local l1, t1, r1, b1 = MV.ViewRect()
      local cu, cv, newZ = MV.View()
      -- Clamping at the world's boundary legitimately moves an anchor. Check every unbounded step.
      local expectedU = au0 - sx / VIEW.w * (r1 - l1)
      local expectedV = av0 - sy / VIEW.h * (b1 - t1)
      if expectedU > (r1 - l1) / 2 and expectedU < 1 - (r1 - l1) / 2
          and expectedV > (b1 - t1) / 2 and expectedV < 1 - (b1 - t1) / 2 then
        near(cu, expectedU, "stress cursor x"); near(cv, expectedV, "stress cursor y")
      end
    elseif op < 8 then
      t.press()
      assert(not MV.Animating(), "drag interrupts ease")
      -- Native pan writes normalized host offsets; test crossing the host's normal extents too.
      SC:InstantPanAndZoom(SC.st.scale, SC.st.cx + (random(21) - 10) * 0.2,
        SC.st.cy + (random(21) - 10) * 0.2, true)
      t.release()
    elseif op == 8 then
      local cu, cv = t.WorldOf(random(2) == 0 and 1429 or 1436, 0.5, 0.5)
      MV.GlideTo(cu, cv, 8 + random(36)); t.Run(0.5)
    else
      t.closeMap(); t.openMap(random(2) == 0 and 1429 or 1415)
      assert(not MV.Animating(), "reopen cancels old easing")
    end
    finiteView()
    local d = MD.Snapshot()
    assert(d.tiles <= 80 and d.made <= 80, "terrain pool bound across course")
    maxTiles = math.max(maxTiles, d.tiles)
    if i % 100 == 0 then
      t.Run(0.3)
      local x, y, zoom = MV.View()
      t.settle()
      local xx, yy, zz = MV.View()
      near(x, xx, "host switch x"); near(y, yy, "host switch y"); near(zoom, zz, "host switch zoom")
    end
  end
  t.settle()
  assert(t.Running() == 0, "no idle work after course")
  t.closeMap()
  assert(MD.Snapshot().tiles == 0 and t.Running() == 0 and t.nativeBase.shown and t.nativeExploration.shown,
    "close releases detail and restores native painting")
  print(("16 seamless regressions OK; seed=73471 operations=%d cpu=%.4fs newTerrainTextures=%d maxActive=%d")
    :format(operations, os.clock() - startTime, MD.Snapshot().made - startMade, maxTiles))
end
