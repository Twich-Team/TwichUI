# TwichUI Workbench — Session Handoff
Date: November 3, 2026, approximately 6:52 PM MST

## Purpose and working arrangement
Perplexity is the product-design/planning and report-review partner. Codex implements in the user's local repository. The user wants focused execution, minimal repeated investigation, and few manual operational steps. It is Codex, not Claude, for this Workbench work.

Repository reported: /home/rich/TwichUI-Workbench
Host/login: rich@llm
Current repository code and fresh tests outrank this handoff. This session did not independently inspect local repository code. Implementation/test claims below come from user-pasted Codex reports. Screenshots and pasted page content supplied additional UI evidence.

## Current accepted work: Models
The user accepted Models presentation on November 3, 2026 ("looks good"). Codex subsequently reported recording acceptance in the local progress register.

Implemented/reported:
- Compact Models overview, separate /models/configure page.
- Provider cards show preferred/fallback/excluded roles, selected model, inactive state, and expandable capability details.
- Discovered model choices where supported; advanced manual identifier entry.
- Provider fallback distinct from model substitution; semantics preserved.
- Demo activity isolated from observed totals: 3 tasks, 6 attempts.
- Compact allowance-unavailable note, clearer global versus provider settings, snapshot-copy wording, readable activity labels, compact single-token observation.
- Six attempts versus five dated rows is expected: an interrupted attempt has no recorded end time; retained in totals, excluded from dated groups, with explanation.

Latest Models-only reported verification: 179 backend, 15 frontend, 40 browser, 10 visual tests; 17 screenshots inspected including 390px and enlarged text; no baselines changed.

Providers remain inactive. Quota telemetry and WB-15 planning-quality limitations remain deferred. Acceptance does not authorize activation, execution, or publication.

## Current milestone: first bounded Milestone 5 slice
Codex reported delivering:
Reviewed fixture -> durable verification request -> existing worker/fake verifier -> recorded result, with publication held.
This is fixture-only, NOT actual implementation, addon/simulator verification, real-client testing, or live delivery.

Initial M5 reported checks: 185 backend, 15 frontend, 43 browser, 10 visual tests; 13 screenshots inspected including 390px and enlarged text.

### Prerequisite screen issue and fix
Initial page buried "Open contract review" inside body text; user could not distinguish the link.
Codex reported replacing it with:
- "Contract review required" status.
- Short explanation.
- Separate primary-styled "Review candidate" link.
- Existing target and navigation-only behavior preserved.

Fix verification reported: keyboard focus/Enter navigation, zero write requests, desktop/390px/200% text screenshots without overflow; 185 backend, 15 frontend, 46 browser, 10 visual tests; no baselines changed. Physical Safari unverified.

The original candidate was already confirmed, so refreshing could not show the prerequisite state. A separate disposable unconfirmed fixture was created, preserving existing confirmed history/results. Do not reset confirmed records just for visual review.

## Latest inspected result content and OPEN ISSUE
User pasted the confirmed candidate's result page:

Controlled verification rehearsal
- Durable request goes to existing worker and deterministic fake verifier.
- Checks controlled fixture identity and behavior contract.
- No model, addon code or external service runs.
- Activation/live execution off; publication held.
- Result bound to candidate version.
- Fixture checks completed.
- Verification: passed; Attempt: completed; Publication: held.
- Passed: Candidate identity matches controlled fixture.
- Passed: Behavior claims match controlled fixture contract.
- Source: deterministic fixture; Execution activation: off; Publication permission: held.

Request version:
98702a0ea3aefe82099da813bf8f4355c06a4f3072fd8a0e05ea21f8eb5eaf04
Request ID:
6398d548-070b-4f7e-9708-458c5cb168ed

Displayed timestamps:
Saved:    2026-11-04T01:44:46.691808+00:00
Started:  2026-11-04T01:44:46.714867+00:00
Finished: 2026-11-04T01:44:46.714118+00:00

OPEN: Finished precedes Started by 749 microseconds. Perplexity produced a bounded Codex correction prompt. No resulting implementation report has been provided yet; do NOT mark this corrected.

Requested investigation/fix:
- Inspect only lifecycle timestamp capture/persistence/display.
- Establish actual lifecycle events versus differently sourced observations.
- Correct capture order or inaccurate mapping/labels as appropriate.
- Do not clamp/reorder timestamps cosmetically or silently rewrite historical audit records.
- Add focused regression test for actual cause and required final checks.
- Preserve candidate/history/results, fixture-only behavior, inactive providers, publication holds.
- Stable review instance only, no new port, provider calls, addon execution, commits, publication.
- Report cause, changes, verification, and handling of existing historical evidence.
- Stop after this correction, before next milestone.

Recommended Codex reasoning effort for timestamp correction: Medium; use current available coding model, no permanent version assumed.

## Acceptance state
- Models: user accepted.
- M5 first slice: reported implemented and fixture-tested; user saw prerequisite and confirmed-result content. Do NOT mark full M5 accepted or complete. Resolve/report timestamp discrepancy, then ask for acceptance of this bounded fixture-only slice if appropriate.
- Pasted result content clearly separates fake check success from real addon verification and publication permission.
- No real-client/addon/simulator evidence established for M5.

## Review instances and operational friction
Known URLs as last reported (availability not independently checked):
- Models: http://127.0.0.1:9387/models
- Models configure: http://127.0.0.1:9387/models/configure
- Models demo: http://127.0.0.1:9387/models?activity=demo
- Confirmed M5: http://127.0.0.1:9487/tasks/cozy-step-review/verification
- Separate unconfirmed: http://127.0.0.1:5180/tasks/cozy-step-review/verification

The user objected to repeated instances/new ports. Perplexity acknowledged overcomplicating it. User said "okay done" after a consolidation instruction, but supplied NO report establishing actual shutdown/consolidation.

Standing instruction now:
- Prefer one stable review instance, existing M5 port 9487.
- Represent states as separate fixture candidates in that instance when supported.
- Explain necessity before creating another instance/port.
- Inspect data/process ownership before any consolidation; preserve confirmed reviews/history/results.
- No blind DB copying/resetting; ask before stopping redundant processes.
- No new infrastructure/broad refactor merely for consolidation.

Instances require host/process availability; reboot survival not guaranteed. Review data reported retained.
Previously reported identity-safe stop commands (do not execute without approval/identity checks):
Models:
/home/rich/TwichUI-Workbench/.venv/bin/python /home/rich/TwichUI-Workbench/scripts/model_review.py --stop
M5:
/home/rich/TwichUI-Workbench/.venv/bin/python /home/rich/TwichUI-Workbench/.local/m5-review-stop.py

## Windows access
Run tunnel in Windows PowerShell, leave terminal open:
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9487:127.0.0.1:9487 rich@llm
Then use the confirmed M5 URL above. Match local and destination ports to avoid known host-validation confusion. Other retained ports require their own matching tunnel if still needed.

## Safety and execution rules
- Routine local implementation/tests/disposable fixtures/browser checks allowed.
- No provider activation, paid calls, local inference, live task execution, external writes, live worker cutover/deployment, commits/pushes/PRs/publication without explicit authorization.
- Preserve user work/private data/live game files/WTF/SavedVariables.
- Maintain distinct saved/acknowledged, capability/availability, activation/permission, admission, attempt outcome, verification, publication states.
- Reuse existing worker/durable-command ownership; no competing writable state or second engine.
- After two substantive failed approaches to a blocker, stop and report evidence and smallest next action.
- Focused tests then repository-required final checks. Screenshot review, automated tests, simulator and real-client tests remain separate.
- Keep prompts bounded; no optional features, dependencies, broad refactors or agent teams by default.
- Recommend model/effort with implementation prompts: current Codex coding model; Medium for routine bounded changes, High for consequential state/ownership work. No current exact version verified.

## UI direction
Warm walnut/espresso surfaces, aged bronze/gold, ivory text, restrained fantasy identity; existing TwichUI logo. Approachable language, explicit states, details secondary. Avoid generic teal/charcoal dashboards, fake percentages, intrusive prompts, unnecessary settings. Do not reopen accepted Models styling absent a concrete regression.

## Relevant local report paths (contents not independently accessed)
/home/rich/Documents/Codex/2026-11-03/files-pasted-by-the-user-implement-2/outputs/models-refinement-report.txt
/home/rich/Documents/Codex/2026-11-03/files-pasted-by-the-user-implement-2/outputs/models-presentation-report.txt
/home/rich/Documents/Codex/2026-11-03/files-pasted-by-the-user-implement-2/outputs/m5-first-slice-report.txt

## Why a new Perplexity session
User's pasted images trigger a Perplexity Max page. Likely upload allowance, not confirmed account telemetry. Do not promise a new session or deleting images resets account upload usage. Continue with plain-text reports/page content where possible.

## Immediate next action for the next assistant
Ask whether Codex has returned the timestamp-correction result; review that report if available. Do not repeat implemented work, invent a new milestone, or claim the timestamp issue is fixed. Once this bounded slice is accepted, inspect current local milestone register through a focused Codex prompt to select the next safe slice rather than guessing from old migration snapshots.
