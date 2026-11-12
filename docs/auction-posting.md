# Sell from Bags: below vendor value

Code: `auction/Price.lua` (the comparison and its wording, pure), `auction/Window.lua` (the strip beside the price and the question),
`modules/Interact.lua` (`Confirm`'s `hold`). Art: `tools/make_vendor_warning_art.py` from `assets/vendor-warning-source.png`.
Tests: `tests/test_auction_price.lua`, `tests/test_auction_window.lua`, `tests/test_interaction.lua`.

## What it does

When the price you have entered lists an auction for less than a vendor would pay for the same items, a strip under the price says
so (an amber icon and "Below vendor value", with the price and the vendor value in the same units), and pressing **Post** asks
first: **Post anyway** or **Cancel**. Nothing is ever corrected, posted or sold for you, and nothing is remembered: each press of
Post on such a posting asks again.

It compares listed prices with vendor value only. It does not subtract the auction house's cut, add the deposit, or say anything
about profit; a price above vendor value is not claimed to be a good one.

## The price model

The page has one price, "Price each" (copper), and a quantity. What is compared is one auction against the vendor value of the same
items:

| Item | What Post lists | Compared per auction |
|---|---|---|
| commodity (cloth, ore...) | one auction of `quantity` items at price x quantity | price x quantity against sell price x quantity ("per stack") |
| other item (equipment...) | `quantity` auctions of one item at the price (no starting bid is set; the game starts it at the buyout) | price against sell price ("per item") |

`P.VendorCheck` also understands a starting bid and a buyout (either low; a missing buyout is not a zero buyout), because the
posting plan it takes allows both. The page has no bid box, so today only the buyout is ever compared; the bid wording is covered
by the pure tests, not by the page.

The vendor value is the sell price (the 11th value of `C_Item.GetItemInfo`, the way Blizzard's own sell frame reads it), per item.
Equal to the vendor value is not below it.

## Unknown, zero, known

- **Known and above zero:** compared.
- **Known zero** (a vendor pays nothing): nothing to compare, nothing is said.
- **Not available yet:** "Vendor value unavailable" in grey, no icon. It is never treated as 0 or as "safe", and never blocks Post.
  The item's data is requested once per visit; `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` (registered only while the page is
  open) bring it, and the strip redraws then. Nothing polls.

An empty or invalid price shows no vendor message at all; the usual checks speak.

## The question

Opens from Post only when the posting is below vendor value. It is TwichUI's usual confirmation (`Interact.Confirm`): Escape and
Cancel submit nothing and leave the item and prices as they were; the selection does not advance. Enter does not accept it (the
dialog sets no "enter clicks first button"). Accept is greyed for one second and a press that arrives earlier is refused with the
question left open, so a held key can't answer it.

The answer is bound to the posting it asked about: list item, quantity, price, duration and vendor value. The question is
withdrawn when any of them changes, when another item is chosen, when the page is hidden, or when the auction house closes; on
Post anyway the posting is prepared again from the page and refused ("changed while you decided") if it differs. One answer covers
the whole batch shown (for example three auctions of one item). Only after that does the existing posting path run, and the next
item is chosen where it always was: when the posting goes through.

## Icon

`media/auction/vendor-warning.tga` (64 px) and `vendor-warning-small.tga` (32 px, the one drawn at 22 units), built by
`tools/make_vendor_warning_art.py`. If the game refuses the file, the strip uses the game's own alert icon
(`Interface\DialogFrame\UI-Dialog-Icon-AlertNew`). The words carry the meaning either way.

## Not covered

No profiling scope or gauge: the work is a table lookup and a few string formats on edits the player makes, with no frame updates,
timers or retained state beyond one number (`vendorSeen`) and a small per-visit request set.

## Settings modernization (11 November 2026)

The previous settings page was two plain headers and switches, with the important rules buried in long tooltips.
It now presents two independent illustrated task cards: **Sell from your bags** and **Track money collected from mail**.
Each shows its actual module enablement, a short workflow explanation and an always-visible safeguard. Selling still
requires Post; mailbox money is explicitly not profit. Both existing switches retain their canonical settings APIs,
keys, defaults, profile behavior and reset scope. A secondary **Pricing and totals explained** disclosure separates
less frequent explanations from setup. No numeric threshold, item list, pricing formula or provider setting exists
to expose here; quantity, price, duration, searches and vendor warnings stay in the actual selling tab.

No companion was added: these settings do not customize an alert's appearance, and a fake auction/price preview
would be misleading. Missing price data is explained, never represented as zero or as a safe price. No current
auction state or fabricated total is displayed. Existing scales and ledger icon sheets, canonical walnut cards,
bronze disclosure controls and switches are reused; no new artwork or shared-component changes were required.
Runtime auction, mailbox, warning, confirmation and search code is untouched. Settings retain existing lazy page
construction in the load-on-demand settings addon; this introduces no startup events, timers or polling, and needs
no new diagnostic scope. No performance improvement is claimed.

### Permanent coverage

- `test_auction_settings.lua`: both canonical switch bindings, live On/Off summaries and visible safeguard text.
- Existing `test_auction_price.lua`: comparable/partial/absent results, vendor unknown versus zero and validation.
- Existing `test_auction_window.lua`: explicit posting, below-vendor confirmation, changed-posting cancellation,
  and skin available/absent stand-ins. These remain unit fixtures, not installed-addon acceptance.
- Existing `test_mail_gold.lua`: actual-received accounting, empty visits, toggle behavior and no retained visit data.
- `tools/simlab/scenarios/settings.lua`: actual page/card construction, each switch toggle/restore, collapsed and
  expanded disclosure, disabled pose, constrained scrolling, search, reopen and navigation cleanup. Handler input
  does not establish real mouse/keyboard hit regions. No auctions, bids, purchases or cancellations are performed.

Rerun focused scenarios:

```sh
bash tools/simlab/settings.sh auction
SIMLAB_SETTINGS_DATA='"off"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh auction
SIMLAB_SETTINGS_DATA='"advanced"' bash tools/simlab/settings.sh auction
SIMLAB_SETTINGS_DATA='"advanced"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh auction
```

**Screenshot-reviewed:** captures are local evidence under `../wow-ui-sim-lab/artifacts/`, excluded from commits.
The first render (`settings-20261111-124422/auction.png`) caught a fallback icon; it was replaced with the existing
ledger illustration. The expanded render (`124542`) exposed excessive wrapping in a narrow status-value column;
explanations were moved below short labels before rerendering. Default final view `124521` and disabled constrained
view `124601` were opened and inspected. Final expanded views are recorded below after review.

Real-client acceptance is pending: native fonts/localization, real pointer/keyboard, disclosure and reset prompts,
reload/profile persistence, Auctionator present/absent behavior, actual auction search/vendor data and mailbox totals.
No real-client acceptance or full transaction verification is claimed by these screenshots. No live SavedVariables
or deployed addon files were edited.

Final screenshot-reviewed evidence (all `auction.png`, folder prefix `settings-20261111-`):

| Folder | View | Handler/state checks |
|---|---|---|
| `124521` | Default enabled cards; corrected ledger art | 17 |
| `124601` | Both disabled, constrained viewport | 17 |
| `124648` | Expanded explanation, corrected label/detail layout | 17 |
| `124848` | Expanded constrained explanation, scrolled to its actual card | 19 |

The lab's raw native scroll range allowed an empty tail when used as a capture target (`124759`); targeting the
actual explanation card instead produces the reviewed constrained view. This does not establish native scrollbar
end-stop correctness; verify it in the client. Simulator fonts are substituted and API sources are older than the
installed Forever client. No simulator engine changes were made.

**Unit-tested:** the focused settings, price, posting-window and mail-gold commands passed. The settings test installs
erroring scan/transaction stand-ins and verifies that describing/editing configuration does not invoke them.
The initial full suite reported 188 passed / 1 failed because the intentional labels/rows changed the settings
contract snapshot. Its documented regeneration command was used; the reviewed fixture diff contains only Auction
House labels/tooltips/rows. Defaults, variables, write destinations, reset results and all other pages are unchanged.
Edited Lua files pass `luac5.1 -p`; final `git diff --check` passes.

Final full rerun: `./tests/run.sh` — **190 passed, 0 failed**, including the new settings test and reviewed contract.
