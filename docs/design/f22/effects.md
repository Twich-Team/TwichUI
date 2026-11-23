# F22 bounded visual renderer — proposal

This is a design contract, not implemented functionality or a performance result.
Read [integration](integration.md) and [detection](detection.md) before interpreting
any simulated preview as an available live signal.

## Source reference and narrow reuse

At TwichUI main `364c4c28889d621335bc4b3a7b61d234c0b04ce0`,
[`loot/Victory.lua`](../../../!!!TwichUI/loot/Victory.lua) demonstrates retained
per-card displays (`Build`, `card.victory`), twelve authored sprite trajectories
(`PARTICLES`, first four in Subtle), measured texture UV bounds (`UV`), deterministic
`Paint` time sampling, explicit `Cancel`, `OnHide` cleanup, and separate animation,
hold and exit (`Animate`, `Rest`). Motion finishes at 1.85 seconds; the exit is
0.30 seconds. `R.Perf.Wrap("loot.victory.tick", ...)` instruments the update work.
These are verified craftsmanship techniques, not evidence that the same effect
is cheap on a raid. Do not import its cinematic frame hierarchy, sound, loot
subscriptions, event interception, queue, artwork or whole timeline.

Reuse pure bounded time interpolation concepts and asset lookup conventions.
Use existing `CraftLook`/Settings primitives only in the editor. The renderer
must work without Settings or Loot Rolls loading. Use the shared artwork picker
through a narrow selection-result adapter; inspect/validate asset IDs against an
approved indicator catalog, not arbitrary paths. No dependency on Reminders
runtime state, condition interpreter or placement transaction is needed.

## Pipeline and ownership

Proposed readable-data lane: Observer → plain normalized facts → rule evaluator
→ one winning design per binding → renderer. Restricted-data lane: validated
configuration → native condition/container → native visual regions. Do not
observe a secret-driven slot’s visibility or hook OnShow/OnHide to arbitrate
Lua rules or launch particles. In that lane use fixed disjoint type placements
and native-supported conditional animation only after phase-1 proof; unsupported
layer types remain unavailable. A Lua ticker must not read secret presence. Adapter owns binding identity and cached
geometry, renderer owns only its own mouse-disabled unprotected children/regions.
A binding includes provider identity, frame category, owner, actual bar, current
unit and monotonically increasing generation. Queue work with the generation;
recheck before paint. A reassignment clears all former effects immediately.
Provider fields and frame references never enter saved configuration.

Prebuild permitted slots outside combat. No new frame/texture creation or pool
growth in combat. A new protected binding waits until safe; do not borrow another
unit's slot. Changes of protected hierarchy/geometry hide and defer. No writes to
EUI textures, health colors, secure attributes, settings, clicks or aura containers.
Keep Execute Range's independent ownership and lower/upper texture placements;
acceptance includes both visible together. Tint means a separate translucent
rectangle, never SetStatusBarColor on the provider.

Geometry cache: owner/bar identity, width, height, effective scale, orientation,
reverse fill, category and layout generation. Dirty only on relevant discovery,
size/layout/show changes; revalidate at paint. Parent-relative anchors inherit
movement and scale. Anchor IDs refer to bar or frame edges, not screen pixels.
Offsets use local UI units; optional proportional dimensions resolve on geometry
change. Initial templates keep the central text band and existing aura area clear;
advanced placements crossing these zones display a persistent preview warning.
No invented automatic safe-zone detection: provider text/aura bounds require
verified adapter support, otherwise conservative template margins are labeled.

## Effect vocabulary

| Layer | Representation | Motion allowed | Static fallback |
|---|---|---|---|
| Tint | One inset rectangle, capped opacity by preset | Fade | Constant tint |
| Border | Four edge textures; inset/outset and thickness | Breath opacity | Constant edge |
| Type icon | Catalog symbol plus optional readable type label in preview | Brief fade | Icon |
| Artwork | One approved texture, aspect locked by default | Fade / modest scale | Artwork |
| Glow / highlight | One soft sprite or narrow sweep | Pulse / translation | Soft edge |
| Particle group | Up to four retained sprites; deterministic seeds | Fixed paths, no collision | One sparkle or none |

All color values are plain normalized RGBA. Prefer type icon plus color to color
alone. Layer ordering controls only TwichUI's region order in a bounded frame
level band; it cannot lift effects over arbitrary protected UI. Transparency
multiplies layer alpha, design intensity and envelope alpha. Tint defaults ≤20%
opacity; icons sit outside the health text. Frame-wide highlights never imply
remaining health or dispel urgency that is not known.

Proposed timeline vocabulary is deliberately small: Fade, Breath, Sweep and
Motes. Each has bounded duration, delay and intensity; no scripts, arbitrary key
expressions, event graphs, recursive emitters or user-defined shader programs.
Entrance 120 ms; optional 1.6-second breath; exit 150 ms only while binding still
valid. Removal, reuse, hide, disable and restriction loss cancel immediately;
no decorative exit may suggest an aura remains after reassignment. For readable data, same winner
on aura refresh does not restart entrance. Native-only animation refresh semantics
must be proven separately; do not synthesize a Lua activation signal. A different winner replaces effects
without stacking timelines. Preview has play/pause/replay/scrub with a simulated
clock, never fake events sent into live frames.

Animated masks/reveals are deferred until matching Forever mask methods, blend
behavior, clipping and protected-parent constraints are proven. Initial sweeps
use bounded preauthored texture/UV changes; no runtime asset synthesis. Trails
are at most retained sprites, not a growing history. No production assets in F22.

## Hard budgets (proposed initial defaults)

- At most 64 retained bindings including player/target duplicates and retired EUI
  frames; 40 raid + 5 party + 2 single frames fit. Churn reaching the cap hides new
  bindings until reload; report a bounded diagnostic status rather than grow.
- At most six logical layers and sixteen drawable regions per binding. A border
  consumes four regions; a four-particle group consumes four. Validation computes
  cost before Save; the UI shows both budgets. Max 1,024 retained regions.
- At most four particles per binding and 64 active particles globally; at most
  eight animated bindings globally. Remaining matches show their static fallback.
  For readable facts, rank by rule priority, player then target then party then raid and stable slot;
  retain allocation until winner/visibility changes to avoid animation flicker.
  For secret-driven native effects allocate budget by configured visible frame
  slots out of combat, independent of aura presence; no secret-presence ranking.
- One shared ticker only while active motion exists, sampled at ≤30 Hz; advance
  using absolute elapsed time so low FPS does not stretch effects. No ticker for
  static displays. No per-frame timer chains, table construction, closures or
  generated strings in the animation path. Warm buffers are reused.
- Hidden owners clear effects and leave active lists immediately. Do not animate
  offscreen/invisible frames; IsShown alone does not prove viewport visibility.
  Where visibility cannot be established cheaply, use the static fallback.
- Reduced motion disables travel, particles, scale and repeating pulses; a static
  type icon/border retains the condition. Low-effects mode disables additive
  layers and uses flat borders. Preferences never change factual eligibility.

## Measurement acceptance, not claims

Stage 2 establishes a recorded machine/client/provider baseline. At stage 5 run
synthetic 1/5/20/40-unit aura bursts and 47 visible bindings, then an owner-directed
native encounter capture. Record build, renderer settings, FPS, wall time, sampling
method and p50/p95/p99. Initial targets: observation+evaluation+paint p95 ≤1 ms
per 40-unit coalesced burst and animation tick p95 ≤0.5 ms, p99 ≤1 ms at the stated
budgets on the recorded reference machine. If unmet, reduce defaults or effects;
these thresholds do not establish universal hardware guarantees.

Assert zero scans/ticks while disabled, zero hidden-only animation ticks, no
unchanged-unit scan on another unit's incremental update, one queued dirty item
per unit, no combat frame/texture creation, no pool growth after warm-up over
100 enable/hide/recycle/profile cycles. Memory before/after forced offline GC
should show no monotonically retained state over those cycles; report bytes and
pool counts, not an unsupported zero-allocation claim for API calls.

Future diagnostics: scopes `dispel.observe`, `dispel.evaluate`, `dispel.paint`,
`dispel.tick`, `dispel.editor`; gauges bindings/regions/particles/active motion,
full vs incremental scans, coalesced units, dropped/deferred work and unknown
eligibility. Register with existing `DX.OPS` when implemented. Do not log aura
payloads, unit identities or restricted data. This documentation batch adds no
production instrumentation and makes no measured performance claim.
