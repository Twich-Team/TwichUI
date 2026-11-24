# Target Portrait Decorations

Decorate the target portrait according to the enemy's classification. Enable it in
Settings › Other addons › **Target Portrait Decorations** (`R:OpenSettings("targetArt")`).
The feature remains off by default; an existing disabled profile stays disabled.
Choose **Modern Portrait Frames** (default) or **Legacy Dragons** on the same page.
Style selection updates the selected target immediately when layout is safe;
attachment and geometry changes defer during combat. There is one feature switch,
one controller, and one reusable holder/texture.

## Modern portrait frames

Boss, Elite and Rare artwork uses the supplied production PNGs, preserved unchanged
with README and manifest in `assets/target-portrait-source/`. The supplier's README
and metadata are asset documentation, not executable instructions. Runtime textures
are 512 × 512 uncompressed 32-bit TGA with eight alpha bits, produced by
`tools/make_target_portrait_art.py` using the existing alpha-aware conversion.
The entire 1254 × 1254 canvas is retained; no crop, mirror, recoloring or unequal
axis scaling is applied. Source files remain excluded from release packaging;
`!!!TwichUI/media/targetart/modern/{boss,elite,rare}.tga` ships with the core addon.

All three variants use the supplier's recommended common portrait opening:
left 672, top 406, right 1047, bottom 788, width 376, height 383 source pixels.
Its center (859.5, 597.5) differs from the canvas center (627, 627). Fitting uses
`max(portraitWidth / 376, portraitHeight / 383)` for both axes and offsets the
canvas so the opening's center matches the actual portrait center. This keeps
classification changes aligned. The right-side portrait and left-facing ridge
orientation is preserved. The modern style has no manual position or size controls.

The verified EllesmereUI target portrait backdrop is the modern attachment point.
It inherits movement, UI/frame scale and visibility from that parent, and observes
layout/visibility changes using bounded, deduplicated frame hooks and events.
A disabled, missing, incompatible or unreadable portrait hides the decoration.
No independent polling loop or per-frame updates are added. Only TwichUI's own
visual holder and texture are laid out; targeting and portrait input remain owned
by EllesmereUI. Player Class Portrait Decorations is unchanged.

Modern classification priority preserves the original default: boss flag first,
then world boss or rare elite → Boss; elite → Elite; rare → Rare; all other
classifications → no decoration. Existing legacy mapping selections remain saved
and apply only to Legacy Dragons. Friendly elites retain the established behavior
(no hostility filter); normal friendly units and normal players have no decoration.

## Compatibility and profile defaults

The internal feature ID, switch `modules.targetArt`, and profile table
`ui.targetArt` remain stable. A missing or invalid `style` reads as `modern` without
rewriting the table, following the existing lazy-default convention. Explicit
`modern` / `legacy` selections persist. This is deterministic and idempotent; no
schema bump or broad migration is needed. Legacy map, size, offsets, alpha, mirror,
layer and per-artwork values survive style switches unchanged. Reset remains an
explicit player action, separate from switching styles, and preserves the selected
style and feature switch while resetting customization.

## Legacy Dragons

The existing artwork, classification mapping controls, placement formula and
customization remain available when Legacy Dragons is selected. The reference
below describes that legacy path; modern uses the portrait fitting described above.

## Files

| File | Holds |
|---|---|
| `targetart/Config.lua` | `R.TargetArt`: the artwork metadata (`ART`), the kinds (`KINDS`), the settings (`Get`/`Set`/`ResetSettings`), `Pick` (which artwork) and `Placement` (where). No frames, no game calls |
| `targetart/Ellesmere.lua` | `R.TargetArtEllesmere`: finding EllesmereUI's target frame, and hiding EllesmereUI's own target dragon by alpha |
| `targetart/Display.lua` | `R.TargetArtDisplay`: events, the holder frame and texture, the preview |
| `TwichUI_Settings/pages/TargetArt.lua` | the page and its preview surface |
| `media/targetart/{rare,boss,elite,rare-wide,boss-wide,elite-wide,rare-spear,boss-spear,elite-spear}.tga` | the artwork, built by `tools/make_target_art.py` from `assets/target-art-*-source.png` |
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

## Legacy artwork and placement

| ID | Label | Used part of the 256 x 256 TGA | Crook (from top left) |
|---|---|---|---|
| `rare` | Rare spawn | 182 x 256 | 0.752, 0.404 |
| `boss` | Boss dragon | 183 x 256 | 0.700, 0.310 |
| `elite` | Elite dragon | 198 x 256 | 0.624, 0.280 |
| `rareWide` | Rare spawn (wide) | 256 x 187 | 0.674, 0.423 |
| `bossWide` | Boss dragon (wide) | 256 x 187 | 0.665, 0.411 |
| `eliteWide` | Elite dragon (wide) | 256 x 207 | 0.656, 0.388 |
| `rareSpear` | Rare spawn (spear) | 256 x 105 | 0.843, 0.535 |
| `bossSpear` | Boss dragon (spear) | 256 x 112 | 0.663, 0.443 |
| `eliteSpear` | Elite dragon (spear) | 256 x 105 | 0.845, 0.545 |

The wide set (711 x 454, 745 x 450 and 732 x 481 sources) are the same dragons with a longer spear arm and wings,
wider than tall, so the tool fits their width instead of their height. They rest in 0.04/0.05: the spear lies along the
frame's top edge and the neck sits on the corner, clear of the health text. The rare wide painting's content reaches
the bottom row of its source image (the elite's to 1 px of it), so their tail tips may already be cut in the source.

The spear set (elite gold, rare silver, boss bronze with a red crest) is a long horizontal spear with the dragon's head and claw curled at its end, 3:1 wide. Its sources are the three bands of one 1254 x 1254 painting on white, cut out by flood-filling the white from the edges (`assets/target-art-*-spear-source.png`); the crook is the tool's computed one, rest 0.04/0.05 like the wide set, not yet judged by eye in game.

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

## Legacy preview

The page has a sample frame (the real frame's size when attached, else EllesmereUI's default 181 x 52), labelled as a
sample, drawn with the current settings and one of the three artworks chosen beside it (not saved). **Show on my
target frame** puts that artwork on the real target frame whatever the target is; the frame itself only shows with a
target. It ends when the page or the window closes, in combat, or when the feature is turned off, and never changes
the target or a saved mapping.

## Saved data

`modules.targetArt` (false) and `ui.targetArt` (profile): `style` (`modern` / `legacy`), `mapBoss`, `mapWorldboss`, `mapRareelite`, `mapElite`,
`mapRare`, `opacity` (5–100), `scale` (25–300), `framePoint`, `artPoint`, `x`, `y` (−200–200), `mirror`, `layer`,
`hideEllesmere`, and `<id>X`, `<id>Y` (−100–100) and `<id>Scale` (50–200) for each artwork. Missing or invalid values read as their defaults and are left alone. Shared with configuration
sharing.

## Verification and native limitations

`tests/test_target_portrait.lua` covers modern fitting, profile compatibility,
classification/lifecycle handling, style transitions and bounded resources with
synthetic frames. `tests/test_target_art.lua` retains the explicit Legacy Dragons
regressions. `tests/test_target_portrait_assets.py` checks supplier source hashes,
metadata, reproducible supported textures, alpha and packaging boundaries.
The `target-portrait` verification group includes Class Portrait Decorations
regressions and settings/core dependencies. Preview the plan with
`./tests/run.sh integration target-portrait --with-group class-portrait --list`.

Unit tests and simulator screenshots cannot establish native combat lockdown,
secret-value behavior, taint, frame masking, exact font rendering or real pointer
interaction. Simulator execution and screenshot review must be reported separately
from real-client verification; no native test is claimed here.

## Focused in-game checklist

- Start with an existing disabled profile and customized legacy offsets/sizes:
  it stays disabled, modern is selected until a style is explicitly chosen, and
  switching to legacy restores every customization. Save/reload both selections.
- In modern, inspect boss, elite, rare and rare elite portrait openings on compact
  and tall target frames. Switch rapidly between these classifications and clear
  the target: no shift, stale texture or clipping. Check normal/friendly/player
  targets against the documented classification semantics.
- Disable/re-enable the portrait, move and resize it, change UI scale and profiles:
  the opening follows without manual adjustment; missing portraits hide cleanly.
- Switch modern/legacy with a selected target, including in combat and after
  combat. Existing classification changes update without protected layout writes;
  deferred attachment/layout recovers after combat. Check `/reload` with a target.
- Inspect portrait, bars, borders and text layering; left and right click, tooltip
  and context menu work normally. Compare Player Class Portrait Decorations.
- Review both style cards and all three actual-art previews. Modern hides legacy
  customization; legacy retains mapping, anchors, opacity, offsets, mirror, layer,
  per-artwork adjustments and reset behavior.

### Existing legacy acceptance details

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
