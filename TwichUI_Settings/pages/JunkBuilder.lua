-- TwichUI settings: Junk marking, the rule builder.
-- A sibling of the Reminders "When" builder: a rail of saved rules, a catalog of conditions, the rule drawn as cards and
-- groups, and a "Try an item" strip over the same footer (Undo, Redo, Cancel, Save). The model is JunkSession.lua (one draft,
-- history, validation, the sentence); this file draws it and routes clicks and drags to it. Saved rules change only on Save.
-- Item tests ask the Workshop's junk reader (Junk.lua Inspect), which decides exactly as marking does and writes nothing.
local R = TwichUI
local B = {}
R.JunkBuilder = B

local function G() return R.SettingsWidgets end
local function M() return R.SettingsMaterial end
local function S() return R.JunkSession end
local function L() return R.WorkshopLauncher end
local function T() return L().JunkTree end

local LEFT_W, GAP, RIGHT_W, HEIGHT = 292, 22, 960, 800
local PALETTE_W, PANE_PAD = 228, 14
local RULE_W = RIGHT_W - PALETTE_W - PANE_PAD * 3 - 20      -- the rule scroll's content width
local RAIL, INSET, HEAD_H, GAP_Y, SEP_H, CARD_H, ICON = 3, 12, 34, 6, 16, 64, 30
local ROW = 54

local f                         -- the right frame (the editor)
local root, left, drag
local ui = { query = "", category = nil, test = nil }
local stats = { cards = 0, groups = 0, rows = 0, paletteRows = 0 }
local pools = { cards = {}, groups = {}, seps = {}, rows = {}, palette = {}, headings = {} }

---------------------------------------------------------------------------
-- Words and art for each kind of condition
---------------------------------------------------------------------------
local function Npc(name) return R.PATH .. [[media\npcs\]] .. name end
local CONDITIONS = {
    { key = "kind", name = "Item type", category = "Item", art = "leather-backpack",
        blurb = "Gear, materials, recipes, supplies or other.",
        tip = "Choose gear, materials, recipes, supplies or other. Quest items and keys are never candidates, whatever the rule says." },
    { key = "armor", name = "Armor type", category = "Item", art = "tabard",
        blurb = "Cloth, leather, mail, plate, shields.",
        tip = "The armor class of the item: cloth, leather, mail, plate or shields. Anything that is not armor is none of these." },
    { key = "quality", name = "Quality range", category = "Item", art = "inscribed-stone",
        blurb = "From Poor to Legendary.",
        tip = "The item's quality, from Poor (gray) to Legendary. Pick the first and last quality the rule may match." },
    { key = "tool", name = "Profession tool", category = "Item", art = "hammer",
        blurb = "Mining pick, skinning knife, rods, fishing poles.",
        tip = "Profession tools: miscellaneous tool weapons (mining pick, blacksmith hammer, skinning knife), fishing poles, and a short list of known rods and spanners. Judged from the item's type; not read from a Forever client yet." },
    { key = "camping", name = "Camping item", category = "Item", art = "paw",
        blurb = "Campfire kits and camp objects.",
        tip = "Campfire kits and the camp objects the professions make, from the camping bar's item list. The Cozy Sleeping Bag is always protected anyway." },
    { key = "wearable", name = "Wearable now", category = "Your character", art = "tabard",
        blurb = "Whether you can wear it.",
        tip = "Whether your character can wear or use it right now, read from the item's tooltip. Only armor and weapons are judged; for anything else this stays unknown and the rule leaves the item alone." },
    { key = "upgrade", name = "Gear Advisor upgrade", category = "Your character", art = "hammer-and-chisel",
        blurb = "Whether the Gear Advisor sees an upgrade.",
        tip = "Whether TwichUI's gear comparison (the Gear Advisor) thinks it would improve what you wear: is an upgrade, or is not. An estimate, and only for armor and weapons." },
    { key = "unlearnedRecipe", name = "Unlearned recipe", category = "Your character", art = "sealed-scroll",
        blurb = "A recipe for my profession I don't know.",
        tip = "A recipe for one of your professions that you have not learned: its tooltip does not say Already known. Your professions are the ones whose window TwichUI has read, so open each profession once." },
    { key = "classReagent", name = "Class reagent", category = "Crafting", art = "reagent-pouch",
        blurb = "A reagent your class uses.",
        tip = "A reagent your class uses, from the vendor restocking list. TwichUI can confirm an item is on it, never that it is not." },
    { key = "profession", name = "Recipe material", category = "Crafting", art = "sealed-scroll",
        blurb = "Used by a recipe you know.",
        tip = "An ingredient in a recipe your characters have learned (remembered by the Workshop). TwichUI can confirm an item is used, never that it is not." },
    { key = "professionMaterial", name = "Profession material", category = "Crafting", art = "cloth-bolts",
        blurb = "A trade good for one of my professions.",
        tip = "A trade good (cloth, leather, ore and stone, herbs, meat, enchanting materials, parts) used by one of your professions, judged from its type. Your professions are the ones whose window TwichUI has read." },
    { key = "vendor", name = "Workshop recommends Vendor", category = "Workshop", art = "coins",
        blurb = "Workshop's advice is to vendor it.",
        tip = "Workshop's Item Advisor recommends selling this to a vendor (using your price source, crafting plans and disenchant value). Older rules had this built in; now it is a condition you can keep, flip or remove. Needs Item Advisor loaded." },
    { key = "all", name = "All of these (AND)", category = "Groups", icon = "profiles",
        blurb = "Every condition inside must be true.",
        tip = "A group where every condition inside must be true: this and that. Use groups to build rules like: Gear, and (Poor or Common)." },
    { key = "any", name = "Any of these (OR)", category = "Groups", icon = "profilesSharing",
        blurb = "At least one condition inside.",
        tip = "A group where at least one condition inside must be true: this or that." },
}
local BY_KEY = {}
for _, c in ipairs(CONDITIONS) do BY_KEY[c.key] = c end
local CATEGORIES = { "Item", "Your character", "Crafting", "Workshop", "Groups" }

local function ApplyArt(texture, key, size)
    local c = BY_KEY[key]
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetSize(size, size)
    if c and c.art then
        texture:SetTexture(Npc(c.art) .. (size <= 32 and "-small.tga" or ".tga"))
    elseif c and c.icon and R.Icons and R.Icons.Apply then
        R.Icons.Apply(texture, c.icon, size)
    end
end

local OPERATOR = {
    all = { heading = "Match all of these", tag = "AND", short = "All", sep = "and",
        tip = "Every condition in this group must be true (AND). The group fails if any one of them is false." },
    any = { heading = "Match any of these", tag = "OR", short = "Any", sep = "or",
        tip = "At least one condition in this group must be true (OR). It is enough that one of them is." },
}
local BOOL_CHOICES = {
    wearable = { { value = true, label = "Can be worn now" }, { value = false, label = "Can't be worn now" } },
    upgrade = { { value = true, label = "Is an upgrade" }, { value = false, label = "Is not an upgrade" } },
    vendor = { { value = true, label = "Recommends Vendor" }, { value = false, label = "Doesn't recommend Vendor" } },
    unlearnedRecipe = { { value = true, label = "Is one I haven't learned" }, { value = false, label = "Is not" } },
    professionMaterial = { { value = true, label = "Is a material for my professions" }, { value = false, label = "Is not" } },
    tool = { { value = true, label = "Is a profession tool" }, { value = false, label = "Is not a tool" } },
    camping = { { value = true, label = "Is a camping item" }, { value = false, label = "Is not a camping item" } },
    classReagent = { { value = true, label = "Is a reagent for my class" }, { value = false, label = "Is not (never matches)" } },
    profession = { { value = true, label = "Used by a recipe I know" }, { value = false, label = "Is not (never matches)" } },
}
local function Qualities()
    local out = {}
    for i, name in ipairs(T().QUALITY) do out[i] = { value = i - 1, label = name } end
    return out
end
local function Kinds()
    local out = {}
    for i, k in ipairs(T().KINDS) do out[i] = { value = k[1], label = k[2] } end
    return out
end
local STATE_WORD = { yes = "Met", no = "Not met", unknown = "Can't tell" }

local function Truncate(text, n)
    if #text <= n then return text end
    return text:sub(1, n - 3):gsub("[\192-\255][\128-\191]*$", "") .. "..."
end
local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end
local DEFAULT_SUBTITLE = "Choose when an item counts as junk. Protections always win."
local function Say(text, tone)
    if f and f.subtitle then
        f.subtitle:SetText(text or DEFAULT_SUBTITLE)
        local pal = G().pal
        G().Color(f.subtitle, tone == "warn" and pal.danger.text or (text and pal.bronzeText or pal.textDim))
    end
end

---------------------------------------------------------------------------
-- Item tests
---------------------------------------------------------------------------
local function Junk() return R.Workshop and R.Workshop.Junk end
local ADVICE = { vendor = "Vendor", auction = "the Auction House", disenchant = "Disenchanting", craft = "Crafting", watch = "waiting" }
local WHY = {
    never = "It is on your Never mark list.",
    cozy = "The Cozy Sleeping Bag is always protected.",
    mage = "Mage Sell keeps this item, so it is never marked.",
    restock = "Vendor restocking keeps this item, so it is never marked.",
}
local BLOCK = {
    locked = "Another copy is locked, so every copy is left alone.",
    quest = "A copy is a quest item, so every copy is left alone.",
    unknown = "The game has not given this item's details yet, so it is left alone.",
}

-- The four answers, and what to say about each: head, tone, detail.
local function Describe(res)
    if not res then return nil end
    if res.state == "unavailable" then return "Item testing is unavailable", "unknown", "Item Advisor must be loaded: turn on Junk marking and load it on the settings page." end
    if res.state == "empty" then return "That slot is empty now", "unknown", "Choose the item again." end
    if res.state == "gone" then return "That item is no longer in your bags", "unknown", "Choose another item to test." end
    if res.state == "unreadable" then return "Cannot determine", "unknown", "The game would not show this item yet. Try again in a moment." end
    local name = res.item and res.item.name or "This item"
    if res.verdict == "protected" then return "Protected: never marked", "protected", WHY[res.why] or "It is protected." end
    if res.verdict == "blocked" then return "Cannot determine", "unknown", BLOCK[res.block] or "It is left alone." end
    if res.verdict == "class" then return "Not a candidate", "unmet", "Quest items and keys are never marked." end
    local trace = res.trace or {}
    local failing, unknown = {}, {}
    local function Walk(n)
        if n.type == "group" then for _, c in ipairs(n.children) do Walk(c) end
        elseif trace[n] == "no" then failing[#failing + 1] = T().Phrase(n)
        elseif trace[n] == "unknown" then unknown[#unknown + 1] = T().Phrase(n) end
    end
    if S().Tree() then Walk(S().Tree()) end
    if res.verdict == "match" then
        local detail
        if (res.reserved or 0) > 0 then detail = "It is reserved for your crafting plan, so it would not be marked."
        elseif res.touched then detail = "You unmarked it earlier this session, so it is left alone."
        elseif res.wanted then detail = "With this rule on, it would be marked."
        else detail = "Marking is off or waiting, so nothing is marked now." end
        return "Matches this rule", "met", detail
    elseif res.verdict == "nomatch" then
        return "Does not match", "unmet", #failing > 0 and ("Not met: " .. table.concat(failing, "; ") .. ".") or "None of the rule's conditions are met."
    end
    return "Cannot determine", "unknown",
        (#unknown > 0 and ("Can't tell: " .. table.concat(unknown, "; ") .. ". ") or "") .. "A condition TwichUI has no answer for yet leaves the item alone."
end

function B.TestSlot(bag, slot)
    ui.test = { bag = bag, slot = slot }
    B.Retest()
    local item = ui.test.result and ui.test.result.item
    ui.test.id = item and item.id or nil
    B.Refresh()
end

-- The chosen item is followed by its ID, so a bag that was rearranged since still tests the same item.
function B.Retest()
    local t = ui.test
    if not t then return end
    local junk = Junk()
    if not junk or not S().Active() then
        t.result = { state = "unavailable" }
    else
        if t.id then
            local at = junk.Find(t.id)
            if not at then
                t.result = { state = "gone" }
                t.revision = S().Revision()
                return
            end
            t.bag, t.slot = at.bag, at.slot
        end
        t.result = junk.Inspect(t.bag, t.slot, S().TestRule())
    end
    t.revision = S().Revision()
end

-- Bags and item details change under an open window: look again, once, shortly after the burst.
local pending
function B.BagsChanged()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        if not B.Shown() then return end
        if ui.survey and not ui.survey.running then ui.survey.stale = true end
        if ui.test then B.Retest() end
        B.PickerRefresh()
        B.Refresh()
    end)
end

-- A chosen item can also be dropped on the strip: its ID is found in the bags; the item itself goes straight back.
function B.TakeCursor()
    if not GetCursorInfo then return false end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or type(id) ~= "number" then return false end
    local junk = Junk()
    local at = junk and junk.Find(id)
    if ClearCursor then ClearCursor() end
    if not at then
        Say("That item is not in your bags, so it cannot be tested.", "warn")
        return false
    end
    B.TestSlot(at.bag, at.slot)
    return true
end

function B.Survey()
    local junk = Junk()
    if not junk or not S().Active() then ui.survey = { unavailable = true }; B.Refresh(); return end
    ui.survey = { running = true, revision = S().Revision() }
    junk.Survey(S().TestRule(), function(result)
        if not ui.survey then return end
        result.revision = ui.survey.revision
        ui.survey = result
        if f and f:IsShown() then B.Refresh() end
    end)
    B.Refresh()
end

---------------------------------------------------------------------------
-- Opening, selecting, closing
---------------------------------------------------------------------------
function B.Shown() return root ~= nil and root:IsShown() end
function B.Frame() return f end
function B.Root() return root end

local function Reset()
    ui.test, ui.survey = nil, nil
end

local function Discard(after)
    if not S().Dirty() then after(); return end
    local current = S().Index()
    R.Interact.Confirm("TWICHUI_DISCARD_JUNK_RULE", "Discard unsaved changes to this rule?", function()
        if S().Index() == current then after() end
    end, { accept = "Discard" })
end

function B.Select(index)
    if S().Active() and S().Index() == index and not S().IsNew() then return end
    Discard(function()
        Reset()
        if S().Begin(index) then Say(nil) else Say("Saved rules are not available right now.", "warn") end
        B.Refresh()
    end)
end

local function Lead()
    -- A new rule leads straight to its first condition.
    if f and f.search then f.search:SetFocus() end
end

function B.New()
    Discard(function()
        Reset()
        if not S().BeginNew("New rule") then
            Say("The rule limit is reached, or saved rules are not available.", "warn")
        else
            Say("Pick the first condition from the list, or start from an example.")
        end
        B.Refresh()
        Lead()
    end)
end

function B.Open(index)
    B.Build()
    if not root then return false end
    local rows = S().Rows()
    if index and rows[index] then
        Reset()
        S().Begin(index)
    elseif not S().Active() and #rows > 0 then
        Reset()
        S().Begin(1)
    end
    root:Show()
    f:Show()
    B.Refresh()
    return true
end

function B.Close()
    if drag then drag:Cancel() end
    S().Cancel()
    Reset()
    if f then f:Hide() end
    if root then root:Hide() end
    if R.SettingsKit and R.SettingsKit.RefreshOverview then R.SettingsKit.RefreshOverview() end
end

function B.RequestClose()
    Discard(B.Close)
end

function B.CancelDrag()
    if drag and drag.source then drag:Cancel(); return true end
    if f and f.picker and f.picker:IsShown() then f.picker:Hide(); return true end
    return false
end

function B.Revert()
    -- Cancel: the rule goes back to what is saved.
    if not S().Active() then return end
    if S().IsNew() then
        S().Cancel()
        Reset()
        if #S().Rows() > 0 then S().Begin(1) end
    else
        local index = S().Index()
        Reset()
        S().Begin(index)
    end
    Say(nil)
    B.Refresh()
end

function B.Save()
    local ok, why = S().Save()
    if not ok then Say(why, "warn"); B.Refresh(); return false end
    Say("Saved.")
    B.Refresh()
    if R.SettingsKit and R.SettingsKit.RefreshOverview then R.SettingsKit.RefreshOverview() end
    return true
end

function B.Delete()
    local name = S().Name() or "this rule"
    local current = S().Index()
    R.Interact.Confirm("TWICHUI_DELETE_JUNK_RULE", ("Delete the rule \"%s\"? Items it marked stay marked; unmark them in EllesmereUI."):format(name), function()
        if S().Index() ~= current then return end
        local ok, why = S().Delete()
        if not ok then Say(why, "warn"); B.Refresh(); return end
        Reset()
        if #S().Rows() > 0 then S().Begin(math.min(current, #S().Rows())) end
        Say("Rule deleted.")
        B.Refresh()
        if R.SettingsKit and R.SettingsKit.RefreshOverview then R.SettingsKit.RefreshOverview() end
    end, { accept = "Delete" })
end

function B.Duplicate()
    if S().IsNew() then
        Say("Save this rule first, then duplicate it.", "warn")
        return
    end
    -- The copy starts from what is on screen, unsaved edits included; the saved original stays as it was.
    Reset()
    if S().BeginCopy() then Say("This is a copy. Save to keep it.") else Say("The rule limit is reached.", "warn") end
    B.Refresh()
end

function B.ToggleRow(index, on)
    if not index then return end
    local ok, why = S().ToggleSaved(index, on)
    if not ok then Say(why, "warn") else Say(nil) end
    B.Refresh()
end

function B.Do(ok, why)
    if ok == false or ok == nil then Say(why, "warn") else Say(nil) end
    B.Refresh()
    return ok
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function B.Build()
    if f then return end
    local g, m = G(), M()
    local pal = g.pal
    local function Font(fs, size, ivory, role) return m.ReminderFont(fs, size, ivory, role) end
    local function Button(parent, label, width, kind, action)
        local b = g.Button(parent, label, width, kind, action)
        m.ReminderControl(b, kind)
        return b
    end
    local function Dropdown(...)
        local d = g.Dropdown(...)
        m.ReminderControl(d, "dropdown")
        return d
    end

    ---------------------------------------------------------------- the two panels
    root = CreateFrame("Frame", "TwichUIJunkBuilder", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("HIGH")
    root:SetToplevel(true)
    root:EnableMouse(true)
    root:Hide()
    g.Solid(root, "BACKGROUND", { 0, 0, 0 }, 0.35):SetAllPoints()
    local pair = CreateFrame("Frame", nil, root)
    pair:SetPoint("CENTER")
    pair:SetSize(LEFT_W + GAP + RIGHT_W, HEIGHT)
    local function Fit()
        local uiScale = UIParent:GetEffectiveScale()
        local anchor = R.SettingsAnchor and R.SettingsAnchor()
        local preferred = anchor and anchor:GetEffectiveScale() / uiScale or 1
        pair:SetScale(math.min(preferred, (UIParent:GetWidth() - 24) / pair:GetWidth(), (UIParent:GetHeight() - 24) / HEIGHT))
    end
    root:SetScript("OnShow", function(self)
        self:Raise()
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        Fit()
        R.SettingsUI.SetWorkspaceVisible(true)
    end)
    root:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        g.CloseMenu()
        R.SettingsUI.SetWorkspaceVisible(false)
    end)
    root:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then B.BagsChanged() else Fit() end
    end)

    left = CreateFrame("Frame", nil, pair)
    left:SetSize(LEFT_W, HEIGHT)
    left:SetPoint("TOPLEFT")
    m.WorkspaceFrame(left)
    m.HeaderBand(left, 65)
    f = CreateFrame("Frame", "TwichUIJunkRules", pair)
    f:SetSize(RIGHT_W, HEIGHT)
    f:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    f:EnableMouse(true)
    m.WorkspaceFrame(f)
    f.placement = "workspace"
    m.FrameConnector(pair, 64):SetPoint("CENTER", left, "TOPRIGHT", GAP / 2, -112)

    ---------------------------------------------------------------- left rail
    local lw = LEFT_W - 44
    local function Heading(parent, text, x, y, size)
        local fs = Font(g.Text(parent, "title"), size or 17, true)
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetText(text)
        return fs
    end
    local function Divider(parent, y, x1, x2)
        local line = g.Solid(parent, "ARTWORK", pal.bronzeLo, 0.56)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", x1 or 22, -y)
        line:SetPoint("TOPRIGHT", -(x2 or 22), -y)
    end
    local title = Heading(left, "Junk marking", 66, 24, 23)
    local crest = left:CreateTexture(nil, "ARTWORK")
    crest:SetSize(36, 36)
    crest:SetPoint("TOPLEFT", 22, -17)
    R.Icons.Apply(crest, "vendors", 36)
    Divider(left, 65)
    Heading(left, "Your marking rules", 22, 78)
    left.count = Font(g.Text(left, "small"), 12)
    left.count:SetPoint("TOPRIGHT", -22, -83)
    local scroll, content = g.Scroll(left, lw - 12)
    scroll:SetPoint("TOPLEFT", 22, -108)
    scroll:SetSize(lw - 12, 272)
    left.fitRail = m.ScrollRail(scroll)
    left.scroll, left.content = scroll, content
    left.empty = Font(g.Text(left, "body"), 13)
    left.empty:SetPoint("TOPLEFT", 26, -116)
    left.empty:SetWidth(lw - 8)
    left.empty:SetWordWrap(true)
    left.empty:SetText("No rules yet. Create one, then choose what it should mark.")
    left.new = Button(left, "+ New rule", lw, "secondary", B.New)
    left.new:SetHeight(34)
    left.new:SetPoint("TOPLEFT", 22, -390)
    m.ContextTip(left.new, "New rule", function()
        return "Starts an empty rule, switched off. It marks nothing until you add a condition and turn it on. Up to 32 rules.",
            "Any enabled rule can mark an item. Rule order does not matter."
    end)
    Divider(left, 436)
    Heading(left, "This rule", 22, 448)
    local sumScroll, sum = g.Scroll(left, lw - 12)
    sumScroll:SetPoint("TOPLEFT", 22, -476)
    sumScroll:SetSize(lw - 12, 100)
    left.fitSum = m.ScrollRail(sumScroll)
    left.summary = Font(g.Text(sum, "body"), 14)
    left.summary:SetPoint("TOPLEFT", 0, 0)
    left.summary:SetWidth(lw - 14)
    left.summary:SetWordWrap(true)
    left.sumScroll, left.sumContent = sumScroll, sum
    Divider(left, 588)
    Heading(left, "Protections", 22, 600)
    left.protect = Font(g.Text(left, "body"), 13)
    left.protect:SetPoint("TOPLEFT", 22, -628)
    left.protect:SetWidth(lw)
    left.protect:SetWordWrap(true)
    left.never = Button(left, "Never mark list...", lw, "secondary", function()
        B.RequestClose()
        if R.WorkshopJunkSettings and R.WorkshopJunkSettings.Open then R.WorkshopJunkSettings.Open() end
    end)
    left.never:SetHeight(32)
    left.never:SetPoint("TOPLEFT", 22, -712)
    m.ContextTip(left.never, "Never mark list", "Closes this window and opens the list of items that are never marked, whatever a rule says.")
    left.note = Font(g.Text(left, "small"), 12)
    left.note:SetPoint("BOTTOMLEFT", 22, 14)
    left.note:SetWidth(lw)
    left.note:SetWordWrap(true)
    g.Color(left.note, pal.stone)
    left.note:SetText("Rules choose candidates. Protections always win. Nothing here sells an item.")

    local function Row(i)
        if pools.rows[i] then return pools.rows[i] end
        local row = CreateFrame("Button", nil, content)
        row:SetSize(lw - 12, ROW - 4)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        m.ReminderRow(row)
        m.MaterialHover(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 8, 0)
        row.icon:SetTexture(Npc("coins-small.tga"))
        row.name = Font(g.Text(row, "heading"), 14, true)
        row.name:SetPoint("TOPLEFT", 44, -7)
        row.name:SetWidth(150)
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row.brief = Font(g.Text(row, "small"), 12)
        row.brief:SetPoint("TOPLEFT", 44, -27)
        row.brief:SetWidth(lw - 12 - 44 - 10)
        row.brief:SetMaxLines(1)
        row.brief:SetWordWrap(false)
        g.Color(row.brief, pal.stone)
        row.pill = m.Pill(row, function(on) B.ToggleRow(row.index, on) end, true)
        row.pill:SetPoint("TOPRIGHT", -10, -9)
        m.ContextTip(row.pill, "Rule on or off", "Switches this saved rule on or off at once. Only an enabled rule can mark items.")
        row:SetScript("OnClick", function(self) if self.index then B.Select(self.index) end end)
        m.ContextTip(row, "Marking rule", function(self) return self.fullName or "", self.fullBrief end)
        pools.rows[i] = row
        stats.rows = #pools.rows
        return row
    end
    B.Row = Row

    ---------------------------------------------------------------- right: header, footer, test strip
    m.HeaderBand(f, 96)
    f.title = g.Text(f, "title")
    f.title:SetPoint("TOPLEFT", 23, -18)
    f.title:SetWidth(RIGHT_W - 120)
    f.title:SetMaxLines(1)
    Font(f.title, 26, true)
    f.subtitle = Font(g.Text(f, "body"), 14)
    f.subtitle:SetPoint("TOPLEFT", 23, -53)
    f.subtitle:SetText(DEFAULT_SUBTITLE)
    f.subtitle:SetWidth(RIGHT_W - 120)
    f.close = R.FrameLook.Close(f, B.RequestClose)
    f.close:SetSize(27, 27)
    m.ReminderControl(f.close, "action")
    f.close:SetPoint("TOPRIGHT", -17, -16)

    local function Band(parent)
        local line = g.Solid(parent, "ARTWORK", { 0.53, 0.41, 0.26 }, 0.63)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT")
        line:SetPoint("TOPRIGHT")
    end
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", 10, 11)
    footer:SetPoint("BOTTOMRIGHT", -10, 11)
    footer:SetHeight(56)
    m.QuietTile(footer, "header")
    Band(footer)
    local function Action(label, width, kind, callback)
        local b = Button(footer, label, width, kind, callback)
        b:SetHeight(38)
        Font(b.text, 14)
        return b
    end
    f.save = Action("Save", 116, "confirmation", B.Save)
    f.save:SetPoint("RIGHT", -13, 0)
    f.cancel = Action("Cancel", 108, "action", B.Revert)
    f.cancel:SetPoint("RIGHT", f.save, "LEFT", -10, 0)
    m.ContextTip(f.cancel, "Cancel", "Discards your unsaved changes and shows the saved rule again.")
    m.ContextTip(f.save, "Save", "Applies the rule. Until you save, the rule marking uses does not change.")
    local function History(label, reverse, callback)
        local b = Action(label, 98, "action", callback)
        b.craftLabelInset = 35
        local icon = b:CreateTexture(nil, "OVERLAY")
        icon:SetAtlas("common-icon-undo")
        if reverse then
            local ulx, uly, llx, lly, urx, ury, lrx, lry = icon:GetTexCoord()
            if lry then icon:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly) end
        end
        icon:SetSize(17, 17)
        icon:SetPoint("LEFT", 12, 0)
        b.text:ClearAllPoints()
        b.text:SetWidth(0)
        b.text:SetPoint("LEFT", 35, 0)
        function b:PaintIcon()
            local c = self:IsEnabled() and pal.bronzeText or pal.stone
            icon:SetVertexColor(c[1], c[2], c[3], self:IsEnabled() and 1 or 0.55)
        end
        return b
    end
    f.undo = History("Undo", false, function() S().Undo(); B.Refresh() end)
    f.undo:SetPoint("LEFT", 13, 0)
    f.redo = History("Redo", true, function() S().Redo(); B.Refresh() end)
    f.redo:SetPoint("LEFT", f.undo, "RIGHT", 10, 0)
    m.ContextTip(f.undo, "Undo", "Reverses the most recent change to this rule.")
    m.ContextTip(f.redo, "Redo", "Puts back what Undo reversed.")
    f.dirty = Font(g.Text(footer, "small"), 13)
    f.dirty:SetPoint("CENTER", 40, 0)

    -- the test strip
    local strip = CreateFrame("Frame", nil, f)
    strip:SetHeight(116)
    strip:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    m.PanelFace(strip, "espresso")
    Band(strip)
    f.strip = strip
    strip.head = Font(g.Text(strip, "title"), 16, true)
    strip.head:SetPoint("TOPLEFT", 16, -10)
    strip.head:SetText("Try an item")
    strip.well = CreateFrame("Frame", nil, strip)
    strip.well:SetSize(400, 38)
    strip.well:SetPoint("TOPLEFT", 16, -32)
    m.PanelFace(strip.well, "well")
    strip.icon = strip.well:CreateTexture(nil, "ARTWORK")
    strip.icon:SetSize(28, 28)
    strip.icon:SetPoint("LEFT", 6, 0)
    strip.itemName = Font(g.Text(strip.well, "body"), 14, true)
    strip.itemName:SetPoint("LEFT", 42, 0)
    strip.itemName:SetWidth(350)
    strip.itemName:SetMaxLines(1)
    strip.choose = Button(strip, "Choose item", 124, "secondary", function() B.TogglePicker() end)
    strip.choose:SetHeight(32)
    strip.choose:SetPoint("LEFT", strip.well, "RIGHT", 10, 0)
    m.ContextTip(strip.choose, "Choose an item", "Pick an item from your bags, or drop one on this strip. It is tested against the rule on screen, unsaved changes included. Nothing is marked or moved.")
    strip.survey = Button(strip, "Check my bags", 130, "secondary", B.Survey)
    strip.survey:SetHeight(32)
    strip.survey:SetPoint("LEFT", strip.choose, "RIGHT", 8, 0)
    m.ContextTip(strip.survey, "Check my bags", "Counts how many different items in your bags this rule would pick out. Runs once, only when you ask, and marks nothing.")
    strip.surveyText = Font(g.Text(strip, "small"), 13)
    strip.surveyText:SetPoint("TOPLEFT", strip.survey, "TOPRIGHT", 12, -2)
    strip.surveyText:SetWidth(RIGHT_W - 16 - 400 - 10 - 124 - 8 - 130 - 12 - 24)
    strip.surveyText:SetMaxLines(2)
    strip.result = Font(g.Text(strip, "heading"), 15, true)
    strip.result:SetPoint("TOPLEFT", 16, -72)
    strip.result:SetWidth(RIGHT_W - 60)
    strip.result:SetMaxLines(1)
    strip.reason = Font(g.Text(strip, "body"), 13)
    strip.reason:SetPoint("TOPLEFT", 16, -92)
    strip.reason:SetWidth(RIGHT_W - 60)
    strip.reason:SetMaxLines(2)
    strip:EnableMouse(true)
    strip:SetScript("OnReceiveDrag", B.TakeCursor)
    strip:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" and GetCursorInfo and GetCursorInfo() then B.TakeCursor() end end)
    strip.well:EnableMouse(true)
    strip.well:SetScript("OnReceiveDrag", B.TakeCursor)

    ---------------------------------------------------------------- the two panes
    local function Pane(x, width)
        local pane = CreateFrame("Frame", nil, f)
        pane:SetPoint("TOPLEFT", x, -100)
        pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", x + width, 67 + 116 + 8)
        m.PanelFace(pane, "editor")
        return pane
    end
    local palette = Pane(PANE_PAD, PALETTE_W)
    local rule = Pane(PANE_PAD * 2 + PALETTE_W, RIGHT_W - PALETTE_W - PANE_PAD * 3)
    f.palette, f.rule = palette, rule

    ---------------------------------------------------------------- the condition catalog
    palette.head = Font(g.Text(palette, "title"), 18, true)
    palette.head:SetPoint("TOPLEFT", 12, -10)
    palette.head:SetText("Add a condition")
    palette.where = Font(g.Text(palette, "small"), 12)
    palette.where:SetPoint("TOPLEFT", 12, -34)
    palette.where:SetWidth(PALETTE_W - 24)
    palette.where:SetMaxLines(1)
    f.search = g.EditBox(palette, PALETTE_W - 24, 28)
    f.search:SetPoint("TOPLEFT", 12, -52)
    m.ReminderControl(f.search, "field")
    f.searchHint = m.SearchDecoration(f.search, "Search...")
    f.search:SetMaxLetters(40)
    f.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        ui.query = self:GetText()
        f.paletteScroll:SetVerticalScroll(0)
        B.Palette()
    end)
    f.search:HookScript("OnEditFocusGained", function() f.searchHint:Hide() end)
    f.search:HookScript("OnEditFocusLost", function() f.searchHint:SetShown(f.search:GetText() == "") end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search:HookScript("OnHide", function(self) self:ClearFocus() end)
    m.ContextTip(f.search, "Search", "A few letters of what you want: quality, gear, recipe, group...")
    f.category = Dropdown(palette, PALETTE_W - 24, function(value)
        ui.category = value ~= "all" and value or nil
        f.paletteScroll:SetVerticalScroll(0)
        B.Palette()
    end)
    f.category:SetHeight(26)
    f.category:SetPoint("TOPLEFT", 12, -84)
    Font(f.category.text, 13)
    f.category:SetChoices(function()
        local out = { { value = "all", label = "All categories" } }
        for _, c in ipairs(CATEGORIES) do out[#out + 1] = { value = c, label = c } end
        return out
    end)
    f.category:SetValue("all", "All categories")
    f.paletteScroll, f.paletteContent = g.Scroll(palette, PALETTE_W - 28)
    f.paletteScroll:SetPoint("TOPLEFT", 8, -116)
    f.paletteScroll:SetPoint("BOTTOMRIGHT", palette, "BOTTOMRIGHT", -20, 8)
    f.fitPalette = m.ScrollRail(f.paletteScroll)
    m.ContextTip(palette.head, "Add a condition", "Click a condition to add it to the highlighted group, or drag it into the rule. To add to another group, press that group's Add a condition button first.")
    palette.none = Font(g.Text(f.paletteContent, "small"), 13)
    palette.none:SetText("No matching conditions.")

    ---------------------------------------------------------------- the rule pane: header strip
    rule.name = g.EditBox(rule, 300, 32)
    rule.name:SetPoint("TOPLEFT", 14, -12)
    m.ReminderControl(rule.name, "field")
    Font(rule.name, 14)
    rule.name:SetMaxLetters(60)
    local function CommitName(self)
        if not S().Active() then return end
        local text = self:GetText()
        if text == "" then self:SetText(S().Name() or "") else S().SetName(text) end
        self:ClearFocus()
        B.Refresh()
    end
    rule.name:SetScript("OnEnterPressed", CommitName)
    rule.name:SetScript("OnEditFocusLost", CommitName)
    rule.name:SetScript("OnEscapePressed", function(self) self:SetText(S().Name() or ""); self:ClearFocus() end)
    m.ContextTip(rule.name, "Rule name", "Only for you: it names the rule in your list. Press Enter to keep a new name.")
    rule.pill = m.Pill(rule, function(on)
        local ok, why = S().SetOn(on)
        if not ok then Say(why, "warn") else Say(nil) end
        B.Refresh()
    end)
    rule.pill:SetPoint("TOPLEFT", 332, -18)
    rule.onText = Font(g.Text(rule, "body"), 14, true)
    rule.onText:SetPoint("LEFT", rule.pill, "RIGHT", 8, 0)
    m.ContextTip(rule.pill, "Rule on or off", function()
        return "Only an enabled rule can mark items. A rule with nothing in it cannot be switched on.", "This is saved with the rule when you press Save."
    end)
    rule.more = Dropdown(rule, 96, function(value)
        if value == "rename" then rule.name:SetFocus(); rule.name:HighlightText()
        elseif value == "duplicate" then B.Duplicate()
        elseif value == "delete" then B.Delete() end
    end)
    rule.delete = Button(rule, "Delete", 80, "danger", function() B.Delete() end)
    rule.delete:SetHeight(32)
    rule.delete:SetPoint("TOPRIGHT", -116, -12)
    m.ContextTip(rule.delete, "Delete rule", "Deletes this rule after asking. Items it already marked stay marked; unmark them in EllesmereUI.")
    rule.more:SetHeight(32)
    rule.more:SetPoint("TOPRIGHT", -14, -12)
    rule.more:SetValue(nil, "Rule")
    rule.more:SetChoices(function()
        local out = { { value = "rename", label = "Rename" } }
        if not S().IsNew() then out[#out + 1] = { value = "duplicate", label = "Duplicate" } end
        out[#out + 1] = { value = "delete", label = S().IsNew() and "Discard this rule" or "Delete rule..." }
        return out
    end)
    m.ContextTip(rule.more, "Rule actions", "Rename, duplicate or delete this rule.")
    rule.line = g.Solid(rule, "ARTWORK", pal.bronzeLo, 0.56)
    rule.line:SetHeight(1)
    rule.line:SetPoint("TOPLEFT", 12, -54)
    rule.line:SetPoint("TOPRIGHT", -12, -54)
    rule.heading = Font(g.Text(rule, "title"), 18, true)
    rule.heading:SetPoint("TOPLEFT", 16, -64)
    rule.heading:SetText("Mark an item as junk when")
    m.ContextTip(rule.heading, "How rules work", function()
        return "An item is marked only when an enabled rule matches every copy you carry.",
            "Never mark items, quest items, keys and the Cozy Sleeping Bag are always left alone, whatever a rule says."
    end)
    rule.scroll, rule.content = g.Scroll(rule, RULE_W)
    rule.scroll:SetPoint("TOPLEFT", 8, -94)
    rule.scroll:SetPoint("BOTTOMRIGHT", rule, "BOTTOMRIGHT", -20, 8)
    f.fitRule = m.ScrollRail(rule.scroll)
    rule.tree = CreateFrame("Frame", nil, rule.content)
    rule.tree:SetPoint("TOPLEFT")
    rule.tree:SetWidth(RULE_W)
    rule.tree:SetHeight(10)

    -- the empty state of the whole pane (no rule chosen) and of a rule with nothing in it
    rule.blank = CreateFrame("Frame", nil, rule)
    rule.blank:SetPoint("TOPLEFT", 16, -64)
    rule.blank:SetPoint("BOTTOMRIGHT", -16, 16)
    rule.blank.title = Font(g.Text(rule.blank, "title"), 18, true)
    rule.blank.title:SetPoint("TOPLEFT", 0, 0)
    rule.blank.title:SetText("Create your first marking rule")
    rule.blank.text = Font(g.Text(rule.blank, "body"), 14)
    rule.blank.text:SetPoint("TOPLEFT", 0, -34)
    rule.blank.text:SetWidth(RULE_W - 40)
    rule.blank.text:SetWordWrap(true)
    rule.blank.text:SetText("A rule says which items may be marked as junk. Start an empty rule, or begin from an example, then add conditions from the list on the left. Nothing is marked until a rule is on and Workshop recommends Vendor.")
    rule.blank.new = Button(rule.blank, "+ New rule", 150, "secondary", B.New)
    rule.blank.new:SetHeight(34)
    rule.blank.new:SetPoint("TOPLEFT", 0, -112)

    ---------------------------------------------------------------- drag
    local function Validate(src, group, slot)
        if not S().Active() or not group or group.type ~= "group" then return false end
        if src.raw then return T().Move(S().Tree(), src.raw, group, slot, false) end
        local node = S().Make(src.entry)
        if not node then return false end
        table.insert(group.children, slot, node)
        local valid = T().Copy(S().Tree()) ~= nil
        table.remove(group.children, slot)
        return valid
    end
    drag = R.RemindersRuleDrag.New(rule.scroll, Validate, function(src, group, slot)
        if src.raw then B.Do(S().Move(src.raw, group, slot)) else B.Do(S().Add(src.entry, group, slot)) end
    end)
    B.drag = drag

    ---------------------------------------------------------------- palette rows
    local function PaletteRow(i)
        if pools.palette[i] then return pools.palette[i] end
        local row = CreateFrame("Button", nil, f.paletteContent, "BackdropTemplate")
        m.MaterialHover(row)
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("CENTER", row, "LEFT", 20, 0)
        row.name = Font(g.Text(row, "body"), 14, true)
        row.name:SetPoint("LEFT", 43, 0)
        row.name:SetWidth(PALETTE_W - 28 - 50)
        row.name:SetMaxLines(1)
        row:SetScript("OnClick", function(self)
            if self.key then B.Do(S().Add(self.key)) end
        end)
        m.ContextTip(row, "Condition", function(self)
            local c = self.key and BY_KEY[self.key]
            return c and (c.name .. "\n" .. c.tip) or "", "Click to add to the highlighted group, or drag it into the rule."
        end)
        drag:Bind(row, function()
            local key = row.key
            return { entry = key, art = function(texture, size) ApplyArt(texture, key, size) end }, BY_KEY[key] and BY_KEY[key].name or ""
        end)
        pools.palette[i] = row
        stats.paletteRows = #pools.palette
        return row
    end
    B.PaletteRow = PaletteRow

    ---------------------------------------------------------------- the item picker
    local picker = CreateFrame("Frame", nil, f, "BackdropTemplate")
    picker:SetSize(380, 330)
    picker:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 16, 6)
    picker:SetFrameLevel(f:GetFrameLevel() + 40)
    picker:EnableMouse(true)
    m.PanelFace(picker, "espresso")
    m.Edge(picker, "control", 8):SetBackdropBorderColor(0.57, 0.47, 0.33, 0.8)
    picker:Hide()
    f.picker = picker
    picker.head = Font(g.Text(picker, "title"), 16, true)
    picker.head:SetPoint("TOPLEFT", 14, -10)
    picker.head:SetText("Choose an item from your bags")
    picker.search = g.EditBox(picker, 352, 28)
    picker.search:SetPoint("TOPLEFT", 14, -38)
    m.ReminderControl(picker.search, "field")
    picker.search:SetMaxLetters(60)
    picker.hint = m.SearchDecoration(picker.search, "Search by name or ID...")
    picker.page = 1
    picker.search:SetScript("OnTextChanged", function(_, user) if user ~= false then picker.page = 1; B.PickerRefresh() end end)
    picker.search:HookScript("OnEditFocusGained", function() picker.hint:Hide() end)
    picker.search:HookScript("OnEditFocusLost", function() picker.hint:SetShown(picker.search:GetText() == "") end)
    picker.search:SetScript("OnEscapePressed", function() picker:Hide() end)
    picker.rows = {}
    for i = 1, 7 do
        local row = CreateFrame("Button", nil, picker)
        row:SetSize(352, 30)
        row:SetPoint("TOPLEFT", 14, -74 - (i - 1) * 32)
        m.MaterialHover(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = Font(g.Text(row, "body"), 14)
        row.name:SetPoint("LEFT", 36, 0)
        row.name:SetWidth(300)
        row.name:SetMaxLines(1)
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if e and e.bag and e.slot then picker:Hide(); B.TestSlot(e.bag, e.slot) end
        end)
        picker.rows[i] = row
    end
    picker.empty = Font(g.Text(picker, "body"), 13)
    picker.empty:SetPoint("TOPLEFT", 16, -86)
    picker.empty:SetText("No matching bag items.")
    picker.prev = Button(picker, "Previous", 90, "secondary", function() picker.page = math.max(1, picker.page - 1); B.PickerRefresh() end)
    picker.prev:SetPoint("BOTTOMLEFT", 14, 12)
    picker.next = Button(picker, "Next", 90, "secondary", function() picker.page = picker.page + 1; B.PickerRefresh() end)
    picker.next:SetPoint("BOTTOMRIGHT", -14, 12)
    picker.count = Font(g.Text(picker, "small"), 12)
    picker.count:SetPoint("BOTTOM", 0, 20)
    picker:SetScript("OnHide", function() picker.search:ClearFocus() end)

    f:SetScript("OnHide", function() picker:Hide() end)
    f.footer = footer
end

function B.TogglePicker()
    local picker = f.picker
    if picker:IsShown() then picker:Hide(); return end
    picker.search:SetText("")
    picker.page = 1
    picker:Show()
    B.PickerRefresh()
end

function B.PickerRefresh()
    local picker = f and f.picker
    if not (picker and picker:IsShown()) then return end
    local source = R.WorkshopJunkSettings
    local entries = source and source.Entries("bags", picker.search:GetText()) or {}
    local pages = math.max(1, math.ceil(#entries / #picker.rows))
    picker.page = math.min(picker.page, pages)
    picker.count:SetText(("%d / %d"):format(picker.page, pages))
    picker.prev:SetEnabled(picker.page > 1)
    picker.next:SetEnabled(picker.page < pages)
    for i, row in ipairs(picker.rows) do
        local e = entries[(picker.page - 1) * #picker.rows + i]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            row.name:SetText(e.name)
            row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    picker.empty:SetShown(#entries == 0)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- The conditions palette: categories, search, hover and drag rows.
function B.Palette()
    local g, m, pal = G(), M(), G().pal
    local content = f.paletteContent
    local pad, w = 4, PALETTE_W - 30
    local query = (ui.query or ""):lower()
    local h, shown = 0, 0
    for _, hd in pairs(pools.headings) do hd.text:Hide(); hd.line:Hide() end
    for _, row in ipairs(pools.palette) do row:Hide() end
    f.palette.none:Hide()
    for _, category in ipairs(CATEGORIES) do
        if not ui.category or ui.category == category then
            local header
            for _, c in ipairs(CONDITIONS) do
                if c.category == category and (query == "" or (c.name .. " " .. c.blurb):lower():find(query, 1, true)) then
                    if not header then
                        local hd = pools.headings[category]
                        if not hd then
                            hd = { text = m.ReminderFont(g.Text(content, "title"), 16, true),
                                line = g.Solid(content, "ARTWORK", { 0.42, 0.34, 0.24 }, 0.65) }
                            hd.text:SetWidth(w - pad * 2)
                            hd.line:SetSize(w - pad * 2, 1)
                            pools.headings[category] = hd
                        end
                        Put(hd.line, content, pad, h + 1)
                        hd.text:SetText(category)
                        g.Color(hd.text, { 0.85, 0.76, 0.62 })
                        Put(hd.text, content, pad, h + 7)
                        h = h + 26
                        header = true
                    end
                    shown = shown + 1
                    local row = B.PaletteRow(shown)
                    row.key = c.key
                    ApplyArt(row.icon, c.key, 30)
                    row.name:SetText(c.name)
                    row:SetSize(w - pad * 2, 31)
                    Put(row, content, pad, h)
                    h = h + 33
                end
            end
        end
    end
    if shown == 0 then
        f.palette.none:SetWidth(w - pad * 2)
        Put(f.palette.none, content, pad, 6)
        h = 30
    end
    content:SetHeight(h + 8)
    if f.fitPalette then f.fitPalette(h + 8) end
end

local function StateColor(state)
    local pal = G().pal
    if state == "yes" then return pal.sage elseif state == "no" then return pal.danger.text end
    return pal.stone
end

local function Grip(parent)
    local g, pal = G(), G().pal
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(20, 24)
    for i = 1, 6 do
        local dot = g.Solid(grip, "ARTWORK", pal.bronzeText, 0.8)
        dot:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
        dot:SetVertexColor(0.64, 0.52, 0.34, 0.85)
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", i % 2 == 0 and 2 or -2, 5 - 5 * math.floor((i - 1) / 2))
    end
    g.Hover(grip, pal.text, 0.12)
    M().ContextTip(grip, "Move", "Drag to a highlighted edge or into a group. The More menu moves it without dragging.")
    drag:Bind(grip, function()
        local node = grip.node
        if not node then return nil end
        return { raw = node, art = function(texture, size) ApplyArt(texture, node.type, size) end },
            node.type == "group" and OPERATOR[node.match].heading or (BY_KEY[node.type] and BY_KEY[node.type].name or "Condition")
    end)
    return grip
end

local function MenuFor(node)
    local out = {}
    local parent, at = T().Find(S().Tree(), node)
    if parent then
        if at > 1 then out[#out + 1] = { value = "up", label = "Move up" } end
        if at < #parent.children then out[#out + 1] = { value = "down", label = "Move down" } end
    end
    out[#out + 1] = { value = "dup", label = "Duplicate" }
    node.dests = S().Destinations(node)
    for i, d in ipairs(node.dests) do out[#out + 1] = { value = "to" .. i, label = "Move into " .. d.label:gsub("^%s+", "") } end
    out[#out + 1] = { value = "remove", label = node.type == "group" and "Remove group and its conditions" or "Remove" }
    return out
end

local function MenuPick(node, value)
    if not node then return end
    if value == "up" then B.Do(S().Shift(node, -1))
    elseif value == "down" then B.Do(S().Shift(node, 1))
    elseif value == "dup" then B.Do(S().Duplicate(node))
    elseif value == "remove" then B.Do(S().Remove(node))
    elseif value:sub(1, 2) == "to" then
        node.dests = node.dests or S().Destinations(node)
        local d = node.dests[tonumber(value:sub(3))]
        if d then B.Do(S().Move(node, d.node, #d.node.children + 1)) end
    end
    node.dests = nil
end
B.MenuFor, B.MenuPick = MenuFor, MenuPick

local function NewCard()
    local g, m, pal = G(), M(), G().pal
    local function Font(fs, size, ivory, role) return m.ReminderFont(fs, size, ivory, role) end
    local c = CreateFrame("Frame", nil, f.rule.tree, "BackdropTemplate")
    m.PanelFace(c, "walnut")
    m.MaterialHover(c)
    c.grip = Grip(c)
    c.grip:SetPoint("TOPLEFT", 3, -20)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("LEFT", 30, 0)
    c.title = Font(g.Text(c, "title"), 17, true)
    c.title:SetMaxLines(1)
    c.title:SetPoint("TOPLEFT", 72, -11)
    c.note = Font(g.Text(c, "heading"), 14, true, "strong")
    c.note:SetPoint("TOPLEFT", 72, -36)
    c.note:SetMaxLines(1)
    local function Dropdown(width, pick)
        local d = g.Dropdown(c, width, pick)
        m.ReminderControl(d, "dropdown")
        d:SetHeight(32)
        Font(d.text, 14, true)
        m.Edge(d, "control", 8):SetBackdropBorderColor(0.57, 0.47, 0.33, 0.8)
        return d
    end
    c.value = Dropdown(230, function(v)
        if c.node.type == "kind" or c.node.value ~= nil then B.Do(S().Set(c.node, "value", v)) end
    end)
    c.from = Dropdown(118, function(v) B.Do(S().Set(c.node, "min", v)) end)
    c.to = Dropdown(118, function(v) B.Do(S().Set(c.node, "max", v)) end)
    c.from:SetChoices(Qualities)
    c.to:SetChoices(Qualities)
    c.toWord = Font(g.Text(c, "body"), 14)
    c.toWord:SetText("to")
    c.more = g.Dropdown(c, 36, function(value) MenuPick(c.node, value) end, true)
    m.ReminderControl(c.more, "dropdown")
    c.more:SetHeight(32)
    c.more:SetValue(nil, "···")
    c.more.menuWidth, c.more.menuAlignRight = 280, true
    c.more:SetChoices(function() return c.node and MenuFor(c.node) or {} end)
    m.ContextTip(c.more, "More", "Move this up or down, into another group, duplicate it or remove it.")
    c.remove = g.Button(c, "×", 32, "secondary", function() if c.node then B.Do(S().Remove(c.node)) end end)
    m.ReminderControl(c.remove, "secondary")
    c.remove:SetHeight(32)
    m.ContextTip(c.remove, "Remove", "Takes this condition out of the rule. Undo brings it back.")
    function c:SetDropHot(on) self:SetAlpha(on and 0.75 or 1) end
    m.ContextTip(c, "Condition", function(self)
        local info = self.node and BY_KEY[self.node.type]
        return info and info.name or "", info and info.tip
    end)
    return c
end

local function NewGroup()
    local g, m, pal = G(), M(), G().pal
    local function Font(fs, size, ivory, role) return m.ReminderFont(fs, size, ivory, role) end
    local b = {}
    b.box = CreateFrame("Frame", nil, f.rule.tree)
    m.PanelFace(b.box, "well")
    b.rail = g.Solid(b.box, "ARTWORK", pal.bronzeText, 0.6)
    b.rail:SetWidth(RAIL)
    b.rail:SetPoint("TOPLEFT", 1, -1)
    b.rail:SetPoint("BOTTOMLEFT", 1, 1)
    b.grip = Grip(b.box)
    b.heading = Font(g.Text(b.box, "body"), 15, true, "strong")
    b.heading:SetWordWrap(false)
    b.tag = Font(g.Text(b.box, "small"), 12)
    g.Color(b.tag, pal.stone)
    b.state = Font(g.Text(b.box, "heading"), 13, true, "strong")
    for _, match in ipairs({ "all", "any" }) do
        local seg = m.Segment(b.box, OPERATOR[match].short, 48, function()
            if b.node then B.Do(S().SetMatch(b.node, match)) end
        end)
        m.ContextTip(seg, OPERATOR[match].heading .. " (" .. OPERATOR[match].tag .. ")", OPERATOR[match].tip)
        b[match] = seg
    end
    b.more = g.Dropdown(b.box, 36, function(value) MenuPick(b.node, value) end, true)
    m.ReminderControl(b.more, "dropdown")
    b.more:SetHeight(28)
    b.more:SetValue(nil, "···")
    b.more.menuWidth, b.more.menuAlignRight = 300, true
    b.more:SetChoices(function() return b.node and MenuFor(b.node) or {} end)
    m.ContextTip(b.more, "More", "Move this group, duplicate it or remove it with what is in it.")
    b.remove = g.Button(b.box, "×", 28, "secondary", function() if b.node then B.Do(S().Remove(b.node)) end end)
    m.ReminderControl(b.remove, "secondary")
    b.remove:SetHeight(28)
    m.ContextTip(b.remove, "Remove group", "Removes this group and everything in it. Undo brings it back.")
    b.empty = Font(g.Text(b.box, "small"), 12)
    b.empty:SetWordWrap(true)
    b.add = g.Button(b.box, "Add a condition", 150, "secondary", function()
        if not b.node then return end
        S().SetTarget(b.node)
        B.Refresh()
        if f.search then f.search:SetFocus() end
    end)
    m.ReminderControl(b.add, "target")
    b.add:SetHeight(30)
    m.ContextTip(b.add, "Add a condition", "Chooses this group. The condition you click or drag from the list goes here.")
    return b
end

-- Draws one node and what is inside it. Returns the y below it.
local function Draw(st, node, parent, index, depth, x, w, y)
    local g, m, pal = G(), M(), G().pal
    local trace = ui.test and ui.test.result and ui.test.result.trace
    local tree = f.rule.tree
    if node.type ~= "group" then
        st.card = st.card + 1
        local c = pools.cards[st.card]
        if not c then c = NewCard(); pools.cards[st.card] = c; stats.cards = #pools.cards end
        c.node = node
        c.grip.node = node
        local info = BY_KEY[node.type]
        c:SetSize(w, CARD_H)
        Put(c, tree, x, y)
        ApplyArt(c.icon, node.type, ICON)
        c.title:SetText(info and info.name or "Condition")
        -- controls, right to left: remove, more, the value(s)
        c.remove:ClearAllPoints(); c.remove:SetPoint("RIGHT", c, "RIGHT", -10, 0); c.remove:Show()
        c.more:ClearAllPoints(); c.more:SetPoint("RIGHT", c.remove, "LEFT", -6, 0); c.more:Show()
        c.value:Hide(); c.from:Hide(); c.to:Hide(); c.toWord:Hide()
        local right = -(10 + 32 + 6 + 36 + 12)
        local left
        if node.type == "quality" then
            c.to:ClearAllPoints(); c.to:SetPoint("RIGHT", c, "RIGHT", right, 0); c.to:Show()
            c.to:SetValue(node.max, T().QUALITY[node.max + 1])
            c.toWord:ClearAllPoints(); c.toWord:SetPoint("RIGHT", c.to, "LEFT", -8, 0); c.toWord:Show()
            c.from:ClearAllPoints(); c.from:SetPoint("RIGHT", c.toWord, "LEFT", -8, 0); c.from:Show()
            c.from:SetValue(node.min, T().QUALITY[node.min + 1])
            left = 118 * 2 + 40
        else
            c.value:ClearAllPoints(); c.value:SetPoint("RIGHT", c, "RIGHT", right, 0); c.value:Show()
            if node.type == "kind" or node.type == "armor" then
                local list = node.type == "kind" and T().KINDS or T().ARMOR
                local choices = {}
                for i, k in ipairs(list) do choices[i] = { value = k[1], label = k[2] } end
                c.value:SetChoices(choices)
                local label
                for _, k in ipairs(list) do if k[1] == node.value then label = k[2] end end
                c.value:SetValue(node.value, label)
            else
                local choices = BOOL_CHOICES[node.type] or {}
                c.value:SetChoices(choices)
                for _, choice in ipairs(choices) do if choice.value == node.value then c.value:SetValue(choice.value, choice.label) end end
            end
            left = 230
        end
        c.title:SetWidth(math.max(80, w - 72 - 10 - 32 - 6 - 36 - 12 - left - 10))
        -- a second line: what the tested item did, or what cannot work
        local note, color
        local never = T().Never(node)
        if trace and trace[node] then
            note, color = STATE_WORD[trace[node]], StateColor(trace[node])
        elseif never then
            note, color = "Never matches", pal.danger.text
        end
        c.note:SetShown(note ~= nil)
        if note then c.note:SetText(note); g.Color(c.note, color) end
        c.never = never
        drag:Row(c, parent, index, false)
        return y + CARD_H + GAP_Y
    end

    -- a group
    st.group = st.group + 1
    local b = pools.groups[st.group]
    if not b then b = NewGroup(); pools.groups[st.group] = b; stats.groups = #pools.groups end
    b.node = node
    b.grip.node = node
    local isRoot = parent == nil
    local match = node.match
    local boxTop = y
    local cur = y + 6
    local inner = x + RAIL + INSET
    local cw = w - (RAIL + INSET) - 10
    local function Rel(yAbs) return yAbs - boxTop end
    local target = S().Target() == node
    -- heading
    local hx = 10
    b.grip:SetShown(not isRoot)
    if not isRoot then Put(b.grip, b.box, hx - 5, Rel(cur) + 3); hx = hx + 22 end
    b.heading:SetText(OPERATOR[match].heading)
    b.heading:SetWidth(190)
    Put(b.heading, b.box, hx, Rel(cur) + 8)
    g.Color(b.heading, pal.text)
    b.tag:SetText("(" .. OPERATOR[match].tag .. ")" .. (target and "   · Adding here" or ""))
    Put(b.tag, b.box, hx + (b.heading:GetStringWidth() or 150) + 6, Rel(cur) + 11)
    g.Color(b.tag, target and pal.bronzeText or pal.stone)
    local right = w - 10
    if not isRoot then
        right = right - 28
        b.remove:ClearAllPoints(); b.remove:SetPoint("TOPLEFT", b.box, "TOPLEFT", right, -(Rel(cur) + 3)); b.remove:Show()
        right = right - 42
        b.more:ClearAllPoints(); b.more:SetPoint("TOPLEFT", b.box, "TOPLEFT", right, -(Rel(cur) + 3)); b.more:Show()
    else
        b.remove:Hide(); b.more:Hide()
    end
    for _, m2 in ipairs({ "any", "all" }) do
        right = right - 52
        b[m2]:SetSelected(match == m2)
        Put(b[m2], b.box, right, Rel(cur) + 3)
    end
    local verdict = trace and trace[node]
    b.state:SetShown(verdict ~= nil)
    if verdict then
        b.state:SetText(STATE_WORD[verdict]); g.Color(b.state, StateColor(verdict))
        Put(b.state, b.box, right - 78, Rel(cur) + 9)
    end
    local rail = match == "any" and { 0.46, 0.53, 0.42 } or { 0.57, 0.46, 0.32 }
    b.rail:SetColorTexture(rail[1], rail[2], rail[3], target and 1 or 0.63)
    cur = cur + HEAD_H + 2
    local n = #node.children
    b.empty:SetShown(n == 0)
    if n == 0 then
        b.empty:SetWidth(cw - 12)
        b.empty:SetText(isRoot and "Nothing here yet. A rule with no conditions never marks anything."
            or "Empty: a group with nothing in it never matches. Add a condition or remove it.")
        g.Color(b.empty, isRoot and pal.stone or pal.danger.text)
        Put(b.empty, b.box, RAIL + INSET, Rel(cur))
        cur = cur + (b.empty:GetStringHeight() or 14) + 8
    end
    for i, child in ipairs(node.children) do
        if i > 1 then
            st.sep = st.sep + 1
            local sep = pools.seps[st.sep]
            if not sep then
                sep = m.ReminderFont(g.Text(tree, "meta"), 12, false, "strong")
                g.Color(sep, pal.bronzeText)
                pools.seps[st.sep] = sep
            end
            sep:SetText(OPERATOR[match].sep:upper())
            Put(sep, tree, inner + 8, cur)
            cur = cur + SEP_H
        end
        local firstGroup = st.group
        cur = Draw(st, child, node, i, depth + 1, inner, cw, cur)
        if child.type == "group" then drag:Row(pools.groups[firstGroup + 1].box, node, i, true) end
    end
    -- the one way to add: choose this group, then click or drag from the list
    b.add.text:SetText(n == 0 and "Add the first condition" or "Add a condition")
    b.add:SetWidth(isRoot and (cw) or 170)
    Put(b.add, b.box, RAIL + INSET, Rel(cur))
    cur = cur + 32
    b.box:SetWidth(w)
    b.box:SetHeight(cur - boxTop + 4)
    Put(b.box, tree, x, boxTop)
    drag:Group(b.box, node, n, depth)
    return cur + 8
end

local function HideAll()
    for _, c in ipairs(pools.cards) do c:Hide(); c.node = nil; c.grip.node = nil end
    for _, b in ipairs(pools.groups) do b.box:Hide(); b.node = nil; b.grip.node = nil; b.state:Hide(); b.empty:Hide() end
    for _, sep in ipairs(pools.seps) do sep:Hide() end
end

local function Layout()
    local g, m, pal = G(), M(), G().pal
    local active = S().Active()
    local rows, held = S().Rows()
    drag:ClearTargets()
    HideAll()
    -- the left rail: saved rules, plus the one being created
    local list = {}
    for i, r in ipairs(rows) do list[i] = r end
    if active and S().IsNew() then list[#list + 1] = { index = S().Index(), name = S().Name() or "New rule", on = S().On(), brief = "Not saved yet", unsaved = true } end
    left.count:SetText(held and "Unavailable" or (#rows .. " / " .. L().JUNK_MAX_RULES))
    left.empty:SetShown(#list == 0)
    for i, r in ipairs(list) do
        local row = B.Row(i)
        row.index = (not r.unsaved) and r.index or nil
        row.fullName, row.fullBrief = r.name, r.brief
        row.name:SetText(Truncate(r.unsaved and (S().Name() or "New rule") or r.name, 20))
        local open = active and not r.unsaved and r.index == S().Index()
        row.brief:SetText(Truncate(r.unsaved and "Not saved yet" or (open and S().Dirty()) and "Unsaved changes" or r.brief, 34))
        g.Color(row.brief, (r.unsaved or (open and S().Dirty())) and pal.bronzeText or pal.stone)
        row.pill:SetShown(not r.unsaved)
        row.pill:SetChecked(r.on == true)
        row.sel:SetShown(active and r.index == S().Index())
        row:Show()
    end
    for i = #list + 1, #pools.rows do pools.rows[i]:Hide() end
    local full = math.max(1, #list * ROW)
    left.content:SetHeight(full)
    if left.fitRail then left.fitRail(full) end
    -- keep the chosen rule in view when the list is longer than its window
    if active then
        local at
        for i, r in ipairs(list) do if r.index == S().Index() then at = i end end
        if at and left.shownIndex ~= at then
            local y, old, window = (at - 1) * ROW, left.scroll:GetVerticalScroll() or 0, 272
            if y < old or y + ROW > old + window then left.scroll:SetVerticalScroll(math.max(0, math.min(y, full - window))) end
        end
        left.shownIndex = at
    end
    left.new:SetEnabled(not held and #rows < L().JUNK_MAX_RULES)
    local never = #L().JunkIgnoreList()
    left.protect:SetText(("Never mark list: %d item%s. The Cozy Sleeping Bag, quest items and keys are always protected."):format(never, never == 1 and "" or "s"))

    -- the right side
    f.title:SetText(active and ("Junk rule: " .. (S().Name() or "New rule")) or "Junk marking")
    f.rule.blank:SetShown(not active)
    for _, el in ipairs({ f.rule.name, f.rule.pill, f.rule.onText, f.rule.more, f.rule.delete, f.rule.line, f.rule.heading, f.rule.scroll }) do el:SetShown(active) end
    f.strip:SetShown(true)
    f.search:SetEnabled(active)
    left.summary:SetText(active and S().Summary() or "Choose a rule to see what it does.")
    local problems = active and S().Problems() or {}
    left.sumContent:SetHeight(math.max(20, (left.summary:GetStringHeight() or 20) + 4))
    if left.fitSum then left.fitSum(left.sumContent:GetHeight()) end
    f.undo:SetEnabled(active and S().CanUndo())
    f.redo:SetEnabled(active and S().CanRedo())
    local dirty = active and S().Dirty()
    f.cancel:SetEnabled(dirty)
    f.save:SetEnabled(dirty)
    f.dirty:SetText(dirty and "Unsaved changes" or "No unsaved changes")
    g.Color(f.dirty, dirty and pal.bronzeText or pal.stone)
    if f.undo.PaintIcon then f.undo:PaintIcon() end
    if f.redo.PaintIcon then f.redo:PaintIcon() end
    -- the tested item
    if ui.test and ui.test.revision ~= S().Revision() then B.Retest() end
    local strip = f.strip
    local t = ui.test
    local res = t and t.result
    if res and res.item then
        strip.itemName:SetText(res.item.name or ("Item " .. res.item.id))
        strip.icon:SetTexture(res.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        strip.icon:SetShown(true)
        g.Color(strip.itemName, pal.text)
    else
        strip.itemName:SetText("Choose an item from your bags, or drop one here")
        g.Color(strip.itemName, pal.stone)
        strip.icon:SetShown(false)
    end
    local head, tone, detail = Describe(res)
    if not head then
        head, tone, detail = "No item chosen yet", "none",
            "Choose an item, or drop one here, to see whether this rule matches it and why. Nothing is marked or moved."
    end
    strip.result:SetText(head or "")
    strip.reason:SetText(detail or "")
    local colors = { met = pal.sage, unmet = pal.textDim, unknown = pal.bronzeText, protected = pal.bronzeText }
    g.Color(strip.result, colors[tone] or pal.text)
    g.Color(strip.reason, pal.textDim)
    local sv = ui.survey
    if sv and sv.running then strip.surveyText:SetText("Looking through your bags...")
    elseif sv and sv.unavailable then strip.surveyText:SetText("Needs Item Advisor loaded.")
    elseif sv then
        local stale = sv.revision ~= S().Revision()
        strip.surveyText:SetText(("%d of %d bag items match%s%s"):format(sv.match or 0, sv.items or 0,
            (sv.unknown or 0) > 0 and (" · " .. sv.unknown .. " can't be told") or "",
            stale and " (rule changed since)" or sv.stale and " (bags changed since)" or ""))
    else strip.surveyText:SetText("") end
    strip.surveyText:SetShown(true)
    g.Color(strip.surveyText, pal.textDim)
    strip.survey:SetEnabled(active)
    strip.choose:SetEnabled(active)

    f.rule.name:SetEnabled(active)
    if active then
        if not f.rule.name:HasFocus() then f.rule.name:SetText(S().Name() or "") end
        f.rule.pill:SetChecked(S().On() == true)
        f.rule.onText:SetText(S().On() and "On" or "Off")
        g.Color(f.rule.onText, S().On() and pal.sage or pal.stone)
    end
    B.Palette()
    f.palette.where:SetText(active and ("Adding to: " .. S().GroupLabel(S().Target())) or "Choose a rule first")
    g.Color(f.palette.where, pal.bronzeText)

    if not active then
        f.rule.tree:Hide()
        return
    end
    -- the tree
    local st = { card = 0, group = 0, sep = 0 }
    f.rule.tree:Show()
    local y = Draw(st, S().Tree(), nil, nil, 0, 0, RULE_W - 4, 4)
    -- an empty rule offers examples
    local tm = f.rule.templates
    if not tm then
        tm = {}
        f.rule.templates = tm
        tm.head = m.ReminderFont(g.Text(f.rule.tree, "body"), 14)
        tm.head:SetText("Or start from an example:")
        g.Color(tm.head, pal.textDim)
        tm.buttons = {}
        for i, t2 in ipairs(S().TEMPLATES) do
            local btn = g.Button(f.rule.tree, t2.name, 200, "secondary", function() B.Do(S().Template(t2.key)) end)
            m.ReminderControl(btn, "secondary")
            btn:SetHeight(32)
            m.ContextTip(btn, t2.name, t2.blurb)
            tm.buttons[i] = btn
        end
    end
    local empty = #S().Tree().children == 0
    tm.head:SetShown(empty)
    for i, btn in ipairs(tm.buttons) do
        btn:SetShown(empty)
        if empty then Put(btn, f.rule.tree, 4 + ((i - 1) % 2) * 212, y + 30 + math.floor((i - 1) / 2) * 38) end
    end
    if empty then Put(tm.head, f.rule.tree, 4, y + 4); y = y + 30 + 76 + 8 end
    -- what is wrong, if anything, under the cards
    local pr = f.rule.problem
    if not pr then
        pr = m.ReminderFont(g.Text(f.rule.tree, "small"), 12)
        pr:SetWordWrap(true)
        f.rule.problem = pr
    end
    local warn = problems[1] and problems[1].text
    pr:SetShown(warn ~= nil and not empty)
    if warn and not empty then
        pr:SetWidth(RULE_W - 20)
        pr:SetText(warn)
        g.Color(pr, pal.danger.text)
        Put(pr, f.rule.tree, 4, y)
        y = y + (pr:GetStringHeight() or 14) + 8
    end
    -- what always wins over a matching rule, in the pane where the rule is written
    local wd = f.rule.words
    if not wd then
        wd = CreateFrame("Frame", nil, f.rule.tree)
        m.PanelFace(wd, "espresso")
        wd.head = m.ReminderFont(g.Text(wd, "title"), 15, true)
        wd.head:SetPoint("TOPLEFT", 14, -10)
        wd.head:SetText("Before anything is marked")
        wd.text = m.ReminderFont(g.Text(wd, "body"), 13)
        wd.text:SetPoint("TOPLEFT", 14, -34)
        wd.text:SetWidth(RULE_W - 8 - 28)
        wd.text:SetWordWrap(true)
        wd.text:SetText("This rule only names candidates. An item is still left alone if it is on your Never mark list, is a quest item or key, or has a locked or crafting-reserved copy. Every copy you carry must match.")
        g.Color(wd.text, pal.textDim)
        f.rule.words = wd
    end
    wd:SetSize(RULE_W - 8, 40 + (wd.text:GetStringHeight() or 32) + 8)
    Put(wd, f.rule.tree, 4, y + 6)
    y = y + 6 + wd:GetHeight() + 6
    f.rule.tree:SetHeight(y + 8)
    f.rule.content:SetHeight(y + 8)
    if f.fitRule then f.fitRule(y + 8) end
end

-- Everything is drawn from the draft, after an edit, a click or a test: never per frame.
function B.Refresh()
    if not (f and f:IsShown()) then return end
    local Perf = R.Perf
    if Perf and Perf.Call then Perf.Call("settings.junkBuilder.layout", Layout) else Layout() end
end

-- The pools the window draws into, for the tests.
function B.cards() return pools.cards end
function B.groups() return pools.groups end

-- For TwichUI Diagnostics and the tests: what has been built. Counts only; it reads and changes nothing.
function B.Snapshot()
    return { cards = stats.cards, groups = stats.groups, rows = stats.rows, paletteRows = stats.paletteRows,
        open = B.Shown() and 1 or 0 }
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
if R.OnSettingsClosed then R.OnSettingsClosed(function() if B.Shown() then B.Close() end end) end
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "junk-rule-builder", function()
        -- A profile change replaces the saved rules; the draft no longer has anything to compare with.
        if B.Shown() then B.Close() else S().Cancel() end
    end)
end
