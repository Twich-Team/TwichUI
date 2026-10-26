dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Layout packages, Phase 3: the screen layer (TwichUI_Layouts/Geometry.lua) and the Classic Adventure package's rules.
-- The resolver is pure, so most of this needs no game: a small synthetic layout for each rule, then the real package
-- on the screens players have: the author's ultrawide, 16:9 and 16:10 at the same UI scale, pixel-perfect 1080p and
-- 1440p, 4K, 32:9, a smaller logical screen (UI scale 1.0), and the larger density. Then the conversions to how
-- EllesmereUI and TwichUI store places, checked against the author's captured data: on the author's own screen the
-- package must give back exactly what was captured, including EllesmereUI's link offsets.
-- None of this is in-game visual verification: docs/layouts/implementation-status.md lists what has to be looked at.

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function Near(a, b, tol) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 0.011) end

local function Copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = Copy(v) end
  return o
end

-- TwichUI and the layouts addon, offline (the adapters' registries are what the attach maps are checked against)
local c = SettingsClient({ name = "Geo", beforeInit = function(c) c.print = function() end end })
for line in io.lines(REPO .. "TwichUI_Layouts/TwichUI_Layouts.toc") do
  line = line:gsub("\r", ""):gsub("%s+$", "")
  if line ~= "" and not line:find("^#") then
    local chunk = assert(loadfile(REPO .. "TwichUI_Layouts/" .. line)); setfenv(chunk, c); chunk("TwichUI_Layouts", {})
  end
end
local LY = c.TwichUI.Layouts
local G = LY.Geometry
local EA, TA = LY.EllesmereAdapter, LY.TwichUIAdapter

---------------------------------------------------------------------------
-- 1. A small synthetic layout: one rule at a time
---------------------------------------------------------------------------
local function Spec()
  return {
    canvas = { w = 2000, h = 1000 }, margin = 0, area = { maxAspect = 2.4 },
    densities = { standard = 1, larger = 1.2 }, narrow = 1400,
    components = {
      block = { managed = true, ref = { x = 0, y = -300, w = 600, h = 400 }, anchor = { point = "BOTTOM", to = "area", rel = "BOTTOM" } },
      left = { managed = true, density = true, ref = { x = -800, y = -400, w = 300, h = 160 },
        anchor = { point = "BOTTOMLEFT", to = "area", rel = "BOTTOMLEFT" }, min = { w = 200, h = 100 }, max = { w = 340, h = 400 },
        room = { side = "right", of = "block", gap = 10 } },
      right = { managed = true, density = true, ref = { x = 850, y = 400, w = 200, h = 200 },
        anchor = { point = "TOPRIGHT", to = "area", rel = "TOPRIGHT" },
        narrow = { anchor = { point = "TOPLEFT", to = "area", rel = "TOPLEFT", x = 20, y = -20 } } },
      under = { managed = true, size = { w = 180, h = 300 }, anchor = { point = "TOPRIGHT", to = "right", rel = "BOTTOMRIGHT", x = 0, y = -10 } },
      card = { managed = true, ref = { x = 0, y = 300, w = 400, h = 80 }, anchor = { point = "TOP", to = "area", rel = "TOP" },
        above = { of = "block", gap = 10 } },
      mid = { ref = { x = 100, y = 50, w = 50, h = 50 }, anchor = { point = "CENTER", to = "screen", rel = "CENTER" } },
    },
  }
end

do
  local spec = Spec()
  local P = LY.Problems()
  Check(G.Check(spec, P) and P.n == 0, "the synthetic layout is valid")
  local canvas = assert(G.Resolve(spec, { w = 2000, h = 1000 }))
  for _, id in ipairs({ "block", "left", "right", "card", "mid" }) do
    local r, ref = canvas.components[id].rect, spec.components[id].ref
    Check(Near(r.x, ref.x, 1e-9) and Near(r.y, ref.y, 1e-9) and Near(r.w, ref.w, 1e-9) and Near(r.h, ref.h, 1e-9), "the canvas reproduces " .. id .. " exactly")
  end
  Check(Near(canvas.components.under.rect.t, 290, 1e-9) and Near(canvas.components.under.rect.r, 950, 1e-9), "a refless component from its explicit rule")
  Check(canvas.fits and #canvas.diagnostics == 0, "and fits, with nothing to report")

  -- wider: edges keep their distance; centre-anchored things don't move; nothing is multiplied by the screen ratio
  local wide = assert(G.Resolve(spec, { w = 2400, h = 1000 }))
  Check(Near(wide.components.left.rect.l, -1150, 1e-9) and Near(wide.components.right.rect.r, 1150, 1e-9), "the edges keep their distance (50) on a wider screen")
  Check(Near(wide.components.mid.rect.x, 100, 1e-9) and Near(wide.components.block.rect.x, 0, 1e-9), "centred things keep their offset (no scaling by 2400/2000)")
  Check(Near(wide.components.under.rect.r, wide.components.right.rect.r, 1e-9) and Near(wide.components.under.rect.t, wide.components.right.rect.b - 10, 1e-9), "anchored to another component: it moves with it")

  -- ultrawide past maxAspect: a centred composition area, not the far edges of the glass
  local ultra = assert(G.Resolve(spec, { w = 4000, h = 1000 }))
  Check(Near(ultra.area.w, 2400, 1e-9) and Near(ultra.components.left.rect.l, -1150, 1e-9) and Near(ultra.components.right.rect.r, 1150, 1e-9),
    "an ultrawide screen gets a central composition area (2.4:1)")
  Check(Near(ultra.components.mid.rect.x, 100, 1e-9), "a screen-anchored component still uses the screen")

  -- shorter: the block keeps its distance from the bottom, the card from the top
  local short = assert(G.Resolve(spec, { w = 2000, h = 800 }))
  Check(Near(short.components.block.rect.b, -400, 1e-9) and Near(short.components.card.rect.t, 400 - 160, 1e-9), "edge distances kept on a shorter screen")

  -- density: sizes grow from the anchored corner, within the bounds
  local big = assert(G.Resolve(spec, { w = 2000, h = 1000 }, { density = "larger" }))
  local l = big.components.left.rect
  Check(Near(l.l, -950, 1e-9) and Near(l.b, -480, 1e-9) and Near(l.w, 340, 1e-9) and Near(l.h, 192, 1e-9), "larger density: grows from its anchor, held at max width")
  Check(Near(big.components.block.rect.w, 600, 1e-9), "a component that doesn't scale with density keeps its size")
  Check(select(2, G.Resolve(spec, { w = 2000, h = 1000 }, { density = "huge" })) == "density", "an unknown density is refused")

  -- room: shrinks toward a neighbour, never under the minimum; the minimum winning is reported, and so is the overlap
  local roomy = assert(G.Resolve(spec, { w = 1500, h = 1000 }))
  Check(Near(roomy.components.left.rect.w, 300, 1e-9) and not roomy.narrow, "room leaves a component that doesn't overlap alone")
  local tight = assert(G.Resolve(spec, { w = 1300, h = 1000 }))
  local lt, bt = tight.components.left.rect, tight.components.block.rect
  Check(Near(lt.r, bt.l - 10, 1e-9) and Near(lt.l, -600, 1e-9) and Near(lt.w, 290, 1e-9), "room: the far edge stops short of the block, the anchored edge stays")
  local tighter = assert(G.Resolve(spec, { w = 1000, h = 1000 }))
  local lr = tighter.components.left.rect
  Check(Near(lr.w, 200, 1e-9), "room never goes under the readable minimum")
  local kinds = {}
  for _, d in ipairs(tighter.diagnostics) do kinds[d.code .. ":" .. d.id .. ":" .. tostring(d.other)] = true end
  Check(kinds["minimum:left:nil"] and kinds["overlap:block:left"] and not tighter.fits, "the minimum and the overlap that follows are both reported")

  -- narrow: below the narrow width, the narrow rule replaces the anchor
  Check(tighter.narrow and Near(tighter.components.right.rect.l, -500 + 20, 1e-9) and Near(tighter.components.right.rect.t, 480, 1e-9), "narrow override moves the component")
  Check(not roomy.narrow and tight.narrow, "and only below the narrow width")

  -- above: a card that would sit on the block is moved up clear of it
  local low = assert(G.Resolve(spec, { w = 2000, h = 560 }))
  local cr, br = low.components.card.rect, low.components.block.rect
  Check(cr.b >= br.t + 10 - 1e-9, "above: kept clear of the block")
  -- off screen and clamping
  local tiny = assert(G.Resolve(spec, { w = 500, h = 400 }))
  local off = {}
  for _, d in ipairs(tiny.diagnostics) do off[d.code .. ":" .. d.id] = true end
  Check(off["offscreen:block"] and not tiny.fits, "a component bigger than the screen is reported off screen")
  local s2 = Spec()
  s2.components.mid.managed, s2.components.mid.ref.x = true, 1060
  local clamp = assert(G.Resolve(s2, { w = 2000, h = 1000 }))
  Check(Near(clamp.components.mid.rect.r, 1000, 1e-9) and off and (function()
    for _, d in ipairs(clamp.diagnostics) do if d.code == "clamped" and d.id == "mid" then return true end end end)(), "partly off screen: moved back on, and said")
  -- unmanaged and zero-size components are never in the overlap check
  local s3 = Spec()
  s3.components.mid.ref = { x = 0, y = -300, w = 50, h = 50 }
  local un = assert(G.Resolve(s3, { w = 2000, h = 1000 }))
  Check(un.fits, "an unmanaged component over a managed one is not an overlap")

  -- deterministic: the same rules built in another order give the same output
  local again = {}
  local keys = {}
  for k in pairs(spec.components) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return a > b end)
  local s4 = Copy(spec); s4.components = {}
  for _, k in ipairs(keys) do s4.components[k] = Copy(spec.components[k]) end
  Check(LY.Canon(G.Resolve(s4, { w = 1777, h = 1000 })) == LY.Canon(G.Resolve(spec, { w = 1777, h = 1000 })), "deterministic: the same output whatever order the rules were built in")
  Check(LY.Canon(G.Resolve(spec, { w = 1777, h = 1000 })) == LY.Canon(G.Resolve(spec, { w = 1777, h = 1000 })), "and on every run")
end

---------------------------------------------------------------------------
-- 2. Refusals: a spec that can't be honoured is refused whole
---------------------------------------------------------------------------
do
  local function Refused(edit, code)
    local s = Spec()
    edit(s)
    local P = LY.Problems()
    G.Check(s, P)
    for _, p in ipairs(P) do if p.code == code then return true end end
    return false
  end
  Check(Refused(function(s) s.components.block.anchor.to = "right"; s.components.right.anchor = { point = "TOP", to = "block", rel = "TOP" } end, "anchor-cycle"), "an anchor cycle")
  Check(Refused(function(s) s.components.left.anchor.to = "nowhere" end, "bad-target"), "an unknown target")
  Check(Refused(function(s) s.components.left.anchor.point = "MIDDLE" end, "bad-value"), "a point that isn't one")
  Check(Refused(function(s) s.components.left.room.side = "left" end, "room-needs-anchor"), "room on the anchored side")
  Check(Refused(function(s) s.densities.standard = 1.1 end, "bad-value"), "standard density must be 1")
  Check(Refused(function(s) s.narrow = nil end, "narrow-without-width"), "a narrow rule without a narrow width")
  Check(Refused(function(s) s.components.under.anchor.x = nil end, "no-offset"), "a refless component needs its offsets")
  Check(Refused(function(s) s.components.left.size = { w = 1, h = 1 } end, "ref-and-size"), "ref and size together")
  Check(Refused(function(s) s.components.left.wobble = true end, "unknown-field"), "an unknown field")
  Check(Refused(function(s) s.attach = { ellesmereui = { nothing = "left" } } end, "unknown-position"), "attaching a position no adapter registers")
  Check(Refused(function(s) s.attach = { ellesmereui = { minimap = "left:MIDDLE" } } end, "bad-target"), "attaching to a point that isn't one")
  Check(Refused(function(s) s.attach = { details = {} } end, "unknown-adapter"), "attaching for an adapter that doesn't exist")
  Check(select(2, G.Resolve(Spec(), { w = 100, h = 100 })) == "screen", "a screen too small to be real is refused")
end

---------------------------------------------------------------------------
-- 3. Converting to how addons store a place
---------------------------------------------------------------------------
do
  local screen = G.Screen(2000, 1000)
  local rect = G.Rect(-700, -400, 300, 160)
  local x, y = G.Stored(rect, "BOTTOMLEFT", "BOTTOMLEFT", screen)
  Check(x == 150 and y == 20, "BOTTOMLEFT from BOTTOMLEFT: the distance of the corner from the screen's corner")
  x, y = G.Stored(rect, "CENTER", "CENTER", screen)
  Check(x == -700 and y == -400, "CENTER from CENTER: the centre offset")
  x, y = G.Stored(G.Rect(0, 352, 520, 96), "TOP", "TOP", screen)
  Check(x == 0 and y == -100, "TOP from TOP: the top edge below the top of the screen")
  x, y = G.Stored(rect, "BOTTOM", "CENTER", screen)
  Check(x == -700 and y == -480, "BOTTOM from CENTER (an action bar that grows up)")
  -- a stored place, followed: point by the screen's point, plus how far the component moved
  x, y = G.Follow({ rel = "LEFT", x = 406, y = -272 }, { dx = 2866.67 / 2 - 840, dy = 75 }, G.Screen(2866.67, 1200), G.Screen(1680, 1050))
  Check(x == 406 and y == -197, "a LEFT place keeps its distance from the left edge and moves with its component")
  x, y = G.Follow({ rel = "CENTER", x = 1000, y = 500 }, { dx = -366.67, dy = 0 }, G.Screen(2866.67, 1200), G.Screen(2133.33, 1200))
  Check(Near(x, 633.33) and y == 500, "a centre place moves by its component's move")
  Check(G.Round(1.006) == 1.01 and G.Round(-2.4949) == -2.49 and G.Round(3) == 3, "places are rounded to 1/100 of a unit")
end

---------------------------------------------------------------------------
-- 4. Classic Adventure: the package, its rules, and the screens players have
---------------------------------------------------------------------------
local PKG, VAR = LY.CLASSIC_PACKAGE, LY.CLASSIC_VARIANT
local CAP = LY.CLASSIC_CAPTURE
local ok, problems = LY.Validate(PKG)
Check(ok, "Classic Adventure is a valid package (" .. tostring(problems and problems.n) .. " problems)")
local spec = PKG.geometry
local CW, CH = spec.canvas.w, spec.canvas.h

local SCREENS = {
  { "the author's 3440x1440 at UI scale 0.64", 2866.67, 1200 },
  { "1920x1080 at UI scale 0.64", 2133.33, 1200 },
  { "1920x1200 at UI scale 0.64", 1920, 1200 },
  { "1920x1080 pixel-perfect", 1920, 1080 },
  { "2560x1440 pixel-perfect", 2560, 1440 },
  { "1680x1050 pixel-perfect (narrow)", 1680, 1050 },
  { "1600x1200 at UI scale 0.64 (narrow)", 1600, 1200 },
  { "3840x2160 at UI scale 0.40", 3413.33, 1920 },
  { "5120x1440 at UI scale 0.64 (32:9)", 4266.67, 1200 },
}
for _, s in ipairs(SCREENS) do
  for _, density in ipairs({ "standard", "larger" }) do
    local r = G.Resolve(spec, { w = s[2], h = s[3] }, { density = density })
    local said = {}
    for _, d in ipairs(r and r.diagnostics or {}) do said[#said + 1] = d.code .. " " .. d.id .. (d.other and (" " .. d.other) or "") end
    Check(r and r.fits, s[1] .. ", " .. density .. ": everything fits (" .. table.concat(said, "; ") .. ")")
    if r then
      for id, comp in pairs(r.components) do
        local cs = spec.components[id]
        local rect = comp.rect
        Check(rect.l >= -s[2] / 2 - 0.01 and rect.r <= s[2] / 2 + 0.01 and rect.b >= -s[3] / 2 - 0.01 and rect.t <= s[3] / 2 + 0.01,
          s[1] .. ": " .. id .. " is on screen")
        -- no unintended shrinking: under the reference size (times the density) only by an explicit rule, and never under
        -- the readable minimum
        if cs.ref and cs.ref.w > 0 then
          local f = cs.density and r.factor or 1
          local ruled = false
          for _, n in ipairs(comp.notes) do if n == "room" or n == "max-w" or n == "max-h" then ruled = true end end
          Check(ruled or (rect.w >= cs.ref.w * f - 0.01 and rect.h >= cs.ref.h * f - 0.01), s[1] .. ", " .. density .. ": " .. id .. " not shrunk without a rule")
        end
        if cs.min then
          Check(rect.w >= cs.min.w - 0.01 and rect.h >= cs.min.h - 0.01, s[1] .. ", " .. density .. ": " .. id .. " at least its readable minimum")
        end
      end
    end
  end
end

-- the narrow screens rearrange; the wide ones don't
do
  local wide = G.Resolve(spec, { w = 2133.33, h = 1200 })
  local narrow = G.Resolve(spec, { w = 1680, h = 1050 })
  Check(not wide.narrow and narrow.narrow, "the narrow width is 1700 units")
  local m, mm = narrow.components.meter.rect, narrow.components.minimap.rect
  Check(Near(m.r, mm.r, 1e-6) and Near(m.t, mm.b - 40, 1e-6), "narrow: the meter goes under the minimap")
  Check(narrow.components.chat.rect.r <= narrow.components.central.rect.l - 12 + 1e-6 and narrow.components.chat.rect.w < 451,
    "narrow: chat gives up width rather than run into the central block")
  local w = wide.components
  Check(Near(w.meter.rect.r, 2133.33 / 2 - 12.5, 0.01) and Near(w.chat.rect.l, -2133.33 / 2 + 49.08, 0.01), "16:9 at the same scale: chat and meter keep their edge distances")
  Check(Near(w.central.rect.x, 0, 1e-9) and Near(w.central.rect.b, -600, 1e-9), "the central block stays bottom centre")
  Check(Near(w.objectives.rect.t, w.minimap.rect.b - 56, 1e-6) and Near(w.objectives.rect.r, w.minimap.rect.r, 1e-6), "objectives hang under the minimap")
  local ultra = G.Resolve(spec, { w = 4266.67, h = 1200 })
  Check(Near(ultra.area.w, 2880, 1e-6) and Near(ultra.components.meter.rect.r, 1440 - 12.5, 0.01), "32:9: the meter is at the composition area's edge, not the glass's")
  local pp = G.Resolve(spec, { w = 2560, h = 1440 })
  Check(Near(pp.components.central.rect.b, -720, 1e-9) and Near(pp.components.notifications.rect.t, 720 - 260, 1e-6), "1440p: the block from the bottom, the cards from the top")
end

-- a smaller logical screen (UI scale 1.0 on 1080p): it doesn't fit, it says so, and nothing goes under its minimum
do
  local r = G.Resolve(spec, { w = 1365.33, h = 768 })
  Check(r and not r.fits, "1365x768 units: Classic Adventure does not fit, and says so")
  local codes = {}
  for _, d in ipairs(r.diagnostics) do codes[d.code] = (codes[d.code] or 0) + 1 end
  Check((codes.overlap or 0) > 0 and (codes.minimum or 0) > 0, "the overlaps and the minimums that won are listed")
  Check(r.components.chat.rect.w >= 280 and r.components.meter.rect.w >= 240 and r.components.minimap.rect.w >= 200, "nothing shrunk past readable to make it fit")
  Check(r.components.notifications.rect.b >= r.components.central.rect.t + 12 - 1e-6, "the cards still stay above the block")
  local bigger = G.Resolve(spec, { w = 1365.33, h = 768 }, { density = "larger" })
  Check(bigger and not bigger.fits and bigger.components.chat.rect.h > r.components.chat.rect.h, "larger text on a small screen: bigger, still reported")
end

---------------------------------------------------------------------------
-- 5. On the author's own screen, the package gives back what was captured
---------------------------------------------------------------------------
do
  local geo = G.Resolve(spec, { w = CW, h = CH })
  local data = { addons = Copy(CAP.ellesmereui.modules), unlockLayout = Copy(CAP.ellesmereui.layout) }
  local placed, notes = EA.Adapt(data, geo, spec.attach.ellesmereui)
  Check(#notes == 0, "every attached EllesmereUI position was found and placed (" .. #notes .. " notes)")
  local n = 0
  for id in pairs(spec.attach.ellesmereui) do
    local p = EA.POSITIONS[id]
    local function Read(t) for _, k in ipairs(p.path) do t = t and t[k] end return t end
    local before, after = Read(CAP.ellesmereui.modules[p.module]), Read(data.addons[p.module])
    if before then
      n = n + 1
      Check(Near(before.x, after.x, 0.006) and Near(before.y, after.y, 0.006) and before.point == after.point and before.relPoint == after.relPoint,
        "the author's screen: " .. id .. " stays where the author put it")
    end
  end
  Check(n == 37, "37 EllesmereUI positions are attached (" .. n .. ")")
  local caps, outs = CAP.ellesmereui.layout.anchors, data.unlockLayout.anchors
  for key, info in pairs(caps) do
    local o = outs[key]
    Check(Near(info.offsetX, o.offsetX, 0.01) and Near(info.offsetY, o.offsetY, 0.01), "the author's screen: link " .. key .. " offsets unchanged")
    if info.edge then Check(Near(info.edge.offset, o.edge.offset, 0.01), "the author's screen: link " .. key .. " edge pin unchanged") end
  end
  Check(data.addons.EllesmereUIChat.chat.chatSize.w == 451 and data.addons.EllesmereUIMinimap.minimap.mapSize == 200
    and data.addons.EllesmereUIDamageMeters.dm.windows[1].width == 375, "sizes as captured")
  -- TwichUI's places on the author's screen
  local composed = LY.Compose({ { name = "variant", units = (function()
    local u = {}
    for id, v in pairs(CAP.twichui.places) do u["twichui:place." .. id] = v end
    return u
  end)() } })
  local places = TA.Places(composed, geo, spec.attach.twichui)
  for id, v in pairs(CAP.twichui.places) do
    Check(Near(places[id].value.x, v.x, 0.006) and Near(places[id].value.y, v.y, 0.006), "the author's screen: TwichUI " .. id .. " where the author put it")
  end
  Check(places["training-card"].value.x == 0 and places["training-card"].value.y == -260, "the training card at the feature's own default place (0, -260 from the top)")
end

---------------------------------------------------------------------------
-- 6. EllesmereUI's link offsets for another screen: placed where EllesmereUI's own anchor pass will put them
--    (the formulas of UM.ApplyAnchorPosition, EUI_UnlockMode_Positions.lua, written out independently here)
---------------------------------------------------------------------------
do
  local function Edge(key, W, H)
    if key == "SCREEN_LEFT" then return { l = -W / 2 - 1, r = -W / 2, x = -W / 2 - 0.5, y = 0, b = -H / 2, t = H / 2 } end
    if key == "SCREEN_RIGHT" then return { l = W / 2, r = W / 2 + 1, x = W / 2 + 0.5, y = 0, b = -H / 2, t = H / 2 } end
    if key == "SCREEN_TOP" then return { b = H / 2, t = H / 2 + 1, y = H / 2 + 0.5, x = 0, l = -W / 2, r = W / 2 } end
    return { t = -H / 2, b = -H / 2 - 1, y = -H / 2 - 0.5, x = 0, l = -W / 2, r = W / 2 }
  end
  -- where EllesmereUI puts a child of size w × h from a link: its centre
  local function Place(info, w, h, W, H)
    local T = Edge(info.target, W, H)
    local cx, cy
    if info.side == "LEFT" then cx, cy = T.l + info.offsetX - w / 2, T.y + info.offsetY
    elseif info.side == "RIGHT" then cx, cy = T.r + info.offsetX + w / 2, T.y + info.offsetY
    elseif info.side == "TOP" then cx, cy = T.x + info.offsetX, T.t + info.offsetY + h / 2
    else cx, cy = T.x + info.offsetX, T.b + info.offsetY - h / 2 end
    local e = info.edge
    if e then
      local E = Edge(e.key, W, H)
      if e.key == "SCREEN_LEFT" or e.key == "SCREEN_RIGHT" then
        cx = e.side == "RIGHT" and (E.r + e.offset + w / 2) or (E.l + e.offset - w / 2)
      else
        cy = e.side == "TOP" and (E.t + e.offset + h / 2) or (E.b + e.offset - h / 2)
      end
    end
    return cx, cy
  end
  for _, s in ipairs({ { 2133.33, 1200, "standard" }, { 1680, 1050, "standard" }, { 4266.67, 1200, "larger" }, { 2560, 1440, "larger" } }) do
    local geo = G.Resolve(spec, { w = s[1], h = s[2] }, { density = s[3] })
    local data = { addons = Copy(CAP.ellesmereui.modules), unlockLayout = Copy(CAP.ellesmereui.layout) }
    EA.Adapt(data, geo, spec.attach.ellesmereui)
    local a = data.unlockLayout.anchors
    for key, comp in pairs({ EBS_Minimap = "minimap", EDM_Win1 = "meter", ECHAT_MainChat = "chat" }) do
      local r = geo.components[comp].rect
      local x, y = Place(a[key], r.w, r.h, s[1], s[2])
      Check(Near(x, r.x, 0.02) and Near(y, r.y, 0.02), ("%sx%s %s: EllesmereUI's link puts %s where the plan says"):format(s[1], s[2], s[3], comp))
    end
    -- a member of the central block linked to the bottom edge stays on it
    local before = CAP.ellesmereui.layout.anchors.Bar4
    Check(Near(a.Bar4.offsetY, before.offsetY, 0.01), ("%sx%s: action bar 4 keeps its link to the bottom edge"):format(s[1], s[2]))
    -- links to another element are left to EllesmereUI
    Check(a.Bar5.offsetY == CAP.ellesmereui.layout.anchors.Bar5.offsetY and a.Bar5.target == "Bar4", "a link to another element is left alone")
    -- the stored place of the meter is the plan's too (it is what the meter uses until its link is applied)
    local pos = data.addons.EllesmereUIDamageMeters.dm.windows[1].position
    Check(Near(pos.x, geo.components.meter.rect.x, 0.006) and Near(pos.y, geo.components.meter.rect.y, 0.006), "the meter's stored place matches")
    if s[3] == "larger" then
      Check(data.addons.EllesmereUIChat.chat.chatFontSize == 17 and data.addons.EllesmereUIDamageMeters.dm.barHeight == math.floor(22 * 1.15 + 0.5),
        "larger density: chat text 15 to 17, meter bars taller")
      Check(data.addons.EllesmereUIChat.chat.chatSize.w == math.floor(451 * 1.15 + 0.5), "and the chat box bigger")
    end
  end
  -- a point-mode link is left as it is
  Check(EA.ShiftLink({ mode = "POINT", target = "SCREEN_BOTTOM", offsetX = 1, offsetY = 2 }, { x = 5, y = 5 }, { w = 10, h = 10 }, { w = 20, h = 20 }) == nil,
    "a point-mode link is not rewritten")
end

---------------------------------------------------------------------------
-- 7. What the capture holds, and what it never holds
---------------------------------------------------------------------------
do
  Check(CAP.source.client == "retail", "the capture says it came from the Retail client")
  for m, blob in pairs(CAP.ellesmereui.modules) do
    Check(EA.MODULES[m], m .. " is a known EllesmereUI module")
    for _, k in ipairs(EA.STRIP[m] or {}) do Check(blob[k] == nil, m .. "." .. k .. " is not captured") end
  end
  Check(CAP.ellesmereui.modules.EllesmereUIGroupFinder == nil, "Group Finder (not in EllesmereUI's profile map) is not captured")
  for k in pairs(CAP.ellesmereui.root) do Check(EA.ROOT[k], "profile root key " .. k .. " is allowed") end
  Check(CAP.ellesmereui.root.customColors == nil, "custom colours are not captured")
  local fields = TA.Fields()
  local n = 0
  for gid, slots in pairs(CAP.twichui.groups) do
    for slot, keys in pairs(slots) do
      for key in pairs(keys) do
        n = n + 1
        local g = c.TwichUI.TwichConfig.Group(gid)
        local f = g and g.index[slot] and g.index[slot][key]
        Check(f and fields[table.concat(f.at, ".") .. "." .. f.key] and not f.switch, "TwichUI " .. gid .. "." .. slot .. "." .. key .. " is a managed look, not a switch")
      end
    end
  end
  Check(n == 206, "206 TwichUI looks (" .. n .. ")")
  for id in pairs(CAP.twichui.places) do Check(TA.PLACES[id], "TwichUI place " .. id .. " is registered") end
  -- the data file is plain data: no functions, no code; it reads back as what the capture tool wrote
  local f = assert(io.open(REPO .. "TwichUI_Layouts/ClassicData.lua", "rb"))
  local text = f:read("*a")
  f:close()
  Check(not text:find("function", 1, true) and not text:find("loadstring", 1, true), "the data file holds no code")
end

---------------------------------------------------------------------------
-- 8. Memory: what the Classic package keeps once the layouts addon is loaded (offline Lua 5.1, not the game's figure)
---------------------------------------------------------------------------
do
  collectgarbage("collect")
  local before = collectgarbage("count")
  local env = { TwichUI = { Layouts = {} } }
  local chunk = assert(loadfile(REPO .. "TwichUI_Layouts/ClassicData.lua"))
  setfenv(chunk, env)
  chunk()
  collectgarbage("collect")
  local kb = collectgarbage("count") - before
  print(("Classic Adventure's captured data: %.0f KB retained once loaded (offline Lua 5.1)"):format(kb))
  Check(kb < 2048, "the captured data stays under 2 MB once loaded")
end

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("LAYOUT GEOMETRY TESTS PASSED")
