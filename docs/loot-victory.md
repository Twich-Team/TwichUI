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

Runtime assets live in `!!!TwichUI/media/loot/victory/`: 16 exact supplied
32-bit, uncompressed, straight-alpha, power-of-two TGAs (frame, emblems, both
laurels, four rarity halos, bright/small sparks, two dust sprites, rim glint,
sheen and badge), plus both supplied OGG sounds. Header/alpha/size tests validate
the exports; no alpha repair or substitute artwork was needed. The original PNGs,
manifest and approved reference remain in `assets/loot-victory/`, excluded from
shipping. Optional coin sprites, large master, original animated preview and WAV
masters are not shipped. The original asset specification is retained as supplied;
this refinement's timing/layout supersedes its illustrative coordinates.

The reference canvas is now 460×224, displayed at the existing 384-pixel card
width and then at the player's scale. Fifteen texture slices preserve the painted
corners, header rail, recessed item area and footer separator. Only the leather
strips at source y80–108 and y350–364 gain height (10 and 14 reference pixels).
The visible source remains y0–444 of the 1024×512 frame. Title, item details and
footer occupy separate frame layers, above the base artwork. The title has a
204×30 centered box at y24, a restrained dark shadow, and a separate 32×32 emblem
at x88/y23. Cropped laurels flank the header. No emblem/rail can enter the title's
reserved region. The item lines have explicit widths/heights and one-line
truncation; the 33-pixel upgrade badge has its own space in the taller footer.
Both real notifications and preview say “Loot roll won”; no inventory claim or
“Sample victory” label appears on the card. Hover uses Cards.ItemTip and modified
clicks use HandleModifiedItemClick.

### Why the first presentation was weak

The supplied art files were correct. The old y13 title anchor intersected the top
rail, and a fixed x134 emblem anchor did not reserve space for title width. The
entire card was shrunk uniformly without adding room to its cramped footer. The
supplied decorative laurels and principal star sprite were omitted.

The old glint/ribbon canvases were flattened to 4/3 reference pixels; their painted
alpha bands occupy only 23/64 and 47/128 of those heights, leaving roughly one
physical pixel after card scaling. The small star's high-alpha core occupied only
16/64 of a 10-pixel canvas (about 2 display pixels), further reduced by the particle
fade envelope and 0.45 intensity. Those choices made a running animation difficult
to perceive. Source alpha is valid; these were composition, sampling and opacity
problems, not evidence that Forever failed to execute OnUpdate.

The refinement crops transparent padding, preserving painted aspect ratios. The
bright star's 34×38 high-alpha core is drawn inside a 106×116 cropped image on a
34×37 canvas: about 9×10 display pixels at 100% card scale. The ribbon's painted
band is 11 pixels high, inside a real 392×12 clipping frame over the top metal
rail. A luminous core and a short supplied ribbon tail use ADD blending. The
frame and static artwork keep straight-alpha BLEND. `SetClipsChildren` is present
in Forever's SimpleFrame API and used by its Objective Tracker/Map Canvas; actual
client clipping/blending still requires owner validation.

| Time | Behavior |
|---|---|
| 0–0.20 s | Freeze the confirmed result, hide old text/controls, remove progress, crossfade shell materials at the same stack slot |
| 0–0.45 s | Reveal the complete header group with ease-out opacity and five reference pixels of upward travel; no scale/bounce |
| 0.30–1.05 s | One visible smoothstep gold sweep with bright core and short tail, clipped above the title |
| 0.30 s | One optional Need/Greed chime on SFX; shared 0.8-second cooldown |
| 0.55–1.45 s | Six (Subtle) or eight (Full) deterministic sprites stagger outward/upward from emblem/rail/icon locations, away from text |
| 1.10–1.75 s | One bright finishing reflection on the emblem, gently contracting and disappearing |
| 1.75 s onward | Fully opaque static card; no OnUpdate; hold for the configured interval |
| After hold | Smooth 0.30-second whole-card fade and recycle |

Short/Normal/Long now mean a **completed-card hold** of 3.5/4/5 seconds, after the
1.75-second celebration. Normal animated total is 6.05 seconds. Off intensity
shows the static card for the configured hold and removes it without decorative
motion; optional sound accompanies its immediate reveal. Turning intensity Off
stops active decorative work immediately. Full adds one star and one supporting
spark to Subtle's two principal stars, two sparks and two dust motes. Small quality
intensity gains never exceed alpha 1. All effects disappear at rest. Missing
qualities use neutral text/border and no halo; missing roll values omit the number.

Preview roll and Preview item quality are page-local choices, not saved loot data.
Replay always restarts the exact production V.Draw/Animate/Paint path with a fresh
entry. Sample name/type/icon, quality label, name/border color and halo agree with
one quality value. The developer-only `LootVictory.PreviewAt(seconds)` helper
pauses **only a synthetic preview** using that same painter. It cancels timers and
updates, never seeks a real result, and stays silent while seeking. Replay resumes
normal animation from zero; no additional player command/framework was introduced.

Sound failures stay isolated with pcall; both global sound switches and the existing
victorySound toggle are respected. Nothing loops. Frames/textures are pooled; only
active reveal/fade work runs per frame. Rest uses one cancellable timer. Diagnostics
keeps the existing victory event/tick scopes and queue/pool/listener gauges.

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
bash tools/simlab/run.sh loot victoryPose000 victoryPose030 victoryPose060 victoryPose090 victoryPose130 victoryPose175 victoryStatic victoryFade victoryDone victoryOff victoryGreed victoryScaled victorySettings
```

They fire the native event over fake item/roll APIs while running real addon code.
The supplied card/emblems/effects render in captures. Simulator fonts fall back to
a game font, game item icons are unavailable in this cloud lab, and snapshots can
include extra settling time. Screenshot review checks proportions, trim bounds,
spacing and lifecycle, not native font metrics, exact animation rhythm or sound.
Original evidence is retained in [initial evidence](evidence/loot-victory/README.md).
The refinement comparison, 50 ms frame capture and visibility measurements are in
[refinement evidence](evidence/loot-victory-refinement/README.md).

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
   border/halo, visible top-rail sweep, six/eight visible particles, finishing glint
   and the fully static 1.75-second rest. The title/emblem must stay inside the leather banner.
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
