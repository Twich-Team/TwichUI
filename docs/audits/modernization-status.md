# Modernization status

2026-11-16. Main after normal PR #39 merge:
`74f5502072bf866ba901079591aa4b4674bfe532`. Publication remains disabled.
This status supersedes campaign stopping instructions in older audit reports;
those reports retain their original evidence and limitations.

## Completed and partial work

| Area | Current status and remaining boundary |
|---|---|
| Release engineering — PRs #31–33 | **Implemented; operational acceptance partial.** Verification is independent of publishing; immutable candidates, digest-bound retry/promotion, protected solo approval, pinned build inputs and exact Forever compatibility mapping exist. [Release procedure](../../RELEASING.md) records inspected protections, but secret scope was not verified and an approved end-to-end promotion/client gate remains outstanding. No release was authorized here. |
| Agent documentation — #34 | **Completed.** Canonical shared rules, thin adapters, ownership map and conservative manual test guidance replaced stale navigation. [Navigation evidence](phase-a2-navigation.md) demonstrates correct routes, not measured AI task-time/token savings. Automatic dependency/group inference remains deferred; its maintenance/risk is not justified by current evidence. |
| Testing efficiency — #26 and #36 audit | **Scoped workflow implemented; deeper attribution partial.** Existing development/feature/integration profiles, independent full discovery, telemetry, faster PNG decoding and optional isolated catalog workers already address routine cost. [Verification audit](../testing-verification-audit.md) records one historical 21.9% representative parallel improvement, not a universal/full-suite saving. Fixture-only native attribution and large offline mock heaps remain unproven optimization targets; no repeat audit is needed now. |
| Repository/evidence — #37 | **Safe cleanup completed.** 269 duplicate paths removed, 21.67 MB gross / 21.53 MB net checkout payload saved at that campaign snapshot. All distinct historical bytes and 40 linked output targets remain in Git with hashes; bounded 14-day CI diagnostics and a new-output tracking guard are active. [Cleanup](repository-evidence-cleanup.md). Remaining 36.96 MB of unique historical output and 113 pre-existing missing historical links are deliberately deferred. No Git-history/clone-transfer saving is claimed. |
| Market — #35 | **Investigation completed; native acceptance pending.** [Market report](phase-a2-market-performance.md) separates compilation, validation, hashing and UI cycles, and supplies exact synthetic fixtures/procedure. No production optimization or native operating envelope was established. Do not repeat its offline investigation or weaken integrity checks. |
| Runtime architecture — #38 | **Investigation completed; one candidate implemented.** [Runtime report](phase-a2-runtime-architecture.md) identified startup attribution gaps and bounded follow-ups. #39 addresses Advisor sorting. Startup/profile costs still need client evidence; broad module/package splits and Settings extraction have no demonstrated return. |
| Item Advisor — #39 | **Implementation and automated verification completed; Forever acceptance pending.** Bounded native sort runs plus cooperative merging preserve unique numeric-ID ordering and original row objects. View/pricing/eligibility/filtering code is unchanged. Existing generation/visibility checks discard stale work, and buffers are local to the coroutine. [Performance report](advisor-performance.md). |

The [A1 findings](phase-a1-findings.md), [baseline](phase-a1-baseline.md),
[release audit](phase-a1-release-engineering.md) and
[verification hygiene audit](phase-a2-verification-hygiene.md) remain historical
inputs, not lists of changes still automatically required.

## PR #39 review and final test status

Reviewed all eight changed files, including the benchmark, tests, mutation models
and recorded evidence. No blocking defect or correction was identified. Final
GitHub `verify` passed in **6m29s** on head `1f44ba0`; the internal build was skipped.
This task recalculated sample medians and checked production hashes; it did not
repeat expensive benchmarks or simulator catalogs.

Historical 20,000-item offline medians: longest catalog step **14.602 → 3.720 ms**;
longest overall callback **15.257 → 10.859 ms**; total timed callback CPU
**201.051 → 200.419 ms** (no established total speedup). Costs: **34 extra callbacks**
and **578.9 KiB additional sampled temporary heap**. Retained heap after completion
and release was unchanged in the measured fixture. These exclude native rendering
and timer waiting; they are not gameplay or elapsed-client measurements.

Existing evidence: three development modules; all 60 feature-selected offline
modules/syntax; 13/13 Advisor mutations killed; exact ordering/row-identity/metadata
boundary cases; mid-sort hide, replacement and suspension checks. The suspension
mock explicitly drives child OnHide as the native frame tree does; this is not
native disable acceptance. Existing selection/scroll/filter tests, replay and
wrong-expectation controls remain intact. The initial feature aggregate remains
failed for sandbox UID-map refusal; a separate elevated retry of its twelve
selected poses passed **with known simulator limitations**. No local full/release
certification, native appearance or Forever performance acceptance is claimed.

## Next priorities — at most three, no new implementation authorized

1. **One controlled Forever runtime capture.** Start with Advisor 1k/20k catalogs,
   then login/reload and first/repeated Settings use using existing Diagnostics/
   LoadTest. Source evidence shows the startup capture starts after file execution
   and SavedVariables loading; Advisor's extra timer turns may affect wall time.
   Benefit: validate the implemented tradeoff and choose any genuinely expensive
   eager work. Effort medium (controlled client setup), low measurement risk;
   later startup changes are higher risk. **Client measurement comes first.**
   Freeze package/data/addons/scale; record frame and callback p95/max, total wall
   completion, instrumentation overhead, counts and comparable memory checkpoints.
   Verify close/disable/replacement and profile cycles; revert only Advisor sorting
   if its responsiveness/completion tradeoff fails acceptance. Add instrumentation
   only when existing tools cannot answer a specific material question.
2. **Complete the already-defined Market native envelope.** Offline attribution
   estimates hashing at roughly 68% of validation CPU, but does not establish
   client slice/frame or completion budgets. Benefit: a trustworthy operating
   envelope and evidence for or against one isolated SHA improvement. Effort
   medium; optimization/integrity risk high. **Forever first:** follow the exact
   smaller-case progression, corruption/replacement and suspension procedure in
   the Market report, with fixed fixtures and agreed limits. Only if native hash
   CPU dominates should a later change prove byte/hash parity, preserved negative
   controls, no worse slice/retention behavior and improvement beyond noise.
   Coordinate with the existing Market campaign; do not run a competing one.
3. **Close release operational evidence before considering publication.** The
   implementation is present; the missing proof is exact-artifact handling and
   owner/client acceptance, not another release framework. Benefit: lower risk of
   distributing uncertified/different bytes. Effort medium plus owner access;
   held/read-only rehearsal risk low, real promotion consequential. Verify the
   existing immutable candidate's source/archive hashes, failure/retry refusal and
   environment/secret-scope evidence without exposing credentials. Actual candidate
   certification and Forever packaged-install acceptance remain required. Keep the
   hold throughout this task; any public promotion requires separate authorization.

## Deliberately stop here

Tooltip reservation indexing lacks a measured bottleneck and stays deferred.
Category/paint changes, profile-refresh coalescing and offline fixture optimization
wait for material traces or recurring developer cost. The Cozy guide's normal-view
hover callback is avoidable but too small to prioritize without client attribution.
Large-file splitting, shared-style unification, new packages/frameworks/repositories,
process reuse, global GC tuning and deleting unique evidence are not worthwhile
on current evidence. Keep event deduplication, tokens, combat/experimental guards,
serial certification, capped caches and reusable widgets.

All new links and quoted calculations checked; report-only diff and publication
hold verified. No additional production, tests, workflows, Market contracts,
SavedVariables or release settings changed. Further modernization is justified
only by the acceptance evidence above, not by the existence of another audit item.
