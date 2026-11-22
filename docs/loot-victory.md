# Loot Victory

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
emblems, two laurels, four rarity halos, rim highlight and badge. Both original
OGGs remain unchanged. Five superseded original effects (bright/small sparks,
two dust sprites and sheen ribbon) no longer ship. Their authoring originals and
historical evidence remain outside the addon.

`!!!TwichUI/media/loot/victory/fx/` contains exactly eleven byte-identical TGAs
from **TwichUI Victory FX Supplement v1**:

| Use | Individual runtime files |
|---|---|
| Atmosphere | `fx_header_haze.tga`, `fx_icon_gold_haze.tga` |
| Brief blooms | `fx_header_bloom.tga`, `fx_emblem_burst.tga`, `fx_icon_bloom.tga` |
| Synchronized sweep | `fx_sweep_haze.tga`, `fx_sweep_core.tga` |
| Item-arrival punctuation | `fx_glint_small.tga` |
| Six reusable particle slots | `fx_particle_star_4point.tga`, `fx_particle_twinkle.tga`, `fx_particle_mote_medium.tga` |

The optional violet ring and other alternatives are not loaded or shipped.
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

### Layers and blending

All supplemental light uses supported `ADD` blending, without vertex tinting.
Original static artwork and quality halos retain straight-alpha `BLEND`.
Layer order relative to the existing victory frame is:

1. Base sliced leather/bronze artwork at the frame's own level.
2. Atmosphere and blooms at level +1. Haze uses BACKGROUND, blooms ARTWORK.
   The two-texture sweep uses a 392×46 clipping frame at +1; its canvas explicitly
   stays at +1 too. Its core uses OVERLAY within that lower frame.
3. Title, laurels, emblem, item icon, rarity border and text at level +2. Neither
   ambient light nor the sweep draws over item pixels or title text.
4. Six deterministic particles and one arrival glint at level +4, on paths outside
   the item-name rectangle. Normal item interactions/tooltips retain their owners.

New frames inherit the existing card strata and cannot intercept mouse input.
No new client API, animation group or global particle manager is introduced.
Forever source documents `SetClipsChildren` and uses additive textures. Native
TGA sampling, blend appearance and real font clearance still need client review.

### One shared timeline

All poses use the existing `V.Paint`, update loop and cancellable hold/fade timers.
`V.MOTION_END = 1.65` stops active lighting work; `V.HOLD_AT = 1.75` preserves the
previous completed-card hold and dismissal schedule. There is no idle OnUpdate.

| Seconds | Effect | Peak alpha, Subtle / Full |
|---|---|---|
| 0.00–0.25 | Header and icon atmosphere awaken | Header 0.35 / 0.42; icon 0.30 / 0.36 |
| 0.00–0.45 | Existing header reveal and result-material transition | Existing easing and five-pixel header travel |
| 0.20–0.53 | Brief title bloom, peak at 0.30 | 0.62 / 0.75 |
| 0.24–0.56 | Burst behind Need/Greed medallion | Off / 0.55 |
| 0.30 | Existing optional chime on SFX | Same sound and shared 0.8-second cooldown |
| 0.38–1.05 | One eased left-to-right haze/core sweep | Haze 0.35 / 0.45; core 0.90 / 1.00 |
| 0.55–1.35 | Three / six controlled star, twinkle and mote paths | Stars up to 0.90 / 1.00; Full motes 0.65 |
| 0.90–1.50 | Icon arrival bloom, peak at 1.10 | 0.42 / 0.62 |
| 0.98–1.50 | Small glint near icon frame, peak at 1.12 | 0.90 / 1.00 |
| 0.70–1.65 | Atmosphere gently settles | Rest: header 0.16 / 0.18; icon 0.12 / 0.15 |
| 1.65 onward | No particles, blooms, sweep or updater; only residual haze | Fully readable static card |
| Existing hold/exit | Configured 3.5/4/5-second hold budget after 1.75, then 0.30-second fade | Normal animated lifetime stays 6.05 seconds |

Off hides **all supplemental textures** and runs no animation update, preserving
the original clean card, rarity halo and configured static hold. Existing explicit
preferences and the Subtle default remain unchanged. Turning Off during a real
win cancels the update and clears all lighting immediately.

The two sweep textures replace the old four-layer sweep. Three (Subtle) or six
(Full) particle slots replace the old eight, with fixed eased paths around the
icon corners and measured laurels. The existing icon border is not recolored or
pulsed by the light. No continuous emitter, scaling, spinning or whole-card flash.
Frames/textures are constructed once per pooled card. Paint allocates no particle
objects; hide, interruption, disable and replay keep the existing cleanup owners.

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
bash tools/simlab/run.sh loot victoryPose030 victoryPose060 victoryPose090 victoryPose120 victoryPose170 victoryPoseFull030 victoryPoseFull060 victoryPoseFull090 victoryPoseFull120 victoryPoseFull170 victoryPoseOff170 victoryReplay victoryStatic victoryDone victorySettings
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
[lighting evidence](evidence/loot-victory-lighting/README.md).

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
   border/halo, visible top-rail sweep, three/six visible particles, item-arrival glint
   and the softly lit static rest after 1.65 seconds. The title must stay clear of the rail; the medallion should sit deliberately on its lower divider.
4. Hear each OGG once at the reveal, then test sound off, global SFX/all sound off,
   rapid wins, and intensity Off/Subtle/Full. Check Normal/Short/Long durations.
5. Hover item tooltips and modified item links. Test during combat with taint/error
   reporting enabled; no protected-action errors should appear.
6. Disable victory notifications and the whole module during a queued burst;
   pending results should return to native. Trigger achievements, quests, normal
   loot acquisition, currencies and upgrades; all unrelated alerts should remain.
7. Use the sample roll/quality selectors and Replay repeatedly (all eight combinations),
   change profiles and reload, and verify settings persistence and cleanup.
   Check with other loot/alert addons and the actual installed Forever build.
