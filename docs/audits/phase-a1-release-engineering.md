# Phase A1 — release engineering decisions

Audit baseline: `d06d74c89de869ef2aae7a9c0ac2ca5e44bf6164`, tree `8deae3b5a7bd8cc6a9ad13c17fb54631a579658c`, 2026-11-16.
[Baseline](phase-a1-baseline.md) · [Ranked findings](phase-a1-findings.md).
All policy changes below are proposals. `.github/release-policy.json` remains false.

## Current branches and protection

**Newly measured:** main, release/v1.3 and feature/workshop exactly match the certified SHAs/tree in the baseline report. PRs 27–29 are merged; no synchronization is needed. GitHub lists 29 branches including numerous historical feature/research/maintenance branches, the stabilization branch and synchronization branch. Branch existence is not proof they remain active; do not delete them based on names alone.

Repository metadata permits merge, squash and rebase; automatic branch deletion is false. Branch listing reports all returned branches `protected=false`. Main's detailed protection endpoint returns 403 (“Resource not accessible by integration”), so this audit cannot fully attest effective organization policy. The visible active ruleset `v3.*` covers tag creation, deletion and non-fast-forward changes, not current `v1.*` names. Environments endpoint returns an empty list. These observations need owner-side confirmation before enforcement changes.

| Model | Normal development | Stabilization/hotfix | Cost and recommendation |
|---|---|---|---|
| Protected main + short branches + explicit promotion | Small reviewed PRs; experiments remain gated | Release a certified immutable main candidate; hotfix off released tag if necessary | Default recommendation; least synchronization |
| Same plus temporary release branch | Main continues while candidate freezes | Only release blockers on temporary branch; carry fixes back once | Use when concurrent work actually requires it |
| Current long-lived main/release/Workshop | Integration across parallel histories | Repeated promotion and reverse synchronization | Preserve current refs/history, but cease treating all three as permanent development destinations after owner approval |

Use squash for ordinary short feature branches if the owner prefers a linear main; preserve existing merge history. A temporary stabilization branch may use explicit merges/cherry-picks with linked provenance, but never repeat synchronization solely because SHAs differ when trees match. Emergency fixes branch from the affected published tag, test the fix/dependencies and release candidate, then port the same fix to main. Retire branches only after owner review of unique commits and recovery needs.

## Actual workflow event matrix

**Source-confirmed:** only `.github/workflows/release.yml` exists at baseline.

| Event | Current planned channel | While hold=false publication flag | If owner later enables publication unchanged |
|---|---|---|---|
| PR opened/updated | None | No workflow | No workflow |
| Push main | alpha | Plan runs; downstream tests/build/publish skipped | Offline tests, stamp, package, GitHub prerelease and CF alpha |
| Push beta | beta | Same skip | Same pipeline, beta |
| Push stable-looking `vN.N.N` tag | release (Python validates exact format) | Same skip | Stable GitHub release/latest + CF release |
| Other branches/tags | None | No run | No run |
| Manual dispatch | Not configured | None | None |

Here “hold” means the file contains `publication_enabled=false`; the workflow starts but `plan.publish` is false. A green held run does not certify the integrated code. Full simulator/client acceptance is not part of this Actions pipeline even when publication is enabled. Current build timeout is 20 minutes, publish 30; complete offline cost and heavy-layout memory vary, so do not put the 7,377-second release-profile command into this build job.

## Publisher and package assessment

**Source-confirmed:** `tools/release.py` centralizes plan/notes/stamp/check/publish. `.pkgmeta` moves exactly seven production addons into the ZIP and excludes tests, tools, docs, assets, test-output and three development addons. `ADDONS`, `LOAD_ON_DEMAND` and `REQUIRED_DEPS` check companion contracts, including Wizard→Layouts. RELEASING's six-folder passages and workflow's “both .toc” comments are stale; actual tooling covers seven.

Versions: stable exact `vMAJOR.MINOR.PATCH`; main/beta derive next patch from reachable stable history plus channel, commit distance and short SHA. Notes use Git history and optional annotated-tag highlights. TOC version is stamped in the build, not a source version-bump commit. GitHub asset names remove leading `!!!`; internal core folder retains them. `release.json` declares flavor `forever` and interface. CurseForge receives displayName, gameVersions, releaseType alpha/beta/release, Markdown changelog. Bundled TOC dependencies are checked; no external addon relationship metadata is supplied. Optional integrations should not become hard dependencies absent runtime need.

Forever interface 16001 becomes 1.60.1. `CurseForge.game_version_id` restricts to Forever's type, but missing exact mappings fall back with a warning to a lower/newest ID. Treat this as a public metadata risk, currently dormant under the hold; require an exact mapping or recorded explicit override before future publication. No CF API credential or live upload was used in A1. GitHub release records corroborate historical alphas, but do not independently prove current CurseForge file contents or compatibility.

**Newly measured remote history:** published records include `v1.2.3-alpha.2.g7fd7be8` (November 11) and stable `v1.2.2` (November 9), with older stable/alpha records retained. The first API entries included unpublished historical drafts (`published_at=null`); these must not be counted as public releases. No v1.3 release was created by this audit. Preserve all existing release history; do not renumber old artifacts to match branch names.

### Safety already worth keeping

- Workflow default contents permission is read-only; publish alone receives contents-write and CF secret. Checkout does not persist credentials. External actions are pinned by full SHA.
- Build has no CF secret; publish downloads the checked build artifact. Artifact retention is 30 days; missing artifact is an error. No CI cache is configured.
- Per-ref concurrency uses `cancel-in-progress:false`; this is not a global release lock and can replace queued runs. It does not justify cross-channel concurrent promotion.
- CLI plan and publish enforce the hold. Invalid policy fails; missing policy intentionally enables old-branch behavior. Never remove the policy file as cleanup. The low-level `publish` helper relies on its CLI caller for this guard.
- Existing draft-state protocol records CF `uploading` before the call. Unknown outcome refuses blind retry; operator reconciliation is required. Certain refusal/connect failures can retry. Stable tag conflicts are rejected; already-published markers prevent ordinary duplicate publication. Keep these semantics.

### Gaps to address before enabling publication

| Concern | Actual severity and smallest response |
|---|---|
| Every main commit may publish alpha | Dormant under hold, high policy risk once lifted. Remove branch-push publication; use explicit promotion |
| Build verification coupled to publish | Active verification gap now; independent PR/main checks and build-only candidate path |
| Training refresh during build | Source reproducibility risk: `tools/update_training_data.sh` fetches newest upstream before packaging. Commit/pin updates before certification; fail on unintended source drift |
| Rebuild/retry identity | `publish` reuses an uploaded GitHub asset by name while CF receives local bytes. Add candidate hash binding and immutable artifact promotion, including old-draft reconciliation |
| Six-versus-seven prose | Documentation defect, not actual missing packaged Workshop; fix prose/derive inventory from ADDONS |
| Forever fallback | Metadata risk; exact mapping or explicit documented override, no guessed compatibility |
| Approvals/protection | No environment in workflow/visible list; branch protection detail inaccessible and visible v3 tag rule mismatched. Owner validates settings and configures scoped approvals |

No release-engineering change should bypass tests or loosen data integrity. Failure-recovery tests should exercise existing mocks in `tests/test_release_tools.py`, not contact public upload endpoints.

## Proposed event and promotion policy

**Proposal; expected benefits require validation.** Keep existing runner and GitHub-hosted Linux for ordinary syntax/offline selections; use the existing controlled simulator installation for relevant feature and full candidate gates. Client acceptance remains human-controlled. Hosted jobs should not need a game install, client credentials or all simulator assets. Start with conservative workers and measured memory limits; no self-hosted fleet or new repository required.

| Event/action | Tests | Build/artifact | Public publication |
|---|---|---|---|
| PR update | Syntax + conservative affected development/feature offline groups; relevant simulator evidence as needed | Optional internal ZIP, no secrets | Never |
| Merge main | Integrated offline verification; global/high-risk changes invoke documented broader gate | Optional internal versioned ZIP + source/hash manifest | Never |
| Explicit internal build dispatch at SHA | Package validation, selected checks; mark uncertified omissions | Internal expiring artifact, e.g. commit-derived dev version | Never |
| Explicit alpha promotion request | Affected feature/integration plus package/install acceptance appropriate to scope; record omissions | Freeze candidate once | Only owner-approved same-hash artifact, CF alpha/GitHub prerelease |
| Beta/RC certification request | Complete release profile, package payload audit, applicable Forever acceptance | Immutable candidate, reports/hash/provenance | Explicit approved beta promotion only |
| Stable release request and final tag | Complete certification for the exact candidate inputs, no repeat solely for docs-only evidence | Promote certified artifact; metadata must match tag/version | Explicit protected approval; stable CF/GitHub |
| Hotfix | Focused fix checks, integration and release acceptance appropriate to affected contracts; no implied waiver | New patch candidate from released line | Same explicit promotion policy |
| Rollback | Validate known compatible previous package and SavedVariables implications | Retain known-good artifact | Deliberate owner action; do not move/delete old tags or silently replace public bytes |

A tag alone should identify a version, not authorize upload. The explicit promotion request selects SHA, channel, version and artifact digest; protected environment approval is the final release action. For stable artifacts, stamp the final version before certification; if moving beta to stable changes stamped bytes, rebuild/check that metadata-only transformation and bind its final hash to the same tested production payload. Never claim differently stamped ZIPs are byte-identical. Release/high-risk full gates remain per `docs/testing.md`, not every ordinary PR. Alpha omissions must be visible and must not be called release certification.

Use immutable annotated `vX.Y.Z` stable tags. Preserve current published versions and choose the next version after reconciling published tags, not merely `release/v1.3` naming. Keep concise annotated highlights plus generated commit notes/compare links; no obligatory per-commit version bump. Use alpha/beta identifiers compatible with the current parser until a separately tested parser change is needed; do not introduce rc tags unsupported by `PRE_TAG` accidentally. Internal ZIP names can be commit-derived without public tag creation.

Recommended artifact retention: short-lived ordinary internal builds (owner selects budget, e.g. 14–30 days), certification evidence and release candidate hashes retained with release records for support/recovery. Retain failures long enough to diagnose; compact provenance in Git, large logs/images in artifacts. A download expiring is not a permanent evidence archive.

## Safe migration and decisions

1. With hold unchanged, add independent verification and build-only metadata planning. Verify held and unheld fake event matrices; separate build permission from publication permission. Publish job must not run for PRs/forks.
2. Make training inputs committed/pinned, record exact seven-addon payload/source/environment hashes, and reject changed artifacts on retry. Exercise timeout/unknown/refusal/success/resume paths in mocked release tests. Do not replay an upload whose outcome is unknown.
3. Add explicit promotion, protected environment/credential access, globally serialized public publisher and immutable version/tag checks. Disable old main/beta automatic upload triggers before any hold change. Rehearse with no credentials and mocked publisher.
4. Owner confirms current branch/tag protections, merge method, candidate evidence retention, version choice and Forever mapping policy. Native client acceptance remains outstanding. Only a separate explicit owner decision may change live publication policy.

Rollback: leave hold active throughout migration; new verification can be disabled independently. Preserve prior workflow/tool commits, drafts and artifacts. If publication is later enabled and a problem occurs, re-hold publication first, inspect recorded upload state and reconcile CF files manually. Do not blindly rerun unknown uploads, delete published history, downgrade SavedVariables or assume installing an older ZIP reverses schema migration. Runtime rollback requires compatible saved-data evidence and the existing backup/recovery paths.

A1 performed source review, read-only GitHub metadata queries, provenance/tree checks and a list-only test-plan query. No CI workflow, branch policy, tag, deployment credential, release artifact or public file was changed. The audit PR itself contains documentation only and must remain draft/unmerged for owner review.
