# Feature icons: source, runtime files and registry

The icons beside feature names in the settings window (its left-hand list, Home's feature tiles and ways in, and
feature cards that name one) come from one registry, `!!!TwichUI/Icons.lua` (`R.Icons`). This page lists every icon,
where its runtime file is, how the files were made and what is known to be imperfect.

## Source

| | |
|---|---|
| Originals (never changed) | `../assets/Fantasy Medieval Icon Grid.png`, `Fantasy RPG Inventory Icon Set.png`, `Fantasy Duel Ban and Keybind Icons.png`, outside the repository (sheets 1 to 3) |
| Copy in the repository | `assets/settings-icons-source.png` (byte-identical; sha256 `dcb88def6f297bdc9f756224255dd14c4f854ffb2651aeac35bca87693470d60`); sheets 2 to 5 are `assets/settings-icons-2-source.png` to `-5-source.png` (below) |
| Format | PNG, 1254 x 1254, 8-bit RGBA, not interlaced |
| Layout | 4 columns x 4 rows, row-major in the order below |
| Background | Already transparent: every corner and gutter pixel is alpha 0. No white background to remove. |

`assets/` is not packaged (`.pkgmeta` ignores it).

## How the runtime files are made

```
python3 tools/make_settings_icons.py            # writes !!!TwichUI/media/icons/*.tga
python3 tools/make_settings_icons.py --check    # builds nothing; prints bounds, holes and sizes
python3 tools/make_settings_icons.py --contact-sheet docs/settings-icons-contact-sheet.png
```

Standard library only, like the other `tools/make_*.py` (it reuses `make_map_tool_icons.py`'s PNG reader and
premultiplied-alpha box filter). `tools/` is not packaged.

1. **Haze removal, by shape.** The sheet's transparency left a faint haze around most icons: about 39,000 red and
   8,000 yellow pixels (plus near-black ones) at alpha 1..63, reaching across the grid lines. The solid artwork is
   taken as alpha >= 128; its 8-connected parts are found over the whole sheet and each goes to the icon whose
   grid cell holds its centre (one part per icon, three for the crystals; none stray). Below 128, a pixel is kept
   only within 3 source pixels of its icon's solid artwork (the antialiased edge), with its colour taken from the
   nearest solid pixel so the haze can't tint the edge; everything further out is cleared. No colour keying.
2. **Enclosed spaces** are judged separately. Mostly fully clear (>= 25% of pixels at alpha 0) means background, cleaned
   like the outside: the bell's loop, the gap between the pennant's pole and flag, the two spaces between the scale's
   chains, the frame corner's opening. Painted see-through means it is kept exactly: the map pin's centre (453 px,
   2% clear) and two small gaps in the left scale pan.
3. **Bounds from the artwork, not the grid.** Row 1 reaches about 10 px below its cell line (y 323 against 313.5)
   and row 2 starts at y 368, so cells are only used to assign parts; nothing is clipped and nothing from a
   neighbour is included.
4. **Normalising.** Each icon is cropped to its kept pixels, scaled with its aspect ratio kept so its longer side fills
   58 of 64 px (29 of 32), centred, then shrunk part way toward the set's median painted area when it is heavier
   (optical balance; only the supply pouch moves noticeably, to 0.90). Colour is carried 2 px into the clear pixels so
   bilinear filtering shows no dark matte. Nothing is recoloured, sharpened or given a glow.
5. **Output.** Uncompressed 32-bit TGA, bottom-left origin, 8 alpha bits (the format of every other
   `media/textures` file). Two sizes per icon, because the client is not relied on to make smaller copies of an addon
   texture: 64 px for cards and Home (drawn at about 28..40 units) and 32 px for list rows (drawn at 20). The map
   toolbar already ships 32 px icons drawn at 18 for the same reason.

## Runtime files and registry

Sheet 1 icons: `!!!TwichUI/media/icons/<id>.tga` (64 x 64) and `<id>-small.tga` (32 x 32). Registry `size` 64, `pad` 3.

| # | Registry id | Picture | Used by (settings page key) |
|---|---|---|---|
| 1 | `home` | cottage | `overview` (Home) |
| 2 | `notifications` | bell | `notifications` |
| 3 | `qualityOfLife` | feather and cog | `qol` |
| 4 | `markers` | pennant | `markers` |
| 5 | `chatCleaning` | speech bubble and brush | `chatClean` |
| 6 | `foodAndDrink` | bread and cup | `food` |
| 7 | `hazardAlerts` | warning shield | `hazard` |
| 8 | `vendorRestocking` | supply pouch and vials | `restock` |
| 9 | `auctionHouse` | merchant's scales and coin | `auction` |
| 10 | `journeyChronicle` | open journal and ribbon | `chronicle`; Home's "Review changed settings" |
| 11 | `sleepingBag` | rolled bedroll | `cozyBag` |
| 12 | `mapsNavigation` | folded map and pin | `worldMap`, `navigation`; Home's "Explore features" |
| 13 | `gearComparison` | breastplate and arrow | `gear` |
| 14 | `classResources` | three resource crystals | `classBars` |
| 15 | `addonSkins` | paintbrush and frame corner | `skins`; Home's "Adjust appearance" |
| 16 | `profilesSharing` | two portrait medallions | `sharing`, `profiles`; the preview portrait's fallback |

Second sheet (`assets/settings-icons-2-source.png`, the user's "Fantasy RPG Inventory Icon Set.png", same format and
transparency; processed the same way, same two sizes):

| # | Registry id | Picture | Used by |
|---|---|---|---|
| 1 | `targetArt` | dragon head in a bronze corner frame | `targetArt` |
| 2 | `mapPins` | red map pin with teal ripple rings | `pins` |
| 3 | `mapToolbar` | parchment map with a brass compass | `mapToolbar` |
| 4 | `vendors` | merchant stall with striped awning | `npcs` |
| 5 | `mage` | arcane staff with a blue orb | `mage` |
| 6 | `guide` | blue guidebook with a route arrow | `restedxp` |
| 7 | `ammunition` | leather quiver of arrows | `ammo` |
| 8 | `troubleshooting` | magnifying glass over a scroll with a cog | `troubleshooting` |
| 9 | `navigation` | antique-gold compass rose | `navigation` (World map keeps `mapsNavigation`) |
| 10 | `profiles` | one bronze medallion with a red ribbon | `profiles` (Configuration sharing keeps `profilesSharing`) |
| 11 | `explore` | brass spyglass | Home: Explore features |
| 12 | `appearance` | painter's palette and brush | Home: Adjust appearance |
| 13 | `reviewChanges` | ledger with a gold checkmark and quill | Home: Review changed settings |
| 14 | `summons` | stone portal | Quality of life: Accept summons card |
| 15 | `resurrection` | angelic wings around a gold ankh | Quality of life: Accept resurrection card |
| 16 | `releaseSpirit` | crossed banners and a teal wisp | Quality of life: Release in battlegrounds card |

Every page in the list now has its own icon.

Third sheet (`assets/settings-icons-3-source.png`, "Fantasy Duel Ban and Keybind Icons.png"): 1774 x 887, two icons side by
side, **no alpha channel** (an opaque background that is a checker of about 241 and 253). The tool removes it
(`remove_background`): the bright (darkest channel >= 236), border-connected part, plus enclosed bright gaps of 30 px or more (the key
bow's openings), then fragments of the texture under 400 px; edge pixels within 3 px are matted against white (colour
from the nearest artwork deeper in, coverage from how far the pixel is from white). The threshold sits above the palest
artwork (a blade's edge highlight, up to about 232), and the result is stable around it. Known limit: the blades'
pale bevels are close to the background in brightness, so their outer edge is slightly softer than the rest.

| # | Registry id | Picture | Used by |
|---|---|---|---|
| 17 | `declineDuels` | crossed swords behind a red prohibition seal | Quality of life: Decline duel requests card |
| 18 | `quickKeybind` | gold key on a dark keyboard key | Quality of life: Quick Keybind card |

All five Quality of life cards now have an icon.

Fourth sheet (`assets/settings-icons-4-source.png`, the user's `reminders.png`, byte-identical; sha256
`cac3ce12e68aa6060c531f9cc736bf4f0920296d8dc7ca17879ab4b3b0f7c3c1`): 1536 x 1024, 8-bit RGBA with real transparency,
3 columns x 2 rows in 512 px cells. Opened in an image viewer that ignores alpha it looks as though it sits on a brown
glow; composited on a flat colour every gutter and corner is alpha 0, so no background is removed. Processed the same way
as sheets 1 and 2. Its icons are balanced against the median of sheets 1 to 3 (`MEDIAN_SHEETS` in the tool), so adding it
changed no earlier icon (every existing file came out byte-identical).

| # | Registry id | Picture | Used by |
|---|---|---|---|
| 19 | `reminders` | rolled parchment scroll with a bronze ribbon (from `assets/settings-icons-6-source.png`, a single-icon sheet; replaced the bell) | `reminders`; a words-only reminder's thumbnail |
| 20 | `reminderShow` | parchment shield in a bronze frame | Reminders editor: Show; an icon a reminder can show |
| 21 | `reminderWhen` | three connected nodes | Reminders editor: When |
| 22 | `reminderPlacement` | a panel within four corner marks (five separate pieces) | Reminders editor: Placement |
| 23 | `reminderPreview` | an eye | Reminders editor: Preview |
| 24 | `reminderTest` | a checklist with a checkmark | Reminders editor: Test; an icon a reminder can show |

The mapping is exactly the expected one: the sheet holds the six pictures in the order described, nothing more.

Fifth sheet (`assets/settings-icons-5-source.png`, the image attached to the TwichUI Diagnostics request on 2026-10-26,
byte-identical; sha256 `e900befb29aff06791703a3281980e0e679017960e2fcddd97d54c53705fc512`): 1536 x 1024, 8-bit RGBA with
real transparency, 4 columns x 2 rows. Processed like sheet 4 and balanced against the same median, so no earlier icon
changed (the run added only the files below). The hourglass's two glass bulbs are clear in the source and stay clear.
Used by TwichUI Diagnostics' window (`TwichUI_Diagnostics/Window.lua`), beside each view's name.

| # | Registry id | Picture | Used by |
|---|---|---|---|
| 25 | `diagOverview` | a magnifying glass over parchment | Diagnostics: Overview |
| 26 | `diagTimeline` | an hourglass | Diagnostics: Timeline |
| 27 | `diagMemory` | a parchment with a trend line | Diagnostics: Memory |
| 28 | `diagOperations` | a bar chart | Diagnostics: Operations |
| 29 | `diagEvents` | connected nodes (close to `reminderWhen`; they are in different windows) | Diagnostics: Events and lifecycle |
| 30 | `diagCompare` | a box of filed cards | Diagnostics: Compare |
| 31 | `diagErrors` | a torn page under a magnifying glass | Diagnostics: Errors |
| 32 | `diagExport` | a scroll with an outward arrow | Diagnostics: Export |

**Fallback:** an unknown id, or a file the game refuses (`SetTexture` returns `success`, per Forever's
`SimpleTextureBaseAPIDocumentation.lua`), draws `media/icon` (the addon's emblem, shown by every TwichUI window's
header). A label is always drawn beside an icon, so a missing file never hides what a row is.

A card names an icon with `icon = "<id>"`; a card without one keeps its text in line with the others.

## Known limitations

- **Checked offline only.** The contact sheet (`docs/settings-icons-contact-sheet.png`: every icon at 64, 40, 32 and
  22 px on a warm charcoal and a light parchment surface) and 4x enlargements of the haziest icons (feather,
  journal, map, medallions, pennant, speech bubble) were inspected: no halo, no white rectangle, no clipped tips,
  no neighbouring artwork. That is not the game's own filtering at the player's UI scale: check in game.
- The 3 px edge kept beyond the solid artwork can hold a little of the original haze where it touched the edge; its
  colour is replaced by the edge's own, so it reads as antialiasing, not a red fringe.
- The map pin's see-through centre is kept as painted (alpha about 20): on a light surface it reads as a hole.
- At 20 px the fine detail (journal page lines, map paths, the chimney's smoke) is lost by design; the silhouettes
  stay readable on the contact sheet. The detailed 64 px files are used only where icons are drawn at 28 and above.
- The contact sheet is a development aid, regenerated by the command above. It is not loaded by the game and
  not packaged (`docs/` is ignored).

## Icons outside the sheets

`healerWatch` (the mana flask) and `healerWatchDrink` (the cup) are Healer Watch's own artwork, cut from
`assets/healer-watch-source.png` by `tools/make_healer_watch_art.py` into `!!!TwichUI/media/healerwatch/<name>.tga`
(64 px) and `<name>-small.tga` (32 px), with a 256 px `-large` file for the panel's Artwork layout. Their registry entries
say `source = "healerWatch"`. `docs/healer-watch.md` "Adding artwork" has how they are made.

`reminderDesigner` (a bronze ring with a check mark, joined by two rods to two smaller rings) is the Reminders condition
designer's emblem, cut from `assets/reminder-designer-source.png` by `tools/make_reminder_designer_art.py` into
`!!!TwichUI/media/reminders/designer.tga` (64 px) and `designer-small.tga` (32 px). It heads the When section of the
Reminders editor; where its files are missing the editor draws `reminderWhen` (three connected nodes) instead, so
nothing depends on it.
