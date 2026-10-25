-- TwichUI: Target dragon artwork, the EllesmereUI side
-- Finds EllesmereUI's target frame and, only when asked, keeps EllesmereUI's own target dragon invisible while
-- TwichUI's shows. Nothing in EllesmereUI is replaced, hooked or saved; this file only reads its frames.
--
-- What it relies on (read from EllesmereUIUnitFrames 9.3.5 in reference_addons and 9.6.7 as installed; EllesmereUI
-- has no public API or callback for its unit frames):
--   * The target frame is the global EllesmereUIUnitFrames_Target, a secure unit button (SecureUnitButtonTemplate)
--     made once, in EllesmereUI's own PLAYER_LOGIN handler, when its target frame source is "EllesmereUI"
--     (EUI_UnitFrames_Init.lua, Engine.SpawnUnitFrame). With Blizzard's or no target frame chosen there is none. It is
--     shown and hidden by the game (RegisterUnitWatch). We accept it only if its "unit" attribute is "target".
--   * EllesmereUI's own target dragons, both made by EllesmereUI only once turned on there, both plain frames that
--     EllesmereUI shows and hides but never changes the alpha of:
--       frame._eliteDragonHolder                   Elite/Rare Indicator in its "Pixels Dragon" style (EUI_UnitFrames_Init.lua)
--       frame.Portrait.backdrop._winglessHolder    the Portrait Dragon / Elite Enemy Dragon (UF_PortraitDragon)
--     Hiding is setting that holder's alpha to 0 while TwichUI's dragon shows, and putting back the alpha it had.
--     Its show/hide, its settings and EllesmereUI's saved data are never touched, so nothing fights its updates.
--     The small Elite/Rare badge icon and the dragon a stock frame style paints into the frame itself are left alone.
-- If a later EllesmereUI renames these, the frame is reported as missing (or the hiding finds nothing) and nothing
-- is drawn on anything else.

local R = TwichUI
local E = {}
R.TargetArtEllesmere = E

E.FRAME_NAME = "EllesmereUIUnitFrames_Target"
E.ADDON = "EllesmereUIUnitFrames"

local function Loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
    return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function IsFrame(f)
    return type(f) == "table" and type(f.GetObjectType) == "function" and type(f.CreateTexture) == "function"
        and type(f.GetHeight) == "function" and type(f.GetAttribute) == "function"
end

-- The target frame, or nil and why: "absent" (EllesmereUI's unit frames are not loaded), "noFrame" (loaded, but it
-- has made no target frame of its own: Blizzard's or none is chosen there, or it has not built its frames yet),
-- "incompatible" (something by that name that is not EllesmereUI's target button).
function E.Find()
    local f = _G[E.FRAME_NAME]
    if f == nil then
        if not Loaded(E.ADDON) then return nil, "absent" end
        return nil, "noFrame"
    end
    if not IsFrame(f) then return nil, "incompatible" end
    local ok, unit = pcall(f.GetAttribute, f, "unit")
    if not ok or unit ~= "target" then return nil, "incompatible" end
    return f
end

---------------------------------------------------------------------------
-- EllesmereUI's own target dragon
---------------------------------------------------------------------------
local held = {}   -- [holder] = the alpha it had before we hid it

local function Holders(frame, out)
    local n = 0
    local function Add(h)
        if type(h) == "table" and type(h.SetAlpha) == "function" and type(h.GetAlpha) == "function" then
            n = n + 1
            out[n] = h
        end
    end
    if frame then
        Add(rawget(frame, "_eliteDragonHolder"))
        local portrait = rawget(frame, "Portrait")
        local bd = type(portrait) == "table" and rawget(portrait, "backdrop")
        if type(bd) == "table" then Add(rawget(bd, "_winglessHolder")) end
    end
    for i = n + 1, #out do out[i] = nil end
    return n
end

local scratch = {}

-- hide: whether EllesmereUI's dragon on frame should be invisible now. Cheap enough for every target change: two
-- field reads, and an alpha set only on a change.
function E.HideNative(frame, hide)
    if hide then
        for i = 1, Holders(frame, scratch) do
            local h = scratch[i]
            if held[h] == nil then
                held[h] = h:GetAlpha()
                h:SetAlpha(0)
            end
        end
    else
        E.RestoreNative()
    end
end

-- Every EllesmereUI dragon hidden by us gets its alpha back.
function E.RestoreNative()
    for h, alpha in pairs(held) do
        held[h] = nil
        pcall(h.SetAlpha, h, alpha)
    end
end

function E.NativeHidden()
    return next(held) ~= nil
end

-- Whether EllesmereUI has a dragon of its own on frame that the option could hide (built there at some point).
function E.HasNative(frame)
    return Holders(frame, scratch) > 0
end
