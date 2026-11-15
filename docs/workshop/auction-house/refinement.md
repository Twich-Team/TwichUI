# Auction House refinement

Task branch: `codex/auction-house-ux-revision`, based on verified
`feature/workshop` `8c1ffad9fb08e91d95c6d921e9e3b4543fe05b0c`.
No transactions, automatic queries, takeover or desktop synchronization.

## Checkpoints

1. Fix Browse/Market catalog ownership, metadata updates, cancellation and diagnostics.
2. Clarify saved/live search and native category hierarchy.
3. Clarify Shopping sources with existing artwork and concise controls.
4. Refine Sell competition, money inputs, stack quantity and financial summary.
5. Refine My Auctions states and Market presentation.
6. Inspect simulator captures, run regression/mutation/performance verification,
   publish a draft PR to `feature/workshop`, retain client gates.

## Loading diagnosis and implementation

Both page stamps included an ever-increasing metadata counter. Browse also
counted unrelated metadata and bag/native events. Discovery reads item metadata;
late responses changed that stamp while a job was running. The previous fix
let the job finish, but the next render immediately discovered the stale stamp
and cleared/rebuilt all rows. Market explicitly scheduled that next render.
Sustained metadata could therefore finish and rediscover indefinitely. Existing
tests stopped their storm at completion and did not check continued stability.
This reproduces a defect consistent with the client report; the specific client
trace remains unrecorded and requires follow-up Diagnostics.

Metadata now queues deduplicated identities, patches only changed information,
and adjusts filter membership without rediscovery. Full candidate membership
includes filtered-out items. Completed catalog identities are reused by local
filter projections; filter changes during discovery wait for that job, then
project the latest controls. Cooperative merge sorting and the 20,000-item bound
remain. Genuine backing-store/generation changes invalidate; fresh read facades
from `Prices.Market` do not. Refresh retains rows until replacement, except when
the actual market changes. Selection/top identity/offset are restored. Hidden,
superseded and timed-out jobs are explicitly canceled and stale callbacks cannot
adopt results. Shared Strategy subscriptions are visible-only and coexist with
Workshop/Shopping observers.

Diagnostics exposes bounded discovery/projection/metadata/patch/paint/invalidation
counters, terminal counts, active jobs and longest slice through the existing
Auction House gauges. No unbounded logging, data writes or metadata request loop.

Unit regression: 6,000 items on each page; sustained duplicate and unrelated
metadata before and after completion; repeated bag events; late filtered names;
selection/top identity/offset; filter changes during discovery; generation
refresh; interleaved page switching and abandoned timers. Existing callback
failure, source failure, timeout, cap, arithmetic and stale-session tests remain.

## Reference and verification limits

Only the pasted request was attached. The five original approved mockups and
real-client captures are absent from both attachments and this repository.
The existing shell and integration.md fidelity ledger are available references;
no direct image comparison with missing attachments can be claimed.

Current Forever source was fetched read-only on its `forever` branch; the
simulator separately reads pinned `ca8368f2` / 1.60.1.70532 objects. No reference
source, simulator binary/source, proprietary game assets, PNG baseline, third
party addon or real SavedVariables is edited.

The environment was initially the separate TwichUI-Market checkout. The target
addon was cloned independently. Lua 5.1/bitop/rsync are extracted from authenticated
Debian packages into a workspace-only runtime. The existing simulator setup
verifies the pinned v0.1.37 release and ICU/ALSA hashes. Elevated execution is
needed for nested Bubblewrap; a workspace launcher adds an empty tmpfs `/mnt`
parent before the original `/mnt/c` mask because this host lacks that mountpoint.
All original read-only binds, isolated writable state and no-network namespace
are retained. These are setup files outside the repository, not shipped code.

Evidence to date: baseline fast Auction House 12/12; loading fast 13/13,
including the new sustained-pressure test; no-assets smoke passes both launches
and 56 page constructions. Feature/full results will be recorded at checkpoints.
Cloud captures are structural only; client fonts/assets/input and actual runtime
auction behavior require the unchanged local/client acceptance gates.

The independent before/after replay against the original Git revision fails on
both pages at the first post-completion metadata delivery; the revised code keeps
6,000 results through 50 continued deliveries on each page. Completion callback
exceptions (including row patches after coroutine completion) now have a terminal
error boundary and an explicit regression case. A retained selection is never
injected into a different catalog as an extra item; only explicit cross-page
item focus can add a missing identity.

First broad feature attempt: 58 offline files pass and the four lifecycle proof
launches pass. The preview catalog was not accepted: extra report files created
during capture correctly failed its status guard. Its unchanged verdict additionally
caught an obsolete zero-observer expectation (Browse now owns one) and the extra
selected identity described above. Both are corrected; the exact one-observer
bound still detects leaked Shopping listeners. All existing 109 assertions per
pose, replay, wrong control and image checks remain. Verification now runs on a
frozen source copy, so independent work cannot change its repository status.

Two targeted catalog mutations are killed by assertions, without invalids,
survivors, timeouts or infrastructure errors. A broad 200-mutation market run was
interrupted after 118 kills to defer its full repetition until Sell arithmetic is
integrated. This is partial evidence, not a 200/200 score.

### Loading checkpoint accepted in Cloud

`feature auction-house --profile cloud`: PASS, 58 offline files, 31 preview
launches / 3,379 structured assertions, four unchanged lifecycle-proof launches /
431 assertions, 1,113.532 s. Both Git index trees were exactly
`fd472c9d946c73baab434306c3de93a036453fe0` before the report-only update.
Every original pose/assertion, replay, deliberate wrong control and PNG check
ran with a stable repository guard. Report:
`TwichUI-checkpoint1/test-output/verification/feature-auction-house-vviyj47g/report.json`.
This is simulator/unit evidence, not real-client or full local visual acceptance.
