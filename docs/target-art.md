# Target dragon artwork

A dragon on EllesmereUI's target frame, chosen by the kind of enemy you target. Decoration only: it never changes
EllesmereUI's frame, settings or saved data, and takes no mouse. Off until turned on (Settings › Other addons ›
Target dragon artwork, `R:OpenSettings("targetArt")`).

Nothing here has been checked in the game yet; see "In-game checklist".

## Files

| File | Holds |
|---|---|
| `targetart/Config.lua` | `R.TargetArt`: the artwork metadata (`ART`), the kinds (`KINDS`), the settings (`Get`/`Set`/`ResetSettings`), `Pick` (which artwork) and `Placement` (where). No frames, no game calls |
| `targetart/Ellesmere.lua` | `R.TargetArtEllesmere`: finding EllesmereUI's target frame, and hiding EllesmereUI's own target dragon by alpha |
| `targetart/Display.lua` | `R.TargetArtDisplay`: events, the holder frame and texture, the preview |
| `TwichUI_Settings/pages/TargetArt.lua` | the page and its preview surface |
| `media/targetart/{rare,boss,elite,rare-wide,boss-wide,elite-wide}.tga` | the artwork, built by `tools/make_target_art.py` from `assets/target-art-*-source.png` |
| `tests/test_target_art.lua` | offline tests with stand-in frames |

## EllesmereUI

EllesmereUI has no public API or callback for its unit frames. What is relied on, read from EllesmereUIUnitFrames
9.3.5 (`reference_addons`) and 9.6.7 (installed):

- `EllesmereUIUnitFrames_Target`: the target frame, a secure unit button made once by `Engine.SpawnUnitFrame` in
  EllesmereUI's own `PLAYER_LOGIN` handler (`EUI_UnitFrames_Lifecycle.lua` `EnableBody` → `EUI_UnitFrames_Init.lua`
  `InitializeFrames`), only when its target frame source is EllesmereUI's. `RegisterUnitWatch` shows and hides it.
  It is accepted only when its `unit` attribute is `"target"`.
- `frame._eliteDragonHolder` (Elite/Rare Indicator, "Pixels Dragon" style) and
  `frame.Portrait.backdrop._winglessHolder` (Portrait Dragon / Elite Enemy Dragon, `ns.UF_PortraitDragon`):
  EllesmereUI's own target dragons. Plain frames EllesmereUI shows and hides but never changes the alpha of.

TwichUI loads before EllesmereUI, and its `PLAYER_LOGIN` may run before EllesmereUI's, so the frame is looked for at
login, on `PLAYER_ENTERING_WORLD` and on each target change (one global lookup each; no loop, no timer). Until it
exists the settings say why: not loaded, no EllesmereUI target frame (Blizzard's or none chosen there), or not
recognised. Nothing is ever drawn on another frame.

The holder is one frame (a child of the target button, `SetAllPoints` on it, mouse off) with one texture, made
once and only out of combat; a new target button by that name (EllesmereUI's frames made again) gets the same
holder, moved out of combat. It follows the frame's movement, scale and visibility because it is its child, and is
laid out again from its own `OnSizeChanged` when the frame's size changes. Nothing of EllesmereUI's frame is hooked,
moved, resized or re-layered, and its strata is inherited.

Layer: "In front" puts the holder 12 levels over the target button (over EllesmereUI's border, which uses +10, and
under its aura hosts, +18 and up); "Behind" one level under it (`max(0, level - 1)`, EllesmereUI's own rule for
a border drawn behind).

### EllesmereUI's own dragon

Off by default. When on, while TwichUI's artwork shows, each of the two holders above has its alpha set to 0, and the
alpha it had is put back as soon as TwichUI's artwork goes (another target, the option off, the feature off, a profile
with it off). Its show/hide, its settings and its saved data are never touched, so nothing fights its updates. Not
covered: the small Elite/Rare badge (an icon, left alone on purpose) and the dragon a stock frame style (Blizzard or
WoW Forever look) paints into the frame's own art.

## Kinds of enemy

From the game, read on `PLAYER_TARGET_CHANGED` and `UNIT_CLASSIFICATION_CHANGED` (target), each answer checked with
`issecretvalue` first:

1. `UnitIsBossMob("target")` true → the **Boss** row (the Forever target frame's own test for its winged boss dragon,
   `Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua` `GetBossPortraitFrameData`). Its row may say "Same as its
   classification", which goes on to step 2.
2. `UnitClassification("target")`: `worldboss`, `rareelite`, `elite`, `rare` → their rows.
3. Anything else (`normal`, `trivial`, `minus`, no target, a secret or missing answer) → nothing.

Defaults: Boss, World boss and Rare elite → Boss dragon; Elite → Elite dragon; Rare → Rare spawn. An elite is never
taken for a boss. Not every encounter boss is guaranteed to carry the boss flag, and many friendly guards are elite;
there is no friendly/hostile filter (EllesmereUI's own dragon has none either).

## Artwork and placement

| ID | Label | Used part of the 256 x 256 TGA | Crook (from top left) |
|---|---|---|---|
| `rare` | Rare spawn | 182 x 256 | 0.752, 0.404 |
| `boss` | Boss dragon | 183 x 256 | 0.700, 0.310 |
| `elite` | Elite dragon | 198 x 256 | 0.624, 0.280 |
| `rareWide` | Rare spawn (wide) | 256 x 187 | 0.674, 0.423 |
| `bossWide` | Boss dragon (wide) | 256 x 187 | 0.665, 0.411 |
| `eliteWide` | Elite dragon (wide) | 256 x 207 | 0.656, 0.388 |

The wide set (711 x 454, 745 x 450 and 732 x 481 sources) are the same dragons with a longer spear arm and wings,
wider than tall, so the tool fits their width instead of their height. They rest in 0.04/0.05: the spear lies along the
frame's top edge and the neck sits on the corner, clear of the health text. The rare wide painting's content reaches
the bottom row of its source image (the elite's to 1 px of it), so their tail tips may already be cut in the source.

Sources: 1254 x 1254, 1254 x 1254 and 1230 x 1278 RGBA PNGs with real transparency (no background), each a dragon
curled round a top-right corner. The tool crops each to its visible content, scales it to 254 px tall keeping its
aspect ratio, and leaves a 1 px clear margin; texcoords draw only the used part. The crook is the top-right corner of
the largest empty rectangle at the painting's bottom left, the space a frame fits into without touching the art.

Resting in: the crook alone keeps every pixel off the frame. Each artwork also has `restX`/`restY` in `ART`, how far
it rests into the frame from its crook as fractions of its own size (rare 0.08/0.06, boss 0.07/0.05, elite
0.05/0.03): the jaw rests on the frame's top edge and the neck over its right edge, clear of the health text. Chosen
by eye on rendered samples at EllesmereUI's default frame; they apply only with the crook as the anchor.

Each artwork's own adjustment (`rareX`/`rareY`/`rareScale`, and the same for `boss` and `elite`; 0, 0, 100%) adds to
the shared offsets and scale. The page's "Fine-tune each artwork" rows adjust the artwork chosen in the preview.

Size: at 100% each dragon's height is `frameHeight / (1 - crookY)`, so with its crook on the frame's top-right corner
its tail reaches the frame's bottom edge (frame height 52 when it can't be read). The default (frame point Top right,
artwork point The dragon's crook, offsets 0) wraps each dragon round that corner outside the frame, so nothing on it is
covered. Offsets are in the frame's own units. Mirroring swaps the texcoords and the crook with them.

## Preview

The page has a sample frame (the real frame's size when attached, else EllesmereUI's default 181 x 52), labelled as a
sample, drawn with the current settings and one of the three artworks chosen beside it (not saved). **Show on my
target frame** puts that artwork on the real target frame whatever the target is; the frame itself only shows with a
target. It ends when the page or the window closes, in combat, or when the feature is turned off, and never changes
the target or a saved mapping.

## Saved data

`modules.targetArt` (false) and `ui.targetArt` (profile): `mapBoss`, `mapWorldboss`, `mapRareelite`, `mapElite`,
`mapRare`, `opacity` (5–100), `scale` (25–300), `framePoint`, `artPoint`, `x`, `y` (−200–200), `mirror`, `layer`,
`hideEllesmere`, and `<id>X`, `<id>Y` (−100–100) and `<id>Scale` (50–200) for each artwork. Missing or invalid values read as their defaults and are left alone. Shared with configuration
sharing.

## In-game checklist

- EllesmereUI's target frame on: turn the feature on; the status says Attached. Target a rare, an elite, a rare
  elite, a world boss and a dungeon boss: the expected artwork each time; an ordinary enemy or a player: none.
- Rapid target changes and clearing the target: never the last target's art.
- `/reload` in and out of combat with a target: the art appears (after combat if reloaded in combat).
- EllesmereUI not loaded, and EllesmereUI set to Blizzard's target frame: the status says so, nothing drawn, no errors.
- Move, resize and rescale the target frame in EllesmereUI's options and Unlock Mode; change UI scale: the art follows.
- Each setting: opacity, scale, both anchors, offsets, mirror, layer (in front over the bars, behind under the
  frame's background). Clicks, right-click menu, tooltip and pings on the target frame behave as without it.
- EllesmereUI's Elite Enemy Dragon on, with and without "Hide EllesmereUI's own target dragon": hidden only while
  TwichUI's shows, back afterwards and after turning the feature off. Its options page still works.
- Preview: the sample, switching art, Show on my target frame with and without a target, closing the settings.
- On and off repeatedly, a profile change, a reload: settings kept, no duplicate art, no errors.
- `UnitIsBossMob` and `UnitClassification` answers on Forever bosses (not verified offline).
