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
