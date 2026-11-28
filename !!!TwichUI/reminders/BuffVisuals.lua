-- Forever can draw a filtered helpful aura in combat through a native aura slot.
-- The slot owns visibility and animation. We only change the slot's configuration
-- and the public mount's alpha, without querying the aura button or its descendants.
local R = TwichUI
local D, GW, Perf = R.ReminderDisplay, R.ReminderGlow, R.Perf
local B = {}
R.ReminderBuffVisuals = B

local SLOT = "reminder"
local rows, spare = {}, { display = {}, glow = {} }
local barEvents, registered = {}, {}
for _, event in ipairs(GW.BUTTON_EVENTS) do barEvents[event] = true end
local eventFrame, queued, generation, made = nil, false, 0, 0
local watchingBars, triedLoad = false, false

local function CanBuild()
    if InCombatLockdown and InCombatLockdown() then return false end
    local secret = C_Secrets and C_Secrets.ShouldAurasBeSecret
    return not secret or R.ReminderState.Plain(secret()) == false
end

local function SetLayer(layer, on)
    if not layer then return false end
    if layer.on ~= on then
        -- Keep the public mount dark if the client refuses to enable or clear a slot.
        layer.mount:SetAlpha(0)
        local ok = pcall(layer.container.SetAuraSlotEnabled, layer.container, SLOT, on)
        if ok then
            layer.on = on
            if on then layer.mount:SetAlpha(1) end
        else
            layer.on = nil
        end
    end
    return layer.on == true
end

local function Release(layer)
    if not layer then return end
    SetLayer(layer, false)
    local pool = spare[layer.kind]
    pool[#pool + 1] = layer
end

local function NewLayer(kind)
    if not AuraContainerInbound then
        if not triedLoad and C_AddOns and C_AddOns.LoadAddOn then
            triedLoad = true
            pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        end
        if not AuraContainerInbound then return nil end
    end
    local mount = CreateFrame("Frame", nil, UIParent)
    mount:EnableMouse(false)
    mount:SetAlpha(0)
    mount:SetAllPoints(UIParent)
    local container = CreateFrame("AuraContainer", nil, mount, "CustomAuraContainerTemplate")
    container:EnableMouse(false)
    container:SetPoint("CENTER", mount, "CENTER")
    container:SetUnit("player")
    local button = container:AddAuraSlot(SLOT, "HELPFUL", { candidateFilters = { includeSpellIDs = {} } })
    container:SetAuraSlotEnabled(SLOT, false)
    button:EnableMouse(false)
    button:SetSize(1, 1)
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER")
    container:Show()
    container:SetEnabled(true)
    made = made + 1
    return { kind = kind, mount = mount, container = container, button = button, on = false }
end

local function Prepare(layer, row, target)
    if layer.filters ~= row.filters then
        layer.container:SetAuraSlotCandidateFilters(SLOT, row.filters)
        layer.filters = row.filters
    end
    if target then
        local mount = layer.mount
        mount:SetParent(target)
        mount:ClearAllPoints()
        mount:SetAllPoints(target)
        layer.surface = R.BarGlowDraw.DrawAuraGlow(mount, layer.button, layer.surface, target, GW.Style(row.view.glow))
    else
        layer.surface = D.DrawAuraSurface(layer.button, layer.surface, row.view)
    end
end

local function Acquire(kind, row, target)
    local layer = table.remove(spare[kind])
    if not layer then
        local ok, created = pcall(NewLayer, kind)
        if not ok then return false end
        layer = created
    end
    if not layer then return false end
    if pcall(Prepare, layer, row, target) then return layer end
    Release(layer)
    return false
end

local function Gate(row)
    local quiet = R.QuietScreen and R.QuietScreen.On()
    local on = SetLayer(row.display, row.useNative and not quiet)
    for target, layer in pairs(row.glows) do
        SetLayer(layer, on and row.buttons[target] == true)
    end
    return on
end

local function Reconcile()
    local build = CanBuild()
    local bt = watchingBars and R.BarGlowButtons
    if bt and (bt.dirty or bt.generation == 0) then bt.Map() end
    for _, row in pairs(rows) do
        if build and row.display == nil then row.display = Acquire("display", row) end
        local buttons = {}
        if bt and row.view.glow.on then
            for _, target in ipairs(bt.ForSpell(bt.SpellName(row.view.glow.spell))) do
                buttons[target] = true
                if build and row.display and row.glows[target] == nil then
                    row.glows[target] = Acquire("glow", row, target)
                end
            end
        end
        row.buttons = buttons
        Gate(row)
        if build then
            for target, layer in pairs(row.glows) do
                if not buttons[target] then Release(layer); row.glows[target] = nil end
            end
        end
    end
end

local function OnEvent(_, event)
    if barEvents[event] and R.BarGlowButtons then R.BarGlowButtons.Dirty() end
    if queued then return end
    queued = true
    local mine = generation
    C_Timer.After(0.05, function()
        if mine ~= generation then return end
        queued = false
        Perf.Call("reminders.buffVisuals", Reconcile)
    end)
end

local function SyncEvents()
    local events = {}
    local needsBars = false
    if next(rows) then
        events.PLAYER_REGEN_ENABLED = true
        events.ADDON_RESTRICTION_STATE_CHANGED = true
        for _, row in pairs(rows) do if row.view.glow.on then needsBars = true; break end end
        if needsBars then for event in pairs(barEvents) do events[event] = true end end
    else
        generation, queued = generation + 1, false
    end
    if needsBars and not watchingBars and R.BarGlowButtons then R.BarGlowButtons.Dirty() end
    watchingBars = needsBars
    if not eventFrame then
        if not next(events) then return end
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", Perf.Wrap("reminders.buffVisuals.event", OnEvent))
    end
    for event in pairs(registered) do
        if not events[event] then eventFrame:UnregisterEvent(event); registered[event] = nil end
    end
    for event in pairs(events) do
        if not registered[event] then eventFrame:RegisterEvent(event); registered[event] = true end
    end
end

local function SetView(id, view)
    local row = rows[id]
    if row and row.view == view then return end
    if row then
        Release(row.display)
        for _, layer in pairs(row.glows) do Release(layer) end
        rows[id] = nil
    end
    local cond = view and view.valid and view.enabled and #view.leaves == 1 and view.leaves[1].cond
    if cond and cond.type == "aura" and not cond.harmful and cond.what == "present"
        and view.display.delay == 0 and view.display.minShow == 0 then
        local spells = {}
        for _, spell in ipairs(cond.spells) do spells[spell] = true end
        rows[id] = { view = view, filters = { includeSpellIDs = spells }, glows = {}, buttons = {}, useNative = false }
    end
end

function B.Sync(views, active, ctx)
    local keep = {}
    for _, view in ipairs(views or {}) do
        local here = active[view.id] and R.ReminderEval.Applies(view, ctx) == R.ReminderConditions.MATCH
        if here then keep[view.id] = true; SetView(view.id, view) end
    end
    for id in pairs(rows) do if not keep[id] then SetView(id, nil) end end
    SyncEvents()
    if next(rows) then Perf.Call("reminders.buffVisuals", Reconcile) end
end

function B.Update(view, here)
    SetView(view.id, here and view or nil)
    SyncEvents()
    if rows[view.id] then Perf.Call("reminders.buffVisuals", Reconcile) end
end

function B.UseNative(id, useNative)
    local row = rows[id]
    if not row then return false end
    if row.useNative == useNative then return row.display and row.display.on == true end
    row.useNative = useNative
    return Gate(row)
end

if R.QuietScreen then
    R.QuietScreen.OnChange(function() for _, row in pairs(rows) do Gate(row) end end)
end

function B.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    return { made = made, spare = #spare.display + #spare.glow, events = events }
end
