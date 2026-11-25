-- TwichUI Fishing: Fishing Mode (Stage 2)
-- How fishing looks while the player fishes with TwichUI. Three presentations (config present.mode):
--
--   immersive   the signature one: the cinematic camera (Camera.lua), the interface faded around the player (Fade.lua),
--               the cast bar (CastBar.lua), the catch list on the right (CatchList.lua), catch notifications (Toast.lua) and
--               the TwichUI Fishing emblem at the top left (P.Brand)
--   compact     the cast bar with its session figures, and catch notifications: no camera, nothing faded
--   classic     Stage 1's fishing key and records with nothing more on screen
-- Each part also has its own switch (camera.enabled, fade.enabled, list.enabled, toast.enabled), which only ever takes a
-- part away from the presentation chosen.
--
-- On and off. Fishing Mode comes on by itself when a fishing line goes out (config present.auto), or when the player asks
-- (the "Fishing Mode" key, or /tui fish mode). It goes off when the session ends, when the player asks (the same key or
-- command; it then stays off for the rest of that session unless asked again), when combat starts, on death, on a loading
-- screen and on logout. Off, everything is put back: the camera and the interface as they were (each only where it is still
-- as Fishing Mode left it), the Quiet screen hold let go, the pieces hidden. While on, the "Reveal the interface" key (held)
-- or /tui fish reveal brings the faded interface back for a moment.
--
-- Safety. Nothing here acts in the game: casting, reeling and every other action stay Stage 1's secure key presses
-- (Action.lua); Fishing Mode never sets a secure attribute, an override or a binding, and never presses anything. Each step
-- of coming on runs protected (pcall); one that fails puts everything back at once and is noted ("present-error"). The camera
-- values are recorded before they change, so a reload or disconnect puts them back at the next start-up; /tui fish recover
-- puts the camera and the interface back regardless, for when something else interfered.
--
-- For later stages:
--   P.State()                   { on, mode, parts = { camera, fade, castbar, list, toast }, revealed, suppressed, reason }
--   P.Enter(reason) / P.Leave(reason, instant) / P.Toggle() / P.Reveal(on) / P.Recover()
--   P.Configure(path, value)    Store.Set, then applied at once (positions, scales, parts, mode)
--   P.SetValueProvider(fn)      Stage 3: fn(kind, ...) -> for kind "session": { text, items = { [itemID] = text }, contents?, provisional?, perHourText? };
--                               for kind "item", itemID, q: text. Asked only when the pieces redraw on an event, never per
--                               frame. With none, no value is shown anywhere.
--   P.Subscribe(fn)             fn(state) after Fishing Mode came on or went off

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Cam = F.Camera
local Fa = F.Fade
local CB = F.CastBar
local L = F.CatchList
local T = F.Toast
local H = F.Hud
local P = {}
F.Present = P

-- What the settings page (TwichUI_Settings/pages/Fishing.lua) may rely on: raise it when the page needs something new
-- from TwichUI Fishing. The two are separate folders, so an install can have one newer than the other; the page checks
-- this before using anything and asks for an update instead of failing.
P.SETTINGS_API = 2
P.MODE_BINDING = "TWICHUI_FISHING_MODE"
P.REVEAL_BINDING = "TWICHUI_FISHING_REVEAL"
P.MODES = { immersive = true, compact = true, classic = true }
P.PRESETS = {
    immersive = { camera = true, fade = true, castbar = true, list = true, toast = true, brand = true },
    compact = { castbar = true, toast = true },
    classic = {},
}

local on, revealed, suppressed, reason = false, false, false, nil
local previewing, previewTimer, previewOpts = false, nil, nil
local parts = {}
local listeners = {}
local provider = nil
local unlocked = false
P.entered, P.left, P.errors = 0, 0, 0

---------------------------------------------------------------------------
-- What the chosen presentation shows
---------------------------------------------------------------------------
function P.Mode()
    local m = S.Get("present.mode")
    return P.MODES[m] and m or "immersive"
end

-- The parts wanted now: the preset, less any part the player switched off.
function P.Parts(mode)
    local preset = P.PRESETS[mode or P.Mode()] or {}
    local out = {}
    out.camera = preset.camera and S.Get("camera.enabled") ~= false or false
    out.fade = preset.fade and S.Get("fade.enabled") ~= false or false
    out.castbar = preset.castbar and S.Get("castbar.enabled") ~= false or false
    out.list = preset.list and S.Get("list.enabled") ~= false or false
    out.toast = preset.toast and S.Get("toast.enabled") ~= false or false
    out.brand = preset.brand and S.Get("present.brand") ~= false or false
    return out
end

function P.On() return on end

function P.State()
    return { on = on, mode = P.Mode(), parts = F.Copy(parts), revealed = revealed, suppressed = suppressed, reason = reason,
        unlocked = unlocked, previewing = previewing }
end

function P.Subscribe(fn)
    if type(fn) ~= "function" then return end
    for _, f in ipairs(listeners) do if f == fn then return end end
    listeners[#listeners + 1] = fn
end

local function Tell()
    local st = P.State()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, st)
        if not ok then R.Fault("fishing mode listener", err) end
    end
    F.Emit("PRESENT", on, P.Mode())
end

---------------------------------------------------------------------------
-- Coming on and going off
---------------------------------------------------------------------------
local Leave

local function Step(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        P.errors = P.errors + 1
        F.Note("present-error", name .. ": " .. tostring(err))
        R.Fault("fishing mode " .. name, err)
    end
    return ok
end

-- Returns true when Fishing Mode is on afterwards, or false and why: "off", "classic", "combat", "dead".
function P.Enter(why)
    if on then return true end
    if not (F.ready and S.Get("enabled")) then return false, "off" end
    if F.InCombat() then return false, "combat" end
    if UnitIsDeadOrGhost and F.Readable(UnitIsDeadOrGhost("player")) == true then return false, "dead" end
    local mode = P.Mode()
    if mode == "classic" then if previewing then P.EndPreview("classic") end return false, "classic" end
    -- a preview in progress hands its faded interface and camera over (one owner, one record: nothing is put back and
    -- taken again mid-move); only its sample pieces go
    if previewing then P.EndPreview("live", true) end
    parts = P.Parts(mode)
    on, revealed, reason = true, false, why
    if why == "player" then suppressed = false end
    P.entered = P.entered + 1
    local fine = true
    if parts.castbar then fine = Step("castbar", CB.Show) and fine end
    if parts.list then fine = Step("list", L.Show) and fine end
    if parts.brand then fine = Step("brand", function() P.Brand(true) end) and fine end
    if parts.fade then fine = Step("fade", function() Fa.Apply() end) and fine end
    if parts.camera then
        fine = Step("camera", function()
            local res = Cam.Apply({ zoom = S.Get("camera.zoom"), offset = S.Get("camera.offset") })
            if res == "unsupported" then F.Note("camera-unsupported") end
        end) and fine
    end
    if not fine then
        Leave("error", true)
        return false, "error"
    end
    Tell()
    return true
end

-- instant: no fades (combat, logout, an error). Returns true when it was on.
function Leave(why, instant)
    if not on then return false end
    on, revealed = false, false
    reason = why
    P.left = P.left + 1
    -- each step on its own: one failing never keeps the others from putting things back
    Step("camera back", function() Cam.Restore(why, { keepZoom = why == "logout" }) end)
    Step("fade back", function() Fa.Restore(instant) end)
    Step("castbar off", CB.Hide)
    Step("list off", L.Hide)
    Step("toasts off", T.Clear)
    Step("brand off", function() P.Brand(false) end)
    Tell()
    return true
end
P.Leave = Leave

-- The player's own on/off. Off stays off for the rest of the session (the next line doesn't bring it back).
function P.Toggle()
    if previewing then P.EndPreview("player") return false end
    if on then
        Leave("player")
        suppressed = true
        return false
    end
    suppressed = false
    local ok, why = P.Enter("player")
    return ok, why
end

function P.Reveal(show)
    if not (on or previewing) then return false end
    show = show and true or false
    if show == revealed then return true end
    revealed = show
    Fa.Reveal(show)
    Tell()
    return true
end

-- Everything put back regardless of who changed what since (the player's own recovery), and Fishing Mode off.
function P.Recover()
    local was = on
    if previewing then P.EndPreview("recover", true) end
    -- forced first: going off on its own would keep what someone else changed
    local cam = Cam.Restore("recover", { force = true })
    Fa.Restore(true, true)
    Leave("recover", true)
    suppressed = true
    if R.QuietScreen and R.QuietScreen.Hold then R.QuietScreen.Hold(Fa.QUIET_OWNER, false) end
    if unlocked then P.Unlock(false) end
    return { was = was, camera = cam }
end

---------------------------------------------------------------------------
-- The "TwichUI Fishing" emblem, top left in immersive Fishing Mode, as in the approved mockup (present.brand)
---------------------------------------------------------------------------
local brand
-- Where the emblem sits: below the top status strip (the data bar and the minimap's header live in the first ~40 units of the
-- screen) with room to breathe, a little in from the left edge. Scaled from the art's size; one place to change it.
P.BRAND = { x = 26, y = -60, scale = 0.36 }
function P.Brand(show)
    if show and not brand then
        local a = H.ART.logo
        local f = CreateFrame("Frame", "TwichUIFishingBrand", UIParent)
        f:SetSize(a.cw * P.BRAND.scale, a.ch * P.BRAND.scale)
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", P.BRAND.x, P.BRAND.y)
        f:SetFrameStrata("LOW")
        f:EnableMouse(false)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        if not H.Texture(tex, "logo") then tex:Hide() end
        brand = f
    end
    if brand then brand:SetShown(show and true or false) end
end
function P.BrandShown() return brand ~= nil and brand:IsShown() end

---------------------------------------------------------------------------
-- Values (Stage 3 connects a valuation; nothing is priced here)
---------------------------------------------------------------------------
function P.SetValueProvider(fn)
    if fn ~= nil and type(fn) ~= "function" then return false end
    provider = fn
    if L.Shown() then L.Refresh() end
    if CB.Shown() then CB.RefreshLines() end
    return true
end

-- The session's value is asked once per change of the records (Hud.serial) and kept until the next: the pieces' timers and
-- animations read the kept answer and never ask the valuation themselves.
local cache = { serial = -1 }
function P.Value(kind, ...)
    if not provider then return nil end
    if kind == "session" and cache.serial == H.serial and cache.provider == provider then return cache.value end
    local ok, res = pcall(provider, kind, ...)
    if not ok then F.Note("value-error", tostring(res)) end
    local value = ok and type(res) == "table" and res or nil
    if kind == "session" then cache.serial, cache.provider, cache.value = H.serial, provider, value end
    return value
end

function P.ValueItem(itemID, q)
    if not provider then return nil end
    local ok, res = pcall(provider, "item", itemID, q)
    if ok and type(res) == "string" then return res end
    return nil
end

---------------------------------------------------------------------------
-- Preview (the settings page's "Preview Fishing Mode", /tui fish preview): the chosen presentation with sample figures,
-- the interface faded and the camera moved, for P.PREVIEW seconds or until asked to stop. Never casts, equips, uses or
-- opens anything, and records nothing. Real Fishing Mode and a preview are never on together: a real line during a
-- preview takes over its faded interface and camera (P.Enter), and everything that turns Fishing Mode off ends a preview.
---------------------------------------------------------------------------
P.PREVIEW = 15

-- Returns true, or false and why: "live" (Fishing Mode is on: it is the real thing), "combat", "classic", "off".
function P.Preview(opts)
    opts = opts or {}
    if previewing then return true end
    if on then return false, "live" end
    if not (F.ready and S.Get("enabled")) then return false, "off" end
    if F.InCombat() then return false, "combat" end
    local mode = P.Mode()
    if mode == "classic" then return false, "classic" end
    if unlocked then P.Unlock(false) end
    previewing, previewOpts = true, opts
    parts = P.Parts(mode)
    local fine = true
    if parts.castbar then fine = Step("preview castbar", function() CB.Preview(true, false) end) and fine end
    if parts.list then fine = Step("preview list", function() L.Preview(true, false) end) and fine end
    if parts.toast then fine = Step("preview toast", function() T.Preview(true, false) end) and fine end
    if parts.brand then fine = Step("preview brand", function() P.Brand(true) end) and fine end
    if parts.fade then fine = Step("preview fade", function() Fa.Apply() end) and fine end
    if parts.camera then
        fine = Step("preview camera", function() Cam.Apply({ zoom = S.Get("camera.zoom"), offset = S.Get("camera.offset") }) end) and fine
    end
    if not fine then P.EndPreview("error", false) return false, "error" end
    if C_Timer and C_Timer.NewTimer then
        previewTimer = C_Timer.NewTimer(opts.seconds or P.PREVIEW, function() previewTimer = nil; P.EndPreview("timeout") end)
    end
    Tell()
    return true
end

-- Ends a preview. keepWorld: the faded interface and the camera stay (real Fishing Mode takes them over).
function P.EndPreview(why, keepWorld)
    if not previewing then return false end
    previewing = false
    if previewTimer then previewTimer:Cancel(); previewTimer = nil end
    Step("preview castbar off", function() CB.Preview(false); CB.Hide() end)
    Step("preview list off", function() L.Preview(false); L.Hide() end)
    Step("preview toasts off", function() T.Preview(false) end)
    Step("preview brand off", function() P.Brand(false) end)
    if not keepWorld then
        local instant = why == "combat" or why == "logout" or why == "dead" or why == "world"
        Step("preview camera back", function() Cam.Restore("preview", { keepZoom = why == "logout" }) end)
        Step("preview fade back", function() Fa.Restore(instant) end)
    end
    local opts = previewOpts
    previewOpts = nil
    Tell()
    if opts and opts.done then pcall(opts.done, why) end
    return true
end

function P.Previewing() return previewing end

---------------------------------------------------------------------------
-- Moving the pieces (/tui fish move): sample figures, dragging saves the place
---------------------------------------------------------------------------
function P.Unlock(show)
    show = show and true or false
    if F.InCombat() and show then return false end
    if show and previewing then P.EndPreview("move") end
    unlocked = show
    CB.Preview(show)
    L.Preview(show)
    T.Preview(show)
    if not show then
        if on and parts.castbar then CB.Show() else CB.Hide() end
        if on and parts.list then L.Show() else L.Hide() end
    end
    return true
end

function P.Unlocked() return unlocked end

---------------------------------------------------------------------------
-- Settings, applied at once
---------------------------------------------------------------------------
function P.Configure(path, value)
    local ok, why = S.Set(path, value)
    if not ok then return false, why end
    P.Apply(path)
    return true
end

function P.Apply(path)
    if type(path) ~= "string" then return end
    local group = path:match("^(%w+)%.")
    if group == "castbar" then CB.Relayout()
    elseif group == "list" then L.Relayout(); L.Refresh()
    elseif path == "present.prompts" then CB.RefreshLines()
    elseif group == "journal" then
        if F.JournalUI and path == "journal.scale" then F.JournalUI.Rescale() end
    elseif group == "toast" then T.Relayout(); if path == "toast.enabled" and not S.Get(path) then T.Clear() end
    end
    if not on then return end
    -- a change to what the presentation shows takes effect by coming on again; a fade or camera figure, by redoing that part
    if path == "present.mode" or path == "camera.enabled" or path == "fade.enabled" or path == "list.enabled" or path == "toast.enabled"
        or path == "present.brand" or path == "castbar.enabled" then
        Leave("settings")
        if P.Mode() ~= "classic" then P.Enter("settings") end
    elseif path:match("^fade%.") and parts.fade then
        Step("fade", function() Fa.Restore(true); Fa.Apply(true) end)
    elseif (path == "camera.zoom" or path == "camera.offset") and parts.camera then
        Step("camera", function()
            Cam.Restore("settings")
            Cam.Apply({ zoom = S.Get("camera.zoom"), offset = S.Get("camera.offset") })
        end)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Vibrate()
    if not S.Get("present.vibrate") then return end
    local G = rawget(_G, "C_GamePad")
    if not (G and G.SetVibration and H.PadActive()) then return end
    if pcall(G.SetVibration, "Low", 0.35) and G.StopVibration and C_Timer and C_Timer.After then
        C_Timer.After(0.18, function() pcall(G.StopVibration) end)
    end
end

F.Subscribe("CAST", function()
    if not on and not suppressed and S.Get("present.auto") then P.Enter("cast") end
end)
F.Subscribe("SESSION_END", function()
    Leave("session-end")
    suppressed = false
end)
F.Subscribe("ITEM", function(_, itemID, q, source)
    if on and parts.toast then T.Push(itemID, q, source) end
end)
F.Subscribe("CATCH", function() if on then Vibrate() end end)
F.Subscribe("CONFIG", function(_, path)
    if path == "enabled" and not S.Get("enabled") then Leave("off", true) end
end)

local function OnCombat() if previewing then P.EndPreview("combat") end Leave("combat", true) end
local function OnDead() if previewing then P.EndPreview("dead") end Leave("dead", true) end
local function OnLogout() if previewing then P.EndPreview("logout") end Leave("logout", true) end
local function OnWorld(isLogin, isReload)
    if previewing then P.EndPreview("world") end
    if on then Leave("world", true) end
    -- start-up: a camera left changed by a reload, a disconnect or an error is put back
    if isLogin or isReload then Step("camera recovery", Cam.Recover) end
end

function P.Init()
    R:On("PLAYER_REGEN_DISABLED", OnCombat)
    R:On("PLAYER_DEAD", OnDead)
    R:On("PLAYER_LOGOUT", OnLogout)
    R:On("PLAYER_ENTERING_WORLD", OnWorld)
    -- loaded after the world was entered (a bound key at login, or /tui fish): a record left from before is put back now
    if R.Life and R.Life.InWorld and R.Life.InWorld() then Step("camera recovery", Cam.Recover) end
    R.Perf.Gauge("fishing.toasts", { label = "Fishing: catch notifications showing or waiting", unit = "count", kind = "state",
        read = function() local a, q = T.Active() return #a + #q end })
end

R:On("ADDON_LOADED", function(name)
    if name == F.ADDON then P.Init() end
end)

---------------------------------------------------------------------------
-- /tui fish (Main.lua hands these words here)
---------------------------------------------------------------------------
local function Say(fmt, ...) R.Print("fishing: " .. fmt, ...) end
local function OnOff(word)
    word = (word or ""):lower()
    if word == "on" or word == "yes" then return true end
    if word == "off" or word == "no" then return false end
    return nil
end
local REFUSED = { held = "your fishing records were saved by a newer TwichUI and are kept unchanged.", invalid = "that value doesn't fit.",
    ["not-ready"] = "not ready yet.", unknown = "unknown setting." }
local function Set(path, value, done)
    local ok, why = P.Configure(path, value)
    if ok then Say("%s", done) else Say("%s", REFUSED[why] or tostring(why)) end
    return ok
end
local WHY = { off = "TwichUI Fishing is turned off (/tui fish on).", combat = "not during combat.", dead = "not while you're dead.",
    classic = "the classic presentation has no Fishing Mode: /tui fish mode immersive or compact.", error = "something went wrong; everything was put back." }

P.HELP = {
    "/tui fish mode - Fishing Mode on or off; mode immersive|compact|classic chooses how it looks; mode auto on|off",
    "/tui fish reveal - show the faded interface for a moment (again to fade it); recover - put the camera and interface back",
    "/tui fish move - drag the cast bar, catch list and notices where you want them (again to lock them)",
    "/tui fish preview - try Fishing Mode for 15 seconds with sample figures: HUD, fading and camera (nothing is cast or used)",
    "/tui fish camera on|off, camera zoom <1-30 yards>, camera offset <-2..2, 0 is off>",
    "/tui fish fade - what can be faded and what was; fade on|off, fade bars|units|minimap|panels|meters|twichui|notices|ellesmere on|off,",
    "    fade alpha <0-0.6>, fade add|remove <FrameName>",
    "/tui fish list on|off, list rows <3-12>, list sort count|recent|name, list value show|hide; toasts on|off; scale castbar|list|toast <0.6-1.6>",
    "/tui fish journal [overview|sessions|collections|locations|treasures] - the Fishing Journal; journal summary on|off",
    "/tui fish brand on|off - the TwichUI Fishing emblem at the top left in immersive Fishing Mode",
    "/tui fish motion on|off, prompts on|off, vibrate on|off (gamepad, on a confirmed catch; unverified)",
    "Keys: Key Bindings > TwichUI > \"Fishing Mode\" and \"Fishing: reveal the interface (hold)\".",
}

local PRESET_WORDS = { immersive = true, compact = true, classic = true }

function P.Command(word, rest)
    rest = rest or ""
    local sub, val = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if word == "mode" then
        if sub == "" then
            local ok, why = P.Toggle()
            if on then Say("Fishing Mode on (%s).", P.Mode()) elseif ok == false and why then Say("%s", WHY[why] or why) else Say(F.Session.Current() and "Fishing Mode off. Session recording continues until /tui fish stop or the idle timeout." or "Fishing Mode off.") end
        elseif PRESET_WORDS[sub] then
            Set("present.mode", sub, "Fishing Mode looks " .. sub .. ".")
        elseif sub == "auto" then
            local v = OnOff(val); if v == nil then Say("usage: /tui fish mode auto on|off") return true end
            Set("present.auto", v, v and "Fishing Mode comes on with your first cast." or "Fishing Mode comes on only when you ask.")
        elseif sub == "on" or sub == "off" then
            if (sub == "on") ~= on then P.Command("mode", "") else Say("Fishing Mode is already %s.", sub) end
        else Say("usage: /tui fish mode [immersive|compact|classic|auto on|off]") end
    elseif word == "preview" then
        if previewing then P.EndPreview("player") Say("preview ended.") return true end
        local ok, why = P.Preview()
        if ok then Say("previewing Fishing Mode for %d seconds (sample figures; nothing is cast or used). /tui fish preview again to stop.", P.PREVIEW)
        else Say("%s", ({ live = "Fishing Mode is on: what you see is the real thing." })[why] or WHY[why] or why) end
    elseif word == "reveal" then
        if not on then Say("Fishing Mode is off.") else P.Reveal(not revealed) end
    elseif word == "recover" then
        local r = P.Recover()
        Say("the camera and the interface were put back%s.", r.camera and r.camera.zoom == "restored" and " (camera zoom too)" or "")
    elseif word == "move" then
        if P.Unlock(not unlocked) then Say(unlocked and "drag the pieces where you want them; /tui fish move again to lock." or "locked.")
        else Say("not during combat.") end
    elseif word == "camera" then
        if sub == "zoom" then Set("camera.zoom", tonumber(val), "Fishing Mode's camera distance: " .. tostring(val) .. " yards.")
        elseif sub == "offset" then Set("camera.offset", tonumber(val), "camera offset " .. tostring(val) .. (tonumber(val) == 0 and " (off)." or "."))
        else
            local v = OnOff(sub); if v == nil then Say("usage: /tui fish camera on|off, zoom <yards>, offset <n>") return true end
            Set("camera.enabled", v, "Fishing Mode's camera " .. (v and "on." or "off."))
        end
    elseif word == "fade" and (sub == "" or sub == "status") then
        -- what Fishing Mode can fade, what it did and why it skipped anything (the player's own command; local chat)
        local E = F.Ellesmere and F.Ellesmere.Status()
        if E and E.detected then
            local mods = {}
            for _, m in ipairs(E.modules) do if m.loaded then mods[#mods + 1] = m.label end end
            Say("EllesmereUI %s%s detected: %s.", E.version or "?", E.forever and " (Forever)" or "", #mods > 0 and table.concat(mods, ", ") or "no modules")
        else
            Say("EllesmereUI not detected: the game's own frames are faded.")
        end
        local lines = Fa.Report()
        if #lines == 0 then Say("nothing faded yet this session (/tui fish preview tries it).") end
        for _, line in ipairs(lines) do print(R.GREY .. "  " .. line .. "|r") end
    elseif word == "fade" then
        if sub == "ellesmere" then
            local v = OnOff(val); if v == nil then Say("usage: /tui fish fade ellesmere on|off") return true end
            Set("fade.ellesmere", v, "fading EllesmereUI's frames " .. (v and "on." or "off."))
        elseif sub == "bars" or sub == "units" or sub == "minimap" or sub == "panels" or sub == "meters" or sub == "twichui" or sub == "notices" then
            local v = OnOff(val); if v == nil then Say("usage: /tui fish fade %s on|off", sub) return true end
            Set("fade." .. sub, v, "fading " .. sub .. " " .. (v and "on." or "off."))
        elseif sub == "alpha" then Set("fade.alpha", tonumber(val), "faded parts are drawn at " .. tostring(val) .. ".")
        elseif sub == "add" or sub == "remove" then
            local name = val:match("^([%w_]+)$")
            if not name then Say("usage: /tui fish fade %s <FrameName>", sub) return true end
            local list = {}
            local cur = S.Get("fade.extra")
            if type(cur) == "table" then for _, n in ipairs(cur) do if n ~= name then list[#list + 1] = n end end end
            if sub == "add" then list[#list + 1] = name end
            Set("fade.extra", #list > 0 and list or false, (sub == "add" and "also fading " or "no longer fading ") .. name .. ".")
        else
            local v = OnOff(sub); if v == nil then Say("usage: /tui fish fade on|off, or fade bars|units|minimap|panels|meters|twichui|notices on|off") return true end
            Set("fade.enabled", v, "fading the interface " .. (v and "on." or "off."))
        end
    elseif word == "journal" then
        local UI = F.JournalUI
        if sub == "summary" then
            local v = OnOff(val)
            if v == nil then Say("usage: /tui fish journal summary on|off") return true end
            Set("journal.summary", v, v and "a summary is offered when a session you ended has catches." or "no session summary.")
        elseif sub ~= "" and not (UI and UI.LABEL[sub]) then
            Say("pages: overview, sessions, collections, locations, treasures; journal summary on|off.")
        elseif not UI then
            Say("the journal isn't available.")
        else
            UI.Toggle(sub ~= "" and sub or nil)
        end
    elseif word == "list" then
        if sub == "rows" then Set("list.rows", tonumber(val), "the catch list shows up to " .. tostring(val) .. " rows.")
        elseif sub == "value" then
            local v = val:lower()
            Set("list.value", v, v == "hide" and "no value area on the catch list." or "the catch list keeps its value area.")
        elseif sub == "sort" then
            local v = val:lower(); Set("list.sort", v, "the catch list is sorted by " .. v .. ".")
        else
            local v = OnOff(sub); if v == nil then Say("usage: /tui fish list on|off, rows <n>, sort count|recent|name") return true end
            Set("list.enabled", v, "the catch list " .. (v and "on." or "off."))
        end
    elseif word == "toasts" then
        local v = OnOff(sub); if v == nil then Say("usage: /tui fish toasts on|off") return true end
        Set("toast.enabled", v, "catch notifications " .. (v and "on." or "off."))
    elseif word == "scale" then
        local group = ({ castbar = "castbar", bar = "castbar", list = "list", toast = "toast", toasts = "toast" })[sub]
        if not group then Say("usage: /tui fish scale castbar|list|toast <0.6-1.6>") return true end
        Set(group .. ".scale", tonumber(val), group .. " scale " .. tostring(val) .. ".")
    elseif word == "motion" or word == "prompts" or word == "vibrate" or word == "brand" then
        local v = OnOff(sub); if v == nil then Say("usage: /tui fish %s on|off", word) return true end
        Set("present." .. word, v, word .. " " .. (v and "on." or "off."))
    else
        return false
    end
    return true
end

-- Lines for /tui fish (the status report).
function P.ReportLines()
    local cam, fade = Cam.Status(), Fa.Status()
    local lines = {}
    lines[#lines + 1] = ("Fishing Mode: %s (%s)%s%s"):format(on and "on" or "off", P.Mode(), revealed and ", interface revealed" or "",
        suppressed and ", off for this session" or "")
    lines[#lines + 1] = ("camera: zoom %s, offset %s%s; faded: %d frame%s%s"):format(
        cam.supported.zoom and "available" or "unavailable", cam.supported.offset and "available" or "unavailable",
        cam.active and ", changed now" or "", fade.frames, fade.frames == 1 and "" or "s", fade.kept > 0 and (", " .. fade.kept .. " left to their addon") or "")
    return lines
end
