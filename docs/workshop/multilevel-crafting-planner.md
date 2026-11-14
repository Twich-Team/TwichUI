# Workshop P1: the multilevel crafting planner

`TwichUI_Workshop/CraftPlanner.lua` (`W.CraftPlanner`). Built 2026-11-13 on `feature/workshop`. P1 (sections 1 to 13) is the **pure engine**: it knows no window, session or saved data. **P2 (section 14, 2026-11-13) connects it** to Opportunities, the Crafting Plan and Shopping through `Strategy.lua`; the engine itself was not changed. `Shopping.Plan` stays as the one-level fallback.

Evidence labels used below: **unit-tested** (`tests/`), **simulator-tested** (`tools/simlab`), **not tested**. Nothing here is **real-client-tested**.

## 1. What it does

Given the queue, what the player owns, the vendor, auction-house and recipe services, and the player's source choices, it decides for **every material of the whole chain** whether it is bought (vendor or auction house) or made by a known recipe. A made material's reagents are decided the same way, several levels deep. The result is one coherent plan:

- the crafts, in an order that can be carried out;
- what to buy, from which source;
- what to take from the bags and what to collect from the bank or guild bank;
- the leftovers;
- the economic cost and the cash needed, each as a lower and upper bound;
- why each source was chosen, and what the alternatives would cost.

It does not touch the queue, the saved source choices, or any saved data. It buys nothing and crafts nothing.

## 2. Public API

```lua
local CP = R.Workshop.CraftPlanner
local plan = CP.Plan(inp, opt)        -- all at once (tests, small plans)
local job  = CP.Job(inp, opt)         -- the same work in steps (P2)
repeat done = job:Step(CP.STEP) until done   -- one Step per frame in the game
local plan = job:Result()
job:Cancel()                          -- drops the work; Step then returns false
CP.Compare(x, y)                      -- "lower" | "higher" | "equal" | "overlap" | "unknown" for two plan figures
CP.WHY[code]                          -- a plain sentence for each reason code
CP.LIMITS, CP.STEP, CP.RANK           -- the bounds, the per-frame step, the tie order
```

`opt = { objective = "economic" | "cash", limits = { ... } }`. `limits` overrides entries of `CP.LIMITS` (the tests use it to force a limited search).

**P2 must use `CP.Job`** for a real queue. `CP.Plan` of a large queue can take 50 to 100 ms at once offline (section 11). It is safe at once only for small plans, such as a single recipe's preview.

## 3. Input contract

`inp` takes the same functions `Shopping.Plan` takes, except that it uses `entries` instead of `rows`:

| field | meaning |
|---|---|
| `entries` | the queue as `Materials.Combine` reads it (`Session`'s `QueueView`): `{ id, name, crafts, mats = { { item, qty } }, outItem, outMin, outMax }`. Each entry is checked: `crafts` must be a whole number from 1 to 999 (else `invalidEntries`). Materials must be countable (else `unknownEntries`, which add nothing, never zero). Duplicate materials are added together. |
| `have(item)` | the bag count. `W.Count` decides it: anything that is not a whole number from 0 (NaN, an infinity, a fraction, a negative, a secret value, a string) is **unknown**. |
| `stock(item)` | bank count and guild-bank count that may be planned with (`Stock.Fn`). |
| `vendor(item)` | a `Vendor.Entry` record `{ p, s, a, at, npc }`. A record that fails the checks still marks the vendor as existing but unpriced. |
| `sells(item)` | `true` when a merchant is known to sell the item. |
| `auction(item)` | the `Market.Price` lookup (the owned-value price, and the old unit quote when there is no cost service). |
| `cost(item, qty)` | `Market.Cost` (A7). Optional; without it, the old unit-price quote is used. |
| `recipes(item)` | the known recipes that make the item (`Session`'s `Index` by output). |
| `available(rec)` | optional; return `false` for a recipe the character cannot do now. Without it, every listed recipe is treated as learned, as `Known.lua` keeps only the character's own learned recipes. |
| `picks` | `{ [item] = "vendor" | "auction" | "make" }`, `Session.picks`. Read, never written. |

**The recipe contract** (checked in this order; a refused recipe is listed under `rejected` with its code):

| code | when the recipe is refused |
|---|---|
| `invalid` | its id is unreadable, or it makes another item |
| `unavailable` | `available(rec)` said no |
| `unsupported` | its materials are missing or empty, an item or quantity is not a whole number in range, or it has more than 16 materials |
| `noamount` | its output is not a whole number from 1 to 9999 |
| `range` | its `outMax` differs from `outMin` |
| `circular` | it uses its own output |

Only a recipe with a **fixed positive output** is planned. Cooldowns, tools, crafting stations, reagents bound to the player and trade restrictions are not read by the Workshop. They are **not checked** and not claimed to be satisfied; P2 must say so, as Shopping does today.

## 4. The rules

**Demand is combined before anything is decided.** The queue's materials are added up and credited with what queued crafts make (`Materials.Combine`, the same rule Shopping uses). A made material's reagents are added to the same per-item total. Demand flows through the items in a fixed order (by depth from the queue, then item id). An item that gains demand after it was passed is visited again in the next pass. So every item is decided once, on its **whole** demand, however many branches need it. Three queued crafts that each need one intermediate are one craft of three, not three crafts.

**Owned stock is allocated exactly once.** An item's whole demand takes, first, what queued crafts make. It then takes from the bags, then the bank, then the guild bank (`W.Split`). Only then is anything bought or made. An item with an unknown bag count is planned as if none were owned: the line is flagged `countsUnknown` and the plan is not complete.

**Batches and leftovers.** The number of crafts is `ceil(still needed / output)`. The rest of the last craft is a leftover. It is reported, never credited to another item, and never valued. Vendor stacks work the same way: whole stacks are bought and the surplus is reported.

**Circles.** A plan whose crafts depend on each other is never returned. Every evaluated combination is checked in two ways:

- demand that keeps growing after as many passes as there are items must come from such crafts;
- after the demand settles, the crafts that are actually done are checked for a cycle.

The second check catches a circle that settles. For example, X makes 3 from 1 Y and Y makes 3 from 1 X: one craft of each "covers" everything at no cost, but neither can be started. The circle is refused and its items are named in the alternative that would have used it (`why = "circular"`, `cycle = { items }`). The same item's other routes stay usable. A recipe whose crafts would exceed 999, or whose demand would exceed 2^31 - 1, is refused as `toomany`.

## 5. Economic cost and cash

- **Cash** is what is bought: vendor costs, and auction-house costs from `Market.Cost` for the item's whole quantity.
- **Economic cost** is cash plus the value of every owned item the plan consumes. The value is the cheapest price per item known (the vendor price over its stack, or the lowest auction listing), rounded half up. This is Shopping's `UnitValue` rule. Owned items are not free: a plan never looks cheaper because the player owns its materials.
- **Collect** rows list what the plan takes from the bank and the guild bank. They are not purchases.

`summary.cash`, `summary.economic` and `summary.owned` are kept apart. The `objective` option chooses which one is optimised:

- `"economic"` (default) ranks plans by (missing costs, economic low, cash low);
- `"cash"` ranks them by (cash missing, cash low, values missing, economic low).

The two can differ. For example: buy X for 15, or make it from 2 R the player owns, each worth 10. Economically, buying wins (15 against 20). For cash, making wins (0). This case is unit-tested.

## 6. Cost ranges and uncertainty

For each buy line:

| source | low | high |
|---|---|---|
| vendor | the exact cost | the exact cost |
| `Market.Cost` exact | the total | the total |
| `Market.Cost` range (whole stacks) | the cost of exactly the quantity | the cost of buying whole listings |
| `Market.Cost` estimate (more than six tiers) | "at least" | **open (nil)**, as A7 shows it; the service's "at most" is kept beside as `atMost` |
| old unit quote, beyond the cheapest listing | price × quantity | open |

Plan totals add up the lows and the highs. The upper bound becomes open as soon as one figure is open. One ingredient at 8 to 11 and another at exactly 2 give 10 to 13 (unit-tested). **Plans are compared on the lower bound**, A7's compatibility rule. The range is carried with every figure, and `CP.Compare` says whether one figure is certainly cheaper (its high is below the other's low), `equal`, `overlap` (the order is not certain) or `unknown` (a cost is missing).

An unknown cost is never zero. Unknowns are counted (`summary.cashMissing`, `summary.valueMissing`, `missing`, and `line.missing` with the reason `noprice`, `limited`, `few` or `nosource`), and a plan with fewer unknowns always ranks first. A `Market.Cost` answer whose numbers are not finite becomes `few` (unknown).

Every auction quote is checked for data quality. A quote from an incomplete scan, an `old` freshness, or quality `limited` or `none` is listed in `warnings`.

## 7. The search: guarantees and limits

1. **The graph.** The planner walks breadth-first from the queue's materials through each item's usable recipes, sorted by id. It stops at these limits:

   | limit | default | reported as |
   |---|---|---|
   | crafting depth | 6 levels | `depthlimit` (deeper items are only bought) |
   | items beyond the queue's own materials | 64 | `graphlimit` |
   | distinct recipes | 96 | `recipelimit` |
   | usable recipes per item | 4 | `candidatelimit` |

   The queue's own materials are always included (at most 30 × 16).
2. **The choices.** Each item has the choice *buy* (resolved at evaluation time to the cheaper of vendor and auction house for its final quantity; a tie goes to the vendor) plus each usable recipe. Collapsing the two buying sources into one choice is exact. Buying creates no demand elsewhere, so the best buying source for a given quantity never depends on other choices. An item with no vendor, no auction house data and no recipe is planned with source `none` (unknown cost).
3. **Independent parts.** Items that share nothing (no common item, so no common stock) are solved separately. The ranking key is a sum of independent parts, and the tie order is item-by-item, so the best plans of the parts together are the best plan of the whole.
4. **Branch and bound in each part.** The planner branches only on items that can be made, each when it first lacks something, choices in rank order. Every cost grows with demand, so the figures of an undecided plan are a lower bound of every plan that completes it. A branch whose bound already ranks after the best plan found is pruned. The search starts from two seed plans: every item's first choice (buy), and the cheapest choice by a rough unit-cost estimate. **While the search finishes within its states, the plan is the proven best of the options considered** (`optimization = "exhaustive"`, `proven = true` when no graph limit was hit either).
5. **Limits.**

   | limit | default |
   |---|---|
   | branch-and-bound states | 2000 per plan |
   | local-improvement evaluations | 300 |
   | items whose alternatives are evaluated | 24 |

   Parts with nothing to decide keep no share of the states. A part that reaches the state limit keeps the best plan found. A local improvement then changes one item's choice at a time and keeps any change that ranks first. The part is reported as `optimization = "bounded"` with the reason `states`, and is **never called optimal**.
6. **Ties.** Among plans of equal key, the planner compares items in id order and prefers vendor, then auction house, then no source, then the recipes by id. The same inputs always give the same plan (unit-tested, also through the stepped job).

**Memoisation.** Only purchase quotes are memoised: `(item, quantity) → quote`, at most `memo` = 4096 per plan. They are state-independent. Nothing that depends on stock or on other branches is cached; each evaluation recomputes demand from scratch.

## 8. Overrides

- A valid player choice restricts the item to that choice: `vendor` or `auction` when that source exists, even if unpriced (as Shopping's `Usable`); `make` when a usable recipe exists. The choice applies to the item's whole combined demand.
- An impossible choice (`novendor`, `noauction`, `norecipe`, or the recipe's own refusal code such as `unavailable`) is ignored, reported in `plan.picks` and `line.pickLost`/`pickWhy` with the reason `picklost`, and does not change any other item.
- If honouring the `make` choices leaves no plan at all (for example, two items chosen to be made from each other), those choices are dropped with the reason (`circular` or `toomany`) and the part is solved again.
- No choice is saved or changed. No new persistence was added.

## 9. The result

```lua
plan = {
  version = 1, objective,
  summary = {
    status = "empty" | "complete" | "incomplete" | "unavailable", complete, entries, final = { { id, name, crafts, outItem } },
    unknownEntries, invalidEntries,
    economic = { low, high }, cash = { low, high }, owned,          -- high nil = open
    missing, cashMissing, valueMissing, crafts (operations), parts,
    optimization = "exhaustive" | "bounded", exhaustive, proven, limits = { codes },
    reasons = { codes },                                            -- CP.WHY has a sentence for each
    baseline = { economic, cash, missing, compare },                -- nothing made beyond the queue: every lacking material bought
    savings = { lowerBounds, low, high, confident },                -- against the baseline, only when nothing is unknown
    work = { evals, states, pruned, leaves, improve, passes, nodes, memo, alternatives },
  },
  crafts = { { order, item, recipe, name, crafts, perCraft, produced, used, leftover, reagents = { { item, qty } }, after = { items } } },
  items = { { item, need, queue, queued, owned = { bags, bank, guild }, value, valueMissing, rest, depth, source = "owned" | "vendor" |
              "auction" | "none" | "make", buy = { source, qty, state, low, high, atMost, exact, at, surplus, purchases, why, quality, freshness,
              complete }, make = <the craft>, options = { vendor, auction }, usedBy = { { queue | recipe, item, qty } },
              alternatives = { { kind, source | recipe, name, ok, why, cycle, economic, cash, missing, compare, difference } },
              picked, pickLost, pickWhy, countsUnknown, rejected, deep, missing } },
  buy = { buy lines with a price }, collect = { { item, where = "bank" | "guild", qty } },
  leftovers = { { item, qty, kind = "craft" | "stack", recipe } },
  warnings = { { item, complete, freshness, quality } }, rejected = { { item, recipe, why } }, picks = { { item, pick, why | kept | ignored } },
}
```

The savings `low`/`high` are `baseline low - plan high` and `baseline high - plan low`, either open. `confident` means the lower end is above zero. `lowerBounds` compares the lower bounds the plans are ranked by and is never a promise. An alternative's `difference` is its economic low minus the plan's: what switching that one item would change, with the other items kept, and newly needed materials at their default choice.

Selling prices, sale chances, auction fees and skill-ups are **not** part of the result. P1 is an acquisition planner.

## 10. Tests

All of these are unit-tested.

- **`tests/test_workshop_craftplanner.lua`** (about 7 s):
  - **A**, hand-calculated chains with the arithmetic in comments: one, two and three levels; combined demand changing the decision; shared raw materials; full, partial and no coverage by stock; bank and guild-bank order; valid and impossible overrides, including a circle of overrides; batches and stacks; self, two-item, three-item and settling circles; a circle with another route; a diamond; several producers; unknown reagent price, output, recipe and bag count; the real `Market.Cost` at a tier boundary, a whole stack and beyond six tiers; a range carried through a chain; an overlapping comparison; cash-best against economy-best; ties; the search limit; budgets with 300 trivial parts; prices beyond 32 bits and beyond 2^53.
  - **B**, 400 seeded scenarios (`FX.Chain`, 7540000+i and, with dear intermediates and a top-level queue, 7545000+i), each planned under both objectives with the **real `Market.Cost` over a market built from the listings**. They are compared item by item and in total with the **exhaustive model** (`TwichUI_TestLab/Reference.lua` section 8, `REF.ChainPlan`). The model lists every combination of every reachable item's choices, finds demand by Jacobi iteration, allocates one item at a time and prices from the plain listings. It shares no code with the planner. Every seed matched: 123 plans make something, 31 of them two or three levels deep, 64 scenarios have circular combinations refused, and in 56 the cash-best plan is not the economy-best. A mismatch report gives the seed, graph, stock, prices and both plans (`CHAIN_SEED=<seed>` reruns one).
  - **C**, the feasibility invariants, recomputed from the inputs: demand equals the queue plus every craft's reagents; one line per item; owned stock equals `REF.Take` (bags, then bank, then guild bank) and never exceeds stock; non-negative whole numbers; the fewest crafts; leftovers; planned recipes valid and available; the craft order; totals equal the sum of the lines; unknowns counted; collect rows. These run on every plan of A and B, on 40 larger graphs, and on limited searches of them (a limited plan never beats the full one).
  - **D**, malformed input: NaN, infinities, fractions, strings, NaN merchant records and cost answers, seven malformed recipes, unreadable entries, a 300-level chain, a fan of 6 × 16 reagents per item.
  - **E**, determinism, inputs never changed, the stepped job equal to the plan at once, cancelling.
  - **F**, `Shopping.Plan` identical with and without the file loaded (30 seeds); no other file in the TOC mentions the planner; the TOC order.
- **Mutation:** `--group crafting.planner` has 24 entries. Each is a realistic defect:

  | area | defects |
  |---|---|
  | demand | late demand dropped (demand split), reagents double counted, queued credit ignored |
  | stock and value | bags counted twice, owned items free, owned value truncated |
  | batches | crafts rounded down, leftover dropped |
  | recipes and circles | alternate recipe ignored, circle accepted, self-recipe accepted, unavailable recipe used, depth one level too deep |
  | order and overrides | order ignores prerequisites, impossible pick honoured |
  | costs | estimate reported as exact, upper bound from the lows, unknown as zero, cash conflated with economic |
  | ranking and search | vendor/auction tie, tie order reversed, equal-bound pruning, limited search called proven, budget reserved for trivial parts |

  All 24 are killed. The whole crafting group: 86 of 86 killed. The market group: 176 of 176. One equivalent mutant (`VecCmp >= 0` → `> 0`) was examined and left out, as the catalog notes.
- **Test Lab** (`cases/Crafting.lua`, core category, offline through `test_testlab.lua`): `crafting.planner.two-level`, `.shared-stock`, `.cycle`, `.alternatives`, `.ranges`, `.bounded`, and `.reference` (16 seeds × 2 objectives against the model, with the `REF.ChainCostFn` stand-in for the cost service; the Lab never builds a saved market). In the client these are **not tested**.
- **Simulator-tested:** `tools/simlab/workshop.sh` loads the real TOC with the new file: 477 checks per launch, passing with only the previously classified simulator limitations. `tools/simlab/testlab.sh` passes with no runtime errors, and `lab_guard.sh` passes 28 of 28. They prove the file loads and nothing in the window changed, nothing more.

## 11. Performance

Offline figures: WSL2, plain Lua 5.1, `os.clock`, median of 5. They are not the game's figures.

| plan | all at once | as a job, `Step(300)`: steps, longest | evaluations |
|---|---|---|---|
| a small chain (reference size) | 0.4 ms | 3, 0.20 ms | 30 |
| a large chain (29 items, exhaustive at 1,900 states) | 47 to 50 ms | 244 to 261, 0.6 to 0.7 ms | about 2,000 |
| A7's 480 materials, buy only | 14 ms | 151, 0.9 ms (worst of 5: 2.0) | 1,920 |
| 480 materials, each from 2 recipes over 3 shared materials (one part reaches its state limit) | 103 ms | 569, 1.5 ms | 3,876 |
| 480 materials, each its own 2-level chain (480 parts) | 19 ms | 167, 1.2 ms | 2,136 |

Benchmarks (`bench_workshop.lua --only crafting.planner`, the same workloads as the Lab's opt-in `perf.crafting.planner.*`, each step one `Step(300)`):

| workload | total for the set | longest step | retained |
|---|---|---|---|
| `small` (40 plans) | 9.7 ms | 0.37 ms | under 150 KB |
| `large` (12 plans) | 53 to 89 ms (noisy) | 1.2 ms | 15 KB |
| `worst` (8 plans) | 28 ms | 0.5 ms | 13 KB |

Growth over repetitions is about 0 KB. While a plan runs, the heap grows by 2 to 7 MB of short-lived tables (evaluation results and search frames); the collector reclaims them.

**Consequences for P2.** A7's 480-material Shopping plan took about 59 ms at once. The planner at once is 14 to 103 ms for such queues, so **P2 must use `CP.Job` with `CP.STEP` per frame** (or less). The job's unit is items touched plus a fixed cost per evaluation, per part and per item built; `CP.BUILD_COST`, `CP.EVAL_COST` and `CP.PART_COST` were calibrated so a step stays near a millisecond offline whatever the plan's shape. The worst plan above needs 569 steps (about 10 s at one step per frame). P2 should show progress, keep the last plan while a new one runs, cancel on a change, and possibly use lower `limits` for a live preview. Nothing runs by itself: no timer, no `OnUpdate`, no background optimiser.

## 12. P2 handoff

- **Input.** Build `inp` as `Session.Shopping` builds Shopping's: `entries = QueueView(byId)`, `have = O.BagCount`, `stock = K.Fn(view)`, `auction`/`cost` over `src.market`, `vendor = V.Entry`, `sells`, `recipes = byOut[item]`, `picks = S.picks`. Add `available` only when a real "cannot do now" fact exists.
- **Crafting Strategy summary.** Use `summary.economic` and `summary.cash` (show the range, "at least" when `high` is nil), `summary.baseline` and `summary.savings` (say "certainly" only when `confident`; `overlap` means the order is not certain), `summary.optimization`/`proven` ("best of the options considered" only when proven; "best found" when bounded), and `reasons` through `CP.WHY`.
- **Buy against make.** Use `items[i].alternatives` with `compare` and `difference`.
- **Collection.** Use `plan.collect`, plus the guild-bank caveats from `Stock` (shared stock, limits).
- **Adding the crafts to the queue.** Use `plan.crafts` in order (`recipe`, `crafts`). This is the player's explicit action, as `S.AddSubcraft` is today, and it needs a confirmation. After adding, the queued credit makes the next plan count those crafts, so nothing is counted twice.
- **Opportunities.** Plan one recipe as a one-entry queue with `CP.Plan` (small) to show "cheapest way to make it". It must not replace the A7 estimate until P2 decides how profit is shown.
- **Shopping.** Switching its suggestions to this planner is a visible change of the approved A7 behaviour. P2 should decide it explicitly. The row shape differs: one line per item and source, rather than buy/make/collect rows.

## 13. Known limitations

These are inputs the client data does not give the Workshop today:

- cooldowns, tools, crafting stations;
- bind and trade restrictions;
- whether the guild-bank allowance really permits the withdrawal (Stock's existing caveat);
- byproducts and procs;
- the selling side.

A recipe is assumed doable if the character knows it. Leftovers have no value in the plan. The queued credit is Materials' rule: it applies only to items the queue itself needs, with no credit for a cyclic queue entry. Auction quotes come from the last scan: remembered, not live. In the client, all of this is **not tested**.

## 14. P2: the planner in the windows (built 2026-11-13, `feature/workshop`)

P2 connects the engine to Opportunities, the Crafting Plan and Shopping. **`CraftPlanner.lua` was not changed**: every consumer adapts to its API. Evidence labels: **unit-tested** (`tests/`), **simulator-tested** (`tools/simlab/workshop.sh`), **not tested** (the real client; nothing here has run in Forever).

### 14.1 What the player sees

- **Opportunities.** The details hold a compact **Crafting strategy** block for the chosen recipe made once, on its own: *Buy ingredients directly*, *Optimized economic cost*, *Cash needed now*, *Savings* (or *Potential savings*), a status ("Best verified plan", "Best plan found", "Partial plan: some prices or recipes are missing"), what to do ("Craft 1 · Buy 3 · Collect 1") and **View strategy**. It is a separate, labelled reference. **The row's cost, profit and the list's sort are still the one-level A7 estimate** (the Cost to make box says so in its tooltip; A8 will replace the selling side). The Price history chart is untouched and has more room than before (section 14.8).
- **View strategy** (`ViewStrategy.lua`). A window over the Workshop in the same surfaces: four figures, then one scrolling list: crafting steps in order (what each uses, leftovers), what to buy (source, quantity, price or range, how old the scan is), what comes from the bags, what to collect from the bank or guild bank, the other ways considered ("Make Bar: 90c more, certainly dearer than the plan"), and what to know (the planner's reason sentences, rejected recipes, "owned materials lower cash, not economic cost", "cooldowns and stations aren't checked"). **Add optimized plan** opens the confirmation.
- **Crafting Plan.** A strip above the materials gives the status and counts of the plan for the **whole queue** (one plan over combined demand: never a sum of per-recipe plans), the economic cost and the cash now, and View strategy. Each material row carries one line on how the plan gets it ("Craft Bar × 4", "Buy 3 at auction", "Collect 2"). The chosen craft's panel is more compact (Open recipe and Remove sit beside the name block) to pay for the strip. The estimates in the boxes and the bar are unchanged.
- **Shopping.** The default suggestions come from the multilevel plan of the whole queue (the approved product decision). The page, its rows, details, source buttons and bar are the ones it had. A material made by the plan shows as a **Make** row whose cost is "In the plan"; its own materials are rows of their own (bought, or collected). **Add optimized plan** (on a Make row) opens the same confirmation. The bar names the plan's status and economic cost; **View strategy** is at the top.

### 14.2 Modules

| file | what it is |
|---|---|
| `Strategy.lua` (`W.Strategy`) | words (`Status`, `Summary`, `Savings`, `Actions`, `RangeText`), the planning jobs (`Request`, `Bump`, `Reset`, `Peek`, `Last`, `Pump` for tests, `Stats`), the adapter (`Adapt`, `RowWhy`), the queue operations (`Ops`) and the strategy rows (`Detail`). No frames, no saved data. |
| `Session.lua` | `PlanKey`, `QueueStrategy`, `ShoppingPlan`, `OppStrategy`, `PreviewOptimized`, `ApplyOptimized`. `S.Shopping` (the one-level plan) is unchanged. |
| `Queue.lua` | `Q.AddBatch(ops)`: several recipes, all or nothing. |
| `ViewStrategy.lua` | the strategy window and the confirmation. |
| `ViewOpportunities.lua`, `ViewCrafting.lua`, `ViewShopping.lua`, `Window.lua` | the three pages and the shell's wiring (a finished job redraws the page; a bag event invalidates plans; closing drops them). |

### 14.3 The planning job lifecycle

1. **A page asks** (`Session.QueueStrategy`, `ShoppingPlan`, `OppStrategy`, `PreviewOptimized`) with a **key**: `Session.PlanKey` = the strategy epoch, the scope, the queue (recipe and crafts), what the bags hold of the entries' own materials, the player's source choices, the guild bank choice, what was seen of the bank and guild bank (times, tab and uncertainty counts), the price source and its scan time, `Scan.ended`, the vendor price count and the known-recipe count.
2. **`Strategy.Request(slot, key, make)`.** A result kept for exactly that key is returned. A job already running for it is left alone. Otherwise the slot's old job is cancelled, a new `CP.Job` is made, and **`St.FIRST` = 3 slices (`CP.STEP` work units each) run at once**: a small plan is ready before the page is drawn, so a click on a source never shows the old list for a frame. A longer plan goes on **one slice per frame** (`C_Timer.After(0)`, rescheduled only while a job is unfinished; no `OnUpdate`, no permanent timer).
3. **Slots** are `queue` (Crafting strip and Shopping share it), `opp` (the chosen recipe), `suggest` (the queue without the player's choices, only while choices exist), `confirm` (the queue plus the recipe being added). Each slot has its own generation, so a request of another slot never makes a job stale (a test and a mutation cover this).
4. **Invalidation.** `Strategy.Bump()` (epoch + 1) cancels every running job and forgets every kept result. It is called by queue edits (add, crafts, remove), a source choice that changed, the guild bank choice, a profession read, recipe details filled, a merchant read, a scan end, a bag event (`BAG_UPDATE_DELAYED`) and a bank or guild bank observation. The key also carries the epoch, the bag counts of the entries' materials and the stock view, so a missed event cannot show an old plan. **A result is only ever used for the key it was made for.**
5. **While it runs.** Opportunities says "Planning..." with "..." in the figures and disables View strategy (never another recipe's figures). Shopping keeps the **last finished list**, dimmed, with "Updating the plan..." in the spending line (`ctx.stale`); with no earlier list it says "Planning your shopping list...". The Crafting strip says "Planning...".
6. **Failure.** A job that raises is caught (`state = "failed"`). Shopping then shows `Session.Shopping`'s one-level plan with the note "Basic list (one level only): the multilevel plan couldn't be worked out", never the strategy words; Opportunities and the Crafting strip say it could not be worked out. The fallback is not used for any other reason.
7. **Close.** `Session.Reset` (the window hid) calls `Strategy.Reset`: every job is cancelled and nothing is kept.

### 14.4 Cost words (what each label promises)

| text | meaning |
|---|---|
| Best verified plan | `proven`: the search finished within its states and no graph limit was hit. The best of **the options considered**, not of everything possible. |
| Best plan found | the search hit a state or graph limit (or finished but did not prove). Never called optimal. |
| Partial plan | a price, recipe or bag count is missing; the figures are what is known. |
| Economic cost | cash plus the value of the owned materials the plan uses. Owned materials are not free. A range, or "at least" when the upper end is open. |
| Cash needed now | only what is bought. Owned and collected materials are not in it. |
| Buy ingredients directly | the baseline: every lacking material bought, nothing made beyond the queue. Shown only when no price is missing. |
| Savings / Potential savings | `Savings`, "at least X", only when the planner says the plan is certainly cheaper (the ranges do not overlap). Otherwise **Potential savings**, "about X" (the lower bounds' difference, not a promise); "None found"; or "Unknown" when a price is missing (no figure is invented). Not a profit: selling prices are not part of it. |

### 14.5 The Shopping adapter (`Strategy.Adapt`)

It turns the planner's result into `Shopping.Plan`'s row shape without changing the planner's output. Per plan item: **make** rows (`make = { planned = true, rec, crafts, made, surplus, reagents }`), **buy** rows (the options come from `Shopping.BuyOptions`, so the tooltips, cost words and source buttons are the old ones), **collect** rows (from `plan.collect`, with the stock's age and limit). `need` is the plan's combined demand for the item, `short` the part of the queue's own shortage, `extra` what is bought for made materials (`reagentOnly` when it is all of it), `forNames` the crafts that use it. A source with no usable price is shown as "No source" (as before) unless the player chose it. A material that is both owned and short appears as a collect/in-bags part plus one buy part: the split is the rows, not one flattened badge.

**Manual choices stay authoritative.** `Session.PickSource` is unchanged; the choice goes to the planner as a pick. A valid choice restricts the item; an impossible one is reported (`pickLost`, "Your earlier choice is no longer possible") and changes nothing else. **What Workshop would suggest** for an item the player chose a source for comes from the `suggest` plan (the same queue with no choices), because a valid pick removes the item's alternatives from the planner's own result. While that plan runs the Suggested tag is blank.

### 14.6 Adding the plan to the queue

**Nothing changes the queue without the confirmation.** The flow:

1. **Add optimized plan** (strategy view, or a Make row in Shopping) opens the confirmation and requests the `confirm` plan: the queue as it is now plus, for Opportunities, the chosen recipe once if it is not queued.
2. It lists the recipes and crafts (`Strategy.Ops`: the planner's crafts in an order that can be done, then the player's own recipe last). While the plan runs the button is disabled.
3. **Add to plan** calls `Session.ApplyOptimized(key, rec)`, which rebuilds the key and **refuses ("Your plan changed while you were looking") unless it equals the key the list was made for**, then `Queue.AddBatch`.
4. **`Queue.AddBatch(ops)` is all or nothing.** It validates everything first (held by a newer version; each recipe known, with materials and a fixed output; no recipe twice; no entry above 999 crafts; room for the new entries; at most 40 operations), changes the list in memory and saves **once**; if the save fails only this call's own changes are undone. A recipe already queued gets more crafts on the same entry.
5. **Nothing is counted twice.** The plan already credits queued crafts, so what is added is only what is missing; after adding, the next plan has no crafts to add (a test checks this, and that raising an entry adds only the difference).

Adding crafts to the queue crafts, buys and visits nothing.

### 14.7 The old planner

`Shopping.Plan` and `Session.Shopping` are untouched and are the fallback (14.3). `Session.AddSubcraft` is still used for a basic list. A test checks that the multilevel and one-level plans give the same spending for the one-level chain, and the simulator scenario's hand-calculated Shopping rows (Peacebloom, Copper Ore, Tin Ore, the spending line) pass unchanged on the multilevel plan.

### 14.8 Layout and the approved mockups

The left navigation, window shell, header and footer are unchanged. The mockups are 1586 x 992 and the Workshop window is 1200 x 700 units, so the layout follows their hierarchy, not their pixels.

- **Opportunities:** the details are wider (400 units), the three money boxes are one row (Cost to make, Sell price, Profit before fees), the Crafting strategy block follows, the materials of one craft sit **beside** the market facts, and the price history has the full width under both. The history keeps the full width under both columns and a height of its own; its exact height was not measured (the simulator screenshots show it, with its caption and the "More scans needed" note, at roughly the size it had).
- **Crafting Plan:** the chosen-craft panel is 126 units (was 164); the strip is 40 units; the materials list shows about four rows and scrolls.
- **Shopping:** as before, plus View strategy and the plan's status in the bar.

Differences from the mockups, on purpose: the mockups' "Beats buying sub-parts (56 30)" and the planned-cost badge are not drawn (the comparison is in the strategy figures); the Crafting Plan page has a strip and per-row notes, not a second panel with the ordered steps (those are in View strategy); the numbers in the mockups are illustrative and some are inconsistent.

### 14.9 Performance (offline, plain Lua 5.1 on the development machine; not the game's figures)

`measure_p2` (a scratch script over `Strategy.Request` and `Pump`; median of 5):

| plan | slices | total | the request's first call (3 slices) | longest slice |
|---|---|---|---|---|
| one recipe, one subcraft (Opportunities) | 1 | 0.1 ms | 0.08 ms | 0.06 ms |
| A7's 480 materials, buy only | 151 | 13 ms | 4.7 ms | 3.9 ms (first run; GC) |
| 480 materials, each from 2 recipes over 3 shared | 569 | 100 ms | 2.6 ms | 1.4 ms |

The heavy plan therefore takes about 570 frames (about 9 s at 60 fps) in the worst case, and no frame does more than the first call's 3 slices (about 3 to 5 ms) or one slice (about 1 ms). A page never calls `CP.Plan`. Memory: results are kept per slot (at most 8 keys) and dropped on a change or when the window closes; the heap grows by the planner's short-lived tables (P1 section 11).

### 14.10 Evidence

- **Unit-tested:** `tests/test_workshop_strategy.lua` (words, the adapter against the one-level plan on the same chain, choices and the suggestion, jobs: slices, cancelling, stale results, two slots, failure, the last list shown as not current; fallback; one recipe; preview without a change; apply, refused after a change, nothing counted twice, raising an entry; invalidation by bags, prices, scan end, crafts, guild bank and choices; mixed bags, bank and bought; `Queue.AddBatch`: capacity, limits, duplicates, an unsaved queue, a held queue), `tests/test_workshop_strategy_ui.lua` (the three pages and the views on recording frames: Opportunities beside the unchanged estimate, planning, the strategy view, the confirmation, Crafting, Shopping, the fallback and updating states, closing during a plan) and the changed expectations in `test_workshop_window.lua` (the Make row's text and the confirmation) and `test_workshop_craftplanner.lua` (Strategy.lua is the one consumer).
- **Mutations:** 14 entries in `tools/mutations/workshop.py` (`crafting.strategy.*`, `crafting.queue.batch-*`): a saving called certain from the lower bounds, "verified" for a bounded plan, an open range shown as a total, a job reused for another key, another slot making a job stale, a collect quantity lost, reagent purchases shown as the queue's shortage, the suggestion equal to the choice, the player's recipe queued first, a key that ignores the bags, a doubled craft count, a failed batch that keeps its entries, a batch refused at exactly full, an entry refused at exactly 999.
- **Simulator-tested:** `tools/simlab/workshop.sh` (the real files over synthetic game data, handler-level clicks): the hand-calculated Shopping figures on the multilevel plan, the confirmation (the click alone adds nothing; accepting queues Smelt Bronze × 3), and 6 new poses (strategy, confirm, stratlong, planning, nodata, override).
- **Test Lab (developer only, not run in the client):** `crafting.strategy.adapter`, `.shared-allocation`, `.queue-wide`, `.stale-job`, `.bounded-frame-time`; they use a slot of their own and never touch the player's queue, choices or prices.

### 14.11 Real-client checks still needed (none done)

1. Open Opportunities with a scan and a multilevel recipe: the strategy block fills in without a visible stall; switching quickly between recipes shows "Planning..." and never another recipe's figures.
2. The price history is visible and readable under the facts and materials at the real window size and UI scale; the recipe names in the list are readable.
3. View strategy: the list scrolls; the numbers agree with the block; tooltips read well.
4. Add optimized plan: the confirmation lists the right recipes; Cancel changes nothing; Add to plan queues them once; the Crafting page and Shopping then show no further crafts to add; `/reload` keeps the queue.
5. Shopping: a manual source choice stays; "Updating the plan..." is not distracting; a bag change, a scan and an auction house visit refresh the list.
6. Click-reachability of every new control with the real pointer (the simulator only proves handlers).
7. A large queue (30 recipes): no hitch while the plan is worked out; closing the window during it is clean; combat and `/reload` during planning are harmless.
8. A real guild bank: the collect rows and their "shared stock" wording.

### 14.12 Limits and decisions

- The strategy of Opportunities is for **one craft on its own** (the queue is not part of it); the confirmation plans the whole queue plus that recipe.
- The make option of a bought material in Shopping is chosen from the known recipes (the planner's own alternative list is empty when a choice restricts the item), so its reagent lines carry quantities only.
- A made material's own cost is not shown on its row ("In the plan"): P1 gives the plan's total, not a per-item share. The Make row's tooltip no longer says "worth Xc".
- The suggestion for a chosen item needs the second (`suggest`) plan; with a very large queue and choices both plans run (one slice per frame each).
- The window is wider (1200 units) so the details and the list both stay readable; `R.FitToScreen` scales it on a smaller screen as before.

### 14.13 Verification results (2026-11-14)

- `./tests/run.sh`: 216 passed, 0 failed. `--group crafting` mutation campaign: 100 of 100 valid mutations killed (14 new entries).
- `tools/simlab/workshop.sh`: 19 launches, 479 checks each, passed with only the classified simulator limitations; the clean run's screenshots are in `wow-ui-sim-lab/artifacts/workshop-20261114-053748/` (`opps`, `strategy`, `confirm`, `planning`, `nodata`, `craft`, `craftlong`, `stratlong`, `shop`, `shopmix`, `override`, `small`). The simulator draws addon fonts in a fallback font and is not visual validation; control clicks are handler-level.

## 15. P2.1: simpler words, the default Add, vendors, the compact view and progress (built 2026-11-14, `feature/workshop`)

The owner's real-client review of P2 (four screenshots of Opportunities, the expanded strategy and the Crafting Plan; the screenshots themselves were not available to this session, so the work follows the written review and the code). **`CraftPlanner.lua` was not changed.** Planning stays in `CP.Job` slices; observation and progress are separate files (`Progress.lua`, `Notice.lua`); nothing new is written by the planner.

### 15.1 Prices: one planning figure

- `Strategy.CostText(range, money, lowerOnly, detailed)` is the one format every Workshop page uses (Opportunities, the strategy view, the Crafting strip, Shopping's rows, details and spending line). **Simple** (the default): an exact figure as it is; a range as **"from X"** (X is the planner's lower bound, the figure plans are compared on); an open upper end or a missing price as **"at least X"**. The range ("Between X and Y. Auctions may require buying whole stacks.") is in the tooltip. A lower bound is never shown without "from" / "at least", and no upper bound is invented. **Detailed** ("Price ranges" switch in the strategy view) shows "X to Y" inline. Saved as `TwichUIDB.workshop.view.prices = "detailed"` (absent = Simple); `Session.PriceDetail` / `SetPriceDetail`; read by `Strategy.detailed`.
- The underlying P1 figures (`summary.economic`, `cash`, `baseline`, `savings`) are unchanged; only their words are.
- Savings words: "Saves at least X" (the ranges do not overlap), "Could save about X" (lower bounds only, overlapping), **"Buying the materials directly is the best supported option."** (the plan is not cheaper) and **"Not enough price information to compare every route."** (a price is missing). "None found" is gone.

### 15.2 Opportunities and the strategy view

- **Opportunities' Crafting strategy** reads top to bottom: the status, what to do (`Strategy.Headline`: "Buy 3 materials", "Craft 2 intermediates · Buy 2 · Collect 1"), **Estimated cost** (large) beside **Gold needed now**, the saving line, View strategy. Buying directly is in the cost's tooltip.
- **The strategy view** (`ViewStrategy.lua`) is a checklist: the item and how sure the plan is, three figures (Estimated cost, Gold needed now, Savings), the headline, then **Craft**, **Buy from vendor**, **Buy from Auction House**, **No price yet**, **Collect**, **Already in your bags**, and **Other options considered (n)**, folded away until clicked. Row titles are the action ("Craft 3 × Bolt of Woolen Cloth", "Buy 1 × Fine Thread"); the subtitle is a few words. **"Good to know" is gone from the list**: what the plan assumes (`Strategy.Notes`) is behind a small **Notes** control.
- **Tooltips.** Every item row shows the game's own item tooltip (`UI.ItemTipLines`, one tooltip per hover, nothing added later) with Workshop's lines under it: makes, uses, left over, the price range and its age, and the buy-or-craft comparison.
- **Buy or craft** (`Strategy.Compare`): from P1's own alternatives, which are whole-plan totals with one item changed (P1 has no per-item share, so none is invented): "Buying it costs 42c more.", "Crafting it (Bolt) costs 18c more.", "… costs about 42c more, but the costs are too close to call." (overlapping ranges: never a certain saving), "… would cost 18c less; you chose …", the real reason for a way that is not possible, "a price is missing, so it can't be compared". The row's right side says it in two or three words ("saves 4s", "cheaper by 18c", "too close to call").

### 15.3 Add to crafting plan: the optimized plan by default

Opportunities' **Add to crafting plan** opens the strategy confirmation for the recipe (`StrategyView.Confirm(rec)`): the queue as it is plus this recipe, planned together, listing exactly the recipes and crafts ("2 recipes, 5 crafts in all") that **Add to plan** adds through `Session.ApplyOptimized` → `Queue.AddBatch` (all or nothing, checked again against the queue, nothing counted twice; P2's rules, unchanged). When no optimized plan can be made (the recipe's output or materials aren't known, or it makes a varying amount), the confirmation says so and offers **Add recipe only**, named as such (never presented as optimized). A queued recipe or a full queue is refused with the plain add's own explanation. Source choices are not changed by adding.

### 15.4 Shopping: Vendor, Auction, Craft, Collect

The list's source column says **Vendor** (balance-scales art), **Auction** (gavel), **Craft** (hammer), **Collect** (backpack) or **No source**; the row's second line and the details say it in full ("Buy from vendor", "Buy at Auction House", "Craft from reagents", "Collect from bank" / "guild bank"). The bar counts the four kinds. Split rows (some collected, some bought) stay separate rows, as in P2.

### 15.5 Show vendor: the nearest known seller

`Vendor.Places` used to put the merchant where the price was noted ahead of every distance, so in Undercity it chose Orgrimmar. Now (the NPC search's tiers): sellers with a comparable straight-line distance, nearest first (whole yards); then sellers on the player's map; then the rest. Ties: a seller the player dealt with, then the price's merchant, then the newest observation, then name and place. It returns how the first was chosen, and Show vendor's words say only that: "the nearest known seller", "a seller in this area", or how many others are known. Faction (`NpcStore.Usable`), the item in the merchant's seen stock, valid maps and coordinates are required as before (`Vendor.Sellers`). Unit-tested in `tests/test_workshop_vendor_places.lua` (the Undercity case, no local seller, several nearby, no position, an instance, faction, stale and reported entries, missing evidence, one NPC at two places).

### 15.6 The compact view and live Shopping (checkpoint 3)

- **Compact view** (`Compact.lua`, "Compact view" in the window's header) swaps the 1200-unit window for a 300-unit movable panel (clamped, Esc closes it, no position saved); **Full view** swaps back, and the queue, the page and the source choices are kept (the session is not reset while either view is shown). Two modes: **Travel** (each material still to get: "3 × Peacebloom", its source in a word, a **Map** button for a seller the NPC collection knows; one summary line "6 materials still needed: 5 to buy, 1 to craft"; no market valuations) and **Craft** (the queue in order: "Ready", "Missing 2", "Collect first"; "Next: craft 2 × …", the crafts left, and a bar of how many recipes are ready). It has no secure or protected control and never crafts, buys or moves anything.
- **Live updates.** While the window or the compact view is shown, a settled bag change (`BAG_UPDATE_DELAYED`) invalidates the plans (`Strategy.Bump`) and schedules **one** redraw `SETTLE` seconds later (0.2 s in the window, 0.3 s in the compact view); a burst of events is one redraw, nothing runs per frame, and a finished plan job redraws the compact view too (`Strategy.onChange`, `Storage.OnChange`). A material that is now covered leaves the list; one that is used or moved comes back. **How** it arrived (bought, collected, looted) is never claimed: the counts are what the bags hold. Source choices are kept while the material is part of the queue's needs (P2's rule). Hidden, neither view listens to anything.
- Unit-tested in `tests/test_workshop_compact.lua` (both modes, the pure row builders, six bag events = one redraw, a material that arrives and leaves, Full view keeps the queue, nothing runs when both are closed). Simulator poses `compact`, `compactcraft`, `tooltip` (an intermediate's item tooltip in the strategy view) and `smallstrat` (the strategy view at 1000×700).
