-- TwichUI: Mage refreshments panel
-- A small window for preparing and handing out conjured food and water (modules/Refreshments.lua does the
-- sums). Opened with /tui refreshments, its key binding, the Mage Conjuring menu or the Mage options page;
-- it never opens by itself.
--   Prepare: a Water and a Food button, each the game's own secure button. A click, or its key (Key
--   Bindings > TwichUI), casts the rank the plan still needs once; TwichUI never casts by itself. They act
--   on the release, so dragging one never casts it: dragging puts the spell on the cursor to drop on an
--   action bar, where the game's Press and Hold Casting can repeat it. Nothing stops a held cast at the
--   target: the bar turns green and one line says "enough", and letting go is the player's.
--   Group: everyone in the party or raid with what their share asks for and what has been marked as
--   handed over this session. Click a row to select it, then correct it below; the first person not yet
--   supplied is marked. TwichUI never trades for the player; marking is by hand.
-- The buttons' spell is set out of combat only, and kept when the panel is shut so their keys work. The
-- panel holds those secure buttons, so it can't be opened in combat and closes as combat starts.

local R = TwichUI
local RF = R.Refreshments
local SM = R.SpellMenu
local S = R.ChronicleStyle
local K = S.color
local Tip = function(...) return R.Interact.Tip(...) end
local P = {}
R.RefreshmentsPanel = P

-- The panel's look, the player's to set on the Mage options page (the trade strip shares it). Its own
-- saved settings, TwichUIDB.ui.refreshmentsStyle; the defaults are the Chronicle's umber with a bronze line.
P.Style = R.MenuStyle.New("refreshmentsStyle", {
    bgTexture = "solid", bgColor = "ff261d15", bgOpacity = 98,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
})

local NAME = "TwichUIRefreshments"
local BUTTON_NAME = { water = "TwichUIRefreshmentsWater", food = "TwichUIRefreshmentsFood" }
local WIDTH, HEIGHT = 380, 548
local PAD = 16
local ROW_H, VISIBLE_ROWS = 22, 9
local BAR_W = WIDTH - PAD * 2 - 48
local RECENT = 10          -- seconds: a kind reaching its target this soon after a conjure says so once
local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
local FONT_HEADER = R.PATH .. [[media\fonts\AlegreyaSansSC-Bold.ttf]]
local FONT_ROW = R.PATH .. [[media\fonts\AlegreyaSans-Medium.ttf]]
local FONT_NOTE = R.PATH .. [[media\fonts\AlegreyaSans-Regular.ttf]]
local GREEN = { 0.56, 0.70, 0.35 }

-- The key bindings in Bindings.xml, by the names the game's Key Bindings list shows.
BINDING_HEADER_TWICHUI = "TwichUI"
_G["BINDING_NAME_TWICHUI_REFRESHMENTS"] = "Mage refreshments panel"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME.water .. ":LeftButton"] = "Conjure water (Mage refreshments)"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME.food .. ":LeftButton"] = "Conjure food (Mage refreshments)"

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- A short local message where the game shows its own; never chat.
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

local function Text(parent, path, size, fallback)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if R.Arrival and R.Arrival.SetFont then R.Arrival.SetFont(fs, path, size, fallback)
    else fs:SetFontObject(fallback) end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and class and names[class]) or (class and (class:sub(1, 1) .. class:sub(2):lower())) or "Unknown class"
end

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return K.text
end

local function RankLabel(kind, rank)
    local spell = RF.SpellFor(kind, rank)
    local name = SM.Spell(spell)
    return (name or ("Conjure " .. RF.KIND_LABEL[kind])) .. " (" .. (SM.RankText(spell, rank) or ("Rank " .. rank)) .. ")"
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local panel, blocks, list, rows, strip, footer
local conjure = {}           -- [kind] = the secure button
local selected               -- the GUID of the selected row
local dirty = false          -- a change came in combat: the buttons' spell waits for it to end
local restyle = false        -- the look changed in combat: the panel is redrawn when it ends
local closeAfterCombat = false
local wasShort = {}          -- [kind] = the plan was still short at the last look
local active = {}            -- [event] = handler, while registered

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

---------------------------------------------------------------------------
-- The secure buttons. Their attributes, and the icon and label that show them, change together, out of
-- combat only.
---------------------------------------------------------------------------
local function FillButton(b, spell)
    b:SetAttribute("type", spell and "spell" or nil)
    b:SetAttribute("spell", spell)
    b.spell = spell
    local icon
    if spell then icon = select(2, SM.Spell(spell)) end
    b.icon:SetTexture(icon or 134400)   -- the question-mark icon when there is none
    b.icon:SetDesaturated(not spell)
end

-- The spell each button should hold now: the plan's choice, or nothing while the feature is off.
local function Wanted(kind)
    if not RF.Enabled() then return nil end
    return (RF.ConjureChoice(kind, RF.Plan()))
end

local Ensure, Restyle   -- below

local function OnRegenEnabled()
    if closeAfterCombat and panel and panel:IsShown() then panel:Hide() end
    closeAfterCombat = false
    Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, false)
    if dirty then
        if panel then P.UpdateButtons() else Ensure() end
    end
    if restyle then Restyle() end
end

function P.UpdateButtons()
    if not conjure.water then return end
    if InCombat() then
        dirty = true
        R.Life.Note("deferred-combat")
        Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, true)
        return
    end
    dirty = false
    for _, kind in ipairs(RF.KINDS) do FillButton(conjure[kind], Wanted(kind)) end
end

local function ShowConjureTip(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if b.spell and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(b.spell)
    else
        GameTooltip:SetText("Conjure " .. RF.KIND_LABEL[b.kind], 1, 1, 1)
        GameTooltip:AddLine("You haven't learned Conjure " .. RF.KIND_LABEL[b.kind] .. " yet. Mage trainers teach it.", K.stone[1], K.stone[2], K.stone[3], true)
    end
    if b.spell then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to conjure once.", K.gold[1], K.gold[2], K.gold[3])
        local key = GetBindingKey and GetBindingKey("CLICK " .. BUTTON_NAME[b.kind] .. ":LeftButton")
        if key then
            GameTooltip:AddLine(("%s does the same, once per press."):format(GetBindingText and GetBindingText(key) or key), K.textDim[1], K.textDim[2], K.textDim[3], true)
        else
            GameTooltip:AddLine("Give it a key in Key Bindings > TwichUI.", K.textDim[1], K.textDim[2], K.textDim[3], true)
        end
        GameTooltip:AddLine("To conjure while holding a key, drag this to one of your action bars and turn on the game's Press and Hold Casting (Options > Combat). The game doesn't repeat a held cast from an addon's button. Let go when the bar turns green.", K.stone[1], K.stone[2], K.stone[3], true)
    end
    GameTooltip:Show()
end

local function NewConjureButton(parent, kind)
    local b = CreateFrame("Button", BUTTON_NAME[kind], parent, "SecureActionButtonTemplate")
    b.kind = kind
    b:SetSize(36, 36)
    -- On the release only, whatever the game's "cast on key down" setting: a drag never casts, and the
    -- key bound to it casts as its key comes up.
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForDrag("LeftButton")
    local rim = Solid(b, "BACKGROUND", K.bronze, 0.9)
    rim:SetAllPoints()
    local well = Solid(b, "BORDER", K.well)
    well:SetPoint("TOPLEFT", 1, -1)
    well:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hot = Solid(b, "HIGHLIGHT", K.gold, 0.18)
    hot:SetAllPoints()
    b:SetScript("OnDragStart", function(self)
        if InCombat() or not self.spell then return end
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(self.spell) end
    end)
    b:SetScript("OnEnter", ShowConjureTip)
    b:SetScript("OnLeave", function(self) R.Interact.HideTip(self) end)
    b:HookScript("OnHide", function(self) R.Interact.HideTip(self) end)
    return b
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Position()
    local saved = TwichUIDB and TwichUIDB.ui and type(TwichUIDB.ui.refreshments) == "table" and TwichUIDB.ui.refreshments.position
    local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return 0, 60
end

local function Place()
    local x, y = Position()
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function SavePosition()
    local cx, cy = panel:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (cx and cy and px and py) then return end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.refreshments) ~= "table" then TwichUIDB.ui.refreshments = {} end
    TwichUIDB.ui.refreshments.position = { x = math.floor(cx - px + 0.5), y = math.floor(cy - py + 0.5) }
end

local function BlockTip(block)
    local plan = RF.Plan()
    local kind = block.kind
    local lines = plan and plan.items[kind] or {}
    local out = {}
    for _, line in ipairs(lines) do
        local parts = {}
        if line.group > 0 then parts[#parts + 1] = ("%d for %d %s"):format(line.group, line.recipients, line.recipients == 1 and "person" or "people") end
        if line.reserve > 0 then parts[#parts + 1] = ("%d to keep"):format(line.reserve) end
        out[#out + 1] = ("%s: %d of %d (%s)"):format(RankLabel(kind, line.rank), math.min(line.have, line.need), line.need, table.concat(parts, ", "))
    end
    if #out == 0 then out[1] = "Nothing planned for " .. RF.KIND_LABEL[kind]:lower() .. "." end
    out[#out + 1] = "\nCounts are single items in your bags. What anyone else carries can't be seen, so it isn't counted."
    return table.concat(out, "\n")
end

local function NewBlock(parent, kind, y)
    local block = CreateFrame("Frame", nil, parent)
    block.kind = kind
    block:SetSize(WIDTH - PAD * 2, 56)
    block:SetPoint("TOPLEFT", PAD, y)
    conjure[kind] = NewConjureButton(parent, kind)
    conjure[kind]:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -2)
    block.name = Text(block, FONT_ROW, 14, "GameFontNormal")
    block.name:SetPoint("TOPLEFT", 48, -2)
    block.name:SetPoint("RIGHT", -70, 0)
    Color(block.name, K.text)
    block.count = Text(block, FONT_ROW, 14, "GameFontNormal")
    block.count:SetPoint("TOPRIGHT", 0, -2)
    block.count:SetJustifyH("RIGHT")
    Color(block.count, K.textDim)
    local track = Solid(block, "ARTWORK", K.well)
    track:SetSize(BAR_W, 6)
    track:SetPoint("TOPLEFT", 48, -22)
    local edge = Solid(block, "BORDER", K.bronzeLo)
    edge:SetPoint("TOPLEFT", track, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 1, -1)
    block.fill = Solid(block, "OVERLAY", K.gold, 0.9)
    block.fill:SetHeight(6)
    block.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    block.detail = Text(block, FONT_NOTE, 12, "GameFontNormalSmall")
    block.detail:SetPoint("TOPLEFT", 48, -33)
    block.detail:SetPoint("RIGHT", 0, 0)
    -- The breakdown by rank, on the text (the secure button's own tooltip is the spell's).
    local hover = CreateFrame("Frame", nil, block)
    hover:SetPoint("TOPLEFT", 48, 0)
    hover:SetPoint("BOTTOMRIGHT", 0, 0)
    hover:EnableMouse(true)
    Tip(hover, RF.KIND_LABEL[kind], function() return BlockTip(block) end)
    return block
end

local Render   -- below

local function Select(guid)
    selected = guid
    Render()
end

local STATUS = {
    supplied = { "Supplied", GREEN }, partial = { "Partial", K.gold },
    pending = { "Not yet", K.textDim }, nothing = { "No share", K.stone },
}
local OFFERED = { "Offered?", K.emberHi }   -- a trade TwichUI couldn't confirm, waiting for the player

local function Counts(row)
    local parts = {}
    for _, kind in ipairs(RF.KINDS) do
        if row.want[kind] > 0 then
            parts[#parts + 1] = ("%s %d/%d%s"):format(kind == "water" and "W" or "F", row.given[kind], row.want[kind], row.noRank[kind] and "?" or "")
        end
    end
    return table.concat(parts, "  ")
end

local function RowTip(r)
    local row = r.row
    if not row then return nil end
    local lines = { row.name or "Unknown", (row.level and ("Level " .. row.level .. " ") or "") .. ClassName(row.class) }
    if not row.class then lines[#lines + 1] = "Their class couldn't be read, so they have no share yet." end
    if not row.level then lines[#lines + 1] = "Their level couldn't be read, so your best rank is planned." end
    if not row.connected then lines[#lines + 1] = "Offline." end
    for _, kind in ipairs(RF.KINDS) do
        if row.want[kind] > 0 then
            local what = row.rank[kind] and RankLabel(kind, row.rank[kind]) or (row.noRank[kind] and "no rank you know that they can use" or "")
            lines[#lines + 1] = ("%s: %d of %d handed over%s"):format(RF.KIND_LABEL[kind], row.given[kind], row.want[kind],
                (row.remaining[kind] > 0 and what ~= "") and (" (" .. what .. ")") or "")
        end
    end
    local offered = RF.Unconfirmed(row.guid)
    if offered then
        lines[#lines + 1] = ("Offered %d water and %d food in a trade TwichUI couldn't confirm. Select them to confirm or dismiss it."):format(offered.water, offered.food)
    end
    lines[#lines + 1] = "\nClick to select, then mark or correct it below."
    return table.concat(lines, "\n")
end

local function NewRow(content, i)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    r.sel = Solid(r, "BACKGROUND", K.band, 0.9)
    r.sel:SetAllPoints()
    r.mark = Solid(r, "ARTWORK", K.gold, 0.95)   -- the next person to supply
    r.mark:SetSize(2, ROW_H - 6)
    r.mark:SetPoint("LEFT", 2, 0)
    local hot = Solid(r, "HIGHLIGHT", K.gold, 0.08)
    hot:SetAllPoints()
    r.status = Text(r, FONT_NOTE, 12, "GameFontNormalSmall")
    r.status:SetPoint("RIGHT", -6, 0)
    r.status:SetJustifyH("RIGHT")
    r.status:SetWidth(58)
    r.counts = Text(r, FONT_NOTE, 12, "GameFontNormalSmall")
    r.counts:SetPoint("RIGHT", r.status, "LEFT", -6, 0)
    r.counts:SetJustifyH("RIGHT")
    r.counts:SetWidth(120)
    Color(r.counts, K.textDim)
    r.name = Text(r, FONT_ROW, 13, "GameFontNormal")
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetPoint("RIGHT", r.counts, "LEFT", -6, 0)
    r:SetScript("OnClick", function(self) if self.row then Select(self.row.guid) end end)
    Tip(r, nil, RowTip)
    return r
end

local function BuildStrip(parent)
    strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(WIDTH - PAD * 2, 54)
    strip.name = Text(strip, FONT_ROW, 13, "GameFontNormal")
    strip.name:SetPoint("TOPLEFT", 2, -4)
    strip.name:SetPoint("RIGHT", -140, 0)
    -- With a trade TwichUI couldn't confirm waiting for them, these two confirm or dismiss it instead.
    strip.supplied = S.Button(strip, "Supplied", 70, "primary", function()
        if not selected then return end
        if RF.Unconfirmed(selected) then RF.ConfirmOffered(selected) else RF.MarkSupplied(selected) end
    end)
    strip.supplied:SetPoint("TOPRIGHT", -62, 0)
    Tip(strip.supplied, nil, function()
        if selected and RF.Unconfirmed(selected) then return "Confirm: the trade went through, so what was offered counts as handed over." end
        return "Supplied: marks everything their share asks for as handed over."
    end)
    strip.clear = S.Button(strip, "Clear", 56, "secondary", function()
        if not selected then return end
        if RF.Unconfirmed(selected) then RF.DismissOffered(selected) else RF.ClearGiven(selected) end
    end)
    strip.clear:SetPoint("TOPRIGHT", 0, 0)
    Tip(strip.clear, nil, function()
        if selected and RF.Unconfirmed(selected) then return "Dismiss: the trade didn't go through; what was offered isn't counted." end
        return "Clear: marks nothing handed over to them this session."
    end)
    strip.kinds = {}
    for i, kind in ipairs(RF.KINDS) do
        local k = CreateFrame("Frame", nil, strip)
        k:SetSize((WIDTH - PAD * 2) / 2, 24)
        k:SetPoint("TOPLEFT", (i - 1) * (WIDTH - PAD * 2) / 2, -28)
        k.label = Text(k, FONT_NOTE, 12, "GameFontNormalSmall")
        k.label:SetPoint("LEFT", 2, 0)
        k.label:SetText(RF.KIND_LABEL[kind])
        Color(k.label, K.textDim)
        k.minus = S.Button(k, "-", 22, "secondary", function()
            if selected then RF.Adjust(selected, kind, -(k.step or 20)) end
        end)
        k.minus:SetPoint("LEFT", 40, 0)
        k.value = Text(k, FONT_ROW, 13, "GameFontNormal")
        k.value:SetPoint("LEFT", k.minus, "RIGHT", 4, 0)
        k.value:SetWidth(62)
        k.value:SetJustifyH("CENTER")
        k.plus = S.Button(k, "+", 22, "secondary", function()
            if selected then RF.Adjust(selected, kind, k.step or 20) end
        end)
        k.plus:SetPoint("LEFT", k.value, "RIGHT", 4, 0)
        Tip(k.minus, "Fewer " .. RF.KIND_LABEL[kind]:lower(), function() return ("Takes %d off what they were handed."):format(k.step or 20) end)
        Tip(k.plus, "More " .. RF.KIND_LABEL[kind]:lower(), function() return ("Adds %d to what they were handed."):format(k.step or 20) end)
        strip.kinds[kind] = k
    end
    strip.empty = Text(strip, FONT_NOTE, 12, "GameFontNormalSmall")
    strip.empty:SetPoint("TOPLEFT", 2, -4)
    strip.empty:SetText("Select someone in the list to mark what you handed them.")
    Color(strip.empty, K.stone)
end

local function Build()
    if panel then return end
    panel = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    panel:Hide()
    panel:HookScript("OnShow", R.FitToScreen)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it
    -- The look (background and border) is the player's, drawn on the outer frame; everything else sits in
    -- a frame of fixed size inside it, which the outer frame grows round as the border thickens.
    local body = CreateFrame("Frame", nil, panel)
    body:SetSize(WIDTH, HEIGHT)
    body:SetPoint("CENTER")
    panel.body = body
    S.Header(body, 34)
    local title = Text(body, FONT_TITLE, 14, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -13)
    title:SetText("Refreshments")
    Color(title, K.text)
    local close = S.Close(body, function() P.Close() end)
    close:SetPoint("TOPRIGHT", -9, -9)

    panel.context = Text(body, FONT_NOTE, 12, "GameFontNormalSmall")
    panel.context:SetPoint("TOPLEFT", PAD + 2, -48)
    panel.context:SetPoint("RIGHT", -80, 0)
    Color(panel.context, K.textDim)
    local shares = S.Link(body, "Shares", function()
        if InCombat() then return end
        P.Close()
        if R.RefreshmentShares then R.RefreshmentShares.Show() end
    end, K.gold, K.text)
    shares:SetPoint("TOPRIGHT", -PAD - 2, -47)
    Tip(shares, "Shares", "How much each class gets in a party and in a raid, and how much you keep. Opens the Mage options.")

    blocks = { water = NewBlock(body, "water", -68), food = NewBlock(body, "food", -128) }
    local hint = Text(body, FONT_NOTE, 11, "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", PAD + 2, -188)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetText("Each press conjures once. To hold a key instead, drag an icon to an action bar.")
    Color(hint, K.stone)

    local header = Text(body, FONT_HEADER, 13, "GameFontNormal")
    header:SetPoint("TOPLEFT", PAD + 2, -212)
    header:SetText("Group")
    Color(header, K.gold)
    panel.summary = Text(body, FONT_NOTE, 12, "GameFontNormalSmall")
    panel.summary:SetPoint("TOPRIGHT", -PAD - 2, -213)
    panel.summary:SetJustifyH("RIGHT")
    Color(panel.summary, K.textDim)

    local listH = VISIBLE_ROWS * ROW_H + 8
    list = CreateFrame("Frame", nil, body, "BackdropTemplate")
    list:SetSize(WIDTH - PAD * 2, listH)
    list:SetPoint("TOPLEFT", PAD, -232)
    S.Well(list, WIDTH - PAD * 2, listH)
    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    S.ScrollBar(scroll)
    list.content = CreateFrame("Frame", nil, scroll)
    list.content:SetSize(WIDTH - PAD * 2 - 28, ROW_H)
    scroll:SetScrollChild(list.content)
    list.empty = Text(list, FONT_NOTE, 12, "GameFontNormalSmall")
    list.empty:SetPoint("TOPLEFT", 10, -10)
    list.empty:SetPoint("RIGHT", -10, 0)
    list.empty:SetWordWrap(true)
    Color(list.empty, K.stone)
    rows = {}

    BuildStrip(body)
    strip:SetPoint("TOPLEFT", PAD, -232 - listH - 8)

    footer = {}
    footer.reset = S.Button(body, "Reset session", 110, "secondary", function()
        R.Interact.Confirm("TWICHUI_REFRESHMENTS_RESET",
            "Forget what you've marked as handed out this session? Your shares stay as they are.",
            function() RF.ResetSession("manual") end)
    end)
    footer.reset:SetPoint("BOTTOMLEFT", PAD, 14)
    Tip(footer.reset, "Reset session", "Starts the checklist again: everyone is owed their whole share. Leaving the group or reloading does the same.")
    footer.next = S.Link(body, "", function() if footer.nextGuid then Select(footer.nextGuid) end end, K.gold, K.text)
    footer.next:SetSize(180, 14)
    footer.next:SetPoint("BOTTOMRIGHT", -PAD - 2, 19)
    Tip(footer.next, "Next", "The first person in the group not yet supplied. Click to select them.")

    panel:SetScript("OnHide", function()
        closeAfterCombat = false
        P.Listen(false)
    end)
end

-- Draws the player's look and grows the panel round its content to clear the border. Out of combat
-- only: the panel holds secure buttons, so it can't be resized in combat.
function Restyle()
    if not panel then return end
    if InCombat() then
        restyle = true
        Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, true)
        return
    end
    restyle = false
    local edge = math.ceil(P.Style.Apply(panel))
    panel:SetSize(WIDTH + edge * 2, HEIGHT + edge * 2)
end
P.Restyle = Restyle

-- The buttons exist (for their keys) whenever the feature is on, even before the panel first opens.
-- Out of combat only: they are secure. Turned on in combat (a reload mid-fight), they wait for it to end.
function Ensure()
    if panel or not RF.Enabled() then return end
    if InCombat() then
        dirty = true
        Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, true)
        return
    end
    Build()
    Restyle()
    P.UpdateButtons()
end

---------------------------------------------------------------------------
-- Drawing (out of combat, while shown)
---------------------------------------------------------------------------
local function DrawBlock(block, plan)
    local kind = block.kind
    local b = conjure[kind]
    local total = plan.totals[kind]
    if b.spell then
        block.name:SetText(RankLabel(kind, RF.SpellIndex(b.spell) or 1))
    else
        block.name:SetText("Conjure " .. RF.KIND_LABEL[kind])
    end
    local short, need = total.short, total.need
    block.count:SetText(need > 0 and ("%d / %d"):format(total.covered, need) or "")
    local share = need > 0 and math.min(1, total.covered / need) or 0
    block.fill:SetWidth(math.max(1, BAR_W * share))
    block.fill:SetShown(share > 0)
    local c = (need > 0 and short == 0) and GREEN or K.gold
    block.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
    local detail, tone
    if not b.spell then
        detail, tone = "Not learned yet. Mage trainers teach Conjure " .. RF.KIND_LABEL[kind] .. ".", K.stone
    elseif need == 0 then
        detail, tone = "Nothing planned. Shares and what you keep are on the Mage options page.", K.stone
    elseif short == 0 then
        detail, tone = "Enough prepared.", GREEN
    else
        local parts = { ("Conjure %d more"):format(short) }
        local line = plan.items[kind][1]
        for _, l in ipairs(plan.items[kind]) do if l.short > 0 then line = l break end end
        local y = line and RF.Yield(line.spell)
        if y then parts[#parts + 1] = ("about %d %s of %d"):format(math.ceil(line.short / y), math.ceil(line.short / y) == 1 and "cast" or "casts", y) end
        local room = line and RF.Room(line.item)
        if room and room < line.short then parts[#parts + 1] = ("bags hold only %d more"):format(room) end
        detail, tone = table.concat(parts, " · "), K.textDim
    end
    block.detail:SetText(detail)
    Color(block.detail, tone)
end

local CONTEXT_TEXT = {
    party = "Party of %d: party shares",
    raid = "Raid of %d: raid shares",
}

function Render()
    if not (panel and panel:IsShown()) or InCombat() then return end
    local plan = RF.Plan()
    if not plan then return end
    local context = plan.context
    if context == "solo" then
        panel.context:SetText("Not in a group: only what you keep for yourself")
    else
        panel.context:SetText(CONTEXT_TEXT[context]:format(#plan.rows + RF.Unreadable() + 1))
    end
    for _, kind in ipairs(RF.KINDS) do DrawBlock(blocks[kind], plan) end

    local found = false
    for i, row in ipairs(plan.rows) do
        local r = rows[i] or NewRow(list.content, i)
        rows[i] = r
        r.row = row
        r.name:SetText(row.name or "Unknown")
        Color(r.name, row.connected and ClassColor(row.class) or K.stone)
        r.counts:SetText(Counts(row))
        local st = RF.Unconfirmed(row.guid) and OFFERED or STATUS[row.status]
        r.status:SetText(row.connected and st[1] or "Offline")
        Color(r.status, row.connected and st[2] or K.stone)
        r.mark:SetShown(row.guid == plan.next)
        r.sel:SetShown(row.guid == selected)
        if row.guid == selected then found = true end
        r:Show()
        R.Interact.RefreshTip(r)
    end
    for i = #plan.rows + 1, #rows do
        rows[i].row = nil
        rows[i]:Hide()
    end
    list.content:SetHeight(math.max(ROW_H, #plan.rows * ROW_H))
    list.empty:SetShown(#plan.rows == 0)
    list.empty:SetText(context == "solo" and "Join a party or raid to see who to supply."
        or (RF.Unreadable() > 0 and "Reading your group..." or "No one else in your group."))
    if not found then selected = nil end

    local c = plan.counts
    local owed = c.supplied + c.partial + c.pending
    local summary = owed > 0 and ("%d of %d supplied"):format(c.supplied, owed) or ""
    if RF.Unreadable() > 0 then summary = summary .. (summary ~= "" and " · " or "") .. ("%d not read yet"):format(RF.Unreadable()) end
    panel.summary:SetText(summary)

    local sel
    for _, row in ipairs(plan.rows) do if row.guid == selected then sel = row end end
    strip.empty:SetShown(not sel)
    strip.name:SetShown(sel ~= nil)
    strip.supplied:SetShown(sel ~= nil)
    strip.clear:SetShown(sel ~= nil)
    for _, kind in ipairs(RF.KINDS) do
        local k = strip.kinds[kind]
        k:SetShown(sel ~= nil)
        if sel then
            k.value:SetText(("%d / %d"):format(sel.given[kind], sel.want[kind]))
            local rank = sel.rank[kind] or RF.RankFor(RF.KnownRanks(kind), sel.level)
            k.step = rank and RF.StackSize(RF.ITEMS[kind][rank]) or 20
            k.minus:SetEnabled(sel.given[kind] > 0)
        end
    end
    if sel then
        local offered = RF.Unconfirmed(sel.guid)
        local parts = {}
        for _, kind in ipairs(RF.KINDS) do
            if offered and offered[kind] > 0 then parts[#parts + 1] = ("%d %s"):format(offered[kind], kind) end
        end
        strip.name:SetText((sel.name or "Unknown") .. (offered and (": offered " .. table.concat(parts, " and ") .. "?") or ""))
        Color(strip.name, offered and K.emberHi or ClassColor(sel.class))
        strip.supplied.text:SetText(offered and "Confirm" or "Supplied")
        strip.clear.text:SetText(offered and "Dismiss" or "Clear")
        R.Interact.RefreshTip(strip.supplied)
        R.Interact.RefreshTip(strip.clear)
    end

    footer.nextGuid = plan.next
    local nextRow
    for _, row in ipairs(plan.rows) do if row.guid == plan.next then nextRow = row end end
    footer.next.text:SetText(nextRow and ("Next: " .. (nextRow.name or "Unknown")) or "")
    footer.next:SetShown(nextRow ~= nil)
end

---------------------------------------------------------------------------
-- Opening and closing, by the player only
---------------------------------------------------------------------------
function P.IsOpen() return panel ~= nil and panel:IsShown() end

local function OnCombatStart() P.Close() end   -- the last moment the panel can be hidden

local function OnScale() if P.IsOpen() then Restyle() end end   -- a border is a whole number of screen pixels

function P.Listen(on)
    Want("PLAYER_REGEN_DISABLED", OnCombatStart, on)
    Want("UI_SCALE_CHANGED", OnScale, on)
    Want("DISPLAY_SIZE_CHANGED", OnScale, on)
end

-- A look changed in the options: an open panel follows at once; a shut one is drawn when it opens.
P.Style.Subscribe(function() if P.IsOpen() then Restyle() end end)

function P.Open()
    if not RF.ForPlayer() then
        R.Print("Mage refreshments are for Mages; this character can't conjure food or water.")
        return false
    end
    if not R:Enabled("mageRefreshments") then
        R.Print("Mage refreshments are turned off. Turn them on on the Mage page of /tui options.")
        return false
    end
    if InCombat() then Notice("Refreshments can't be opened in combat.") return false end
    Ensure()
    Restyle()
    Place()
    panel:Show()
    P.Listen(true)
    Render()
    return true
end

-- Closes the panel, unless combat has already begun; then it closes as combat ends.
function P.Close()
    if not P.IsOpen() then return true end
    if InCombat() then
        closeAfterCombat = true
        Want("PLAYER_REGEN_ENABLED", OnRegenEnabled, true)
        return false
    end
    panel:Hide()
    return true
end

function P.Toggle()
    if P.IsOpen() then P.Close() else P.Open() end
end
RF.TogglePanel = P.Toggle   -- Bindings.xml

-- From the options' appearance section: the real panel, beside the Options window so both can be seen.
-- Placed against UIParent at that spot rather than anchored to the Options window; its saved place is
-- kept, and used the next time it opens.
function P.TogglePreview()
    if P.IsOpen() then P.Close() return end
    if not P.Open() then return end
    local sp = SettingsPanel
    if sp and sp:IsShown() then
        local right, top = sp:GetRight(), sp:GetTop()
        local scale = (sp:GetEffectiveScale() or 1) / ((panel:GetEffectiveScale() or 1))
        if right and top then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right * scale + 8, top * scale)
        end
    end
    panel:Raise()
end

-- One line, once, when a kind reaches what the plan needs just after a conjure: the cue to let go of a
-- held key. Whether or not the panel is open, since the key may be held with it shut.
local function Cue(plan)
    local since = RF.SinceConjure()
    for _, kind in ipairs(RF.KINDS) do
        local total = plan.totals[kind]
        local short = total.short > 0
        if wasShort[kind] and not short and total.need > 0 and since and since < RECENT then
            Notice(("Enough %s prepared."):format(RF.KIND_LABEL[kind]:lower()))
        end
        wasShort[kind] = short
    end
end

-- After the plan, the shares or the switch change: the buttons follow, and an open panel redraws.
RF.OnChange(function()
    if not RF.Enabled() then
        wipe(wasShort)
        P.Close()
        if conjure.water then P.UpdateButtons() end   -- emptied, so their keys do nothing while it is off
        return
    end
    local plan = RF.Plan()
    if plan then Cue(plan) end
    if not panel then Ensure() return end
    P.UpdateButtons()
    Render()
end)


---------------------------------------------------------------------------
-- For /tui diagnostics: whether each button's secure spell is the one the plan wants.
---------------------------------------------------------------------------
function P.Snapshot()
    local out = { built = panel ~= nil, shown = P.IsOpen(), deferred = dirty, closeAfterCombat = closeAfterCombat, buttons = {} }
    for _, kind in ipairs(RF.KINDS) do
        local b = conjure[kind]
        local attr = b and b:GetAttribute("spell")
        out.buttons[#out.buttons + 1] = { kind = kind, built = b ~= nil, spell = attr, wanted = Wanted(kind),
            matches = b ~= nil and attr == b.spell }
    end
    return out
end
