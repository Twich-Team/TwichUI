# Auction House revision integration — PR #19

Follow-up to [the refinement record](refinement.md), 2026-11-15. This record
supersedes its final verification status. The comprehensive run below completed
and failed on a separate Workshop blocker; the earlier voice-related full
failure remains preserved as historical evidence.
PR: <https://github.com/Twich-Team/TwichUI/pull/19>. Keep it draft and unmerged.

## Integration

Source: `codex/auction-house-ux-revision`, starting at
`2c84ec570c9735a564d0bb2335b9d3f74a201b7f`, initially clean and equal to its
remote. Target: `feature/workshop` at
`572da3a04fe1a64581b3d1cd0208038c0104cfe3` (merged M1a, PR #21).
Merge commit: `e2f5766d214679f6411d70ae522900fc314d0c28` (two parents; no
rebase or history rewrite). Smoke correction and frozen full-test commit:
`cbb48c8b90d3c6949a09537c5fedad67ebe2af23`. Later changes are evidence/proposal
documents only; all 2,401 frozen tracked files still match their recorded hashes.

The sole actual conflict was `tools/mutations/workshop.py`: adjacent additions
of the AH `market.auction.*` / `market.sell.*` mutations and incoming M1a
`market.canonical.*` mutations. Retain both sets: 335 total valid patterns,
218 in Market. Restore unchanged comment separators after conflict cleanup.
No other conflict, older-file replacement or unrelated change was necessary.

The incoming dormant `PricingV1.lua`, its tests, `tests/groups.json`, pinned
`market_bridge_v1` fixtures and M1a documentation match the target byte for byte.
The existing AH runtime files match `2c84ec5` byte for byte. M0.5 specifications
and `pricing_v1` fixtures remain intact. M1a stays outside the TOCs. Local prices,
Market data formats, Advisor safeguards, lifecycle/recovery controls, defaults,
transaction gates and the approved five pages are preserved. No separate M1b
branch or PR was incorporated or edited.

## Smoke diagnosis and correction

Best-supported cause: a timing-sensitive native simulator limitation exposed by
an inconsistent smoke permit set, rather than an AH regression. Blizzard's
`Blizzard_SettingsDefinitions_Shared/Audio.lua:657–669` registers a five-second
ticker calling `C_VoiceChat.CanAccessSettings`. Forever simulator v0.1.37 has the
native binding but raises exactly:

```
C_VoiceChat.CanAccessSettings: settings access has not been supplied
```

Its documented return is a non-nil boolean; this simulator has no supplied
capability/setter. The existing delayed-error classifier already describes the
limitation, but smoke permitted only the group HELLO UTF-8 limitation.

The old full smoke advanced absolute time 15.523718139–17.523718139 and printed
the native error after tick 17.023718139. The isolated revision advanced
12.801625168–14.801625168; isolated old base advanced
18.770846734–20.770846734. Neither encountered it. These absolute GetTime values
are not portable timer deadlines: startup and native registration phases vary.

Reproduction on this machine, same simulator, no assets and six seconds in
0.05-second steps:

| Addons | Window | Voice error last preceding tick | Exit |
|---|---|---|---:|
| None (`--no-addons --no-saved-vars`) | 17.043087242–23.043087242 | 20.043087242 | 0 |
| Current target `572da3a` | 16.251609707–22.251609707 | 18.651609707 | 0 |
| Reconciled AH branch | 11.002369163–17.002369163 | 12.952369163 | 0 |

The latter two used identical smoke fixture bytes and staging commands, serially.
Loaded addon files in `572da3a` also match the old original baseline `5b6e4e9`;
the only added runtime-directory file is dormant, unlisted `PricingV1.lua`.

The native read-only probe reported a C function, `pcall=false` and the exact
missing-capability message in the no-addon reproduction as well. Simulator exit
0 alone does not establish a passing verdict.

Inspection found fresh simulator processes, serial runner execution, fresh
addon staging, `--no-saved-vars`, empty checked WTF directories, isolated run
artifacts/TMPDIR, cleared assertion-altering environment variables and the same
Cloud asset mode. The full runner runs offline checks, lab guard, then smoke;
smoke is not sharing an earlier suite's simulator process. No state leak was
observed. Host scheduling/startup phase was not independently controlled, so the
exact reason one old two-second window crossed the native deadline is uncertain;
no broad environmental or production fix is claimed.

The correction touches only the smoke fixture, verdict and its tests:

- Observe six seconds, covering a full native ticker interval rather than
  avoiding delayed failures. Retain the same frame-sized fade steps.
- Probe the actual native C binding with `pcall`, without replacing it or its
  timer. Emit capability evidence and bracket this fixture's clock advancement.
- Permit only the existing exact voice message with that evidence, inside the
  bracket, and with only the observed `AdvanceTime`/fixture-main stack plus
  optional Blizzard error-report frames. The simulator drops the Audio.lua
  callback frame; requiring it would not match the captured native error.
- Reject addon frames, other messages, missing probe/scope, errors outside the
  bracket and suppressed summaries without a prior full validated occurrence.
  Keep HELLO's existing origin checks and the strict page-construction sweep.

No generic classifier rule, production API, shim, required assertion, suite,
error log, image baseline or acceptance gate was removed or weakened. The raw
native error remains visible and disclosed. If simulator stack shape changes,
the smoke rule intentionally fails pending review.

Negative controls, using the actual corrected smoke capture:

| Verdict/input | Expected | Actual |
|---|---:|---:|
| Corrected verdict, original capture | 0 | 0 |
| Original verdict, same capture including native voice error | 1 | 1 |
| Corrected verdict, copied capture + deliberate unexpected Lua error | 1 | 1 |

In the new comprehensive run, smoke again printed both native voice error forms
(last preceding tick 14.695788007), with `native=true unavailable=true` probe
evidence. Smoke exited 0 after all checks; interaction also passed. This is a
full-run occurrence exercised by the correction, rather than an isolated retry
that happened not to cross the deadline. Overall full status is recorded below.

`test_simlab_smoke.py`: six tests pass, including native/Blizzard duplicate
forms, missing/altered probe, missing/duplicate clock markers, wrong native call,
addon origin, changed voice message, out-of-window errors and uncorroborated
suppressed summaries. Existing HELLO and unexpected-error controls remain.

## Verification

Focused verification uses `/workspace/TwichUI-reconcile-verification`; full
verification uses the clean frozen `/workspace/TwichUI-integration-full` at
`cbb48c8`. Installation/source references are read-only. Activate the documented Cloud
tooling with `source /workspace/twichui-env/activate.sh`. No game assets are
available, so screenshots establish structure only. Full Cloud success does not
satisfy the local milestone or real-client acceptance gate.

| Command | Result |
|---|---|
| `./tests/run.sh fast auction-house` | PASS: 16 offline files |
| `./tests/run.sh fast market` | PASS: 14 offline files, including M1a conformance |
| `./tests/run.sh fast item-advisor` | PASS: 2 offline files |
| `bash tools/mutate.sh --all --check` | PASS: 335/335 patterns valid |
| `SIMLAB_ASSETS=0 bash tools/simlab/run.sh smoke` | PASS: all 56 pages constructed; native voice limitation disclosed |
| `./tests/run.sh feature auction-house --profile cloud` | PASS, exit 0: 63 offline files, 167 Lua syntax checks; preview 34 launches / 4,422 checks; lifecycle proof 4 / 431 |
| `bash tools/mutate.sh --group market --jobs 2` | Exit 1: 213 kills, 5 timeouts; all five killed in isolated serial retry, exit 0 |
| `./tests/run.sh full --profile cloud` | **FAIL, exit 1**: 243 offline modules pass, 706 Lua syntax checks pass; 191 launches / 30,221 structured checks; 9/10 simulator suites pass; 6,790.094 s |

The mutation campaign overlapped the feature simulator and hit the existing
120-second cap on five history cases. Preserve that exit-1 report: it is not a
clean campaign. After all simulator work stopped, a five-ID `--jobs 1` retry
used the same tests, code and default cap. Baselines passed (history 98.8 s,
schema 3.4 s); the five mutations were killed in 91.6, 96.9, 99.2, 103.0 and
88.5 seconds. Retry: exit 0, five kills (four assertion, one runtime error),
zero survivors/invalid/timeouts/infra errors or source drift. Across both runs,
all 218 unique Market mutations were detected (213 assertion, five runtime-error
kills). This supports resource contention near the cap; no timeout increase or
arithmetic change was made. Retry JSON/log and the initial campaign log are
preserved. Comprehensive verification runs without a mutation overlap.

Feature dependencies include shared UI, core, crafting, Market and Item Advisor.
Existing tests cover catalog discovery/metadata stability, selection and scroll,
native categories, saved/live distinctions, Shopping source/planner behavior,
Sell denomination conversion/Max/copying/deposit precision/unknown net, Advisor
safeguards, owned-auction empty/unavailable states, disabled AH-1a and recovery.
The default full catalog retains all replays and intentional wrong controls.

## Comprehensive result and unresolved blocker

The full command completed once, without cancellation, on frozen `cbb48c8`.
There were no offline failures or timeouts. The exact overall exit is **1**;
this is not complete green regression evidence.

| Suite | Launches | Structured checks | Exit | Result |
|---|---:|---:|---:|---|
| lab-guard | 0 | 0 | 0 | PASS |
| smoke | 2 | 0 | 0 | PASS |
| interact | 4 | 244 | 0 | PASS |
| diagnose | 6 | 101 | 0 | PASS |
| auctionproof | 4 | 431 | 0 | PASS |
| auctionpreview | 34 | 4422 | 0 | PASS |
| workshop | 38 | 19997 | 1 | **FAIL** |
| testlab | 9 | 229 | 0 | PASS |
| settings | 58 | 1029 | 0 | PASS |
| reminders | 36 | 3768 | 0 | PASS |

Workshop completed all 38 launches. In `overview`, `empty`, and `notice`, the
same three checks failed (nine unexpected failed assertions in total):

1. `no answer followed the bag change: the tab may have changed`: expected true,
   actual false; the guild tab was not marked uncertain.
2. `its stock is not collected from any more: back to the bank-only list`:
   the list still included guild stock instead of the expected bank-only list.
3. `and the note says why`: expected true, actual false; the uncertainty note
   was absent.

The other 34 capture launches passed those checks. All 37 common pre-pose vectors
had 523 entries, but their results differed, so the required replay comparison
also correctly failed. The intentional wrong-expectation control and screenshot
checks still passed. This is not an unclassified voice error and is not waived.

Best-supported diagnosis is an existing fixture timing boundary, still requiring
confirmation: `Bank.lua` ignores a bag change when `Now() - guild.items < B.PAIR`,
with `B.PAIR = 1.0`. After the guild answer, the fixture advances 0.3 seconds,
changes the tab with 0.1 seconds of settling, then advances 0.6 seconds before
firing `BAG_UPDATE_DELAYED`. That is exactly one second, although its comment
claims more than a second. A startup/manual-clock floating-point phase can put
that subtraction on either side of the strict boundary. The raw run did not
record that actual subtraction, so the precise mechanism is not claimed proven.
Bank code, this Workshop fixture and its verdict are byte-identical to original
baseline `5b6e4e9`; no bank implementation was changed by reconciliation.

Per the subsequent verification-policy instruction, no new test-infrastructure
change, assertion relaxation, timeout change or suppression was made for this
blocker. The full run was not repeated. A separate narrow investigation/correction
must establish the boundary explicitly and retain all three assertions and replay
controls before claiming a clean full result. The draft PR remains blocked on
this full-regression failure as well as real-client acceptance.

Measured runtime and proposed future policy are in the separate
[verification policy proposal](../../testing-policy-proposal.md). Full suite
costs, native phase proxies, CPU sampling limits and safe optimization options
are reported there; no performance infrastructure changes are implemented.


## Evidence and remaining acceptance

Raw files are preserved under `/workspace/twichui-env/`: `reconcile-*.log`,
`reconcile-no-addon-voice.{stdout,stderr}`, `reconcile-{base,revised}-voice.*`,
`reconcile-timing-evidence.json` (raw log SHA256s) and `voice-controls/`.
Screenshots for the equivalent comparison are
`/workspace/wow-ui-sim-lab/artifacts/reconcile-{base,revised}.png`.
Runner reports, individual scenario logs, screenshots and modeled hit rectangles
are preserved in both verification checkouts' ignored `test-output/` directories.
The compact [integration evidence](integration-evidence.json) records report/log
hashes, counts, timing attribution and selected screenshot hashes. The prior failed
full run and isolated comparisons remain in their original verification copies.

Still required: the complete [real-client acceptance procedure](refinement.md#real-client-acceptance-procedure--still-pending)
and [AH-1a lifecycle/recovery proof](lifecycle-proof.md), real fonts/assets,
localized/narrow/scaled input and hit testing, combat/taint/reload/coexistence,
real native read ownership/timing and precision/deposit checks. No live buying,
posting, cancellation/repost, automatic replacement, scan activation, Market
synchronization or release activation is authorized by this verification.
