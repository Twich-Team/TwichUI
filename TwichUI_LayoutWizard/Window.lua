-- TwichUI Layout Setup: the window
-- One window, built the first time it is opened and kept; its pages are built when first shown (Pages.lua). It is drawn
-- with TwichUI's own look (R.Look), so it is complete without EllesmereUI or any other addon, and it closes with Escape
-- through the game's own list of frames Escape closes (never RegisterGameMenuEscHandler: an addon calling that taints
-- the game's Escape path, see the settings window).
--
-- While it is open it listens for four events (combat starting and ending, the screen's size and the UI scale changing),
-- on one frame of its own, and stops listening when it closes. Nothing here runs while it is closed. Closing drops
-- everything the model worked out (the plan holds the payload it would import) and changes nothing in the game.
--
-- The only things that change the game are a few buttons, each after a confirmation that names the exact scope, each
-- refused in combat by the model and again by the engine: Apply, Restore, Undo this update, Keep the update (removes the
-- copy an update kept), and the reload the player starts.
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
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }

local win, scroll, content, stepper, footer, evframe
local suspended = false   -- hidden for the full-size preview: the session goes on
local pages = {}
W.pages = pages       -- read by the tests
W.frames = 0          -- frames made, for the troubleshooting report
W.listening = 0       -- events registered now (0 while closed)
W.builds = 0          -- times the window was built (1 once opened; never more)

local function Look() return R.Look end

local function Say(fmt, ...) R.Print("layout setup: " .. fmt, ...) end

function W.IsShown() return win ~= nil and win:IsShown() end

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
    local text, shown = M.ConfirmText()
    R.Interact.Confirm("TWICHUI_LAYOUT_APPLY", text, function()
        local ok, result, extra = M.Apply(shown)
        if not ok then
            Fail(result, extra)
            if result == "stale" then M.Invalidate() end
        end
        W.Refresh()
    end, { accept = "Apply", combat = true, valid = function()
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

function Actions.restore()
    local text, rp = M.RestoreConfirmText()
    if not rp.ok then
        local why = rp.blocked[1] or "It can't be restored right now."
        footer.note:SetText(why)
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
        footer.note:SetText(up.blocked[1] or "It can't be undone right now.")
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
    if not ok then footer.note:SetText(M.ApplyReason(why)) W.Refresh() end
end

function Actions.check()
    M.Check()
    W.Refresh()
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
        if not ok and footer then footer.note:SetText(why or "") end
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
    end
end

local function PaintFooter(step)
    local note = ""
    footer.back:SetShown(step > M.WELCOME and step < M.RESULT)
    footer.next:SetShown(step < M.RESULT)
    footer.next:SetEnabled(true)
    if step < M.REVIEW then
        footer.next.text:SetText(step == M.WELCOME and "Start" or "Next")
        local ok = M.CanContinue()
        footer.next:SetEnabled(ok)
        if not ok then note = "Fix what is marked Blocked first. Nothing has changed." end
    elseif step == M.REVIEW then
        footer.next.text:SetText("Apply")
        local can, code, blocked = M.CanApply()
        footer.next:SetEnabled(can)
        if not can then note = M.ApplyReason(code, blocked) end
    end
    if M.Session() and M.Session().failed then note = "Nothing was changed: " .. M.ApplyReason(M.Session().failed.code) end
    footer.note:SetText(note)
end

function W.Refresh()
    if not win or not M.Active() then return end
    local step = M.Step()
    for k, p in pairs(pages) do p.frame:SetShown(k == step) end
    local p = Page(step)
    p.frame:Show()
    local ok, h = pcall(p.Refresh)
    if not ok then
        R.Fault("layout setup", h)
        h = 200
    end
    content:SetHeight(math.max(h or 200, 200))
    if scroll.SetVerticalScroll and W.lastStep ~= step then scroll:SetVerticalScroll(0) end
    W.lastStep = step
    PaintStepper(step)
    PaintFooter(step)
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
    W.Refresh()
end

local function Build()
    local L = Look()
    local pal = L.pal
    W.builds = W.builds + 1
    win = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
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
        stepper.tabs[i] = tab
    end

    -- the page, in a scroll area (the footer is outside it: its buttons are never hidden by scrolling)
    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
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
    footer.close = L.Button(footer, "Close", 90, "secondary", function() W.Close() end)
    footer.close:SetPoint("BOTTOMLEFT", 0, 0)
    R.Interact.Tip(footer.close, "Close", "Closes the setup. Nothing is changed by closing; your choices are remembered.")
    footer.next = L.Button(footer, "Next", 110, "primary", function()
        if M.Step() == M.REVIEW then Actions.apply() else M.Next() W.Refresh() end
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
        Listen(true)
        W.Refresh()
    end)
    win:HookScript("OnHide", function()
        Listen(false)
        -- the sample tooltip's pointer tracking (Preview.lua) runs only while the pointer is over a miniature of a shown window
        for _, page in pairs(pages) do if page.preview and page.preview.Track then page.preview:Track(false) end end
        if suspended then return end   -- set aside for the full-size preview: the session, and what it worked out, stay
        M.End()
        -- a page's preview and texts stay built (they are cheap); what the model worked out is gone
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
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function W.Open(step)
    if WZ.Overlay and WZ.Overlay.IsShown() then WZ.Overlay.Close("back") return true end   -- asked for again: back to the setup
    if not win then R.Perf.Call("layoutwizard.build", Build) end
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

function W.Close()
    if WZ.Overlay and WZ.Overlay.IsShown() then WZ.Overlay.Close("exit") return end   -- the preview first; its hide ends the session
    if suspended then
        -- closed while set aside (the preview's Exit, or the window asked to close): end the session
        suspended = false
        if win then win:Hide() end   -- already hidden, so its OnHide won't run: end the session here
        M.End()
        return
    end
    if win then win:Hide() end
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
    if win then win:Show() end   -- OnShow: the session is still there, so it is drawn as it was left
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
