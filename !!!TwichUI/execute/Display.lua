-- Texture-only health-bar decoration. No protected frame geometry is changed.
local R, C, E = TwichUI, TwichUI.ExecuteRange, TwichUI.ExecuteRangeEllesmere
local D = {}
R.ExecuteRangeDisplay = D
local records, units, count = {}, {}, 0
local observedOwners = setmetatable({}, { __mode = "k" })
local MAX_BARS = 128 -- includes retired provider bars; incompatible churn fails closed
local events, listening, generation, queued = nil, false, 0, false
local refreshing = false
local function On() return R:Enabled("executeRange") end
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Alpha(texture, value)
    if not texture then return end
    if texture._executeAlpha ~= value then texture:SetAlpha(value); texture._executeAlpha = value end
end
local function Hide(record)
    if not record then return end
    Alpha(record.marker, 0)
    Alpha(record.fill, 0)
    for _, texture in ipairs(record.edges) do Alpha(texture, 0) end
    record.active, record.shown, record.pending = false, false, false
end
local function LayoutAllowed(bar)
    -- Protected target descendants are prepared out of combat. Their unchanged
    -- geometry follows the parent natively during combat; recoloring is region-only.
    return not Combat() or (bar.IsProtected and not bar:IsProtected())
end
local function Place(texture, bar, x, y, w, h)
    texture:ClearAllPoints()
    texture:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, y)
    texture:SetSize(w, h)
end
local function Current(record)
    if record.invalid or not On() then return false end
    if record.unit == "target" then
        if not C.Get("target") or not E.Enemy("target") then return false end
        local bar, owner = E.Target()
        return bar == record.bar and owner == record.owner
    end
    if not C.Get("nameplates") or units[record.unit] ~= record then return false end
    local bar, owner = E.Nameplate(record.unit)
    return bar == record.bar and owner == record.owner
end
local function Paint(record)
    if not Current(record) or not record.bar:IsShown() or not record.owner:IsShown() then Hide(record); return end
    local bar = record.bar
    local w, h, orientation, reverse = E.Geometry(bar)
    if not w then Hide(record); return end
    local threshold = C.Get("threshold")
    if record.w ~= w or record.h ~= h or record.orientation ~= orientation
        or record.reverse ~= reverse or record.threshold ~= threshold then
        if not LayoutAllowed(bar) then Hide(record); record.pending = true; return end
        record.fx, record.fy, record.fw, record.fh = nil, nil, nil, nil
        local x, y, mw, mh = C.Marker(w, h, orientation, reverse, threshold)
        Place(record.marker, bar, x, y, mw, mh)
        local edge = math.min(1, w / 2, h / 2)
        Place(record.edges[1], bar, 0, 0, w, edge)
        Place(record.edges[2], bar, 0, h - edge, w, edge)
        Place(record.edges[3], bar, 0, edge, edge, math.max(0.01, h - edge * 2))
        Place(record.edges[4], bar, w - edge, edge, edge, math.max(0.01, h - edge * 2))
        record.w, record.h, record.orientation, record.reverse, record.threshold = w, h, orientation, reverse, threshold
    end
    record.pending = false
    local _, edge, _, highlight = C.Style(C.Get("appearance"))
    local fraction
    if edge or highlight then fraction = E.HealthFraction(record.unit) end
    D.Decorate(record, w, h, orientation, reverse, fraction, LayoutAllowed(bar))
    record.shown = true
end
-- Shared by live verified bars and the Settings-owned static sample. No provider
-- texture, value or frame is written. The fill is below our marker and edges.
function D.Decorate(record, w, h, orientation, reverse, fraction, layoutAllowed)
    local marker, edge, zone, highlight = C.Style(C.Get("appearance"))
    local threshold = C.Get("threshold") / 100
    local active = fraction ~= nil and fraction > 0 and fraction <= threshold
    record.healthUnavailable = (edge or highlight) and fraction == nil
    Alpha(record.marker, marker and 0.7 or 0)
    for _, texture in ipairs(record.edges) do Alpha(texture, edge and active and 0.65 or 0) end
    record.active = active
    local amount = zone and threshold or (highlight and active and fraction or 0)
    if amount <= 0 then Alpha(record.fill, 0); return end
    local x, y, fw, fh = C.Region(w, h, orientation, reverse, amount)
    if record.fx ~= x or record.fy ~= y or record.fw ~= fw or record.fh ~= fh then
        if not layoutAllowed then
            -- Preserve unchanged marker/edge while a protected fill needs layout.
            Alpha(record.fill, 0); record.pending = true
            -- Use the established active edge instead of a stale filled fraction.
            if highlight and active then for _, texture in ipairs(record.edges) do Alpha(texture, 0.65) end end
            return
        end
        Place(record.fill, record.bar, x, y, fw, fh)
        if orientation == "HORIZONTAL" then
            record.fill:SetTexCoord(reverse and 1 - amount or 0, reverse and 1 or amount, 0, 1)
        else
            record.fill:SetTexCoord(0, 1, reverse and 0 or 1 - amount, reverse and amount or 1)
        end
        record.fx, record.fy, record.fw, record.fh = x, y, fw, fh
    end
    local color, texture = C.Get("color"), C.Get("texture")
    local media = R.MenuStyle and R.MenuStyle.StatusBars
    local file = media and media.Resolve(texture) or [[Interface\Buttons\WHITE8X8]]
    file = file or [[Interface\Buttons\WHITE8X8]]
    if record.fillColor ~= color or record.fillFile ~= file then
        if record.fill:SetTexture(file) == false then record.fill:SetTexture([[Interface\Buttons\WHITE8X8]]) end
        record.fill:SetVertexColor(tonumber(color:sub(3,4),16)/255, tonumber(color:sub(5,6),16)/255,
            tonumber(color:sub(7,8),16)/255, tonumber(color:sub(1,2),16)/255)
        record.fillColor, record.fillFile = color, file
    end
    Alpha(record.fill, C.Get("opacity") / 100)
end
function D.CreateDecoration(bar)
    local record = { bar = bar, edges = {} }
    record.marker = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    record.marker:SetColorTexture(0.83, 0.65, 0.32, 1)
    for i = 1, 4 do
        record.edges[i] = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        record.edges[i]:SetColorTexture(0.85, 0.47, 0.28, 1)
    end
    record.fill = bar:CreateTexture(nil, "OVERLAY", nil, 0)
    Hide(record)
    return record
end
function D.Preview(record, w, h, fraction)
    local x,y,mw,mh = C.Marker(w,h,"HORIZONTAL",false,C.Get("threshold"))
    Place(record.marker, record.bar, x,y,mw,mh)
    local edge = math.min(1,w/2,h/2)
    Place(record.edges[1],record.bar,0,0,w,edge)
    Place(record.edges[2],record.bar,0,h-edge,w,edge)
    Place(record.edges[3],record.bar,0,edge,edge,math.max(0.01,h-edge*2))
    Place(record.edges[4],record.bar,w-edge,edge,edge,math.max(0.01,h-edge*2))
    D.Decorate(record,w,h,"HORIZONTAL",false,fraction,true)

end
local function RefreshRecord(record)
    -- Provider changes may invalidate fields while their own callbacks run.
    -- Fail closed without assigning, repairing or walking an unknown hierarchy.
    local ok = pcall(Paint, record)
    if not ok then Hide(record) end
end
local function Observe(record)
    local bar = record.bar
    bar:HookScript("OnHide", function() Hide(record) end)
    bar:HookScript("OnShow", function() if On() then D.Queue() end end)
    bar:HookScript("OnSizeChanged", function() if On() then RefreshRecord(record) end end)
    if hooksecurefunc then
        for _, method in ipairs({ "SetOrientation", "SetReverseFill" }) do
            hooksecurefunc(bar, method, function() if On() then RefreshRecord(record) end end)
        end
        local owner = record.owner
        if record.unit ~= "target" and not observedOwners[owner] and type(owner.UpdateHealthValues) == "function" then
            -- EUI can swap a pooled plate's unit token without add/remove events.
            -- Post-observe that verified method so the old occupant is hidden on
            -- the same update, even when ns.plates still has the earlier key.
            observedOwners[owner] = true
            hooksecurefunc(owner, "UpdateHealthValues", function()
                local current = records[owner.health]
                if On() and current then RefreshRecord(current) end
            end)
        end
    end
end
local function Attach(unit, bar, owner)
    if not bar then return end
    local record = records[bar]
    if not record then
        if count >= MAX_BARS or not LayoutAllowed(bar) then return end
        record = D.CreateDecoration(bar)
        record.owner, record.unit, record.invalid = owner, unit, true
        records[bar], count = record, count + 1
        Observe(record)
        record.invalid = false
    end
    if record.invalid then return end
    -- A pooled bar receives only its current verified registry occupant.
    if record.unit ~= unit then
        if units[record.unit] == record then units[record.unit] = nil end
        Hide(record)
    end
    record.unit, record.owner = unit, owner
    units[unit] = record
    RefreshRecord(record)
end
local function Discover()
    if C.Get("target") then
        pcall(function() Attach("target", E.Target()) end)
    end
    if C.Get("nameplates") then
        local registry, visited = E.Registry(), 0
        if registry then
            for unit in pairs(registry) do
                visited = visited + 1
                if visited > MAX_BARS then break end
                if E.NameplateToken(unit) then
                    pcall(function() Attach(unit, E.Nameplate(unit)) end)
                end
            end
        end
    end
end
function D.Queue()
    if queued or not On() or not (C_Timer and C_Timer.After) then return end
    queued = true
    local expected = generation
    -- One event-turn handoff: EUI populates its registry synchronously in its
    -- NAME_PLATE_UNIT_ADDED/login handlers. No guessed delay or retry polling.
    C_Timer.After(0, function()
        if expected ~= generation then return end
        queued = false
        if On() then D.Refresh() end
    end)
end
local function Event(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local record = E.NameplateToken(unit) and units[unit]
        if record then Hide(record); units[unit] = nil end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if E.Plain(unit) and type(unit) == "string" then
            local record = units[unit]
            if record then RefreshRecord(record) end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then D.Queue()
    elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" or event == "UNIT_NAME_UPDATE" then
        if E.Plain(unit) and (unit == "target" or E.NameplateToken(unit)) then
            local record = units[unit]
            if record then RefreshRecord(record) end
            -- EUI also promotes initially friendly/pending plates on these events.
            D.Queue()
        end
    else D.Refresh(); D.Queue() end
end
local EVENT_NAMES = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
    "UNIT_FACTION", "UNIT_FLAGS", "UNIT_NAME_UPDATE" }
function D.Refresh()
    if refreshing then return end
    refreshing = true
    local on = On()
    if on and not events then events = CreateFrame("Frame"); events:SetScript("OnEvent", Event) end
    if on ~= listening then
        listening = on
        generation, queued = generation + 1, false
        if on then for _, event in ipairs(EVENT_NAMES) do events:RegisterEvent(event) end
        elseif events then events:UnregisterAllEvents() end
    end
    -- Resolver errors (including a provider being rebuilt mid-callback) must not
    -- latch the reentrancy guard or leave yesterday's attachment visible.
    if on then pcall(Discover) end
    for _, record in pairs(records) do RefreshRecord(record) end
    refreshing = false
end
function D.Invalidate()
    generation, queued = generation + 1, false
    for _, record in pairs(records) do Hide(record) end
    units = {}
    D.Refresh(); D.Queue()
end
function D.Status()
    if not On() then return "off" end
    local target, plates, unavailable, pending = false, 0, false, false
    for _, record in pairs(records) do
        if record.shown then
            if record.unit == "target" then target = true else plates = plates + 1 end
            unavailable = unavailable or record.healthUnavailable
        end
        pending = pending or record.pending == true
    end
    return "on", target, plates, unavailable, pending
end
C.Subscribe(function() D.Refresh(); D.Queue() end)
R:OnInit(D.Refresh)
R:On("PLAYER_LOGIN", function() D.Refresh(); D.Queue() end)
R.Profiles.OnApply("layout", "executeRange", D.Invalidate)
R.Profiles.OnChange(D.Invalidate) -- Duplicate changes profile identity without OnApply
-- Bounded retained resources, read only while diagnostics asks. No timed hot-path scope.
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("execute.bars", { label = "Execute range observed bars", unit = "count", kind = "pool", read = function() return count end })
end

if R.MenuStyle and R.MenuStyle.StatusBars then
    R.MenuStyle.StatusBars.Subscribe(function() D.Refresh() end)
end
