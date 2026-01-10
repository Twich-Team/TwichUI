---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

---@type ToolsModule|table
local TM = T:GetModule("Tools")

---@class ToolsUI
local UI = TM.UI or {}
TM.UI = UI

local _G = _G
local wipe = wipe
local tinsert = tinsert
local tostring = tostring
local type = type
local tonumber = tonumber

local function SetFontString(fs, size)
    if not fs then return end

    local fontObj = nil
    if size == "small" then
        fontObj = _G.GameFontNormalSmall or _G.GameFontHighlightSmall or _G.GameFontDisableSmall
    else
        fontObj = _G.GameFontNormal or _G.GameFontHighlight or _G.GameFontDisable
    end

    if fontObj and fontObj.GetFont then
        local ok, fontPath, fontSize, fontFlags = pcall(fontObj.GetFont, fontObj)
        if ok and fontPath then
            pcall(fs.SetFont, fs, fontPath, fontSize or 12, fontFlags)
            return
        end
    end

    if fontObj and fs.SetFontObject then
        pcall(fs.SetFontObject, fs, fontObj)
        return
    end

    local fallbackFont = _G["STANDARD_TEXT_FONT"]
    if fallbackFont and fs.SetFont then
        pcall(fs.SetFont, fs, fallbackFont, (size == "small") and 12 or 14, "")
    end
end

local function SafeTrimLower(s)
    if type(s) ~= "string" then return "" end
    s = s:lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

---@class TwichUISearchSelectorCandidate
---@field value number
---@field name string
---@field icon any|nil
---@field desc string|nil
---@field search string|nil
---@field onEnter fun(row:Button, candidate:TwichUISearchSelectorCandidate)|nil
---@field onLeave fun(row:Button, candidate:TwichUISearchSelectorCandidate)|nil

---@class TwichUISearchSelector
---@field Open fun(self:TwichUISearchSelector, params:table)
---@field Close fun(self:TwichUISearchSelector)
---@field IsOpen fun(self:TwichUISearchSelector):boolean

---@param frame Frame
local function GetBorderColor(frame)
    ---@diagnostic disable-next-line: undefined-field
    local E = _G.ElvUI and _G.ElvUI[1]
    if E and E.media and E.media.bordercolor then
        local r, g, b = unpack(E.media.bordercolor)
        return r or 1, g or 1, b or 1, 1
    end
    return 1, 1, 1, 1
end

---@param key string
---@param opts table|nil
---@return TwichUISearchSelector
function UI.CreateSearchSelector(key, opts)
    opts = opts or {}

    local width = tonumber(opts.width) or 420
    local targetHeight = tonumber(opts.height) or 300

    local selector = CreateFrame("Frame", key, _G.UIParent)
    selector:SetWidth(width)
    selector:SetHeight(1)
    -- Strata/level are re-evaluated on open (relative to ElvUI options frame when possible).
    -- Use FULLSCREEN_DIALOG strata to stay above config UIs while avoiding
    -- extremely high frame levels that can break child hit-testing.
    selector:SetFrameStrata("FULLSCREEN_DIALOG")
    selector:SetFrameLevel(500)
    selector:SetClampedToScreen(true)
    -- Enable mouse on the root so clicks on empty selector space don't fall
    -- through to the outside close-catcher. Child widgets (EditBox/rows) remain
    -- interactive.
    selector:EnableMouse(true)
    selector:SetScript("OnMouseDown", function() end)
    if selector.SetToplevel then
        selector:SetToplevel(true)
    end
    selector:Hide()

    -- Backdrop lives on its own low-level child frame so it can't ever overlay
    -- the selector's interactive children (scroll rows, search box, etc.).
    local backdropFrame = CreateFrame("Frame", nil, selector, "BackdropTemplate")
    backdropFrame:SetAllPoints(selector)
    backdropFrame:SetFrameLevel(selector:GetFrameLevel() or 0)
    backdropFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    backdropFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    backdropFrame:SetBackdropBorderColor(0, 0, 0, 1)
    backdropFrame:EnableMouse(false)

    local closeCatcher = CreateFrame("Button", nil, _G.UIParent)
    closeCatcher:SetAllPoints(_G.UIParent)
    closeCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    closeCatcher:SetFrameLevel(499)
    closeCatcher:EnableMouse(true)
    if closeCatcher.SetToplevel then
        closeCatcher:SetToplevel(true)
    end
    closeCatcher:Hide()

    -- NOTE: We intentionally do NOT create a secondary close-catcher parented to
    -- the ElvUI options frame. In practice, that frame can end up above the selector
    -- (depending on effective frame levels/strata), which blocks clicks/focus.

    -- Forward declarations so helper functions can reference these locals.
    local search
    local hint
    local scroll
    local scrollChild
    local rows = {}

    local function ApplyChildStrata()
        local strata = selector:GetFrameStrata() or "TOOLTIP"
        if search and search.SetFrameStrata then
            search:SetFrameStrata(strata)
        end
        if scroll and scroll.SetFrameStrata then
            scroll:SetFrameStrata(strata)
        end
        if scrollChild and scrollChild.SetFrameStrata then
            scrollChild:SetFrameStrata(strata)
        end
        if scroll and scroll.ScrollBar and scroll.ScrollBar.SetFrameStrata then
            scroll.ScrollBar:SetFrameStrata(strata)
        end
        for i = 1, #rows do
            if rows[i] and rows[i].SetFrameStrata then
                rows[i]:SetFrameStrata(strata)
            end
        end
    end

    -- Child frame levels: some UI templates can end up with low default frame levels,
    -- which causes the selector's backdrop to render on top of the list contents.
    local function ApplyChildFrameLevels()
        local base = selector:GetFrameLevel() or 0
        if backdropFrame and backdropFrame.SetFrameLevel then
            backdropFrame:SetFrameLevel(math.max(0, base - 10))
        end
        if search and search.SetFrameLevel then
            search:SetFrameLevel(base + 10)
        end
        if hint and hint.GetParent and hint:GetParent() == selector then
            -- FontString doesn't have SetFrameLevel; it uses its parent's frame.
        end
        if scroll and scroll.SetFrameLevel then
            scroll:SetFrameLevel(base + 10)
        end
        if scrollChild and scrollChild.SetFrameLevel then
            scrollChild:SetFrameLevel(base + 11)
        end
        for i = 1, #rows do
            if rows[i] and rows[i].SetFrameLevel then
                rows[i]:SetFrameLevel(base + 12)
            end
        end
    end

    search = CreateFrame("EditBox", nil, selector, "InputBoxTemplate")
    search:SetSize(math.max(140, width - 160), 20)
    search:SetPoint("TOPLEFT", selector, "TOPLEFT", 10, -10)
    search:SetAutoFocus(false)
    search:SetText("")
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if UI.SkinEditBox then
        UI.SkinEditBox(search)
    end

    ApplyChildStrata()

    hint = selector:CreateFontString(nil, "OVERLAY")
    SetFontString(hint, "small")
    hint:SetPoint("LEFT", search, "RIGHT", 10, 0)
    hint:SetTextColor(0.70, 0.70, 0.70)
    hint:SetText(type(opts.hint) == "string" and opts.hint or "Search")

    scroll = CreateFrame("ScrollFrame", nil, selector, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -2, -10)
    scroll:SetPoint("BOTTOMRIGHT", selector, "BOTTOMRIGHT", -28, 12)
    if UI.SkinScrollBar then
        UI.SkinScrollBar(scroll)
    end

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetPoint("TOPLEFT")
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)

    ApplyChildStrata()

    local candidates = {}
    local filtered = {}
    local selectedValue = nil
    local onSelect = nil

    local function EnsureRow(i)
        if rows[i] then return rows[i] end

        local row = CreateFrame("Button", nil, scrollChild)
        if row.SetFrameStrata then
            row:SetFrameStrata(selector:GetFrameStrata() or "TOOLTIP")
        end
        local baseLevel = selector:GetFrameLevel() or 0
        if row.SetFrameLevel then
            row:SetFrameLevel(baseLevel + 12)
        end
        row:SetHeight(34)
        row:SetPoint("LEFT", scrollChild, "LEFT", 0, 0)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row:EnableMouse(true)

        if i == 1 then
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -4)
        end

        local r, g, b = GetBorderColor(row)

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        base:SetColorTexture(r, g, b, 0.05)
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        hover:SetColorTexture(r, g, b, 0.10)
        hover:Hide()
        row.__twichuiHoverBG = hover

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.name = row:CreateFontString(nil, "OVERLAY")
        SetFontString(row.name, "normal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        row.name:SetJustifyH("LEFT")

        row.desc = row:CreateFontString(nil, "OVERLAY")
        SetFontString(row.desc, "small")
        row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.desc:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetTextColor(0.70, 0.70, 0.70)

        row.selectedText = row:CreateFontString(nil, "OVERLAY")
        SetFontString(row.selectedText, "small")
        row.selectedText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.selectedText:SetTextColor(0.90, 0.90, 0.90)
        row.selectedText:SetText("Selected")
        row.selectedText:Hide()

        row:SetScript("OnEnter", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Show() end
            local cand = self.__twichuiCandidate
            if cand and cand.onEnter then
                pcall(cand.onEnter, self, cand)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Hide() end
            local cand = self.__twichuiCandidate
            if cand and cand.onLeave then
                pcall(cand.onLeave, self, cand)
            end
        end)

        row:SetScript("OnClick", function(self)
            local cand = self.__twichuiCandidate
            if not cand then return end
            selectedValue = cand.value
            if type(onSelect) == "function" then
                pcall(onSelect, cand.value, cand)
            end
            if selector.__twichuiClose then
                selector.__twichuiClose()
            end
        end)

        row:Hide()
        rows[i] = row
        return row
    end

    local function ClearRows()
        for i = 1, #rows do
            rows[i]:Hide()
        end
    end

    local function SetScrollHeight(lastWidget)
        local bottom = lastWidget
        local h = 0
        if bottom and bottom.GetBottom and scrollChild.GetTop then
            local top = scrollChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        scrollChild:SetSize(width - 30, h)
    end

    local animTarget = targetHeight
    local function Animate(open)
        selector.__twichuiOpen = open and true or false
        if open then
            closeCatcher:Show()
            selector:Show()
            -- Keep content fully opaque; only fade the backdrop.
            selector:SetAlpha(1)
            if backdropFrame and backdropFrame.SetAlpha then
                backdropFrame:SetAlpha(0)
            end
            selector:SetHeight(1)
            selector.__twichuiAnim = { from = 1, to = animTarget, t = 0, dur = 0.16 }
        else
            closeCatcher:Hide()
            selector.__twichuiAnim = { from = selector:GetHeight() or animTarget, to = 0, t = 0, dur = 0.12, closing = true }
        end

        selector:SetScript("OnUpdate", function(f, elapsed)
            local a = f.__twichuiAnim
            if not a then
                f:SetScript("OnUpdate", nil)
                return
            end
            a.t = a.t + (elapsed or 0)
            local p = a.dur > 0 and math.min(1, a.t / a.dur) or 1
            local h = (a.from or 0) + ((a.to or 0) - (a.from or 0)) * p
            if h < 1 then h = 1 end
            f:SetHeight(h)
            if backdropFrame and backdropFrame.SetAlpha then
                backdropFrame:SetAlpha(math.max(0, math.min(1, h / animTarget)))
            end
            if p >= 1 then
                f:SetScript("OnUpdate", nil)
                if a.closing then
                    f:SetHeight(1)
                    if backdropFrame and backdropFrame.SetAlpha then
                        backdropFrame:SetAlpha(0)
                    end
                    f:Hide()
                else
                    f:SetHeight(animTarget)
                    if backdropFrame and backdropFrame.SetAlpha then
                        backdropFrame:SetAlpha(1)
                    end
                end
            end
        end)
    end

    local function Close()
        if selector.__twichuiOpen then
            Animate(false)
        end
        if search then
            search:ClearFocus()
        end
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end

    selector.__twichuiClose = Close

    closeCatcher:SetScript("OnMouseDown", function() Close() end)

    search:SetScript("OnEscapePressed", function()
        if selector.__twichuiOpen then
            Close()
        else
            search:ClearFocus()
        end
    end)

    local function RebuildFiltered()
        local q = SafeTrimLower(search:GetText() or "")
        wipe(filtered)

        if #candidates == 0 then
            return
        end

        if q == "" then
            for i = 1, #candidates do
                filtered[i] = candidates[i]
            end
            return
        end

        for i = 1, #candidates do
            local c = candidates[i]
            local blob = SafeTrimLower(c.search or c.name or "")
            if blob ~= "" and blob:find(q, 1, true) then
                tinsert(filtered, c)
            end
        end
    end

    local function Render()
        ClearRows()
        RebuildFiltered()

        local last = nil
        for i = 1, #filtered do
            local c = filtered[i]
            local row = EnsureRow(i)
            row.__twichuiCandidate = c

            if c.icon then
                row.icon:SetTexture(c.icon)
                row.icon:Show()
            else
                row.icon:SetTexture(nil)
                row.icon:Hide()
            end

            row.name:SetText(tostring(c.name or ""))
            if type(c.desc) == "string" and c.desc ~= "" then
                row.desc:SetText(c.desc)
                row.desc:Show()
            else
                row.desc:SetText("")
                row.desc:Hide()
            end

            if selectedValue ~= nil and tonumber(c.value) == tonumber(selectedValue) then
                row.selectedText:Show()
            else
                row.selectedText:Hide()
            end

            row:Show()
            last = row
        end

        SetScrollHeight(last)
    end

    search:SetScript("OnTextChanged", function()
        Render()
    end)

    local api = {}

    function api:IsOpen()
        return selector.__twichuiOpen and true or false
    end

    function api:Close()
        Close()
    end

    ---@param params table
    --- params.candidates TwichUISearchSelectorCandidate[]
    --- params.selectedValue number|nil
    --- params.onSelect fun(value:number, candidate:TwichUISearchSelectorCandidate)|nil
    --- params.title string|nil
    --- params.point string|nil
    --- params.relativeTo Frame|nil
    --- params.relativePoint string|nil
    --- params.x number|nil
    --- params.y number|nil
    function api:Open(params)
        params = params or {}

        candidates = params.candidates or {}
        selectedValue = params.selectedValue
        onSelect = params.onSelect

        -- Prefer to compute a base level from ElvUI's actual options frame when available.
        ---@diagnostic disable-next-line: undefined-field
        local E = _G.ElvUI and _G.ElvUI[1]
        local optionsFrame = (params and params.relativeTo)
        if not optionsFrame and E and type(E) == "table" then
            optionsFrame = E.OptionsUI or E.OptionsFrame
        end
        if not optionsFrame then
            local ACD = _G.LibStub and (
                _G.LibStub("AceConfigDialog-3.0-ElvUI", true)
                or _G.LibStub("AceConfigDialog-3.0", true)
            )
            if ACD and type(ACD.OpenFrames) == "table" then
                local of = ACD.OpenFrames.ElvUI
                if type(of) == "table" then
                    optionsFrame = of.frame or of
                end
            end
        end

        local base = 0
        if optionsFrame and type(optionsFrame) == "table" and optionsFrame.GetFrameLevel then
            base = optionsFrame:GetFrameLevel() or 0
        end

        -- Keep levels reasonable; fallback to 500 if we can't determine a base.
        local selectorLevel = (base > 0) and (base + 500) or 500
        selector:SetFrameStrata("FULLSCREEN_DIALOG")
        selector:SetFrameLevel(selectorLevel)
        closeCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        -- Always keep the close catcher *below* the selector, so clicks inside the selector
        -- can't accidentally dismiss it due to frame-level edge cases.
        closeCatcher:SetFrameLevel(math.max(0, selectorLevel - 1))

        -- Some Blizzard templates can override strata on creation; re-apply to keep
        -- interactive children on the same strata as the selector.
        ApplyChildStrata()

        -- Ensure backdrop is below all interactive children even after re-leveling.
        if backdropFrame and backdropFrame.SetFrameLevel then
            backdropFrame:SetFrameLevel(math.max(0, (selector:GetFrameLevel() or 0) - 10))
        end

        ApplyChildFrameLevels()

        animTarget = tonumber(params.height) or targetHeight
        if animTarget < 160 then animTarget = 160 end

        selector:ClearAllPoints()
        selector:SetPoint(
            params.point or "CENTER",
            params.relativeTo or _G.UIParent,
            params.relativePoint or params.point or "CENTER",
            tonumber(params.x) or 0,
            tonumber(params.y) or 0
        )

        hint:SetText(type(params.title) == "string" and params.title or
            (type(opts.hint) == "string" and opts.hint or "Search"))

        search:SetText("")
        Render()

        Animate(true)
    end

    return api
end

return UI
