-- TwichUI Fishing: the Fishing Mode camera (Stage 2)
-- A cinematic view while fishing, put back as it was afterwards. Inspired by the way Dialogue UI frames a conversation;
-- nothing of that addon is used or needed.
--
-- What it changes, and only when Fishing Mode (Present.lua) asks:
--   zoom    the camera's distance, moved once to config camera.zoom (yards) with the game's own CameraZoomIn/CameraZoomOut,
--           so the move is as smooth as the player's own zooming (the client animates it at its zoom speed). Read with
--           GetCameraZoom.
--   offset  the over-the-shoulder offset (CVar test_cameraOverShoulder), only when config camera.offset is not 0 (it is 0,
--           off, by default) and only when the client has that setting. The client may ask the player to confirm an
--           experimental camera setting the first time; TwichUI never suppresses or answers that question.
-- Nothing else: no pitch, no view slots (SaveView/SetView would overwrite one of the player's own saved views), no
-- per-frame camera control. The camera is moved once on the way in and once on the way out; in between, the player's
-- own zooming and turning are left alone, never corrected.
--
-- Putting it back. Before changing anything the values are recorded in TwichUIFishingDB.client.camera (Store.lua), so a
-- reload, a disconnect, a logout or an error in between still lets the next start-up put them back. A value is put back
-- only if it is still what Fishing Mode set (within Cam.TOLERANCE yards for the zoom): when the player zoomed, or another
-- addon changed the setting, theirs is kept. `/tui fish recover` puts both back regardless (the player asked).
--
-- Unverified on Forever (docs/fishing-feasibility.md, "Stage 2"): that GetCameraZoom, CameraZoomIn and CameraZoomOut exist
-- and are free to call from addon code (also in combat), that they animate, and that test_cameraOverShoulder exists. Each is
-- looked up when used; a missing one turns that part off, and a zoom that does not move is noted ("camera-no-effect") and
-- not tried again this session.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Cam = {}
F.Camera = Cam

Cam.TOLERANCE = 0.75      -- yards: a zoom within this of what Fishing Mode set is still Fishing Mode's
Cam.SETTLE = 1.5          -- seconds the client is given to finish a zoom before it is read back
Cam.OFFSET_CVAR = "test_cameraOverShoulder"

local runtime = nil       -- the record while the saved data is held (nothing may be written then)
local noEffect = false    -- a zoom was seen to do nothing this session
local deferred = false    -- the offset waits for combat to end

local function Fn(name)
    local f = rawget(_G, name)
    return type(f) == "function" and f or nil
end

function Cam.Zoom()
    local get = Fn("GetCameraZoom")
    if not get then return nil end
    local ok, z = pcall(get)
    return ok and F.Num(z) or nil
end

local function CVar(name)
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, v = pcall(C_CVar.GetCVar, name)
    v = ok and F.Readable(v) or nil
    return v ~= nil and tostring(v) or nil
end

local function SetCVar(name, value)
    if not (C_CVar and C_CVar.SetCVar) then return false end
    local ok, res = pcall(C_CVar.SetCVar, name, value)
    return ok and res ~= false
end

-- What this client allows: { zoom = bool, offset = bool }.
function Cam.Supported()
    return {
        zoom = Fn("GetCameraZoom") ~= nil and Fn("CameraZoomIn") ~= nil and Fn("CameraZoomOut") ~= nil and Cam.Zoom() ~= nil and not noEffect,
        offset = CVar(Cam.OFFSET_CVAR) ~= nil,
    }
end

function Cam.Record()
    return S.ClientRecord("camera") or runtime
end

local function Save(rec)
    if S.held then runtime = rec return end
    runtime = nil
    S.SetClientRecord("camera", rec)
end

-- Moves the zoom by (target - current): out for a positive difference. Returns true when asked.
local function MoveZoom(from, to)
    local d = to - from
    if math.abs(d) < 0.05 then return false end
    local fn = d > 0 and Fn("CameraZoomOut") or Fn("CameraZoomIn")
    if not fn then return false end
    local ok, err = pcall(fn, math.abs(d))
    if not ok then F.Note("camera-error", tostring(err)) end
    return ok
end

-- Fishing Mode's view. opts: { zoom = yards or nil, offset = number (0 for none) }. Returns "applied", "nothing", "active",
-- "combat" or "unsupported".
function Cam.Apply(opts)
    if Cam.Record() then return "active" end
    if F.InCombat() then return "combat" end
    local sup = Cam.Supported()
    local rec = { at = F.Now() }
    local target = F.Num(opts.zoom)
    if target and sup.zoom then
        local cur = Cam.Zoom()
        if cur and math.abs(cur - target) > 0.25 then
            rec.zoom = { before = cur, set = target }
        end
    end
    local offset = F.Num(opts.offset) or 0
    if offset ~= 0 and sup.offset then
        local before = CVar(Cam.OFFSET_CVAR)
        local want = ("%.2f"):format(offset)
        if before and tonumber(before) ~= tonumber(want) then rec.offset = { before = before, set = want } end
    end
    if not rec.zoom and not rec.offset then
        return (sup.zoom or sup.offset) and "nothing" or "unsupported"
    end
    -- recorded first: whatever happens next, the values to put back are saved
    Save(rec)
    if rec.offset and not SetCVar(Cam.OFFSET_CVAR, rec.offset.set) then
        rec.offset = nil
        F.Note("camera-offset-refused")
    end
    if rec.zoom then
        MoveZoom(rec.zoom.before, rec.zoom.set)
        Cam.Settle(rec)
    end
    Save(rec)
    return "applied"
end

-- Once the zoom has had time to finish: the distance the client actually reached is the one Fishing Mode set (the client
-- caps the distance; a far target ends at the cap). A zoom that did not move at all is given up for the session.
function Cam.Settle(rec)
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(Cam.SETTLE, function()
        if Cam.Record() ~= rec or not rec.zoom then return end
        local now = Cam.Zoom()
        if not now then return end
        if math.abs(now - rec.zoom.before) < 0.05 and math.abs(rec.zoom.set - rec.zoom.before) > 0.5 then
            noEffect = true
            F.Note("camera-no-effect")
            rec.zoom = nil
        else
            rec.zoom.set = now
        end
        if not rec.zoom and not rec.offset then Save(nil) else Save(rec) end
    end)
end

local OnRegen
local function WaitForCombat()
    if deferred then return end
    deferred = true
    R:On("PLAYER_REGEN_ENABLED", OnRegen)
end
function OnRegen()
    deferred = false
    R:Off("PLAYER_REGEN_ENABLED", OnRegen)
    Cam.Restore("combat-ended")
end

-- Puts the view back. opts.force: put back what was recorded even if the player changed it since (the player's own
-- /tui fish recover). opts.keepZoom: ask for the zoom but keep its record (logging out: the move may not finish before
-- the game closes, so the next start-up checks again). Returns { zoom = "restored"|"kept"|nil, offset = ... }.
function Cam.Restore(reason, opts)
    opts = opts or {}
    local rec = Cam.Record()
    local out = {}
    if not rec then return out end
    if rec.zoom then
        local cur = Cam.Zoom()
        if cur and (opts.force or math.abs(cur - rec.zoom.set) <= Cam.TOLERANCE) then
            MoveZoom(cur, rec.zoom.before)
            out.zoom = "restored"
        elseif cur then
            out.zoom = "kept"
        end
        if not opts.keepZoom and cur then rec.zoom = nil end
    end
    if rec.offset then
        if F.InCombat() then
            WaitForCombat()
            out.offset = "waiting"
        else
            local cur = CVar(Cam.OFFSET_CVAR)
            if cur and (opts.force or tonumber(cur) == tonumber(rec.offset.set)) then
                SetCVar(Cam.OFFSET_CVAR, rec.offset.before)
                out.offset = "restored"
            elseif cur then
                out.offset = "kept"
            end
            rec.offset = nil
        end
    end
    if not rec.zoom and not rec.offset then Save(nil) else Save(rec) end
    if out.zoom == "kept" or out.offset == "kept" then F.Note("camera-kept", reason) end
    return out
end

-- Start-up: a record left by a reload, a disconnect or an error is put back (Fishing Mode is never on at start-up).
function Cam.Recover()
    if not Cam.Record() then return nil end
    return Cam.Restore("recovery")
end

function Cam.Status()
    local rec = Cam.Record()
    local sup = Cam.Supported()
    return { supported = sup, active = rec ~= nil, zoom = rec and rec.zoom and F.Copy(rec.zoom) or nil,
        offset = rec and rec.offset and F.Copy(rec.offset) or nil, current = Cam.Zoom(), noEffect = noEffect, waiting = deferred }
end

-- Test support.
function Cam.Reset() runtime, noEffect, deferred = nil, false, false end
