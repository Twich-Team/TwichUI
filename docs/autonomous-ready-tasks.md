# TwichUI — Autonomous-Ready Development Tasks

**Status:** Proposed ready-task register, incorporating eight owner decisions (November 21, 2026). This document is a planning specification, **not standing authorization to implement, merge, deploy, or release**. A task becomes authorized only when the owner selects it explicitly or launches an autonomous batch with a stated scope and limit. Read [the product roadmap](product-roadmap.md) for original wording and [AGENTS.md](../AGENTS.md) for the engineering policy.

## Choosing and executing a batch

1. Only choose items with **Ready** status here **whose dependencies are satisfied**. Verification-only or blocked entries are not implementation tasks. Respect priority, risk, exclusions and the owner's batch size; do not promote raw ideas or ambiguous candidates.
2. First inspect current `main`, open PRs and relevant code. If the issue is gone, in progress, or the work needs a product decision beyond this mini-spec, **skip it and report why**; never duplicate work.
3. Prefer small independent changes with clear player-visible benefit. **One task per branch/draft PR.** Use at most two independent workers if the owner permits subagents. Never work on conflicting code paths simultaneously.
4. Verification is proportional: smallest focused unit/syntax tests while editing; relevant feature or targeted simulator checks at the checkpoint when useful. No default full suite, mutation campaign, new framework or mandatory game session for these ordinary polish tasks. Preserve negative controls and record what was not verified.
5. Protect saved data, existing user preferences, combat restrictions, security and native game action boundaries. A failed reproduction warrants a concise investigation, not speculative redesign. Do not merge, push to `main`, publish or release.
6. Task statuses change only on evidence. **Ready** = can be selected if authorized; **Active** = someone is already implementing; **In review** = draft PR exists; **Done** = merged and verified to the stated extent; **Blocked** = missing product decision or dependency.

**Task isolation:** W21/W22 both edit `TwichUI_Workshop/ViewShopping.lua`; W11/W20 edit `TwichUI_Workshop/ViewCrafting.lua`. Run each conflict group sequentially. P01 and F12 may both touch Magic Inventory and should not overlap if they share files. P05 must not expand into a global style refactor. Do not select Workshop pricing, Market validation, AH status or Opportunities tasks while the A01/A02 stack (#97/#99/#100/#102) is active. W11 additionally waits for that stack to integrate. Ready means eligible, not authorized.

## Ready queue

Each Ready task is a **mini-specification**, not a guarantee the issue still exists. Validate against current source and open PRs. A dependent task is ineligible until its condition is met.

| Order | ID | Task | Risk / effort | Ownership | Conflict / dependency |
|---|---|---|---|---|---|
| 1 | **P01** | Bank transfer progress-text readability | Low / S | `!!!TwichUI/inventory/Window.lua` | Inventory |
| 2 | **P04** | Target/World marker toggle overlap | Low / S | `TwichUI_Settings/pages/Markers.lua` | Markers |
| 3 | **W22** | Shopping footer icons/counts alignment | Low / S | `TwichUI_Workshop/ViewShopping.lua` | Shopping |
| 4 | **P05** | Premium restocking dialog materials; existing layout | Low–medium / S–M | `!!!TwichUI/modules/RestockPrompt.lua` | Restock/style |
| 5 | **F12** (F29) | Missing carried Waylaid crates in item/rule picker | Medium / S–M | `!!!TwichUI/inventory/Picker.lua`, `Items.lua` | Inventory |
| 6 | **W21** | Shopping “Needed for” detail | Medium / S–M | `TwichUI_Workshop/ViewShopping.lua` | After W22 |
| 7 | **P03** (A03) | Advisory targeted-test selection usability | Medium / S–M | `docs/testing.md`, existing runner | Test tooling |
| 8 | **W20** | Click queued count to enter exact quantity; keep +/- | Low / S–M | `TwichUI_Workshop/ViewCrafting.lua` | Crafting / W11 sequential |
| 9 | **W16** | Fix existing In bags view to exclude equipped-only items | Medium / S–M | `AdvisorData.lua`, `ViewAdvisor.lua`, `Observe.lua` | Advisor |
| 10 | **W11** | Shift-click queued item to search TwichUI AH | Medium / S–M | Crafting queue + AH Browse | After A01/A02 integration; with W20 sequential |

### P01 — Magic Inventory **bank transfer** progress text

- **Problem:** Specifically the bank transfer progress indicator's confirmed-moves text is obscured by its fill; other progress indicators are out of scope.
- **Desired result:** The text remains comfortably legible at 0%, intermediate and 100% progress, with different confirmed/total counts, at supported UI scales.
- **Where to start:** `!!!TwichUI/inventory/Window.lua` (`f.bankProgress.fill`, `f.bankProgress.text`, `DrawBank`), `!!!TwichUI/inventory/Run.lua` (`BankProgress`). The fill and text already exist; do not invent another progress system.
- **Acceptance:** Foreground/contrast/layering remains correct while the fill grows or shrinks; text does not clip or get covered; confirmed-only progress, Stop, result totals and transfer logic are unchanged; no animation work is added to the transfer path.
- **Verification:** Focused Magic Inventory UI/bank tests and a relevant simulated state or layout capture if available. No real bank transactions; use synthetic progress values.
- **Boundaries:** Only bank-review `f.bankProgress` presentation. No change to transfer authorization, progress calculation, data model, or bank automation.

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

### W12 — Withdrawn: Craft Queue search

The original note was clarified. **Do not implement a Craft Queue search.** The owner wants direct entry of an exact quantity; see W20. Retain this entry only to prevent agents reviving the mistaken requirement.

### W20 — Direct Craft Queue quantity entry

- **Owner intent:** Clicking a queue item's displayed quantity lets the player type an exact count (e.g., 20) and press Enter instead of clicking + twenty times. **Keep the existing + and - controls.**
- **Source:** `TwichUI_Workshop/ViewCrafting.lua` (`MakeQueueRow`, count and +/-), `Session.SetCrafts`, `Queue.SetCrafts`. Reuse existing input components.
- **Acceptance:** The editor starts with the current count; accepts integers 1 through `W.MAX_CRAFTS`; Enter saves, Escape cancels; invalid/blank/out-of-range input cannot alter the queue. Saved quantity, row, queue totals and material requirements refresh correctly. +/- and selection still work.
- **Verification:** Focused crafting tests for 1→20, bounds, invalid values, save/cancel, persistence and +/-; a targeted UI simulation if useful.
- **Bounds:** No queue search, auto-crafting, automatic completion work or persistence rewrite. The original optional right-click menu (Remove/Open recipe) is separate follow-up work, not a condition for this task. Do not parallelize with W11.

### W16 — Correct existing Item Advisor "In bags" filter

- **Owner intent:** **In bags** currently shows items the player is wearing. This is a bug, **not a request for an Equipped filter**.
- **Source:** `TwichUI_Workshop/AdvisorData.lua` (`D.Catalog`, bag-source flag and filter, displayed quantities), `ViewAdvisor.lua`, `Observe.lua` (`O.BagCount`). Source already marks actual bag-slot discoveries, but its count uses `C_Item.GetItemCount`; investigate whether that can include equipped-only items.
- **Acceptance:** Equipped-only gear does not appear in **In bags**; a matching item physically in bags still appears with the correct bag-only count, including when another copy is equipped. Preserve Tracked / All known items, selections, advice and transaction safeguards. Handle missing item metadata gracefully.
- **Verification:** Focused Advisor tests with equipped-only, bag-only, both, multiple bag stacks and unknown item data. Prove the old false-positive case.
- **Bounds:** Do not add an Equipped tab/filter or change Market pricing and unrelated inventory systems.

### P05 — Premium styling of existing restock dialog

**In review** · [Draft PR #111](https://github.com/Twich-Team/TwichUI/pull/111)

- **Owner decision:** Keep the dialog's existing layout and workflow. Apply TwichUI's premium espresso/walnut leather, subtle bronze, ivory text, legible controls and restrained depth.
- **Where to start:** `!!!TwichUI/modules/RestockPrompt.lua`, `docs/settings-design-system.md`, existing `R.CraftLook`/`R.FrameLook`. The dialog already has a configurable `MenuStyle`; respect saved choices.
- **Acceptance:** Default look matches approved Settings/Workshop craftsmanship; items, quantities, prices, Purchase/Cancel and disclosures retain their arrangement, reachability, visibility, contrast and text fit at scaled sizes. User-selected look, Esc/Cancel and purchase/spending protections still work.
- **Verification:** Existing restock UI tests, a focused synthetic multi-item/long-name preview and relevant layout capture if supported.
- **Boundaries:** Presentation only: no new dialogs, transaction changes or global style abstraction. If already correct on current code, close with evidence instead of inventing a redesign.

### F12 — Show carried Waylaid crates in Magic Inventory item/rule picker (F29)

**In review** · [Draft PR #110](https://github.com/Twich-Team/TwichUI/pull/110)

- **Owner decision:** The primary issue is missing Waylaid crates in the item/rule picker. **Junk marking is separate and not approved by this task.**
- **Where to start:** `!!!TwichUI/inventory/Picker.lua` (`Gather`, `P.Draw`), `Items.lua` (bag facts/late metadata), `TwichUI_Settings/pages/MagicInventory.lua` (picker launch and editor integration).
- **Acceptance:** A Waylaid crate actually present in a bag can be seen, searched, selected and retained in the rule/item picker without affecting ordinary item visibility. Handle pending item names and unknown icon/name safely; a bag-only picker need not enumerate crates not carried by the player.
- **Verification:** Focused synthetic bag/picker tests with a source-grounded crate identity, an ordinary item, missing metadata, empty bag and saved selection.
- **Boundaries:** This is **visibility/selection only**. Do not bypass quest-item, binding, locked-item, Never transfer or other transfer/junk protections. If a supported item ID/fixture or the missing path cannot be established, report Blocked; never hard-code guessed crate identifiers.

### P03 — Make choosing targeted tests straightforward

**In review** · [Draft PR #109](https://github.com/Twich-Team/TwichUI/pull/109)

- **Owner decision:** Difficulty is **selecting the appropriate tests**, not running tests or increasing their number.
- **Where to start:** `docs/testing.md`, `tests/groups.json`, `tools/test_runner.py` (`plan`, `--list`), `tests/run.sh`. Reuse existing group globs and documented boundaries.
- **Desired result:** An opt-in, read-only, **no-test-execution recommendation** for one or more changed repo-relative paths, listing likely focused group(s), preview commands and why they apply. CLI syntax may follow existing runner conventions. If a small, deterministic CLI addition proves too complex, make a concrete command-selection guide instead.
- **Acceptance:** Single-file, multiple-file, known shared path and unknown/unmapped path all produce understandable choices. Unknown/shared risk explicitly says to inspect consumers or escalate; never silently claim coverage is complete. Existing `fast/feature/integration/full/release`, CI, `--list` and simulator selection are unchanged.
- **Verification:** A handful of deterministic runner/help tests and documentation examples; no unrelated full suite.
- **Boundaries:** No new dependency engine, auto-execution, CI gate changes, or source-to-test registry parallel to `tests/groups.json`.

### W11 — Shift-click a queued craft to search TwichUI Auction House

- **Owner decision:** Shift-click means **search the queued recipe's resulting item** in TwichUI AH, **not** paste a chat link.
- **Where to start:** `TwichUI_Workshop/ViewCrafting.lua` (`MakeQueueRow`), queued recipe `outItem`, `TwichUI_Workshop/auction/ViewBrowse.lua` (`A.OpenBrowse(item, qty, opt)`) and `auction/Window.lua` (`A.Live`, `A.IsShown`). A chat-link Shift-click already exists on the output icon outside an AH context.
- **Acceptance:** In a supported, available AH context, Shift-click searches/opens the matching output item via the existing Browse adapter; it never searches ingredients by mistake. Unknown output or unavailable AH produces clear no-action guidance. Preserve normal selection, chat-link behavior outside the AH, refusal handling and explicit buy/post controls.
- **Verification:** Focused queue/AH tests for live vs preview/closed states, missing output identity and refused searches. No live purchase/post actions.
- **Dependencies and stop:** **Wait until A01/A02 PRs integrate.** If the Crafting queue cannot be interacted with while integrated AH owns the window, stop and request an interaction-design decision—do not alter AH host/suspension lifecycle just to force this shortcut.

## Not ready: decisions or dependencies to resolve

| Source | Why not ready | Owner decision needed |
|---|---|---|
| **P02** party ping replay | `pins/Ping.lua` already plays the receipt sound and `pins/PingMap.lua` already draws received pings and replays sound/animation from the recent list after changing maps; `docs/map-pings.md` documents this | **Verify/close, not new implementation.** Reproduce the owner-reported failure before reopening; preserve mute, anti-spam and reduced-motion behavior |
| **F12/F29** junk treatment | The owner clarified that missing picker visibility is the current request; junk marking was another idea | Defer junk-marking behavior and any protected-item exception to a separate owner decision |
| **W24** multi-craft aggregate timer | **Presentation preference resolved:** owner wants both a movable TwichUI total-progress bar and a native cast-bar enhancement option. Native integration and reliable completed-craft evidence remain unverified | Technical discovery first: confirm Forever permits safe, non-protected native cast-bar presentation; offer separate-bar fallback when unavailable. No automatic crafting or unreliable queue credit; not Autonomous-Ready |
| **W25** Add to queue from Blizzard profession frame | Requires native frame placement/selection semantics and load-on-demand behavior | Decide one craft vs currently selected quantity and verify Forever UI attachment safely |
| **W10** merchant offer for queued reagents | Queue Shopping plan and vendor Restock transactions are separate consent models | Decide whether an itemized confirm-to-buy offer is enough or a separately approved opt-in auto-buy is intended; never purchase on open by default |
| **W26** Travel/Shopping craftable ingredient → recipe | Multiple known make recipes may produce same item | Choose gesture and tie handling; reuse existing profession OpenRecipe path, no auto-craft |
| **W13** automatic craft decrement | **Owner decision resolved:** count verified completed crafts and enable by default **once technically safe**. `TwichUI_Workshop/Progress.lua` holds `P.auto=false` pending Forever evidence about recipe/spell IDs, UNIT_SPELLCAST_SUCCEEDED GUIDs and multi-craft event counts | **Blocked on evidence, not product preference:** verify with existing `crafting.progress.events` Test Lab probe/Forever API before changing the default; no speculative bag-count credits, unsafe decrement or removal. Manual Done/Undo remains. This prerequisite does not make real-client testing a general release gate. |
| **F19** remove last name from chat | Could refer to realm suffix or character surname/nameplate | Which exact displayed text should be hidden and in which chat contexts? |
| **W05 / A05 / W04** Market/AH status controls | Current A01/A02 performance work touches Market/Workshop plumbing | Re-evaluate against merged performance result first; no parallel work now |
| **A04** neutral auction fee | Pricing correctness is important but current Market/Opportunities stack is active | Recheck after A01/A02 merges; separate small economic fix with targeted tests |
| **F04 / F09 / reminder glow** | Fishing Stage 2 already merged; Loot victory PR #101 and Reminder glow PR #91 are active | Verify PR state and select only separately approved follow-ups |
| **UX02** shared Reminders artwork picker and per-rule icons | Batch 6 shared foundation and 20 approved existing-art additions are implemented for review; custom rule fields/builders remain unimplemented | Review [contract](design/shared-artwork-picker.md), [curated inventory](design/shared-artwork-inventory.md) and [consumer specs](design/shared-artwork-rule-integrations.md). Scope is settings rule list/editor identity only. Follow-ups below remain awaiting review, not Ready |
| **All larger product concepts** | Scope and interactions are not yet defined | Keep original ideas in roadmap; discuss one product slice at a time |

### UX02 specified follow-ups awaiting owner review

**Status:** UX02-A/B foundation work is implemented for review in owner-authorized
Batch 6. UX02-C/D remain Specified — awaiting owner review and separate execution
authorization; neither is Ready. No rule schema/editor work is included in Batch 6.
The [shared contract](design/shared-artwork-picker.md) and approved 20-candidate
slice are implemented; the remaining rule-reference compatibility/version policy
and consumer editor placement still need review. No future task is auto-selected.

**UX02-A — Extract the approved chooser with Reminders parity (implemented for review).**
- Scope: shared core catalog/reference drawing + one Settings-only chooser;
  thin Reminder adapter continues `Gallery.Choose`/`SetDisplayMany`. Preserve
  all existing 79 entries, IDs, crops, categories, search, source tabs, thumbnails,
  preview, Apply/Cancel, Esc/close, companion placement and display modes.
- Acceptance: caller-owned acceptance/persistence; isolated copied candidate and
  owner/profile generation checks; automatic staging supported for callers that
  opt in; cancel/replacement/pagehide/profile/settings-close writes nothing;
  exact-once cleanup and no stale callbacks/pool growth. Reminders works as before,
  including Settings load-on-demand and Reminders disabled. No rule schema/editor
  changes. No new generic UI/provider framework.
- Verification: existing Gallery/Reminders settings and relevant load-order tests,
  targeted session/atomicity regressions and selected picker normal/narrow poses
  if available. Dependencies: owner-reviewed contract; coordinate any overlapping
  Reminders work at execution time. Keep glow behavior outside scope.

**UX02-B — Add only owner-approved existing catalog artwork (20 implemented for review).**
- Scope: additive metadata for the approved subset of the [28 candidates](design/shared-artwork-inventory.md);
  20 are recommended first, eight are conditional. No new art or unrelated rebuild.
- Acceptance: verified paths and variants, stable noncolliding IDs, curated categories
  and search synonyms, no duplicate alias targets; baseline order/IDs unchanged.
  Register new art resolution and Reminder icon allowlist mappings consistently;
  never turn the whole texture directory/registry into catalog entries.
- Verification: bounded file/ID/metadata checks and small-size/light/dark review;
  existing Gallery rendering/search tests and useful picker capture. Dependencies:
  owner approval of rows/IDs and UX02-A's reviewed reference/resolution boundary.

**UX02-C — Loot Rules identification artwork.**
- Scope: Choose icon in the settings editor; custom identity only in list/header.
  Proposed `rule.artwork` remains subject to schema/version-policy review.
- Acceptance: preserve automatic Need/Greed/Pass defaults and explicit action words
  even for incomplete rules; picker Apply uses the existing immediate-save model;
  automatic reset/cancel differ correctly; checked fresh references survive
  supported mutation/duplication/profile/backup paths. Unknown valid IDs fall back
  visibly without rewrite; no rule matching/roll action or transport changes.
- Verification: focused loot config/settings, duplication/profile, malformed and
  unknown-ref tests; prove different artwork gives identical loot decisions.
  Dependencies: approved schema/compatibility and UX02-A; UX02-B only for new art.

**UX02-D — Magic Inventory rule identification artwork.**
- Scope: rules list and builder summary/Rule review identity, not runtime transfer
  review or drag ghosts. Preserve existing item/category automatic precedence.
- Acceptance: picker Apply changes only private draft; existing Save/Cancel,
  failed Save and pagehide-retains-draft/profile-apply-discards-draft semantics
  remain; duplication makes independent references; cleaner retains approved
  field/valid unknown IDs; fallback/mask cleanup is visible and nonmutating.
  Matching, destinations, recipients, priorities and transfers are unchanged.
- Verification: focused rules/settings/recipient/profile tests, independent draft
  and saved duplication, fallback/mask and behavior-invariance checks; useful
  narrow/scaled builder pose when implemented. Dependencies: approved field/version
  policy and UX02-A; UX02-B only for new art. Run sequentially with overlapping
  Inventory editor work, and preserve existing settings-sharing exclusions.

## Owner decisions — November 21, 2026

- **P01:** bank progress bar specifically.
- **P05:** preserve restock dialog layout; apply approved premium style.
- **P02:** sound on receipt, plus replay when a recent ping is selected (including map navigation). Source already implements the expected paths; verify before fixing.
- **P03:** test group **selection** is confusing; give advisory selection guidance, not more tests.
- **W11:** Shift-click queues search the resulting item in TwichUI AH.
- **F12/F29:** crate visibility in the item/rule picker first; junk support separate.
- **W13:** auto-decrement verified crafts **on by default once event correctness is established**; current automatic counting remains disabled pending client evidence.
- **W16 (superseded):** fix the existing In bags filter; no new Equipped filter.

## Candidate first autonomous batch

**P01 + P04 + W22**. Three independently owned presentation defects; P01 is specifically the bank transfer progress bar. None requires changes to pricing/Market, persisted behavior, protected actions or a major design decision. If owner authorization is granted, two agents can implement distinct tasks at once and a coordinator can review/submit one draft PR per item. The batch ends after those three or fewer if one is blocked/obsolete.

**Do not automatically select the next items after this batch.** Future owner-authorized batches may select W20 direct quantity entry, W16 In bags filtering, W21, or other eligible work; W12 search is withdrawn. W11 must await A01/A02 integration. The idea bank is not an execution queue.

## Maintenance

After the owner chooses a batch, record its authorization *in the batch prompt or corresponding GitHub issue*, not as a standing instruction in this file. When a PR is opened, move the associated task to **In review**, link the PR and avoid duplicate selection. When merged, mark **Done** with the merged commit and keep its original note in [the roadmap](product-roadmap.md). Revise assumptions and checks only when concrete evidence changes them; do not spin up a task-orchestration service or rewrite the idea bank.
