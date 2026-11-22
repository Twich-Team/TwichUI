# TwichUI — Autonomous-Ready Development Tasks

**Status:** Proposed ready-task register. This document is a planning specification, **not standing authorization to implement, merge, deploy, or release**. A task becomes authorized only when the owner selects it explicitly or launches an autonomous batch with a stated scope and limit. Read [the product roadmap](product-roadmap.md) for original wording and [AGENTS.md](../AGENTS.md) for the engineering policy.

## Choosing and executing a batch

1. Only choose items with **Ready** status here. Respect priority, risk, exclusions and the owner's batch size; do not promote raw ideas or ambiguous candidates.
2. First inspect current `main`, open PRs and relevant code. If the issue is gone, in progress, or the work needs a product decision beyond this mini-spec, **skip it and report why**; never duplicate work.
3. Prefer small independent changes with clear player-visible benefit. **One task per branch/draft PR.** Use at most two independent workers if the owner permits subagents. Never work on conflicting code paths simultaneously.
4. Verification is proportional: smallest focused unit/syntax tests while editing; relevant feature or targeted simulator checks at the checkpoint when useful. No default full suite, mutation campaign, new framework or mandatory game session for these ordinary polish tasks. Preserve negative controls and record what was not verified.
5. Protect saved data, existing user preferences, combat restrictions, security and native game action boundaries. A failed reproduction warrants a concise investigation, not speculative redesign. Do not merge, push to `main`, publish or release.
6. Task statuses change only on evidence. **Ready** = can be selected if authorized; **Active** = someone is already implementing; **In review** = draft PR exists; **Done** = merged and verified to the stated extent; **Blocked** = missing product decision or dependency.

**Task isolation:** W21 and W22 both primarily edit `TwichUI_Workshop/ViewShopping.lua` — run sequentially, not in parallel. W12 and W20 both edit `TwichUI_Workshop/ViewCrafting.lua` — run sequentially. Do not select any Workshop pricing, Market validation, Auction House Market status or Opportunities tasks while the A01/A02 PR stack (#97/#99/#100/#102) is active. Items labelled Ready here are *candidates*, not priorities overriding an explicitly requested task.

## Ready queue

| Order | ID | Task | Risk / effort | Principal ownership | Conflict group |
|---|---|---|---|---|---|
| 1 | **P01** | Make Magic Inventory transfer progress text consistently readable | Low / S | `!!!TwichUI/inventory/Window.lua` | Inventory |
| 2 | **P04** | Fix Target/World marker settings toggle overlap | Low / S | `TwichUI_Settings/pages/Markers.lua` | Markers |
| 3 | **W22** | Align Shopping source-count art and labels | Low / S | `TwichUI_Workshop/ViewShopping.lua` | Shopping |
| 4 | **W21** | Give a selected Shopping material a proper “Needed for” section | Medium / S–M | `TwichUI_Workshop/ViewShopping.lua` | Shopping |
| 5 | **W12** | Add local Craft Queue search/filter | Low / S–M | `TwichUI_Workshop/ViewCrafting.lua` | Crafting |
| 6 | **W20** | Direct Craft Queue quantity entry and right-click actions | Medium / M | `TwichUI_Workshop/ViewCrafting.lua` | Crafting |
| 7 | **W16** | Show equipped items in Item Advisor without treating them as bag stock | Medium / M | `TwichUI_Workshop/AdvisorData.lua`, `ViewAdvisor.lua` | Advisor |

### P01 — Magic Inventory transfer progress text

- **Problem:** Bank transfer progress text is obscured by the filling progress bar.
- **Desired result:** The text remains comfortably legible at 0%, intermediate and 100% progress, with different confirmed/total counts, at supported UI scales.
- **Where to start:** `!!!TwichUI/inventory/Window.lua` (`f.bankProgress.fill`, `f.bankProgress.text`, `DrawBank`), `!!!TwichUI/inventory/Run.lua` (`BankProgress`). The fill and text already exist; do not invent another progress system.
- **Acceptance:** Foreground/contrast/layering remains correct while the fill grows or shrinks; text does not clip or get covered; confirmed-only progress, Stop, result totals and transfer logic are unchanged; no animation work is added to the transfer path.
- **Verification:** Focused Magic Inventory UI/bank tests and a relevant simulated state or layout capture if available. No real bank transactions; use synthetic progress values.
- **Boundaries:** Visual presentation only. No change to transfer authorization, data model, or bank automation.

### P04 — Target and World marker toggle overlap

- **Problem:** Controls in Target markers / World markers settings visually overlap.
- **Desired result:** Every switch/label and its hit target is readable and separately operable at supported settings sizes and scales.
- **Where to start:** `TwichUI_Settings/pages/Markers.lua`, Settings Kit row layout and existing marker settings tests. Determine whether the overlap occurs in a specific nested-row combination; avoid globally resizing shared controls to fix one page.
- **Acceptance:** No overlap or misdirected clicks across both tabs; all switches retain their saved values, enable/disable conditions and help text; no change to marker placement or binding semantics.
- **Verification:** Relevant `tests/test_markers.lua`, settings/UI tests and a focused simulated layout at normal and narrow widths if feasible.
- **Boundaries:** Layout-only correction; no new marker behavior.

### W22 — Align Shopping footer counters

- **Problem:** Vendor, Auction, Craft and Collect pictograms are not vertically aligned with their count and text in the footer.
- **Desired result:** Four consistent icon/count/label groups with the same baseline and optical centering at normal and scaled fonts.
- **Where to start:** `TwichUI_Workshop/ViewShopping.lua`, `BuildBar` (art, numeric count, label anchors).
- **Acceptance:** Art and text align in every group including 0, single- and multi-digit counts; no clipping against the spend-summary separator or changes to planner totals.
- **Verification:** Focused Workshop window/Shopping tests, targeted simulator Shopping pose or screenshot inspection when available.
- **Boundaries:** Do not touch shopping calculations, source selection, or Market pricing.

### W21 — Shopping “Needed for” destination section

- **Problem:** The recipe/output that requires a selected material is buried in small inline text at the bottom of the details pane.
- **Desired result:** A clearly separated, premium-styled “Needed for” section in the selected material detail, listing recipe/product names and item icons **where the existing record supplies a verified item ID/icon**; fall back to text rather than guess missing identities.
- **Where to start:** `TwichUI_Workshop/ViewShopping.lua` (`d.usedFor`, `RenderDetail`); existing `S.NeededFor` and plan/recipe data. Reuse a pooled row or existing item icon components if needed.
- **Acceptance:** Correct for one or several outputs, long names, missing known icon, missing recipe identity, empty/collect-only state and switching selected material; clear section hierarchy without clipping or making the page materially taller; no new synchronous full-catalog scan during every repaint.
- **Verification:** Focused Shopping and Workshop-window tests; relevant simulator pose with multiple output consumers if already supported.
- **Boundaries:** Presentation and bounded data adaptation only; do not modify planner economics or invent recipe relationships. **Do not parallelize with W22.**

### W12 — Craft Queue search

- **Problem:** The Crafting page offers recipe search but no search when viewing the player's current queue.
- **Desired result:** A small search input on the **Craft queue** tab filtering queued entries by known recipe name (case-insensitive), without changing saved queue membership or craft counts. Recipe browsing retains its own current search.
- **Where to start:** `TwichUI_Workshop/ViewCrafting.lua` (`BuildLeft`, `ShowLeft`, `Render`); existing `S.QueueRows` and `UI.Search`.
- **Acceptance:** Empty query shows the complete queue, unmatched query explains that the list is filtered (not empty), switching tabs retains sensible focus/selection, and clearing search restores rows and scroll behavior; queue changes still affect the complete queue; no new SavedVariables.
- **Verification:** Focused crafting/window tests and existing UI search/filter scenarios if applicable.
- **Boundaries:** Read-only UI filter; no global recipe lookup or new search engine. **Do not parallelize with W20.**

### W20 — Craft Queue direct quantity and context menu

- **Problem:** Queued craft count can only be adjusted with +/- controls; Remove/Open recipe exist in the details panel but not beside the relevant row.
- **Desired result:** Clicking the displayed count opens a compact numeric editor. Right-clicking a queue row opens a standard TwichUI context menu offering **Open recipe** and **Remove from queue** (reuse existing actions). No action fires merely from opening the menu.
- **Where to start:** `TwichUI_Workshop/ViewCrafting.lua` (`MakeQueueRow`, detail actions); `Session.SetCrafts`, `Session.OpenRecipe`, `Session.Remove`, `Queue.SetCrafts` and existing popover/menu patterns.
- **Acceptance:** Accept whole numbers from 1 through existing `W.MAX_CRAFTS`, reject invalid/out-of-range input without altering data, support Esc/cancel, preserve select/hover behavior, keep +/- and existing detail buttons working, and do not perform any protected gameplay action without its existing owner-controlled path. Menu dismisses on outside click/close.
- **Verification:** Focused queue/unit/window tests; one targeted menu/input UI simulation when supported.
- **Boundaries:** No automatic craft completion or alternate persistence. **Do not parallelize with W12.**

### W16 — Equipped items in Item Advisor

- **Problem:** Advisor discovers items from bags, tracked identities, known recipes and local Market, but not the character's currently equipped gear.
- **Desired result:** Equipped items are discoverable in the Advisor's **All known items** view and visibly identified as equipped. Continue to distinguish equipped from bag copies; do not count equipped copies as sellable bag stock or automatically recommend posting/vendoring an equipped item.
- **Where to start:** `TwichUI_Workshop/AdvisorData.lua` (`D.Catalog`, source flags), `ViewAdvisor.lua` (row metadata/search/filter/presentation). Use only reliable equipped-slot and item-link APIs supported by Forever. Reuse existing item identity and variant guards.
- **Acceptance:** Equipped-only and simultaneously equipped+bag items are represented without duplicate catalog identities or incorrect counts; missing item information is represented as unknown; leaving/changing equipment updates the catalog at a bounded rate; no change to automatic advice or transaction eligibility.
- **Verification:** Focused Advisor/catalog tests with synthetic equipment slots, lifecycle changes and safety cases; no real-game item manipulation.
- **Boundaries:** Read-only discovery and UI attribution, no automatic gear actions and no broad Advisor redesign. If identifying equipped variants safely is not supported, document the limit and stop rather than guessing.

## Not ready: decisions or dependencies to resolve

| Source | Why not ready | Owner decision needed |
|---|---|---|
| **P05** restock dialog styling | It already has a configurable frame style; “not styled” does not identify the approved target | Use existing layout with premium materials, or redesign structure? Which reference window? |
| **P02** party ping replay | Timing and audience of replay are unclear; duplicating sounds/animations could spam | Which actions should replay locally, and should it occur on receipt, on map selection, or both? |
| **P03 / A03** individual test execution | Existing runner has direct-test and group support; requested friction isn't specified | What about individual-test execution is inconvenient? |
| **W11** “shut click” queue link at AH | “Shift-click” is probable but link target uncertain | Shift-click to search the selected item in TwichUI AH, link it in chat, or both? |
| **F12 / F29** Waylaid crates | Missing item discovery and desired junk treatment are distinct issues | Where are crates missing, and should junk marking be an explicit rule? |
| **W13** auto-remove crafted quantities | Manual Done/Undo already exists; client event attribution can be ambiguous | Should auto-credit only verified self-crafted output be opt-in, and how should partial craft batches behave? |
| **F19** remove last name from chat | Could refer to realm suffix or character surname/nameplate | Which exact displayed text should be hidden and in which chat contexts? |
| **W05 / A05 / W04** Market/AH status controls | Current A01/A02 performance work touches Market/Workshop plumbing | Re-evaluate against merged performance result first; no parallel work now |
| **A04** neutral auction fee | Pricing correctness is important but current Market/Opportunities stack is active | Recheck after A01/A02 merges; separate small economic fix with targeted tests |
| **F04 / F09 / reminder glow** | Fishing Stage 2 already merged; Loot victory PR #101 and Reminder glow PR #91 are active | Verify PR state and select only separately approved follow-ups |
| **All larger product concepts** | Scope and interactions are not yet defined | Keep original ideas in roadmap; discuss one product slice at a time |

## Candidate first autonomous batch

**P01 + P04 + W22**. Three independently owned presentation defects; none requires changes to pricing/Market, persisted behavior, protected actions or a major design decision. If owner authorization is granted, two agents can implement distinct tasks at once and a coordinator can review/submit one draft PR per item. The batch ends after those three or fewer if one is blocked/obsolete.

**Do not automatically select the next items after this batch.** When the owner has reviewed results, a new bounded batch may pick W21, W12/W20 (sequentially), or W16. The idea bank is not an execution queue.

## Maintenance

After the owner chooses a batch, record its authorization *in the batch prompt or corresponding GitHub issue*, not as a standing instruction in this file. When a PR is opened, move the associated task to **In review**, link the PR and avoid duplicate selection. When merged, mark **Done** with the merged commit and keep its original note in [the roadmap](product-roadmap.md). Revise assumptions and checks only when concrete evidence changes them; do not spin up a task-orchestration service or rewrite the idea bank.
