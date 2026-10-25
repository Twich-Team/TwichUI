dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Target dragon artwork (targetart/, TwichUI_Settings/pages/TargetArt.lua), with stand-in frames for EllesmereUI's target
-- frame and the game's target:
--   * which artwork each kind of enemy gets (the boss flag first, then the classification), None, and a secret or
--     missing answer;
--   * the settings: checked on the way in and out, a bad stored value read as its default and left alone, the reset;
--   * the placement: aspect ratio kept, the crook on the frame's point, scale from the frame's height, mirroring;
--   * the built textures: size, format, alpha, and the metadata matching what is drawn;
--   * EllesmereUI absent, without a target frame, made late, made again; something else by that name;
--   * target changes, classification changes, no target, rapid changes: one texture, never the last target's art;
--   * settings changes redraw only what they touch; layering; nothing of EllesmereUI's frame is changed;
--   * combat: attaching waits, everything else does not; the preview ends;
--   * EllesmereUI's own dragon hidden by alpha only while ours shows, and given back;
--   * on and off repeatedly: one holder, no growing events; the settings page, preview surface and sharing.
-- How it looks on a real frame, and whether the game's answers are as documented, is in docs/target-art.md.

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. msg, 2) end
end

---------------------------------------------------------------------------
-- Stand-in frames
---------------------------------------------------------------------------
local all = {}
local function Fake(kind, parent)
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0, level = 1,
    events = {}, unitEvents = {}, calls = {}, alpha = 1 }
  all[#all + 1] = f
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    RegisterEvent = function(s, e) s.events[e] = true end,
    RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
    UnregisterEvent = function(s, e) s.events[e] = nil end,
    UnregisterAllEvents = function(s) s.events = {} end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    SetAllPoints = function(s, other) s.points = { { "ALL", other } } end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
    SetShown = function(s, v) s.shown = v and true or false end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetParent = function(s, p) s.parent = p end, GetParent = function(s) return s.parent end,
    SetFrameLevel = function(s, v) s.level = v end, GetFrameLevel = function(s) return s.level end,
    EnableMouse = function(s, v) s.mouse = v and true or false end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
    GetObjectType = function(s) return s.kind end,
    GetAttribute = function(s, k) return s.attrs and s.attrs[k] end,
    CreateTexture = function(s, _, layer) local t = Fake("Texture", s); t.layer = layer; s.textures = (s.textures or 0) + 1; return t end,
    SetTexture = function(s, p) s.texture = p; s.textureSets = (s.textureSets or 0) + 1 end,
    SetTexCoord = function(s, l, r, t, b) s.coords = { l, r, t, b } end,
    SetDrawLayer = function(s, l) s.layer = l end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    SetText = function(s, t) s.text = t end, GetText = function(s) return s.text end,
    SetFont = function() return true end, GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
    GetStringWidth = function(s) return #(s.text or "") * 6 end, GetStringHeight = function() return 12 end,
    IsEnabled = function() return true end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

-- EllesmereUI's target button: anything that would move, resize, re-layer or reparent it is recorded as a fault.
local WRITES = { SetPoint = true, ClearAllPoints = true, SetSize = true, SetWidth = true, SetHeight = true, SetScale = true,
  SetParent = true, SetFrameLevel = true, SetFrameStrata = true, SetAttribute = true, SetScript = true, HookScript = true,
  EnableMouse = true, SetHitRectInsets = true, SetAlpha = true, SetClipsChildren = true, Show = true, Hide = true }
local touched = {}
local function TargetButton(w, h)
  local f = Fake("Button")
  f.w, f.h, f.level = w or 181, h or 52, 5
  f.attrs = { unit = "target" }
  local index = getmetatable(f).__index
  return setmetatable(f, { __index = function(_, k)
    local base = index(f, k)
    if WRITES[k] and type(base) == "function" then
      return function(...) touched[#touched + 1] = k; return base(...) end
    end
    return base
  end })
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local SECRET = {}
local game = { exists = false, class = "normal", boss = false, combat = false, euiLoaded = false }
local c, S = SettingsClient({ beforeInit = function(c)
  c.CreateFrame = function(kind, name, parent)
    local f = Fake(kind, parent)
    if name then c[name] = f end
    return f
  end
  c.UIParent = Fake("Frame")
  c.InCombatLockdown = function() return game.combat end
  c.issecretvalue = function(v) return v == SECRET end
  c.UnitExists = function(u) return u == "target" and game.exists end
  c.UnitClassification = function(u) return game.class end
  c.UnitIsBossMob = function(u) return game.boss end
  c.C_AddOns.IsAddOnLoaded = function(name) return name == "EllesmereUIUnitFrames" and game.euiLoaded end
end })
local R = c.TwichUI
local TA, E, D = R.TargetArt, R.TargetArtEllesmere, R.TargetArtDisplay

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(all) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Target(class, boss)
  if class == nil then game.exists = false else game.exists, game.class, game.boss = true, class, boss or false end
  Fire("PLAYER_TARGET_CHANGED")
end
local function Tex() return D.Texture() end
local function Showing() local t = Tex() return t and t.shown and t.texture or nil end
local function Art(id) return TA.ART[id].path end
local function Events() return D.Snapshot().events end
local function On() R:SetEnabled("targetArt", true) end
local function Off() R:SetEnabled("targetArt", false) end
local function ReadTga(path)
  local fh = assert(io.open(path, "rb"))
  local data = fh:read("*a")
  fh:close()
  return data
end

---------------------------------------------------------------------------
-- 1. Which artwork: the boss flag first, then the classification; None; unknown kinds
---------------------------------------------------------------------------
do
  Check(TA.Pick("rare", false) == "rare" and TA.Pick("elite", false) == "elite", "rare and elite defaults")
  Check(TA.Pick("rareelite", false) == "boss" and TA.Pick("worldboss", false) == "boss", "rare elite and world boss defaults")
  for _, k in ipairs({ "normal", "trivial", "minus", "something", nil }) do Check(TA.Pick(k, false) == nil, "no art for " .. tostring(k)) end
  Check(TA.Pick("normal", true) == "boss", "the boss flag wins over the classification")
  Check(TA.Pick(nil, nil) == nil, "nothing readable, nothing drawn")
  -- an elite is never taken for a boss
  Check(TA.Pick("elite", false) == "elite" and TA.Pick("elite", nil) == "elite")
  -- every kind to every artwork, and None
  for _, k in ipairs(TA.KINDS) do
    local key = TA.MapKey(k[1])
    for _, id in ipairs(TA.ART_ORDER) do
      Check(TA.Set(key, id), key .. " takes " .. id)
      local picked = k[1] == "boss" and TA.Pick("normal", true) or TA.Pick(k[1], false)
      Check(picked == id, key .. " -> " .. id)
    end
    Check(TA.Set(key, "none"))
    Check((k[1] == "boss" and TA.Pick("elite", true) or TA.Pick(k[1], false)) == nil, key .. " -> none")
  end
  -- the Boss row may defer to the classification; the others may not
  Check(TA.Set("mapBoss", "class") and TA.Set("mapElite", "elite"))
  Check(TA.Pick("elite", true) == "elite" and TA.Pick("normal", true) == nil, "Same as its classification")
  Check(not TA.Set("mapElite", "class"), "only the Boss row can say \"class\"")
  TA.ResetSettings()
  Check(TA.Get("mapBoss") == "boss" and c.TwichUIDB.ui.targetArt.mapElite == nil, "reset forgets the values")
end

---------------------------------------------------------------------------
-- 2. Settings checked on the way in and out
---------------------------------------------------------------------------
do
  Check(not TA.Set("opacity", 0) and not TA.Set("opacity", 101) and not TA.Set("opacity", 50.5), "opacity bounds and whole numbers")
  Check(not TA.Set("scale", "100") and not TA.Set("framePoint", "MIDDLE") and not TA.Set("unknown", 1), "types, enums, unknown keys")
  Check(TA.Set("x", -200) and TA.Get("x") == -200 and not TA.Set("x", -201), "negative offsets")
  Check(TA.Set("mirror", true) and TA.Set("mirror", false) and TA.Get("mirror") == false, "a saved false is a value")
  c.TwichUIDB.ui.targetArt.layer = "sideways"
  c.TwichUIDB.ui.targetArt.scale = 1e9
  Check(TA.Get("layer") == "front" and TA.Get("scale") == 100, "a bad stored value reads as its default")
  Check(c.TwichUIDB.ui.targetArt.layer == "sideways", "... and is left alone")
  local told = 0
  TA.Subscribe(function() told = told + 1 end)
  TA.Set("y", 3); TA.Set("y", 3)
  Check(told == 1, "an unchanged value tells nobody")
  c.TwichUIDB.ui.targetArt = nil
end

---------------------------------------------------------------------------
-- 3. Placement
---------------------------------------------------------------------------
do
  for _, id in ipairs(TA.ART_ORDER) do
    local art = TA.ART[id]
    local p = TA.Placement(id, 52)
    Check(math.abs(p.w / p.h - art.width / art.height) < 1e-9, id .. " keeps its aspect ratio")
    -- the tail reaches the frame's bottom: below the crook, the art is exactly the frame's height
    Check(math.abs(p.h * (1 - art.crookY) - 52) < 1e-9, id .. ": 100% is frame-relative")
    -- the crook sits on the frame's top right, then rests in by the artwork's own amount (left and down)
    Check(p.point == "TOPLEFT" and p.relPoint == "TOPRIGHT", id .. " anchors")
    Check(art.restX > 0 and art.restX < 0.2 and art.restY > 0 and art.restY < 0.2, id .. " rests a little into the frame")
    Check(math.abs(p.x + art.crookX * p.w + art.restX * p.w) < 1e-9, id .. " crook, rested in")
    Check(math.abs(p.y - art.crookY * p.h + art.restY * p.h) < 1e-9, id .. " crook, rested down")
    Check(p.l == 0 and math.abs(p.r - art.width / 256) < 1e-9 and p.t == 0 and math.abs(p.b - art.height / 256) < 1e-9, id .. " texcoords: only the used part")
  end
  TA.Set("scale", 200)
  Check(math.abs(TA.Placement("rare", 52).h - 2 * TA.BaseHeight("rare", 52)) < 1e-9, "scale is percent of the base")
  Check(TA.BaseHeight("rare", nil) == TA.BaseHeight("rare", 52) and TA.BaseHeight("rare", 0) == TA.BaseHeight("rare", 52), "unreadable height falls back")
  TA.ResetSettings()
  -- one artwork's own adjustment adds to the shared placement and leaves the others alone
  local before = TA.Placement("boss", 52, nil, {})
  local other = TA.Placement("rare", 52, nil, {})
  Check(TA.Set("bossX", -10) and TA.Set("bossY", 4) and TA.Set("bossScale", 150), "the boss dragon's own values")
  Check(not TA.Set("bossScale", 49) and not TA.Set("bossX", 101) and not TA.Set("dragonX", 1), "their limits")
  local after = TA.Placement("boss", 52, nil, {})
  Check(math.abs(after.h - 1.5 * before.h) < 1e-9, "its own size, percent of the shared one")
  Check(math.abs((after.x + TA.ART.boss.crookX * after.w + TA.ART.boss.restX * after.w) - (-10)) < 1e-9, "its own offset adds")
  Check(math.abs((after.y - TA.ART.boss.crookY * after.h + TA.ART.boss.restY * after.h) - 4) < 1e-9)
  local same = TA.Placement("rare", 52, nil, {})
  Check(same.x == other.x and same.y == other.y and same.h == other.h, "the other artworks are not moved")
  TA.Set("x", 5)
  Check(math.abs(TA.Placement("boss", 52, nil, {}).x - after.x - 5) < 1e-9, "the shared offset still moves it")
  TA.ResetSettings()
  Check(TA.Get("bossScale") == 100, "the page reset covers each artwork's values")
  TA.Set("mirror", true)
  local p = TA.Placement("elite", 52)
  Check(p.l > p.r, "mirrored texcoords")
  Check(math.abs(p.x + (1 - TA.ART.elite.crookX) * p.w - TA.ART.elite.restX * p.w) < 1e-9, "the crook mirrors, and rests in to the right")
  TA.Set("artPoint", "BOTTOMLEFT"); TA.Set("x", 7); TA.Set("y", -3)
  p = TA.Placement("elite", 52)
  Check(p.point == "BOTTOMLEFT" and p.x == 7 and p.y == -3, "an ordinary point uses the offsets as they are, no rest")
  TA.ResetSettings()
end

---------------------------------------------------------------------------
-- 4. The built textures
---------------------------------------------------------------------------
do
  Check(#TA.ART_ORDER == 6, "six artworks")
  for _, id in ipairs({ "rareWide", "bossWide", "eliteWide" }) do
    Check(TA.ART[id].width == 256 and TA.ART[id].height < 256, id .. " is wider than tall")
  end
  for _, id in ipairs(TA.ART_ORDER) do
    local art = TA.ART[id]
    local data = ReadTga(art.path:gsub("^Interface\\AddOns\\!!!TwichUI\\", ROOT):gsub("\\", "/") .. ".tga")
    local b = function(i) return data:byte(i) end
    local w, h = b(13) + b(14) * 256, b(15) + b(16) * 256
    Check(b(3) == 2 and b(17) == 32 and b(18) == 8, id .. ": uncompressed 32-bit with 8 alpha bits")
    Check(w == 256 and h == 256 and #data == 18 + 256 * 256 * 4, id .. ": 256 x 256")
    -- alpha: content inside the used width, nothing beyond it, nothing on the 1 px margin, partial alpha on the edges
    local beyond, margin, opaque, partial = 0, 0, 0, 0
    for row = 0, 255 do          -- bottom-up in the file
      local base = 19 + row * 256 * 4
      local y = 255 - row          -- from the top, as the texcoords count
      for x = 0, 255 do
        local a = data:byte(base + x * 4 + 3)
        if a > 0 then
          if x >= art.width or y >= art.height then beyond = beyond + 1 end
          if x == 0 or x == art.width - 1 or y == 0 or y == art.height - 1 then margin = margin + 1 end
          if a >= 250 then opaque = opaque + 1 else partial = partial + 1 end
        end
      end
    end
    Check(beyond == 0 and margin == 0, id .. ": nothing outside the used part or on its margin")
    Check(opaque > 5000 and partial > 100, id .. ": real alpha, solid body and soft edges")
  end
end

---------------------------------------------------------------------------
-- 5. EllesmereUI absent, then without a target frame: nothing drawn anywhere, no search loop
---------------------------------------------------------------------------
do
  Check(c.TwichUIDB.modules.targetArt == false and Events() == 0 and not D.Snapshot().built, "off by default: nothing built or listened for")
  On()
  Check(D.Status() == "absent" and not D.Snapshot().built, "EllesmereUI absent")
  Check(Events() == 3, "three events, no timers: " .. Events())
  Target("elite")
  Check(D.Status() == "absent" and not D.Snapshot().built, "a target change looks once and draws nothing")
  game.euiLoaded = true
  Fire("PLAYER_ENTERING_WORLD")
  Check(D.Status() == "noFrame", "loaded without its own target frame")
  c.EllesmereUIUnitFrames_Target = { "not a frame" }
  Fire("PLAYER_TARGET_CHANGED")
  Check(D.Status() == "incompatible" and not D.Snapshot().built, "something else by that name is not used")
  local other = Fake("Button"); other.attrs = { unit = "focus" }
  c.EllesmereUIUnitFrames_Target = other
  Fire("PLAYER_TARGET_CHANGED")
  Check(D.Status() == "incompatible" and not D.Snapshot().built, "a frame for another unit is not used")
  c.EllesmereUIUnitFrames_Target = nil
  Target(nil)
end

---------------------------------------------------------------------------
-- 6. Made late (after our login), then targets come and go
---------------------------------------------------------------------------
local target = TargetButton()
do
  c.EllesmereUIUnitFrames_Target = target
  Target("rare")
  local s = D.Snapshot()
  Check(D.Status() == "ready" and s.built and s.host == target, "found on the next target change")
  local holder = D.Holder()
  Check(holder.parent == target and holder.mouse == false, "a child of the target frame that takes no mouse")
  Check(holder.points[1][1] == "ALL" and holder.points[1][2] == target, "covering it, for its size changes")
  Check(Showing() == Art("rare"), "rare art")
  Target("elite");     Check(Showing() == Art("elite"), "elite art")
  Target("worldboss"); Check(Showing() == Art("boss"), "world boss art")
  Target("rareelite"); Check(Showing() == Art("boss"), "rare elite art")
  Target("normal", true); Check(Showing() == Art("boss"), "a boss by the game's flag")
  Target("normal");    Check(Showing() == nil, "an ordinary enemy: none, never the last target's")
  Target(nil);         Check(Showing() == nil, "no target: none")
  game.exists, game.class = true, SECRET
  Fire("PLAYER_TARGET_CHANGED")
  Check(Showing() == nil, "a secret classification: none")
  -- rapid changes: one texture throughout, texture file set only when the art changes
  local textures, sets = target.textures, Tex().textureSets
  for i = 1, 50 do Target(i % 2 == 0 and "elite" or "rare") end
  Check(target.textures == nil and holder.textures == 1, "one texture, made once")
  Check(Tex().textureSets - sets <= 50, "the file is set only on a change of art")
  Target("elite"); local n = Tex().textureSets; Target("elite")
  Check(Tex().textureSets == n, "the same art again sets nothing")
  -- a classification change on the same target
  game.class = "rare"
  Fire("UNIT_CLASSIFICATION_CHANGED", "target")
  Check(Showing() == Art("rare"), "classification change redraws")
  Check(#touched == 0, "nothing of EllesmereUI's frame was changed: " .. table.concat(touched, ", "))
end

---------------------------------------------------------------------------
-- 7. Settings changes: only what they touch; layering; size changes
---------------------------------------------------------------------------
do
  local t = Tex()
  local layouts = D.Snapshot().layouts
  TA.Set("opacity", 40)
  Check(t.alpha == 0.4 and D.Snapshot().layouts == layouts, "opacity only sets the alpha")
  TA.Set("layer", "behind")
  Check(D.Holder().level == 4 and D.Snapshot().layouts == layouts, "behind: one level under the frame")
  TA.Set("layer", "front")
  Check(D.Holder().level == 5 + 12, "front: over the frame's border")
  TA.Set("scale", 150)
  Check(D.Snapshot().layouts == layouts + 1 and math.abs(t.h - 1.5 * TA.BaseHeight("rare", 52)) < 1e-6, "scale lays out again")
  Check(t.points[1][2] == target and t.points[1][3] == "TOPRIGHT", "placed on the target frame")
  TA.Set("mapRare", "elite")
  Check(Showing() == Art("elite"), "a mapping change redraws at once")
  TA.Set("mapRare", "none")
  Check(Showing() == nil, "mapped to None")
  TA.ResetSettings()
  Check(Showing() == Art("rare") and t.alpha == 1, "reset redraws")
  -- EllesmereUI's frame resized (a settings pass, UI scale): the holder's own OnSizeChanged lays out again
  target.h = 80
  D.Holder().scripts.OnSizeChanged(D.Holder())
  Check(math.abs(t.h - TA.BaseHeight("rare", 80)) < 1e-6, "follows the frame's new height")
  target.h = 52
  D.Holder().scripts.OnSizeChanged(D.Holder())
  Check(#touched == 0, "still nothing of EllesmereUI's frame changed")
end

---------------------------------------------------------------------------
-- 8. EllesmereUI's own dragon: alpha only, only while ours shows, and given back
---------------------------------------------------------------------------
do
  local native = Fake("Frame"); native.alpha = 0.9
  local wingless = Fake("Frame")
  rawset(target, "_eliteDragonHolder", native)
  rawset(target, "Portrait", { backdrop = { _winglessHolder = wingless } })
  Target("elite")
  Check(native.alpha == 0.9 and D.Snapshot().hasNative, "the option is off by default")
  TA.Set("hideEllesmere", true)
  Check(native.alpha == 0 and wingless.alpha == 0, "hidden while ours shows")
  Check(native.shown and wingless.shown, "never hidden or shown, so its own updates are not fought")
  Target("normal")
  Check(native.alpha == 0.9 and wingless.alpha == 1, "given back when ours goes")
  Target("rare")
  Check(native.alpha == 0, "hidden again")
  Off()
  Check(native.alpha == 0.9 and Showing() == nil and Events() == 0, "off: given back, hidden, no events")
  On()
  Target("rare")
  TA.Set("hideEllesmere", false)
  Check(native.alpha == 0.9, "option off: given back")
  TA.ResetSettings()
  rawset(target, "_eliteDragonHolder", nil); rawset(target, "Portrait", nil)
end

---------------------------------------------------------------------------
-- 9. Combat, frames made again, and on/off repeatedly
---------------------------------------------------------------------------
do
  -- EllesmereUI made its frames again: the one holder moves, out of combat
  local again = TargetButton()
  c.EllesmereUIUnitFrames_Target = again
  game.combat = true
  Target("elite")
  Check(D.Status() == "combat" and D.Snapshot().host == target, "a new frame waits for combat to end")
  TA.Set("opacity", 70)
  Check(Tex().alpha == 0.7, "our own texture changes in combat")
  game.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  Check(D.Status() == "ready" and D.Snapshot().host == again and D.Holder().parent == again, "moved after combat")
  Check(Showing() == Art("elite"), "drawn after combat")
  Check(D.Snapshot().events == 3, "the combat event is dropped again")
  target = again
  TA.ResetSettings()
  -- on and off ten times: one holder, the same events
  local frames = #all
  for _ = 1, 10 do Off(); On() end
  Target("rare")
  Check(#all == frames, "no frame made by switching")
  Check(Events() == 3 and Showing() == Art("rare"), "events do not grow")
  Check(#touched == 0, "nothing of EllesmereUI's frame changed")
end

---------------------------------------------------------------------------
-- 10. The preview
---------------------------------------------------------------------------
do
  Target("normal")
  Check(D.SetPreviewArt("elite") and not D.SetPreviewArt("dragonfly"), "any of the three, nothing else")
  Check(D.PreviewStart())
  Check(Showing() == Art("elite"), "the preview art whatever the target")
  D.SetPreviewArt("rare")
  Check(Showing() == Art("rare"), "switching art")
  local saved = c.TwichUIDB.ui.targetArt
  Check(saved == nil or next(saved) == nil, "the preview saves nothing")
  D.PreviewStop()
  Check(Showing() == nil, "back to the real target")
  D.PreviewStart()
  Fire("PLAYER_REGEN_DISABLED")
  Check(not D.PreviewActive() and Showing() == nil, "combat ends it")
  game.combat = true
  Check(not D.PreviewStart(), "not started in combat")
  game.combat = false
  D.PreviewStart()
  R.SettingsLauncher.Closed()   -- what the window calls as it hides
  Check(not D.PreviewActive() and Showing() == nil, "closing the settings ends it")
  D.PreviewStart()
  Off()
  Check(not D.PreviewActive() and Showing() == nil, "switching off ends it")
  Check(select(2, D.PreviewStart()) == "off", "no preview while off")
end

---------------------------------------------------------------------------
-- 11. The settings page and sharing
---------------------------------------------------------------------------
do
  local page
  for _, p in ipairs(S.pages) do if p.key == "targetArt" then page = p end end
  Check(page and page.kind == "hosted" and page.group == "addons", "a page under Other addons, with its preview")
  local labels = {}
  for _, row in ipairs(page.rows) do if row.GetName then labels[row:GetName()] = row end end
  for _, l in ipairs({ "Show dragon artwork on the target frame", "EllesmereUI target frame", "Boss", "World boss", "Rare elite",
    "Elite", "Rare", "Opacity", "Scale", "Point on the target frame", "Point on the artwork", "Horizontal offset",
    "Vertical offset", "Mirror the artwork", "Draw it", "Hide EllesmereUI's own target dragon while this one shows" }) do
    Check(labels[l], "row: " .. l)
  end
  local v = S.variables
  Check(v.TWICHUI_targetArt and v.TWICHUI_targetArtMapRareelite and v.TWICHUI_targetArtOpacity, "the settings exist")
  v.TWICHUI_targetArtOpacity:SetValue(55)
  Check(TA.Get("opacity") == 55, "a row writes through the feature")
  local text = S.ClickReset(labels["Target dragon artwork settings"])
  Check(TA.Get("opacity") == 100 and text:find("1 of the", 1, true), "the reset asks, then resets")
  -- the fine-tune rows follow the artwork chosen in the preview
  Check(labels["This artwork's horizontal offset"] and labels["This artwork's size"] and labels["Put this artwork back"], "fine-tune rows")
  D.SetPreviewArt("elite")
  v.TWICHUI_targetArtTuneX:SetValue(12)
  Check(TA.Get("eliteX") == 12 and TA.Get("rareX") == 0, "writes the chosen artwork's value only")
  D.SetPreviewArt("rare")
  Check(v.TWICHUI_targetArtTuneX:GetValue() == 0, "reads the newly chosen artwork's")
  local note = labels["This artwork's horizontal offset"].note()
  Check(note == "Adjusting: Rare spawn.", "says which artwork: " .. tostring(note))
  D.SetPreviewArt("elite")
  labels["Put this artwork back"].click()
  Check(TA.Get("eliteX") == 0, "put back")
  D.SetPreviewArt("rare")
  -- the preview surface is built and drawn without a real frame
  local f = R.TargetArtPage.Frame()
  f.shown = true
  f.scripts.OnShow(f)
  Check(f.art and f.art.texture == Art("rare") and f.sample.w == 181 and f.sample.h == 52, "the sample frame at EllesmereUI's default size")
  f.choices[2].scripts.OnClick(f.choices[2])
  -- the status line says why nothing is drawn
  R:SetEnabled("targetArt", true)
  c.EllesmereUIUnitFrames_Target = nil
  Fire("PLAYER_TARGET_CHANGED")
  Check(D.Status() == "noFrame", "status for the page")
  Off()
  local TC = R.TwichConfig
  local g
  for _, group in ipairs(TC.Groups()) do if group.id == "targetArt" then g = group end end
  Check(g and g.complete, "a complete sharing group")
  local shared = {}
  for _, fld in ipairs(g.fields) do shared[fld.key] = true end
  for key in pairs(TA.DEFAULTS) do Check(shared[key], key .. " is shared") end
  Check(shared.targetArt, "the switch is shared")
end

print(("TARGET ART TESTS PASSED (%d checks)"):format(checks))
