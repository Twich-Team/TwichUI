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
| `GetInboxHeaderInfo(index)` (money, COD) read at the moment of the call | the amount the request is worth; a missing COD value counts as none | as `MailFrame.lua` reads it |
| `MAIL_INBOX_UPDATE` (during a visit) + `GetInboxNumItems()` | the money each position showed at the last update, used once per position when the message already reads empty at the call (a post-hook cannot know the game has not cleared it yet) | |
| `PLAYER_MONEY` + `GetMoney()` | the money *arrived*: a gain exactly equal to a waiting request | |
| `MAIL_FAILED` with no item ID | a refused take | `MailFrame.lua` treats an item ID as an item failure |

A request counts only when the matching gain arrives: one waiting request, or several the game reported as one change. When more than
one set of waiting requests could explain the gain, the oldest set pays the chat total (V5). The message's position is read once, at the
call, and never again, so shifting inbox positions cannot misattribute anything. A repeated call for the same message (same position,
header and amount, no inbox update since) is a *spare*: never matched to money, it only waits out its expiry, which keeps V1's line
timing. After `MAIL_INBOX_UPDATE` a position can hold another message (Blizzard's Open All takes position 1 again after each paid mail is
deleted), so in-flight positions are forgotten at each update. A request is dropped on `MAIL_FAILED` (no item), on switching off, on a
loading screen, or after 4 seconds without a matching gain; while `C_Mail.IsCommandPending()` says a mail command is still pending it waits
a second at a time, never past 15 seconds.
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
- The remembered amount is per position and refreshed at each inbox update; if positions shift without an update, a stale amount could be
  read for a message that already reads empty. It still counts only if a gain of exactly that amount arrives within the wait.
- Whether the real client orders `PLAYER_MONEY`, `MAIL_FAILED` and `MAIL_CLOSED` as the test models is unverified.
- Two messages with identical sender, subject, days left and amount at the same position, taken again with no inbox update between, cannot
  be told apart: the second is a spare and its money is not counted. Blizzard's Open All waits for the update that follows each deletion.

## In-game checklist (use a throwaway character with small amounts; do not take or send real money to test)

1. Mail yourself (or an alt) a few copper in two or three letters. Open the mailbox, take one by the money button, close: one line with that amount.
2. Open again, take the rest by right/shift-click or an Open All button, close: one line with only the new amount (not the earlier one).
3. Open, take nothing, close: no line. Open, take only an item, close: no line.
4. Open, take money and close at once: the line appears by itself within a few seconds, once.
5. Close and reopen quickly after a take: the line for the first visit is not added to the second.
6. Send a letter (postage) and pay a small COD: neither adds to the total.
7. Turn the setting off (Auction House page): no line; on again: lines return, no reload needed.
8. Check `/reload` mid-visit: no stray line afterwards, and `TwichUIDB` has no totals (`/tui saved`).


V5 follow-up: complete positive batches through the 50-request inbox bound are
matched directly; partial subset search considers only amounts <= the gain and
never authorizes attribution when its 12-candidate window is incomplete. The
recorder-order deferral buffer now covers one inbox burst (50), while eight remains
the **invoice/component detail** cap. Mixed payments keep one Mail collected entry
and may expose securely reconciled seller components without counting extra cash
or inventing cost/profit. Diagnostics reasons include search-limit, detail-limit,
no-request and deferred-full. See the [V5 verification and limitations](workshop/gold-ledger.md#v5-follow-up-on-current-main-2026-11-21).
