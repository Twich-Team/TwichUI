# Thirteen-addon Market transport

Owner-authorized implementation, held for coordinated review. No merge,
deployment, signing or publication is authorized. Chart PR117 and temporary
codec-probe PR135 are separate and are not included.

The owner reports actual Forever 1.60.1/build71037 codec results: 26 passed,
one unsupported (zlib wrapper), zero failed; external raw Deflate and Base64
match exactly, largest output512KiB, worst native inflate1.363ms, worst measured
probe step2.842ms, sixteen separately scheduled history calls12.511ms combined.
These are owner-reported bounded-fixture results, not full transport acceptance
or a proven native allocation limit. The complete raw report was not supplied.

The layout is one shared root plus two current and four history containers in
each of A/B: **13 physical Market addons**. Current partitioning remains32;
history partitioning remains64. No pricing, variant, estimation or authentication
formula changes. The server's source generation and prepared attestation remain
unchanged. Summary transport version3 identifies compressed packaging; versions1
and2 continue to use their existing readers. Older Companions ignore the additive
capability and continue delivering supported uncompressed data.

Container TOCs execute only bounded data-literal assignments. Requested logical
streams are raw-Deflate/Base64 blocks, with at most524288 expected output bytes
per block. A native block always yields back to the existing scheduler before
another block; no new timer system or decoder library is added to the addon.
Prepared tuples still authenticate against the original source Merkle roots,
including missing-result neighbors. History still passes original digest,
semantic, count and current-projection validation before use. No decoded bytes
are executed. Prepared strings retain their existing generation lifetime;
history retains the existing single decoded-partition cache.

The Companion negotiates packaging separately, validates the complete original
generation, compresses deterministically, decodes/validates file readback, and
activates the root last. It refuses a physical source file over8MiB rather than
silently increasing the admission envelope. This source-size bound does not
guarantee client compilation time. Expected output lengths are checks, not a
caller-supplied native allocation cap: a native call cannot be interrupted.
Input is only Companion-generated, verified local data; native buffer peaks and
arbitrary malicious-stream expansion are not claimed bounded by these checks.

Migration requires WoW to be closed. Previously owned folders and exact old
roots are retained outside AddOns in `Interface/.twichui-market-legacy` only
after replacement validation/activation. Unknown files, links, foreign ownership
and conflicting recovery bytes fail closed. Interrupted work is resumable;
the owner must not remove recovery data. First installation/layout migration
requires a full game restart for addon discovery. Ordinary subsequent bank
updates preserve the existing delivery/reload behavior.

Verification commands, comparable performance results and exact coordinated
source identities are recorded in the Market companion report. Full 13-TOC
loading, native GC/frame stalls, combat and in-game lifecycle acceptance remain
unverified until an owner-directed game run; the codec probe alone proves none
of those properties.

The implementation is in draft PR136, based on prepared-reader PR131. The
required main-target verification must test their combined ancestry before any
coordinated merge is considered. The first focused development run passed15
modules in11.272s; full verification and final comparable results are recorded
with the exact paired Market source in its final report. The temporary codec
ZIP/source from PR135 are deliberately absent from this branch.

Opt-in diagnostics reuse the existing `/tui perf` capture and export. Container
load, Base64 and raw-inflate calls have separate registered scopes; the existing
Market addon-memory aggregate includes the12 containers. No new sampling timer
is introduced. Native verification can use `/tui perf start workshop 3`,
`/tui perf mark opportunities-open`, open Opportunities/select history, then
`/tui perf stop` and copy the export from `/tui perf`.
