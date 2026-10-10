# RestedXP skin

The settings are a page of their own, **Addon skins > RestedXP guide window** (a nested page of the Addon skins page, which keeps a short pointer to it).

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
  the repaint when combat ends.

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
