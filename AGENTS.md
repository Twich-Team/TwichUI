# TwichUI agent entry point

TwichUI targets **WoW: Forever, Lua 5.1**. The core folder is `!!!TwichUI/`;
single-quote it in shell commands. Start with the task, not a historical milestone.

## Efficient AI development

- Optimize for a responsive, premium, cohesive player experience and maintainable code; reuse existing primitives instead of inventing frameworks.
- Read only relevant source, contracts, and documentation sections. Avoid broad scans and planning artifacts for routine changes.
- Run the smallest useful tests while iterating; expand to affected feature/integration coverage at checkpoints and the documented full gate for release or high-risk changes.
- Add tests for meaningful behavior, safety boundaries, and realistic regressions, not test-count targets. Do not weaken assertions to pass; rerun failures only with changed inputs or a diagnostic hypothesis.
- Prefer offline verification and existing simulation. Real-client checks are owner-directed, never an automatic completion or release blocker; report native-only uncertainty honestly.
- Measure plausible performance risks with representative bounded inputs. Do not create testing infrastructure or run long benchmarks unless justified by the change.
- Review the diff, report verification and limitations concisely, and stop when acceptance criteria are met.

1. Read [shared engineering rules](docs/engineering-rules.md), then only the relevant
   sections of [feature rules](docs/dev-rules.md). These are the shared policy authorities.
2. Use [architecture and ownership](docs/architecture.md) to locate source, manifests,
   settings and contracts. Source and `.toc` manifests establish what exists.
3. Use [test selection](docs/testing.md#source-to-test-guidance) and preview the plan
   before choosing coverage. Shared or unknown changes require broader review.
4. Follow [release engineering](RELEASING.md) for candidate/promotion work.

Edit the repository, preserve user data and unrelated changes, and respect combat,
experimental and publication protections. Commit/push only when requested; never use
destructive cleanup. Keep changes within the task and label verification honestly.
[Current status](STATUS_AND_BACKLOG.md) is context, not authorization for more work.
[Product roadmap and idea bank](docs/product-roadmap.md) is optional planning context
for prioritization only; read it when needed, never treat its ideas as assigned work.
For an **explicitly owner-authorized autonomous batch only**, use
[Autonomous-Ready tasks](docs/autonomous-ready-tasks.md); Ready is eligibility,
not standing permission to implement or merge.

Development follows [protected main and short-lived PR branches](docs/git-workflow.md). Workshop and release/v1.3 are preserved historical branches, not new work targets.
