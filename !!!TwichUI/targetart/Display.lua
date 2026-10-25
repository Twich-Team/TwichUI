-- TwichUI: Target dragon artwork, the controller and the texture
-- Draws the chosen dragon on EllesmereUI's target frame for the kinds of enemy the player picked. Decoration only:
-- it never targets, clicks, moves or resizes anything of EllesmereUI's, and takes no mouse.
--
-- Game APIs and events (each used by Blizzard's own Forever target frame, Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua
-- and Mainline/TargetFrame.lua, and documented in Blizzard_APIDocumentationGenerated/UnitDocumentation.lua):
--   UnitExists("target"), UnitClassification("target") ("worldboss", "rareelite", "elite", "rare", "normal", "trivial",
--   "minus"), UnitIsBossMob("target") (the Forever frame's own test for its winged boss dragon);
--   events PLAYER_TARGET_CHANGED, UNIT_CLASSIFICATION_CHANGED (unit), PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED,
--   PLAYER_REGEN_DISABLED. Answers are checked with issecretvalue before use, as EllesmereUI does; a secret or missing
--   answer means no artwork.
-- None of this has been seen in the game; docs/target-art.md lists what to check.
--
-- Lifecycle:
--   * Off (the default): no frame, no texture, no event.
--   * On: PLAYER_ENTERING_WORLD, PLAYER_TARGET_CHANGED and UNIT_CLASSIFICATION_CHANGED for the target. Each one reads
--     two values and changes the texture only when the artwork differs. No OnUpdate, no timer, no polling.
--   * The holder (one frame, one texture, made once) is a child of EllesmereUI's target frame, so it moves, scales and
--     hides with it; it is laid out again when the frame changes size (the holder's own OnSizeChanged; nothing of
--     EllesmereUI's is hooked). It is made out of combat only: in combat that waits for PLAYER_REGEN_ENABLED.
--     Everything after that is our own frame and works in combat too.
--   * EllesmereUI's frame is looked for at login, on entering the world and when the target changes, never in a loop;
--     until it exists the settings say why. A different frame by that name (EllesmereUI's frames rebuilt) is moved to.
--   * Off, or a profile that has it off, hides the texture, puts EllesmereUI's dragon back and drops every event.
--     The holder frame stays (a frame can't be destroyed), hidden, taking nothing.

local R = TwichUI
local TA = R.TargetArt
local E = R.TargetArtEllesmere
local D = {}
R.TargetArtDisplay = D

local FRONT_LEVELS = 12   -- over EllesmereUI's border (+10), under its aura and text hosts (+18 and up)

local holder, tex, host   -- our frame and texture, and the target frame they are on
local evf
local registered = {}
local status = "off"      -- "off", "waiting" (not logged in), "combat" (made after combat), "ready", or E.Find's why
local shown               -- the art id on the frame now, or nil
local placed = {}         -- what the texture was last laid out for: id, height, rev
local layoutRev = 1
local preview = { active = false, art = "boss" }
local stats = { updates = 0, layouts = 0 }
local placement = {}

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function On() return R:Enabled("targetArt") end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local SyncEvents

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if preview.active then D.PreviewStop() end   -- a sample never carries into a fight
        return
    end
    -- one global lookup: finds the frame once EllesmereUI has made it, or a new one if it made its frames again
    if event ~= "UNIT_CLASSIFICATION_CHANGED" then D.Attach() end
    D.Update()
end

function SyncEvents()
    local want = {}
    if On() then
        want.PLAYER_ENTERING_WORLD, want.PLAYER_TARGET_CHANGED, want.UNIT_CLASSIFICATION_CHANGED = true, true, true
        if status == "combat" then want.PLAYER_REGEN_ENABLED = true end
        if preview.active then want.PLAYER_REGEN_DISABLED = true end
    end
    if not evf then
        if next(want) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", OnEvent)
    end
    for event in pairs(registered) do
        if not want[event] then
            evf:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event in pairs(want) do
        if not registered[event] then
            if event == "UNIT_CLASSIFICATION_CHANGED" and evf.RegisterUnitEvent then evf:RegisterUnitEvent(event, "target")
            else evf:RegisterEvent(event) end
            registered[event] = true
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function HostHeight()
    local h = host and host:GetHeight()
    if type(h) == "number" and h >= 1 then return h end
    return nil
end

local function ApplyLevel()
    local level = host:GetFrameLevel() or 0
    if TA.Get("layer") == "behind" then holder:SetFrameLevel(math.max(0, level - 1))
    else holder:SetFrameLevel(level + FRONT_LEVELS) end
end

local function Layout(id)
    local h = HostHeight()
    if placed.id == id and placed.height == h and placed.rev == layoutRev then return end
    stats.layouts = stats.layouts + 1
    local p = TA.Placement(id, h, nil, placement)
    if placed.id ~= id then tex:SetTexture(TA.ART[id].path) end
    tex:SetTexCoord(p.l, p.r, p.t, p.b)
    tex:SetSize(p.w, p.h)
    tex:ClearAllPoints()
    tex:SetPoint(p.point, host, p.relPoint, p.x, p.y)
    tex:SetAlpha(TA.Get("opacity") / 100)
    ApplyLevel()
    placed.id, placed.height, placed.rev = id, h, layoutRev
end

-- Which artwork the frame should show now: the preview's, else the target's (nil: none).
local function Wanted()
    if preview.active then return preview.art end
    if not (UnitExists and Plain(UnitExists("target"))) then return nil end
    local classification = Plain(UnitClassification and UnitClassification("target"))
    local isBoss = Plain(UnitIsBossMob and UnitIsBossMob("target"))
    return TA.Pick(classification, isBoss)
end

function D.Update()
    if not (holder and host and status == "ready") then return end
    stats.updates = stats.updates + 1
    local id = On() and Wanted() or nil
    if id then
        Layout(id)
        tex:Show()
        holder:Show()
    else
        tex:Hide()
    end
    shown = id
    E.HideNative(host, id ~= nil and On() and TA.Get("hideEllesmere"))
end

local function OnSized()
    if shown then D.Update() end   -- Layout sees the new height
end

---------------------------------------------------------------------------
-- Attaching
---------------------------------------------------------------------------
-- Finds EllesmereUI's target frame and puts the holder on it. Safe at any time; does nothing new when attached.
function D.Attach()
    if not On() then return end
    if not (R.Life and R.Life.loggedIn) then status = "waiting"; return end
    local frame, why = E.Find()
    if not frame then
        status = why
        if holder then tex:Hide() end
        if host then E.RestoreNative() end
        shown = nil
        SyncEvents()
        return
    end
    if holder and host == frame then
        if status ~= "ready" then status = "ready"; SyncEvents() end
        return
    end
    if InCombat() then
        -- a new child of the secure target button is made (or moved) out of combat only
        status = "combat"
        SyncEvents()
        return
    end
    if host and host ~= frame then E.RestoreNative() end
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:EnableMouse(false)
        tex = holder:CreateTexture(nil, "ARTWORK")
        tex:Hide()
        holder:SetScript("OnSizeChanged", OnSized)
    else
        holder:SetParent(frame)
    end
    holder:ClearAllPoints()
    holder:SetAllPoints(frame)
    host = frame
    placed.id = nil
    status = "ready"
    SyncEvents()
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe to call at any time.
---------------------------------------------------------------------------
function D.Refresh()
    if not On() then
        preview.active = false
        if holder then tex:Hide() end
        shown = nil
        E.RestoreNative()
        status = "off"
        SyncEvents()
        return
    end
    if status == "off" then status = "waiting" end
    SyncEvents()
    D.Attach()
    D.Update()
end

---------------------------------------------------------------------------
-- Preview (settings)
---------------------------------------------------------------------------
function D.PreviewActive() return preview.active end
function D.PreviewArt() return preview.art end

-- Which artwork the preview shows (any of the three). Changes nothing saved.
function D.SetPreviewArt(id)
    if not TA.ART[id] then return false end
    preview.art = id
    if preview.active then D.Update() end
    return true
end

-- Shows the preview artwork on the target frame whatever the target is (the frame itself only shows while you have a
-- target). Only while the feature is on, and not in combat. Ends with the settings, combat or switching off.
function D.PreviewStart()
    if not On() then return false, "off" end
    if InCombat() then return false, "combat" end
    if not preview.active then
        preview.active = true
        SyncEvents()
        D.Update()
    end
    return true
end

function D.PreviewStop()
    if not preview.active then return end
    preview.active = false
    SyncEvents()
    D.Update()
end

---------------------------------------------------------------------------
-- Status, for settings and the tests: plain values
---------------------------------------------------------------------------
function D.Status() return status end

function D.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    return { enabled = On(), status = status, shown = shown, preview = preview.active, previewArt = preview.art,
        events = events, built = holder ~= nil, host = host, updates = stats.updates, layouts = stats.layouts,
        nativeHidden = E.NativeHidden(), hasNative = host ~= nil and E.HasNative(host) }
end

function D.Texture() return tex end
function D.Holder() return holder end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
TA.Subscribe(function(key)
    if not (holder and shown) then
        if key == nil then D.Refresh() end
        return
    end
    if key == "opacity" then
        tex:SetAlpha(TA.Get("opacity") / 100)
    elseif key == "layer" then
        ApplyLevel()
    elseif key == "hideEllesmere" or (key and key:find("^map")) then
        D.Update()
    else
        layoutRev = layoutRev + 1
        D.Update()
    end
end)

R:OnInit(function() if On() then D.Refresh() end end)
R:On("PLAYER_LOGIN", function() if On() then D.Refresh() end end)
R.Profiles.OnApply("layout", "targetArt", function() D.Refresh() end)
R.OnSettingsClosed(function() D.PreviewStop() end)
