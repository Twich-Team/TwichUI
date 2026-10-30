# Magic Inventory

For anyone changing the feature. Code: `inventory/Rules.lua` (rules, destinations, recipients, the Never transfer
list, templates), `inventory/Items.lua` (item facts, categories, matching, reading the bags), `inventory/Plan.lua` (the
dry run: precedence, keep amounts, allocation, batches), `inventory/Run.lua` (moving items when asked: mail, bank, guild
bank), `inventory/Window.lua` (the review and the interface buttons), `inventory/Picker.lua` (choosing items from the
bags), and the settings page `TwichUI_Settings/pages/MagicInventory.lua`. Tests: `tests/test_magic_inventory.lua`
(rules and plan), `tests/test_magic_inventory_run.lua` (moving), `tests/test_magic_inventory_ui.lua` (review, buttons,
chooser), `tests/test_magic_inventory_settings.lua` (the page), with the stand-ins in `tests/mi_mock.lua`.

**Nothing here has been tried in the game.** No mail has been sent and no item moved by it. See "In-game checklist".

## What it does

The player makes rules: which items (categories as the game files them, quality, equipment or not, binding, and lists
of items to include or never include), what happens to them (Send by mail, Deposit in bank, Deposit in guild bank, Keep
in bags, Never transfer), and how many of each to keep in the bags. With the feature on, opening a mailbox, the bank or
a guild bank shows a small **Magic Inventory · N stacks** button just above that window's top right corner. Clicking it
opens the review. Nothing moves until the player presses an action in the review:

- **Mail:** "Prepare mail 1 of 2 to Bankalt" attaches up to 12 stacks in the game's Send Mail window (where the player
  can see them); "Send mail 1 of 2 to Bankalt" sends exactly that mail. Each mail is two clicks; one recipient per mail.
- **Bank / guild bank:** "Deposit 8 stacks" moves them one at a time, each confirmed by the game before the next.

Off by default (`modules.magicInventory`, only an explicit `true` is on). Opening an interface never opens the review,
never prints anything, and never moves anything.

## Client facts, and where they come from (Forever 1.60.1 UI source, `forever` branch)

| Question | Source | What it shows |
|---|---|---|
| Which mail UI loads | `Blizzard_MailFrame.toc` (`AllowLoadGameType: mainline`; camelot is in the mainline family) | `MailFrame.lua` |
| Attachments per mail | `MailFrame.lua`: `ATTACHMENTS_MAX_SEND = 12` | 12 (read from the global, at most 12) |
| Attaching | `SendMailAttachmentButton_OnClick` → `ClickSendMailItemButton(id)` with an item on the cursor | `PickupContainerItem` then `ClickSendMailItemButton(slot)` |
| What is attached | `SendMailFrame_Update`: `HasSendMailItem(i)`, `GetSendMailItem(i)` → name, itemID, texture, count, quality | read after each attach and before sending |
| Postage | `GetSendMailPrice()` | the price of what is attached; shown once a mail is prepared, checked against `GetMoney()` |
| Sending | `SendMailFrame_SendMail` → `SendMail(name, subject, body)`; `MAIL_SEND_SUCCESS`, `MAIL_FAILED` (`MailInfoDocumentation.lua`) | success only from `MAIL_SEND_SUCCESS` with the attachments gone |
| After a send | `MAIL_SEND_SUCCESS` → `SendMailFrame_Reset` clears name, subject and body | so a mail is never prepared over the player's draft |
| Items to a stranger | `Blizzard_SecureTransferUI.lua`: `SECURE_TRANSFER_CONFIRM_SEND_MAIL` → the game's own dialog → `C_SecureTransfer.SendMail()`; `SECURE_TRANSFER_CANCEL` | waited for with no time limit; only the player answers it |
| Refundable attachment | `MAIL_LOCK_SEND_ITEMS` → `CONFIRM_MAIL_ITEM_UNREFUNDABLE` popup | the run stops; the player answers the game |
| Money, C.O.D. | `SendMailButtonMixin:OnClick` sets `SetSendMailCOD`/`SetSendMailMoney` | never called; a draft with money or C.O.D. refuses |
| Bank UI | `Blizzard_UIPanels_Game.toc`: `[Game]\BankFrame.lua [AllowLoadGameType camelot]` | `Camelot/BankFrame.lua`: character bank tabs are bags (`Enum.BagIndex.CharacterBankTab_1` = 6 ...) |
| Bank bags | `BankDocumentation.lua`: `C_Bank.FetchPurchasedBankTabIDs(bankType)` → BagIndex list; `C_Bank.CanUseBank` | deposit targets |
| Guild bank UI | `Blizzard_GuildBankUI.toc`: `[Family]\Blizzard_GuildBankUI.lua [AllowLoadGameType mainline]` | loads for camelot; `MAX_GUILDBANK_SLOTS_PER_TAB = 98`, `GetGuildBankTabInfo` → name, icon, isViewable, canDeposit, `PickupGuildBankItem(tab, slot)` |
| Guild vaults on Forever's realms | nowhere | **unknown**; the adapter only acts when `GUILDBANKFRAME_OPENED` fires |
| Item class, subclass, binding | `ItemDocumentation.lua` `C_Item.GetItemInfo` → `classID`, `subclassID`, `bindType` (`Enum.ItemBind`: 0 none, 1 on acquire, 2 on equip, 3 on use, 4 quest) | matching |
| Category names | `C_Item.GetItemSubClassInfo`, `GetItemClassInfo`; subclasses from `C_AuctionHouse.GetAuctionItemSubClasses` (the Camelot auction categories use it) | the game's own names; templates find their category from an example item (Linen Cloth 2589, Peacebloom 2447, Copper Ore 2770) through `GetItemInfoInstant` |
| A stack | `C_Container.GetContainerItemInfo` → `isBound`, `isLocked`, `stackCount`; `GetContainerItemQuestInfo`; `GetContainerItemEquipmentSetInfo` | hard protections |
| Splitting | `C_Container.SplitContainerItem` is documented | **not used**: how mail, bank and guild bank take a split stack isn't verified |
| Protected or hardware-only | none of these calls are marked protected in the documentation | **not verified in the game**: whether `SendMail` or the pickups work outside a click. Prepare, Send and Deposit start from the player's click; later stacks of a deposit or attachments of a mail follow events, not clicks. `ADDON_ACTION_BLOCKED`/`FORBIDDEN` stop a run |

## Saved data

| Where | Scope | Holds |
|---|---|---|
| `TwichUIDB.ui.magicInventory` | per profile | `rules` (list order is priority; at most 40) and `dests` (named places: `{ id, kind = "mail" \| "guild", label }`, at most 12). A destination is only a name, never a recipient |
| `TwichUIDB.magicInventory.chars["Name - Realm"][destId]` | per character | `{ recipient }` or `{ guild, tab, tabName }` |
| `TwichUIDB.magicInventory.shared[destId]` | account | `{ recipient }`, only when the player ticked **All my characters** |
| `TwichUIDB.magicInventory.never` | account | `{ [itemID] = true }`, the Never transfer list (at most 200) |

A rule: `{ id, name, enabled, kind, dest, cats, qualities, equip, bind, include, exclude, keep }` (`inventory/Rules.lua`
has the exact shape and limits). Reading never writes; an entry that can't be read is left out of the next write.
Nothing of a visit (plans, runs, results, what was left out) is saved, so nothing resumes after a reload, a logout,
combat or reopening an interface.

`Persist.lua` treats `ui.magicInventory` and `magicInventory` as containers (a non-table is dropped and rebuilt).
`ui.magicInventory` is part of backups as part of TwichUI's settings; `magicInventory` (recipients, guild tabs, the
Never transfer list) is in `Restore.OWN_LEFT_OUT`: a backup, which can be copied out as text, never carries names, and
a restore never changes where items go. Configuration sharing (`TwichConfig.LOCAL`) keeps `modules.magicInventory`
("acts"), `ui.magicInventory` and `magicInventory` ("other") local: rules and recipients are never in a share. Rules are
not exported in this version. If an export is added: send destination names, never recipients; import every rule turned
off and require each destination to be chosen on the receiving character (the per-character layout already makes an
imported rule need its recipient).

## Precedence (`inventory/Plan.lua`, tested in `tests/test_magic_inventory.lua`)

1. **Hard protections and the Never transfer list.** The account's Never transfer list and any enabled **Never transfer**
   rule protect an item whatever its place in the list. Per stack, for the owning rule's destination: a quest item,
   conjured (known IDs, or the game's own "Conjured Item" tooltip line for consumables and miscellaneous items; can't
   tell = kept), in an equipment set (can't tell = kept), locked (looked at again a few times during a run, then
   skipped), soulbound for mail and guild banks (fine for your bank), binding not said by the game for mail and guild
   (kept), lock state not said (kept), item details still loading (kept, asked for). **No "Also include" list overrides
   any of these.**
2. **A rule's "Never include" list:** the rule never matches the item (another rule still may).
3. **A rule's "Also include" list, or its filters** (all set filters must hold; categories are any-of): the rule matches.
   A rule with no filters matches only what it lists.
4. **Keep amounts:** for each item ID, the most of: the owning rule's "keep N of each", every enabled matching **Keep in
   bags** rule, and an enabled vendor restocking target for it. Counted over every carried stack of that item (protected
   stacks stay, so they count), never the bank or mail. Only what is above it may move.
5. **The destination must take each stack** (step 1's per-stack checks for that kind).
6. **Priority:** the first enabled rule in the list that moves items (mail, bank, guild) owns the item, wherever it
   sends it. Later matching rules are listed as shadowed. An item is **never passed to a later rule**: a mailbox never
   takes what a bank rule above owns (shown as "Reserved by ..."), and an unavailable destination (no recipient here,
   another guild) never reroutes anything; the owning rule is listed as needing attention.

**Whole stacks only.** Eligible stacks are taken largest first while they fit under (carried − keep); a stack that would
pass the keep amount stays, and the review says how many more than the keep amount stay. With splitting allowed
(`MI.SPLIT`, off everywhere) the last stack would be split to meet the keep amount exactly; the planner supports it and the
tests cover it, but no adapter splits.

## Moving (`inventory/Run.lua`)

One run at a time, serialized and event-driven. Before each stack: the interface is still open, out of combat, the
plan's generation is current (any rule, destination, recipient, tab or Never transfer change makes it stale), the stack
is found again (its old slot if it still holds the same item and count, else any carried stack of the same item and
count this run hasn't used) and judged again. The cursor must be empty before anything is picked up; an item the run
picked up and the destination didn't take goes back with `ClearCursor` (which returns it to its slot); something else on
the cursor is never touched and refuses the action.

**Mail:**
- Prepare is refused while the game's Send Mail window holds anything that isn't this run's (a name, subject, body,
  attachment, money or C.O.D.). The player's draft is never changed or cleared: the game itself clears the form after a
  send, so there is no "allow anyway".
- The Send Mail tab must be shown (TwichUI doesn't switch the game's tabs, to leave its frames untouched).
- Before Send: the attachments are exactly the prepared ones, the recipient is unchanged since the review, money covers
  the postage, no money or C.O.D. is set. The subject is what the game would write (the first item's name and count),
  the body is empty, and no money is sent.
- Outcomes: `MAIL_SEND_SUCCESS` with no attachment left is confirmed; with some left, uncertain. `MAIL_FAILED` is
  failed, with the game's red error message as the reason; the items stay attached (locked), so a new review can't send
  them twice. No answer within 20 s is uncertain. The game's secure confirmation has no time limit; declining it sends
  nothing and leaves the mail prepared (pressing Send again is a new decision, not a retry). A `MAIL_SEND_SUCCESS` while
  the mail is only prepared means the game's own Send button was used: uncertain, and the run stops. **Nothing is ever
  retried.**

**Bank:** a stack goes onto a bank stack of the same item with room for all of it, else an empty slot in a bank bag
that can hold it (bag family). Confirmed when the bag slot no longer holds it and the bank slot shows exactly the right
count; uncertain when it left the bag but didn't show up within 4 s; failed when it never left. No room stops the run.
Nothing is withdrawn, no bank tab is bought, nothing else in the bank is moved.

**Guild bank:** only into the chosen tab, in the guild it was chosen in, with that tab shown in the guild bank window
and its name unchanged, and only when `canDeposit` is true; empty slots only. Another guild, a renamed tab or no deposit
rights need review; another tab shown asks the player to show the right one. Nothing is withdrawn, no money is used,
no tab setting changes.

**Stopping:** the interface closing, combat, `PLAYER_LEAVING_WORLD`, the feature turned off, any rule change, a profile
change, `ADDON_ACTION_BLOCKED`/`FORBIDDEN`, Stop, no room, a refused step, an uncertain step. What was done stays done;
nothing is undone or offered as undoable. One line in your own chat per run: confirmed, didn't move, skipped, not
confirmed, and why it stopped.

## The review and the buttons (`inventory/Window.lua`)

- Groups by destination: `Send by mail to Bankalt` (stacks, mails, one recipient per mail, postage once prepared), `Deposit
  in your bank` (stacks, free slots), `Deposit in the guild bank of <Guild>, tab 2 "Mats"`.
- Each item: icon, name, count, stacks, the rule, the keep amount, and "N more than the keep amount stay" when whole
  stacks leave extra. **Leave out** removes it from this operation only (the rule is unchanged); **Review again** puts
  everything back.
- Needs attention (rules that match but can't run), Reserved by other rules, Staying in your bags (each reason), Shadowed
  rules, and the last transfer's results.
- Empty state: says why nothing is listed and offers **Manage rules**.
- The interface button: shown only while that interface is open and the feature is on; counted when it opens and when
  the bags change (coalesced), never on a timer; anchored above the game's window, or at the top of the screen when
  another addon draws that interface (a bag addon's bank).

## Settings (`TwichUI_Settings/pages/MagicInventory.lua`, Everyday > Magic Inventory)

Feature card and switch, then: **Your rules** (on/off, name, Items, Destination, Keep, Up/Down, Edit, Duplicate, Delete
with a question), **New rule from a template** (Cloth to bank alt, Herbs to bank, Metal & Stone to bank (the game files
ore, bars and stone together), Uncommon BoE equipment to a friend, Custom items; each starts off; templates name no
recipient), **Preview** (the review from your bags, no actions), **Destinations on this character** (recipient for this
character, **All my characters** only when ticked, **Use the tab shown now** with the guild bank open, Rename, Clear here,
Remove), **Never transfer** (Choose from bags, Add by ID or link). The editor: Name, then 1 Items, 2 Destination, 3
Exceptions and keep, 4 Review (the rule in one sentence, why it can't be turned on yet, Turn this rule on), Save, Cancel.

## Diagnostics

Scopes `inventory.plan` (`MI.CurrentPlan`) and `inventory.step` (one stack attached or deposited), in `DX.OPS` and
`docs/diagnostics.md`. Gauges `inventory.frames` (review rows and buttons), `inventory.listeners`, `inventory.itemCache`
(bounded at 512). No new load-on-demand addon. Reports hold no names, recipients or items.

## Known limits

- Nothing has been run in the game: attaching and depositing outside a click, the secure confirmation's events, bank
  bag families, `GetSendMailPrice` before sending, guild vaults on Forever, and `GetContainerItemEquipmentSetInfo` are
  all unverified.
- `ITEM_CONJURED` is a client string, not in the UI source. If this client doesn't define it, or a tooltip can't be read,
  no consumable or miscellaneous item moves ("Can't tell whether it is conjured"): the safe direction, but a real limit.
- `tools/sv_inspect.py --redact` hides account, realm and character names; a recipient saved under
  `magicInventory` is a value and isn't one of those. Read a report before sharing it.
- Stopping a mail run doesn't take prepared items back out of the game's Send Mail window: the player removes them or
  closes the mailbox (the game hands them back). The summary says so.
- Whole stacks only; the account bank isn't a destination.
- A recipient is checked for its form only. Whether it exists, accepts mail, or who plays it isn't known.
- Disenchantability isn't checked: the template says "Uncommon BoE equipment", nothing more.
- Rules aren't exported or shared.

## In-game checklist (use low-value items and a character you own as the recipient)

1. Fresh: Magic Inventory is off; opening a mailbox, bank or guild bank shows nothing new.
2. Turn it on, add **Cloth to bank alt**: it saves turned off and says it needs a recipient; it can't be turned on. Set
   the recipient (try `bad name` first: refused). On another character on the same profile: no recipient there.
3. Mailbox with 14 stacks of cloth: the button says 14 stacks (or what is above the keep amount); the review doesn't open
   by itself; nothing in chat. Open the review: exact recipient, 2 mails.
4. Type a name in the game's Send Mail window: Prepare is refused, your text stays. Clear it.
5. Prepare: 12 attachments appear in the game's window; nothing is sent; the postage shows. Send: one mail to exactly
   that character; the next mail is offered, not sent. Check the recipient's mailbox.
6. A recipient who isn't a friend or guild member: the game's own confirmation appears; decline: nothing sent; the review
   says so.
7. Close the mailbox while prepared: the items come back to your bags; the run says it stopped.
8. Bank: herbs rule; the button appears (also with EllesmereUI's bank); Deposit: each stack lands, merging into a stack
   with room; a full bank stops with the rest listed as skipped.
9. Leave out one item: it stays; the rule is unchanged after closing.
10. A soulbound item included by ID: never offered for mail; offered for the bank.
11. Keep 20 of 48: two stacks (20 and 8) move; keep 25: one stack of 20 moves and the review says 3 more stay.
12. Combat during a deposit: it stops before the next stack.
13. Guild bank (if your realm has one): choose a tab with **Use the tab shown now**; show another tab: Deposit asks you to
    show the right one; deposit into the right tab only.
14. `/reload` mid-way: nothing continues; the review must be opened and the action pressed again.
15. `/tui perf`: `inventory.plan` appears when an interface opens; no cost while none is open.
