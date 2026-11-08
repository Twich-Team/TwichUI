-- TwichUI: Magic Inventory, the panel at the guild bank window
-- A small strip attached to the guild bank window while it is open (and Magic Inventory is on): what is ready, and the
-- buttons Deposit, Organize bank and Arrangement (with an arrangement for this guild), and Withdraw (with a rule that withdraws
-- from a tab of this guild). Nothing in it moves an item by itself:
--   * opening the bank only makes GuildPrep.lua read the tabs and keep the summary ("Reading bank...", then "12 stacks ready to
--     deposit · 8 stacks to organize");
--   * Deposit or Organize bank makes sure every tab is current, then puts up ONE review (every tab it touches, quantities,
--     what is left out and why). Start is the player's approval of exactly that review (GuildRun.Start checks it is still true);
--   * while it runs the strip shows confirmed progress, Stop, and Continue when the game wants a click;
--   * the result (Completed / Partially completed / Stopped / Needs review) stays until dismissed; Details has the evidence.
-- The panel is built once, the first time the bank opens with the feature on, and reused. It hooks nothing of the game's: it
-- listens to the events Magic Inventory already listens to. It sits just outside the bank window (below it, else above it), so
-- it covers none of the game's controls.

local R = TwichUI
local MI = R.MagicInventory
local GB = MI.GuildBank
local GR = MI.GuildRun
local P = MI.GuildPrep

local Panel = {}
MI.GuildPanel = Panel

local NAME = "TwichUIGuildBankPanel"
local BAR_H, PAD, GAP = 58, 21, 4
local ICON, ICON_GAP, MAX_ICONS = 38, 6, 8
local MIN_W, MAX_W, SIDE_W = 520, 800, 400
local AMBER = { 0.93, 0.72, 0.38 }
local MAX_DETAIL = 14

local f
local review                 -- the review waiting for the player's approval
local awaiting               -- "deposit" | "reorganize" | "withdraw" while the tabs are being made current for a review
local said                   -- one line of explanation (a refused action, a changed plan)
local detailsOpen = false
local dismissed              -- the result the player has dismissed
local queued = false

local function Look() return R.Look end
local function Plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or (many or one .. "s")) end

local OUTCOME = { completed = "Completed", partial = "Partially completed", stopped = "Stopped", review = "Needs review" }
local DOING = { deposit = "Depositing", reorganize = "Organizing", withdraw = "Withdrawing" }
local TITLE = { deposit = "Deposit", reorganize = "Organize", withdraw = "Withdraw" }
local START = { deposit = "Start deposit", reorganize = "Start organizing", withdraw = "Start withdrawal" }

-- the words for why preparation is waiting; every one is something the player is doing or the game is, not a failure
local HOLD = {
    cursor = "Put down what is on your cursor and the bank will be read",
    combat = "Waiting for combat to end",
    mode = "Show the bank's items to read the other tabs",
    navigated = "Paused while you browse tabs",
    run = "A run is in progress",
    limit = "Not every tab was read",
    guild = "This isn't your guild's bank, as far as the game says",
    closed = "The bank is closed",
}

---------------------------------------------------------------------------
-- What the strip says
---------------------------------------------------------------------------
local function Guild() return MI.Plain((IsInGuild and IsInGuild() and GetGuildInfo and (GetGuildInfo("player"))) or nil) end

-- Returns the state of the bar: { kind, text, tone, deposit = { enabled, why }, organize = { enabled, why }, read = bool }
local function Compute()
    local prog = GR.Progress()
    if prog then
        local what = DOING[prog.mode] or "Organizing"
        local text = what .. "\226\128\166"
        if prog.stage == "refresh" then text = "Checking the bank\226\128\166"
        elseif prog.stage == "final" then text = "Checking the result\226\128\166" end
        if prog.needClick then text = what .. " \194\183 your click is needed"
        elseif prog.stopping then text = "Stopping\226\128\166" end
        return { kind = "run", text = text, prog = prog }
    end
    if review then return { kind = "review", text = "Ready when you are" } end
    local status = P.Status()
    if not status.arrangement and not status.withdraw then
        return { kind = "setup", text = ("No arrangement for %s yet"):format((Guild() and ("<" .. Guild() .. ">")) or "this guild") }
    end
    if awaiting or status.reading then
        local text = "Reading bank\226\128\166"
        if status.reading and status.tab and status.total > 0 then text = ("Reading bank\226\128\166 (tab %d)"):format(status.tab) end
        return { kind = "reading", text = text, tone = "dim", status = status }
    end
    local sum = P.Summary()
    if not sum then return { kind = "reading", text = "Reading bank\226\128\166", tone = "dim" } end
    local d, o, w = sum.deposit or {}, sum.organize or {}, sum.withdraw or {}
    local bits = {}
    if (d.moves or 0) > 0 then bits[#bits + 1] = ("%s ready to deposit"):format(Plural(d.moves, "stack")) end
    if (o.moves or 0) > 0 then bits[#bits + 1] = ("%s to organize"):format(Plural(o.moves, "stack")) end
    if (w.moves or 0) > 0 then bits[#bits + 1] = ("%s to withdraw"):format(Plural(w.moves, "stack")) end
    local text
    local lead = status.arrangement and d or w
    if #bits > 0 then text = table.concat(bits, " \194\183 ")
    elseif lead.code == "cursor" or lead.code == "combat" or lead.code == "closed" or lead.code == "mode" then text = lead.text or "Not ready"
    elseif status.arrangement then text = "Nothing to move for your arrangement right now"
    else text = "Nothing to withdraw right now" end
    local missing = {}
    for tab in pairs(status.problems or {}) do missing[#missing + 1] = tab end
    table.sort(missing)
    local tone
    local read = false
    if #missing > 0 then
        local m = {}
        for _, t in ipairs(missing) do m[#m + 1] = tostring(t) end
        text = text .. (" \194\183 tab%s %s not read"):format(#m == 1 and "" or "s", table.concat(m, ", "))
        tone, read = "warn", true
    elseif status.state == "blocked" and HOLD[status.reason] then
        text = text .. " \194\183 " .. HOLD[status.reason]
        tone, read = "warn", status.reason == "limit" or status.reason == "navigated" or status.reason == "mode"
    end
    local function Why(x, label)
        if (x.moves or 0) > 0 then return true end
        if x.code == "nothing" or x.code == nil then return false, "Nothing for " .. label .. " to do right now." end
        return false, x.text
    end
    local de, dw = Why(d, "Deposit")
    local oe, ow = Why(o, "Organize bank")
    local we, ww = Why(w, "Withdraw")
    return { kind = "ready", text = text, tone = tone, read = read, arrangement = status.arrangement, withdrawing = status.withdraw,
        deposit = { enabled = de, why = dw }, organize = { enabled = oe, why = ow }, withdraw = { enabled = we, why = ww } }
end

-- the evidence under Details: one line a move, every tab named (a review), or what the result recorded
local function ReviewDetails(rv)
    local out = {}
    if #rv.tabs > 1 or rv.crossTab > 0 then out[#out + 1] = "The bank window will show each tab in turn while this runs, and your own tab again at the end." end
    local function Name(id) local fa = id and MI.ItemFacts(id); return fa and fa.name or ("item " .. tostring(id)) end
    local function At(w) return w.kind == "bag" and ("bag %d slot %d"):format(w.bag, w.slot) or ("tab %d slot %d"):format(w.tab, w.slot) end
    for i, o in ipairs(rv.ops) do
        if i > MAX_DETAIL then out[#out + 1] = ("\226\128\166 and %d more"):format(#rv.ops - MAX_DETAIL) break end
        out[#out + 1] = ("%s \195\151%d: %s \226\134\146 %s%s"):format(Name(o.id), o.count, At(o.src), At(o.dst), o.cross and " (between tabs)" or "")
    end
    for _, b in ipairs(rv.blockedItems or {}) do
        out[#out + 1] = ("%s \195\151%d \226\128\148 %s"):format(Name(b.id), b.count or 0, b.text or "")
    end
    for _, w in ipairs(rv.ruleNotes or {}) do out[#out + 1] = ("\"%s\" \226\128\148 %s"):format(w.rule, w.why or "") end
    for _, it in ipairs(rv.shortItems or {}) do
        out[#out + 1] = it.short and ("%s: %d short \226\128\148 %s"):format(Name(it.id), it.short, it.text or "") or ("%s \226\128\148 %s"):format(Name(it.id), it.text or "")
    end
    return out
end

---------------------------------------------------------------------------
-- The look: the shared framed look (FrameLook.lua), the treatment approved on this panel
-- The frame, the espresso interior, the action strip's sheen, the deeper recessed result area and the groove where they meet are
-- the shell's; the buttons are the look's. Nothing here takes the mouse, animates or runs per frame, and nothing is saved.
---------------------------------------------------------------------------
local F = R.FrameLook
local _, FT, FR, FB = F.ContentInsets()     -- where content begins inside the frame (top, right, bottom)
local AL, AT, AR, AB = F.RailInsets()       -- where the rails end, inside

-- The frame and its interior on a frame of its own that sits under the content (same level as the panel, so the strip and the block
-- draw over it). The strip's shell has the sheen and the groove; every shell has the recess.
local function MakeShell(parent, strip)
    local s = F.Shell(parent)
    if strip then s:Sheen() end
    s:Recess()
    if strip then s:Groove() end
    s:Fit(BAR_H)
    return s
end

local Button = F.Button

---------------------------------------------------------------------------
-- The frames (built once)
---------------------------------------------------------------------------
local function Build()
    if f then return true end
    local L = Look()
    if not (L and L.Surface and L.Text and L.Recess and F.Ready()) then return false end
    f = CreateFrame("Frame", NAME, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(MIN_W, BAR_H)
    f:Hide()
    f.shell = MakeShell(f, true)            -- the frame around the strip (and the block, when it is joined to the strip)
    f.shellB = MakeShell(f)                 -- the block's own frame, when it sits apart from the strip
    f.shellB:Hide()
    f.bar = CreateFrame("Frame", nil, f)    -- the action strip's inside; Dress() fits it to the shell
    f.bar:SetAllPoints(f)
    f.status = L.Text(f.bar, "body")
    f.status:SetPoint("LEFT", f.bar, "LEFT", PAD, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.arrange = Button(f.bar, "Arrangement\226\128\166", 110, "secondary", function()
        if R.OpenSettings then R:OpenSettings("magicInventory") end
    end)
    f.arrange:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    R.Interact.Tip(f.arrange, "Arrangement", "Opens the arrangement editor: where each item belongs in the guild bank.")
    f.organize = Button(f.bar, "Organize bank", 110, "secondary", function() Panel.Act("reorganize") end)
    f.organize:SetPoint("RIGHT", f.arrange, "LEFT", -8, 0)
    f.deposit = Button(f.bar, "Deposit", 90, "primary", function() Panel.Act("deposit") end)
    f.deposit:SetPoint("RIGHT", f.organize, "LEFT", -8, 0)
    f.setup = Button(f.bar, "Set up arrangement", 150, "primary", function()
        if R.OpenSettings then R:OpenSettings("magicInventory") end
    end)
    f.setup:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    f.withdraw = Button(f.bar, "Withdraw", 90, "secondary", function() Panel.Act("withdraw") end)
    R.Interact.Tip(f.withdraw, "Withdraw", function()
        if f.withdraw.why then return f.withdraw.why end
        return "Takes whole stacks out of the tabs your withdrawing rules name, into your bags, up to each rule's target and never past it. You review, then approve."
    end)
    f.read = Button(f.bar, "Read again", 90, "secondary", function() Panel.ReadAgain() end)
    R.Interact.Tip(f.read, "Read again", "Reads the tabs that were not read, one at a time. Nothing moves.")
    f.stop = Button(f.bar, "Stop", 80, "danger", function() GR.Stop() end)
    f.stop:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    R.Interact.Tip(f.stop, "Stop", "Ends the run after the move in progress. Nothing already moved is undone.")
    f.go = Button(f.bar, "Continue", 90, "primary", function() GR.Continue() end)
    f.go:SetPoint("RIGHT", f.stop, "LEFT", -8, 0)
    R.Interact.Tip(f.go, "Continue", "The game asked for a click before this move. One move per click.")
    for _, key in ipairs({ "deposit", "organize" }) do
        local b = f[key]
        R.Interact.Tip(b, key == "deposit" and "Deposit" or "Organize bank", function()
            if b.why then return b.why end
            if key == "deposit" then return "Moves eligible items from your bags into the tabs your arrangement names. You review, then approve." end
            return "Moves items already in the guild bank to where your arrangement wants them, including between tabs. You review, then approve."
        end)
    end

    f.detail = CreateFrame("Frame", nil, f)
    f.title = L.Text(f.detail, "title")                 -- the one big line: what this is, or how it went
    f.title:SetJustifyH("LEFT")
    f.sub = L.Text(f.detail, "body")                    -- one short line under it
    f.sub:SetJustifyH("LEFT")
    f.warn = L.Text(f.detail, "body")                   -- what needs a look, in amber, one short line
    f.warn:SetJustifyH("LEFT")
    f.more = L.Text(f.detail, "small")                  -- Details: the evidence, only when asked for
    f.more:SetJustifyH("LEFT")
    f.more:SetSpacing(2)
    f.icons = {}
    for i = 1, MAX_ICONS + 1 do
        local b = CreateFrame("Frame", nil, f.detail, "BackdropTemplate")
        b:SetSize(ICON, ICON)
        L.Surface(b, L.pal.well, 1, L.pal.bronzeLo, 0.9)
        L.Recess(b)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.count = L.Text(b, "body")
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.count:SetJustifyH("RIGHT")
        b.count:SetShadowColor(0, 0, 0, 1)
        b.count:SetShadowOffset(1, -1)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            if self.tip2 then GameTooltip:AddLine(self.tip2, AMBER[1], AMBER[2], AMBER[3], true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        f.icons[i] = b
    end
    -- the progress bar: a track, a fill and the count, drawn from textures (no template)
    f.progress = CreateFrame("Frame", nil, f.detail, "BackdropTemplate")
    f.progress:SetHeight(26)
    L.Surface(f.progress, L.pal.well, 1, L.pal.bronzeLo, 0.9)
    L.Recess(f.progress)
    f.progress.fill = f.progress:CreateTexture(nil, "ARTWORK")
    f.progress.fill:SetPoint("TOPLEFT", 2, -2)
    f.progress.fill:SetPoint("BOTTOMLEFT", 2, 2)
    f.progress.fill:SetWidth(1)
    f.progress.fill:SetColorTexture(L.pal.tealHi[1], L.pal.tealHi[2], L.pal.tealHi[3], 0.9)
    f.progress.text = L.Text(f.progress, "title")
    f.progress.text:SetPoint("CENTER", 0, 0)
    f.progress:Hide()
    f.curIcon = f.detail:CreateTexture(nil, "ARTWORK")
    f.curIcon:SetSize(24, 24)
    f.curIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cur = L.Text(f.detail, "body")                    -- the move in progress: "Linen Cloth > Cloth"
    f.cur:SetJustifyH("LEFT")
    f.start = Button(f.detail, "Start", 130, "primary", function() Panel.Start() end)
    f.cancel = Button(f.detail, "Cancel", 80, "secondary", function() Panel.Cancel() end)
    f.details = Button(f.detail, "Details", 80, "secondary", function() detailsOpen = not detailsOpen; Panel.Refresh() end)
    f.dismiss = Button(f.detail, "Dismiss", 80, "secondary", function() Panel.Dismiss() end)
    return true
end

local function Tone(fs, tone)
    local L, pal = Look(), Look().pal
    if tone == "warn" then L.Color(fs, AMBER)
    elseif tone == "dim" then L.Color(fs, pal.textDim)
    else L.Color(fs, pal.text) end
end

local function Edge(frame, name, default)
    local fn = frame and frame[name]
    local v = type(fn) == "function" and fn(frame) or nil
    return type(v) == "number" and v or default
end

-- The strip: below the bank window, else above it, else a quiet place at the top of the screen (another addon draws the bank).
-- Returns its width. f.near: "top" (below the window), "bottom" (above it) or nil (not attached).
local function PlaceBar()
    f:ClearAllPoints()
    f.near = nil
    local host = _G.GuildBankFrame
    local w = MIN_W
    if type(host) == "table" and host.IsShown and host:IsShown() then
        w = math.min(MAX_W, math.max(MIN_W, Edge(host, "GetWidth", MIN_W)))
        local bottom, top = Edge(host, "GetBottom", 0), Edge(host, "GetTop", 0)
        local screenTop = Edge(UIParent, "GetTop", Edge(UIParent, "GetHeight", 0))
        if bottom >= BAR_H + GAP * 2 then f:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -GAP); f.near = "top"
        elseif screenTop - top >= BAR_H + GAP * 2 then f:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, GAP); f.near = "bottom" end
    end
    if not f.near then f:SetPoint("TOP", UIParent, "TOP", 0, -110) end
    f:SetSize(w, BAR_H)
    return w
end

-- The review or result block: joined to the strip when the screen has room on that side, else beside the bank window (right,
-- then left), and only when there is room nowhere on top of the strip's own side (the last resort, which can cover the window).
-- fill(width, joined) lays the text out for a width (joined to the strip or not: the frame's rail is on one side less) and returns the block's height. Returns true when the block is joined to the strip
-- (no gap: one frame around both), nil when it sits apart.
local function PlaceDetail(barW, fill)
    local host = _G.GuildBankFrame
    local d = f.detail
    d:ClearAllPoints()
    local h = fill(barW, true)
    local attached = type(host) == "table" and host.IsShown and host:IsShown()
    if attached then
        local bottom, top = Edge(host, "GetBottom", 0), Edge(host, "GetTop", 0)
        local screenTop = Edge(UIParent, "GetTop", Edge(UIParent, "GetHeight", 0))
        if f.near == "top" and bottom - BAR_H - GAP * 2 >= h + GAP then
            d:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0); d:SetWidth(barW); d:SetHeight(h)
            return true
        elseif f.near == "bottom" and screenTop - top - BAR_H - GAP * 2 >= h + GAP then
            d:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0); d:SetWidth(barW); d:SetHeight(h)
            return true
        end
        local left, right = Edge(host, "GetLeft", 0), Edge(host, "GetRight", 0)
        local screenRight = Edge(UIParent, "GetRight", Edge(UIParent, "GetWidth", 0))
        h = fill(SIDE_W, false)
        if screenRight - right >= SIDE_W + GAP then
            d:SetPoint("TOPLEFT", host, "TOPRIGHT", GAP, 0); d:SetWidth(SIDE_W); d:SetHeight(h)
            return
        elseif left >= SIDE_W + GAP then
            d:SetPoint("TOPRIGHT", host, "TOPLEFT", -GAP, 0); d:SetWidth(SIDE_W); d:SetHeight(h)
            return
        end
        h = fill(barW, true)
    end
    -- nowhere beside the window: the block takes the strip's own side (it may overlap what is there)
    if f.near == "bottom" then d:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0) else d:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0) end
    d:SetWidth(barW); d:SetHeight(h)
    return true
end

-- Fits the frames to what is shown. Joined: one shell around strip and block, the strip and block each fitted to its inside with a
-- quiet groove where they meet. Apart (or no block): the strip's shell alone, and the block's own shell.
local function Dress(joined)
    local d = f.detail
    local shown = d:IsShown()
    joined = joined and shown
    local above = joined and f.near == "bottom"                 -- the block is above the strip
    f.shell:ClearAllPoints()
    if joined and above then
        f.shell:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0); f.shell:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    elseif joined then
        f.shell:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.shell:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
    else
        f.shell:SetAllPoints(f)
    end
    f.shellB:ClearAllPoints()
    if shown and not joined then f.shellB:SetAllPoints(d); f.shellB:Show() else f.shellB:Hide() end
    f.shell:Fit(joined and (BAR_H + d:GetHeight()) or BAR_H)
    f.shellB:Fit(d:GetHeight())
    -- the strip's inside: the frame on its outer sides, the groove on the side it shares with the block
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -((joined and above) and 0 or FT))
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, (joined and not above) and 0 or FB)
    f.shell:Sheen():Place(f.bar, AL, 0, AR, 0)
    -- the block's inside is drawn by the shell that holds it
    local s = joined and f.shell or f.shellB
    f.shell:Recess():SetShown(joined)
    f.shellB:Recess():SetShown(shown and not joined)
    f.shell:Groove():SetShown(joined)
    if not shown then return end
    s:Recess():Place(d, AL, (joined and not above) and 2 or AT, AR, (joined and above) and 2 or AB)
    if joined then s:Groove():Place(d, above and "BOTTOM" or "TOP", 0, AL, AR) end
end


-- the words and pictures of the block under the strip, for what is going on: a review waiting, a run, the last result, or a line
-- of explanation. Short on purpose: the evidence is under Details.
local function ItemName(id) local fa = id and MI.ItemFacts(id); return fa and fa.name or ("item " .. tostring(id)) end
local function ItemIcon(id) local fa = id and MI.ItemFacts(id); return fa and fa.icon or "Interface\\Icons\\INV_Misc_QuestionMark" end

local function TabNames(rv)
    local names = {}
    for _, tab in ipairs(rv.tabs) do
        local t = rv.tabInfo[tab]
        names[#names + 1] = (t and t.name) or ("tab " .. tab)
    end
    if #names <= 1 then return names[1] or "the bank" end
    local last = table.remove(names)
    return table.concat(names, ", ") .. " and " .. last
end

local function Content(state, result)
    local c = { icons = {} }
    if state.kind == "run" then
        local prog = state.prog
        c.run = true
        c.title = DOING[prog.mode] or "Organizing"
        if prog.stage == "refresh" then c.title = "Checking the bank" elseif prog.stage == "final" then c.title = "Checking the result" end
        c.frac = prog.stage == "final" and 1 or (prog.total > 0 and prog.confirmed / prog.total or 0)
        c.barText = prog.stage == "refresh" and "\226\128\166" or ("%d of %d"):format(prog.confirmed, prog.total)
        if prog.current and prog.stage == "ops" then
            c.cur = { id = prog.current.id, text = ("%s \195\151%d"):format(ItemName(prog.current.id), prog.current.count) }
        end
        if prog.needClick then c.warn = "The game wants a click: press Continue."
        elseif prog.stopping then c.warn = "Stopping after this move."
        elseif prog.reading then c.warn = ("Reading tab %d\226\128\166"):format(prog.reading) end
    elseif state.kind == "reading" and state.status and state.status.total > 0 then
        -- reading the bank: a bar of the tabs that are read (the shown tab and the ones already asked for count)
        local stt = state.status
        c.run = true
        c.title = "Reading the bank"
        c.frac = math.min(1, stt.done / stt.total)
        c.barText = ("%d of %d tabs"):format(math.min(stt.done, stt.total), stt.total)
    elseif state.kind == "review" and review then
        local rv = review
        c.review, c.hasDetails = true, true
        c.title = TITLE[rv.mode] or "Organize"
        c.sub = (rv.mode == "deposit" and "%s into %s" or (rv.mode == "withdraw" and "%s from %s into your bags" or "%s in %s")):format(Plural(rv.moves, "stack"), TabNames(rv))
        for _, it in ipairs(rv.items) do c.icons[#c.icons + 1] = { id = it.id, qty = it.qty } end
        c.more = #rv.itemsMore
        local bits = {}
        if rv.crossTab > 0 then bits[#bits + 1] = ("%d between tabs"):format(rv.crossTab) end
        if #rv.dropped > 0 then bits[#bits + 1] = ("%d left out"):format(#rv.dropped) end
        if rv.planBlocked > 0 then bits[#bits + 1] = ("%d blocked"):format(rv.planBlocked) end
        if #(rv.shortItems or {}) > 0 then bits[#bits + 1] = ("%s short of %s"):format(Plural(#rv.shortItems, "item"), #rv.shortItems == 1 and "its target" or "their targets") end
        if #rv.unread > 0 then bits[#bits + 1] = ("tab%s %s not read"):format(#rv.unread == 1 and "" or "s", table.concat(rv.unread, ", ")) end
        if #bits > 0 then c.note = table.concat(bits, " \194\183 ") end
        c.warn = said
        c.start = START[rv.mode] or "Start organizing"   -- a partial plan says so in the line above (what is left out)
    elseif state.kind ~= "run" and result then
        c.result, c.hasDetails = true, #result.lines > 0
        c.title = OUTCOME[result.outcome] or result.outcome
        c.good = result.outcome == "completed"
        c.sub = ("%d of %d stacks moved"):format(result.confirmed, result.total)
        local seen, order = {}, {}
        for _, o in ipairs(result.ops) do
            local e = seen[o.id]
            if not e then e = { id = o.id, qty = 0, state = "ok" }; seen[o.id] = e; order[#order + 1] = e end
            if o.status == "confirmed" then e.qty = e.qty + o.count
            elseif o.status == "uncertain" then e.state = "warn"
            elseif e.state ~= "warn" then e.state = "dim" end
        end
        for _, e in ipairs(order) do c.icons[#c.icons + 1] = e end
        local bits = {}
        if result.reason and not c.good then bits[#bits + 1] = result.reason:gsub("^%l", string.upper) end
        if result.unreadTabs and #result.unreadTabs > 0 then bits[#bits + 1] = Plural(#result.unreadTabs, "tab") .. " not read" end
        if result.cursor then
            local w = result.cursor.where
            bits[#bits + 1] = ("Your cursor holds %s: put it back in %s"):format(ItemName(result.cursor.id), w.kind == "bag" and ("bag %d slot %d"):format(w.bag, w.slot) or ("tab %d slot %d"):format(w.tab, w.slot))
        end
        if #bits > 0 then c.warn = table.concat(bits, " \194\183 ") end
        c.dismiss = true
    elseif said then
        c.say, c.warn = true, said
    end
    return c
end

local function Layout(state)
    local barW = PlaceBar()
    local L, pal = Look(), Look().pal
    local result = GR.Last()
    if result and result == dismissed then result = nil end
    local c = Content(state, result)
    if not (c.run or c.review or c.result or c.say) then f.progress:Hide(); f.detail:Hide(); Dress(false) return end
    f.detail:Show()
    -- what is shown
    f.title:SetText(c.title or "")
    if c.good then L.Color(f.title, pal.sage) elseif c.result then L.Color(f.title, AMBER) else L.Color(f.title, pal.text) end
    f.sub:SetText(c.sub or "")
    L.Color(f.sub, pal.textDim)
    local warn = c.warn
    if c.note and c.review then warn = warn and (c.note .. " \194\183 " .. warn) or c.note end
    f.warn:SetText(warn or "")
    L.Color(f.warn, AMBER)
    local details = c.hasDetails and detailsOpen
    if details and c.review then f.more:SetText(table.concat(ReviewDetails(review), "\n"))
    elseif details and c.result then
        local det = {}
        for i, l in ipairs(result.lines) do
            if i > MAX_DETAIL then det[#det + 1] = ("\226\128\166 and %d more lines"):format(#result.lines - MAX_DETAIL) break end
            det[#det + 1] = l
        end
        f.more:SetText(table.concat(det, "\n"))
    else f.more:SetText("") end
    if c.review then f.start.text:SetText(c.start); f.start:SetWidth(math.max(130, #c.start * 8 + 28)) end
    f.start:SetShown(c.review == true); f.cancel:SetShown(c.review == true); f.dismiss:SetShown(c.dismiss == true or c.say == true)
    f.progress:SetShown(c.run == true)
    if c.run then
        f.progress.text:SetText(c.barText)
        f.curIcon:SetShown(c.cur ~= nil); f.cur:SetShown(c.cur ~= nil)
        if c.cur then f.curIcon:SetTexture(ItemIcon(c.cur.id)); f.cur:SetText(c.cur.text) end
    else
        f.curIcon:Hide(); f.cur:Hide()
    end
    -- the icons: what is moving (or moved), with its quantity; a tile for the rest
    local nIcons = math.min(#c.icons, MAX_ICONS)
    for i, b in ipairs(f.icons) do
        local e = c.icons[i]
        if i <= nIcons and e then
            b.tex:SetTexture(ItemIcon(e.id))
            b.count:SetText((e.qty or 0) > 1 and tostring(e.qty) or "")
            b.tex:SetAlpha(e.state == "dim" and 0.4 or 1)
            local edge = e.state == "warn" and AMBER or pal.bronzeLo
            b:SetBackdropBorderColor(edge[1], edge[2], edge[3], e.state == "warn" and 1 or 0.9)
            b.tip = ("%s%s"):format(ItemName(e.id), (e.qty or 0) > 1 and (" \195\151" .. e.qty) or "")
            b.tip2 = e.state == "warn" and "Not confirmed" or (e.state == "dim" and "Not moved" or nil)
            b:Show()
        elseif i == nIcons + 1 and ((c.more or 0) > 0 or #c.icons > MAX_ICONS) then
            b.tex:SetTexture(nil)
            b.count:SetText("+" .. ((c.more or 0) + math.max(0, #c.icons - MAX_ICONS)))
            b.tip, b.tip2 = nil, nil
            b:SetBackdropBorderColor(pal.bronzeLo[1], pal.bronzeLo[2], pal.bronzeLo[3], 0.9)
            b:Show()
        else
            b:Hide()
        end
    end
    local overflow = ((c.more or 0) > 0 or #c.icons > MAX_ICONS) and 1 or 0
    local shownIcons = nIcons + overflow

    -- laid out for a width; returns the block's height
    local function Fill(width, joined)
        local textW = width - PAD * 2
        local above = joined and f.near == "bottom"      -- the block is above the strip: its lower edge is the shared one
        local ti = (joined and not above) and 10 or FT + 8
        local bi = above and 10 or FB + 8
        local y = ti
        local function Line(fs, gap)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            fs:SetWidth(textW)
            if (fs:GetText() or "") == "" then fs:Hide() return end
            fs:Show()
            y = y + (fs:GetStringHeight() or 14) + (gap or 4)
        end
        Line(f.title, 4)
        Line(f.sub, 8)
        if shownIcons > 0 then
            local per = math.max(1, math.floor((textW + ICON_GAP) / (ICON + ICON_GAP)))
            for i = 1, shownIcons do
                local b = f.icons[i]
                local col, row = (i - 1) % per, math.floor((i - 1) / per)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD + col * (ICON + ICON_GAP), -(y + row * (ICON + ICON_GAP)))
            end
            y = y + math.ceil(shownIcons / per) * (ICON + ICON_GAP) + 4
        end
        if c.run then
            f.progress:ClearAllPoints()
            f.progress:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            f.progress:SetWidth(textW)
            f.progress.fill:SetWidth(math.max(1, math.floor((textW - 4) * math.min(1, math.max(0, c.frac or 0)))))
            f.progress.fill:SetShown((c.frac or 0) > 0)
            y = y + 26 + 10
            if c.cur then
                f.curIcon:ClearAllPoints(); f.curIcon:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
                f.cur:ClearAllPoints(); f.cur:SetPoint("LEFT", f.curIcon, "RIGHT", 8, 0); f.cur:SetWidth(textW - 32)
                y = y + 24 + 8
            end
        end
        Line(f.warn, 8)
        Line(f.more, 8)
        f.start:ClearAllPoints(); f.cancel:ClearAllPoints(); f.details:ClearAllPoints(); f.dismiss:ClearAllPoints()
        if c.review or c.dismiss or c.say then
            if c.review then
                f.start:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
                f.cancel:SetPoint("LEFT", f.start, "RIGHT", 6, 0)
            else
                f.dismiss:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            end
            if c.hasDetails then
                f.details.text:SetText(detailsOpen and "Hide details" or "Details")
                f.details:SetWidth(math.max(80, #f.details.text:GetText() * 8 + 24))
                f.details:Show()
                f.details:SetPoint("TOPRIGHT", f.detail, "TOPRIGHT", -PAD, -y)
            else
                f.details:Hide()
            end
            y = y + 26 + 4
        else
            f.details:Hide()
        end
        return y + bi - 4
    end
    Dress(PlaceDetail(barW, Fill))
end

---------------------------------------------------------------------------
-- Drawing (coalesced: any number of events is one redraw)
---------------------------------------------------------------------------
local function Open()
    if not (MI.Enabled() and GB.IsOpen()) then return false end
    local frame = _G.GuildBankFrame
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end   -- (whatever the events said)
    return true
end

local function Draw()
    queued = false
    if not Open() then
        if f then f:Hide() end
        return
    end
    if not Build() then return end
    local st = Compute()
    f:Show()
    f.status:SetText(st.text)
    Tone(f.status, st.tone)
    for _, key in ipairs({ "deposit", "organize", "withdraw", "arrange", "setup", "read", "stop", "go" }) do f[key]:Hide() end
    local busy = st.kind == "run"
    if st.kind == "run" then
        f.stop:Show(); f.stop.text:SetText(st.prog.stopping and "Stopping\226\128\166" or "Stop"); f.stop:SetEnabled(not st.prog.stopping)
        if st.prog.needClick then f.go:Show() end
    elseif st.kind == "setup" then
        f.setup:Show()
    else
        local status = P.Status()
        local arranged, withdrawing = status.arrangement, status.withdraw
        local locked = st.kind == "reading" or st.kind == "review"
        local lockedWhy = locked and (st.kind == "review" and "Finish or cancel the review first." or "Reading the bank first.") or nil
        -- with an arrangement: Arrangement, Organize bank, Deposit; without one: Set up arrangement. Withdraw to their left.
        local leftmost
        if arranged then
            f.arrange:Show()
            f.deposit:Show(); f.organize:Show()
            local d, o = st.deposit or {}, st.organize or {}
            f.deposit:SetEnabled(not locked and d.enabled == true)
            f.organize:SetEnabled(not locked and o.enabled == true)
            f.deposit.why = lockedWhy or d.why
            f.organize.why = lockedWhy or o.why
            leftmost = f.deposit
        else
            f.setup:Show()
            leftmost = f.setup
        end
        if withdrawing then
            local w = st.withdraw or {}
            f.withdraw:Show()
            f.withdraw:ClearAllPoints()
            f.withdraw:SetPoint("RIGHT", leftmost, "LEFT", -8, 0)
            f.withdraw:SetEnabled(not locked and w.enabled == true)
            f.withdraw.why = lockedWhy or w.why
            leftmost = f.withdraw
        end
        f.read:ClearAllPoints()
        f.read:SetPoint("RIGHT", leftmost, "LEFT", -8, 0)
        if st.read and not locked then f.read:Show(); leftmost = f.read end
        st.leftmost = leftmost
    end
    f.status:ClearAllPoints()
    f.status:SetPoint("LEFT", f.bar, "LEFT", PAD, 0)
    local rightmost = busy and (st.prog.needClick and f.go or f.stop) or (st.kind == "setup" and f.setup) or st.leftmost or f.deposit
    f.status:SetPoint("RIGHT", rightmost, "LEFT", -8, 0)
    Layout(st)
end

function Panel.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        local ok, err = pcall(Draw)
        if not ok then queued = false; R.Fault("magic inventory guild panel", err) end
    end)
end

---------------------------------------------------------------------------
-- The player's actions
---------------------------------------------------------------------------
function Panel.Act(mode)
    if review or awaiting or GR.Busy() or not Open() then return end
    said, dismissed = nil, GR.Last()
    awaiting = mode
    Panel.Refresh()
    -- the tabs are made current first (immediately when they already are), then ONE review is made from them
    P.EnsureFresh(function(ok, state, reason)
        awaiting = nil
        if not Open() then Panel.Refresh() return end
        local rv = GR.Review(mode)
        if rv.ok then
            review, said = rv, nil
        else
            review = nil
            said = rv.refuse.text
            if state == "blocked" and HOLD[reason] and rv.refuse.code == "unread" then said = HOLD[reason] .. "." end
        end
        Panel.Refresh()
    end)
end

function Panel.Cancel()
    review, said = nil, "Nothing was moved."
    Panel.Refresh()
end

function Panel.Dismiss()
    said, dismissed = nil, GR.Last()
    review = nil
    detailsOpen = false
    Panel.Refresh()
end

function Panel.ReadAgain()
    P.EnsureFresh(function() Panel.Refresh() end)
    Panel.Refresh()
end

-- The approval: exactly the review on the panel, or nothing. A changed bank or rules gives a NEW review to read.
function Panel.Start()
    local rv = review
    if not rv or GR.Busy() then return end
    local ok, code, text, fresh = GR.Start(rv)
    if ok then
        review, said, dismissed = nil, nil, nil
        detailsOpen = false
    else
        review = (fresh and fresh.ok) and fresh or nil
        said = text .. (review and " The new plan is below." or "")
    end
    Panel.Refresh()
end

-- read only, for the tests and the diagnostics
function Panel.Review() return review end
function Panel.FrameCount()
    if not f then return 0 end
    return 5 + (MAX_ICONS + 1) + 1 + 11
end
function Panel.Visible() return f ~= nil and f:IsShown() end
function Panel.DetailFrame() return f and f.detail end
-- the progress bar as drawn: { shown, text, fill (pixels), track (pixels) }
function Panel.Progress()
    if not f then return nil end
    return { shown = f.detail:IsShown() and f.progress:IsShown(), text = f.progress.text:GetText(), fill = f.progress.fill:IsShown() and f.progress.fill:GetWidth() or 0,
        track = (f.progress:GetWidth() or 0) - 4 }
end
function Panel.Texts()
    if not f then return nil end
    return { status = f.status:GetText(), title = f.title:GetText(), sub = f.sub:GetText(), warn = f.warn:GetText(), more = f.more:GetText() }
end

---------------------------------------------------------------------------
-- Events: redraw when anything the strip says may have changed
---------------------------------------------------------------------------
GB.Watch(function(what)
    if what == "close" then
        review, awaiting, said, dismissed, detailsOpen = nil, nil, nil, nil, false
    end
    Panel.Refresh()
end)
P.OnUpdate(function() Panel.Refresh() end)
GR.OnUpdate(function(what)
    if what == "done" then
        local res = GR.Last()
        -- the plan changed before anything moved: its new review is put up to read and approve, never started
        if res and res.fresh and res.code == "stale" then
            review, dismissed = res.fresh, res
            said = "The bank, your bags or your rules changed since the review, so nothing was moved. The new plan is below."
        end
    end
    Panel.Refresh()
end)
MI.OnChange(function()
    if review and review.fingerprint then
        -- a rules change withdraws a review that was made from the old rules (Start would refuse it anyway)
        review, said = nil, "Your rules changed, so that review was withdrawn."
    end
    Panel.Refresh()
end)

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.guildPanel", { label = "Magic Inventory guild bank panel (frames)", unit = "count", kind = "pool",
        read = function() return Panel.FrameCount() end })
end
