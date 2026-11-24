-- A stand-in for the parts of EllesmereUI (9.9.1) that Fishing Mode's fading meets, built from reading its source (not run):
--   * action bars EABBar_<key> parented to UIParent, whose alpha EllesmereUI writes itself from its own record (_fadeAlpha)
--     through a fader that animates on an OnUpdate (FadeTo), at state edges only: mouse-over enter and leave, a visibility
--     pass (a target change, combat), Advanced Fade conditions. A mouse-over bar rests at 0 and fades in under the pointer.
--   * the paging frame EABPagingFrame, and the data bar holder EllesmereEAB_XPBar
--   * unit frames under one parent, EllesmereUIUnitFrames_Hider (never written), the player inside a wrapper EllesmereUI
--     writes; the target frame written directly by its visibility pass; a 3D portrait model under the player frame whose
--     alpha EllesmereUI mirrors itself (models don't inherit a parent's alpha)
--   * the game's Minimap taken out of MinimapCluster, which EllesmereUI sets to alpha 0; EllesmereUIMicroMenu
-- It proves the integration's bookkeeping against that behaviour, never compatibility with the real EllesmereUI.
--
--   EUI = EllesmereStandIn(c, W, opts)    opts.absent: nothing of EllesmereUI exists; opts.noUnitFrames
--   EUI.bars[key], EUI.Hover(key, on), EUI.VisibilityPass(), EUI.TargetChanged(), EUI.Rebuild(key), EUI.Late(key)

function EllesmereStandIn(c, W, opts)
  opts = opts or {}
  local UI = W.UI
  local EUI = { bars = {}, record = {}, writes = 0 }
  if opts.absent then return EUI end
  c.EllesmereUI = { IS_FOREVER = true }
  c.EUI_CLIENT_FOREVER = true
  local loaded = c.C_AddOns.IsAddOnLoaded
  local MODULES = { EllesmereUI = true, EllesmereUIActionBars = true, EllesmereUIUnitFrames = not opts.noUnitFrames,
    EllesmereUIMinimap = true }
  c.C_AddOns.IsAddOnLoaded = function(n) if MODULES[n] ~= nil then return MODULES[n] end return loaded(n) end
  c.C_AddOns.GetAddOnMetadata = function(n, field) if MODULES[n] and field == "Version" then return "9.9.1" end end
  EUI.modules = MODULES

  -- the fader: one OnUpdate queue, alpha from its own record
  local queue = {}
  local fader = UI.Create("Frame", nil, c.UIParent)
  local function Paint(frame, a) EUI.writes = EUI.writes + 1; frame:SetAlpha(a); EUI.record[frame] = a end
  fader:SetScript("OnUpdate", function(_, dt)
    for frame, q in pairs(queue) do
      q.t = q.t + dt
      local p = math.min(1, q.t / q.d)
      Paint(frame, q.from + (q.to - q.from) * p)
      if p >= 1 then queue[frame] = nil end
    end
  end)
  function EUI.FadeTo(frame, to, d)
    local cur = EUI.record[frame] or 1
    if math.abs(cur - to) < 0.01 then Paint(frame, to) return end
    queue[frame] = { from = cur, to = to, d = d or 0.15, t = 0 }
  end

  local function Bar(key, mouseover)
    local f = UI.Create("Frame", "EABBar_" .. key, c.UIParent)
    f:SetSize(300, 40); f:SetPoint("BOTTOM", c.UIParent, "BOTTOM", 0, 20)
    f.mouseover = mouseover
    EUI.bars[key] = f
    Paint(f, mouseover and 0 or 1)
    return f
  end
  Bar("MainBar"); Bar("Bar2"); Bar("Bar3", true); Bar("StanceBar")
  function EUI.Hover(key, on)
    local f = EUI.bars[key]
    W.UI.mouse[f] = on or nil
    if f.mouseover then EUI.FadeTo(f, on and 1 or 0, 0.15) end
  end
  -- a visibility pass: every always-visible bar written at its resting alpha, the target frame too (no comparison first)
  function EUI.VisibilityPass()
    for _, f in pairs(EUI.bars) do if not f.mouseover then Paint(f, 1) end end
    if EUI.target then EUI.target:SetAlpha(1) end
    if EUI.wrap then EUI.wrap:SetAlpha(1) end
    if EUI.model then EUI.model:SetAlpha(1) end
  end
  function EUI.TargetChanged() EUI.VisibilityPass() end
  function EUI.Rebuild(key)
    local old = EUI.bars[key]
    local f = Bar(key, old.mouseover)
    return old, f
  end
  function EUI.Late(key) return Bar(key) end

  local paging = UI.Create("Frame", "EABPagingFrame", c.UIParent); paging:SetSize(20, 40)
  local xp = UI.Create("Frame", "EllesmereEAB_XPBar", c.UIParent); xp:SetSize(400, 8)
  EUI.paging, EUI.xp = paging, xp

  if not opts.noUnitFrames then
    local hider = UI.Create("Frame", "EllesmereUIUnitFrames_Hider", c.UIParent)
    hider:SetAllPoints(c.UIParent)
    local wrap = UI.Create("Frame", nil, hider)
    local player = UI.Create("Button", "EllesmereUIUnitFrames_Player", wrap)
    player:SetSize(200, 50)
    local target = UI.Create("Button", "EllesmereUIUnitFrames_Target", hider)
    target:SetSize(200, 50); target:Hide()
    local model = UI.Create("PlayerModel", nil, player)
    EUI.hider, EUI.wrap, EUI.player, EUI.target, EUI.model = hider, wrap, player, target, model
  end

  -- the minimap: out of the cluster, the cluster at alpha 0
  local cluster = UI.Create("Frame", "MinimapCluster", c.UIParent); cluster:SetAlpha(0)
  local map = UI.Create("Frame", "Minimap", c.UIParent); map:SetSize(140, 140)
  EUI.cluster, EUI.map = cluster, map
  local menu = UI.Create("Frame", "EllesmereUIMicroMenu", c.UIParent)
  EUI.menu = menu
  return EUI
end
