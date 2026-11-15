# Auction House revision integration — PR #19

Follow-up to [the refinement record](refinement.md), 2026-11-15. This record
supersedes its final verification status once the comprehensive run below
completes; the earlier failed full run remains preserved as historical evidence.
PR: <https://github.com/Twich-Team/TwichUI/pull/19>. Keep it draft and unmerged.

## Integration

Source: `codex/auction-house-ux-revision`, starting at
`2c84ec570c9735a564d0bb2335b9d3f74a201b7f`, initially clean and equal to its
remote. Target: `feature/workshop` at
`572da3a04fe1a64581b3d1cd0208038c0104cfe3` (merged M1a, PR #21).
Merge commit: `e2f5766` (two parents; no rebase or history rewrite).

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

`test_simlab_smoke.py`: six tests pass, including native/Blizzard duplicate
forms, missing/altered probe, missing/duplicate clock markers, wrong native call,
addon origin, changed voice message, out-of-window errors and uncorroborated
suppressed summaries. Existing HELLO and unexpected-error controls remain.

## Verification

Verification uses a frozen checkout at `/workspace/TwichUI-reconcile-verification`;
installation/source references are read-only. Activate the documented Cloud
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
| `bash tools/mutate.sh --group market --jobs 2` | Exit 1: 213 kills, 5 timeouts; serial retry pending |
| `./tests/run.sh full --profile cloud` | Pending |

Feature dependencies include shared UI, core, crafting, Market and Item Advisor.
Existing tests cover catalog discovery/metadata stability, selection and scroll,
native categories, saved/live distinctions, Shopping source/planner behavior,
Sell denomination conversion/Max/copying/deposit precision/unknown net, Advisor
safeguards, owned-auction empty/unavailable states, disabled AH-1a and recovery.
The default full catalog retains all replays and intentional wrong controls.

## Evidence and remaining acceptance

Raw files are preserved under `/workspace/twichui-env/`: `reconcile-*.log`,
`reconcile-no-addon-voice.{stdout,stderr}`, `reconcile-{base,revised}-voice.*`,
`reconcile-timing-evidence.json` (raw log SHA256s) and `voice-controls/`.
Screenshots for the equivalent comparison are
`/workspace/wow-ui-sim-lab/artifacts/reconcile-{base,revised}.png`.
Runner reports, individual scenario logs, screenshots and modeled hit rectangles
are in the frozen checkout's ignored `test-output/` directories. The prior failed
full run and isolated comparisons remain in their original verification copies.

Still required: the complete [real-client acceptance procedure](refinement.md#real-client-acceptance-procedure--still-pending)
and [AH-1a lifecycle/recovery proof](lifecycle-proof.md), real fonts/assets,
localized/narrow/scaled input and hit testing, combat/taint/reload/coexistence,
real native read ownership/timing and precision/deposit checks. No live buying,
posting, cancellation/repost, automatic replacement, scan activation, Market
synchronization or release activation is authorized by this verification.
