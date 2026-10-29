# Bundled layout: imported from a package published in game

Written by `tools/import_published_layout.lua` (`tools/update_bundled_layout.sh --from-published`). Generated: do not edit by hand.
The procedure is in `docs/layouts/presets.md`.

## Source

| | |
|---|---|
| Package | `twichui-adventure`, revision 7 |
| Fingerprint | `#4265506251:429773` (the envelope's, derived again and checked) |
| What it resolves to | `#4121823111:15319` (`Pub.Contents`: layers, choices, screen rules, targets, requirements) |
| Published | 2026-10-29 in game, on a non-Forever client |
| Read from | the exported text in export.txt |
| Checked | `Pub.Check`, as a recipient's TwichUI checks it |

## What changed in the bundled package

Revision 6 to 7.

- choices: 1 difference

Files written: TwichUI_Layouts/ChoicesData.lua, TwichUI_Layouts/Classic.lua.

Copies of shared modules in a layout's own part (`LD.DropSharedCopies`): a module the shared base holds, written again in a layout, is left out
when the two differ only in how their numbers were written (two decimals, or 15 digits), so a later change to the base still reaches that layout.
A setting a wizard choice always writes (friendly plates' showFriendlyPlayers) is not compared, as the picked option replaces it. A module that differs in any other value stays in the layout.
- left out (the base's module applies): compact-adventure/EllesmereUIAuraBuffReminders, compact-adventure/EllesmereUIBags, compact-adventure/EllesmereUIChat, compact-adventure/EllesmereUIDataBars, compact-adventure/EllesmereUIMinimap, compact-adventure/EllesmereUIMythicTimer, compact-adventure/EllesmereUINameplates, compact-adventure/EllesmereUIQuestTracker

## The TwichUI presets it holds

Selector `helpers` ("TwichUI helpers"), editable presets (format 6), default `as-is`, no longer offered: new-preset:
- `as-is` "Leave them as they are": leave them as they are (names nothing)
- `on-screen` "On-screen helpers": 3 settings; on: Class resource bars, Food and drink, Marker bar; off: none; 0 other, 0 reset
- `finding-my-way` "Helpers and navigation": 4 settings; on: Class resource bars, Food and drink, Marker bar, Navigation; off: none; 0 other, 0 reset
- `curated` "Curated": 48 settings; on: Addon skins, Addon skins: Auctionator skin, Addon skins: Forever dungeon journal skin, Addon skins: Whats training skin, Auction House, Chat cleaning, Food and drink, Food and drink: Food drink drink, Food and drink: Food drink food, Gear comparison, Gear comparison: Gear bag icons, Gear comparison: Gear roll icons, General, General: Quiet login, Hazard alerts, Healer Watch, Journey Chronicle, Journey Chronicle: Chronicle bosses, Journey Chronicle: Chronicle deaths, Journey Chronicle: Chronicle gold, Journey Chronicle: Chronicle levels, Journey Chronicle: Chronicle professions, Journey Chronicle: Chronicle riding, Journey Chronicle: Chronicle sound, Journey Chronicle: Chronicle zones, Journey Chronicle: Welcome back, Mage, Mage: Mage conjure, Mage: Mage refreshments, Mage: Mage refreshments trade, Marker bar, Marker cycling, Marker cycling: Markers world, Navigation, Notifications, Notifications: Arrival dungeons, Notifications: Arrival subzones, Notifications: Friend login, Notifications: Friend login sound, Notifications: Training notice, Quality of life, SpeakStone speech frame, Target dragon artwork; off: Auction House: Mail gold summary, Class resource bars, Journey Chronicle: Chronicle chat, Notifications: Arrival reduced motion, World map; 0 other, 0 reset

## Left out (not part of what is bundled)

The package's own words and labels stay with the publication: its title (`TwichUI Adventure Compact`), made, source, release notes and the author's
label. The bundled package keeps the title and the developer flag Classic.lua gives it (`dev = true` until it is checked on WoW: Forever),
and declares the lowest package format its choices need. None of these changes what an install resolves to.

## Round trip

After writing, `tools/check_bundled_layout.lua --published` loads the bundled package from these files in a fresh process, unpacks the
published entry again (with the same copies left out) and requires `Pub.Compare` to find them the same, the choices to be identical byte for byte (labels and
descriptions included), and the revision to be the published one. A failure puts every file back.
