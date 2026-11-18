# TwichUI agent entry point

TwichUI targets **WoW: Forever, Lua 5.1**. The core folder is `!!!TwichUI/`;
single-quote it in shell commands. Start with the task, not a historical milestone.

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

Development follows [protected main and short-lived PR branches](docs/git-workflow.md). Workshop and release/v1.3 are preserved historical branches, not new work targets.

Development builds intended for owner testing must be delivered as downloadable
GitHub Actions artifacts. Verify source identity and archive contents, then provide
the completed run link and artifact name. A local workspace path is not delivery.
