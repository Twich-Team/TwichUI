# Loot Victory

For Expanded/Collapsed layouts, per-instance overrides and late-event presentation
retention, see [compact loot cards](loot-roll-compact.md). The Expanded celebration
and native notification ownership below remain in place.

Loot Rolls now replaces a confirmed Need/Greed winning notification with the supplied
leather/bronze victory artwork. The Loot Rolls module remains off by default;
within it, Custom victory notification is on, intensity is Subtle, sound is off until the player opts in,
and duration is Normal. Existing rule evaluation and RollOnLoot submission remain
in their existing owners.

## Events and ownership

The inspected Forever UI source is Gethe `forever` revision `ca8368f2f` (the
simulator's pinned 1.60.1.70532 source). Its `Blizzard_FrameXML.toc` loads
`Mainline/AlertFrames.lua`, `Mainline/AlertFrameSystems.lua`, and
`Camelot/AlertFrameSystemsOverride.lua`; the Camelot override only changes mount
quality. `Blizzard_APIDocumentationGenerated/LootDocumentation.lua` declares
`LOOT_ITEM_ROLL_WON(itemLink, rollQuantity, rollType, roll, upgraded)`.
`AlertFrameMixin:OnEvent` routes that event to `LootAlertSystem:AddAlert` with
Need/Greed type and roll value. This is the authoritative self-win signal, including
wins whose custom roll card/record has already disappeared.

The preexisting path is START_LOOT_ROLL → observation/rules → pending/scheduled →
submitted via RollOnLoot → CANCEL_LOOT_ROLL confirms placement → history or
LOOT_ROLLS_COMPLETE resolves the record → linger/prune. C_LootHistory supplies
`rollInfos`/`winner` with `isSelf`, `state`, and `roll`, but identifies drops by
encounter/key and item hyperlink, not roll ID. It continues to populate ordinary
results. Neither a selection nor a history update starts this animation.

`loot/Victory.lua` owns presentation and a private win-event relay. When enabled,
it requires a registered, unprotected AlertFrame and a callable original OnEvent
script. It unregisters **only LOOT_ITEM_ROLL_WON from AlertFrame**, registering that
event on its own frame. It never replaces a Blizzard function/script, hides a
Blizzard alert container, changes loot acquisition, or alters server events.
Achievements, quests, money, currencies, SHOW_LOOT_TOAST, upgrades and other alerts
retain their registrations and handlers. The original script receives unsupported,
ambiguous, overflow, or failed presentations. Disable/error restores registration
and forwards every unfinished accepted result. If another addon re-registers the
native win event while the relay is active, the relay relinquishes ownership.
There are no combat-protected operations or secure hooks in this implementation;
actual combat/taint behavior still needs native validation.

If the selective path is absent, protected, or already owned by another replacement,
TwichUI leaves the native notification alone and shows no additional custom victory.
Preview remains available. This capability check is source/simulator evidence,
not a guarantee for a different Forever build or third-party alert replacement.

## Stack and lifetime

A unique matching roll reuses its existing pooled card and numeric stack key.
Confirmation freezes a view and resolves the original record, preventing another
choice. The normal renderer skips that record thereafter. The victory entry
survives pruning/dismissal of the original record; unmatched late wins get a fresh
key at the same configured stack anchor. Ambiguous concurrent identical hyperlinks
fall back to native rather than guess which roll/card won.

Started victories retain priority; new ones wait behind live controls and before
ordinary finished results. The existing maxCards setting bounds visible cards.
The queue holds at most 32 wins; overflow goes to native. Every queued entry gets
its duration when it first appears. Reducing maxCards suspends excess entries,
cancels their update/timer work, and resumes them with a fresh readable duration.
The existing card pool can retain one retiring slot beyond the visible count;
there is one additional reusable preview card. No loot/item history is saved.

Native win events carry no unique result ID. Exact duplicates associated with a
claimed original roll are ignored while that record remains, plus a bounded
64-entry, one-second recent-event guard. Fresh roll records can still win with
identical values. **Two identical late events without any source record cannot be
distinguished reliably:** the repeated event goes to native rather than silently
lose a possibly distinct win. This exceptional case can show a native notification
after the first custom card. There is no global acquisition-toast suppression.

## Artwork and animation

The approved 460×218 reference canvas still displays at 384 pixels wide before
the player's scale. Title/laurels/medallion, item/text geometry, quality colors,
roll information and conditional upgrade badge retain their approved positions.
The 15-slice leather/bronze backdrop keeps its painted corner scale. Single-line
name fitting preserves whole UTF-8 characters and the complete item tooltip.

### Runtime assets and alpha

`!!!TwichUI/media/loot/victory/` retains eleven original TGAs: frame, Need/Greed
emblems, two laurels, four rarity halos, rim highlight and badge. The supplied
cue ships as `loot_won.ogg`, a 48 kHz stereo Vorbis export. Five superseded original effects (bright/small sparks,
two dust sprites and sheen ribbon) no longer ship. Their authoring originals and
historical evidence remain outside the addon.

`!!!TwichUI/media/loot/victory/fx/` contains thirteen byte-identical TGAs
from **TwichUI Victory FX Supplement v1**:

| Use | Individual runtime files |
|---|---|
| Atmosphere | `fx_header_haze.tga`, `fx_icon_gold_haze.tga` |
| Brief blooms | `fx_header_bloom.tga`, `fx_emblem_burst.tga`, `fx_icon_bloom.tga` |
| Synchronized sweep | `fx_sweep_haze.tga`, `fx_sweep_core.tga`, `fx_sweep_trail.tga` |
| Sharp glints / burst stars | `fx_glint_small.tga`, `fx_emblem_final_star.tga` |
| Twelve reusable particle slots | `fx_particle_star_4point.tga`, `fx_particle_twinkle.tga`, `fx_particle_mote_medium.tga` |

The supplied trail and final-star alternatives solve specific sweep/burst roles.
The optional violet ring and all other alternatives are not loaded or shipped.
Original supplement manifest/docs, selected editable PNGs and reference previews
live in `assets/loot-victory-fx/`. That directory is excluded by `.pkgmeta`, as are
all `assets` and `docs`. Full source atlases stay in the supplied archive; no atlas
is rendered. These are 32-bit uncompressed straight-alpha power-of-two TGAs.
Checksums, dimensions, alpha bits and transparent outer borders are unit-tested.

Manifest content UVs remove invisible canvas padding. The medium mote's generic
113×113 content rectangle still encloses a roughly 52×53 painted sprite, so its
UVs use measured alpha bounds plus two transparent pixels (x43..99, y32..89 on
128×128). This preserves its feathered edge and makes a 10–12 reference-pixel mote
visible without stretching a large empty rectangle. Artwork pixels are unchanged.
Other sprites use the provided content UVs. The existing cropped rarity halos
remain at static alpha 0.42, with no second independent pulse.

### Rectangular sweep diagnosis

The supplied sweep haze/core/trail exports have transparent outer canvas edges,
zero RGB in transparent pixels, and clean sampled content perimeters. Unit tests
verify both the canvas and actual manifest-UV borders (at most 1/255 alpha).
PNG and TGA decoded pixels agree; no alpha conversion repair was needed.

The prior implementation used a 392×46 `SetClipsChildren(true)` header viewport.
When the bright moving texture reached its right edge, that viewport sliced the
feathered light into a hard vertical cutoff. The isolated `sweepLab` scenario
reproduces this at gameplay size over black, leather, gray and checkerboard, at
full and half opacity. Removing the scissor restores the complete feather at the
same brightness. This is the reproduced rendering cause; native-driver appearance
still needs client confirmation, especially without a new native artifact capture.

The production sweep is now unclipped. Its core moves from x55 to405 at y15 on the
460-pixel canvas, keeping the bright center on bronze while the haze and short
supplied tail retain their complete transparent fringes. Brightness is not reduced
to disguise the boundary. No generic replacement texture or procedural glow is used.

### Layers and blending

Supplemental light uses supported `ADD` without item-icon vertex tinting. Original
artwork and quality halos retain straight-alpha `BLEND`. Layers relative to the
victory frame, rear to front:

1. Original sliced leather/bronze base at its own level.
2. Atmosphere, header/emblem blooms, expanding radial burst and icon light at +1.
3. The one synchronized haze/core/tail sweep at +3, above the bronze but unclipped.
4. Small trim glints and twelve pooled particles at +4. Only four slots are used
   in Subtle. Full's fixed paths can escape 15–30 UI pixels above/around the frame.
5. Original title/laurels/emblem, item icon/border, all item text and badge at +6.
   Text remains above competing light, including effects from adjacent cards.

New frames inherit the card's existing strata and disable mouse input. None of the
card ancestors clip these effects. No new protected API or global particle manager
is involved. The local Forever source documents clipping and uses additive blend
textures; actual native sampling, blending and font clearance remain unverified.

### One shared celebration timeline

The existing V.Paint/update/timer architecture remains. `V.MOTION_END` and
`V.HOLD_AT` are 1.85 seconds: the new afterglow completes before the configured
3.5/4/5-second finished-card hold. The original 0.30-second dismissal fade stays;
Normal animated lifetime is now 6.15 seconds (0.10 seconds longer). No idle updater.

| Stage | Time | Subtle | Full |
|---|---|---|---|
| Ignition | 0–0.20 s | Soft header/icon atmosphere | Richer haze expands slightly; emblem begins glowing |
| Radiant burst | 0.20–0.60 s, peak around 0.38–0.40 | Header bloom peaks at 0.38 alpha | Header bloom 1.00, emblem glow 0.80, large supplied radial bloom 0.95, three prominent stars; eight particle slots overlap by 0.55 |
| Golden sweep | 0.45–0.95 s | Core 0.75, haze 0.28, tail 0.20 | Core 1.00, haze 0.60, tail 0.65; two synchronized trim glints |
| Item arrival | 0.75–1.40 s, then decay | Bloom 0.35, frame glint 0.80, subtle actual-rarity rise | Bloom 0.85, frame glint 1.00, stronger actual-rarity rise and outward sparks |
| Afterglow | 1.40–1.85 s | Four quiet sparks/motes fade | Twelve fixed particle paths finish; large haze contracts back inside the header |
| Rest | 1.85 onward | Header/icon haze 0.12/0.09 | Header/icon haze 0.18/0.14; all bright effects gone |

Header haze peaks at 0.28/0.65 and icon haze at 0.23/0.48 (Subtle/Full). The supplied
header haze grows from 88% to 100% size during ignition; the card never scales. The radial
copy opens above the header only in Full. The body is never flooded with light.
The supplied stereo victory cue starts at 0.30 seconds with the rising burst.
Rapid reveals queue their cues 1.55 seconds apart so the 1.48-second tail can
finish. Victory Sound and the game SFX settings govern playback.

Full uses three prominent supplied final-star glints, medium star/twinkle sparks
and smaller motes, with intentionally staggered attack/decay. Some paths arc gently;
others drift or barely move. There is no randomness, spinning, bounce or emitter.
The quality ring is driven by actual item data, rising by at most 0.06/0.22 during
arrival and returning to 0.42. It never substitutes purple for another rarity.

Off clears every supplemental layer and has no animation updater. All objects are
built once per pooled card; painting creates no frames, textures, tables or particles.
Twelve slots replace six; the added radial copy, tail and two trim glints are fixed
pooled textures. Hidden/interrupted/disabled cards cancel their existing update and
timer owners. Queue limits, duplicate handling and native fallbacks are unchanged.

### Preview and capture behavior

The previous gray GIF was the fully transparent time-zero pose, which was also its
first frame and therefore the only image in viewers that do not animate GIFs. The
actual preview was not failing to load: later poses and clock-driven playback were
present. A transparent 0.00-second pose remains correct for the fade-in and is still
tested. The review workflow now provides a visible production-pose poster, a GIF
starting with that poster, a short MP4 and six separately labeled checkpoint images.
The motion export starts at 0.10 seconds, omitting the intentionally empty first
instant and showing the active reveal through completed rest. No native rendering
is fabricated; sampled poses and repeated hold frames are labeled as simulator data.

Preview roll/quality selectors remain page-local and cover all eight combinations.
Replay uses the production Draw/Animate/Paint path and resets every light, particle,
position, alpha, timer and sound state. The existing developer-only
`LootVictory.PreviewAt(seconds)` silently freezes only a synthetic preview using
that same painter. An optional third preview fixture argument supports long names
and missing upgrades without saving or creating a real result. Sound behavior,
confirmed-win attribution and selective Blizzard notification handling are intact.

## Verification

Unit coverage extends the existing loot rules/automation regression and checks
Need/Greed wins, losses/Pass, late/no-record wins, duplicate events, rapid queues,
overflow, missing metadata/value/audio, all quality fallbacks, static mode,
independent/global sound switches, timeout/reuse, interruption, combat simulation,
registration ownership, unrelated alerts, ambiguous links and renderer failure.
A dedicated settings test describes the real page/search rows and checks defaults,
setters, saved-value reconstruction and reset without enabling the module.
These are synthetic clients, not native reload/combat/input tests.

Simulator scenarios are available through:

```sh
bash tools/simlab/run.sh loot sweepLab victoryPose015 victoryPose040 victoryPose070 victoryPose100 victoryPose145 victoryPose185 victoryPoseFull015 victoryPoseFull040 victoryPoseFull070 victoryPoseFull100 victoryPoseFull145 victoryPoseFull185 victoryPoseOff185 victoryReplay victoryStatic victoryDone victorySettings
```

They fire the native event over fake item/roll APIs while running real addon code.
The supplied card/emblems/effects render in captures. Simulator fonts fall back to
a game font, game item icons are unavailable in this cloud lab, and snapshots can
include extra settling time. Screenshot review checks proportions, trim bounds,
spacing and lifecycle, not native font metrics, exact animation rhythm or sound.
Original evidence is retained in [initial evidence](evidence/loot-victory/README.md).
The refinement comparison, 50 ms frame capture and visibility measurements are in
[refinement evidence](evidence/loot-victory-refinement/README.md). The latest header,
footer, long-name and finishing-accent comparison is in
[final polish evidence](evidence/loot-victory-polish/README.md). The latest
supplemental lighting captures, timing and identity are in
[lighting evidence](evidence/loot-victory-lighting/README.md). The current burst,
sweep isolation and repaired review exports are in
[celebration evidence](evidence/loot-victory-celebration/README.md).

## Owner-directed in-game checks

Update the addon from this branch and reload to rebuild the pooled frames. Open
Loot Rolls, choose each roll/quality combination, and use Replay before testing
actual dungeon loot. The preview card should have no sample label, no title/rail
collision and no emblem/title overlap.

1. With Loot Rolls enabled, win real Need and Greed rolls; verify exactly one
   winning alert, correct icon/name/type/quality/method/value and no false win
   after losing or passing. Check automatic rules still submit once.
2. Resolve several rolls together, including identical items; verify unique
   attribution or the documented native fallback. Confirm late wins after the
   original card disappears. Check timeout and no reappearing old result.
3. Compare the supplied static/GIF previews at 75%, 100%, and larger UI scales:
   font baselines, long/localized names, emblem alignment, alpha edges, icon
   border/halo, visible top-rail sweep, four/twelve visible particles, item-arrival glint
   and the softly lit static rest after 1.85 seconds. The title must stay clear of the rail; the medallion should sit deliberately on its lower divider.
4. Hear the Ogg cue once at the reveal, then test sound off, global SFX/all sound off,
   rapid wins, and intensity Off/Subtle/Full. Check Normal/Short/Long durations.
5. Hover item tooltips and modified item links. Test during combat with taint/error
   reporting enabled; no protected-action errors should appear.
6. Disable victory notifications and the whole module during a queued burst;
   pending results should return to native. Trigger achievements, quests, normal
   loot acquisition, currencies and upgrades; all unrelated alerts should remain.
7. Use the sample roll/quality selectors and Replay repeatedly (all eight combinations),
   change profiles and reload, and verify settings persistence and cleanup.
   Check with other loot/alert addons and the actual installed Forever build.
