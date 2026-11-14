# Workshop P1: the multilevel crafting planner

`TwichUI_Workshop/CraftPlanner.lua` (`W.CraftPlanner`). Built 2026-11-13 on `feature/workshop`. It is a **pure engine with no consumer yet**: no window, session or tooltip code calls it, and Shopping keeps using `Shopping.Plan` (a test checks both). P2 will connect it to Opportunities, the Crafting Plan and Shopping.

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
