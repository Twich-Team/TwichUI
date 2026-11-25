# Group Finder dungeon icons

`groupfinder-dungeons-source.png` is original image-generated artwork created for the Group Finder implementation. The left square depicts a volcanic fortress entrance for Blackrock Depths; the right square depicts a purple gothic academy entrance for Scholomance. Neither illustration copies game assets or third-party artwork. The requested composition was two equally sized square illustrations in one transparent sheet, with aged bronze octagonal rims and no text.

The generator returned a 1774 × 887 RGBA PNG. Packaging crops the left and right 887 × 887 cells, then resizes each using Pillow's Lanczos filter to uncompressed 32-bit RGBA TGA files at 128 × 128 and 64 × 64 in `!!!TwichUI/media/groupfinder/`. The originals remain unchanged. Transparent corner pixels and visible doorways were checked in both packaged sizes against an espresso background.

The shared `groupfinder/Art.lua` lookup maps public map IDs verified in `!!!TwichUI/map/Data.lua` for Forever 1.60.1.70450 and public English full/short activity names. No activity IDs are hardcoded. Blackrock Depths and Zul'Farrak are absent from the verified local map inventory, so their map IDs are intentionally not inferred. Unmatched or localized activity names without a verified map match use a neutral painted entrance.

## Expanded dungeon set

`groupfinder-classic-dungeons-source.png` is a second original generated atlas, requested as four columns by five rows of square octagonal icons with no text. The returned sheet is 1122 × 1402 RGBA. Cell boundaries use rounded proportional quarters/fifths, then each cell is resized with Lanczos to 128, 64 and 32 pixels and saved as uncompressed RGBA TGAs. The existing BRD/Scholomance source also supplies their new 32-pixel variants. At 32 pixels, doors and silhouettes remain distinct; transparent corner edges were checked against the browser's espresso background.

Reading left to right, top to bottom:

| Row | First | Second | Third | Fourth |
| --- | --- | --- | --- | --- |
| 1 | Maraudon | Zul'Farrak | Uldaman | Deadmines |
| 2 | Wailing Caverns | Ragefire Chasm | Shadowfang Keep | Blackfathom Deeps |
| 3 | Stockade | Gnomeregan | Razorfen Kraul | Razorfen Downs |
| 4 | Scarlet Monastery | Sunken Temple | Dire Maul | Stratholme |
| 5 | Lower Blackrock Spire | Upper Blackrock Spire | Ancient Zul'Gurub | Neutral entrance |

Scarlet Monastery subareas, Dire Maul wings and Stratholme routes share their parent dungeon's art. Ancient Zul'Gurub is the Forever addition verified in the local map inventory; other additions continue to populate from live activity data and receive the neutral entrance until an identity can be verified.

The native Encounter Journal was audited: its implementation obtains `buttonImage` through `EJ_GetInstanceByIndex`/`EJ_GetInstanceInfo` (`Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua`). The local simulator does not provide those licensed image assets. Packaged original art therefore supplies consistent appearance without inventing native texture paths or copying game artwork. Existing map assets contain map tiles and a small generic entrance marker, not a complete set of distinct icon illustrations.

## Confirmed Forever picker additions

The owner's in-game dungeon-picker screenshot confirms the exact labels `Alcaz Prison`, `Blackmaw Hold`, `City of Dalaran`, and `Excavation Site: Wetlands`. `groupfinder-forever-dungeons-source.png` is original generated artwork for those four activities in a two-column/two-row sheet: island prison, black mountain hold, violet arcane ruined city, and marsh archaeological dig respectively. The generator returned a 1254 × 1254 RGBA image; packaging crops its four equal cells and saves each at 128/64/32 pixels using the same Lanczos/uncompressed-RGBA process. Public English names select these icons; no unverified map or activity IDs are introduced. Unmatched names retain the neutral entrance. The screenshot also verifies parenthesized `Dire Maul (East)`, `(North)`, and `(West)` labels, which share the existing Dire Maul painting.
