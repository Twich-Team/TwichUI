-- The shared framed look (FrameLook.lua) with recording stand-in frames. Synthetic: proves what the module paints and keeps, not how the game
-- draws it.
--   * styles: the defaults never change, an override applies color by color, a bad value is ignored, instances do not share;
--   * a shell makes its textures once; Fit, Restyle and asking for a piece again make none, and the corners keep their proportions;
--   * a button's hover, pressed, disabled and hidden states repaint the bevel and the face and never stick; restyling and rebuilding
--     leave one set of hooks and textures;
--   * nothing is saved (the module reads and writes no saved variables).
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Near(a, b) return math.abs(a - b) < 1e-6 end
local function Is(c, r, g, b, a) return c and Near(c[1], r) and Near(c[2], g) and Near(c[3], b) and (a == nil or Near(c[4], a)) end

local made = { textures = 0 }
local function Rec(fr, kind)
  fr.SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end
  fr.SetVertexColor = function(s, r, g, b, a) s.vertex = { r, g, b, a } end
  fr.SetBackdropColor = function(s, r, g, b, a) s.bg = { r, g, b, a } end
  fr.SetBackdropBorderColor = function(s, r, g, b, a) s.border = { r, g, b, a } end
  fr.SetTexCoord = function(s, ...) s.tc = { ... } end
  fr.SetFrameLevel = function(s, l) s.level = l end
  fr.GetFrameLevel = function(s) return s.level or 5 end
  fr.CreateTexture = function(s)
    made.textures = made.textures + 1
    return Rec(MIFake("Texture", s), "Texture")
  end
  fr.CreateFontString = function(s) return Rec(MIFake("FontString", s), "FontString") end
  return fr
end
local function Descendants(f)
  local n = 0
  for _, ch in ipairs(f.children or {}) do n = n + 1 + Descendants(ch) end
  return n
end
local function Hooks(f)
  local n = 0
  for _, list in pairs(f.hooks) do n = n + #list end
  return n
end

local c = MIClient("Rich", {
  db = { modules = {} },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = Rec(MIFake(kind, parent), kind); if name then cl[name] = fr end return fr end
    cl.UIParent = Rec(MIFake("Frame"), "Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = {},
})
local R = c.TwichUI
local F = R.FrameLook
local function Parent(w, h)
  local p = c.CreateFrame("Frame", nil, c.UIParent)
  p:SetSize(w or 400, h or 200)
  return p
end

Check(F and F.Ready(), "the look is ready when Look.lua and the shared button are loaded")
Check(select("#", F.ContentInsets()) == 4 and F.ContentInsets() == 12, "content insets are fixed")
local rl, rt, rr, rb = F.RailInsets()
Check(Near(rl, 9) and Near(rt, 9) and Near(rr, 9) and Near(rb, 9.75), "the rails end where the approved frame's do")

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------
local base = F.Style()
base.ink[1] = 0.9
base.primary.bg[1] = 0.9
Check(Near(F.Style().ink[1], 0.106), "a style is a copy: changing one does not change the defaults")
Check(Near(F.Style().primary.bg[1], 0.255), "...nor a button set in it")
local over = F.Style({ interior = { 0.2, 0.2, 0.2 }, primary = { bg = { 0.5, 0.4, 0.3 }, bogus = { 1, 1, 1 }, border = "red" }, grainInterior = 0.5,
  nonsense = { 1, 2, 3 }, ink = { 1, 2 } })
Check(Is(over.interior, 0.2, 0.2, 0.2), "an override replaces the color")
Check(Is(over.primary.bg, 0.5, 0.4, 0.3) and Is(over.primary.border, 0.66, 0.52, 0.29), "a button set is overridden color by color")
Check(over.primary.bogus == nil and over.nonsense == nil, "an unknown name is ignored")
Check(Is(over.ink, 0.106, 0.067, 0.055) and Near(over.grainInterior, 0.5), "a value that is not a color is ignored; a number replaces a number")
Check(Is(over.danger.border, R.Look.pal.danger.border[1], R.Look.pal.danger.border[2], R.Look.pal.danger.border[3]), "danger is the shared rust unless overridden")
local srcOverride = { 0.3, 0.3, 0.3 }
local copyOf = F.Style({ interior = srcOverride })
srcOverride[1] = 0.9
Check(Near(copyOf.interior[1], 0.3), "the caller's own table is copied, not kept")

---------------------------------------------------------------------------
-- The shell
---------------------------------------------------------------------------
local p = Parent(400, 200)
local t0 = made.textures
local s = F.Shell(p)
local built = made.textures - t0
Check(built == 10, "a shell makes its interior, grain, four corners and four rails: " .. built)
Check(s.parent == p and s.level == 5, "it sits on a frame of its own at the parent's level")
local below = F.Shell(Parent(), { below = true })
Check(below.level == 4, "below puts it one level under the parent")
Check(Is(s.interior.color, 0.105, 0.088, 0.073, 1), "the interior is the neutral espresso")

local a, b2 = F.Shell(Parent(), { style = { interior = { 0.3, 0.2, 0.1 } } }), F.Shell(Parent())
Check(Is(a.interior.color, 0.3, 0.2, 0.1, 1) and Is(b2.interior.color, 0.105, 0.088, 0.073, 1), "a style given to one shell does not reach another")
a.style.interior[1] = 0.9
Check(Near(b2.style.interior[1], 0.105) and Near(F.Style().interior[1], 0.105), "nor the defaults")

-- corners keep their proportions: a fixed 24 x 24 block, and only the stub is cut on a short side
s:Fit(200)
local tl, br = s.corner.tl, s.corner.br
Check(tl.w == 24 and tl.h == 24 and br.w == 24 and br.h == 24, "a tall shell has full corners (24 units)")
Check(tl.tc[3] == 0 and tl.tc[4] == 1 and br.tc[3] == 0 and br.tc[4] == 1, "...drawn from the whole file")
Check(s.edge.left.shown and s.edge.right.shown, "...with rails between them")
s:Fit(31)
Check(tl.w == 24 and tl.h == 15 and Near(tl.tc[4], 15 / 24) and Near(br.tc[3], 1 - 15 / 24) and br.tc[4] == 1, "a short shell cuts the stub, it does not squeeze the corner")
Check(s.edge.left.shown, "a rail remains while there is room (31 units: two 15-unit stubs and one to spare)")
s:Fit(48)
Check(not s.edge.left.shown and not s.edge.right.shown and tl.h == 24, "two full corners meeting leave no side rail")
s:Fit(0)
Check(tl.h == 0, "a zero height is safe")
s:Fit(nil)
s:Fit("x")
s:Fit(100)
local points = #s.edge.left.points
s:Fit(100)
Check(#s.edge.left.points == points, "fitting to the same height again changes nothing")

-- no texture is made by anything done again
t0 = made.textures
for i = 1, 20 do s:Fit(60 + i); s:Restyle({ interior = { 0.1, 0.1, 0.1 } }); s:Sheen(); s:Recess(); s:Groove() end
local pieces = made.textures - t0
Check(pieces == 5, "pieces are made once: sheen, recess (fill and shadow) and groove (two lines): " .. pieces)
local again = made.textures
for i = 1, 20 do s:Fit(70 + i); s:Restyle(); s:Sheen(); s:Recess(); s:Groove() end
Check(made.textures == again, "asking again, fitting and restyling make no texture")
Check(s:Sheen() == s:Sheen() and s:Recess() == s:Recess() and s:Groove() == s:Groove(), "a piece asked for again is the same piece")

s:Restyle({ interior = { 0.4, 0.3, 0.2 }, ink = { 0.5, 0.5, 0.5 } })
Check(Is(s.interior.color, 0.4, 0.3, 0.2, 1), "Restyle repaints the interior")
s:Restyle()
Check(Is(s.interior.color, 0.105, 0.088, 0.073, 1), "Restyle with nothing returns to the defaults")

-- placement of the pieces
local host = Parent(300, 100)
s:Groove():Place(host, "TOP", 0, 9, 9)
local g1 = #host.points
s:Groove():Place(host, "BOTTOM", 3, 9, 9)
Check(#host.points == g1, "placing writes anchors of the piece, not new ones on the host")
local before = made.textures
s:Recess():Place(host, 9, 9, 9, 9.75)
s:Sheen():Place(host, 9, 0, 9, 0)
Check(made.textures == before, "placing a piece makes no texture")
s:Recess():SetShown(false)

-- follow: the frame fits itself whenever the shell changes size
local f1 = F.Shell(Parent(300, 300), { follow = true })
f1:Fire("OnSizeChanged", 300, 40)
Check(f1.corner.tl.h == 20, "a shell that follows refits when it is resized (half of 40)")
f1:Fire("OnSizeChanged", 300, 400)
Check(f1.corner.tl.h == 24, "...and again when it grows")

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local bp = Parent(300, 100)
local clicks = 0
t0 = made.textures
local b = F.Button(bp, "Start", 120, "primary", function() clicks = clicks + 1 end)
local per = made.textures - t0
local look = b.twichLook
local bev = look.bevel
Check(per == 10, "a button makes ten bevel textures once: " .. per)
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.32), "a primary button's lit edge is antique gold at rest")
Check(Is(bev.dark.color, 0.106, 0.067, 0.055, 0.50) and bev.sheen.shown ~= false and bev.inset.shown == false, "at rest: a shaded lower edge, the sheen, no pressed shade")
local sec = F.Button(bp, "Cancel", 80, "secondary", function() end)
Check(Is(sec.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.32), "a secondary button's lit edge is aged bronze")
local danger = F.Button(bp, "Stop", 80, "danger", function() end)
local rust = R.Look.pal.danger
Check(Is(danger.border, rust.border[1], rust.border[2], rust.border[3], 1), "a danger button's rim is the shared rust")

b:Fire("OnEnter")
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.46), "under the pointer the lit edge is brighter")
Check(Is(b.border, 0.80, 0.65, 0.38, 1), "...and the face and rim are the hot ones")
b:Fire("OnMouseDown")
Check(Is(bev.lit.color, 0.106, 0.067, 0.055, 0.55) and bev.inset.shown and not bev.sheen.shown, "pressed: the lit edge goes dark, the sheen goes, the inset comes in")
b:Fire("OnMouseUp")
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.46) and not bev.inset.shown and bev.sheen.shown, "released under the pointer: lit again, nothing left sunk")
b:Fire("OnLeave")
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.32) and Is(b.border, 0.66, 0.52, 0.29, 1), "leaving: resting again, face included")
b:Fire("OnEnter"); b:Fire("OnMouseDown")
b:SetEnabled(false)
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.07) and not bev.sheen.shown and not bev.inset.shown and Is(bev.dark.color, 0.106, 0.067, 0.055, 0.25),
  "disabled while pressed: subdued, no pressed shade, no sheen")
b:SetEnabled(true)
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.46) and not bev.inset.shown, "enabled again: not stuck pressed (the pointer is still over it)")
b:Fire("OnLeave")
b:Fire("OnEnter"); b:Fire("OnMouseDown")
b:Hide()
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.32) and not bev.inset.shown and Is(b.border, 0.66, 0.52, 0.29, 1),
  "hidden under the pointer or mid-press: it comes back resting, bevel and face")
b:Show()
b.scripts.OnClick(b)
Check(clicks == 1, "the click handler is the caller's own")

-- restyle and rebuild: no more hooks or textures
local hooks, kidsBefore = Hooks(b), Descendants(b)
for i = 1, 10 do b:Restyle({ gold = { 0.9, 0.8, 0.1 }, primary = { bg = { 0.4, 0.2, 0.1 } } }) end
Check(Hooks(b) == hooks and Descendants(b) == kidsBefore, "restyling adds no hook and no texture")
Check(Is(bev.lit.color, 0.9, 0.8, 0.1, 0.32) and Is(b.bg, 0.4, 0.2, 0.1, 1), "a changed style repaints the bevel and the face")
b:Restyle()
Check(Is(bev.lit.color, 0.84, 0.70, 0.42, 0.32), "restyling with nothing is the defaults")
Check(Is(sec.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.32) and Is(F.Style().gold, 0.84, 0.70, 0.42), "another button and the defaults are untouched")
local player = F.Button(bp, "Mine", 80, "secondary", function() end, { style = { quiet = { bg = { 0.3, 0.1, 0.1 } }, bronzeHi = { 0.2, 0.9, 0.2 } } })
Check(Is(player.bg, 0.3, 0.1, 0.1, 1) and Is(player.twichLook.bevel.lit.color, 0.2, 0.9, 0.2, 0.32), "a style given to a button (the player's own) wins over the defaults")
Check(Is(sec.bg, 0.150, 0.112, 0.086, 1), "...and reaches no other button")

---------------------------------------------------------------------------
-- The close box and the fade
---------------------------------------------------------------------------
local close = F.Close(bp, function() end)
t0 = made.textures
Check(close.twichLook and close.twichLook.bevel.lit, "the close box has the same bevel")
close:Fire("OnEnter")
Check(Is(close.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.46), "...and lifts under the pointer")
close:Fire("OnLeave")
Check(Is(close.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.32), "...and rests again")
close:Restyle({ bronzeHi = { 0.1, 0.1, 0.9 } })
Check(Is(close.twichLook.bevel.lit.color, 0.1, 0.1, 0.9, 0.32), "...and restyles")

---------------------------------------------------------------------------
-- The title strip and the two-state button
---------------------------------------------------------------------------
local hp = Parent(500, 300)
local hs = F.Shell(hp, { below = true })
local pieces0, kids0 = made.textures, #hp.children
local head = hs:Header(40)
Check(head and head.parent == hp and head.h == 40, "the title strip is a frame of the window's own, as high as it was asked")
Check(head.points and head.points[1] and head.points[1][1] == "TOPLEFT", "...anchored along the window's top")
Check(made.textures - pieces0 == 3, "...with a sheen (one texture) and a groove (two lines) and nothing else: " .. (made.textures - pieces0))
local after = made.textures
Check(hs:Header(99) == head and head.h == 40 and made.textures == after, "asking again returns the same strip, unchanged, and makes nothing")
Check(hs:Sheen() == hs:Sheen() and hs:Groove() == hs:Groove(), "the strip's sheen and groove are the shell's own pieces")
Check(#hp.children - kids0 == 1, "the strip adds one frame to the window: " .. (#hp.children - kids0))

local tp = Parent()
local tl0 = made.textures
local toggled = 0
local tg = F.Toggle(tp, "Reveal", 120, function() toggled = toggled + 1 end)
Check(tg.twichLook and tg.twichLook.bevel.lit and made.textures - tl0 >= 10, "a toggle has the same bevel (ten textures) as a button")
tg:SetOn(false)
Check(Is(tg.border, 0.40, 0.30, 0.20, 1), "off: the quiet face and rim")
tg:SetOn(true)
Check(Is(tg.border, 0.66, 0.52, 0.29, 1) and Is(tg.bg, 0.255, 0.168, 0.108, 1), "on: the primary face and the gold rim")
tg:Fire("OnEnter")
Check(Is(tg.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.46), "under the pointer the lit edge is brighter")
tg:Fire("OnLeave")
Check(Is(tg.twichLook.bevel.lit.color, 0.66, 0.50, 0.29, 0.32), "...and rests again")
tg:Fire("OnClick")
Check(toggled == 1, "the click handler is the caller's own")
local th, tk = Hooks(tg), Descendants(tg)
local tt = made.textures
tg:Restyle({ primary = { border = { 0.1, 0.9, 0.1 } } })
Check(Is(tg.border, 0.1, 0.9, 0.1, 1) and Hooks(tg) == th and Descendants(tg) == tk and made.textures == tt, "restyling repaints it and adds no hook, frame or texture")
local other = F.Toggle(tp, "Other", 120, function() end)
other:SetOn(true)
Check(Is(other.border, 0.66, 0.52, 0.29, 1) and Is(F.Style().primary.border, 0.66, 0.52, 0.29), "another toggle and the defaults are untouched")

local fp = Parent()
F.FadeIn(fp)
local fh = Hooks(fp)
F.FadeIn(fp)
Check(fh > 0 and Hooks(fp) == fh, "the fade is hooked once however often it is asked for")

---------------------------------------------------------------------------
-- The bare shell and F.Frame: the frame alone, for a window whose background is the player's
---------------------------------------------------------------------------
do
  local bp2 = Parent(300, 200)
  local before = made.textures
  local bare = F.Shell(bp2, { bare = true, follow = true })
  Check(made.textures - before == 8 and bare.interior == nil and bare.grain == nil, "a bare shell makes four corners and four rails, no interior or grain: " .. (made.textures - before))
  bare:Restyle({ interior = { 0.9, 0.1, 0.1 } })
  bare:Fit(120); bare:Sheen(); bare:Recess(); bare:Groove()
  Check(bare.corner.tl.h == 24, "it fits, restyles and takes the optional pieces like any shell")
  local style = { border = "solid" }
  local look = { Get = function(k) return k == "borderTexture" and style.border or nil end }
  local fp2 = Parent(300, 200)
  local t1 = made.textures
  Check(F.Frame(fp2, look) == 0 and fp2.twichFrame == nil and made.textures == t1, "another border: nothing is made and nothing is reserved")
  style.border = F.BORDER
  local reach2 = F.Frame(fp2, look)
  Check(reach2 == 13 and fp2.twichFrame and fp2.twichFrame.shown ~= false and made.textures - t1 == 8, "the frame border: one bare shell, and its reach")
  local shell2 = fp2.twichFrame
  style.border = "none"
  Check(F.Frame(fp2, look) == 0 and shell2.shown == false, "any other border puts it away and reserves nothing")
  style.border = F.BORDER
  local t2 = made.textures
  Check(F.Frame(fp2, look) == 13 and fp2.twichFrame == shell2 and shell2.shown ~= false and made.textures == t2, "chosen again: the same shell comes back, none is made")
  Check(F.PANEL_BG == "ff1b1613" and F.PANEL_BORDER == "ffa8804a", "the colors a panel look starts from: the espresso and the aged bronze")
end

---------------------------------------------------------------------------
-- No saved data
---------------------------------------------------------------------------
local saved = {}
for k in pairs(c.TwichUIDB) do saved[k] = true end
F.Shell(Parent()); F.Button(bp, "x", 50, "primary", function() end); F.Close(bp, function() end); F.Toggle(bp, "x", 50, function() end)
F.Shell(Parent()):Header(30)
local added = {}
for k in pairs(c.TwichUIDB) do if not saved[k] then added[#added + 1] = k end end
Check(#added == 0, "building anything writes nothing to the saved variables: " .. table.concat(added, ","))

if failures == 0 then print("PASSED test_frame_look") else print(failures .. " failures") os.exit(1) end
