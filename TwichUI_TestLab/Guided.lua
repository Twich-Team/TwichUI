-- TwichUI Test Lab: the guided-case mechanism (R.TestLab.Guided)
-- A guided case asks the player to put the pointer somewhere and then READS what the client says is under it. The hard part is taking the
-- sample WITHOUT moving the pointer, so a click on a "Sample" button will not do. Two ways, both explicit and both ending with the case:
--   the key       while a request is open, ONE key (G.KEY) is bound with SetOverrideBindingClick to a Lab-owned button. An override binding
--                 belongs to its owner frame, is never saved, and is removed by ClearOverrideBindings(owner); nothing else is rebound and
--                 SaveBindings is never called. SetOverrideBindingClick is used by Blizzard's own insecure code in the Forever UI source
--                 (Blizzard_GamepadSharedUtility); that this client allows it from an addon is reported by the first real run, not assumed.
--                 It is refused in combat, and if the function is missing the key is simply not offered.
--   the countdown "Sample in N s" on the prompt takes the sample N seconds after the click, wherever the pointer is by then; no binding at all.
-- A request never clicks the target, writes nothing and listens to nothing: the sample is taken in the key's (or the button's) handler,
-- once, and the case reads the finished snapshot. G.End releases everything and is called when the case ends, on Stop, on combat, on a
-- closed window, on an error and on a timeout (Runner calls it), so no binding can outlive the run. G.Snapshot() says what is still live.

local R = TwichUI
local TL = R.TestLab
local G = {}
TL.Guided = G

G.KEY = "F9"
G.COUNTDOWN = 5
G.MAX_ATTEMPTS = 8
G.NAME = "TwichUITestLabSampleButton"
G.PROMPT_NAME = "TwichUITestLabPrompt"

local state      -- the open request, or nil
local proxy      -- the Lab-owned, mouse-passive button the key is bound to (made once)
local prompt     -- the small instruction window (made once)
local boundKey   -- the key bound right now, or nil

local function Now() return TL.Runner and TL.Runner.Now() or (GetTime and GetTime() or 0) end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- The proxy button: shown while a request is open, 1x1, mouse OFF, so it can never take the pointer from anything
---------------------------------------------------------------------------
local function Proxy()
    if proxy then return proxy end
    proxy = CreateFrame("Button", G.NAME, UIParent)
    proxy:SetSize(1, 1)
    proxy:EnableMouse(false)
    proxy:SetScript("OnClick", function() G.Trigger("key") end)
    proxy:Hide()
    return proxy
end

local function Unbind()
    if boundKey and proxy and ClearOverrideBindings then pcall(ClearOverrideBindings, proxy) end
    boundKey = nil
end

local function Bind(key)
    if InCombat() then return false, "not during combat" end
    if type(SetOverrideBindingClick) ~= "function" or type(ClearOverrideBindings) ~= "function" then
        return false, "this client has no SetOverrideBindingClick, so there is no key"
    end
    local p = Proxy()
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    p:Show()
    local ok = pcall(SetOverrideBindingClick, p, true, key, G.NAME, "LeftButton")
    if not ok then p:Hide() return false, "the client refused the key binding" end
    boundKey = key
    return true
end

---------------------------------------------------------------------------
-- The prompt window (built the first time a request opens)
---------------------------------------------------------------------------
local function BuildPrompt()
    if prompt then return prompt end
    local L, F, CL = R.Look, R.FrameLook, R.CraftLook
    local p = CreateFrame("Frame", G.PROMPT_NAME, UIParent)
    p:SetSize(560, 190)
    p:SetPoint("TOP", UIParent, "TOP", 0, -30)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if p.SetDontSavePosition then p:SetDontSavePosition(true) end
    CL.PanelFace(p, "card")
    p.title = L.Text(p, "heading"); p.title:SetPoint("TOPLEFT", 14, -10)
    p.body = L.Text(p, "body"); p.body:SetPoint("TOPLEFT", 14, -34); p.body:SetWidth(532); p.body:SetWordWrap(true); p.body:SetJustifyV("TOP")
    p.status = L.Text(p, "small"); p.status:SetPoint("BOTTOMLEFT", 14, 44); p.status:SetWidth(532); p.status:SetWordWrap(true)
    local function Button(label, w, onClick)
        local b = F.Button(p, label, w, "secondary", onClick)
        b:SetHeight(24); CL.Control(b); CL.Font(b.text, 13)
        return b
    end
    p.sample = Button("Sample now", 110, function() G.Trigger("button") end)
    p.sample:SetPoint("BOTTOMLEFT", 14, 10)
    p.count = Button("Sample in " .. G.COUNTDOWN .. " s", 130, function() G.StartCountdown() end)
    p.count:SetPoint("LEFT", p.sample, "RIGHT", 8, 0)
    p.skip = Button("Skip this step", 120, function() G.Skip() end)
    p.skip:SetPoint("LEFT", p.count, "RIGHT", 8, 0)
    p.cancel = Button("Cancel", 90, function() if TL.Runner then TL.Runner.Stop("user") end end)
    p.cancel:SetPoint("LEFT", p.skip, "RIGHT", 8, 0)
    p:Hide()
    prompt = p
    return p
end

local function Say(text)
    if prompt and state then prompt.status:SetText(text or "") end
end

local function KeyText()
    if boundKey then return ("Press %s (the pointer does not move)."):format(boundKey) end
    return ("No key is available (%s). Use \"Sample in %d s\", then move the pointer onto the target and leave it there."):format(state and state.keyWhy or "unknown", G.COUNTDOWN)
end

local function Paint()
    if not (prompt and state) then return end
    local run = TL.Runner and TL.Runner.Progress and TL.Runner.Progress()   -- where this step stands in the run
    prompt.title:SetText((state.title or "Pointer probe") .. (run and (" (case %d of %d)"):format(run.at, run.n) or ""))
    local lines = {}
    for i, line in ipairs(state.lines or {}) do lines[i] = i .. ". " .. line end
    lines[#lines + 1] = (#lines + 1) .. ". " .. KeyText()
    prompt.body:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- A request
---------------------------------------------------------------------------
-- req = { title, lines = { "..." }, capture = function() -> snapshot (taken at the moment of the key; read only) }
-- Returns true, or false and why (the caller skips the case with that sentence).
function G.Begin(req)
    if state then G.End("replaced") end
    if type(req) ~= "table" or type(req.capture) ~= "function" then return false, "no capture function" end
    if InCombat() then return false, "not during combat" end
    state = { title = req.title, lines = req.lines, capture = req.capture, status = "waiting", attempts = 0, startedAt = Now() }
    local ok, why = Bind(G.KEY)
    if not ok then state.keyWhy = why end
    BuildPrompt():Show()
    Paint()
    Say("Waiting for you.")
    return true
end

function G.Active() return state ~= nil end
function G.Status() return state and state.status or "idle", state and state.sample, state and state.err end

-- Takes the sample NOW (called from the key's handler, the Sample button's, or the countdown's). Ignored unless a request is waiting.
function G.Trigger(source)
    local s = state
    if not s or s.status ~= "waiting" then return false end
    s.countdownAt = nil
    s.attempts = s.attempts + 1
    local ok, snap = pcall(s.capture, source, s.attempts)
    if not ok then
        s.status, s.err = "failed", tostring(snap)
        Say("The sample could not be taken.")
        return true
    end
    s.status, s.sample = "sample", snap
    Say(("Sample %d taken (%s)."):format(s.attempts, tostring(source)))
    return true
end

-- The sample was not usable (the pointer was not on the target): wait for another, and say why. Returns false after MAX_ATTEMPTS.
function G.Retry(message)
    local s = state
    if not s or s.status ~= "sample" then return false end
    if s.attempts >= G.MAX_ATTEMPTS then return false end
    s.status, s.sample = "waiting", nil
    Say(("Not counted (%d of %d): %s"):format(s.attempts, G.MAX_ATTEMPTS, tostring(message)))
    return true
end

function G.StartCountdown()
    local s = state
    if not s or s.status ~= "waiting" then return false end
    s.countdownAt = Now() + G.COUNTDOWN
    Say(("Taking a sample in %d seconds. Move the pointer onto the target and leave it there."):format(G.COUNTDOWN))
    return true
end

-- Called by the case's loop: fires a due countdown. Returns true when it took the sample.
function G.Poll()
    local s = state
    if not s or s.status ~= "waiting" or not s.countdownAt then return false end
    if Now() >= s.countdownAt then return G.Trigger("countdown") end
    if prompt then Say(("Taking a sample in %.0f s."):format(math.max(0, s.countdownAt - Now()))) end
    return false
end

function G.Skip()
    local s = state
    if not s or (s.status ~= "waiting" and s.status ~= "sample") then return false end
    s.status, s.countdownAt = "skipped", nil
    Say("Skipped.")
    return true
end

-- Releases everything: the key, the prompt, a pending countdown. Safe to call at any time, any number of times.
function G.End()
    state = nil
    Unbind()
    if proxy then proxy:Hide() end
    if prompt then prompt:Hide() end
end

-- What is still live (for the tests and the diagnostics): nothing, once a run is over.
function G.Snapshot()
    return { active = state ~= nil, status = state and state.status or "idle", bound = boundKey, proxyShown = proxy ~= nil and proxy:IsShown() or false,
        promptShown = prompt ~= nil and prompt:IsShown() or false, countdown = state ~= nil and state.countdownAt ~= nil }
end
