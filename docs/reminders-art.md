# Reminders artwork library

The pictures a reminder can show come from one catalog. This file explains where they came from, how they are built, what each one is called, how
the picker finds them, and how to add more. The picker itself is described in [reminders.md](reminders.md) (Appearance and the image picker).

## Sources

Two painted sheets, kept whole and never changed, in `docs/reminders-revision/`:

| Sheet | File | Size | Layout |
|---|---|---|---|
| 1 | `icon-grid-1.png` | 1536 × 1024, RGBA | Dense, six bands of 8 / 10 / 9 / 8 / 8 / 8 pictures, not on a uniform grid |
| 2 | `icon-grid-2.png` | 1024 × 1536, RGBA | Regular: 4 columns × 6 rows of 256 px cells |

Both have real transparency (about half of each sheet is fully clear, with a faint haze around some pictures). The approved mock-up the picker follows is
`docs/reminders-revision/artwork-selector-mockup.png`.

## How a picture is found and built (`tools/make_reminder_gallery.py`)

Standard library only, like the other `make_*.py` tools. It reuses the repository's PNG reader, solid-part finder, shape-based haze cleaning, premultiplied-alpha
resampling, colour bleed and TGA writer. Nothing is keyed out by colour.

1. **Find.** The solid artwork (alpha ≥ 128) is split into 8-connected parts. On sheet 1 every picture is one part (a few fragments of a glow are separate and are
   attached to the picture whose bounds they touch); the parts are sorted into the six bands by their centre's height and into reading order by their centre's x.
   On sheet 2 a part belongs to the 256 px cell that holds its centre, so a picture of several pieces (the fishing rod, the arcane focus, the crumbling hourglass)
   stays whole. The crop is the union of the picture's parts, so nothing is cut and no neighbour leaks in; no nominal grid line is used as a crop edge. The tool
   stops if what it finds is not exactly what the list below accounts for.
2. **Clean.** A pixel is kept if it is solid or within 3 px of solid (its antialiased edge) with the colour of the nearest solid pixel, so no haze or matte survives.
3. **Normalize.** The picture is scaled with its aspect ratio kept so its longer side is 86 % of a square canvas (a 7 % clear margin each side). A picture that is heavy and
   compact for its size is shrunk a little (never below 88 %, so the margin stays under about 13 %), by the optical balance `make_npc_art.py` uses, so a dense medallion does
   not look bigger than a thin rod. It is then centred.
4. **Write.** Three files per picture (below), `assets/reminder-gallery/manifest.json` and the generated `!!!TwichUI/reminders/ArtData.lua`.

`python3 tools/make_reminder_gallery.py --contact-sheet docs/reminders-art/contact-sheet.png --qa-sheet docs/reminders-art/qa-sheet.png` rebuilds everything (about 25 s). `--check` builds nothing and reports.
`--only ID...` draws only those pictures (for a quick check). `tests/test_reminder_gallery.py` checks the shipped files against a fresh build.

| Output | Where | Size |
|---|---|---|
| Individual source | `assets/reminder-gallery/<id>.png` | 192 × 192, RGBA (the source of the runtime files) |
| Runtime, large | `!!!TwichUI/media/reminders/gallery/<id>.tga` | 128 × 128, uncompressed 32-bit, 8 alpha bits, for a reminder drawn above 64 units |
| Runtime, small | `!!!TwichUI/media/reminders/gallery/<id>-small.tga` | 64 × 64, for 64 units and under, and for the picker's thumbnails |
| Manifest | `assets/reminder-gallery/manifest.json` | every field below |
| Game data | `!!!TwichUI/reminders/ArtData.lua` | generated: id, name, category, description, keywords, related |
| Contact sheet | `docs/reminders-art/contact-sheet.png` | every picture at 64, 48, 32 and 24 px on dark and light surfaces |
| QA sheet | `docs/reminders-art/qa-sheet.png` | every picture at 96 px with its stable id and display name (`--qa-sheet`); a QA artifact, not runtime art and not packaged (`docs/` is ignored by `.pkgmeta`) |

The whole canvas is the picture's used area (the metadata `width = height = size`), so the clear margin is part of what is drawn and every picture has the same
apparent size at the same Size setting. The existing artwork (`shield`, `ammo`, `wellfed`, `enchant`) keeps its tight crop and its own files.

## The manifest

`assets/reminder-gallery/manifest.json` holds, for each picture: `id`, `name`, `category`, `description`, `keywords`, `sheet`, `position` (row, column), `crop`
(x, y, width, height in the sheet, the union of its parts), `parts`, `source`, `texture` (path without extension; `-small` is the small file), `textureSizes`,
`related` (ids of meaningful alternatives), and `balance`. It also lists the categories, the pictures that were already in Reminders (`legacy`) and the `rejected` ones.

**Ids** are `reminder-<what it is>` (lower case, digits, hyphens, at most 40 characters: `display.art` must fit). They never contain a row or column and are never
renamed or reused: a reminder keeps its id in saved data. Row and column are source metadata only.

## Categories

Equipment, Buffs & Effects, Supplies, Character, Adventure, General (and All in the picker). A picture is filed where a player would look for it; none is listed
under a category only to populate it.

## Search

Every word typed must appear in the picture's name, its category or its keywords (case ignored, plain text, at most eight words). Matches whose name holds every
word come first, then the rest, each in catalog order. A category narrows search. Keywords are lower-case words a player might use ("health", "heart", "low").

## Compatibility with saved reminders

Nothing stored changed. A reminder's `display` still has `mode` (`artworkText`, `artwork`, `iconText`, `icon`, `text`), `art`, `iconSource`, `icon` and `item`.
`reminders/Gallery.lua` presents three modes (Image + text, Image only, Text only) as a view of those five, and reads and writes only through `RM.SetDisplay` /
`RM.SetDisplayMany`. The four pictures that were here first keep their ids (`shield`, `ammo`, `wellfed`, `enchant`); the eight TwichUI icons a reminder could show
(`R.Icons` ids `reminderShow`, `reminders`, `reminderTest`, `hazardAlerts`, `ammunition`, `foodAndDrink`, `gearComparison`, `mage`) are listed in the same catalog
under their own names and are stored exactly as before (`iconSource = "bundled"`, `icon = <id>`). Artwork this version does not have is kept by id and reported
("Artwork unavailable"), never changed.

## Adding a picture

1. Put the new painted sheet in `docs/reminders-revision/` (or add the picture to a sheet there) and add the sheet to `SHEETS` if it is new.
2. Add a line to `E` in `tools/make_reminder_gallery.py`: a new stable `reminder-...` id, the sheet and position, a name, a category, a description, keywords and any
   related ids. If a picture on the sheet should not be catalogued, add it to `REJECTED` with the reason (the tool refuses a sheet with a picture it can't account for).
3. Run `python3 tools/make_reminder_gallery.py --contact-sheet docs/reminders-art/contact-sheet.png` and look at the contact sheet (edges on the light surface, 24 px).
4. Run `./tests/run.sh`. Commit the sheet, the tool, `assets/reminder-gallery/`, `media/reminders/gallery/`, `ArtData.lua` and the contact sheet.

Nothing else needs to know: the catalog, the picker, search and the renderer read `ArtData.lua`.

## Quality notes

**Catalog count:** 79 entries: 67 library pictures, the 4 earlier artworks and the 8 TwichUI icons. The final audit (every picture on `qa-sheet.png`) found no crop, alpha, halo, mapping or duplicate defect; the margin was reduced from 12 % to 7 % (the picture fills 86 % of its canvas) after the first picker looked sparse.

* Both sheets were inspected at full size and every crop was checked on a dark and a light surface; no halo, brown remnant, partial neighbour or hard cutout was found.
* Pictures with soft, see-through effects (the fading sigil of *Missing buff*, the arcane glows) keep their effect only within a few pixels of solid paint, so their
  edge is slightly harder than the painting's. That is the cost of removing the haze by shape rather than colour.
* At 24 px the thin or dark pictures (*Fishing rod*, *Missing buff*, the two *Talent* tablets) are the least recognizable; at 32 px and above every picture reads.
  The picker's thumbnails are drawn at 64 units (the small texture, 1:1); reminders default to 64.

## Source-position map

### Sheet 1 (icon-grid-1.png, 1536 × 1024)

| Id | Sheet | Position | Crop (x,y w×h) | Name | Category | Related |
|---|---|---|---|---|---|---|
| reminder-lion-shield | 1 | R1C1 | 24,13 151×174 | Lion shield | Equipment | reminder-broken-shield, reminder-tank-preparation |
| reminder-enchanted-sword | 1 | R1C2 | 202,19 167×163 | Enchanted sword | Equipment | reminder-sharpening-stone |
| reminder-sharpening-stone | 1 | R1C3 | 384,35 181×151 | Sharpening stone | Equipment | — |
| reminder-poisoned-dagger | 1 | R1C4 | 584,13 147×177 | Poisoned dagger | Equipment | reminder-rogue-preparation |
| reminder-helmet | 1 | R1C5 | 760,12 163×175 | Helmet | Equipment | — |
| reminder-breastplate | 1 | R1C6 | 935,18 189×162 | Plate armor | Equipment | — |
| reminder-broken-shield | 1 | R1C7 | 1136,12 156×175 | Broken shield | Equipment | reminder-lion-shield |
| reminder-combat-loadout | 1 | R1C8 | 1311,15 210×171 | Combat loadout | Equipment | — |
| reminder-arcane-sigil | 1 | R2C1 | 16,199 167×145 | Arcane sigil | Buffs & Effects | — |
| reminder-hourglass | 1 | R2C2 | 200,198 145×153 | Golden hourglass | Buffs & Effects | reminder-expiring-buff |
| reminder-curse-skull | 1 | R2C3 | 362,206 129×134 | Cursed skull | Buffs & Effects | reminder-harmful-debuff |
| reminder-arcane-ward | 1 | R2C5 | 689,202 119×141 | Arcane ward | Buffs & Effects | reminder-missing-buff |
| reminder-blessing-hand | 1 | R2C6 | 833,201 112×144 | Blessing | Buffs & Effects | — |
| reminder-war-horn | 1 | R2C7 | 959,198 170×166 | War horn | Buffs & Effects | — |
| reminder-open-spellbook | 1 | R2C8 | 1113,203 178×136 | Open spellbook | Buffs & Effects | — |
| reminder-golden-rings | 1 | R2C9 | 1296,202 103×135 | Golden rings | Buffs & Effects | reminder-aura-stacks |
| reminder-stained-cloth | 1 | R2C10 | 1412,206 116×134 | Stained cloth | Buffs & Effects | — |
| reminder-arrow-quiver | 1 | R3C1 | 16,358 148×157 | Arrow quiver | Supplies | ammo |
| reminder-crystal-pouch | 1 | R3C2 | 175,368 169×147 | Crystal pouch | Supplies | reminder-low-reagents |
| reminder-supply-pack | 1 | R3C3 | 353,361 185×155 | Supply pack | Supplies | reminder-full-inventory |
| reminder-health-potion | 1 | R3C4 | 561,362 128×151 | Health potion | Supplies | — |
| reminder-mana-potion | 1 | R3C5 | 725,360 130×151 | Mana potion | Supplies | reminder-low-mana |
| reminder-bread-and-cheese | 1 | R3C6 | 860,379 179×134 | Bread and cheese | Supplies | reminder-low-food, wellfed |
| reminder-waterskin | 1 | R3C7 | 1049,362 138×152 | Waterskin | Supplies | reminder-low-drink |
| reminder-purple-elixir | 1 | R3C8 | 1211,360 116×155 | Purple elixir | Supplies | — |
| reminder-hammer-and-anvil | 1 | R3C9 | 1345,363 175×151 | Hammer and anvil | Equipment | — |
| reminder-red-crystal | 1 | R4C1 | 24,517 135×157 | Red crystal | Character | reminder-low-health |
| reminder-blue-crystal | 1 | R4C2 | 198,516 152×158 | Blue crystal | Character | reminder-low-mana |
| reminder-lightning-rune | 1 | R4C3 | 386,520 156×149 | Lightning rune | Character | reminder-low-energy |
| reminder-battle-emblem | 1 | R4C4 | 575,526 173×140 | Battle emblem | Character | reminder-low-rage |
| reminder-arcane-spellbook | 1 | R4C5 | 763,524 183×143 | Arcane spellbook | Character | — |
| reminder-bandages | 1 | R4C8 | 1330,532 180×129 | Bandages | Supplies | — |
| reminder-warrior-banner | 1 | R5C4 | 542,672 168×157 | Crossed swords banner | Character | — |
| reminder-healing-light | 1 | R5C5 | 738,678 171×150 | Healing light | Character | — |
| reminder-dungeon-entrance | 1 | R5C7 | 1098,674 201×147 | Dungeon entrance | Adventure | — |
| reminder-raid-gate | 1 | R5C8 | 1313,679 204×139 | Raid gate | Adventure | — |
| reminder-marked-map | 1 | R6C1 | 10,840 184×159 | Marked map | Adventure | — |
| reminder-horse | 1 | R6C2 | 204,841 168×157 | Horse | Adventure | — |
| reminder-bedroll | 1 | R6C3 | 386,846 191×152 | Bedroll | Adventure | reminder-camp-tent |
| reminder-companion-crests | 1 | R6C5 | 769,832 175×167 | Companion crests | Adventure | reminder-group-preparation |
| reminder-leather-backpack | 1 | R6C6 | 964,839 169×162 | Leather backpack | Supplies | reminder-full-inventory |
| reminder-bronze-bell | 1 | R6C7 | 1151,832 163×169 | Bronze bell | General | — |
| reminder-camp-tent | 1 | R6C8 | 1319,827 208×168 | Camp tent | Adventure | reminder-bedroll |

Rejected from this sheet:

| Position | Picture | Reason | Duplicate of |
|---|---|---|---|
| R2C4 | Empty plate | Same subject as the existing Plate and cutlery (wellfed), which saved reminders already use. | wellfed |
| R4C6 | Hourglass medallion | Near-identical to Expiring buff (sheet 2) and to Golden hourglass. | reminder-expiring-buff |
| R4C7 | Crossed-out spellbook | Same idea as Spell not learned (sheet 2), which is the stronger version. | reminder-spell-not-learned |
| R5C1 | Talent tree parchment | Same subject as Talent specialization (sheet 2), which is more detailed. | reminder-talent-specialization |
| R5C2 | Lit rune stone | Same subject as Talent learned (sheet 2). | reminder-talent-learned |
| R5C3 | Unlit rune stone | Same subject as Talent missing (sheet 2). | reminder-talent-missing |
| R5C6 | Plain steel shield | Same subject as the existing Shield (shield), which saved reminders already use. | shield |
| R6C4 | Crossed weapons banner | Near-identical to Crossed swords banner, one row above. | reminder-warrior-banner |

### Sheet 2 (icon-grid-2.png, 1024 × 1536)

| Id | Sheet | Position | Crop (x,y w×h) | Name | Category | Related |
|---|---|---|---|---|---|---|
| reminder-missing-buff | 2 | R1C1 | 38,41 186×186 | Missing buff | Buffs & Effects | reminder-expiring-buff, reminder-arcane-ward |
| reminder-expiring-buff | 2 | R1C2 | 287,41 195×191 | Expiring buff | Buffs & Effects | reminder-hourglass, reminder-missing-buff |
| reminder-harmful-debuff | 2 | R1C3 | 539,42 200×196 | Harmful debuff | Buffs & Effects | reminder-curse-skull |
| reminder-aura-stacks | 2 | R1C4 | 777,41 216×191 | Aura stacks | Buffs & Effects | reminder-golden-rings |
| reminder-low-health | 2 | R2C1 | 38,287 193×189 | Low health | Character | reminder-red-crystal |
| reminder-low-mana | 2 | R2C2 | 301,279 163×198 | Low mana | Character | reminder-mana-potion, reminder-blue-crystal |
| reminder-low-energy | 2 | R2C3 | 533,274 206×203 | Low energy | Character | reminder-lightning-rune |
| reminder-low-rage | 2 | R2C4 | 794,270 189×214 | Low rage | Character | reminder-battle-emblem |
| reminder-talent-specialization | 2 | R3C1 | 25,522 221×210 | Talent specialization | Character | — |
| reminder-talent-learned | 2 | R3C2 | 296,521 175×209 | Talent learned | Character | reminder-talent-missing |
| reminder-talent-missing | 2 | R3C3 | 545,521 174×209 | Talent missing | Character | reminder-talent-learned |
| reminder-cooldown-ready | 2 | R3C4 | 774,512 230×224 | Cooldown ready | Character | — |
| reminder-low-reagents | 2 | R4C1 | 31,777 192×190 | Low reagents | Supplies | reminder-crystal-pouch, reminder-missing-class-reagents |
| reminder-low-food | 2 | R4C2 | 274,782 214×182 | Low food | Supplies | reminder-bread-and-cheese, wellfed |
| reminder-low-drink | 2 | R4C3 | 522,771 185×201 | Low drink | Supplies | reminder-waterskin |
| reminder-missing-class-reagents | 2 | R4C4 | 781,777 215×189 | Class reagents | Supplies | reminder-low-reagents |
| reminder-full-inventory | 2 | R5C1 | 21,1001 224×220 | Full inventory | Supplies | reminder-leather-backpack, reminder-supply-pack |
| reminder-fishing-rod | 2 | R5C2 | 261,1023 233×193 | Fishing rod | Equipment | — |
| reminder-group-preparation | 2 | R5C3 | 516,1007 233×210 | Group preparation | Adventure | reminder-companion-crests |
| reminder-spell-not-learned | 2 | R5C4 | 780,1016 215×210 | Spell not learned | Character | — |
| reminder-healer-preparation | 2 | R6C1 | 19,1255 222×221 | Healer preparation | Character | reminder-healing-light |
| reminder-tank-preparation | 2 | R6C2 | 269,1253 223×224 | Tank preparation | Character | reminder-lion-shield |
| reminder-caster-preparation | 2 | R6C3 | 528,1250 194×230 | Caster preparation | Character | — |
| reminder-rogue-preparation | 2 | R6C4 | 764,1256 227×223 | Rogue preparation | Character | reminder-poisoned-dagger |

Rejected from this sheet:

| Position | Picture | Reason | Duplicate of |
|---|---|---|---|
| — | none | | |
### Kept from before

| Catalog id | Kind | Name | Category |
|---|---|---|---|
| shield | artwork | Steel shield | Equipment |
| ammo | artwork | Arrows | Supplies |
| wellfed | artwork | Plate and cutlery | Supplies |
| enchant | artwork | Weapon oil | Equipment |
| icon-reminderShow | TwichUI icon | Framed shield | General |
| icon-reminders | TwichUI icon | Bell | General |
| icon-reminderTest | TwichUI icon | Checklist | General |
| icon-hazardAlerts | TwichUI icon | Warning shield | General |
| icon-ammunition | TwichUI icon | Quiver | Supplies |
| icon-foodAndDrink | TwichUI icon | Bread and cup | Supplies |
| icon-gearComparison | TwichUI icon | Breastplate | Equipment |
| icon-mage | TwichUI icon | Arcane staff | Character |
