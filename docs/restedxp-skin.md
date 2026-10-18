# RestedXP skin

The settings are a page of their own, **RestedXP** (listed under Other addons, after Addon skins; the Addon skins page keeps a short pointer to it). The page also holds the map waypoint switch, **Mark RestedXP's destination**.

An optional look for the RestedXP Guides window (`modules/RestedXPSkin.lua`, `diag/RestedXPSkin.lua`).
Written against RestedXP Guides v4.11.22 (Interface 16001 listed). Off by default.

## How it works

* **A theme, through RestedXP's own interface.** One table named `TwichUI` is handed to RestedXP once
  (the `RXPGuides_Themes` channel while RestedXP is not up yet, `RegisterTheme` after) and changed in
  place, so a settings change allocates nothing. RestedXP reads background colour with opacity, row
  colours, map pin and text colour and the font face from it when it paints.
* **A finish for what a theme cannot express** (border colour/thickness/texture, background texture,
  fonts and outlines on text it has already made, scroll bar tint). It uses `MenuStyle` (the look the
  Mage menus and refreshments panel share) on RestedXP's own `BackdropTemplate` frames, and only on a
  frame that is showing one of RestedXP's own backdrop tables.
* **Active only while RestedXP's theme is TwichUI's.** Turning the skin on selects the theme and
  remembers the previous name (`ui.restedxpSkinState.previousTheme`, the only thing kept). Choosing
  another theme in RestedXP, or another RestedXP profile, steps the skin aside; choosing TwichUI again
  brings it back. Turning the skin off restores the remembered theme and runs RestedXP's own
  `RenderFrame`, then removes TwichUI's overlays and puts back only text colours and fonts that still
  carry what this skin applied. No per-frame snapshots exist, so a recycled frame cannot be restored to
  a stale state.
* **Hooks** (installed once, gated on the skin being active): `addon.RenderFrame`,
  `RXPFrame.CurrentStepFrame.UpdateText`, `addon.UpdateGuideFontSize`, the `UpdateVisuals` of the item
  and target trays once they exist, and the footer menu button's OnEnter/OnLeave (its tooltip). Each does
  comparisons first and draws only what differs. No `OnUpdate`, no ticker, no polling: RestedXP loading
  later is caught by `ADDON_LOADED`. A layout change that has to wait for RestedXP's own layout to finish
  uses one zero-delay call.
* **Combat:** nothing is drawn or refreshed in combat; the latest request waits for
  `PLAYER_REGEN_ENABLED`. A skin turned off in combat gives RestedXP's setting back at once and finishes
  the repaint when combat ends. A skin turned on in combat chooses its theme when combat ends. When only
  RestedXP's own redraws were passed over (a step completed mid-fight), combat's end finishes them with one
  step layout, one list layout and the padding, not RestedXP's full refresh, which reloads the guide; a
  theme change that waited still gets that refresh.

## Surfaces

| Surface | Handling |
| --- | --- |
| Header (guide name), footer, steps panel, step cards, step number tabs | background + border finish, banner art hidden |
| Step and objective text, list rows, header/footer text | text colour (only RestedXP base colours), font face, outline |
| Step list rows and their hover | theme colours (`bottomFrameBG`, `bottomFrameHighlight`) |
| Scroll bar | RestedXP's own slider, restyled slim in place (see Layout); or tinted as it was |
| Item tray and target tray (frame and title tab) | same finish, when RestedXP shows a backdrop on them |
| v2 guide window (beta), map arrow and pins | theme colours/font only; not drawn on |
| Right-click menus, tooltips, RestedXP options, tracker, talents, importer | not touched |

Not supported by RestedXP's theme interface and therefore not offered as theme values: per-element
colours, recolouring check boxes (completion state is meaningful). Text size is done by the layout finish
below, not the theme.

## Layout (the cleaner window)

Verified in `GuideWindow.lua` v4.11.22 before any of it was written:

| Piece | What it is | Handling |
| --- | --- | --- |
| `GuideName.icon`, `GuideName.classIcon` | plain textures (logo, class badge); no click action | `Hide()` (survives RestedXP's `SetTexture` on refresh, so nothing watches them); title anchors collapsed from RestedXP's 29 px left reserve to 10; a badge shown alone sits at the header's left |
| `GuideName.text` | the guide's title | can be hidden (`Hide()`); the header is then a 14 px strip with no background or border (`ClearBackdrop`; the step panel and the list hang from it, and it is still the drag handle and right-click menu), and the title is a line in the cog's tooltip |
| `GuideName` (35 px) | header frame; owns drag and right-click menu | height fitted to the wrapped title (26-84); scripts untouched |
| `Footer.text` | version and guide-format range (`BetaVersionCheck`) | subdued (smaller, 70 %), hidden, or as RestedXP draws it; the same text is in the cog's tooltip |
| `Footer.cog` | the footer's menu button (`DropDownMenu`); no tooltip of RestedXP's | `HookScript` OnEnter/OnLeave once; tooltip only while the skin is active; can be hidden (`Hide()`), the header's right click opens the same menu |
| `Footer.icon` | the resize grip (a button; mouse down starts `StartSizing`) | can be hidden (`Hide()`: RestedXP's timers change its strength, never its visibility); Alt + drag on the window resizes as before unless RestedXP's frames are locked |
| `ScrollFrame.ScrollBar` | template slider: thumb, up/down buttons | restyled in place (see Scroll bar below); range, wheel, dragging and arrows are the template's and RestedXP's |
| `ScrollChild.framePool[n]` | list rows: `text`, `number`; OnEnter/OnLeave set again on every guide load | text 6 px in and 4 below the top (RestedXP's row is text + 8 high: centred), number 6 px in and quieter, gap widened by the step padding; OnEnter wrapped so a dimmed (done) row rises 40 % of the way to full strength instead of all of it |
| `CurrentStepFrame.framePool[n]` | step cards: `number` tab, `elements[j]` (check, text, icon) | sizes and spacing; padding under each line; tab roomier and moved 2 px in, first line pushed down by the step padding plus 4 (RestedXP puts it flush against the tab; with a padding of 0 it is RestedXP's own) and further for a taller tab |

The dark circle beside the scroll arrows in the reference screenshot is the scroll thumb (`Knob.blp` is a
dark filled circle), not the class icon (`MAGE.blp` etc.): verified by decoding the textures.

The current-step panel is anchored to the header (`SetStepFrameAnchor`), so it moves with the window; only a
tip window is independently movable, and its anchors are never touched.

### Scroll bar

The template's bar is the old arrow-button slider (`UIPanelScrollBarTemplate`), not the modern ScrollBar, so
EllesmereUI's published `S.ScrollBar` (which handles `Track`/`Back`/`Forward`) does not apply and its
`AttachSmoothScrollbar` helper would replace the frame's wheel and range scripts. The skin draws it the way
EllesmereUI's own window packs draw this template (`EllesmereUIBlizzardSkin_WindowPacks.lua`): stock arrow art
faded to alpha 0 (the buttons stay, with their clicks and enable states), the thumb texture a `WHITE8X8`
strip. With EllesmereUI loaded (`EllesmereUI.ICONS_PATH`, its published media path), its `eui-arrow-up3` /
`eui-arrow-down3` icons are drawn on the buttons at 0.6, 1 under the pointer, 0.25 when the button cannot
scroll (the values its own bars use), through `OnEnter/OnLeave/OnEnable/OnDisable` hooks added once. Without
EllesmereUI the buttons show the game's own `UI-ScrollBar-*` arrows. The strip is the border colour at half
strength (the "tint" setting) or EllesmereUI's neutral white at 0.3; the track is the same colour at 0.08.

### List and footer no longer overlap

RestedXP anchors the list frame's bottom edge 14 px above the window's while the footer is 20 high, so the
list runs 6 px behind the footer. Under this look (borders, and the fade above) that showed through, so the
list's bottom edge is anchored at the footer's height instead. The anchor is captured once and restored. The
list frame is 6 px shorter and RestedXP works the scroll range out from that frame's height, so the range
follows; the point at which RestedXP hides the list for a very short window moves up by the same 6 px.

### Footer bar with neither button

With the menu button and the resize handle both hidden the footer frame is hidden too (`Hide()`; RestedXP
never shows or hides it), together with its version string, which belongs to the header's frame but has
nothing left to sit with. The list's bottom edge then moves from the footer's top to the window's bottom
(captured once, restored). RestedXP's timer bars are anchored to the footer's rectangle, which stays; while
one runs it draws over the bottom of the list.

### The waypoint arrow

`addon.arrowFrame` (`RXPG_ARROW`, `map.lua`): a 32 x 32 frame (times RestedXP's Arrow Scale) with one texture
RestedXP rotates from its own `OnUpdate` (`DrawArrow`) and a string for the step and the distance. This skin
adds no `OnUpdate`, and changes neither the rotation nor the text. RestedXP sets the picture in the arrow's
`UpdateVisuals` (every theme refresh and `SetupArrow`), the size in `SetSize` (login, its Arrow Scale option,
a profile change) and the string's font in `SetFont` (login, its Arrow Text Size option), so those three are
hooked once and what RestedXP just set is scaled:

| Setting | Effect |
| --- | --- |
| Shape | the texture file: TwichUI's bronze plate (`media/textures/arrow-bronze.tga`, 128 x 128, 32-bit; the default), or: a RestedXP theme's `texturePath` + `rxp_navigation_arrow-1` (the same call RestedXP's `GetV1Texture` makes), a v2 theme's `navigationArrow`, or EllesmereUI's `eui-arrow-up3` chevron when `EllesmereUI.ICONS_PATH` is there. All point up, which RestedXP's rotation relies on (I decoded RestedXP's seven; the chevron is a white up arrow). A shape that is not there is drawn as the default and stays chosen. |
| Colour, opacity | the texture's vertex colour and alpha (the arrow frame's own strength is RestedXP's, set 0 or 1 to show and hide it) |
| Size | a percentage (50-250) of RestedXP's `32 * arrowScale`; applied to what `SetSize` was just given, so it never accumulates |
| Text shown, text size | `Hide()` on the string; the size a percentage (60-200) of what `SetFont` was just given |

The bronze plate is artwork supplied by the project owner (source `assets/arrow-bronze-source.png`, 1254 x 1254, which
packaging ignores); the texture is it cropped to its edges with a 3 % margin and averaged down, premultiplied by
its alpha. It is TwichUI's own file, so it needs nothing from RestedXP or EllesmereUI.

With the skin off (or another theme chosen) everything is put back: RestedXP's own `UpdateVisuals`, no tint,
`32 * arrowScale`, and `arrowText`.

### Fading the guide list

The list is faded as one container: `BottomFrame` (its background and border, the scroll frame and bar, and
the rows, which are its children) and `Footer` (its border, and the resize grip, which is its child) get the
frame strength `1 - fade` (the setting, 0-70 %, default 35). RestedXP never sets the strength of those two
frames. It does set the footer's string (a child of the header's frame, not the footer), the cog (a child of
the window) and the grip to 0 or 1 itself while a timer bar shows (`Timers.lua`), so the string and the cog
are faded individually and only while they are not hidden: a hidden one stays hidden, and one RestedXP
restores is faded again on the next pass. The header and the current-step panel are not part of it.

### Hover on a list row

RestedXP's row `OnEnter` remembers the row's strength, sets it to full and fills the row with the theme's
`bottomFrameHighlight`. A done row is at half strength, so that was a jump to bright. The theme's highlight is
now the row colour a quarter of the way to the border colour (it was the border colour at half opacity, a
bright slab with a light border), and the row's `OnEnter` is wrapped (RestedXP's handler runs first, then a
dimmed row is eased to 40 % of the way up). `OnLeave` is RestedXP's and restores what it remembered.

### Text sizes and layout settling

* RestedXP sizes strings from its **Guide Font Size** (header +2, footer +0, step text +2, tab +0, list text
  +0, list number -1). Until "Set text sizes here" is on, sizes are RestedXP's; with it on, the three sizes
  are used (list numbers one smaller, the tab two smaller than the step text, the footer two smaller than the
  title, one more when subdued). Turning it off puts every string back to RestedXP's own size, including
  recycled ones.
* Heights are never computed here. After a layout setting changes (or RestedXP resets a string this skin had
  styled) RestedXP's own `CurrentStepFrame.UpdateText` runs once, then the step padding is added to the
  heights it just set. The list is laid out with `BottomFrame.UpdateFrame` called with a `self` that has no
  step, which is the call RestedXP itself makes every frame while the window is resized (it lays out all rows
  and the scroll extent and does not call any guide step's update). The padding is added only straight after
  RestedXP's own layout and only once per layout, so repeated refreshes do not accumulate it; with no guide
  loaded RestedXP lays nothing out, and nothing is added.
* The list's scroll extent follows the rows' real positions (RestedXP measures first row to last row), so a
  wider row gap needs no extra arithmetic. The list's own frame is deliberately not moved: RestedXP derives
  the scroll range from frame heights, and a shorter viewport would cut off the last row.

### Restoration

Anchors and sizes RestedXP sets once (header title, badge, header height, scroll bar, thumb and button
sizes, thumb coordinates) are captured once, before the first change, and put back from that. Row text, gap
and number anchors are RestedXP's constants (it sets the text and gap again on every guide load, the number's
only when it makes the row) and are put back by value. Everything else is put back by RestedXP's own refresh
(`RenderFrame`), plus `UpdateScrollBar` for the scroll bar art.

## The current-step panel

Two small additions to RestedXP's panel of step cards (`CurrentStepFrame`), both in the skin's own pass and
both under **RestedXP > Current step**.

### Step tab: Step X, X/Y, with a percentage

What RestedXP does (v4.11.22, `GuideWindow.lua`): `LoadGuide` runs `step.index = n` over
`addon.currentGuide.steps`, the list `ProcessGuideTable` built for this character (steps whose `<<` conditions
do not apply, and steps hidden by `IsStepShown`, are not in it, so there is nothing to filter again). The tab
says `step.title or fmt(L("Step %d"), step.index)`; the list's rows count `n` the same way. So:

| | Source | Meaning |
| --- | --- | --- |
| X | `step.index` of the card's step | RestedXP's own number, as the list shows it |
| Y | `#addon.currentGuide.steps` | the length of the list X is a position in: every step, including optional and hidden-row steps and ones with nothing to do (it is the last row's number) |
| % | `floor((200 X + Y) / (2 Y))` | X / Y rounded half up, 0-100; the last step is 100 %. It is position in the guide's steps, not time spent, travel, or verified quest completion |

* **No cache.** `currentGuide` is replaced when RestedXP loads a guide and `#steps` is read only when a tab is
  drawn (a step change), so there is nothing to invalidate. (A pooled card's text is remembered only to know
  what this skin wrote.)
* **When a tab is not touched:** it has a title of its own (a tip, a guide's custom title), the step is sticky
  (RestedXP draws its tab hidden), `steps[index]` is not that very step (a number from another list is never
  paired with this total), the guide or its list is missing, or RestedXP's `locale.Get` is not there. The tab
  is then RestedXP's own `Step X`; `/tui diagnostics` counts these and says why. `0/0`, `nan` and a total
  smaller than the number cannot be drawn.
* **Wording:** the number in RestedXP's own text is replaced (`Step 5` -> `Step 5/120 (4%)`, `第 5 步` ->
  `第 5/120 (4%) 步`), so the language stays RestedXP's.
* **When:** RestedXP sets every tab's text in its `UpdateText` (also on each step change); the skin's hook
  for that runs the labels after RestedXP's layout and before the padding (which sizes the tab from its
  text). A format change alone relabels the visible cards and refits the tabs, with no RestedXP layout.
* **Narrow panels:** the whole label is used if it fits between the tab's place and the menu button's room
  (`width - 9 - 22`); else `X/Y` (for the percentage formats); else `Step X`. Measured only when a tab is
  drawn, not while the window is dragged wider or narrower (the release of a resize runs RestedXP's layout).
* **Combat:** nothing is applied in combat (the rule of the whole skin); the tab shows RestedXP's text and
  changes when combat ends.
* **Restore:** turning the skin off puts RestedXP's text back through its own refresh, and the strip does it
  itself for a tab that still shows what this skin wrote (a text another addon wrote is left alone).

### Menu button on hover

* **What it does:** `RXPFrame.DropDownMenu()`, resolved at click time, which is exactly the footer cog's
  `OnClick` (`Footer.cog:SetScript("OnClick", function() RXPFrame.DropDownMenu() end)`; the header's right
  click calls the same). The cog is a plain Button (left click only), so is this. It is RestedXP's menu
  (choose a guide, go to a step, Options...); it does not open TwichUI's skin settings. It does not depend
  on the cog being shown.
* **Where:** a 14 px child of `CurrentStepFrame`, `TOPRIGHT` at (-4, -2), above the cards. RestedXP's
  first line of text begins 11 px under its card's top; the first card's lines are therefore pushed to start
  at least 5 px lower (the skin's step padding already does 6 by default), always, so nothing moves when the
  button appears. The hit area is 3 px larger than the picture on its sides and top, not below.
* **Picture and look:** RestedXP's own `rxp_cog-32` (the file named by `GetV1Texture`, as the footer cog
  uses; read at run time, never copied), tinted with the skin's title colour; the background and a 1 px
  border in the skin's look, lighter on hover and darker pressed. Not a textured border: at 14 px it would be
  a blob.
* **Hover without polling:** `OnEnter` is hooked (`HookScript`, once per frame) on the panel, on each card and
  on each line's check box; a line's own `OnEnter` is RestedXP's, set when it makes the line and cleared on
  every step change, so it is wrapped after each layout (RestedXP's runs first), as the list rows are. An
  enter only counts while `panel:IsMouseOver()`, which keeps a tip window (a frame of RestedXP's elsewhere)
  from showing it. While shown, the button runs one `OnUpdate` throttled to 0.1 s that checks
  `IsMouseOver` of the panel and the button (geometry, so moving between a card, a line and the button never
  flickers) and whether RestedXP's menu is open (`L_DropDownList1` shown and `L_UIDROPDOWNMENU_OPEN_MENU` is
  RestedXP's `MenuFrame`, or the game's `DropDownList1` equivalents). A hidden frame's `OnUpdate` does not
  run, so nothing runs while it is not shown; a tip card is not hooked.
* **Combat:** showing, hiding and clicking are on plain frames and are allowed; drawing it (building,
  texture, colours) waits for the pass, which is not run in combat.
* **Lifetime:** one button for the window's life (re-parented if RestedXP ever hands a different panel). The
  option off, the skin off, or another theme hide it and put RestedXP's line `OnEnter` back. Hover state is
  never saved.

Saved: `ui.restedxpSkinText.stepLabel` (`step` / `total` / `percent` / `both`, default `step`: existing players
see no change) and `settingsButton` (default on, with the skin).

### Borders and scale

A border's thickness is worked out in UI units, for the scale its frame has when it is drawn (one screen pixel
at any scale; `MenuStyle`). RestedXP scales its windows after the skin has first drawn (login) and again
whenever its Window, Active Items or Active Targets scale slider moves, and the game's own UI scale can
change. Each of those draws the borders again (one debounced pass, borders only: RestedXP is not asked to
refresh and nothing is laid out again): `SetScale` on the window and on the two trays is hooked once, and
`UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED` are listened for while the skin is on.

An EllesmereUI border texture is drawn by EllesmereUI's `ApplyBorderStyle`, which sizes the edge in pixels at
UIParent's scale; the backdrop then shrinks with RestedXP's window scale (a 12 px Pixels Textured edge at a
0.5 window scale was 6 px, its line under a pixel). `MenuStyle` passes its `normalizeScale`, so the edge is the
chosen number of screen pixels on the scaled window too, as the plain line is.

## Media

Backgrounds and borders: `MenuStyle`'s lists (game textures, LibSharedMedia, EllesmereUI's when it is
installed). Fonts: LibSharedMedia's `font` list, cached and rebuilt only after a font registers. EllesmereUI's
own fonts are offered only if it registers them with LibSharedMedia (unverified). Saved ids are never
overwritten when media is missing; a missing or unusable file is drawn as RestedXP's own font and is
listed "(not available)". A disabled provider's files remain usable only while LibSharedMedia still lists
them; once the list drops them the fallback applies and the choice is kept.

## Licensing

* EUI-RestedXP: All Rights Reserved; nothing copied or required. Its engine is adapted from LiteTweaks
  with permission to that author only.
* RXPGuides: CC BY-NC-SA 4.0; nothing copied or bundled. The theme references RestedXP's installed
  `Textures\DarkMode\` path at run time, as RestedXP's own DarkMode theme does.
* EllesmereUI: license not available locally; only its runtime API (already used by `Borders.lua` /
  `MenuStyle.lua`) is called.

## Conflicts

Recognised: EUI-RestedXP with its reskin on and a layout other than `DEFAULT`, and LiteTweaks with
`rxpEnabled` not false. Other RestedXP skins cannot be recognised and may fight this one.

## Reference plugin review (source-level; nothing here is a measurement)

Confirmed in source: full window rebuild per RestedXP refresh (`Reskin.lua` `R.Skin`, hooked on
`UpdateVisuals`, `UpdateText`, `BottomFrame.UpdateFrame`; the last runs every frame while resizing),
per-pass table creation (`used = {}`, `Reskin.lua:1604`), a `C_Timer.NewTicker(0.25)` readiness poll
(`Core.lua:634`), `OnUpdate` animations while cards enter/leave, `ns.ApplyFont` string concatenation and
pcall per call (`Core.lua:39`), font option list rebuilt per call (`Core.lua:133`), and RestedXP settings
rewritten at login (`DisableAnnouncements`). Pools are bounded by the largest pass. Hypothesis, not
confirmed: most of its memory is compiled Lua source (~450 KB of source) rather than retained data.

## Timer bars

RestedXP's countdown bars (waiting for an event or scene, a flight, Hearthstone timing) get the same look,
as a finish on the skin: `modules/RestedXPTimers.lua`. It is an extension of the skin, not a second timer
system: RestedXP starts, counts down and ends every bar exactly as before.

### What the bars are (RXPGuides v4.11.22, read from source)

| Piece | Source | Notes |
| --- | --- | --- |
| `addon.StartTimer(duration, label)` | `Timers.lua` | the one place any bar is started: guide steps' `element.timer` / `timerText` (`functions.lua`, `map.lua`: event, RP and scene waits), the flight timer (`PLAYER_CONTROL_LOST`), Hearthstone batching (`HSBatching.lua`) |
| `barPool`, `CreateBar` | `Timers.lua` | RestedXP's own pool of LibCandyBar bars: a hidden bar is reused, else `candy:New` |
| `BarContainer` (`RXPFrame.BarContainer`) | `Timers.lua` | anchors and stacks the bars on the footer; `.height` (16) is read by `StartTimer` and `SortTimers` |
| `candyBarBar`, `candyBarBackground`, `candyBarLabel`, `candyBarDuration`, `candyBarIconFrame`, `candyBarBackdrop` | `libs/LibCandyBar-3.0` | the fill (a StatusBar), its background texture, the two strings, RestedXP's pocket-watch texture, and a frame the library provides for stylers |

All the timer types share this implementation, so there is one integration and no per-type code. There is no
spark, so none is offered. Bars the library makes for other addons are never touched: only the bar
`StartTimer` just put under a label in `BarContainer.bars` is drawn.

### How it is integrated

* **Hooks (installed once, gated on the skin and its switch):** `hooksecurefunc` on `addon.StartTimer`
  (draw the bar it just started or reused) and `addon.ShowTimers` (RestedXP showed bars it had hidden), plus
  LibCandyBar's `LibCandyBar_Stop` callback. Nothing is hooked per tick: the library's own update, the
  countdown text and the fill's value are never touched, and no `OnUpdate` or ticker is added.
* **When it draws:** at each start (the fill colour and the icon, which RestedXP resets at every start, and
  the text, which the library resets whenever it makes a bar), and when a setting changes (one coalesced
  update after 0.2 s). A bar already drawn for the current settings is skipped.
* **Height** is RestedXP's own `BarContainer.height`, which its stacking reads; `addon:SortTimers()` is run
  once after a change. The bar is never shorter than its text needs (`ceil(size * 1.25) + 2`), so a large
  font is not clipped. Width follows the footer and is not offered.
* **Border and background:** the library's `candyBarBackdrop` frame (one of ours when an older library has
  none), drawn with the shared `MenuStyle` look, just under the fill and just outside the bar's edge, so a
  border never covers the fill and stacked bars keep RestedXP's spacing. The library's own background is
  made transparent while ours is drawn.
* **Text:** the label is at the left and the time at the right. The time takes its own width and the label
  stops at it (word wrap off, so a long label is cut with an ellipsis; bars take no mouse, so there is no
  tooltip: a tooltip would take clicks from the footer's buttons). Padding is in from the bar's ends.
* **Icon:** hidden with the library's own `SetIcon(nil)`, which gives the bar its room (no gap), and set
  again by RestedXP at the next start.
* **Gradient:** `Texture:SetGradient(orientation, ColorMixin, ColorMixin)` (the Forever signature; the old
  seven-argument form is not in its API documentation) on the status bar's texture. The shading spans the
  part of the bar that is filled, so it narrows as the bar runs down. A gradient and a vertex colour share
  the texture's vertex colours, so the colour is set neutral first and the gradient last, with the opacity
  carried by the gradient's colours; clearing it sets a neutral gradient before the colour. If the call
  fails, the average of the two colours is used and `/tui diagnostics` counts it. **Not verified in the
  game.**

### Restoration

* Each bar has one record (a weak-keyed table, reused: starting a timer allocates nothing). It holds a
  snapshot taken the first time the look draws on it (texture, background strength, both strings' font,
  colour and anchors, the icon) and a few flags.
* A bar that stops is put back **at the stop callback**: the library keeps stopped bars in a cache shared
  with every other addon's bars (and RestedXP keeps its pooled bars in that cache too, so one can be handed
  out again), so a bar must never go back carrying this look.
* Turning the look off (the switch, the skin, another RestedXP theme, a conflict, the v2 window) puts back
  every bar drawn, running or not. It never restarts, stops, hides or re-times one.
* The fill's colour and the height are not restored from a snapshot: the colour is RestedXP's
  `colors.mapPins` as it is then, and the height is put back only if it is still the value this set, so a
  newer RestedXP setting is never overwritten.
* In combat nothing is drawn or restored; the latest request waits for `PLAYER_REGEN_ENABLED`. (The bars are
  not protected frames, but their anchors hang from RestedXP's window, so this follows the skin's own rule.)

### Settings (RestedXP > Timer bars)

| Setting | Default | Notes |
| --- | --- | --- |
| Skin timer bars | on | with the skin; never turns the skin on |
| Fill gradient / Fill color / Fill gradient end color | left to right, `#80502D`, `#C69A52` | "None" is one colour |
| Fill opacity | 100 | the fill only |
| Label color / Time color | `#E9E1CF` | warm ivory |
| Label size / Time size | 10 / 10 | 8-18 |
| Show RestedXP's clock icon | off | decoration; off gives its room to the bar |
| Bar height | 16 (RestedXP's) | 12-28; the text's need wins |
| Timer background and border (texture, color, opacity, thickness) | solid, `#17110B` at 85 %, a 1 px `#8C6E38` line at 90 % | "None" textures and a thickness of 0 are supported |
| Text padding, Fill texture, label and time fonts and outlines | 4 px, flat color, the guide's step font, outline | |
| Preview | | two made-up bars (a short and a long label) on frames of their own |
| Reset timer bars | | only the timer bars; not the switch of the skin or its look |

Saved in `ui.restedxpTimerText` and `ui.restedxpTimerLook`; only values the player changed are saved.

### Media

Fill textures: RestedXP's own (the path it gives the library), a flat fill, EllesmereUI's bar textures (its
public `BuildBarTextureTables`, only while it is installed; nothing copied), and every LibSharedMedia
`statusbar` entry (`MenuStyle.StatusBars`). Backgrounds and borders: `MenuStyle`'s lists. Fonts:
`MenuStyle.Fonts` (TwichUI's, EllesmereUI's when registered with LibSharedMedia, then the rest). Ids are
stable names; a missing one is drawn as RestedXP's own texture or the guide's font, stays saved and listed
"(not available)", and is drawn when LibSharedMedia registers it (no list is rebuilt per timer).

### Preview

`TogglePreview` shows two sample bars on a frame of its own beside the Options window. They are built from
plain frames with the library's part names and drawn by the same functions as a real bar. They are **not**
LibCandyBar bars (a bar made with `candy:New` would be taken from the cache every addon's bars share, and
could be one RestedXP is about to reuse), run no countdown, start no timer, call nothing of RestedXP's and
have records of their own. They go away with the Options window, the Preview button, or the skin switch.

### Not covered

RestedXP's v2 guide window (its bars are left as RestedXP draws them), other addons' LibCandyBar bars,
bar width, and any guide-window redesign.

## Manual profiling

1. `/reload` with only RXPGuides; `/run collectgarbage(); UpdateAddOnMemoryUsage(); print(GetAddOnMemoryUsage("RXPGuides"))`.
2. Repeat with EUI-RestedXP, then TwichUI with the skin off, then on. Record client/addon versions.
3. After each step change guides 20 times, open/close RestedXP options 10 times, drag a slider for 10
   seconds, toggle the skin 10 times; `collectgarbage()` and re-measure. Growth that survives a collect is
   retention; growth that falls back is allocation churn.
4. CPU: `/console scriptProfile 1`, `/reload`, then `GetAddOnCPUUsage("!!!TwichUI")` during the same actions.
   `/tui diagnostics` shows pass and refresh counts and the number of frames held.

## In-game checklist (not yet run)

Layout (added with the cleaner window):

L1. Logo and class badge hidden, no gap left of the title; the toggles bring each back; the header menu
(right click) and the cog still open RestedXP's menu. L2. Active-step, list and title sizes change with
"Set text sizes here"; long multi-line steps and long titles are not clipped; turning it off returns
RestedXP's sizes. L3. Inline colours, quest icons, check boxes and clickable text unchanged. L4. Mouse
wheel, thumb drag and both arrows; the first and last row fully reachable at several window heights and
widths; thumb visible; the bar's right padding clear of numbers. L5. Several UI scales and window sizes.
L6. Guide change, "Reload Guide", guide list with 100+ steps (row gap, scroll position of the current step).
L7. Footer subdued / hidden / normal; tooltip on the cog. L8. A tip window and the item tray unaffected.
L9. RestedXP profile change, Reset appearance, turn off and on: everything RestedXP's again; no growth in
`/tui diagnostics` counts. L10. Combat: changes wait.

1. TwichUI + RestedXP without EllesmereUI; 2. with EllesmereUI; 3. RestedXP loading before/after TwichUI;
4. default look; 5. background/border texture, colour, opacity; 6. fonts and long step text (layout
settles); 7. warning/completion/link colours unchanged; 8. guide changes and recycled step cards;
9. move/resize the window; 10. UI scales and window sizes (1 px border stays 1 px); 11. RestedXP profile
switch, Reset appearance (progress, positions and RestedXP settings untouched); 12. disable/re-enable and
restoration; 13. changes in combat; 14. another RestedXP skin on; 15. a font pack disabled; 16. guide
progression and clickable actions unchanged; 17. repeated changes without sustained growth; 18. memory and
CPU comparison per the steps above.

Current step (C1-C15, none run in game yet):

C1. Hover the panel (over text, over a gap, over a tab): the cog appears at its upper-right corner and no text moves.
C2. Move the pointer from the panel onto the cog: it stays. C3. Click it: RestedXP's menu opens at the pointer
(guide list, go to step, Options...); with the footer's menu button hidden in the skin's settings it still works
and the footer button stays hidden. C4. Leave the panel: it goes within a moment; a tooltip is not left behind.
C5. With RestedXP's menu open from it, it stays until the menu closes. C6. Drag the window by the panel's gaps,
click a check box, a link and an action button in the step text: all as before; the first line's text does not
touch the cog (default padding, padding 0, a large font, a narrow window). C7. Each step-label format on the
first, a middle and the last step; the percentage reads 100 at the last. C8. A guide with steps for another class
or faction (the total is the number of the list's last row), a guide with sticky steps and optional steps, a
tip window (tip tab unchanged, hovering it does not show the cog on the panel). C9. Switch guides, load a
guide with no steps, `/rxp` reset: the tab never says 0/0 or nan. C10. A very long guide (hundreds of steps),
large fonts, a 220 px wide window at several UI scales. C11. Switch RestedXP profile, `/reload`. C12. Turn each
option off, then the skin, then on: RestedXP's tab text and hover behaviour return, one cog only. C13. Combat:
the tab shows RestedXP's text and is formatted when combat ends; the cog still shows and opens the menu.
C14. Step completion, skipping and navigation are identical with the look on and off. C15. `/tui diagnostics`
shows the tabs drawn / left alone and the button's counts.

Timer bars (T1-T17, none run in game yet):

T1. An RP / event wait (a guide step with a timer) shows the bar in the look; its countdown, ending and
the step's completion are unchanged. T2. A flight timer (take a flight path with RestedXP's flight timers
on) the same. T3. Hearthstone timing (a Hearthstone cast with the batching option) and a gossip-cancel wait
if available. T4. Two bars at once keep RestedXP's stacking; with the window anchored to the bottom of the
screen they stack upward as before. T5. Fill texture, colour and opacity change on a running bar without
restarting it. T6. Background and border: None, solid, a textured border, thickness 0 and 8; the border
never covers the fill or the text. T7. Gradient left to right and bottom to top and None: look at the fill
at full and at 20 %; if the game draws anything else, set the gradient to None and report it. T8. Label and
time font, size, outline and colour; the label never overlaps the time. T9. A long label on a narrow window,
and size 18 (the bar grows; nothing clipped). T10. The clock icon on and off: no gap when off. T11. A timer
ending and another starting: the same bar is reused and is drawn once (no stale look, no duplicate border).
T12. Change every setting while a timer runs. T13. Turn "Skin timer bars" off, then the whole skin, with a
timer running: RestedXP's own look returns at once, the countdown carries on, its colour is its theme's.
T14. Choose another RestedXP theme, switch RestedXP profile, `/reload`. T15. With and without EllesmereUI
(its textures listed or not; saved EllesmereUI textures stay chosen). T16. Durations, countdown text and
guide progression identical with the look on and off (compare a flight's time to the same flight with the
look off). T17. Start 30 timers: `/tui diagnostics` shows one bar record per pooled bar and no growth in
frames drawn on; with BigWigs or DBM installed, a BigWigs bar made after a RestedXP bar stopped has no
TwichUI look. The preview: opens beside Options, follows every change, is gone when Options closes, and never
shows up in RestedXP's footer.
