-- TwichUI Layout Setup: the window
-- One window, built the first time it is opened and kept; its pages are built when first shown (Pages.lua). It is drawn
-- with TwichUI's own look (R.Look), so it is complete without EllesmereUI or any other addon, and it closes with Escape
-- through the game's own list of frames Escape closes (never RegisterGameMenuEscHandler: an addon calling that taints
-- the game's Escape path, see the settings window).
--
-- While it is open it listens for four events (combat starting and ending, the screen's size and the UI scale changing),
-- on one frame of its own, and stops listening when it closes. Nothing here runs while it is closed. Closing drops
-- everything the model worked out (the plan holds the payload it would import) and changes nothing in the game.
-- Closing a first-install setup (Onboarding.lua) without an answer puts it off, as "Do this later" does.
--
-- The dimming: while the window is shown, one full-screen frame behind it (the scrim) darkens the game a little, so the
-- setup is plainly what is in front. It is a texture on a frame that takes no mouse and no keyboard (clicks go through to
-- the world), anchored to UIParent (so it follows the screen size and UI scale by itself), at the bottom of the window's
-- strata: the window, its tooltips, the game's dialogs (Apply's question included) and everything above that strata stay
-- clear and usable. It fades in briefly unless "Reduce window motion" is on, lifts during combat, is put away the moment
-- the window hides (Escape, Close, the full-size preview, which has its own, an error while opening), and is made once.
--
-- The only things that change the game are a few buttons, each after a confirmation that names the exact scope, each
-- refused in combat by the model and again by the engine: Apply (labelled Apply & Reload when the plan needs a reload: the
-- question says so, and accepting it authorises the apply and the reload that finishes it), Restore, Undo this update, Keep the
-- update (removes the copy an update kept), and the reload the player starts for those.
--
-- The result step is not a step of the wizard: it is a compact, content-sized dialog (no stepper, no footer) in the same window,
-- made by Pages.lua from the same M.Result, and "Set up again" is the way back into the full six steps. Done only closes it.
--
--   Window.Open(step)   opens it (on a step, or where the model says); Window.Close(), Window.Toggle(), Window.IsShown()
--   Window.Refresh()    draws the current step again from the model
--   Window.Suspend()    sets the window aside for the full-size preview (Overlay.lua) without ending the session;
--   Window.Resume()     brings it back where it was. Closing while set aside ends the session as closing always does.

local R = TwichUI
local WZ = R.LayoutWizard
local M = WZ.Model
local W = {}
WZ.Window = W

local FRAME_NAME = "TwichUILayoutWizard"
local WIDTH, HEIGHT = 780, 590
local HEADER_H, PAD, STEPPER_H, FOOTER_H = 44, 16, 30, 54
local COMPACT_W, COMPACT_MIN_H, COMPACT_MAX_H = 520, 240, 600   -- the result dialog: a width of its own, a height that follows its content
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }
local SCRIM_NAME = "TwichUILayoutWizardScrim"
W.SCRIM_ALPHA = 0.40                          -- how dark the dimming is (the game stays plainly visible)
W.SCRIM_COLOR = { 0.035, 0.030, 0.025 }        -- warm charcoal, not black

local win, scroll, content, stepper, footer, evframe, scrim, scrimFade
local suspended = false   -- hidden for the full-size preview: the session goes on
local closeWhy            -- what closed it (Do this later, Skip, ...), for the first-install record
local aborting = false    -- an error while opening is being cleaned up: the close is not an answer
local resuming = false    -- shown again after the full-size preview: no fade-in for the dimming
local compact = false     -- the result step: a small content-sized dialog instead of the six-step window
local pageNote            -- a sentence for the compact dialog (why a button did nothing), until the next redraw
local complete = false    -- Build ran to its end (an error part way builds again at the next open)
local pages = {}
W.pages = pages       -- read by the tests
W.frames = 0          -- frames made, for the troubleshooting report
W.listening = 0       -- events registered now (0 while closed)
W.builds = 0          -- times the window was built (1 once opened; never more)

local function Look() return R.Look end

local function Say(fmt, ...) R.Print("layout setup: " .. fmt, ...) end

function W.IsShown() return win ~= nil and win:IsShown() end
function W.IsCompact() return compact end

-- Says why a button did nothing: in the footer's note (the six steps) or on the compact dialog, until it is next drawn.
function W.Note(text)
    if compact then
        pageNote = text
        W.Refresh(true)
    elseif footer then
        footer.note:SetText(text or "")
    end
end

---------------------------------------------------------------------------
-- The dimming behind the window (made once, with the window)
---------------------------------------------------------------------------
local function BuildScrim()
    if scrim then return end
    scrim = CreateFrame("Frame", SCRIM_NAME, UIParent)
    scrim:SetAllPoints(UIParent)
    scrim:SetFrameStrata("HIGH")
    scrim:SetFrameLevel(0)
    scrim:EnableMouse(false)
    if scrim.EnableKeyboard then scrim:EnableKeyboard(false) end
    scrim:Hide()
    local c = W.SCRIM_COLOR
    local tex = scrim:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(scrim)
    tex:SetColorTexture(c[1], c[2], c[3], W.SCRIM_ALPHA)
    scrim.tex = tex
    scrimFade = Look().Motion.Fader(function(a) scrim:SetAlpha(a) end, 0)
    W.frames = W.frames + 2
end

-- Shown while the window is (not set aside, not in combat); hidden otherwise, at once. fade: ease it in (an opening).
local function Dim(fade)
    if not scrim then return end
    local want = win ~= nil and win:IsShown() and not suspended and not aborting and not InCombatLockdown()
    if want then
        if not scrim:IsShown() then
            scrim:Show()
            if fade then scrimFade:Set(0) scrimFade:To(1, Look().Motion.TIME.window) else scrimFade:Set(1) end
        end
    elseif scrim:IsShown() then
        scrimFade:Set(0)
        scrim:Hide()
    end
end
function W.Scrim() return scrim end   -- read by the tests

-- The first-install record (Onboarding.lua, in the core) is told when the window opens and closes.
local function Onboarding() return R.Onboarding end

---------------------------------------------------------------------------
-- Confirmed actions (the only changes the wizard can make to the game)
---------------------------------------------------------------------------
local function Fail(code, extra)
    Say("nothing was changed: %s", M.ApplyReason(code, extra))
end

local Actions = {}

function Actions.apply()
    local can, code, blocked = M.CanApply()
    if not can then
        footer.note:SetText(M.ApplyReason(code, blocked))
        return
    end
    local text, shown, c = M.ConfirmText()
    R.Interact.Confirm("TWICHUI_LAYOUT_APPLY", text, function()
        -- one authorised action: the apply and, when the question said so, the reload that finishes it (Model.ApplyAndReload says
        -- when it will not reload: a failed or partial apply, a stale plan, combat, a note that could not be saved)
        local ok, result, extra = M.ApplyAndReload(shown, c.reload)
        if not ok then
            Fail(result, extra)
            if result == "stale" then M.Invalidate() end
        end
        W.Refresh()
    end, { accept = c.accept, alt = "View details", onAlt = function() W.ShowDetails() end, combat = true, valid = function()
        local ok, why = M.CanApply()
        if not ok then M.NoteFailure(why) W.Refresh() return false, M.ApplyReason(why) end
        if M.Plan().key ~= shown then
            M.NoteFailure("stale")
            M.Invalidate()
            W.Refresh()
            return false, M.ApplyReason("stale") .. " Nothing was changed."
        end
        return true
    end })
end

-- "View details" on the question: back to the review with its account of every change open. Applies nothing.
function W.ShowDetails()
    if not (win and M.Active() and M.Step() == M.REVIEW) then return end
    local p = pages[M.REVIEW]
    if p then p.changesOpen = true end
    W.Refresh()
end

function Actions.restore()
    local text, rp = M.RestoreConfirmText()
    if not rp.ok then
        local why = rp.blocked[1] or "It can't be restored right now."
        W.Note(why)
        return
    end
    R.Interact.Confirm("TWICHUI_LAYOUT_RESTORE", text, function()
        local ok, result = M.Restore(rp.key)
        if not ok then Say("nothing was changed: %s", M.Explain(result)) end
        W.Refresh()
    end, { accept = "Restore", combat = true })
end

function Actions.undo()
    local text, up = M.UndoConfirmText()
    if not up.ok then
        W.Note(up.blocked[1] or "It can't be undone right now.")
        return
    end
    R.Interact.Confirm("TWICHUI_LAYOUT_UNDO", text, function()
        local ok, result = M.Undo(up.key)
        if not ok then Say("nothing was changed: %s", M.Explain(result)) end
        W.Refresh()
    end, { accept = "Undo the update", combat = true })
end

function Actions.keepUpdate()
    local j = R.Layouts.Journal.Read()
    local name = j and j.euiBackup
    R.Interact.Confirm("TWICHUI_LAYOUT_KEEP_UPDATE",
        ("Keep this update for good?\n\n%sUndo this update will no longer be offered. Restore (back to before your first install) is not affected, and nothing else changes."):format(
            name and ("The copy of your EllesmereUI profile from before it, \"" .. name .. "\", is removed; every character on this account shares it. ") or ""),
        function()
            local ok, code = M.ForgetUpdate()
            if not ok then Say("nothing was changed: %s", M.Explain(code)) end
            W.Refresh()
        end, { accept = "Keep it", combat = true })
end

function Actions.keep()
    local j = R.Layouts.Journal.Read()
    local name = j and j.euiBackup
    R.Interact.Confirm("TWICHUI_LAYOUT_KEEP",
        "Keep this setup?\n\nThis finishes the setup: the restore point is forgotten, so Restore (and Undo this update) will no longer be offered"
            .. (name and (", and the copy of your EllesmereUI profile from before the last update, \"" .. name .. "\", is removed") or "")
            .. ". TwichUI keeps managing the layout: everything installed stays exactly as it is, and a later update still knows which changes are yours.",
        function()
            local ok, code = M.Keep()
            if not ok then Say("nothing was changed: %s", M.Explain(code)) end
            W.Refresh()
        end, { accept = "Keep it", combat = true })
end

function Actions.forget()
    R.Interact.Confirm("TWICHUI_LAYOUT_FORGET",
        "Forget the install record?\n\nIt can't be read, so it can't be used to restore anything. This forgets it and changes nothing else.",
        function() M.StopManaging() W.Refresh() end, { accept = "Forget it" })
end

function Actions.stop()
    R.Interact.Confirm("TWICHUI_LAYOUT_STOP",
        "Stop managing this layout?\n\nEverything installed stays exactly as it is. TwichUI forgets which package is installed and what the last install left, so a later setup can't tell your changes from the layout's.",
        function() M.StopManaging() W.Refresh() end, { accept = "Stop managing" })
end

function Actions.removePackage()
    local pk = M.Package()
    if not pk then return end
    R.Interact.Confirm("TWICHUI_LAYOUT_REMOVE_PACKAGE",
        ("Remove the stored package %q (revision %d)?\n\nThis deletes only the stored copy. An install already made from it, and Restore, are not touched. Ask the sender again if you want it back."):format(
            pk.env.package.title or pk.env.meta.id, pk.env.meta.version),
        function() M.RemovePackage() W.Refresh() end, { accept = "Remove" })
end

function Actions.reload()
    local ok, why = M.Reload()
    if not ok then W.Note(M.ApplyReason(why)) end
end

function Actions.check()
    M.Check()
    W.Refresh()
end

-- First install only: Skip setup (nothing is applied; EllesmereUI's own first run, if it was held back for this, is handed back)
function Actions.skip()
    local O = Onboarding()
    if not (O and O.FirstRun()) then return end
    local held = O.Held()
    R.Interact.Confirm("TWICHUI_LAYOUT_SKIP",
        "Skip the guided setup?\n\nNothing is applied and nothing changes. You can run it any time: type /tui layout, or use Home > Interface layout in TwichUI's settings."
            .. (held and "\n\nEllesmereUI's own first-run setup was held back for this one. It opens next, so you can make its choices." or ""),
        function()
            local ok, wasHeld = O.Skip("user")
            if not ok then return end
            W.Close("skip")
            if wasHeld then Say("%s", O.HandBackText(O.HandBack()))
            else Say("skipped. Type /tui layout to open it any time.") end
        end, { accept = "Skip setup" })
end

-- First install, with EllesmereUI's own first run held back for this setup: use EllesmereUI's instead
function Actions.native()
    local O = Onboarding()
    if not (O and O.FirstRun()) then return end
    R.Interact.Confirm("TWICHUI_LAYOUT_NATIVE",
        "Use EllesmereUI's own first-run setup instead?\n\nThis closes TwichUI's layout setup without applying anything and opens EllesmereUI's, where you choose which of its addons stay on. EllesmereUI reloads your interface when you press its button. TwichUI's setup stays under /tui layout.",
        function()
            if not O.Skip("native") then return end
            W.Close("native")
            local shown, code = O.HandBack()
            if not shown then Say("%s", O.HandBackText(shown, code)) end
        end, { accept = "Open EllesmereUI's setup", combat = true })
end

-- The result's Done: closes the dialog. It is an acknowledgment and nothing else: the install stays managed, and Restore and
-- Undo stay offered until the player chooses Keep this setup (Manage layout).
function Actions.done()
    W.Close("later")
end

-- The result's "Open settings": closes the setup (as Close does) and opens TwichUI's settings window
function Actions.settings()
    W.Close("later")
    if R.OpenSettings then R:OpenSettings("overview") end
end

function Actions.again()
    M.Go(M.WELCOME)
    W.Refresh()
end
W.Actions = Actions

---------------------------------------------------------------------------
-- Drawing the current step
---------------------------------------------------------------------------
local env = {
    Actions = Actions,
    Relayout = function() W.Refresh() end,
    Go = function(step) M.Go(step) W.Refresh() end,
    Overlay = function()
        local ok, why = WZ.Overlay.Open()
        if not ok then W.Note(why or "") end
    end,
}

local function Page(step)
    local p = pages[step]
    if not p then
        p = WZ.Pages.Build(step, content, env)
        p.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        pages[step] = p
        W.frames = W.frames + 1
    end
    return p
end

local function PaintStepper(step)
    local session = M.Session()
    for i, tab in ipairs(stepper.tabs) do
        tab:SetSelected(i == step)
        local reachable = session ~= nil and i <= session.reached
        tab:SetEnabled(reachable)
        tab:SetAlpha(reachable and 1 or 0.45)
        -- done: a step before this one that was reached (a small check, so it isn't colour alone); a step ahead is quiet and, until
        -- it is reached, can't be chosen
        tab.tick:SetShown(reachable and i < step)
    end
end

local function PaintFooter(step)
    local note = ""
    local first = M.FirstRun()
    if footer.first ~= first then
        footer.first = first
        footer.close.text:SetText(first and "Do this later" or "Close")
        footer.close:SetWidth(first and 120 or 90)
        R.Interact.Tip(footer.close, first and "Do this later" or "Close", first
            and "Closes the setup for now. Nothing is changed, your choices are remembered, and TwichUI offers it again the next time you log in. Escape and the close box do the same."
            or "Closes the setup. Nothing is changed by closing; your choices are remembered.")
    end
    footer.back:SetShown(step > M.WELCOME and step < M.RESULT)
    footer.next:SetShown(step < M.RESULT)
    footer.next:SetEnabled(true)
    footer.next:SetWidth(110)
    footer.done = false   -- whether the primary button closes the setup (Done) instead of going on or applying
    if step < M.REVIEW then
        footer.next.text:SetText(step == M.WELCOME and "Get started" or "Next")
        local ok = M.CanContinue()
        footer.next:SetEnabled(ok)
        if not ok then note = "Fix what is marked Blocked first. Nothing has changed." end
    elseif step == M.REVIEW then
        local can, code, blocked = M.CanApply()
        if not can and code == "nothing" then
            -- already up to date: nothing to apply, so the way out is the primary action
            footer.next.text:SetText("Done")
            footer.done = true
        else
            -- the label says what accepting does: a plan that needs a reload applies and reloads in one action
            local plan = M.Plan()
            local reload = not plan.problems and plan.ok == true and plan.reload == true   -- also while disabled (combat): the label doesn't flip
            footer.next.text:SetText(reload and "Apply & Reload" or "Apply")
            footer.next:SetWidth(reload and 150 or 110)
            footer.next:SetEnabled(can)
            if not can then note = M.ApplyReason(code, blocked) end
        end
    elseif step == M.RESULT then
        -- a finished, checked setup: Done. Anything unfinished or wrong keeps its own actions on the page
        local p = pages[M.RESULT]
        local ready = p and p.result and p.result.ready
        footer.next:SetShown(ready == true)
        footer.next.text:SetText("Done")
        footer.done = true
    end
    footer.note:ClearAllPoints()
    footer.note:SetPoint("BOTTOMLEFT", footer.close, "BOTTOMRIGHT", 14, 2)
    if footer.back:IsShown() then footer.note:SetPoint("BOTTOMRIGHT", footer.back, "BOTTOMLEFT", -14, 2)
    elseif footer.next:IsShown() then footer.note:SetPoint("BOTTOMRIGHT", footer.next, "BOTTOMLEFT", -14, 2)
    else footer.note:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 2) end
    if M.Session() and M.Session().failed then note = "Nothing was changed: " .. M.ApplyReason(M.Session().failed.code) end
    footer.note:SetText(note)
end

-- The window is one of two shapes: the six steps (stepper, scrolling page, footer), or the compact result dialog (the page alone,
-- as tall as it needs to be). Switching only moves and sizes what already exists.
local function SetCompact(on)
    if compact == on then return end
    compact = on
    stepper:SetShown(not on)
    footer:SetShown(not on)
    scroll:ClearAllPoints()
    if on then
        scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + PAD))
        scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, PAD)
        win:SetWidth(COMPACT_W)
        content:SetWidth(WZ.Pages.COMPACT_W)
    else
        scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + 10 + STEPPER_H + 8))
        scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, FOOTER_H + PAD)
        win:SetSize(WIDTH, HEIGHT)
        content:SetWidth(WZ.Pages.CONTENT_W)
        R.FitToScreen(win)
    end
end

-- keep: the redraw is only to show pageNote (a sentence about a button that did nothing)
function W.Refresh(keep)
    if not win or not M.Active() then return end
    if not keep then pageNote = nil end
    local step = M.Step()
    SetCompact(step == M.RESULT)
    for k, p in pairs(pages) do p.frame:SetShown(k == step) end
    local p = Page(step)
    p.frame:Show()
    local ok, h = pcall(p.Refresh, pageNote)
    if not ok then
        R.Fault("layout setup", h)
        h = 200
    end
    content:SetHeight(math.max(h or 200, 200))
    if compact then
        -- as tall as the content (a scroll bar only if it does not fit the screen), never a mostly empty window
        win:SetHeight(math.max(COMPACT_MIN_H, math.min(COMPACT_MAX_H, HEADER_H + 2 * PAD + (h or 200))))
        R.FitToScreen(win)
    end
    if scroll.SetVerticalScroll and W.lastStep ~= step then scroll:SetVerticalScroll(0) end
    W.lastStep = step
    if not compact then
        PaintStepper(step)
        PaintFooter(step)
    end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Listen(on)
    if not evframe then return end
    if on then
        if W.listening == 0 then
            for _, e in ipairs(EVENTS) do evframe:RegisterEvent(e) end
            W.listening = #EVENTS
        end
    elseif W.listening > 0 then
        for _, e in ipairs(EVENTS) do evframe:UnregisterEvent(e) end
        W.listening = 0
    end
end

local function OnEvent(_, event)
    if not (win and win:IsShown() and M.Active()) then return end
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then M.Invalidate() end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then Dim(event == "PLAYER_REGEN_ENABLED") end
    W.Refresh()
end

local function Build()
    local L = Look()
    local pal = L.pal
    W.builds = W.builds + 1
    BuildScrim()
    win = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    -- the dimming goes the moment the window hides, before anything else its hiding runs (so nothing can leave it up)
    win:HookScript("OnHide", function() Dim(false) end)
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    if win:GetFrameLevel() <= scrim:GetFrameLevel() then win:SetFrameLevel(scrim:GetFrameLevel() + 1) end
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    win:HookScript("OnShow", R.FitToScreen)
    -- Escape: the game's own list (UISpecialFrames), once
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then listed = true end end
    if not listed then tinsert(UISpecialFrames, FRAME_NAME) end
    L.Shell(win, HEADER_H)
    local crest = win:CreateTexture(nil, "ARTWORK")
    crest:SetSize(30, 30)
    crest:SetPoint("TOPLEFT", 14, -7)
    WZ.Art.Apply(crest, "emblem")
    local title = L.Text(win, "title")
    title:SetPoint("LEFT", crest, "RIGHT", 8, 0)
    title:SetText("TwichUI Layout Setup")
    local sub = L.Text(win, "meta")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
    sub:SetText("interface layouts")
    L.CloseBox(win)

    -- the six steps
    stepper = CreateFrame("Frame", nil, win)
    stepper:SetPoint("TOPLEFT", PAD, -(HEADER_H + 10))
    stepper:SetPoint("TOPRIGHT", -PAD, -(HEADER_H + 10))
    stepper:SetHeight(STEPPER_H)
    stepper.tabs = {}
    local w = math.floor((WIDTH - 2 * PAD) / #M.STEPS)
    for i, s in ipairs(M.STEPS) do
        local tab = L.Tab(stepper, i .. "  " .. s.label, w, function() M.Go(i) W.Refresh() end)
        tab:SetPoint("TOPLEFT", (i - 1) * w, 0)
        tab.bar:SetHeight(3)                                                      -- the step you are on: a heavier bar and a warmer wash
        tab.fill:SetColorTexture(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3], 0.20)
        tab.tick = WZ.Controls.Tick(tab, pal.bronzeText)
        tab.tick:SetPoint("LEFT", 9, 0)
        stepper.tabs[i] = tab
    end

    -- the page, in a scroll area (the footer is outside it: its buttons are never hidden by scrolling)
    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll.scrollBarHideable = 1   -- the template's own flag (SecureScrollTemplates.lua): the bar and its arrows show only while the page overflows
    scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + 10 + STEPPER_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, FOOTER_H + PAD)
    L.ScrollBar(scroll)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WZ.Pages.CONTENT_W, 200)
    scroll:SetScrollChild(content)

    -- the footer
    footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    footer:SetHeight(FOOTER_H - 10)
    local line = L.Solid(footer, "BORDER", pal.bronzeLo, 0.6)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", 0, 0)
    footer.close = L.Button(footer, "Close", 90, "secondary", function() W.Close("later") end)
    footer.close:SetPoint("BOTTOMLEFT", 0, 0)
    footer.next = L.Button(footer, "Next", 110, "primary", function()
        local step = M.Step()
        if footer.done then W.Close("later")
        elseif step == M.REVIEW then Actions.apply()
        else M.Next() W.Refresh() end
    end)
    footer.next:SetPoint("BOTTOMRIGHT", 0, 0)
    footer.back = L.Button(footer, "Back", 90, "secondary", function() M.Back() W.Refresh() end)
    footer.back:SetPoint("RIGHT", footer.next, "LEFT", -8, 0)
    footer.note = L.Text(footer, "small")
    footer.note:SetPoint("BOTTOMLEFT", footer.close, "BOTTOMRIGHT", 14, 2)
    footer.note:SetPoint("BOTTOMRIGHT", footer.back, "BOTTOMLEFT", -14, 2)
    footer.note:SetWordWrap(true)
    footer.note:SetJustifyH("LEFT")
    footer.note:SetHeight(30)

    evframe = CreateFrame("Frame")
    evframe:SetScript("OnEvent", OnEvent)
    W.evframe = evframe   -- read by the tests
    win:HookScript("OnShow", function()
        if not M.Active() then M.Begin() end
        local O = Onboarding()
        if O then O.Opened() end
        Listen(true)
        W.Refresh()
        Dim(not resuming)   -- last, so an error above leaves the screen as it was
    end)
    win:HookScript("OnHide", function()
        Listen(false)
        -- the sample tooltip's pointer tracking (Preview.lua) runs only while the pointer is over a miniature of a shown window
        for _, page in pairs(pages) do if page.preview and page.preview.Track then page.preview:Track(false) end end
        if suspended then return end   -- set aside for the full-size preview: the session, and what it worked out, stay
        M.End()
        -- a page's preview and texts stay built (they are cheap); what the model worked out is gone
        local why = closeWhy or "closed"
        closeWhy = nil
        local O = Onboarding()
        if O and not aborting then O.WizardClosed(why) end
    end)
    -- a profile change makes what the plan was worked out against stale: one listener for the session, added once
    if R.Profiles and R.Profiles.OnChange and not W.profileHooked then
        W.profileHooked = true
        R.Profiles.OnChange(function()
            if not M.Active() then return end
            M.Invalidate()
            if win and win:IsShown() then W.Refresh() end
        end)
    end
    W.frames = W.frames + 8
    complete = true
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function W.Open(step)
    if WZ.Overlay and WZ.Overlay.IsShown() then WZ.Overlay.Close("back") return true end   -- asked for again: back to the setup
    if not (win and complete) then R.Perf.Call("layoutwizard.build", Build) end
    if not M.Active() then
        local session, why = M.Begin()
        if not session then Say("there is no layout to set up (%s).", tostring(why)) return false end
    end
    if step then
        local session = M.Session()
        if step > session.reached then session.reached = step end
        M.Go(step)
    end
    win:Show()
    W.Refresh()
    return true
end

-- why: what closed it ("later": Do this later or Close; "skip", "native"; nil: anything else), for the first-install record.
function W.Close(why)
    closeWhy = why
    if WZ.Overlay and WZ.Overlay.IsShown() then WZ.Overlay.Close("exit") return end   -- the preview first; its hide ends the session
    if suspended then
        -- closed while set aside (the preview's Exit, or the window asked to close): end the session
        suspended = false
        if win then win:Hide() end   -- already hidden, so its OnHide won't run: end the session here
        M.End()
        Dim(false)
        local O = Onboarding()
        closeWhy = nil
        if O then O.WizardClosed(why or "closed") end
        return
    end
    if win then win:Hide() end
    closeWhy = nil
end

-- After an error while building or opening (LayoutsLauncher.OpenWizard): the window and its dimming are put away and the
-- session ends, so nothing the player can't close is left on screen. Not an answer to a first-install setup.
function W.Abort()
    aborting = true
    suspended, resuming = false, false
    closeWhy = nil
    if scrim then scrimFade:Set(0) scrim:Hide() end
    local ok, err = true, nil
    if win and win:IsShown() then ok, err = pcall(win.Hide, win) end
    if win and not complete then win = nil end   -- built only part way: made again at the next open
    Listen(false)
    M.End()
    aborting = false
    if not ok then R.Fault("layout setup", err) end
end

-- Hides the window for the full-size preview without ending the session; Resume brings it back where it was.
function W.Suspend()
    if not (win and win:IsShown()) then return false end
    suspended = true
    win:Hide()
    return true
end

function W.Resume()
    if not suspended then return false end
    suspended = false
    resuming = true
    if win then win:Show() end   -- OnShow: the session is still there, so it is drawn as it was left (and dimmed again)
    resuming = false
    return true
end

function W.Toggle()
    if W.IsShown() then W.Close() else W.Open() end
end

---------------------------------------------------------------------------
-- What the troubleshooting report can read (no building, nothing changed)
---------------------------------------------------------------------------
R.Perf.Gauge("layoutwizard.events", { label = "Layout setup: events registered (0 while closed)", unit = "count", kind = "listeners",
    group = "layouts", read = function() return W.listening end })
R.Perf.Gauge("layoutwizard.frames", { label = "Layout setup: frames and pages kept", unit = "count", kind = "pool",
    group = "layouts", read = function() return W.frames end })

R.LayoutWizard.ready = true
