-- One flat UI sparkle overlay anchored to the current object's nameplate, reused forever.
-- Only visual alpha is borrowed, only for that object, and restored when the target changes.
local R = TwichUI
local G, Perf = R.QoLGathering, R.Perf
local D = {}
G.Display = D
local Safe = G.Safe
local frame, plate, kind, age, token
local stars, veiled = {}, {}
local COLORS = { herb = { 0.78, 0.91, 0.55 }, ore = { 1, 0.79, 0.42 }, locked = { 0.65, 0.65, 0.65 } }
local function Unveil()
    for object, alpha in pairs(veiled) do
        if Safe(object.GetAlpha, object) == 0 then Safe(object.SetAlpha, object, alpha) end
        veiled[object] = nil
    end
end
local function Veil(object)
    if not object or Safe(object.IsForbidden, object) == true then return end
    local alpha = Safe(object.GetAlpha, object)
    if type(alpha) ~= "number" then return end
    if veiled[object] == nil or alpha ~= 0 then veiled[object] = alpha end
    Safe(object.SetAlpha, object, 0)
end
function D.Hide()
    if frame then frame:Hide(); frame:SetScript("OnUpdate", nil); frame:ClearAllPoints() end
    Unveil()
    plate, token = nil, nil
    G.stats.shown = 0
end
local function Animate(_, elapsed)
    if not plate or Safe(plate.IsShown, plate) ~= true or InCombatLockdown() then D.Hide(); return end
    age = age + math.min(elapsed, 0.1)
    local alpha = Safe(plate.GetEffectiveAlpha, plate) or Safe(plate.GetAlpha, plate) or 1
    if type(alpha) ~= "number" then D.Hide(); return end
    frame:SetAlpha(math.max(0, math.min(1, alpha)))
    local reduced = R:Enabled("arrivalReducedMotion")
    for i, star in ipairs(stars) do
        local phase = reduced and 0.5 or (age * 0.5 + i / #stars) % 1
        local strength = math.sin(phase * math.pi)
        star:SetAlpha(0.18 + 0.65 * strength * strength)
        star:SetSize(9 + 8 * strength, 9 + 8 * strength)
    end
end
local onUpdate = Perf.Wrap("gathering.animate", Animate)
local function Build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(90, 65)
    frame:SetFrameStrata("BACKGROUND")
    frame:EnableMouse(false)
    for i = 1, 6 do
        local star = frame:CreateTexture(nil, "OVERLAY")
        star:SetTexture([[Interface\Cooldown\star4]]) -- same native texture as classbars/Effects.lua
        star:SetBlendMode("ADD")
        local angle = i * math.pi / 3
        star:SetPoint("CENTER", frame, "CENTER", math.cos(angle) * 27, math.sin(angle) * 16)
        stars[i] = star
    end
    G.stats.frames = 1
end
function D.Show(anchor, category, locked)
    if Safe(anchor.IsForbidden, anchor) == true or Safe(anchor.IsShown, anchor) ~= true then D.Hide(); return end
    local current = Safe(UnitGUID, "softinteract")
    -- The same plate can be recycled before the next NAME_PLATE_UNIT_REMOVED.
    if plate ~= anchor or token ~= current then D.Hide(); age = 0 end
    if not frame then Build() end
    plate, token, kind = anchor, current, category
    local unitFrame = anchor.UnitFrame
    Veil(unitFrame)
    if unitFrame then Veil(unitFrame.SoftTargetFrame) end -- EllesmereUI can move this outside UnitFrame
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, "CENTER", 0, -40)
    local color = locked and COLORS.locked or COLORS[kind]
    for _, star in ipairs(stars) do star:SetVertexColor(color[1], color[2], color[3]) end
    G.stats.shown = 1
    frame:SetScript("OnUpdate", onUpdate)
    frame:Show()
end
