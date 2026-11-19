# Phase A2 navigation verification

Baseline: `e046a8f20c53cea9ffa4f59ec0e76b496fea4e0c`, 2026-11-16.
Documentation-only change; production, runner, CI and release policy inputs are unchanged.

## Discovery comparison

This is an informed route replay, not a controlled cold-agent benchmark. The same
session inspected the code before writing the guide. No independent agents were
used. A temporary Python script read each route as bytes, using `git show` at the
baseline and filesystem reads after editing. Each before route read AGENTS,
CLAUDE, testing.md and groups.json; each after route read AGENTS, architecture.md,
testing.md and groups.json. Both then read the same task-specific implementation
and test files listed below. Shared rules are read separately for engineering work;
they are not included in these navigation-only routes on either side.

| Task | Files before / after | Bytes before / after | Invalid target paths |
|---|---|---|---|
| Reminders settings | 7 / 7 | 205826 / 197691 | 0 / 0 |
| Market schema-3 | 9 / 9 | 157316 / 149181 | 0 / 0 |
| AH lifecycle | 8 / 8 | 95129 / 86994 | 0 / 0 |

Reminders targets: core reminders Config, Settings pages/Reminders, test_reminders_settings.
Market targets: Workshop Bridge, BridgeValidate, BridgeSchema, test_workshop_bridge_scoped
Lua and Python modules. AH targets: core WorkshopLauncher, Workshop Window, auction/Window,
test_workshop_auction_lifecycle. All target filenames are in the architecture guide.
Both routes ran in one batched shell tool call. No task-completion latency or token
telemetry was measured. File count did not improve; fewer bytes are a consequence
of document organization, not proof of faster reasoning or fewer future tool calls.

Baseline prose had the obsolete Reminders priority and incorrect Libs casing;
these no longer occur in the primary instructions. A1's failed Prefs guess and
case-sensitive search miss were not replayed as artificial failures. Its timings
cannot be compared to this exercise. A future independent cold-session evaluation
should use identical prompts, fixed revisions and budgets, score correctness first,
and record actual tool calls, files and wall time.

## Checks performed

- Markdown relative file links in all changed instruction/navigation/testing files
  resolve. New guide source paths checked against checkout and manifests, including
  contextual Kit and scoped fixture filenames. Seven production manifests represented;
  all six companions declare LoadOnDemand; Wizard also requires Layouts.
- Shared rules preserve the previous CLAUDE engineering policy, with relative links
  adjusted and wrong library casing corrected. Feature rules remain in dev-rules.
  Tool adapters delegate to the same authorities; Cline continuity notes remain local.
- Read groups.json, test_runner selection and ci_verify selection. List-only previews:
  feature reminders: 58 tests / 120 syntax files / 1 simulator selection;
  feature market: 48 / 110 / 1;
  integration auction-preview plus workshop: 80 / 134 / 4;
  full: 255 / 479 / 10. No tests or simulators executed by these previews.
- `git diff --check` passed. Release policy remains publication_enabled=false.
  RELEASING already describes seven packages and protected solo approval; no release
  workflow or release instruction change was needed.

Automatic source selection is deferred: a reviewed ownership map, shared/unmapped
negative cases and dependency validation would be needed. Existing CI remains
unchanged. No simulator certification, live client work, deployment or publication
was performed; this change establishes navigation and documentation evidence only.
