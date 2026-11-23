# F22 implementation roadmap — proposed, not authorized runtime work

Each phase should produce a reviewable working slice in its own future PR.
Research does not authorize implementing it. Source identity and unknowns are
in [integration](integration.md) and [detection](detection.md). Performance targets
and hard resource bounds are in [effects](effects.md).

## 1. Prove observation and attachment on the matching client

**Scope:** an opt-in development probe, native AuraKit feasibility for the four
categories, bounded binding discovery, identity invalidation, teardown, explicit
unsupported/unknown states. No player-facing effect library. Prove friendly
cleanse and offensive purge separately. Keep a minimal independent fallback
only where source review justifies it; never add a Lua aura scan merely to feed a
secret-dependent condition that cannot be evaluated.

**Dependencies/source:** pinned EUI/Forever evidence; capability-gated native
container contracts and verified player/target/party/raid health-bar mapping.
Confirm which facilities are exported versus private before selecting runtime
coupling. No changes to provider settings or protected attributes.

**Acceptance:** no stale binding after target swap, roster churn or layout
rebuild; unavailable provider fails closed; unsupported predicates visibly
unavailable. Disable/profile changes invalidate all queued work. Coalescing and
resource caps observable via future diagnostics. No production feature enabled
by default. Execute Range retains its independent behavior.

**Tests:** pure contract fixtures for missing/changed provider, both load/event
orders, late provider load, secret sentinels that throw on comparison, recycled
units, failed getters, hidden/forbidden/protected owners, full vs incremental
updates, cancel-after-disable. No copied EUI implementation in fixtures.

**Native owner-directed verification:** record installed build/version; inspect
all four actual frames out of combat and in combat; group join/leave, raid sort,
party-to-raid switch, target swap, reload, disable, layout scale/orientation
changes, friendly vs hostile Magic and dispel capability changes. Check blocked
action/taint reports and no protected click/target behavior changes.

**Risks/decisions:** native slot behavior may not supply public per-aura metadata;
private party/raid discovery is a versioned adapter risk. Confirm the recommended
native path before promising spell-ID rules. **Deferred:** effects, profiles,
editor, priority arbitration requiring restricted facts.

## 2. Ship the smallest useful indicator

**Scope:** one fixed preset with configurable type color, border, low-opacity
tint and optional type icon; selected frame categories; explicit eligibility
scope supported by phase 1. Single winning treatment, conservative text-safe
placement and static reduced-motion behavior. No modification of provider art.

**Dependencies/source:** proven phase-1 contracts, supported native visibility
signals and geometry; existing Execute Range adapter is a pattern, not a public
four-category API. Core renderer runs without Settings opening.

**Acceptance:** state removal clears immediately, unknown eligibility never
becomes “can dispel”, no duplicate overlay on a recycled frame; vertical/reverse
bars and multiple party/raid layouts follow actual geometry. Both Execute Range
and dispel indication remain readable together. Warm-up obeys region caps.

**Tests:** deterministic geometry snapshots and visual fixture captures with
plain/secret/absent data; many units affected simultaneously; no combat pool
growth. Record baseline diagnostics before claiming low overhead.

**Native:** health/name/absorb text and provider indicators remain legible;
combat enable/layout change safely defer as designed; clicks and aura tooltips
remain provider-owned. Compare 1/5/20/40 active units.

**Risks/decisions:** overlap policy and default icon placement need visual review.
**Deferred:** animated layers, particle assets, custom positioning and complex
conditions. Saving configuration requires a separately reviewed feature-owned
profile contract, not speculative schema edits in this batch.

## 3. Presets and simple settings

**Scope:** library, built-in templates, named designs, category/type selection,
color/intensity and safe duplicate/delete/save. Search and truthful prerequisite
messages; simulated player/party/raid preview. Built-ins are immutable with Save
as copy. Simple mode is the default entry point.

**Dependencies/source:** stable phase-2 renderer/config setter boundary;
Settings load-on-demand registration, Kit/CraftLook and narrow artwork-picker
selection adapter. Reuse Reminders draft/apply behavior as a UX pattern, not its
runtime condition engine. Read Magic Inventory rule-builder interactions.

**Acceptance:** a new player can create a Magic border for party frames without
opening Advanced; Save atomic, Cancel/Escape discard draft, invalid settings
cannot replace last working config. Reload/duplicate/profile switch preserve
intended designs, no provider objects persisted. Unsupported options explain why.

**Tests:** settings-only fixtures for searches, load failure, reset scope, draft
isolation, profile changes, future-version hold/recovery and missing asset ID
fallback. Check repeated opens do not duplicate subscriptions.

**Native:** owner walkthrough from library to Save, reopen/reload; keyboard and
large fonts/localization, missing EUI, combat-open policy and overlap review.
**Risks/decisions:** approve initial preset set and profile/share inclusion.
**Deferred:** freeform composition and timeline editing.

## 4. WYSIWYG editing

**Scope:** bounded palette, click-to-add plus drag/drop; select/move/resize,
anchor guides and safe-zone warnings; layer reorder, hide, duplicate/delete;
property inspector, numeric precision, undo/redo and simulated conditions.
A selected design remains a private draft until Save. Preview uses the same
validated render description as live output but owns entirely synthetic frames.

**Dependencies/source:** phase-3 transactional drafts; [editor contract](editor.md)
and approved wireframes. Use actual supported frame geometry where readable;
otherwise label the representative sample. Never manipulate live EUI in editor.

**Acceptance:** every drag has a button/keyboard equivalent; one undo per gesture,
escape cancels gesture, selection stable after reorder; budget errors shown
before Save; Simple→Advanced preserves representation. Advanced→Simple must not
silently discard custom layers; use a preset copy for simplification.

**Tests:** model command history including drag cancel/coalescing, transform
round trips at multiple preview scales, minimum-size bounds, overflow budgets,
missing texture, invalid imports if sharing later exists. Visual review at
supported minimum window size, UI scale, larger fonts and color-vision variants.

**Native:** drag vs scroll input, focus, window movement, Escape and picker return,
layout switching and 40-unit preview responsiveness. No gameplay frame changes
until committed and permitted by combat policy. **Risks/decisions:** minimum
workspace dimensions and reserved-zone policy. **Deferred:** timeline and motes.

## 5. Bounded motion and layered effects

**Scope:** Fade/Breath/Sweep/Motes presets and bounded parameter controls,
coordinated entrance/hold/exit, real-time preview transport and timeline states.
Animation masks only after explicit API feasibility proof; no arbitrary scripting.

**Dependencies/source:** phase-4 layers, catalog-backed approved assets in a
separately authorized artwork batch, Forever texture/animation method checks.
Borrow Victory's deterministic time sampling and cancellation techniques only.

**Acceptance:** budgets from effects.md enforced before render; one shared ticker,
static fallback at animation limits; reduced-motion keeps factual signal; same
winner refresh does not replay; disabled/hidden/rebound frames stop immediately.
No ever-growing particle history. Stable deterministic degradation selection.

**Tests:** time-sampled render snapshots at entrance, peak, sustained, exit;
zero/FPS-jump intervals; pause/scrub; disabled/hidden/profile/rebind cancellation;
full-budget synthetic measurements with recorded machine and configuration.

**Native:** compare 47 visible bindings with zero/eight animations and the particle
cap, low FPS, combat restrictions, rapid aura changes, reduced motion. Collect
p95/p99 rather than advertise unmeasured savings. **Risks/decisions:** approve
motion intensity and initial caps against measurements. **Deferred:** masks or
trails without proven budget and any general-purpose keyframe engine.

## 6. Compatibility, accessibility and polish

**Scope:** saved-profile validation/migration and future-version protection,
optional sharing contract only if separately approved; addon version mismatch
messages, recovery and supported-version matrix, localization/font/accessibility
review, diagnostics coverage, optimized asset resolution and degraded effects.

**Dependencies/source:** final phase-1–5 contracts and actual measurements. Schema
and packaging changes require explicit implementation review; a design format
number in a proposal is not an existing SavedVariables contract.

**Acceptance:** unknown provider shapes hide safely, missing assets preserve IDs
with visible fallback, no schema downgrade, bounded memory over 100 lifecycle
cycles; all performance targets measured or revised transparently. No color-only
signal, essential text covered by default or continuous motion in reduced mode.

**Tests:** migration fixtures from every actually shipped version, future-version
hold, repeated open/close/enable/profile cycles; focused integration against
Execute Range and settings. Run affected suites only; release verification is a
later authorized release task.

**Native:** owner-driven varied classes/talents/spells, dispel/purge mechanics,
40-person raid, provider reconfiguration, hidden units, reload/combat/taint and
supported scales. Record unresolved client-only limitations without implying
that offline checks certify them. **Risks/decisions:** supported EUI version
policy and release readiness. **Deferred:** unrelated conditions, automated
spellcasting, WeakAuras import, global animation framework.

## Proposed data boundary (no saved-data changes)

`Design` has a bounded stable ID/name, validated layers, motion preference and
asset IDs. `Rule` references one design, category set, friendly/hostile scope,
type set, supported eligibility mode, optional supported spell include/exclude
and integer priority. `Layer` has type, anchor, normalized/absolute dimensions,
offsets, RGBA, opacity, order and a small motion preset/parameters. Saved records
contain only validated plain values; no executable expressions, provider tables,
aura handles, restricted data or frame references. Exact versioned persistence,
sharing bounds and migration ownership are decisions for phase 3.

Adapter output and observer facts are ephemeral; unavailable facts retain an
explicit unknown state. Native condition handles must not be converted into Lua
booleans by inspecting restricted values. Compile only the supported subset;
report unsupported rules, never quietly broaden their conditions.

## Owner decisions before future runtime work

1. Approve capability-limited launch: source-proven type/eligibility indicators
   first; spell-level filters/priorities only where plain reliable facts exist.
2. Approve native integration/private-adapter compatibility policy and fail-closed
   behavior when EUI changes; decide whether a supported upstream extension is
   worth requesting in a separate authorized communication.
3. Approve Simple default, separate hostile purge scope, preset set and conservative
   safe-zone/Execute Range coexistence policy.
4. Approve six-layer/sixteen-region budgets, eight animated bindings, static raid
   fallback and reduced-motion treatment, subject to recorded measurements.
5. Approve the editor's minimum workspace and profile/share scope after visual
   review. Native tests are owner-directed follow-ups, not claimed completed here.
