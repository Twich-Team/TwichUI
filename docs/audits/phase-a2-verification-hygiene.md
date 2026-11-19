# Phase A2 — verification cost and repository hygiene

2026-11-16. Baseline: `cdd873a951ebc034b2fac5ad05e556bfd710926c`, the latest main commit
with a successful `verify` check at preparation; separate
`engineering/verification-cost-hygiene` worktree. Newer main `95ee710` had CI
still running. It merges PR #35 (Market report/measurement tooling only); that
work and ongoing Market testing remain untouched.
Report only; `publication_enabled=false`. No simulator, full certification,
Market measurement, production change or asset deletion was performed.

## Evidence and current costs

**Source-inspected/new inventory:** Git blob sizes and identities at the baseline,
runner plan inspection, test/tool dependencies and documentation links.
**Previously measured:** all execution times below, reused from the
[verification audit](../testing-verification-audit.md), its
[measurement record](../evidence/verification-optimization/results.json), and
[historical performance report](../testing-performance.md).
The [A1 findings](phase-a1-findings.md) already established the investigation boundaries.
No new unit-tested, simulator-tested, screenshot-reviewed or real-client-tested
claim accompanies this report. Existing evidence is sufficient; another native
sample would repeat the completed phase-attribution investigation.

| Cost | Evidence and practical meaning |
|---|---|
| Whole verification | M1.5 Cloud: 2,446.279 s, 247 modules, 192 launches. Later L3: 5,701.768 s, 251 modules, 198 launches on different source. Neither is a current-main benchmark or local certification. |
| Workshop repeated work | M1.5: 890.723 s, 38 launches/37 PNGs. Each pose reruns common behavior, calculations and frame advancement in a fresh process. Those repeats include reproducibility checks. |
| Native startup | Representative ten-launch serial sample: 291.859 s native total, including 98.525 s bootstrap (33.8%; median 9.377 s). Not all of this can safely be removed. |
| Work after startup | Same sample: 127.299 s to a post-check render diagnostic, 22.758 s after it, 43.277 s without that boundary. Fixture work, actual-expression calculations, rendering/encoding and teardown are coupled; these are interval proxies, not isolated CPU attribution. |
| Setup and verdict | Workshop fresh staging median 0.309 s; reused staging 0.023 s; entire fixture-file catalog generation 0.352 s. Selected Workshop verdict 4.074 s, including two PNG decodes and all controls. All catalogs together spent 21.941 s outside native intervals. |
| Slow offline work | Instrumented/contended sample: wizard 107.625 s / 4,142.8 MiB peak child, history2 91.019 s, publish 73.252 s, market-scale 70.910 s. Earlier M1.5 observations were 39.251/30.331/34.680/21.051 s respectively. Costs vary strongly with source/host contention. |
| Offline aggregate | Integrated-base acceptance: 250 modules in 910.072 s, overlapping other validation. Current-main discovery is 255 modules; no new aggregate timing. |
| Screenshot handling | Same-input decoder improvement already landed: 2.035292 → 1.776474 s median (12.7%). Native PNG encoding is not separately timed. Separate captures can differ in pixels even serially; retain structural checks and real-client appearance review. |

Current plan inspection through [the existing runner](../../tools/test_runner.py)
and [groups](../../tests/groups.json): development Workshop Settings selects
12 modules, nine source syntax files, zero launches; feature selects 102 modules
and `design craft wrong` (three launches). Focused AH selects 71 modules and 18
launches; broad AH selects the same offline scope and 45 launches: **27 avoided
launches**, with intentionally narrower pose coverage. Earlier counts of 11/101
Workshop Settings modules describe older source. The last recorded default
inventory is 197 launches/183 PNGs; Settings is discovered dynamically, so this
is not a newly executed current-main count.

## What already works; what remains uncertain

[Current policy](../testing.md) already avoids full certification for ordinary
feature work. No-argument execution discovers all offline tests independently
of groups. Integration unions tests/syntax and merges simulator selections;
full catalogs dominate filtered duplicates. Use one integration invocation for
cross-feature changes, and one release invocation when candidate certification
is due: release includes full, so full immediately before it duplicates work.
Do not rerun unchanged failures without a diagnostic hypothesis. Source/fixture
changes invalidate reused results; a report from another commit is context,
not proof that the current candidate passed.

Offline defaults to two workers (maximum four); large layout heaps stay serial.
Each module gets a fresh process and temporary directory; teardown cleans that
temporary state and timeout cleanup kills descendants. Python failures run once
and retain complete output. Artwork generators already rebuild once per test
class where applicable; do not introduce a mutable shared client/cache.

Simulator staging/cache reuse and faster decoding already exist. Catalogs are
serial by default; opt-in two-lane scheduling isolates roots, home, WTF, fixtures,
cache, logs and locks. Admission requires four quota CPUs and 8 GiB available;
it is not a memory reservation. The existing representative pair improved
319.913 → 249.833 s (**70.080 s, 21.9%**) while individual catalogs slowed.
Peak sampled native launch RSS was 1.790 GiB; a follow-up two-worker pipeline
sampled 2.834 GiB. Sampling is not an exact heap peak. Keep serial certification;
no full-suite or game-assets speedup follows from this pair.

Repeated initialization/calculation is real, but its fixture-only fraction is
unknown. Timing `Lab.Check` misses argument evaluation. No validated native Lua
host clock/reset contract exists in this evidence. Process reuse, screenshot
batching, cached expected/actual results and fewer replay checks are therefore
poor next investments. The old 1,878.73 s Workshop pre-render trace is already
investigated, not a reason to repeat an unbounded profile.

## Tracked-output inventory and dependencies

New measurement using `git ls-tree -rl HEAD`: 2,478 files, **292,525,344 bytes**
of logical tracked payload. `test-output/`: **606 files / 54,133,698 bytes**
(54.13 decimal MB, 51.63 MiB; 18.5%). Of these, 553 PNGs occupy 52,817,948 bytes;
20 JSON files 111,584 bytes; 31 Lua files plus one TOC 1,203,006 bytes; one text
file 1,160 bytes. The copied Lua/TOC are historical baseline source, not runtime
addons. Git history identifies style commits `98e0373` and `81f789f` as provenance.

| Historical output family | Files | Bytes |
|---|---:|---:|
| `settings-second-pass/` | 52 | 20,498,717 |
| `craft-comparison-final/`, `craft-comparison-pass1/`, `craft-review/` | 224 | 12,882,706 |
| Four `reminders-components-*` directories | 175 | 13,234,391 |
| Other art inspection/calibration/polish outputs | 155 | 7,517,884 |

Output contains 340 distinct Git blobs totaling 36,957,973 bytes: **17,175,725
bytes of repeated checkout payload**. This is not additional Git object-store
saving: Git already shares identical blobs. `settings-second-pass/baseline/`
alone is 32 copied source files / 1,203,006 bytes; its screenshots are 18 files /
19,290,945 bytes. Preserve baseline revision/diff provenance before replacing
those copies with a manifest.

Dependency review of tests, tools, workflows and packaging found **no test that
consumes the 606 historical files as input**. Runner/workflow tests create their
own temporary `test-output` state; that path is still required. Art tools write
inspection previews there. Current simulator verdicts consume newly generated
run directories, not these historical captures. This is a source-inspection
finding, not a deletion experiment or test pass after removal.

Documentation does depend on them: 40 distinct existing tracked output targets
are linked from [Settings modernization](../settings-modernization.md) (four),
[second-pass review](../settings-second-pass.md) (18), and
[Reminders implementation](../reminders-revision/implementation.md) (18).
Other prose/backtick references also need migration review. Keep those evidence
links working or replace them with selected durable review images before any
untracking. A blanket removal is not ready. Historical failures/before-images
cannot be faithfully regenerated from today's source; archive their exact bytes.
Current art previews can be recreated from sources/tools; fresh simulator output
can be recreated only with the recorded runtime, source and fixtures, and need
not be pixel-identical to historical captures.

[Ignore rules](../../.gitignore) already exclude new `test-output/` files,
including nested benchmark output; they cannot untrack existing files and forced
adds can bypass them. [Packaging](../../.pkgmeta) excludes output, docs, assets
and tools already: **no runtime ZIP saving** follows from this cleanup.
A future ordinary removal commit could reduce checked-out payload by at most
54.13 MB, less retained evidence; full-history clones still contain old blobs.
Shallow/single-revision checkouts could benefit, but compressed transfer/disk
savings are unmeasured. Current CI uses `fetch-depth: 0`. No history rewrite or
LFS migration is justified.

## Other large data

- `docs/`: 169 files / 65,778,481 bytes. Reminders revision material alone is
  29,962,331 bytes. Three identical images also in `docs/reminders-style-references/`
  duplicate **4,498,988 bytes**. Consolidating references could save that checkout
  payload; retain the approved images and fix every caller first. Large mockups
  include `docs/workshop/workshop-overview-mockup.png` (2,726,881 bytes) and
  `docs/test-lab/lab-mockup.png` (2,025,892 bytes). Size alone does not make them disposable.
- `assets/`: 161 files / 118,597,199 bytes, largely source artwork. One exact
  duplicate pair is `reminder-art-custom-source.png` and `settings-icons-6-source.png`
  (609,600 bytes each). Distinct generator contracts may need both paths; leave
  them until a separate caller-aware change. Sources plus generated runtime TGAs
  are intentional: artwork tests rebuild and compare shipped bytes.
- `tests/fixtures/`: 56 files / 707,229 bytes, no identical Git blobs; no identical
  blobs anywhere within tracked `tests/`. Similar scenario structures are not
  proven redundant fixtures. Keep deterministic/reference/negative inputs,
  generated catalogs and runtime media in place.

## Recommended order — separate implementation tasks

1. **Use the existing selection/report workflow consistently.** Avoid unrelated
   catalogs and duplicate full/release or overlapping group invocations. Use
   `--list`, explicit integration consumer groups and documented risk triggers.
   Measurable opportunity: 27 fewer launches for focused AH; Workshop Settings
   uses three rather than the last recorded 197 defaults. No equivalent-coverage
   wall saving is claimed. Effort small, risk underselection; verify plans against
   actual callers and shared/unmapped negative cases. A conservative suggestion
   map can follow in the existing runner, with manual fallback. Reverse by
   selecting broader existing groups; do not narrow the independent full gate.
2. **Archive future raw evidence, then migrate historical output in a normal PR.**
   Extend the existing Actions artifact mechanism to verification reports/logs
   (including failures), PNGs and source/fixture/runtime manifests; retain on
   failure too. Keep compact conclusions and selected linked review images in
   Git. Agree retention/access first: the existing internal-candidate artifact's
   30-day retention is not durable historical evidence. Verify downloads/hashes,
   all references, fresh generation and absence of historical test inputs before
   untracking an explicit reviewed list. Upper bound 54.13 MB checkout saving,
   including 17.18 MB repeated payload; no history/ZIP saving. Effort medium,
   risk expired evidence links; reverse by reverting the normal removal commit.
   Then consider the separate 4.50 MB duplicated documentation images.
3. **Use existing two-catalog workers selectively on quiet capable hosts.**
   Saves scheduling time, not CPU: the measured representative saving is 70.080 s.
   No new scheduler/framework needed. Effort small, risk contention or misleading
   comparisons; verify the same selected checks, replay/negative failures, source
   identity and isolated artifacts under existing resource guards. Reverse with
   `--sim-jobs 1`; leave certification serial and avoid concurrent Market work.
4. **Only then profile one slow offline fixture boundary.** Start with layout
   wizard/mock-client construction using existing per-module `--measure` evidence.
   Its ~4 GiB heap and 39–108 s historical times justify a bounded follow-up;
   fixture-only indexing or allocation reduction is a hypothesis with **unknown
   savings**. Effort medium, risk leaked state or hidden production recomputation.
   Verify unchanged assertions, seeds, production calls, fresh-process behavior
   and comparable serial CPU/RSS before accepting any optimization. Revert the
   isolated fixture change. Leave history2/market-scale work to the Market campaign.

## Verification and boundaries

Report links and named affected paths checked locally; inventory arithmetic and
profile counts checked against Git/current runner plans. Publication policy
remains false. No production Lua, test behavior, workflow or tracked asset changes.
Do not remove replay, wrong-expectation controls, failure reports, source-integrity
checks, artwork parity tests, serial heavy-layout isolation or real-client gates.
PR #35/Market acceptance, runtime media and release authorization remain outside
this campaign. Stop here; implementation needs a separate task.
