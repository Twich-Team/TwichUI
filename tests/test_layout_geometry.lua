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
    local p = EA.POSITIONS[id]   -- the tooltip's fixed place is not a position in a module blob (TipPlace; test_layout_tooltip.lua)
    local function Read(t) for _, k in ipairs(p.path) do t = t and t[k] end return t end
    local before, after
    if p then before, after = Read(CAP.ellesmereui.modules[p.module]), Read(data.addons[p.module]) end
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
-- 8. Variants (Phase 5): a layout's own rules on top of the shared ones, and Compact Adventure on the screens players have
---------------------------------------------------------------------------
do
  -- the mechanism, on the synthetic layout
  local spec0 = Spec()
  spec0.variants = {
    alt = { components = { block = { managed = true, ref = { x = 0, y = -350, w = 300, h = 300 }, anchor = { point = "BOTTOM", to = "area", rel = "BOTTOM" } },
        extra = { managed = true, ref = { x = 700, y = 0, w = 100, h = 100 }, anchor = { point = "RIGHT", to = "area", rel = "RIGHT" } } },
      narrow = 1100 },
    empty = {},
  }
  local P = LY.Problems()
  Check(G.Check(spec0, P) and P.n == 0, "a spec with variants is valid")
  Check(G.Spec(spec0, nil) == spec0 and G.Spec(spec0, "nobody") == spec0, "no variant, or one that names nothing: the shared spec itself")
  local alt = G.Spec(spec0, "alt")
  Check(alt ~= spec0 and alt.variants == nil, "a variant's spec is a spec of its own, without `variants`")
  Check(alt.components.block.ref.w == 300 and alt.components.extra ~= nil and alt.components.left == spec0.components.left, "its components replace and add by id; the others are the shared tables, not copies")
  Check(spec0.components.block.ref.w == 600 and spec0.components.extra == nil and alt.narrow == 1100 and spec0.narrow == 1400, "the shared spec is not changed by it")
  Check(G.Spec(spec0, "alt") == alt, "and a second ask returns the same table")
  Check(G.Spec(spec0, "empty") == G.Spec(spec0, "empty"), "a variant with no changes works too")
  local shared = assert(G.Resolve(spec0, { w = 2000, h = 1000 }))
  local mine = assert(G.Resolve(spec0, { w = 2000, h = 1000 }, { variant = "alt" }))
  Check(shared.components.block.rect.w == 600 and shared.components.extra == nil, "resolved without a variant: the shared rules")
  Check(mine.variant == "alt" and mine.components.block.rect.w == 300 and mine.components.extra and Near(mine.components.extra.rect.r, 750, 1e-9), "resolved for the variant: its own rules")
  Check(Near(mine.components.block.rect.b, -500, 1e-9), "its block keeps its distance from the bottom, as the shared one did")
  Check(mine.narrow == false and assert(G.Resolve(spec0, { w = 1150, h = 1000 }, { variant = "alt" })).narrow == false
    and assert(G.Resolve(spec0, { w = 1050, h = 1000 }, { variant = "alt" })).narrow == true
    and assert(G.Resolve(spec0, { w = 1150, h = 1000 })).narrow == true, "the narrow width is the variant's own")
  -- every variant must be a valid spec on its own
  local function Refused(mut, code, what)
    local t = Spec()
    t.variants = { alt = { components = {} } }
    mut(t)
    local Pr = LY.Problems()
    G.Check(t, Pr)
    local found = false
    for _, pr in ipairs(Pr) do if pr.code == code then found = true end end
    Check(found, "refused: " .. what .. " (" .. code .. ")")
  end
  Refused(function(t) t.variants = 5 end, "not-table", "variants that is not a table")
  Refused(function(t) t.variants.alt = 5 end, "not-table", "a variant that is not a table")
  Refused(function(t) t.variants.alt.canvas = {} end, "unknown-field", "a variant changing the canvas")
  Refused(function(t) t.variants.alt.densities = {} end, "unknown-field", "a variant changing the densities")
  Refused(function(t) t.variants.alt.components = 5 end, "not-table", "components that are not a table")
  Refused(function(t) t.variants.alt.components = { a = { ref = { x = 0, y = 0, w = 10, h = 10 }, anchor = { point = "CENTER", to = "b", rel = "CENTER", x = 0, y = 0 } },
    b = { ref = { x = 0, y = 0, w = 10, h = 10 }, anchor = { point = "CENTER", to = "a", rel = "CENTER", x = 0, y = 0 } } } end, "anchor-cycle", "a variant whose components anchor to each other")
  Refused(function(t) t.variants.alt.components = { block = { ref = { x = 0, y = 0, w = 10, h = 10 }, anchor = { point = "CENTER", to = "nobody", rel = "CENTER", x = 0, y = 0 } } } end,
    "bad-target", "a variant component anchored to nothing")
  Refused(function(t) t.variants.alt.attach = { nobody = {} } end, "unknown-adapter", "an attachment for an adapter that doesn't exist")
  Refused(function(t) t.variants["Bad Id"] = {} end, "bad-id", "a variant with a bad id")
  Refused(function(t) for i = 1, 9 do t.variants["v" .. i] = {} end end, "too-many", "more than eight variants")
  -- the package: a variant's rules belong to a variant the package has
  local pkg = Copy(PKG)
  pkg.geometry.variants.nobody = {}
  local okp, pp = LY.Validate(pkg)
  local named = false
  for _, pr in ipairs(pp or {}) do if pr.code == "geometry-variant-unknown" then named = true end end
  Check(not okp and named, "a package whose geometry has rules for a variant it doesn't have is refused")
end

local CMP = LY.COMPACT_VARIANT
local K = LY.COMPACT_CAPTURE
do
  local ck = assert(PKG.geometry.variants[CMP])
  Check(LY.Validate(PKG) and CMP == "compact-adventure" and PKG.layers.variants[CMP], "Compact Adventure is a variant of the same package")
  Check(PKG.geometry.variants[VAR] == nil, "Classic names no rules of its own: the shared ones are Classic's")
  local names = {}
  for id in pairs(ck.components) do names[#names + 1] = id end
  table.sort(names)
  Check(table.concat(names, ",") == "central,chat,left-edge", "Compact changes only the block, chat's narrow arrangement and adds the left edge (" .. table.concat(names, ",") .. ")")
  -- the shared components are Classic's own tables, so the two cannot drift apart
  local cs, cc = G.Spec(spec, CMP), G.Spec(spec, VAR)
  local same, differ = {}, {}
  for id, comp in pairs(cc.components) do
    if cs.components[id] == comp then same[#same + 1] = id else differ[#differ + 1] = id end
  end
  table.sort(same); table.sort(differ)
  Check(table.concat(differ, ",") == "central,chat", "of Classic's components only the block and chat differ in Compact (" .. table.concat(differ, ",") .. ")")
  Check(cs.narrow == 1780 and cc.narrow == 1700, "Compact's narrow width is 1780, Classic's 1700")
  local chatC, chatK = cc.components.chat, cs.components.chat
  Check(chatK.ref == chatC.ref and chatK.anchor == chatC.anchor and chatK.room == chatC.room and chatK.min == chatC.min and chatK.max == chatC.max
    and chatC.narrow == nil and chatK.narrow ~= nil, "Compact's chat is Classic's chat (the same tables) plus a narrow arrangement")
end

-- Compact on the screens players have, both densities
for _, s in ipairs(SCREENS) do
  for _, density in ipairs({ "standard", "larger" }) do
    local r = G.Resolve(spec, { w = s[2], h = s[3] }, { density = density, variant = CMP })
    local said = {}
    for _, d in ipairs(r and r.diagnostics or {}) do said[#said + 1] = d.code .. " " .. d.id .. (d.other and (" " .. d.other) or "") end
    Check(r and r.fits, "Compact, " .. s[1] .. ", " .. density .. ": everything fits (" .. table.concat(said, "; ") .. ")")
    if r then
      for id, comp in pairs(r.components) do
        local cs = G.Spec(spec, CMP).components[id]
        local rect = comp.rect
        Check(rect.l >= -s[2] / 2 - 0.01 and rect.r <= s[2] / 2 + 0.01 and rect.b >= -s[3] / 2 - 0.01 and rect.t <= s[3] / 2 + 0.01,
          "Compact, " .. s[1] .. ": " .. id .. " is on screen")
        if cs.min then
          Check(rect.w >= cs.min.w - 0.01 and rect.h >= cs.min.h - 0.01, "Compact, " .. s[1] .. ", " .. density .. ": " .. id .. " at least its readable minimum")
        end
        if cs.ref and cs.ref.w > 0 and not cs.density then
          Check(Near(rect.w, cs.ref.w, 1e-6) and Near(rect.h, cs.ref.h, 1e-6), "Compact, " .. s[1] .. ": " .. id .. " keeps its size (it doesn't scale)")
        end
      end
    end
  end
end

do
  -- the author's own screen: Compact gives back the captured layout, and shares everything but the block with Classic
  local k = G.Resolve(spec, { w = CW, h = CH }, { variant = CMP })
  local c0 = G.Resolve(spec, { w = CW, h = CH }, { variant = VAR })
  for _, id in ipairs({ "chat", "meter", "minimap", "objectives", "notifications", "focus" }) do
    local a, b = k.components[id].rect, c0.components[id].rect
    Check(Near(a.x, b.x, 1e-9) and Near(a.y, b.y, 1e-9) and Near(a.w, b.w, 1e-9) and Near(a.h, b.h, 1e-9), "on the author's screen Compact's " .. id .. " is where Classic's is")
  end
  local ck, cc = k.components.central.rect, c0.components.central.rect
  Check(Near(ck.w, 1091, 1e-9) and Near(ck.h, 157.5, 1e-9) and Near(ck.b, -600, 1e-9) and cc.w == 890 and cc.h == 525, "the block is its own: low and wide (1091 x 157.5), not 890 x 525")
  Check(Near(k.components["left-edge"].rect.l, -CW / 2, 1e-6) and k.components["left-edge"].rect.w == 0, "the left edge is a point on the area's left")
  -- narrow screens: Compact's chat rises above the block, Classic's squeezes beside it
  local nk = G.Resolve(spec, { w = 1680, h = 1050 }, { variant = CMP })
  local nc = G.Resolve(spec, { w = 1680, h = 1050 }, { variant = VAR })
  Check(nk.narrow and nc.narrow, "1680 units is narrow in both")
  Check(nk.components.chat.rect.b >= nk.components.central.rect.t + 12 - 1e-6 and Near(nk.components.chat.rect.w, 451, 1e-6),
    "Compact, narrow: chat keeps its width and sits above the block")
  Check(nc.components.chat.rect.w < 451 and nc.components.chat.rect.r <= nc.components.central.rect.l - 12 + 1e-6, "Classic, narrow: chat still gives up width beside the block")
  local between = G.Resolve(spec, { w = 1750, h = 1050 }, { variant = CMP })
  local classicBetween = G.Resolve(spec, { w = 1750, h = 1050 }, { variant = VAR })
  Check(between.narrow and not classicBetween.narrow, "between the two widths (1750) Compact is already narrow and Classic is not")
  -- a 1365x768 logical screen is honest: it doesn't fit in Compact either, and nothing is shrunk past readable
  local small = G.Resolve(spec, { w = 1365.33, h = 768 }, { variant = CMP })
  Check(small and not small.fits and small.components.meter.rect.w >= 240, "1365x768: Compact doesn't fit either, and says so")
end

---------------------------------------------------------------------------
-- 9. Compact on the author's own screen gives back what was captured; its positions, links and pieces
---------------------------------------------------------------------------
-- the modules Compact has: the shared ones from the base, the rest its own (as the composer lays the layers)
local function CompactModules()
  local m = {}
  for name, blob in pairs(PKG.layers.base.ellesmereui.modules) do m[name] = Copy(blob) end
  for name, blob in pairs(PKG.layers.variants[CMP].ellesmereui.modules) do m[name] = Copy(blob) end
  return m
end
do
  local geo = G.Resolve(spec, { w = CW, h = CH }, { variant = CMP })
  local attach = G.Attach(spec, CMP)
  local data = { addons = CompactModules(), unlockLayout = Copy(PKG.layers.variants[CMP].ellesmereui.layout) }
  local before = Copy(data)
  local placed, notes = EA.Adapt(data, geo, attach.ellesmereui)
  Check(#notes == 0, "Compact: every attached EllesmereUI position was found and placed (" .. #notes .. " notes)")
  local n, total = 0, 0
  for id in pairs(attach.ellesmereui) do
    local p = EA.POSITIONS[id]   -- "tooltip" is the fixed tooltip place, not a position in a module blob
    if p then total = total + 1 end
    local function Read(t) for _, key in ipairs(p.path) do t = t and t[key] end return t end
    local b, a
    if p then b, a = Read(before.addons[p.module]), Read(data.addons[p.module]) end
    if b then
      n = n + 1
      Check(Near(b.x, a.x, 0.006) and Near(b.y, a.y, 0.006) and b.point == a.point and b.relPoint == a.relPoint, "Compact, the author's screen: " .. id .. " stays where the author put it")
    end
  end
  Check(n == total and total == 41, "41 EllesmereUI positions are attached in Compact, and each is stored (" .. n .. " of " .. total .. ")")
  for key, info in pairs(before.unlockLayout.anchors) do
    local o = data.unlockLayout.anchors[key]
    Check(Near(info.offsetX, o.offsetX, 0.01) and Near(info.offsetY, o.offsetY, 0.01), "Compact, the author's screen: link " .. key .. " offsets unchanged")
    if info.edge then Check(Near(info.edge.offset, o.edge.offset, 0.01), "Compact, the author's screen: link " .. key .. " edge pin unchanged") end
  end
  -- TwichUI's places are the shared ones, attached to Compact's own components
  local units = {}
  for id, v in pairs(PKG.layers.base.twichui.places) do units["twichui:place." .. id] = v end
  local places = TA.Places(LY.Compose({ { name = "base", units = units } }), geo, attach.twichui)
  for id, v in pairs(PKG.layers.base.twichui.places) do
    Check(Near(places[id].value.x, v.x, 0.006) and Near(places[id].value.y, v.y, 0.006), "Compact, the author's screen: TwichUI " .. id .. " where the author put it")
  end
  -- another screen: the bottom row keeps its distance from the bottom, the left-hand frames from the left edge, the bar on the meter with it
  local W, H = 1920, 1080
  local geo2 = G.Resolve(spec, { w = W, h = H }, { variant = CMP })
  local d2 = { addons = CompactModules(), unlockLayout = Copy(PKG.layers.variants[CMP].ellesmereui.layout) }
  EA.Adapt(d2, geo2, attach.ellesmereui)
  local ab0, ab1 = before.addons.EllesmereUIActionBars.barPositions, d2.addons.EllesmereUIActionBars.barPositions
  Check(Near(ab1.Bar4.y - ab0.Bar4.y, (CH - H) / 2, 0.01) and Near(ab1.Bar6.y - ab0.Bar6.y, (CH - H) / 2, 0.01), "1080p: the bottom row moves up with the bottom edge (60 units)")
  Check(Near(ab1.Bar4.x, ab0.Bar4.x, 0.01), "and keeps its place across")
  local rf0, rf1 = before.addons.EllesmereUIRaidFrames.unlockPos, d2.addons.EllesmereUIRaidFrames.unlockPos
  Check(Near(rf1.x - rf0.x, (CW - W) / 2, 0.01) and Near(rf1.y, rf0.y, 0.01), "1080p: the raid frames keep their distance from the left edge (and the middle of the height)")
  local bm0, bm1 = before.addons.EllesmereUIActionBars.barPositions.Bar7, ab1.Bar7
  local m0, m1 = geo.components.meter.rect, geo2.components.meter.rect
  Check(Near(bm1.x - bm0.x, m1.x - m0.x, 0.01) and Near(bm1.y - bm0.y, m1.t - m0.t, 0.01), "1080p: the bar on top of the meter moves with the meter's top edge")
  -- the screen-edge links are rewritten the way Classic's are: Bar2 sits on the bottom edge by link
  local l0, l1 = before.unlockLayout.anchors.Bar2, d2.unlockLayout.anchors.Bar2
  Check(l0.target == "SCREEN_BOTTOM" and Near(l1.offsetY, l0.offsetY, 0.01), "1080p: a bar linked to the bottom edge keeps its offset from it")
end

do
  -- the pieces inside the components: where the install puts them, and sizes read from the layout's own data
  local geo = G.Resolve(spec, { w = CW, h = CH }, { variant = CMP })
  local list, notes = LY.Elements(PKG, CMP, geo)
  local by = {}
  for _, e in ipairs(list) do by[e.id] = e end
  Check(by["uf-player"] and Near(by["uf-player"].rect.x, -392.08, 0.01) and Near(by["uf-player"].rect.y, -507.08, 0.01), "the player frame, where the author put it")
  Check(by["uf-player"] and Near(by["uf-player"].rect.w, 225, 1e-6) and Near(by["uf-player"].rect.h, 63.33 + 10, 0.01), "sized from its frame width and its health and power heights")
  Check(by["bar-7"] and Near(by["bar-7"].rect.w, 377, 0.5) and Near(by["bar-7"].rect.w / geo.components.meter.rect.w, 1, 0.01), "the bar on top of the meter is as wide as the meter (377 vs 375): the size rule matches the author's own layout")
  Check(by["bar-main"] and Near(by["bar-main"].rect.w, 469.2, 0.1) and Near(by["bar-2"].rect.w, by["bar-main"].rect.w, 0.01), "bars 1 and 2 are the same width, as the author's width link makes them")
  Check(by["bar-3"] and by["bar-3"].rect.h > by["bar-3"].rect.w * 4, "bar 3 is the narrow upright bar beside chat (5 buttons in a column)")
  Check(by["party-frames"] and Near(by["party-frames"].rect.w, 125, 1e-6), "the party frames are one block, 125 wide")
  Check(by["rb-cast"] and by["uf-target-cast"] and by["uf-focus"] and by["uf-focus-cast"], "cast bars and the focus frame are there")
  Check(by["uf-player-cast"] == nil, "the player cast bar EllesmereUI's unit frames hide (showPlayerCastbar is off) is left out")
  local noSize = false
  for _, nt in ipairs(notes) do if nt.id == "uf-player-cast" then noSize = true end end
  Check(noSize and #notes == 1, "and said (a piece with no size is a note, never a guess)")
  for _, id in ipairs({ "class-bars", "marker-bar", "nav-arrow", "food-drink", "healer-watch" }) do
    Check(by[id] and by[id].kind == "marker" and by[id].rect.w == 26 and by[id].adapter == "twichui", "TwichUI's " .. id .. " is a marker at its place")
  end
  Check(by["raid-frames"] == nil, "the raid frames (a raid-only layout) are placed by the install but not drawn")
  -- a piece's rect is the install's own position math: compare with what Adapt writes on other screens (centre of the frame)
  local function CenterOf(rec, w, h, S)
    local sx = (rec.relPoint == "LEFT" or rec.relPoint:find("LEFT")) and -S.w / 2 or ((rec.relPoint:find("RIGHT")) and S.w / 2 or 0)
    local sy = rec.relPoint:find("BOTTOM") and -S.h / 2 or (rec.relPoint:find("TOP") and S.h / 2 or 0)
    local px, py = sx + rec.x, sy + rec.y
    local cx, cy = px, py
    if rec.point:find("LEFT") then cx = px + w / 2 elseif rec.point:find("RIGHT") then cx = px - w / 2 end
    if rec.point:find("BOTTOM") then cy = py + h / 2 elseif rec.point:find("TOP") then cy = py - h / 2 end
    return cx, cy
  end
  for _, sc in ipairs({ { 2133.33, 1200 }, { 1920, 1080 }, { 1680, 1050 }, { 2560, 1440 }, { 4266.67, 1200 } }) do
    for _, density in ipairs({ "standard", "larger" }) do
      local S = { w = sc[1], h = sc[2] }
      local g = G.Resolve(spec, S, { variant = CMP, density = density })
      local els = LY.Elements(PKG, CMP, g)
      local data = { addons = CompactModules(), unlockLayout = Copy(PKG.layers.variants[CMP].ellesmereui.layout) }
      local placed = EA.Adapt(data, g, G.Attach(spec, CMP).ellesmereui)
      local checked = 0
      for _, e in ipairs(els) do
        local pl = placed[e.id]
        if e.adapter == "ellesmereui" and pl then
          local cx, cy = CenterOf(pl.rec, e.rect.w, e.rect.h, S)
          Check(Near(cx, e.rect.x, 0.02) and Near(cy, e.rect.y, 0.02), ("%dx%d %s: the preview's %s is where the install writes it"):format(sc[1], sc[2], density, e.id))
          checked = checked + 1
        end
      end
      Check(checked >= 18, ("%dx%d %s: %d EllesmereUI pieces compared with the install's own positions"):format(sc[1], sc[2], density, checked))
    end
  end
end

---------------------------------------------------------------------------
-- 10. What Compact's capture holds, and the claim that what it shares is shared
---------------------------------------------------------------------------
do
  Check(K.source.client == "retail" and K.twichui == nil, "the Compact capture says it came from Retail, and holds no TwichUI settings (it shares Classic's)")
  Check(K.sameAs and K.sameAs.of == "CLASSIC_CAPTURE", "it says what it was compared with")
  local shared = PKG.layers.base.ellesmereui.modules
  local classicOwn, compactOwn = PKG.layers.variants[VAR].ellesmereui.modules, PKG.layers.variants[CMP].ellesmereui.modules
  local ns, nc, nk = 0, 0, 0
  for name, fp in pairs(K.sameAs.modules) do
    ns = ns + 1
    Check(shared[name] and classicOwn[name] == nil and compactOwn[name] == nil, name .. ": kept once, in the base, and in neither variant")
    Check(LY.Fingerprint(CAP.ellesmereui.modules[name]) == fp and LY.Fingerprint(shared[name]) == fp, name .. ": Classic's module is the one Compact's capture was proven identical to")
  end
  for name in pairs(classicOwn) do nc = nc + 1 Check(shared[name] == nil, name .. ": Classic's own module is not also shared") end
  for name, blob in pairs(compactOwn) do
    nk = nk + 1
    Check(shared[name] == nil and CAP.ellesmereui.modules[name] and not LY.Same(CAP.ellesmereui.modules[name], blob), name .. ": Compact's own module really differs from Classic's")
  end
  Check(ns == 11 and nc == 7 and nk == 7, "11 modules shared once, 7 Classic's own, 7 Compact's own (" .. ns .. ", " .. nc .. ", " .. nk .. ")")
  Check(PKG.layers.base.ellesmereui.root == CAP.ellesmereui.root and K.ellesmereui.root == nil or next(K.ellesmereui.root) == nil, "the look (fonts, accent, palette) is one: Compact's capture holds none of its own")
  for name, blob in pairs(K.ellesmereui.modules) do
    Check(EA.MODULES[name], name .. " is a known EllesmereUI module")
    for _, key in ipairs(EA.STRIP[name] or {}) do Check(blob[key] == nil, name .. "." .. key .. " is not captured") end
  end
  for key in pairs(K.ellesmereui.layout) do Check(key == "anchors" or key:find("^widthMatch") or key:find("^heightMatch") or key == "phantomBounds", "layout table " .. key .. " is allowed") end
  Check(Near(K.ellesmereui.layout.anchors.Bar7.offsetY, 4.17, 0.01) and K.ellesmereui.layout.anchors.Bar7.target == "EDM_Win1", "Compact's bar 7 is linked to the damage meter")
  local f = assert(io.open(REPO .. "TwichUI_Layouts/CompactData.lua", "rb"))
  local text = f:read("*a")
  f:close()
  Check(not text:find("function", 1, true) and not text:find("loadstring", 1, true), "the Compact data file holds no code")
  local lf = assert(io.open(REPO .. "docs/layouts/capture-compact-adventure.md", "rb"))
  local report = lf:read("*a")
  lf:close()
  Check(report:find("Found: 0 names, 0 realms, 0 GUIDs, 0 links, 0 BattleTags", 1, true), "its report says the personal-data scan found nothing")
end

-- promoting a setting between the layers: what is in the base reaches both layouts, what is in a variant only that one
do
  local function Payload(pkg, variant, screen)
    local ok, res = LY.Resolve(pkg, variant, { screen = screen or { w = 2133.33, h = 1200 } })
    assert(ok, "resolve")
    return res.adapters.ellesmereui.units
  end
  local pkg = Copy(PKG)
  local base = pkg.layers.base.ellesmereui.modules
  base.EllesmereUIChat.chat.chatFontSize = 77   -- a shared module: both layouts
  local k, c0 = Payload(pkg, CMP), Payload(pkg, VAR)
  Check(k["ellesmereui:addons.EllesmereUIChat"].chat.chatFontSize == 77 and c0["ellesmereui:addons.EllesmereUIChat"].chat.chatFontSize == 77, "a value changed in a shared (base) module reaches both layouts")
  pkg.layers.variants[CMP].ellesmereui.modules.EllesmereUIActionBars.bars.Bar2.buttonWidth = 99   -- Compact's own
  k, c0 = Payload(pkg, CMP), Payload(pkg, VAR)
  Check(k["ellesmereui:addons.EllesmereUIActionBars"].bars.Bar2.buttonWidth == 99 and c0["ellesmereui:addons.EllesmereUIActionBars"].bars.Bar2.buttonWidth ~= 99, "a value changed in Compact's own module reaches Compact only")
  -- promoting Compact's damage meter look to the base: the variants still have their own, which win; take Classic's out and both follow
  local own = pkg.layers.variants[CMP].ellesmereui.modules.EllesmereUIDamageMeters
  base.EllesmereUIDamageMeters = Copy(own)
  base.EllesmereUIDamageMeters.dm._styleSlots.eui.bgAlpha = 0.11
  pkg.layers.variants[CMP].ellesmereui.modules.EllesmereUIDamageMeters = nil
  pkg.layers.variants[VAR].ellesmereui.modules.EllesmereUIDamageMeters = nil
  k, c0 = Payload(pkg, CMP), Payload(pkg, VAR)
  Check(k["ellesmereui:addons.EllesmereUIDamageMeters"].dm._styleSlots.eui.bgAlpha == 0.11 and c0["ellesmereui:addons.EllesmereUIDamageMeters"].dm._styleSlots.eui.bgAlpha == 0.11,
    "a module promoted from the variants to the base is the same in both")
  -- a TwichUI look in the base: both
  local groups = pkg.layers.base.twichui.groups
  Check(next(groups) ~= nil, "the base holds TwichUI looks")
  local compose = function(variant)
    local ok, res = LY.Resolve(pkg, variant, { screen = { w = 2133.33, h = 1200 } })
    assert(ok)
    return res.adapters.twichui
  end
  local tk, tc = compose(CMP), compose(VAR)
  Check(#tk.list == #tc.list and #tk.list > 200 and LY.Same(tk.units, tc.units), "TwichUI's looks and places are the same for both layouts (" .. #tk.list .. " units)")
end

---------------------------------------------------------------------------
-- 11. Memory: what the Classic package keeps once the layouts addon is loaded (offline Lua 5.1, not the game's figure)
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
  collectgarbage("collect")
  before = collectgarbage("count")
  local env2 = { TwichUI = { Layouts = {} } }
  local chunk2 = assert(loadfile(REPO .. "TwichUI_Layouts/CompactData.lua"))
  setfenv(chunk2, env2)
  chunk2()
  collectgarbage("collect")
  local kb2 = collectgarbage("count") - before
  print(("Compact Adventure's captured data: %.0f KB retained once loaded (offline Lua 5.1): only what differs from Classic's"):format(kb2))
  Check(kb2 < kb and kb + kb2 < 2048, "Compact's data is only what differs from Classic's (smaller than Classic's), and both together stay under 2 MB once loaded")
end

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("LAYOUT GEOMETRY TESTS PASSED")
