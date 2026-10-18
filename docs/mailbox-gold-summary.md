# Mailbox gold summary

For anyone changing the feature. Code: `auction/Mail.lua` (`R.MailGold`), the switch `modules.mailGoldSummary` (default on; `Core.lua`,
`Switches.lua`), the setting on the Auction House page (`TwichUI_Settings/pages/Auction.lua`, "Show mailbox gold summary"), the sharing group
in `setup/TwichConfig.lua` (with `auctionPosting`). Test: `tests/test_mail_gold.lua`. **Nothing here has been tried in the game.**

## What it does

Each time the mailbox opens a visit starts at zero. When it closes, one line goes to the player's own chat if money was taken:
`TwichUI: Collected 12g 34s 56c from mail.` It is everything the mail paid out (auction proceeds, money other players sent, COD payments
buyers made to the player), not a profit figure: deposits, fees and costs are not subtracted. Nothing is saved (no total, no history);
the only saved value is the switch.

## How money is attributed

| Signal | Used for | Source |
|---|---|---|
| `MAIL_SHOW`, `MAIL_CLOSED` | visit start / end | `Blizzard_APIDocumentationGenerated/MailInfoDocumentation.lua` |
| `PLAYER_LEAVING_WORLD` | a loading screen ends the visit | |
| post-hooks on `TakeInboxMoney(index)` and `AutoLootMailItem(index)` | a take was *requested* | the calls Blizzard's own `MailFrame.lua` / `OpenAllMailMixin` make; add-on "Open All" buttons use the same two |
| `GetInboxHeaderInfo(index)` (money, COD) read at the moment of the call | the amount the request is worth | as `MailFrame.lua` reads it |
| `PLAYER_MONEY` + `GetMoney()` | the money *arrived*: a gain exactly equal to a waiting request | |
| `MAIL_FAILED` with no item ID | a refused take | `MailFrame.lua` treats an item ID as an item failure |

A request counts only when the matching gain arrives (oldest request first; the oldest several together if the game reports them as one
change). The message's position is read once, at the call, and never again, so shifting inbox positions cannot misattribute anything.
A request is dropped on `MAIL_FAILED` (no item), on switching off, on a loading screen, or after 4 seconds without a matching gain.
Messages with a COD charge never make a request. Postage, COD payments and any spending are losses and ignored; a gain that matches no
waiting request is ignored. `MAIL_SUCCESS` and `MAIL_INBOX_UPDATE` are not used: neither carries an amount, and the first is shared with sending.

## Visit boundaries and late events

Every request holds its own visit. Closing with requests still waiting finishes the visit once they are answered or expired (at most
4 seconds after the last take); the line is printed then, for that visit only. A new visit never receives an older visit's money. One
line per visit at most; a duplicate `MAIL_CLOSED` does nothing; a `MAIL_SHOW` with no close in between ends the earlier visit first.

## Limitations (conservative on purpose)

- A gain of exactly a request's amount from another source within the wait would be counted. Practically only possible for a deliberate
  coincidence; a refusal or no-op ends the request first where the game says so.
- A gain merged with a loss or another gain into one `PLAYER_MONEY` event does not match, so that money is not counted (undercount).
- A take made through a reference to the original function that another add-on saved before TwichUI hooked it (TwichUI loads first,
  at `ADDON_LOADED`) is not seen.
- Money taken before the switch was turned on, or with the mailbox already open when it was, is not counted until the next visit.
- A `MAIL_FAILED` without an item that belongs to something else (a failed send) while a take waits drops that take (undercount).
- Whether the real client orders `PLAYER_MONEY`, `MAIL_FAILED` and `MAIL_CLOSED` as the test models is unverified.

## In-game checklist (use a throwaway character with small amounts; do not take or send real money to test)

1. Mail yourself (or an alt) a few copper in two or three letters. Open the mailbox, take one by the money button, close: one line with that amount.
2. Open again, take the rest by right/shift-click or an Open All button, close: one line with only the new amount (not the earlier one).
3. Open, take nothing, close: no line. Open, take only an item, close: no line.
4. Open, take money and close at once: the line appears by itself within a few seconds, once.
5. Close and reopen quickly after a take: the line for the first visit is not added to the second.
6. Send a letter (postage) and pay a small COD: neither adds to the total.
7. Turn the setting off (Auction House page): no line; on again: lines return, no reload needed.
8. Check `/reload` mid-visit: no stray line afterwards, and `TwichUIDB` has no totals (`/tui saved`).
