-- TwichUI settings: Magic Inventory, the arrangement editor's two small pieces (MagicInventoryGuild.lua uses them):
--   P.Drag   a VIRTUAL drag. A small picture follows the pointer while the mouse button is held on an item of the editor,
--            and where the button is let go decides the drop. Nothing real is picked up: the game's cursor is never set,
--            cleared or read for anything but "is the player holding something", no container or guild bank call is made,
--            and a drop on nothing changes nothing.
--   P.Split  the small "Split stack" dialog: a quantity, Split and Cancel. Esc closes it. It only reports the quantity; the
--            editor does the splitting when the player has chosen where the new stack goes, so cancelling at any point leaves
--            the design as it was.

local R = TwichUI
local P = R.MagicInventoryPage
local function Wg() return R.SettingsWidgets end

---------------------------------------------------------------------------
-- The virtual drag
---------------------------------------------------------------------------
local Drag = {}
P.Drag = Drag
local ghost, current

local function Ghost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(28, 28)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:EnableMouse(false)
    ghost.tex = ghost:CreateTexture(nil, "ARTWORK")
    ghost.tex:SetAllPoints()
    ghost.tex:SetAlpha(0.85)
    ghost.count = ghost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    ghost.count:SetPoint("BOTTOMRIGHT", -1, 1)
    -- a drag of something without a picture (a row of the rules table) carries its name instead
    ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.bg:SetAllPoints()
    ghost.bg:SetColorTexture(0.10, 0.08, 0.06, 0.9)
    ghost.label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.label:SetPoint("LEFT", 8, 0)
    ghost:Hide()
    -- only while a drag is on: follow the pointer and tell the editor what is under it (to light up the target)
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        if current and current.hover then current.hover(current.find and current.find() or nil) end
    end)
    return ghost
end

function Drag.Active() return current ~= nil end
function Drag.Source() return current and current.src or nil end

-- def: { src = whatever the editor wants back, icon, count (or label instead: a short text carried in place of a picture), find = function() -> the target under the pointer or nil,
--        hover = function(target) (optional), drop = function(src, target), cancel = function(src) (optional) }
function Drag.Start(def)
    if current then Drag.Cancel() end
    current = def
    local g = Ghost()
    if def.label then
        g.tex:Hide()
        g.count:SetText("")
        g.bg:Show()
        g.label:SetText(def.label)
        g.label:Show()
        g:SetSize(math.min(260, math.max(80, (g.label:GetStringWidth() or 0) + 16)), 24)
    else
        g.tex:Show()
        g.bg:Hide()
        g.label:Hide()
        g:SetSize(28, 28)
        g.tex:SetTexture(def.icon)
        g.count:SetText((def.count and def.count > 1) and def.count or "")
    end
    g:Show()
end

local function End()
    local d = current
    current = nil
    if ghost then ghost:Hide() end
    if d and d.hover then d.hover(nil) end
    return d
end

-- The mouse button was let go: whatever is under the pointer decides.
function Drag.Stop()
    local d = End()
    if not d then return end
    local target = d.find and d.find() or nil
    if target and d.drop then d.drop(d.src, target)
    elseif d.cancel then d.cancel(d.src) end
end

function Drag.Cancel()
    local d = End()
    if d and d.cancel then d.cancel(d.src) end
end

---------------------------------------------------------------------------
-- The split dialog
---------------------------------------------------------------------------
local Split = {}
P.Split = Split
local NAME = "TwichUIMagicInventorySplit"
local dlg, def

local function Qty()
    local n = tonumber(dlg.qty:GetText() or "")
    if n and n == math.floor(n) then return n end
end

local function Check()
    if not def then return false end
    local n = Qty()
    if def.size then
        local ok = n ~= nil and n >= 1 and n <= def.limit
        dlg.hint:SetText(ok and (n >= def.limit and "A full stack." or ("Stacks of %d."):format(n)) or ("Choose a whole number from 1 to %d."):format(def.limit))
        Wg().Color(dlg.hint, ok and Wg().pal.textDim or { 0.93, 0.72, 0.38 })
        dlg.ok:SetEnabled(ok)
        return ok
    end
    local ok = n ~= nil and n >= 1 and n < def.count
    dlg.hint:SetText(ok and ("%d go to the new stack, %d stay."):format(n, def.count - n) or ("Choose a whole number from 1 to %d."):format(def.count - 1))
    Wg().Color(dlg.hint, ok and Wg().pal.textDim or { 0.93, 0.72, 0.38 })
    dlg.ok:SetEnabled(ok)
    return ok
end

local function Confirm()
    if not (def and Check()) then return end
    local qty, done = Qty(), def.onConfirm
    Split.Close()
    if done then done(qty) end
end

local function Build()
    local G = Wg()
    dlg = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    dlg:SetSize(290, 150)
    dlg:SetFrameStrata("FULLSCREEN_DIALOG")
    dlg:SetToplevel(true)
    dlg:SetClampedToScreen(true)
    dlg:EnableMouse(true)
    G.Shell(dlg, 0)
    dlg:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it, as Cancel
    dlg.title = G.Text(dlg, "heading")
    dlg.title:SetPoint("TOPLEFT", 16, -14)
    dlg.title:SetText("Split stack")
    dlg.icon = dlg:CreateTexture(nil, "ARTWORK")
    dlg.icon:SetSize(24, 24)
    dlg.icon:SetPoint("TOPLEFT", 16, -42)
    dlg.item = G.Text(dlg, "body")
    dlg.item:SetPoint("LEFT", dlg.icon, "RIGHT", 8, 0)
    dlg.item:SetWidth(230)
    dlg.item:SetJustifyH("LEFT")
    dlg.qty = G.EditBox(dlg, 70, 22)
    dlg.qty:SetMaxLetters(5)
    dlg.qty:SetPoint("TOPLEFT", 44, -78)
    dlg.minus = G.Button(dlg, "-", 24, "secondary", function()
        local n = Qty() or 1
        dlg.qty:SetText(tostring(math.max(1, n - 1)))
        Check()
    end)
    dlg.minus:SetPoint("RIGHT", dlg.qty, "LEFT", -4, 0)
    dlg.plus = G.Button(dlg, "+", 24, "secondary", function()
        local n = Qty() or 0
        dlg.qty:SetText(tostring(math.min(def and (def.size and def.limit or (def.count - 1)) or n + 1, n + 1)))
        Check()
    end)
    dlg.plus:SetPoint("LEFT", dlg.qty, "RIGHT", 4, 0)
    dlg.hint = G.Text(dlg, "small")
    dlg.hint:SetPoint("LEFT", dlg.plus, "RIGHT", 10, 0)
    dlg.hint:SetWidth(120)
    dlg.hint:SetJustifyH("LEFT")
    dlg.ok = G.Button(dlg, "Split", 100, "primary", Confirm)
    dlg.ok:SetPoint("BOTTOMLEFT", 16, 14)
    dlg.cancel = G.Button(dlg, CANCEL or "Cancel", 100, "secondary", function() Split.Close() end)
    dlg.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    dlg.qty:SetScript("OnTextChanged", function() Check() end)
    dlg.qty:SetScript("OnEnterPressed", Confirm)
    dlg.qty:SetScript("OnEscapePressed", function() Split.Close() end)
    dlg:SetScript("OnHide", function() def = nil end)
end

-- d: { id, name, icon, count (at least 2), anchor (a frame to open under), onConfirm(qty) }
-- or, to choose the size an item is spread in: { size = true, limit (the item's stack limit, at least 2), current, id, name, icon, anchor, onConfirm(n) }
function Split.Open(d)
    if not dlg then Build() end
    if not (d and ((d.size and d.limit and d.limit >= 2) or (d.count and d.count >= 2))) then return false end
    def = d
    dlg.icon:SetTexture(d.icon)
    dlg.title:SetText(d.size and "Stack size" or "Split stack")
    dlg.ok.text:SetText(d.size and "Set size" or "Split")
    dlg.item:SetText(d.size and (d.name or "Item") or ("%s \195\151%d"):format(d.name or "Item", d.count))
    dlg.qty:SetText(tostring(d.size and (d.current or d.limit) or math.max(1, math.floor(d.count / 2))))
    dlg:ClearAllPoints()
    if d.anchor then dlg:SetPoint("TOPLEFT", d.anchor, "BOTTOMLEFT", 0, -6) else dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    dlg:Show()
    dlg:Raise()
    dlg.qty:SetFocus()
    Check()
    return true
end

function Split.Close()
    if dlg and dlg:IsShown() then dlg:Hide() end
    def = nil
end

function Split.IsShown() return dlg ~= nil and dlg:IsShown() end
function Split.Dialog() return dlg end
