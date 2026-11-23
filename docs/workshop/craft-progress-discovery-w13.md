# W13: trustworthy automatic craft progress

Discovery only, 2026-11-22, addon base `cf188dd`. `Progress.auto=false` remains
unchanged. No event hooks/defaults were added. Owner preference for default-on
**after correctness is established** is already resolved in the
[task register](../autonomous-ready-tasks.md); the remaining gate is evidence
and a narrow implementation that preserves manual Done/Undo.

## What the repository establishes

**Unit-tested:** [Progress.lua](../../TwichUI_Workshop/Progress.lua) registers no
event while auto is false, and `OnSpellcast` refuses. Its proposed successful
event contract is `(unit, castGUID, spellID)`: player only, a queued recipe ID
equal to spellID, nonempty cast identity, one operation credited per unique GUID.
`Credit` changes crafts by one through Queue's save/rollback and removes a
finished entry. It remembers an identity only after a successful save. The last
manual credit can be undone. Recipe output quantity is not operation count.

**Historical documented evidence only:**
[planner §15.7](multilevel-crafting-planner.md#157-progress-and-notices-checkpoint-4)
reports Forever 1.60.1 source declarations for
`TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)` and
`TRADE_SKILL_ITEM_CRAFTED_RESULT(itemID, quantity, operationID, …)`, with no
recipe ID in the latter. The local Forever/reference source trees are absent,
so declarations/signatures could not be rechecked. No direct client recording
was available. The set of events Forever actually fires, their payloads, the
recipe/spell mapping, repeated-craft cardinality, and fail/interrupt/cancel order
are **not verified**. A result's itemID cannot uniquely identify a recipe;
quantity or operationID must not be promoted to a completion count without proof.

## Existing Test Lab probe: useful evidence, limited verdict

[cases/Progress.lua](../../TwichUI_TestLab/cases/Progress.lua) provides guided
`crafting.progress.events`. It listens for player spellcast events, craft begin,
crafted result and bag updates while the owner makes three crafts and cancels
one. It changes no queue or auto setting. The summary tests in
`tests/test_testlab.lua` exercise **synthetic** recordings, not actual events.

- Event registration uses `pcall` and discards registration failures. Zero
  observations cannot distinguish an unsupported event from one that did not fire.
- All spellcast events are parsed as `(unit, GUID, spellID)`; each event's real
  signature must be checked independently, especially SENT. A differing payload
  can create misleading cast lines. Only SUCCEEDED would drive production credit.
- `GetRecipeInfo(spellID)` is queried when summarizing, against the then-current
  profession state. A table only shows a lookup worked, not that this was the
  selected learned recipe for that successful operation. Keep the profession
  open and independently record selected recipe IDs.
- The verdict accepts **at least three** recipe successes, zero duplicate
  successes and zero other successes. It does not assert exactly three actual
  operations, one cancel, a partial batch, or a recipe-specific mapping. Its
  “EVIDENCE OK” wording is insufficient by itself to authorize automatic credit.
- Capture stops silently at 400 events; the report prints at most eight cast
  and four crafted-result lines. The result decoder expects one table argument,
  whereas the historical planner describes positional result fields. Until the
  actual payload is known, missing item details are inconclusive. The report
  cannot substitute for raw payload/order evidence where needed.

## Smallest safe follow-up after event evidence

Keep credit at **one confirmed completed operation**, once; repeated batches must
emit that evidence once per operation or need a separately verified adapter.
Never credit start/create clicks, total requested batch size, stop alone, failed
or interrupted casts, or bag increases/decreases. A batch of five cancelled after
two completions must credit exactly two, regardless of produced item count.
Unmapped/ambiguous/missing identities must refuse automatic credit.

The future change is more than flipping `auto`: `Progress.Start` currently has
no matching Stop or `W.Active()` guard, and `W.Suspend` does not stop it. Add
idempotent active/disable/profile cleanup before enabling events. The 64-entry
GUID cache rejects recent replays only; eviction/reload permit old identities
again. Verify actual replay scope and bound any chosen dedup policy; preserve
save-failure retry and final-entry/requeue safety. Resolve manual Done racing
with delayed automatic credit so one operation is not counted twice; manual
Undo must remain understandable. Do not add permanent progress history merely
to cover a hypothetical replay.

`Session.MarkCrafted` explicitly bumps Strategy; an event credit bypasses that
Session method. `Progress.onCredit` currently belongs to Notice and only handles
notice/readiness state. Future automatic credit must invalidate plans and refresh
visible full/compact views independent of notices being on, including when
Workshop was hidden. Use existing coalesced refresh machinery and settled bag
updates; confirm actual success/bag event order. Recalculate `Session.Materials`
and shopping from the **remaining queue plus current bags**. Materials already
combines demand before allocating owned stock once (including existing queued
intermediate-output rules); never subtract consumed materials or crafted outputs
a second time. Example: five crafts needing two reagents each, bags ten; after
two completions queue three and bags six imply demand six and shortage zero.

## Exact owner probe steps (development profile only)

1. Record `/dump GetBuildInfo()` and addon revision. Install/open the existing
   development Test Lab as described in [Test Lab](../testlab.md#installation-development-only).
   Enable Workshop experimental consent normally. Keep automatic counting off;
   record queue counts and do not press manual Done during capture.
2. Open one own profession and leave it open through report creation. Open Test
   Lab via its data-bar menu or `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`;
   on later runs use `/tuilab`. Untick other groups, tick **Crafting progress
   probe (opt-in)**, press Run. Use a cheap learned recipe and known operation
   counts. Within the 120-second listening window perform three operations and
   start/cancel one more, then click the guided **Done** (not Workshop Done).
   Copy report and save exact recipe/name, visible operation count, output count,
   cancellation action and final bag/queue values beside it.
3. Repeat separately for three single Create clicks, a requested three-operation
   batch, a five-operation batch cancelled after exactly two successes, and a
   multi-output/ranged-output recipe if available. Add one interrupted attempt
   and one naturally refused attempt (for example insufficient reagents); do
   not manufacture failures by invoking Craft APIs. Keep each run small enough
   for all relevant cast lines; do not mix unrelated spells. Repeat for another
   profession and recipe to test mapping, not just lookup coincidence.
4. For each run compare **unique successful GUIDs** to actual completed operations
   and selected recipe ID. Confirm cancellation/failure has no success for the
   uncompleted operation. Save exact event arguments and order using Blizzard's
   event trace tool (`/etrace`, if installed) for the probe's listed events,
   including success/result/bag timing. Record registration support and raw
   result payload shape. If that tool/source is unavailable, return the probe
   reports first: a separately scoped read-only probe improvement is needed;
   neither an empty report nor its verdict closes those unknowns.
5. Supply matching Forever generated API documentation and native profession
   source revision to verify event signatures/selection mapping. Review these
   recordings before any default change. A later implemented adapter additionally
   needs synthetic duplicate/late-event, save-failure retry, requeue, manual
   race/Undo, disabled/profile/combat lifecycle and material-refresh tests.

Verification: `test_workshop_compact.lua` and `test_testlab.lua` pass with Lua
5.1/bitop; existing manual/guard/dedup and synthetic summary behavior remain
intact. No simulator, direct Forever source verification or real-client test
was performed. No runtime/economic change means no mutation campaign is needed.
