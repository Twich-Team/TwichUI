# Prepared current reader (review candidate)

This is Stage C of the coordinated implementation of [investigation #127](https://github.com/Twich-Team/TwichUI/pull/127).
It stacks on that audit reconciled with addon main `b541c5b39f324c9d356cb3783cff67db1362787b`.
Market [#46](https://github.com/Twich-Team/TwichUI-Market/pull/46) supplies the authoritative
attestation; [#47](https://github.com/Twich-Team/TwichUI-Market/pull/47) independently validates,
prepares and publishes it. No merge, deployment or release is part of these drafts.
Chart-loading draft #117 remains separate; chart rendering and Pricing.Chart are unchanged.

## Runtime and trust

The additive installed capability prefers 16 physical current partitions, allows 32 by
changing `prepared_current_partitions` for controlled testing, and retains the original
64 historical partitions. Older Companions ignore the capability and deliver their supported
legacy format. New Companions require the actual Prepared.lua and TOC entry, not just JSON.
An absent/refused prepared capability uses fully validated legacy data; it does not obtain
the prepared performance benefit. Fresh two-bank prepared installations have 161 addon
folders (193 with 32), including the root; upgrades can retain older folders for rollback.
No automatic deletion of existing installation folders is introduced.

Summary admits the original Contract 3 manifest, receipt and canonical prepared attestation.
The latter binds generation, layout, canonical current hashes, counts and positional Merkle
roots. This is the same trusted Companion/file-installation boundary as the original unkeyed
manifest digest, **not a digital signature or protection against malicious local code**.
The native publisher independently checks the attestation against all authoritative original
current records. In game, a requested 135-character tuple is typed, reconstructed canonically,
and authenticated at its exact tree position. Missing results require authenticated adjacent
neighbors (including strict ordering/boundary checks); empty buckets are attested explicitly.
Only authenticated tuples can reach Pricing. An unrelated corrupt tuple may remain undetected
until requested; no price from it is used. Strings captured from the addon envelope are immutable;
subsequent mutable-global table replacements cannot alter a previously authenticated snapshot.

Binary lookup uses fixed offsets, portable 7-hex-digit chunks and exact 64-character variant
identities. Authentication flags use sparse 32-leaf words. There is no duplicate price table:
Pricing retains its existing 8,192 resolved-plus-pending bound. Raw loaded strings and bounded
flags remain associated with active/last-good generation; each declared physical projection is
bounded to 4 MiB and the entire prepared projection to 32 MiB. Lua cannot unload already loaded
addon globals; retained/private and client-attributed memory must be measured separately.

One Summary worker shares the existing approximately 2 ms cooperative slice with history.
Nested proof/hash coroutines yield within that budget; there is no per-price timer or polling.
Initially visible/default 12 recipes supply priority identities; later viewport changes promote
up to 512 dependency identities. Each authenticated price immediately releases just its own
Pricing reservation and invalidates its dependent recipes. Notifications remain coalesced.
Dense background demand can switch to a streaming canonical-current hash instead of repeating
many proofs; priority proofs can interrupt that hasher. Whole-part verification is also used
for public EachItem enumeration. Variants authenticates its returned range and both boundaries.
The historical JSON reader, lazy loading, daily observations and historical provenance remain
unchanged. Current requests preempt a suspended historical decoder rather than restarting it.

Cancellation drops owned queues/reservations, retains already authenticated immutable data,
and guards stale timer callbacks. Multiple owners/direct consumers retain shared work.
Combat performs no new addon loads and leaves no retry timer loop; ordinary subsequent activity
can retry. Invalid current data rejects the split generation using the existing last-good path.

## Verification at the Stage C checkpoint

```sh
python tools/test_runner.py feature market-performance --list
python tools/test_runner.py feature market-performance --jobs 2
```

14 tests passed, zero failed, no simulators, 10.081 seconds on the development host.
The new deterministic test uses byte-identical Stage A vectors for 16/32 layouts and covers
prices, exact variants, authenticated misses/empty buckets, public reader operations, lazy
history, independent completion, shared ownership, cancellation, generation replacement,
combat, mutated prices/proofs/identities, truncated payloads, cache reuse and last-good retention.
Clock times are observations, not CI thresholds. Broader combined integration, actual native
publication and 60-day before/after benchmark results belong to Stage D; this checkpoint does
not claim native WoW Forever settlement or frame-time acceptance.

Diagnostics adds prepared load/verification scopes, bounded read-only counters and raw/flag/
pending gauges. The existing expensive-memory sampling interval includes both banks of all
current/history formats; no item identities are recorded.

## Dense-workload follow-up

The first repeated integrated campaign rejected this checkpoint at the unchanged 15%
dense CPU limit: +23.33% with 16 and +20.70% with 32 at 5,000 recipes. That evidence is
retained in Market Stage D. No processing budget was raised. Dense completion now avoids
proof coroutines/searches for already fully authenticated partitions; its streaming hash
constructs canonical atoms directly instead of allocating decoded tuples and passing them
through the generic JSON encoder. Binary pivots are speculative navigation only: returned
records and both missing-result neighbors still authenticate; unrelated pivot variant bytes
need not be scanned repeatedly. An immediately returned prepared price is passed into the
existing Pricing cache handoff rather than looked up twice.

Additional deterministic checks cover typed upper boundaries (item 2147483647,
99999999999 copper and supply 9007199254740991), cancellation of enumeration, history
preemption without restart, queue capacity, modeled slice limits and eligibility expiry
while a proof is suspended. Expiry releases the reservation without publishing a stale price.
The additional boundary fixture was generated by the production `seal_split` and `prepare`
functions from fabricated tuples; it contains no live observations. Whole-part hashes count
all authenticated leaves and release their sparse flag words. Repeated final campaign
results, exact source identities and native-only limits remain in the coordinated Stage D
report; a targeted passing run alone is not the final acceptance evidence.

A lifecycle regression test also replaces/cancels a pending reader while keeping the
immutable source generation unchanged. That reproduced an idle waiting row with no
remaining price request. The calculation context now includes the existing cancellation
epoch; item completions do not change it. Header activation also drops work requested
from the previous prepared context during admission. Completed ordinary reopen paths
still reuse their caches, while cancelled work cannot masquerade as a compatible job.
