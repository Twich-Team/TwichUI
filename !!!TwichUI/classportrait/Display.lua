-- EllesmereUI 9.9.1 verified adapter. No enumeration, layout writes, or global hooks.
local R, C = TwichUI, TwichUI.ClassPortrait
local D = {}
R.ClassPortraitDisplay = D
local holder, texture, host, portrait, class, classRead
local status, preview, refreshing = "off", false, false
local hooked = setmetatable({}, { __mode = "k" })
local events, retryGeneration = nil, 0
local activeEvents = false
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Wanted() return C.Get("enabled") or preview end
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Frame(f)
    return type(f) == "table" and type(f.GetObjectType) == "function"
        and type(f.GetWidth) == "function" and type(f.GetHeight) == "function"
        and type(f.GetParent) == "function" and type(f.HookScript) == "function"
end
function D.Find()
    local f = _G.EllesmereUIUnitFrames_Player
    if not Frame(f) or type(f.GetAttribute) ~= "function" then return nil end
    local ok, unit = pcall(f.GetAttribute, f, "unit")
    if not ok or not Plain(unit) or unit ~= "player" then return nil end
    local p = type(f.Portrait) == "table" and f.Portrait.backdrop
    -- Verified direct child, never search descendants or use a Blizzard fallback.
    if not Frame(p) or p:GetParent() ~= f then return nil end
    return f, p
end
local function Retry()
    retryGeneration = retryGeneration + 1
    local generation = retryGeneration
    if not (Wanted() and C_Timer and C_Timer.After) then return end
    -- Bounded login/load recovery; never an indefinite polling loop.
    for _, delay in ipairs({ 0, 0.5, 2, 5 }) do
        C_Timer.After(delay, function()
            if generation == retryGeneration and Wanted() then D.Refresh() end
        end)
    end
end
local function Event(_, event)
    if event == "PLAYER_REGEN_DISABLED" then preview = false end
    D.Refresh()
    if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" then Retry() end
end
local function SyncEvents()
    local want = Wanted()
    if want and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", Event)
    end
    if want == activeEvents then return end
    activeEvents = want
    retryGeneration = retryGeneration + 1
    if want then
        for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
            "PLAYER_REGEN_DISABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do events:RegisterEvent(e) end
    elseif events then events:UnregisterAllEvents() end
end
local function Observe(f)
    if hooked[f] then return end
    hooked[f] = true
    -- Only the two verified layout frames. Hooks stay inert while disabled and
    -- don't capture old frames. Movement/scale/visibility follow the parent natively.
    f:HookScript("OnSizeChanged", function() if Wanted() then D.Refresh() end end)
    f:HookScript("OnShow", function() if Wanted() then D.Refresh() end end)
    f:HookScript("OnHide", function() if Wanted() then D.Refresh() end end)
    if hooksecurefunc then
        hooksecurefunc(f, "SetFrameStrata", function() if Wanted() then D.Refresh() end end)
        hooksecurefunc(f, "SetFrameLevel", function() if Wanted() then D.Refresh() end end)
    end
end
function D.Refresh()
    if refreshing then return end
    refreshing = true
    SyncEvents()
    if not classRead and R.Life and R.Life.loggedIn then
        local _, token = UnitClass("player")
        if Plain(token) then class = token end
        classRead = true
    end
    -- Keep an already attached decoration during combat; only hide stale art.
    local currentFrame, currentPortrait = D.Find()
    if Combat() and Wanted() and holder and currentFrame == host and currentPortrait == portrait then
        status = "combat"
        refreshing = false
        return
    end
    if texture then texture:Hide() end
    if not Wanted() then status = "off"
    elseif not (R.Life and R.Life.loggedIn) then status = "waiting"
    else
        local f, p = D.Find()
        if not C.ART[class] then status = "class"
        elseif not f then status = "missing"
        elseif Combat() then status = "combat" -- every layout write deferred
        else
            if not holder then
                holder = CreateFrame("Frame", nil, p)
                holder:EnableMouse(false)
                texture = holder:CreateTexture(nil, "BACKGROUND")
            elseif portrait ~= p then holder:SetParent(p) end
            host, portrait = f, p
            Observe(f); Observe(p)
            holder:ClearAllPoints()
            holder:SetAllPoints(p)
            local strata = C.Get("strata")
            holder:SetFrameStrata(strata == "inherit" and f:GetFrameStrata() or strata)
            -- Only our visual holder changes. Above clears the portrait and the
            -- verified text host (+15); a strata override takes priority over levels.
            local level = C.Get("above") and (math.max(f:GetFrameLevel(), p:GetFrameLevel()) + 20)
                or math.max(0, f:GetFrameLevel() - 1)
            holder:SetFrameLevel(level)
            local w, h = p:GetWidth(), p:GetHeight()
            local size, x, y
            if Plain(w) and Plain(h) and type(w) == "number" and type(h) == "number" then
                size, x, y = C.Placement(class, w, h)
            end
            if not size then status = "missing"
            else
                local path = R.PATH .. "media\\classportrait\\" .. class
                local loaded = true
                if D.texturePath ~= path then
                    loaded = texture:SetTexture(path)
                    if loaded ~= false then D.texturePath = path end
                end
                if loaded == false then status = "texture"
                else
                    texture:ClearAllPoints()
                    texture:SetPoint("CENTER", p, "CENTER", x, y)
                    texture:SetSize(size, size)
                    texture:Show()
                    status = "ready"
                end
            end
        end
    end
    refreshing = false
end
function D.Status() return status end
function D.Class() return class end
function D.Holder() return holder end
function D.Texture() return texture end
function D.PreviewActive() return preview end
function D.PreviewStart()
    if Combat() then return false end
    preview = true; D.Refresh(); Retry()
    return status == "ready"
end
function D.PreviewStop() preview = false; D.Refresh() end
C.Subscribe(function() D.Refresh(); if status == "missing" then Retry() end end)
R:On("PLAYER_LOGIN", function() D.Refresh(); Retry() end)
R:OnInit(function() D.Refresh() end)
R.Profiles.OnApply("layout", "classPortrait", function() preview = false; D.Refresh(); Retry() end)
R.OnSettingsClosed(D.PreviewStop)
-- Event-rare layout code needs no timed scope. Gauge retained resources without
-- constructing anything, following the existing diagnostics registration pattern.
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("classportrait.frames", { label = "Class portrait decoration frames", unit = "count", kind = "pool",
        read = function() return holder and 1 or 0 end })
    R.Perf.Gauge("classportrait.events", { label = "Class portrait event listeners", unit = "count", kind = "listeners",
        read = function() return activeEvents and 6 or 0 end })
end
