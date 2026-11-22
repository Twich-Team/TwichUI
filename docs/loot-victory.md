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

Runtime assets live in `!!!TwichUI/media/loot/victory/`: the exact supplied
32-bit, uncompressed, straight-alpha, power-of-two TGAs for the base frame,
Need/Greed emblems, four rarity halos, rim glint/sheen, three spark/dust sprites,
and upgrade badge; plus both supplied OGG sounds. TGA and OGG match established
addon/client format usage. Header/alpha/size checks validate the exports; actual
Forever decoding/playback remains untested. The base uses UV `0,1,0,444/512`.
A fixed 460×200 canvas scales uniformly to the existing 384-pixel loot-card width,
then follows the player's card scale. Decorative corners keep their proportions.
Item icon/border, labels, quality, method/value and upgrade text are native regions.
The neutral footer says “Loot roll won”; inventory acquisition is never asserted.
Item hover reuses Cards.ItemTip; modified item clicks use HandleModifiedItemClick.

`assets/loot-victory/` keeps the supplied manifest, README/specification, PNG source
exports and approved static reference. This folder is excluded by `.pkgmeta`.
Optional laurels/coin sprites and spark_bright are intentionally unused: the
approved five-particle sequence needs no extra ornament. The large master, animated
preview and WAV masters remain in the supplied archive and are not shipped.

| Time | Behavior |
|---|---|
| 0–0.20 s | Freeze result, disable controls, remove progress, crossfade old content into the fixed artwork at the same stack slot |
| 0.15–0.45 s | Runtime title and appropriate emblem fade in, settling by two reference pixels without overshoot |
| 0.35–0.80 s | One smoothstep trim sweep; both supplied highlights stay physically within the top rail and outside text |
| 0.45–1.20 s | Five authored spark/dust positions; each drifts upward 8–12 reference pixels and slightly outward; no randomness |
| 0.48 s | One supplied Need/Greed chime on SFX, subject to sound switches and a shared 0.8-second cooldown |
| 1.20–3.70 s | Static; no OnUpdate script; one cancellable timer awaits fade |
| 3.70–4.00 s | Smooth whole-card fade and recycle |

Short/Normal/Long durations are 3.5/4/5 seconds. Off intensity shows an immediate
static card for the chosen duration, without reveal/fade/particles; its sound,
if enabled, accompanies the immediate reveal. Switching intensity off during a
reveal immediately stops decorative updates. Subtle/Full share the same five
sprites; Full raises opacity modestly, with small Epic/Legendary intensity gains.
Missing qualities have a neutral border/text fallback and no halo. Missing roll
values omit the number. Missing metadata uses available roll/link information and
a question-mark icon until a subsequent notification; it never invents facts.

Sound failures are isolated with pcall; Sound_EnableAllSound and Sound_EnableSFX
are respected in addition to the independent victorySound setting. Nothing loops.
The animator derives curves from client elapsed time, so frame rate cannot change
travel distances. Frame/texture allocations occur only when warming the pool.
Hidden/recycled frames cancel their timer and update script. Diagnostics registers
`loot.victory.event`/`loot.victory.tick` and queue/pool/listener gauges.

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
bash tools/simlab/run.sh loot victoryResolve victoryReveal victorySheen victoryParticles victoryStatic victoryFade victoryDone victoryOff victoryGreed victoryScaled cards
```

They fire the native event over fake item/roll APIs while running real addon code.
The supplied card/emblems/effects render in captures. Simulator fonts fall back to
a game font, game item icons are unavailable in this cloud lab, and snapshots can
include extra settling time. Screenshot review checks proportions, trim bounds,
spacing and lifecycle, not native font metrics, exact animation rhythm or sound.
Selected captures and results are recorded in [evidence](evidence/loot-victory/README.md).

## Owner-directed in-game checks

1. With Loot Rolls enabled, win real Need and Greed rolls; verify exactly one
   winning alert, correct icon/name/type/quality/method/value and no false win
   after losing or passing. Check automatic rules still submit once.
2. Resolve several rolls together, including identical items; verify unique
   attribution or the documented native fallback. Confirm late wins after the
   original card disappears. Check timeout and no reappearing old result.
3. Compare the supplied static/GIF previews at 75%, 100%, and larger UI scales:
   font baselines, long/localized names, emblem alignment, alpha edges, icon
   border/halo, top-rail sheen, five subtle particles and the 1.2-second rest.
4. Hear each OGG once at the reveal, then test sound off, global SFX/all sound off,
   rapid wins, and intensity Off/Subtle/Full. Check Normal/Short/Long durations.
5. Hover item tooltips and modified item links. Test during combat with taint/error
   reporting enabled; no protected-action errors should appear.
6. Disable victory notifications and the whole module during a queued burst;
   pending results should return to native. Trigger achievements, quests, normal
   loot acquisition, currencies and upgrades; all unrelated alerts should remain.
7. Use the settings preview repeatedly (cycles Need/Greed and four qualities),
   change profiles and reload, and verify settings persistence and cleanup.
   Check with other loot/alert addons and the actual installed Forever build.
