# RestedXP skin

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
  `RXPFrame.CurrentStepFrame.UpdateText`, `addon.UpdateGuideFontSize`, and the `UpdateVisuals` of the item
  and target trays once they exist. Each does comparisons first and draws only what differs. No
  `OnUpdate`, no ticker, no polling: RestedXP loading later is caught by `ADDON_LOADED`.
* **Combat:** nothing is drawn or refreshed in combat; the latest request waits for
  `PLAYER_REGEN_ENABLED`. A skin turned off in combat gives RestedXP's setting back at once and finishes
  the repaint when combat ends.

## Surfaces

| Surface | Handling |
| --- | --- |
| Header (guide name), footer, steps panel, step cards, step number tabs | background + border finish, banner art hidden |
| Step and objective text, list rows, header/footer text | text colour (only RestedXP base colours), font face, outline |
| Step list rows and their hover | theme colours (`bottomFrameBG`, `bottomFrameHighlight`) |
| Scroll bar | tinted with the border colour (RestedXP's own DarkMode art) |
| Item tray and target tray (frame and title tab) | same finish, when RestedXP shows a backdrop on them |
| v2 guide window (beta), map arrow and pins | theme colours/font only; not drawn on |
| Right-click menus, tooltips, RestedXP options, tracker, talents, importer | not touched |

Not supported by RestedXP's theme interface and therefore not offered: text size (RestedXP's **Guide
Font Size** governs it), per-element colours, recolouring check boxes (completion state is meaningful).

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

1. TwichUI + RestedXP without EllesmereUI; 2. with EllesmereUI; 3. RestedXP loading before/after TwichUI;
4. default look; 5. background/border texture, colour, opacity; 6. fonts and long step text (layout
settles); 7. warning/completion/link colours unchanged; 8. guide changes and recycled step cards;
9. move/resize the window; 10. UI scales and window sizes (1 px border stays 1 px); 11. RestedXP profile
switch, Reset appearance (progress, positions and RestedXP settings untouched); 12. disable/re-enable and
restoration; 13. changes in combat; 14. another RestedXP skin on; 15. a font pack disabled; 16. guide
progression and clickable actions unchanged; 17. repeated changes without sustained growth; 18. memory and
CPU comparison per the steps above.
