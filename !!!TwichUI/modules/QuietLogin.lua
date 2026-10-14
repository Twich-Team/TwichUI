-- TwichUI: quiet login
-- Hides the "vX.Y loaded, type /foo for options" lines addons print when you
-- log in or reload. Only runs for a short window: from the moment TwichUI
-- loads (before other addons) until a few seconds after the loading screen.
-- Nothing is lost: /twichui hidden prints everything that was held back.
-- Real problems (errors, warnings, conflicts) are never hidden.

local R = TwichUI
local Q = {}
R.Quiet = Q

local WINDOW_AFTER_LOAD = 10     -- seconds after the loading screen
Q.hidden = {}
Q.active = false
local bypass = false

-- Lines that look like a welcome / loaded / how-to-use message.
local HIDE = {
    "loaded", "welcome", "initiali[sz]ed", "%f[%w]v%d+%.%d", "version %d", "version:",
    "type /", "use /", "/%a+ for ", "/%a+ to ", "thanks? for using", "thank you for",
    "enabled%.?$", "is ready", "by [%w%s]+ loaded",
}
-- Never hide these, even inside the window.
local KEEP = { "error", "fail", "warn", "conflict", "incompatible", "missing", "disabled due", "outdated", "out of date" }

local function Plain(msg)
    return msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):lower()
end

local function ShouldHide(msg)
    if not Q.active or bypass or type(msg) ~= "string" then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    if msg:find("TwichUI:", 1, true) then return false end
    local p = Plain(msg)
    for _, k in ipairs(KEEP) do if p:find(k, 1, true) then return false end end
    for _, pat in ipairs(HIDE) do if p:find(pat) then return true end end
    return false
end

local function Hold(msg)
    Q.hidden[#Q.hidden + 1] = msg
end

-- 1) print() goes through the print handler.
local origPrint
local function PrintHandler(...)
    if Q.active then
        local n = select("#", ...)
        local parts = {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        local msg = table.concat(parts, " ")
        if ShouldHide(msg) then Hold(msg) return end
    end
    return origPrint(...)
end

-- 2) Many addons write straight to the chat frame. Wrap it only for the
--    login window, then put the original back.
local wrapped
local function Wrap()
    local cf = DEFAULT_CHAT_FRAME
    if not cf or wrapped then return end
    local orig = cf.AddMessage
    -- own: an AddMessage someone already set on the frame itself (nil = the frame's own method)
    wrapped = { frame = cf, own = rawget(cf, "AddMessage"), fn = function(self, msg, ...)
        if ShouldHide(msg) then Hold(msg) return end
        return orig(self, msg, ...)
    end }
    cf.AddMessage = wrapped.fn
end

local function Unwrap()
    if wrapped and wrapped.frame.AddMessage == wrapped.fn then
        wrapped.frame.AddMessage = wrapped.own   -- back to what was there before
    end
    wrapped = nil
end

function Q:Stop()
    Q.active = false
    Unwrap()
    -- Same for print, unless another addon has chained its own handler onto ours.
    if origPrint and getprinthandler() == PrintHandler then setprinthandler(origPrint) end
end

function Q:ShowHidden()
    if #Q.hidden == 0 then R.Print("no addon messages were hidden this session.") return end
    bypass = true
    R.Print("%d addon messages hidden at login:", #Q.hidden)
    for _, m in ipairs(Q.hidden) do DEFAULT_CHAT_FRAME:AddMessage("  " .. m) end
    bypass = false
end

R:OnInit(function()
    if not R:Enabled("quietLogin") then return end
    Q.active = true
    if getprinthandler and setprinthandler then
        origPrint = getprinthandler()
        setprinthandler(PrintHandler)
    end
    Wrap()
end)

R:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if Q.active and (isLogin or isReload) then
        C_Timer.After(WINDOW_AFTER_LOAD, function() Q:Stop() end)
    elseif Q.active then
        Q:Stop()
    end
end)
