-- TwichUI Fishing: catch notifications (Stage 2)
-- A short notice for each confirmed catch (Stage 1's ITEM notification: an item that reached the bags from fishing loot or
-- from a fishing container), left of the middle of the screen so it never covers the bobber or the cast bar. The bronze
-- icon frame and fading band are the texture pack's, with the sample icons cut out (tools/make_fishing_art.py); the icon,
-- name and quantity are the item's own.
--
--   catch      "Caught!" and the item, for what the line brought up
--   treasure   "Treasure!", a warmer frame (toast-treasure) and a gold glint behind the icon, for what came out of a fishing
--              container (clam contents: pearls and the like) and for items the game itself rates rare or better (its item
--              quality). Nothing else is called a treasure: no rarity or value is guessed.
-- The same item again while its notice is still up (several stacks from one catch, or a fast second catch) adds to that
-- notice ("x3") instead of showing another. At most three show at once, newest at the bottom; up to six more wait.
-- Each comes in with a short slide and fade (only the fade with reduced motion), stays config toast.hold seconds, and fades
-- out. The value line is shown only when a valuation is connected (Present.Value, Stage 3).
-- Notice frames are made once (three) and reused; their OnUpdate exists only while one is showing.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local H = F.Hud
local T = {}
F.Toast = T

T.VISIBLE = 3
T.QUEUE = 6
T.MERGE = 2.5        -- seconds after its last update that a notice still takes the same item
T.IN, T.OUT = 0.28, 0.6
local K = 0.72

local anchor
local pool, active, queue = {}, {}, {}
T.shown, T.merged, T.dropped = 0, 0, 0

local function Text(parent, size, role, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    H.Font(fs, size, role)
    H.Color(fs, color or H.IVORY)
    return fs
end

local function Anchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "TwichUIFishingToasts", UIParent)
    anchor:SetSize(H.ART.toast.cw * K, H.ART.toast.ch * K)
    anchor:SetFrameStrata("MEDIUM")
    anchor:EnableMouse(false)
    H.Movable(anchor, "toast", "LEFT")
    H.Place(anchor, "toast", "LEFT")
    return anchor
end

local function Make()
    local f = CreateFrame("Frame", nil, Anchor())
    f:SetSize(H.ART.toast.cw * K, H.ART.toast.ch * K)
    f:EnableMouse(false)
    f:Hide()
    f.glint = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.glint:SetBlendMode("ADD")
    H.Texture(f.glint, "glint", { 1, 0.8, 0.4, 0.2 })
    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.art = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.title = Text(f, 15, "serif", H.GOLD)
    f.name = Text(f, 13, "strong")
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.value = Text(f, 12, "body", H.MUTED)
    pool[#pool + 1] = f
    return f
end

local function Dress(f, kind)
    local art = kind == "treasure" and H.ART.treasure or H.ART.toast
    local name = kind == "treasure" and "treasure" or "toast"
    f:SetSize(art.cw * K, art.ch * K)
    f.art:ClearAllPoints()
    f.art:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.art:SetSize(art.cw * K, art.ch * K)
    H.Texture(f.art, name, { 0.14, 0.09, 0.06, 0.85 })
    local w = art.well
    local side = math.min(w[3] - w[1], w[4] - w[2]) * K
    local cx, cy = (w[1] + w[3]) / 2 * K, (w[2] + w[4]) / 2 * K
    f.icon:ClearAllPoints()
    f.icon:SetPoint("CENTER", f, "TOPLEFT", cx, -cy)
    f.icon:SetSize(side, side)
    f.glint:ClearAllPoints()
    f.glint:SetPoint("BOTTOM", f, "TOPLEFT", cx, -cy + side * 0.05)
    f.glint:SetSize(side * 1.9, side * 0.9)
    f.glint:SetShown(kind == "treasure")
    local x = (w[3] + 20) * K      -- clear of the frame's right rim
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", x, -14 * K - 2)
    f.title:SetText(kind == "treasure" and "Treasure!" or "Caught!")
    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.name:SetWidth(art.cw * K - x - 14)
    f.value:ClearAllPoints()
    f.value:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
end

-- The value line's text, asked of a connected valuation when the catch arrives (never while a notice animates).
local function Value(e)
    local P = F.Present
    return P and P.ValueItem and P.ValueItem(e.id, e.q) or nil
end

local function Words(f)
    local e = f.entry
    local name = e.name or ("Item " .. e.id)
    f.name:SetText(e.q > 1 and (name .. " \195\151" .. e.q) or name)
    local v = e.value
    f.value:SetText(v and ("(Est. " .. v .. ")") or "")
    f.value:SetShown(v ~= nil)
end

local function Motion()
    if S.Get("present.motion") == false then return false end
    return not (R.Enabled and R:Enabled("arrivalReducedMotion"))
end

local function Layout()
    local y = 0
    for i = #active, 1, -1 do
        local f = active[i]
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", Anchor(), "BOTTOMLEFT", f.slide or 0, y)
        y = y + f:GetHeight() + 6
    end
end

local Release

local function OnUpdate(f)
    local now = F.Clock()
    local t = now - f.phaseAt
    if f.phase == "in" then
        local p = math.min(1, t / T.IN)
        local e = p * p * (3 - 2 * p)
        f:SetAlpha(e)
        f.slide = f.moves and (-14 * (1 - e)) or 0
        if f.glint:IsShown() then f.glint:SetAlpha(0.35 + 0.5 * e) end
        if p >= 1 then f.phase, f.phaseAt = "hold", now end
        Layout()
    elseif f.phase == "hold" then
        if f.glint:IsShown() then f.glint:SetAlpha(0.85 - math.min(0.45, t * 0.25)) end
        if t >= f.hold then f.phase, f.phaseAt = "out", now end
    elseif f.phase == "out" then
        local p = math.min(1, t / T.OUT)
        f:SetAlpha(1 - p)
        if p >= 1 then Release(f) end
    end
end

function Release(f)
    f:SetScript("OnUpdate", nil)
    f:Hide()
    f.entry = nil
    for i, g in ipairs(active) do if g == f then table.remove(active, i) break end end
    Layout()
    if #queue > 0 then T.Show(table.remove(queue, 1)) end
end

function T.Show(entry)
    local f
    for _, g in ipairs(pool) do if not g.entry then f = g break end end
    f = f or Make()
    f.entry = entry
    Dress(f, entry.kind)
    f.icon:SetTexture(entry.icon or H.QUESTION)
    Words(f)
    f.hold = S.Get("toast.hold") or 3.5
    f.moves = Motion()
    f.phase, f.phaseAt = "in", F.Clock()
    f.slide = f.moves and -14 or 0
    f:SetAlpha(0)
    active[#active + 1] = f
    Layout()
    Anchor():Show()
    f:Show()
    f:SetScript("OnUpdate", OnUpdate)
    T.shown = T.shown + 1
end

-- A confirmed catch: itemID, quantity, Stage 1's source ("direct" or "content").
function T.Push(itemID, q, source)
    itemID, q = F.Count(itemID), F.Count(q)
    if not (itemID and q and q > 0) then return end
    local name, icon, quality = H.Item(itemID)
    local kind = (source == "content" or (quality and quality >= 3)) and "treasure" or "catch"
    local now = F.Clock()
    for _, f in ipairs(active) do
        local e = f.entry
        if e and e.id == itemID and e.kind == kind and f.phase ~= "out" and now - e.at <= T.MERGE then
            e.q, e.at = e.q + q, now
            e.value = Value(e)
            Words(f)
            if f.phase == "hold" then f.phaseAt = now end
            T.merged = T.merged + 1
            return f
        end
    end
    for _, e in ipairs(queue) do
        if e.id == itemID and e.kind == kind then e.q = e.q + q; e.value = Value(e); T.merged = T.merged + 1 return e end
    end
    local entry = { id = itemID, q = q, kind = kind, name = name, icon = icon, at = now }
    entry.value = Value(entry)
    if #active < T.VISIBLE then
        T.Show(entry)
    else
        queue[#queue + 1] = entry
        while #queue > T.QUEUE do table.remove(queue, 1); T.dropped = T.dropped + 1 end
    end
    return entry
end

-- Everything away at once (Fishing Mode ended, or notifications turned off).
function T.Clear()
    queue = {}
    for i = #active, 1, -1 do
        local f = active[i]
        f:SetScript("OnUpdate", nil)
        f:Hide()
        f.entry = nil
        active[i] = nil
    end
end

function T.Active() return active, queue end
function T.Relayout() if anchor then H.Place(anchor, "toast", "LEFT") end end

-- Move mode: one sample notice to place.
function T.Preview(on)
    local a = Anchor()
    H.SetUnlocked(a, on)
    if on then
        T.Clear()
        T.Show({ id = 0, q = 2, kind = "catch", name = "A catch", icon = H.QUESTION, at = F.Clock() })
        active[1].phase, active[1].hold = "hold", math.huge
        active[1]:SetAlpha(1)
    else
        T.Clear()
    end
end

H.OnItem(function()
    for _, f in ipairs(active) do
        local e = f.entry
        if e and not e.name then e.name, e.icon = H.Item(e.id); f.icon:SetTexture(e.icon or H.QUESTION); Words(f) end
    end
end)
