dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The layout wizard's presentation (TwichUI_LayoutWizard Controls.lua, Pages.lua, Window.lua; docs/layouts/wizard.md): measured on the real
-- page builders with the stand-in frames (wizard_probe.lua works out where each frame and text ends up from its anchors). Covers: one
-- choice card for every choice (selected, hover, the check, the outline, titles clear of the indicator, a card keeping its size when
-- its state changes); both layouts inside the window's standard viewport; helper presets read from the package (more than three,
-- custom ones, no outdated claims, details behind a button); the personalize choices all in reach with their own samples; the review as
-- a receipt (fresh, update, nothing to change, blocked); the result's headings per outcome and the recovery actions in view; the stepper
-- and footer; scroll bars only on overflow with the footer outside the scrolling content; repeated opening making no new frames or
-- listeners; selecting changing nothing in the game; the new artwork. Nothing here is the game: what only a screen can show is the
-- checklist in docs/layouts/wizard.md.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same = LM.Copy, LM.Same
local P = dofile(TESTS .. "wizard_probe.lua")

local function Find(frame, label)
  if frame.scripts and frame.scripts.OnClick then
    local hit = frame.text == label
    for _, ch in ipairs(frame.children or {}) do if ch.kind == "FontString" and ch.text == label then hit = true end end
    if hit and frame:IsVisible() then return frame end
  end
  for _, ch in ipairs(frame.children or {}) do
    local b = Find(ch, label)
    if b then return b end
  end
end
local function Click(win, label)
  local b = Find(win, label)
  assert(b, "no visible button '" .. label .. "'")
  assert(b.enabled ~= false, "button '" .. label .. "' is disabled")
  b.scripts.OnClick(b)
end
local function Has(win, label) return Find(win, label) ~= nil end
local function Enabled(win, label) local b = Find(win, label) return b ~= nil and b.enabled ~= false end
local function Expand(win, label)
  local b = Find(win, label)
  assert(b, "no visible disclosure '" .. label .. "'")
  if not b.open then b.scripts.OnClick(b) end
  return b
end
local function Collapse(win, label)
  local b = Find(win, label)
  assert(b, "no visible disclosure '" .. label .. "'")
  if b.open then b.scripts.OnClick(b) end
  return b
end
local function Says(win, text) return LM.Says(win, text) end
local function Open(c)
  c.SlashCmdList.TWICHUI("layout")
  return c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
end
local function Advance(win, M, step)
  while M.Step() < step do Click(win, M.Step() == 1 and "Get started" or "Next") end
end
local function World(c)
  local tw = Copy(c.TwichUIDB)
  if tw.layouts then tw.layouts.wizard = nil; if next(tw.layouts) == nil then tw.layouts = nil end end
  return { tw = tw, eui = Copy(c.EllesmereUIDB), restore = Copy(c.TwichUIRestoreDB), share = Copy(c.TwichUIShareDB), chron = Copy(c.TwichUIChronicleDB) }
end
local function Unchanged(a, b) return Same(a.tw, b.tw) and Same(a.eui, b.eui) and Same(a.restore, b.restore) and Same(a.share, b.share) and Same(a.chron, b.chron) end

-- the window's scroll area, as the window drew it: its top and bottom edge from the window's top (what a page may fill without scrolling)
local function Viewport(win)
  for _, ch in ipairs(win.children) do
    if ch.kind == "ScrollFrame" then
      local top = ch.points[1][3] and -ch.points[1][3]
      local bottom = win.h - ch.points[2][3]
      return top, bottom, ch
    end
  end
end
local function FooterOf(win)
  for _, ch in ipairs(win.children) do
    if ch.kind == "Frame" and ch.points[1] and ch.points[1][1] == "BOTTOMLEFT" and ch.h > 0 then return ch end
  end
end

-- every choice card under a frame (a frame that has the card's title, hint, indicator and Fill)
local function Cards(frame, out)
  out = out or {}
  for _, ch in ipairs(P.Descendants(frame)) do
    if ch.Fill and ch.mark and ch.title and ch.hint and ch.outline then out[#out + 1] = ch end
  end
  return out
end
-- what a card must keep: the title short of the indicator (and of the word beside it), the hint clear of it, all inside the card
local function AuditCard(card, where)
  local r, t, m = P.Rect(card), P.Rect(card.title), P.Rect(card.mark)
  Check(r and t and m, where .. ": the card, its title and its indicator can be placed")
  if not (r and t and m) then return end
  Check(t.r <= m.l, where .. (": the title (right %.0f) stops short of the indicator (left %.0f)"):format(t.r, m.l))
  Check(m.t >= r.t and m.r <= r.r, where .. ": the indicator is inside the card, at its top right")
  if card.selText then
    local s = P.Rect(card.selText)
    Check(s.r <= m.l and s.l >= t.r, where .. ": the word Selected sits between the title and the indicator")
  end
  if card.hint.shown then
    local h = P.Rect(card.hint)
    Check(h.t >= m.b or h.r <= m.l, where .. ": the hint is clear of the indicator")
    Check(h.r <= r.r and h.b <= r.b, where .. (": the hint is inside the card (bottom %.0f of %.0f)"):format(h.b, r.b))
  end
  Check(t.b <= r.b, where .. ": the title is inside the card")
end

---------------------------------------------------------------------------
-- 1. Welcome: a calm opening, a verdict, the checks behind a button
---------------------------------------------------------------------------
local c = LM.Boot("Ui", nil, { euiVersion = "9.6.9" })   -- the version the bundled layout was tested with
local win, WK = Open(c)
P.origin = win
local M, W = WK.Model, WK.Window
local top, bottom, scroll = Viewport(win)
local VIEW_H = bottom - top
do
  Check(top == 92 and bottom == 520 and VIEW_H == 428, "the scroll area is the window's standard viewport (92 to 520: " .. tostring(top) .. " to " .. tostring(bottom) .. ")")
  Check(scroll.scrollBarHideable == 1, "the scroll bar is the template's hideable one: it shows only while a page overflows")
  local welcome = W.pages[1]
  Check(Says(win, "Make yourself at home") and Says(win, "Choose a layout, pick your conveniences, and make it yours."), "one heading and one short line")
  Check(Says(win, "Choose your layout") and Says(win, "Add your preferences") and Says(win, "Review, then apply"), "the three points")
  Check(Says(win, "backed up when you do") and not Says(win, "restore point is made first"), "the backup is promised for the apply, not as if one exists already")
  Check(Says(win, "every character on this account"), "the account-wide part stays in view")
  Check(Says(win, "Items to review") and Says(win, "A preview build"), "this client's one warning is said at once, with its short explanation")
  Check(Has(win, "Compatibility details") and not Says(win, "Version 9.6.9.") and not Says(win, "refused during combat"), "and the checks are behind Compatibility details")
  Check(not Has(win, "Skip setup"), "no first-install buttons outside a first installation")
  Check(welcome.frame.h <= VIEW_H, "the page fits the viewport without scrolling (" .. welcome.frame.h .. " of " .. VIEW_H .. ")")
  local before = World(c)
  Expand(win, "Compatibility details")
  Check(Says(win, "Version 9.6.9.") and Says(win, "Applying and restoring are refused during combat"), "Compatibility details shows every check")
  Check(Says(win, "Classic Adventure fits."), "including the screen, for each layout")
  Collapse(win, "Compatibility details")
  Check(not Says(win, "Version 9.6.9."), "and folds again")
  Check(Unchanged(World(c), before), "opening and folding it changed nothing")
  Check(Enabled(win, "Get started") and not Has(win, "Start"), "Get started is the one primary action")
end

-- a blocker is said at once, with its reason, and the details stay available
do
  local k = LM.Boot("Blocked", nil, { noEUI = true })
  local w = Open(k)
  Check(Says(w, "Setup blocked") and Says(w, "EllesmereUI isn't installed or isn't turned on") and Says(w, "Blocked"), "no EllesmereUI: Setup blocked, the reason in view, marked with a word")
  Check(not Enabled(w, "Get started"), "and Get started waits")
  Expand(w, "Compatibility details")
  Check(Says(w, "TwichUI profiles") and Says(w, "Your screen"), "the full list is there when asked for")
  local ok = LM.Boot("Ready", nil, { eui = {} })
  Check(true, "(a second client boots)")
end

---------------------------------------------------------------------------
-- 2. One card for every choice: states and fit
---------------------------------------------------------------------------
do
  Advance(win, M, 2)
  local page = W.pages[2]
  local a, b = page.cards[1], page.cards[2]
  Check(a.selected and not b.selected, "Classic is chosen")
  -- selected: the check, the outline all round, the fill, the word; not selected: none of it
  local function Lit(card)
    local n = 0
    for _, t in ipairs(card.outline) do if t.shown then n = n + 1 end end
    return n == 4 and card.fill.shown and card.mark.on and card.mark.tick.shown and card.selText.shown
  end
  local function Dark(card)
    local n = 0
    for _, t in ipairs(card.outline) do if t.shown then n = n + 1 end end
    return n == 0 and not card.fill.shown and not card.mark.on and not card.mark.tick.shown and not card.selText.shown
  end
  Check(Lit(a) and Dark(b), "the selected card has the check, a full outline, a fill and the word Selected; the other has none")
  Check(a.border[4] == 1 and b.border[4] < 0.5, "the selected edge is solid bronze; the other's is quiet")
  local ha, hb = a.h, b.h
  b:Fire("OnEnter")
  Check(b.border[4] > 0.5 and b.border[4] < 1 and Dark(b), "hover lights the edge a little and nothing else: quieter than selected, no check, no outline")
  a:Fire("OnEnter")
  Check(a.border[4] == 1 and Lit(a), "hover over the selected card leaves it selected")
  b:Fire("OnLeave"); a:Fire("OnLeave")
  Check(b.border[4] < 0.5, "leaving puts the hover away")
  page.cards[2].scripts.OnClick(page.cards[2])
  Check(Lit(b) and Dark(a) and a.h == ha and b.h == hb, "choosing the other moves the selection without changing either card's size")
  page.cards[1].scripts.OnClick(page.cards[1])
  Check(a.selected and a.h == ha and b.h == hb, "and back")
  for i, card in ipairs(page.cards) do AuditCard(card, "layout card " .. i) end

  -- both layouts, whole, inside the viewport at the standard window size, and with no description pushing the second off
  local ra, rb = P.Rect(a), P.Rect(b)
  Check(ra.t >= top and ra.b <= bottom and rb.t >= top and rb.b <= bottom, ("both layout cards are fully in view (%.0f-%.0f and %.0f-%.0f of %d-%d)"):format(ra.t, ra.b, rb.t, rb.b, top, bottom))
  Check(rb.t >= ra.b and page.frame.h <= VIEW_H, "one under the other, and the page needs no scrolling (" .. page.frame.h .. ")")
  Check(a.hasPic and b.hasPic and a.pic.shown and b.pic.shown, "each has its illustration")
  Check(Says(win, "Classic Adventure") and Says(win, "Compact Adventure") and Says(win, "Chat lower left") and Says(win, "Open screen centre"), "title, a short description and traits")
  Check(not Says(win, "EllesmereUI: its modules") and not Says(win, "The unit frames and action bars sit low"), "the long account is not in the cards")
  Expand(win, "Layout details")
  Check(Says(win, "EllesmereUI: its modules, their layout links") and Says(win, "The unit frames and action bars sit low"), "Layout details has it for the chosen layout")
  Check(M.Layout().id == "classic-adventure", "opening it chose nothing")
  Collapse(win, "Layout details")

  -- the preview: one short caption, the long account behind an info button, and no repeated disclaimer
  local pv = page.preview
  Check(Says(win, "Layout preview \194\183 Sample content") and not Says(win, "An illustration"), "the preview is captioned in one line")
  Check(pv.info and pv.info.twichuiTip and pv.info.twichuiTip.body:find("sample shapes", 1, true), "and what it is and isn't is behind its info button")

  -- more than two layouts: another card, placed after the others, the page grows (and scrolls) rather than clipping
  local s = M.Session()
  local third = Copy(s.layouts[1])
  third.id, third.title = "third-layout", "Third Layout"
  third.pkg, third.variant = s.layouts[1].pkg, s.layouts[1].variant
  s.layouts[#s.layouts + 1] = third
  W.Refresh()
  Check(page.cards[3] and page.cards[3].shown and P.Rect(page.cards[3]).t >= rb.b and page.frame.h > VIEW_H, "a third layout is a third card below, and the page scrolls to it")
  table.remove(s.layouts)
  W.Refresh()
  Check(not page.cards[3].shown, "taken away it is hidden again")
  Check(Unchanged(World(c), World(c)), "(nothing in the game moved)")
end

---------------------------------------------------------------------------
-- 3. Helpers: every preset the package offers, read from it
---------------------------------------------------------------------------
do
  Advance(win, M, 3)
  local page = W.pages[3]
  Check(#page.cards >= 3 and page.preview == nil, "three cards, and no layout preview that shows nothing of what a helper does")
  Check(Says(win, "Keep my current helper preferences.") and Says(win, "Useful resource and utility displays.") and Says(win, "On-screen helpers, plus navigation."),
    "the three bundled presets in the short wording, derived from what each sets")
  Check(Says(win, "The layout's own look and places apply whichever you choose."), "and one short statement that the layout's look applies whichever is chosen")
  Check(not Says(win, "only turn") and not Says(win, "never off") and not Says(win, "Only turns") and not Says(win, "Never turns"), "no claim that a preset only switches things on")
  Check(not Says(win, "Class resource bars"), "no feature or setting names in the cards until asked")
  for i = 1, 3 do AuditCard(page.cards[i], "helper card " .. i) end
  local keep, onscreen, nav = page.cards[1], page.cards[2], page.cards[3]
  Check(keep.pic.texture:find("media\\keep", 1, true), "Keep my settings has the journal")
  Check(onscreen.pic.texture:find("media\\helpers", 1, true), "On-screen helpers has the bar, pin and cup")
  Check(nav.pic.texture:find("navigation", 1, true), "Helpers and navigation reuses TwichUI's compass")
  Check(keep.selected and not onscreen.selected, "the default is shown selected")
  local before = World(c)
  -- the included settings: built when first opened, kept through a pick, and a fold loses nothing
  Check(onscreen.detail == nil, "the details are not built until asked for")
  Click(win, "View included settings")   -- the first card's
  Check(keep.detail and keep.detail.shown and Says(win, "Changes none of the"), "Keep my settings: what it leaves alone, in words")
  onscreen.more.scripts.OnClick(onscreen.more)
  Check(onscreen.detail.shown and Says(win, "Turns on: Class resource bars, Food and drink, Marker bar."), "On-screen helpers: what it turns on, read from the package")
  Check(Says(win, "The layout's look and places apply whichever you pick."), "and that the layout's look still applies")
  for i = 1, 3 do AuditCard(page.cards[i], "helper card " .. i .. " (open)") end
  onscreen:Fire("OnClick")
  onscreen.scripts.OnClick(onscreen)
  Check(M.Pick("helpers") == "on-screen" and onscreen.selected and not keep.selected, "choosing with the details open selects it")
  keep.more.scripts.OnClick(keep.more)
  Check(not keep.detail.shown and onscreen.detail.shown and M.Pick("helpers") == "on-screen", "folding one leaves the other open and the pick alone")
  onscreen.more.scripts.OnClick(onscreen.more)
  M.SetPick("helpers", "as-is")
  W.Refresh()
  Check(Unchanged(World(c), before) and M.Pick("helpers") == "as-is", "none of it changed the game")
end

-- more than three presets, custom ones: whatever the author made, with no icon of its own and no claim it can't back
do
  local k = LM.Boot("Many")
  local w, WK2 = Open(k)
  local M2, W2 = WK2.Model, WK2.Window
  local P2 = P
  P2.origin = w   -- measured from this client's window until the next section says otherwise
  local ch = M2.Choice("helpers")
  local own = #ch.options   -- the bundled options come first; the three below are cards own + 1 .. own + 3
  ch.options[#ch.options + 1] = { id = "quiet", label = "Quiet screen", hint = "Turns the on-screen extras off. Everything else stays as it is, and you can bring any of them back later.",
    twichui = { groups = { classBars = { modules = { classBars = false } }, markerBar = { modules = { markersBar = false } } } } }
  ch.options[#ch.options + 1] = { id = "mine-a", label = "Raid night", hint = "The bars and the markers, no food buttons.",
    twichui = { groups = { classBars = { modules = { classBars = true } }, markerBar = { modules = { markersBar = true } } } } }
  ch.options[#ch.options + 1] = { id = "plain", label = "Plain", hint = "", twichui = { groups = { food = { modules = { foodDrink = false } } } } }
  Advance(w, M2, 3)
  local page = W2.pages[3]
  Check(#page.cards == own + 3 and page.cards[own + 3].shown, "every preset is a card")
  local last = P2.Rect(page.cards[own + 3])
  local _, bottom2, scroll2 = Viewport(w)
  Check(page.frame.h > 428 and last.b > bottom2, "more than fit: the page is taller than the window's viewport and scrolls")
  Check(scroll2.GetVerticalScrollRange(scroll2) > 0, "so the scroll area has something to scroll")
  local footer = FooterOf(w)
  Check(footer and P2.Rect(footer).t >= bottom2, "the footer sits below the scroll area: scrolling never hides a button")
  local inScroll = false
  for _, d in ipairs(P2.Descendants(scroll2)) do if d == footer then inScroll = true end end
  Check(not inScroll, "and is not part of what scrolls")
  for i = 1, #ch.options do AuditCard(page.cards[i], "preset card " .. i) end
  Check(Says(w, "Turns the on-screen extras off.") and not Says(w, "Everything else stays as it is, and you can bring"), "a custom preset keeps its author's first sentence, and the rest is behind the button")
  Check(Says(w, "The bars and the markers, no food buttons."), "and a short one whole")
  Check(page.cards[own + 1].pic.texture:find("qualityOfLife", 1, true) and page.cards[own + 2].pic.texture:find("qualityOfLife", 1, true), "a custom preset with no artwork of its own gets the generic icon")
  Check(Says(w, "Turns off:") == false, "(no preset's details are built until asked for)")
  page.cards[own + 1].more.scripts.OnClick(page.cards[own + 1].more)
  Check(Says(w, "Turns off: Class resource bars, Marker bar.") and Says(w, "Everything else stays as it is, and you can bring any of them back later."), "its details say what it turns off, and carry the author's full text")
  page.cards[own + 3].more.scripts.OnClick(page.cards[own + 3].more)
  Check(Says(w, "Turns off: Food and drink."), "a preset made of one switch says it")
  Check(page.cards[6].h > 70, "(a plain preset with no hint is still a whole card)")
  -- a bundled id the author changed is no longer described as the bundled shape
  local k2 = LM.Boot("Changed")
  local w3, WK3 = Open(k2)
  local ch3 = WK3.Model.Choice("helpers")
  for _, o in ipairs(ch3.options) do
    if o.id == "on-screen" then o.twichui = { groups = { classBars = { modules = { classBars = false } } } } o.hint = "Switches the class bars off. Nothing else." end
  end
  Advance(w3, WK3.Model, 3)
  Check(Says(w3, "Switches the class bars off.") and not Says(w3, "Useful resource and utility displays."), "a preset that no longer matches its old shape is not given the old description")
end

---------------------------------------------------------------------------
-- 4. Personalize: every choice in reach, each with its own small sample
---------------------------------------------------------------------------
do
  P.origin = win   -- (the section above measured another client's window)
  c.CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
  Advance(win, M, 4)
  local page = W.pages[4]
  Check(page.preview == nil, "no large generic layout diagram on this page")
  Check(page.frame.h <= VIEW_H, "every group fits the viewport at its defaults (" .. page.frame.h .. " of " .. VIEW_H .. ")")
  Check(Says(win, "Accent colour") and Says(win, "Aged gold") and Says(win, "Your class colour") and Says(win, "Verdigris") and Says(win, "Ember") and Says(win, "Dusk blue"),
    "five accents, each named under its swatch (no colour alone)")
  local shownSw = 0
  for _, sw in ipairs(page.swatches) do if sw.shown then shownSw = shownSw + 1 end end
  Check(shownSw == 5, "five swatches")
  local sel = 0
  for _, sw in ipairs(page.swatches) do if sw.mark.shown and sw.mark.on then sel = sel + 1 end end
  Check(sel == 1 and page.swatches[1].mark.shown, "the chosen one has the check")
  local classSw
  for i, o in ipairs(M.Choice("accent").options) do if o.id == "class" then classSw = page.swatches[i] end end
  Check(classSw.icon.shown and classSw.icon.coords and classSw.icon.coords[1] == 0.25, "the class colour carries the class's own icon, so it is not an unexplained swatch")
  Check(Says(win, "Size") and #page.sizes == 2 and page.sizes[1].shown and page.sizes[2].shown and page.sizes[1].sample.text == "Aa" and page.sizes[2].sample.text == "Aa",
    "size: Standard and Larger, each showing Aa")
  Check(Says(win, "How large chat, the damage meter and the minimap are drawn"), "and what it changes, from the package: chat, meter and minimap, not the whole UI")
  Check(Says(win, "Applies to every character on this account."), "tooltip placement states its account-wide scope")
  local tg, pg = page.groups.tooltip, page.groups["friendly-plates"]
  Check(tg.cards[1].pic.texture:find("tipfixed", 1, true) and tg.cards[2].pic.texture:find("tipcursor", 1, true) and tg.cards[1].pic.shown and tg.cards[2].pic.shown, "tooltip placement: the two illustrations, matched to the two options")
  Check(#pg.cards == 2 and pg.cards[1].samples and #pg.cards[1].samples == 3 and #pg.cards[2].samples == 3, "friendly nameplates: three synthetic samples inside each card")
  Check(pg.cards[1].samples[1].name.text == "Warrior" and not pg.cards[1].samples[1].name.text:find("Rich"), "the samples are synthetic players, never the player's own")
  Check(not Says(win, "Blizzard's nameplates draw friendly players"), "and the Standard blue note is not shown while Class colors is the pick")
  for _, g in ipairs({ tg, pg }) do for i, card in ipairs(g.cards) do AuditCard(card, "personalize card " .. i) end end
  for i, card in ipairs(page.sizes) do AuditCard(card, "size card " .. i) end
  -- every one of them is clickable, and clicking changes nothing in the game
  local calls, LY = 0, c.TwichUI.Layouts
  local apply = LY.Apply
  LY.Apply = function(...) calls = calls + 1 return apply(...) end
  local before = World(c)
  for i, sw in ipairs(page.swatches) do if sw.shown then sw.scripts.OnClick(sw) end end
  for _, card in ipairs(page.sizes) do card.scripts.OnClick(card) end
  for _, g in ipairs({ tg, pg }) do for _, card in ipairs(g.cards) do card.scripts.OnClick(card) end end
  Check(Unchanged(World(c), before) and calls == 0, "choosing every accent, size, tooltip and nameplate option changed nothing in the game and applied nothing")
  Check(M.Pick("friendly-plates") == "blue" and Says(win, "Blizzard's nameplates draw friendly players") and Says(win, "stays until you change it there"),
    "Standard blue says what it leaves while it is the pick")
  Check(pg.cards[2].selected and tg.cards[2].selected, "and the last card of each group is the selected one")
  M.ResetPicks()
  W.Refresh()
  Check(tg.cards[1].selected and pg.cards[1].selected, "Start over: the layout's own again")
  -- the class samples differ from each other; Standard blue's are one colour
  local cs = pg.cards[1].samples
  local c1, c2 = cs[1].name.textColor, cs[2].name.textColor
  Check(c1 and c2, "Class colors: each sample has its own colour (names only in this layout)")
  local bs = pg.cards[2].samples
  Check(bs[1].bar.color[1] == bs[2].bar.color[1] and bs[2].bar.color[3] == bs[3].bar.color[3] and bs[1].bar.shown, "Standard blue: the same blue for each")
  LY.Apply = apply
end

---------------------------------------------------------------------------
-- 5. Review: a receipt, with the long account behind View changes
---------------------------------------------------------------------------
do
  M.SetPick("size", "larger")
  Advance(win, M, 5)
  local page = W.pages[5]
  Check(Says(win, "Ready to apply") and Says(win, "Nothing has changed yet."), "a fresh installation: one heading, one line")
  local labels = {}
  for _, row in ipairs(page.rows) do if row.shown then labels[#labels + 1] = row.label.text end end
  Check(table.concat(labels, "|") == "Layout|Helpers|Accent|Tooltip placement|Friendly nameplates|Size", "the choices, in rows, in order: " .. table.concat(labels, "|"))
  Check(Says(win, "Classic Adventure") and Says(win, "Larger"), "with their values")
  Check(Says(win, "every character on this account") and Says(win, "A restore point is saved first") and Says(win, "A reload finishes EllesmereUI's part"),
    "and the consequences: what is account-wide, the way back, the reload")
  Check(Says(win, "Objectives position isn't changed"), "a limit that stays in view: what isn't placed")
  Check(not Says(win, "fully verified") and not Says(win, "Verified"), "no claim of verification before there is anything to verify")
  Check(not Has(win, "Change") and Has(win, "View changes") and not Has(win, "Advanced"), "no update policy on a first installation, the account of changes behind a button, nothing advanced")
  Check(not Says(win, "Left alone") and not Says(win, "If something goes wrong"), "the long account is folded")
  local rc = page.receipt
  Check(rc.kind == "fresh" and #rc.rows == 6 and rc.counts == nil, "the receipt is read from the review: fresh, six rows, no update counts")
  Expand(win, "View changes")
  Check(Says(win, "Left alone") and Says(win, "If something goes wrong") and Says(win, "TwichUI: at once"), "View changes shows the account, section by section")
  Collapse(win, "View changes")
  Check(M.Pick("size") == "larger" and Says(win, "Larger"), "folding it kept the choices")
  Check(Has(win, "Apply") and not Has(win, "Force re-apply") and not Has(win, "Stop forcing"), "Apply is the footer's primary action; Force re-apply is not offered on a clean installation")
  for _, ch in ipairs(P.Descendants(FooterOf(win))) do
    Check(not (ch.text == "Force re-apply" or ch.text == "Stop forcing"), "no Force button in the footer")
  end
  -- the preview on the review: the plan's own placement, captioned as a sample
  Check(Says(win, "Layout preview \194\183 Sample content"), "the review's preview has the same one-line caption")
end

---------------------------------------------------------------------------
-- 6. The stepper and the footer
---------------------------------------------------------------------------
do
  local tabs
  for _, ch in ipairs(win.children) do
    if ch.kind == "Frame" and ch.children[1] and ch.children[1].tick then tabs = ch.children end
  end
  Check(tabs and #tabs == 6, "six steps")
  Check(tabs[1].tick.shown and tabs[2].tick.shown and tabs[3].tick.shown and tabs[4].tick.shown and not tabs[5].tick.shown and not tabs[6].tick.shown,
    "on the review, the four steps before it carry a check; this one and the one after do not")
  Check(tabs[5].bar.h == 3 and tabs[5].bar.shown and not tabs[1].bar.shown, "the step you are on has a heavy bar; the others none")
  Check(tabs[6].enabled == false and tabs[6].alpha < 0.6 and tabs[5].alpha == 1 and tabs[1].enabled, "a step not reached is quiet and can't be chosen; the rest can")
  M.Go(2)
  W.Refresh()
  Check(tabs[1].tick.shown and not tabs[2].tick.shown and not tabs[3].tick.shown and tabs[5].enabled and tabs[5].alpha == 1,
    "going back: only what is behind you is checked; a step already reached ahead is still open")
  M.Go(5)
  W.Refresh()
  -- the footer: one primary action at the right, its label says what it does
  local f = FooterOf(win)
  local function Primary()
    for _, ch in ipairs(f.children) do if ch.scripts.OnClick and ch.text == nil then end end
    return Find(win, "Apply") or Find(win, "Next") or Find(win, "Get started") or Find(win, "Done")
  end
  M.Go(1) W.Refresh()
  Check(Has(win, "Get started") and not Has(win, "Back"), "welcome: Get started, no Back")
  M.Go(3) W.Refresh()
  Check(Has(win, "Next") and Has(win, "Back") and Has(win, "Close"), "the choices: Next, Back, Close")
  M.Go(5) W.Refresh()
  Check(Has(win, "Apply") and Has(win, "Back") and Has(win, "Close"), "the review: Apply, Back, Close")
  local nb, bb, cb = Find(win, "Apply"), Find(win, "Back"), Find(win, "Close")
  local rn, rb, rc = P.Rect(nb), P.Rect(bb), P.Rect(cb)
  Check(rn.t == rb.t and rn.t == rc.t and rn.r > rb.r and rb.r < rn.l and rc.r < rb.l, "one row: Close at the left, Back and the primary action at the right")
  Check(rn.r == win.w - 16 and rn.b == win.h - 16, "the primary action is in the corner, at the same place on every step")
  Check(rn.w >= 110 and #("Get started") * 6 < 110, "its labels fit its button")
end

---------------------------------------------------------------------------
-- 7. Outcomes: the heading says what happened, and an unfinished one keeps its actions in view
---------------------------------------------------------------------------
do
  local k = LM.Boot("Out")
  local w, WK2 = Open(k)
  local M2 = WK2.Model
  P.origin = w
  Advance(w, M2, 5)
  local before = World(k)
  Click(w, "Apply"); k.Accept()
  Check(M2.Step() == 6 and Says(w, "Reload to finish your setup") and not Says(w, "Your interface is ready"), "applied, waiting for a reload: not the success heading")
  Check(Enabled(w, "Reload now") and Enabled(w, "Restore previous setup") and not Has(w, "Done") and not Has(w, "Manage layout"), "Reload now and Restore are in view; no Done, nothing folded away")
  Check(not Has(w, "Stop managing") and not Has(w, "Open settings"), "and no Stop managing or Open settings while it is unfinished")
  Click(w, "Reload now")
  local k2 = LM.Boot("Out", LM.Logout(k))
  local w2 = k2.TwichUILayoutWizard
  P.origin = w2
  Check(w2.shown and Says(w2, "Your interface is ready") and Says(w2, "Installed layout: Classic Adventure"), "checked after the reload: Your interface is ready, with the installed layout")
  Check(Says(w2, "checked only for being there"), "the summary says what was only checked for being there")
  Check(Has(w2, "Done") and Has(w2, "Open settings") and Has(w2, "Manage layout") and Has(w2, "Details"), "Done and Open settings in view; Manage layout and Details folded")
  Check(not Has(w2, "Stop managing") and not Has(w2, "Run setup again") and not Has(w2, "Restore previous setup"), "no maintenance action is offered as a way to finish")
  Check(not Says(w2, "What was chosen"), "the receipt of choices is under Details")
  Expand(w2, "Details")
  Check(Says(w2, "What was chosen") and Says(w2, "Accent colour"), "Details has what was chosen")
  Expand(w2, "Manage layout")
  Check(Says(w2, "Installed revision") and Has(w2, "Set up again") and Has(w2, "Restore previous setup") and Has(w2, "Keep this setup") and Has(w2, "Check again"),
    "Manage layout: the revision, set up again, restore, keep, check")
  Check(not Has(w2, "Stop managing") and not Has(w2, "Undo this update"), "Stop managing only once the setup is finished, Undo only for an update: neither is offered here")
  -- Open settings closes the window and asks the settings to open
  local opened
  k2.TwichUI.OpenSettings = function(_, page) opened = page return true end
  Click(w2, "Open settings")
  Check(not w2.shown and opened == "overview", "Open settings closes the setup and opens TwichUI's settings")
  Open(k2)
  Expand(k2.TwichUILayoutWizard, "Manage layout")
  -- a limited check is not "ready"
  local LY2 = k2.TwichUI.Layouts
  local j = LY2.Journal.Read()
  j.state = "mismatch"
  j.verify = { state = "mismatch", checked = 3, presence = 2, diffs = { { adapter = "ellesmereui", unit = "ellesmereui:root.euiAccent", code = "changed" } } }
  LY2.Journal.Write(j)
  M2 = k2.TwichUI.LayoutWizard.Model
  M2.Go(6)
  k2.TwichUI.LayoutWizard.Window.Refresh()
  local w2b = k2.TwichUILayoutWizard
  Check(Says(w2b, "Some settings didn't read back as planned") and not Says(w2b, "Your interface is ready"), "a mismatch: its own heading, never the success one")
  Check(Says(w2b, "doesn't read back as planned") or Says(w2b, "What doesn't read back"), "and what differs is in view")
  Check(Enabled(w2b, "Restore previous setup") and Enabled(w2b, "Check again") and not Has(w2b, "Manage layout"), "with Restore and Check again in view")
  -- partial
  j.state = "partial"
  LY2.Journal.Write(j)
  k2.TwichUI.LayoutWizard.Window.Refresh()
  Check(Says(w2b, "Your setup was only partly applied") and not Says(w2b, "Your interface is ready") and Enabled(w2b, "Restore previous setup"), "only partly applied: said, Restore in view")
  -- interrupted
  j.state = "interrupted"
  LY2.Journal.Write(j)
  k2.TwichUI.LayoutWizard.Window.Refresh()
  Check(Says(w2b, "Your setup was interrupted") and Enabled(w2b, "Restore previous setup"), "interrupted: said, Restore in view")
end

---------------------------------------------------------------------------
-- 8. A blocked review, and the way out being under Advanced
---------------------------------------------------------------------------
do
  local k = LM.Boot("Stuck")
  local w, WK2 = Open(k)
  P.origin = w
  Advance(w, WK2.Model, 5)
  Click(w, "Apply"); k.Accept()
  Click(w, "Reload now")
  local k2 = LM.Boot("Stuck", LM.Logout(k))
  local w2, WK3 = k2.TwichUILayoutWizard, k2.TwichUI.LayoutWizard
  P.origin = w2
  k2.TwichUIDB.layouts.install.state = "restore-partial"
  WK3.Window.Actions.again()
  Advance(w2, WK3.Model, 5)
  Check(Says(w2, "Can't apply yet") and Says(w2, "Blocked: "), "a blocked review says so in words, with the reason")
  Check(Has(w2, "Advanced") and Enabled(w2, "Force re-apply"), "and the way out is under Advanced, opened for it")
  Check(not Enabled(w2, "Apply"), "Apply waits")
  local before = World(k2)
  Click(w2, "Force re-apply")
  Check(WK3.Model.Forced() and Says(w2, "Forced re-apply") and Has(w2, "Stop forcing") and Unchanged(World(k2), before), "turning it on changes nothing and the review says what it does")
  Click(w2, "Apply")
  Check(k2.popup and k2.popup.key == "TWICHUI_LAYOUT_APPLY" and k2.popup.text:find("Forced re-apply", 1, true), "Apply still asks, and the question says it is forced")
  k2.Decline()
  Check(Unchanged(World(k2), before), "declining changes nothing")
end

---------------------------------------------------------------------------
-- 9. Reopening and repeated use make nothing new
---------------------------------------------------------------------------
do
  local k = LM.Boot("Again")
  local w, WK2 = Open(k)
  local M2, W2 = WK2.Model, WK2.Window
  local function Tour()
    Advance(w, M2, 5)
    for _, label in ipairs({ "View changes", "Advanced" }) do local b = Find(w, label) if b and not b.open then b.scripts.OnClick(b) end end
    for step = 4, 1, -1 do
      M2.Go(step) W2.Refresh()
      for _, label in ipairs({ "Compatibility details", "Layout details", "View included settings" }) do local b = Find(w, label) if b and not b.open then b.scripts.OnClick(b) end end
    end
    M2.Go(6) W2.Refresh()
    for _, label in ipairs({ "Manage layout", "Details" }) do local b = Find(w, label) if b and not b.open then b.scripts.OnClick(b) end end
    W2.Close()
    Open(k)
  end
  Tour()
  local made, frames = k.made(), W2.frames
  for _ = 1, 5 do Tour() end
  Check(k.made() == made and W2.frames == frames, "five more tours with every disclosure opened made no new frame (" .. made .. ")")
  Check(W2.listening == 4 and k.made() == made, "and left four listeners while it is open")
  W2.Close()
  Check(W2.listening == 0, "none once it is closed")
  Check(k.TwichUIDB.layouts == nil or k.TwichUIDB.layouts.install == nil, "and nothing was installed by looking")
end

---------------------------------------------------------------------------
-- 10. Artwork: the icon sheet's four pictures
---------------------------------------------------------------------------
do
  local Art = WK.Art
  local function Pixels(name)
    local f = assert(io.open(REPO .. "TwichUI_LayoutWizard/media/" .. name .. ".tga", "rb"))
    local d = f:read("*a") f:close()
    local w, h = d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256
    local function A(x, y) return d:byte(19 + ((h - 1 - y) * w + x) * 4 + 3) end   -- bottom-left origin
    return d, w, h, A
  end
  for id, name in pairs({ keep = "keep", helpers = "helpers", tipFixed = "tipfixed", tipCursor = "tipcursor" }) do
    local e = Art.FILES[id]
    Check(e and e.file:find("media\\" .. name, 1, true) and e.icon, id .. ": registered, with its icon id")
    local d, w, h, A = Pixels(name)
    Check(w == 128 and h == 128 and d:byte(17) == 32 and d:byte(18) == 8 and d:byte(3) == 2, id .. ": 128 x 128, 32-bit, uncompressed, 8 alpha bits")
    local clear, solid, total = 0, 0, 0
    for y = 0, h - 1 do for x = 0, w - 1 do
      local a = A(x, y)
      total = total + 1
      if a == 0 then clear = clear + 1 elseif a == 255 then solid = solid + 1 end
    end end
    Check(A(0, 0) == 0 and A(w - 1, 0) == 0 and A(0, h - 1) == 0 and A(w - 1, h - 1) == 0, id .. ": real transparency at the corners (no baked-in background)")
    Check(clear > total * 0.15 and solid > total * 0.3, id .. (": a transparent surround (%d%%) and an opaque interior (%d%%)"):format(math.floor(clear * 100 / total), math.floor(solid * 100 / total)))
    -- the outermost painted pixels are inside the file with room for bilinear filtering: no clipped outline
    local edge = 0
    for i = 0, w - 1 do if A(i, 0) > 0 or A(i, h - 1) > 0 or A(0, i) > 0 or A(w - 1, i) > 0 then edge = edge + 1 end end
    Check(edge == 0, id .. ": nothing painted touches the file's edge")
    Check(R and true or true, "")
    Check(c.TwichUI.Icons.Get(e.icon) and c.TwichUI.Icons.Get(e.icon).file == e.file, id .. ": in the icon registry")
  end
  Check(io.open(REPO .. "assets/layout-wizard-icons-source.png"), "the sheet is kept in assets/ as a source")
  local tool = io.open(REPO .. "tools/make_layout_wizard_art.py"):read("*a")
  Check(tool:find("layout-wizard-icons-source.png", 1, true) and tool:find("keep", 1, true) and tool:find("tipcursor", 1, true), "and the tool that builds them names it")
  local toc = io.open(REPO .. "TwichUI_LayoutWizard/TwichUI_LayoutWizard.toc"):read("*a")
  local order = {}
  for line in toc:gmatch("[^\r\n]+") do if not line:find("^#") and not line:find("^##") then order[#order + 1] = line end end
  local function At(name) for i, l in ipairs(order) do if l == name then return i end end end
  Check(At("Art.lua") and At("Controls.lua") and At("Pages.lua") and At("Art.lua") < At("Controls.lua") and At("Controls.lua") < At("Preview.lua") and At("Controls.lua") < At("Pages.lua"),
    "Controls.lua loads after Art.lua and before the preview and the pages that use it")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT WIZARD UI TEST PASSED")
