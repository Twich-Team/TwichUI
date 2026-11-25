# TwichUI — Product Roadmap & Idea Bank

**Planning snapshot:** November 21, 2026. **Status:** Living planning register, not a commitment to implement everything. 57 original notes preserved below (5 polish, 23 Workshop, 29 feature ideas), plus audit-derived recommendations. Statuses are based on a source/PR review and can change as branches merge; they are not a full in-game verification.

## Owner-authorized Batch 12 — November 23, 2026

**In review:** [Batch 12 draft PR #146](https://github.com/Twich-Team/TwichUI/pull/146). No merge/release authorization. [Combined verification](workshop/batch12-verification.md). Original notes below
are retained; these outcomes supersede earlier candidate labels for this batch.

| ID | Status for review | Outcome and remaining limit |
|---|---|---|
| W27 | Implemented, including W27 follow-up | [Item-quality audit](workshop/batch12-quality.md): actual material/item names use verified game quality across Crafting materials, Shopping, Compact Travel, Advisor, Strategy, Ledger and AH lists; recipe/actions/categories and quantity/price/status colors remain separate. Follow-up covers Opportunities through separate presentation hunks; #117 history/pricing changes still apply cleanly. |
| W10 | Implemented quote fallback; purchases Blocked | [Live merchant quote](workshop/batch12-vendor-assistance.md), current ShoppingPlan + live listings, bundle/partial stock/money disclosures, no spending. Native limited-stock and transaction sequencing evidence remains missing. Explicit confirmation policy is resolved by Batch 12; no auto-buy authorized. |
| F13 | Investigated; runtime Deferred | [Implementation-ready specification](design/batch12-leave-me-alone.md); Fishing #143 remains open and changes QuietScreen ownership/state. No competing runtime edits. |
| F18 | Investigated; markers Blocked | [Position evidence finding and owner test](design/batch12-party-death-markers.md): party APIs exist but death-time freshness/corpse semantics are unverified. No misleading pins or Party Wipe work. |
| W13 | Implemented diagnostic improvements; automatic credit Blocked | [Five-scenario probe workflow](workshop/batch12-craft-evidence.md); registration, redacted argument shapes, bounded timelines and explicit truncation. Manual Done/Undo unchanged, `Progress.auto=false`. |

### W27 — Workshop item-quality coloring

Purpose: actual item names consistently communicate the game's established
quality on dark Workshop surfaces. Audit Overview, Opportunities, Advisor,
Craft Queue/materials, Shopping, Compact, Gold Ledger and AH Browse/Owned/Sell/
Shopping/Market; distinguish recipe names, action words and category labels.
Acceptance: poor/common/uncommon/rare/epic and other supported qualities come
from verified metadata; missing/pending quality stays readable neutral; delayed
metadata refreshes; pooled rows and selection changes reset; quantities, prices,
sources and status labels keep their semantic colors in normal/narrow layouts.
No changes to pricing, rarity, recommendations, ordering, ownership or tooltips.
Follow-up presentation edits cover Opportunities; the actual #117 history/chart hunks remain unchanged and apply cleanly.

F09 Loot Received Cards is **Verified Existing (owner-confirmed)**; no new receipt
implementation is selected. F22 remains a **separate major initiative**, Dispel
Indicator Studio [PR #139](https://github.com/Twich-Team/TwichUI/pull/139), outside
Batch 12. #143, #117, #98, #91 and #139 remain untouched.

## Target Portrait Decorations — November 24, 2026

Owner-requested modernization implemented for review: supplied Boss, Elite and Rare
portrait frames become the default style of the existing target artwork feature.
Legacy Dragons retains its configuration and feature switch; player class artwork
is unaffected. [Architecture, profile compatibility and focused native checks](target-art.md).
No merge or release is authorized; native verification remains owner-directed.

## Product North Star

**Premium, cohesive, responsive, dependable WoW: Forever experience.** TwichUI should feel like a crafted game interface, not a pile of utilities. For developers and AI agents, favor clear subsystem ownership, safe data contracts, small reversible changes, proportional offline tests and concise reviewable PRs. Keep real-game verification **owner-directed** and **nonblocking** for release decisions.

**Source of truth:** This document tracks proposed priorities and owner-selected work, not the implementation status of every file. Consult `STATUS_AND_BACKLOG.md` and the relevant feature docs for technical handoffs, and actual source/PRs for current code. Recheck dated implementation labels when planning a task; no item independently authorizes code changes.

## Rules for using this roadmap

1. **Ideas are not promises or authorization.** An item enters active work only after the owner selects it. Preserve experiments and open questions as such.
2. **Status is not checkbox state.** An original note may already be partially or fully implemented; verify before creating another implementation.
3. **Fix quality before expanding surface area.** Prioritize measured slow paths, player-facing defects, economic correctness, then related workflow simplification.
4. **Test proportionately.** Focused unit/regression tests during development; affected subsystem integration at milestones; full offline certification at release. Native acceptance is optional and at the owner's discretion, with unverified client behavior clearly labeled.
5. **Stop at the acceptance criteria.** Avoid unrelated refactors, new test frameworks, large evidence dumps, blanket benchmark campaigns and speculative performance work.
6. **One scoped item per implementation PR.** Ordinary work requires the owner to select an item. For an explicitly authorized autonomous batch, an agent may select up to the owner's stated limit from the separate [Autonomous-Ready task register](autonomous-ready-tasks.md). Ready status alone never grants permission to implement or merge anything.

### Autonomous batch task selection

[Autonomous-Ready tasks](autonomous-ready-tasks.md) contain actionable mini-specifications, initial priorities, source entry points, acceptance criteria, proportional verification and file-overlap constraints. They are *eligible for an owner-authorized batch*, not already assigned. The source inventory below remains complete and unchanged; proposals needing product decisions stay in discovery. Before implementation, check current `main`, open PRs and actual behavior; skip a task if superseded or conflicting.

### Proposed disposition labels

- **Active:** already selected and being worked on.
- **Fix candidate:** observed UI/behavior defect, validate and repair.
- **Refinement / UX candidate:** existing capability that should be polished before expanded.
- **Candidate:** attractive option; needs impact/effort decision.
- **Discovery:** needs design questions or technical feasibility before scheduling.
- **In progress:** existing active branch/PR, not a new blank-slate feature.
- **Implemented — verify/close:** code exists; visually or behaviorally check if useful, then archive the note.

## Proposed six-stage roadmap

| Stage | Focus | Entry / exit criteria | Representative items |
|---|---|---|---|
| **1. Stabilization & performance** | Make the core and Workshop predictably responsive, with sensible offline tests | Measured before/after results; no unacceptable synchronous work; existing correctness preserved | A01, A02, A03, A07, P03, W19 |
| **2. Correctness & trust** | Reliable prices, data provenance, Ledger and recovery | No invented economic facts; known conditional bugs covered; old data preserved | A04, A05, A06, saved-data recovery |
| **3. Premium polish quick wins** | Clearer screens, alignment, better empty/loading states and shared materials | Visible improvements with low regression risk, targeted review | P01, P04, P05, W04, W05, W21, W22, F12/F29 |
| **4. Workshop workflow refinements** | Move smoothly from Opportunity → Craft/Buy → Shop → Sell → Ledger | First verify existing planner; add only missing connections and meaningful usability improvements | W01–W03, W06–W13, W16, W20 |
| **5. Gameplay QoL & integrations** | Contextual, quiet, player-controlled extras, including finishing existing branches | Opt-in/privacy/compatibility understood, scoped feature by feature | P02, W14, W23, F02, F04, F07–F09, F11, F13, F16, F18, F22–F23, F27 |
| **6. Longer-term discovery** | Large systems or undefined ideas | Short feasibility/spec decisions before scheduling implementation | F01, F03, F05–F06, F10, F14, F20–F21, F24–F26, F28, W03, W15 |

These stages indicate *priority buckets*, not a serial schedule. Engineering standards, targeted testing, visual cohesion and performance are cross-cutting. A small Stage 3 fix can happen before an expensive Stage 1 investigation is complete if the owner chooses.

## Product UX discovery — quality-of-life settings

### UX01 — Make the Quality of life page easier to scan

- **Status:** **Owner-approved Option A implemented for review in Autonomous Batch 9.** [Design, inventory and implementation notes](design/qol-settings-redesign.md) retain the approved 13-row/four-group layout and all 22 settings. No further UX01 task is auto-selected.
- **Owner observation (screenshot, November 22, 2026):** The Quality of life settings page has become a long scroll of large feature cards. The interface is intimidating, finding a specific convenience takes too much scrolling, and the explanations are far too wordy.
- **Current reference:** `TwichUI_Settings/pages/QoL.lua` builds a sequence of `K.Card` sections (accept summons/resurrections, battleground release, duel handling, group invites, Quick Keybind, Group Finder zones, error handling, quest/herb/ore sparkles). The screenshot shows full example previews, explanatory paragraphs, “Rules”/“Good to know” text and further actions competing for space inside the first two cards. The current overview counts eleven switches, but the Batch 8 source audit finds 12 cards, 13 independent switches and 22 persisted controls; both error switches were omitted from that overview count. Preserve every secondary and conditional setting.
- **Desired player experience:** An approachable, compact, easy-to-scan index of conveniences, with short plain-English names, recognisable icons, at-a-glance on/off status, and low-friction navigation. Keep common actions easy to reach and put long descriptions, warnings, samples and advanced conditions behind deliberate detail/expand actions. Allow a player to find one feature quickly without reading every previous card.
- **Design exploration (not an approved layout):** Compare a compact categorized card/list view with a two-pane list + selected-feature details, or another equally cohesive design. Consider a persistent local search or category chips *only if they improve discovery without duplicating Settings' global search*. A feature detail can retain existing preview, rule options and contextual guidance, without displaying them all for every feature simultaneously.
- **Visual direction:** Preserve the approved restrained espresso/walnut leather, aged-bronze borders, readable ivory typography and illustrated accents. Avoid giant cards, dense dashboard chrome, flat modern styling, extra modal layers and ornamental artwork that reduces scanability.
- **Functional constraints:** Preserve all existing controls, saved defaults, Leatrix compatibility warnings, sample previews, conditional configuration, tooltip/help access, combat/lifecycle behavior and disabled/prerequisite states. Retain keyboard and different UI-scale accessibility. Do not change feature semantics or create a new general Settings framework.
- **Acceptance:** A player can locate any QoL feature from the overview without scrolling past several expanded explanations; most feature rows can be scanned by title + one-line purpose + current state; details reveal complete controls on demand; no controls become unreachable; visual consistency is verified in normal and narrow window widths.
- **Next action:** Review the Batch 9 implementation and its focused verification/player checklist. Global search, inline details, existing previews and profile/reset semantics remain in scope; new features and additional redesigns require separate authorization.
- **Scope boundary:** Do **not** implement this as part of unrelated autonomous polish batches. The UX model needs owner input; do not assume the preferred layout.

## Shared artwork picker — new owner idea (November 22, 2026)

### UX02 — Reuse the Reminders image picker across TwichUI rule builders

- **Status:** Shared foundation **merged in PR #128**; both rule consumers **implemented for review in owner-authorized Batch 7**. The [shared contract](design/shared-artwork-picker.md), [28-candidate inventory](design/shared-artwork-inventory.md) and [consumer specification/compatibility decision](design/shared-artwork-rule-integrations.md) cover the implementation. One chooser/catalog serves all three features; 20 additional existing-file choices are available and eight remain deferred. **Stage:** 3 (premium UX and cohesion).
- **Owner request:** TwichUI already contains excellent artwork and the **Reminders “Choose an image” picker** is a successful browsing experience. Generalize that picker so other settings/features can choose from the same curated, searchable visual catalog. Enrich the catalog with **other useful existing TwichUI icons/artwork not currently listed**, not indiscriminately every texture file. Initial consumers: **Loot Rolls → Loot rules** and **Magic Inventory → rule builder**, where many rules become difficult to distinguish using repeated automatic icons.
- **Source inventory / reuse points:** `TwichUI_Settings/ArtworkPicker.lua` now provides categorized searchable artwork, preview, staged selection and Apply/Cancel; `pages/RemindersImagePicker.lua` is the thin Reminder adapter. `!!!TwichUI/artwork/Catalog.lua` provides catalog/search/rendering, while `reminders/Gallery.lua` retains its **reminder-specific** `G.Choose` operation; generated `!!!TwichUI/reminders/ArtData.lua` and `assets/reminder-gallery/manifest.json` document stable artwork metadata; `R.Icons` provides another existing icon source. `docs/reminders-art.md` describes generation and size variants. This is not a request to throw out the existing picker or build a second catalog.
- **Current rule presentation:** Both editors offer Choose icon through the shared picker. Optional validated `rule.artwork` controls Settings identity only. Loot retains action words and immediate saves; Magic Inventory retains item/category-derived defaults and private draft Save/Cancel. No runtime roll or transfer artwork changes.
- **Desired player experience:** In each supported rule editor, **Choose icon** opens the familiar Reminders-style picker with thumbnail grid, categories, search, current choice, clear preview, **Apply/Cancel**, and **Use automatic icon** to restore the existing feature-derived default. Chosen artwork helps visually recognize a rule in long rule lists and its editor without altering any matching criteria, rule priority, item transfers or roll automation.
- **Default and semantics:** Existing rules keep their current automatic art until the player explicitly selects an override. For Loot Rules, preserve Need/Greed/Pass **meaning in words/status** even if the player chooses a different rule illustration. For Magic Inventory, selecting an image must never change item categories, binding restrictions or rule destinations. Unavailable/removed catalog IDs fall back visibly to automatic art, without silently rewriting the saved preference.
- **Curated shared catalog:** Audit existing `!!!TwichUI/media/` and `R.Icons` for useful, appropriately licensable bundled **symbolic icons/illustrations** that read at approximately 20–48 px. Add stable IDs, display names, categories, keywords and appropriate small textures while reusing existing sources and deduplicating files where feasible. **Exclude** window borders, backgrounds, progress bars, decorative sheets, giant banners and other UI material assets that are poor choices as personal icons. Preserve artwork provenance and generated-data workflow; do not blindly bulk-import every file or assume assets meant for a single UI use have a suitable icon crop.
- **Architecture boundary:** Separate a reusable **selector/catalog + candidate representation** from the **Reminders-specific persistence** (`Gallery.Choose` / `RM.SetDisplayMany`). Keep Reminders' current behavior, load-on-demand settings frame coordination, accessibility and existing selections intact. Each consumer owns its own bounded, validated selection save; prefer stable `kind/id` references to arbitrary texture paths. Do not rewrite the reminder display schema or create a new generalized settings framework.
- **Review boundary:** Batch 7 authorizes both Settings consumers and the smallest compatible optional reference. [Downgrade limits](design/shared-artwork-rule-integrations.md#batch-7-compatibility-decision) are explicit: older feature writers may discard custom choices. No broad migration, rule transport, runtime identity changes or additional catalog work is authorized.
- **Acceptance:** One consistent picker can be launched from Reminders, Loot Rules and Magic Inventory without losing another editor's unsaved state. Search/categories/selection/Apply/Cancel work identically. Distinct selected icons appear in the two rule lists and editor headers; automatic icons remain the default and can be restored. All saved selections survive reload/profile switch and duplication according to the existing rule settings conventions. Unknown IDs fail safely; every rule's behavior, action cues and priority stay unchanged; reused thumbnails remain readable at standard and narrow UI scale.
- **Suggested milestones (separate scoped PRs only after approval):** (1) review/curate artwork candidates and approve a lightweight picker mockup/reuse boundary; (2) extract or adapt shared picker/catalog with Reminders parity tests; (3) add Loot Rules icon overrides with validated persistence; (4) add Magic Inventory icon overrides with validated persistence. The rule consumers should not be built against an unfinished shared API.
- **Verification / exclusions:** Existing `tests/test_reminder_gallery.lua`, `tests/test_reminders_settings.lua`, `tests/test_loot_rolls_settings.lua`, and `tests/test_magic_inventory_settings.lua` are sensible starting points; use targeted settings/simulator captures only if valuable. No changes to loot decisions, Magic Inventory movements, combat APIs, automatic rule action, Market/Opportunities, or release workflow.
- **Resolved scope:** Custom artwork identifies rules in Settings lists/builders only. Shared item icons, bundled art and registered catalog choices are supported. Runtime visuals and the eight conditional catalog candidates remain outside this batch.

## Workshop crafting experience — new owner requests (November 22, 2026)

**Status: Product candidates and reliability investigation — not Autonomous-Ready.** These five requests form a connected journey: add a craft → gather needed items → open the recipe → observe a combined multi-craft timer → keep completed crafts and remaining materials accurate. Existing notes **W10 and W13** are expanded rather than duplicated; **W24–W26** are newly numbered ideas. No item is authorized for implementation by this section.

| ID | Request | Preliminary priority | Scope and relevant existing implementation | Readiness |
|---|---|---|---|---|
| **W24** | One combined progress bar/estimated remaining time when crafting multiple items (e.g., 40 bolts of silk cloth at roughly five seconds each) | Medium UX | **Owner-selected presentation preference: offer both styles** — (1) a separate, movable TwichUI overall crafting progress bar and (2) integration with/enhancement of the game's existing cast bar **only if Forever safely supports it**. Let the player choose the presentation, with a safe separate-bar fallback if native integration is unavailable. Both show estimated total time and confirmed completed/remaining crafts, distinguish waiting/stopped/interrupted work and never promise a guaranteed ETA. Reuse `TwichUI_Workshop/Progress.lua` when completion evidence is established. | **Discovery / technical feasibility:** verify native cast-bar permissions, secure lifecycle and event reliability before enabling that style. Do not suppress or replace protected casting, start casts, or misrepresent unverified progress. Not Autonomous-Ready. |
| **W25** | “Add to TwichUI Craft Queue” button in Blizzard's profession pane | Medium integration | On the player's own selected recipe, offer an explicit button that adds it to the existing Workshop queue using `Session.Add`/`Queue.Add`, respecting learned recipes, queue limits, duplicates, available quantity information, and Workshop experimental consent. Verify supported profession frame APIs and attachment lifecycle. | **Discovery:** add one craft or use Blizzard's currently selected quantity? UI placement and safety need review. [W25 evidence and proposed minimum](workshop/native-queue-discovery-w25.md); native APIs/placement and quantity decision remain open. |
| **W10** | When visiting a relevant merchant, offer to buy queued vendor materials and show the total price | High convenience | Extend existing W10: calculate still-needed quantities from `Session.ShoppingPlan` and current vendor listing/stock; show a contextual review with items, quantities, per-item cost and **total cost**. Use existing `Restock` safeguards as a reference, preserving its independent preferences. Never buy beyond available stock, funds or space; handle shortfalls and merchant closing. | **Candidate requiring purchase policy:** default to an explicit **Purchase** click and revalidation. Do not automatically spend on merchant open without separately approved opt-in. |
| **W13** | Automatically reduce queued crafts after crafting, keeping remaining required materials accurate | **High reliability issue** | User reports a queued recipe does not decrement after completing a craft, so consumed reagents can make remaining material requirements grow. `Progress.Credit` already decrements on manual Done, but `Progress.auto=false` holds event-driven crediting pending verification of `UNIT_SPELLCAST_SUCCEEDED`, recipe IDs, cast GUIDs and multi-craft cardinality. Credit **confirmed craft operations only**, once each, and recompute remaining shopping needs from the corrected queue and real bag state; avoid double subtraction. Preserve manual Done/Undo. | **Blocked on trustworthy Forever event evidence** (existing Test Lab `crafting.progress.events` probe); owner prefers default-on only when verified safe. A narrow client probe may be needed but never blocks unrelated releases. [W13 evidence, probe limits and owner steps](workshop/craft-progress-discovery-w13.md). |
| **W26** | Click an ingredient marked “Craft” in the compact **Travel** view (and relevant Shopping rows) to open its profession recipe | Medium convenience | Travel is an existing mode of `TwichUI_Workshop/Compact.lua`; use the selected plan's known make recipe, `Session.OpenRecipe` and `Observe.OpenRecipe`. Offer a clear click action, and explain when the recipe/profession is unavailable. Multiple possible recipes must not select an unverified one. | **Candidate/discovery:** decide click gesture and handling when several recipes make the same item; never automatically start crafting. |

### Intended experience and guardrails

- **Correctness dependency:** W13 is foundational for trustworthy queue counts, reagent demand and W24's completed-craft feedback. Treat the failure to decrement as a reliability bug, not merely a feature idea.
- **Player control:** The W25/W26 UI actions add or navigate only. W10 offers review of purchases and requires explicit player consent before spending; preserve merchant and combat restrictions.
- **Timing clarity:** W24 should offer a player choice between a movable TwichUI overall timer and a safely supported native cast-bar enhancement. The duration is estimated; account for pauses, interruptions and confirmed completed iterations. Never modify or hide protected cast controls, and fall back to the separate TwichUI display if native integration is unsupported.
- **Reuse:** Start from `Progress.lua`, `Queue.lua`, `Session.lua`, `Observe.lua`, `Compact.lua`, `ShoppingPlan` and existing Test Lab probes. Avoid duplicate inventory/merchant/craft engines or costly blanket testing.
- **Owner decision resolved:** W24 should offer **both** presentation styles as selectable options, with the native-style choice conditional on verified Forever feasibility and a safe separate-bar fallback.
- **Remaining design questions:** W24 native cast-bar API/lifecycle feasibility; W25 quantity behavior; W10 explicit confirmation versus separately opt-in remembered auto-buy; W26 recipe choice when several output the same material.
- **Release / readiness:** No new task enters [Autonomous-Ready](autonomous-ready-tasks.md) until acceptance criteria and relevant Forever API/safety assumptions are confirmed. The normal offline test tiers remain proportional, and real-client acceptance is owner-directed.

## Audit-derived work register

| ID | Finding / initiative | Proposed position | Status and acceptance guidance |
|---|---|---|---|
| **A01** | Opportunities list/estimate/render responsiveness | **Active / Stage 1** | Owner already tackling it. Profile first paint, cached repaint, worst uninterrupted callback and dependency invalidation; use a few representative small/large inputs. Don't change price math as a shortcut. |
| **A02** | Market data payload validation, load/sync and partition behavior | **Active with A01 / Stage 1** | PRs #97, #99, #100 and #102 cover joint Opportunities/Market performance investigation and remediation; do not start parallel implementations. Confirm merged status before marking finished. Preserve integrity and atomic fallback. |
| **A03** | Proportional offline tests and affordable performance regression detection | Stage 1 / ongoing | PR #95 agent-policy guidance merged. Improve existing runner/source selection only where current friction is measured; no new framework; preserve release tier. |
| **A04** | Neutral/Blackwater auction house fee classification | Stage 2 | Source-confirmed potential rate omission; normalize supported market identity, test vendor/auction fee examples. |
| **A05** | Market source status and refusal messaging | Stage 2–3 | Closed, unmerged PR #87 holds relevant UX design; review against current main. Clear external vs local source, timestamp, scope, rejected reasons. |
| **A06** | Ledger Open All sale attribution | Stage 2 | PR #81 merged and regression-tested offline; optionally compare against a natural in-game mailbox session. Do not claim exact profit for unmatchable auction sales. |
| **A07** | Startup, SavedVariables and first-use performance attribution | Stage 1 | Existing Diagnostics starts after file/SV loading; keep cold login, reload and first-open timings distinct. Optimize only proven contributors. |
| **A08** | Cohesive settings/window interactions and EllesmereUI consistency | Stage 3 / ongoing | Establish a lightweight visual QA checklist, including keyboard/gamepad relevance, hover, scale, alignment, scroll, progress, errors and recovery. See **UX01** for the specific Quality of life page redesign discovery. |
| **A09** | Testing evidence/repository hygiene and AI agent navigation | Ongoing | Keep a concise agent entrypoint and architecture map; migrate historical generated artifacts only if worth the effort. No blanket refactors or automated agent teams. |
| **A10** | Native performance monitor improvements | Later if justified | Prefer existing Perf/Diagnostics and bounded opt-in copies of reports; do not add background instrumentation without a demonstrated data gap. |
| **A11** | Release packaging/CI safeguards | Ongoing | Existing one-click owner-authorized release workflow and offline checks; optional native testing under owner control, with honest evidence labels. |

## Priority shortlist for discussion (not accepted commitments)

**Now:** A01 Opportunities and A02 Market performance are already being addressed together through the current active PR stack; do not select either for an unrelated autonomous batch. **Later, only if measurements justify it:** A07 startup attribution. **Small correctness fixes:** A04 and A05 after performance integration. **Ready polish candidates:** P01, P04, P05, W21, W22, F12; P03 improves test selection. W04/W05 remain on hold while Market changes are active. **Verify existing before rebuilding:** W09 multilevel crafting, W17/W18 tooltip builder, F15 auto flight, F17 Attune broker, F04 Fishing follow-up.

**Watch for overlap:** W01 and W19 both touch auction pricing/Market confidence but are not identical; W07 builds on Gold Ledger; F12 and F29 describe one Waylaid-crate area. New W24/W25/W26 intersect with existing W10/W13 and Workshop's crafting/Travel flows; reuse those systems rather than build duplicates. Keep linked notes until scoped.

**Settings discovery:** UX01 still needs design. **UX02** has a merged shared foundation and Batch 7 consumer integrations in review; further scope requires separate authorization.

**Reasonable release cadence:** small PRs with focused tests, periodic integration checks for shared changes, full offline certification at explicit release preparation. No native game-play gate unless the owner elects to use one.

## Complete original note inventory

The original 57-note inventory is retained below; new November 22 Workshop ideas W24–W26, and refinements to W10/W13, are documented separately in [Workshop crafting experience](#workshop-crafting-experience--new-owner-requests-november-22-2026).

Each note is preserved in wording below. The proposed status and effort are planning estimates, not verified implementation outcomes. **S / M / L** mean small / medium / large relative effort; **?** needs definition. Stage **—** means already implemented/verify, not part of the prospective build roadmap.

### Polish Critiques — all 5 notes

| ID | Original note | Stage | Proposed disposition | Effort | Rationale / next question |
|---|---|:---:|---|:---:|---|
| P01 | The Magic inventory progress bar hides the text on top of it | 3 | **Autonomous-Ready** | S | Specifically bank transfer progress text; preserve confirmed-only progress and banking actions |
| P02 | Party ping receipt and replay | — | **Verified Existing — Batch 10** | S | Existing sound/animation/navigation/mute/rate/cancellation tests pass; no replay rewrite. [Native-only checks](map-pings.md#batch-10--p02-verified-existing) |
| P03 | The way tests are ran individually needs to be changed | 1 | **Autonomous-Ready** | S/M | Owner wants easier selection of the correct targeted tests; use advisory no-run recommendations and safe unknown-path fallback |
| P04 | Toggles on target markers and world markers overlap | 3 | Fix candidate | S | Check scale, compact width, font and input hit targets |
| P05 | Restock from this merchant dialog not styled | 3 | **Autonomous-Ready** | S/M | Preserve layout and saved appearance; apply premium leather/bronze styling only |

### Workshop — all 23 notes

| ID | Original note | Stage | Proposed disposition | Effort | Rationale / next question |
|---|---|:---:|---|:---:|---|
| W01 | Added smarts to the auction sale tab where it analyzes the type of item and the amount listed to pick the correct price. For example, if there are 25 savory deets listed at one silver, but then 600 listed at two silver, it would prefer the two silver price over the one silver. as it is an increasing gold and is still highly likely to sell | 4 | Refinement of existing pricing | M/L | PR #85 already excludes bait tiers in estimates; assess sell tab distinct volume/depth tradeoffs with deterministic examples; no guaranteed sale probability |
| W02 | Flight master as currency source in ledger | 4 | Candidate | S/M | Attribute verified taxi expenses without double-counting or inventing sources |
| W03 | Dungeon run totals | 6 | Discovery | M | Define gold / loot / expenses / duration / run grouping before scope |
| W04 | Need button in the new auction house frame to scan it, as well as a progress bar, probably down at the bottom where the market date is | 3 | UX candidate | S/M | Explicit local AH scan control separate from Market server reload; show progress and safe disabled states |
| W05 | The market data should just show the date time of the loaded data and the tool tip is massive with just a bunch of hash codes in it | 3 | UX candidate | S | Make compact status and date; technical hashes only under expandable diagnostics |
| W06 | Would be nice to customize the auction sold messages in chat to show the icon, the amount they were sold for, and a optional sound | 4 | Candidate | M | Opt-in quiet concise messages; source only from verified auction-sale evidence |
| W07 | Needs tracking and charts to determine if I’m actually making any progress | 4 | Refine existing Gold Ledger | M | Existing charts measure gold flow; define progress metrics without confusing cash flow and realized profit |
| W08 | PFB: Near vendor price, adjustable offset via gold or percentage. | 4 | Candidate | S/M | Post From Bags vendor threshold with absolute or percent setting; preserve explicit posting and warning |
| W09 | Crafting queue needs to calculate cost of self crafting sub materials and offer a way for me to choose one or another, as well as track those materials if that is what I choose | 4 | Verify/refine existing planner | M | Multilevel craft/buy planner and source choice already exist; test full end-to-end UX and material tracking |
| W10 | Crafting queue should offer to purchase the required items from a vendor when opened | 4 | **Implemented quote / purchases Blocked — Batch 12** | M | Expanded Nov 22: contextual offer to purchase remaining planned vendor materials with itemized quantities and total price; keep explicit spending safeguards. See new Workshop crafting experience section. |
| W11 | Crafting queue should allow me to shut click at AH to link | 4 | **Autonomous-Ready after A01/A02** | S/M | Shift-click queued craft output searches TwichUI AH; must verify view availability and reuse existing Browse adapter |
| W12 | Crafting queue probably should have a custom search function | — | **Withdrawn: clarified into W20** | — | No queue search requested. Owner meant typing a quantity directly; don't implement W12. |
| W13 | Queue should remove X number of items as they are crafted | 2–4 | **Probe improved / automatic credit Blocked — Batch 12** | M | User observes queue remaining unchanged after crafting, causing incorrect reagent needs; Progress.Credit supports manual decrement, but automatic event credit remains off pending proof. See new Workshop crafting experience section. |
| W14 | Auto track gathering | 5 | Candidate | M | Clarify what is tracked, when the quest/objective updates and opt-in policy |
| W15 | Recipe Finder | 6 | Discovery | M/L | Define search by product, material, profession, alt and unknown recipe data |
| W16 | Item advisor shows items equipped | 4 | **Autonomous-Ready: fix existing In bags filter** | S/M | Existing In bags filter includes equipped-only gear; exclude worn gear while retaining any actual bag copies. No new Equipped filter. |
| W17 | Tool tip builders should include custom separators | — | Implemented — verify/close | S | PR #84 merged; review appearance if desired, do not rebuild |
| W18 | Tool tip builders should include the ability to remove or change the text that is displayed for what it’s worth | — | Implemented — verify/close | S | PR #84 includes editable/removable default heading |
| W19 | The opportunities page should use a better algorithm for the cost to make, as it’s currently just using the least expensive items in the marketplace and for example right now during launch, items sell so fast that those are not accurate values almost immediately | 1 | Partially addressed — investigate | M | PR #85 walks listing depth, filters bait and estimates confidence; current launch-market freshness and load responsiveness still need measurement |
| W20 | Any craft queue list, I should be able to click on the number to manually set a number, as well as have a right click context menu to do things like remove the entry or open the recipe in my professions book | 4 | **Autonomous-Ready: direct quantity entry** | S/M | Click current count, type 20 and Enter; retain +/-; existing Session.SetCrafts recalculates needs. Right-click is an optional separate scope. |
| W21 | In the shopping tab of the workshop frame, it shows the items I need, and on the right side it does actually show show what recipe it’s needed for, but it’s just a small text at the bottom. I think that should be a section of the bottom where it actually shows the item icon and name of what it’s for | 3 | UX candidate | S/M | Promote ingredient-to-output explanation to a useful dedicated section |
| W22 | In the shopping tab of the workshop frame, at the bottom, there are various numbers based off of the items sources, like vendor, auction, craft, and collect. The artwork for them is not vertically aligned with the text for each one | 3 | Visual fix candidate | S | Check different font sizes/scales |
| W23 | A favorite items tab on the auction house frame that allows you to quickly purchase your favorite items in your predefined amounts | 5 | Candidate | M | Favorite watchlist and requested quantities; never auto-buy without explicit confirmation |

### Feature Ideas — all 29 notes

| ID | Original note | Stage | Proposed disposition | Effort | Rationale / next question |
|---|---|:---:|---|:---:|---|
| F01 | Full gamepad support | 6 | Large concept / discovery | L | Start with navigation/action equivalence and protected input constraints |
| F02 | Configurable Execute Range indicator | 5 | Implemented for review — Batch 10 | S/M | Personal 1–100% threshold; source-verified EllesmereUI target/nameplate bars, marker/active/both. Secret health hides active edge; protected layout defers. [Evidence and native checks](design/execute-range.md) |
| F03 | Custom waypoint ui | 6 | Concept / discovery | L | Build on current navigation/WaypointUI rather than replacing blindly |
| F04 | Fishing module | 5 | Implemented; final integration and owner acceptance in PR #140 | M | Existing engine, HUD and Journal preserved; optional Workshop estimates, container reconciliation, Journal/HUD economics and settings implemented. See PR #140 and docs/fishing-verification.md for passing feature checks, simulator/RSS corrections and native acceptance. |
| F05 | What dungeons or zones are good for me | 6 | Concept / discovery | M | Define guidance inputs: level, quests, interests and group role |
| F06 | Dungeon tools | 6 | Broad concept | L | Decompose into discrete user journeys rather than generic large module |
| F07 | Quest log cleanup | 5 | Candidate | M | Specify reversible display/organization scope before touching quest records |
| F08 | Quest item cleanup | 5 | Candidate with safeguards | M | Avoid deleting or vendoring anything automatically without explicit review |
| F09 | Loot received cards | 5 | **Verified Existing — owner-confirmed** | M | Original distinction: receipts, not just roll choice. Owner confirms Loot Received Cards already exists; do not reimplement. |
| F10 | Arrival time of board and zeps | 6 | Feasibility first | M/L | Verify accessible timetable/observation data; no invented ETA |
| F11 | Automatically sort bank and bags after running a magic inventory rule | 5 | Candidate with safety gate | M | Respect automation protections, inventory state and click authorization |
| F12 | Do not see waylay crates in the magic inventory. There should also be a way to mark them as junk | 3 | **Autonomous-Ready: picker only** | S/M | Make carried crates selectable in item/rule picker; junk support requires separate decision; retain item safety guards |
| F13 | Leave me alone mode should also silence whispers and group invite sounds, suppress whisper messages | 5 | **Investigated / runtime Deferred — Batch 12** | M | Expand existing QuietScreen only as explicit opt-in; avoid irrecoverable communication hiding |
| F14 | Cooldown timeline bar | 6 | Large concept / discovery | L | Avoid rebuilding EllesmereUI; assess spell/accessibility and layout model |
| F15 | Navigation automatic flight | — | Verified existing + safety corrections — Batch 10 | S | Existing opt-in journey flight retained; fixed account-consent profile copying and stale delayed attempts. [Verification](navigation.md#batch-10-automatic-flight-verification) |
| F16 | Healer Watch contextual communication | 5 | Implemented for review — Batch 10 | S/M | Motion-only hover preserves click-through; explicit guarded clicks select self-status messages, never inferred statements about another healer. [Evidence and checks](healer-watch-communication-discovery.md) |
| F17 | Data broker for Attune | — | Implemented — verify/close | S | PR #73 merged and art PR #74 merged |
| F18 | Show a marker where party member died while they are dead. | 5 | **Investigated / position evidence Blocked — Batch 12** | M | Existing PartyDeath notification does not establish location marker; privacy/data and lifetime constraints |
| F19 | Remove last name from chat | 5 | Research/refinement | S/M | Clarify whether realm suffix vs actual displayed surname; avoid mangling names |
| F20 | Reminder Behaviors | 6 | Clarify / extend existing reminders | M | Define behavior examples and distinguish from outputs such as action glow |
| F21 | Talent builder | 6 | Large concept / feasibility | L | Avoid unrestricted talent/spell automation; specify planner UX and game API |
| F22 | Enhanced dispel indicators | 5 | **Separate major initiative — PR #139** | M | Healer usability, overlap with other addon visuals, combat-safe signals |
| F23 | Prayer of Mending tracker | 5 | Candidate / API feasibility | S/M | Spell-specific observation; confirm Forever mechanics and secure UI limits |
| F24 | TUI Does it Die? | 6 | Concept — clarify | ? | Keep idea name; define intended inputs/outputs before estimate |
| F25 | Naowh: Smart Reminders | 6 | Research concept | M/L | Capture inspirational behaviors; implement distinct value, not clone |
| F26 | Noawh: Group Inspect | 6 | Research concept | M/L | Capture desired group inspection experience, limitations and privacy |
| F27 | Party wipe effect | 5 | Candidate | S/M | Could reuse PartyDeath visual effects; require restrained opt-in presentation |
| F28 | Clicked/Macro Kit | 6 | Research concept | M/L | Clarify feature boundaries and protected macro creation/action restrictions |
| F29 | Magic inventory: Waylaid crates | 3 | Cross-reference F12 | S/M | Picker defect in F12; any future junk behavior requires separate scope |

## F30 — Magic Inventory: Bank and Guild Bank Quick Actions

**Owner idea (November 24, 2026):** Add a second page/tab to the existing bank
and guild bank Magic Inventory frame, with illustrated shortcuts for common
bulk transfers, such as withdrawing auction-recommended items, cloth, meat or
fish. **Proposed priority:** 4; **effort:** L, staged; **status:** discovery
ready, implementation gated. See [staged autonomous task specifications](autonomous-ready-tasks.md#f30--magic-inventory-quick-actions).

- Keep the existing Inventory/rule review intact. Add a Quick Actions tab with
  premium TwichUI artwork, readable labels, matching counts and disabled/empty
  states; group actions by Workshop recommendations and item categories.
- Initial withdrawal categories: cloth, meat, fish, herbs, ore/bars, leather,
  gems and enchanting materials, using verified item metadata rather than name
  heuristics. Consider all materials, consumables and equipment after core
  categories are proven. Preview matching stacks, quantities and destination.
- Workshop actions: Auction, Vendor and Disenchant recommendations must reuse
  the authoritative Advisor decision including local and Market inputs,
  readiness and freshness policy; unknown/pending recommendations are not
  actionable. Never auction, vendor or disenchant as part of a transfer.
- Proposed extensions (not initial requirements): Deposit direction, guild
  scope (current/selected/accessible tabs), Crafting Plan and Restock actions,
  and named/reorderable custom shortcuts using the existing rule builder and
  artwork picker. Preserve existing keep quantities and item protections.
- Every transfer requires explicit player review/authorization and obeys actual
  Forever API restrictions, bag capacity, permissions, withdrawal limits,
  locked items, combat and session changes. Reuse the existing transfer engine;
  do not bypass protected actions or claim unsupported automation. Report
  confirmed moves, skips and partial results; Stop prevents further requests.
- Design a small mockup before implementation; validate native API assumptions
  separately from simulator behavior. Split work by dependency, avoid concurrent
  edits to shared inventory/Advisor paths, and keep mailbox behavior unchanged.


## Status cross-checks and references

- [PR #95](https://github.com/Twich-Team/TwichUI/pull/95): shared agent efficiency/testing policy **merged**; runner improvements remain distinct possible work.
- [PR #85](https://github.com/Twich-Team/TwichUI/pull/85): Opportunities cost realism **merged**; not proof that current price freshness or load time is satisfactory.
- [PR #84](https://github.com/Twich-Team/TwichUI/pull/84): custom tooltip separators and removable/editable default heading **merged**.
- [PR #73](https://github.com/Twich-Team/TwichUI/pull/73): Attune broker **merged**; [PR #74](https://github.com/Twich-Team/TwichUI/pull/74) supplies artwork.
- [PR #92](https://github.com/Twich-Team/TwichUI/pull/92): Fishing Stage 1 **merged**; [PR #94](https://github.com/Twich-Team/TwichUI/pull/94) Stage 2 **merged**. Further stages remain uncommitted.
- [PR #81](https://github.com/Twich-Team/TwichUI/pull/81): auction Open All attribution **merged**, simulation-tested, real-client confirmation not claimed.
- [PR #87](https://github.com/Twich-Team/TwichUI/pull/87): clearer Market source/empty state **closed without merge**; assess applicable design intent, not an active PR.
- `!!!TwichUI/nav/Flight.lua`: opt-in autoFlight already implemented; `TwichUI_Workshop/Strategy.lua`: multilevel craft/buy planner; `!!!TwichUI/modules/RestockPrompt.lua`: some frame-style support exists despite visual critique; `!!!TwichUI/modules/PartyDeath.lua`: existing death notification, not evidence of a death-location map marker.

## Decision log (initial)

- **Owner corrections (November 22):** W12 search is not wanted; W20 means directly typing a queued craft quantity while keeping +/-; W16 means fixing the current In bags view so equipped-only gear is not listed, not adding an Equipped filter.
- **Owner clarifications (8):** P01 bank text; P05 keep layout/premium style; P02 receipt and replay (existing code, verify); P03 test selection; W11 AH Shift-click search; F12 picker visibility only; W13 verified auto-progress default on once safe; W16 Equipped filter. See [Autonomous-Ready register](autonomous-ready-tasks.md) for acceptance and blockers.

- **Owner-selected active campaign:** Opportunities and Market performance together (A01/A02, W19), with PRs #97/#99/#100/#102 open at this planning review. Await merge/results before selecting overlapping Market or Workshop pricing tasks.
- **Owner policy:** prioritize premium, cohesive UX; reliable responsiveness; AI-agent-friendly repository; comprehensive but proportionate offline tests; owner retains sole release readiness decision.
- **Not authorized by the roadmap alone:** no automatic backlog execution, feature builds, issue creation, PRs or repository edits. A separate owner-issued batch instruction may expressly authorize a bounded number of Autonomous-Ready items; Ready is eligibility only.

## How to refine next

Choose a few items by **player pain**, **how often experienced**, **implementation risk**, and **expected value**. For each selected item, write a short acceptance statement and designate required existing tests. Move out-of-date fulfilled notes to **verified/archive** rather than deleting their history. Ideas requiring substantial design stay in **discovery** until the player experience is articulated. Update statuses only with a merged code/reference or the owner's own acceptance, not assumptions.
