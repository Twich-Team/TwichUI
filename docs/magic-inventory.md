# Magic Inventory

For anyone changing the feature. Code: `inventory/Rules.lua` (rules, destinations, recipients, the Never transfer
list, templates), `inventory/Items.lua` (item facts, categories, matching, reading the bags), `inventory/Plan.lua` (the
dry run: precedence, keep amounts, allocation, batches), `inventory/Design.lua` (the guild bank arrangement as a draft and its
translation to rules), `inventory/GuildBank.lua` and `inventory/GuildPlan.lua` (reading and previewing the guild bank), `inventory/Run.lua` (moving items when asked: mail, bank, guild
bank), `inventory/GuildRun.lua` (reviewing and carrying out a guild bank arrangement: Deposit and Organize bank), `inventory/Window.lua` (the review and the interface buttons), `inventory/Picker.lua` (choosing items from the
bags), and the settings page `TwichUI_Settings/pages/MagicInventory.lua`. Tests: `tests/test_magic_inventory.lua`
(rules and plan), `tests/test_magic_inventory_run.lua` (moving), `tests/test_magic_inventory_ui.lua` (review, buttons,
chooser), `tests/test_magic_inventory_settings.lua` (the page), `tests/test_magic_inventory_guildrun.lua` and
`tests/test_magic_inventory_guildrun_ui.lua` (the guild bank run and its panel), with the stand-ins in `tests/mi_mock.lua` and
`tests/mi_guildsim.lua`.

**Nothing here has been tried in the game.** No mail has been sent and no item moved by it. See "In-game checklist".

## What it does

The player makes rules: which items (categories as the game files them, quality, equipment or not, binding, and lists
of items to include or never include), what happens to them (Send by mail, your bank, a guild bank tab, Keep in bags,
Never transfer), and how many of each to keep in the bags. A bank or guild bank rule also says which way: **Deposit extras**
(above the keep amount), **Withdraw to top up** (take whole stacks out until the bags hold the keep amount, never more) or
**Balance both ways** ("Withdrawing", below). With the feature on, opening a mailbox, the bank or
a guild bank shows a small **Magic Inventory · N stacks** button just above that window's top right corner (the guild bank has its
own panel instead: "The guild bank at the bank window"). Clicking it opens the review. Nothing moves until the player presses an action in the review:

- **Mail:** "Prepare mail 1 of 2 to Bankalt" attaches up to 12 stacks in the game's Send Mail window (where the player
  can see them); "Send mail 1 of 2 to Bankalt" sends exactly that mail. Each mail is two clicks; one recipient per mail.
- **Bank:** "Deposit 8 stacks" moves them one at a time, each confirmed by the game before the next; "Withdraw 2 stacks"
  takes what withdrawing rules top the bags up with, the same way.
- **Guild bank:** the panel at the bank window (Deposit, Organize bank, Arrangement..., and Withdraw with a withdrawing rule), below.

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

A rule: `{ id, name, enabled, kind, dest, cats, qualities, equip, bind, include, exclude, keep }`, plus `flow` on bank and
guild bank rules (`"deposit"` | `"withdraw"` | `"balance"`; absent or unknown reads as `"deposit"`, so an older TwichUI reads a
withdrawing rule as a depositing one and keeps it rather than dropping it; an arrangement rule is always `"deposit"`), `stack` on guild
bank rules and `design`, `place`, `rest` on the arrangement editor's guild rules ("The arrangement editor") (`inventory/Rules.lua`
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

## The rules table (settings page)

"Your rules" is a table, one row a rule in priority order: grip, number, on/off, Name, Items, Action, Where, Keep, then Up, Dn,
Edit, Copy and Delete. Rows are banded; a cell is one line cut off with "..." (the row's tooltip has the full Items,
Destination, Keep, target stack size and any problem); "Where" turns amber when a destination is missing. A row is dragged
by pressing on it away from its controls: a virtual drag (`MagicInventoryDrag.lua`, a label follows the pointer, nothing
real is picked up) with a line showing where the rule will land, and the page scrolls near the view's top and bottom
edges. Letting go on a row calls `MI.MoveRuleTo(id, place)`; letting go anywhere else changes nothing, and hiding the
page ends the drag. Up and Dn stay for one-step moves. Tests: `tests/test_magic_inventory_settings.lua`,
`MoveRuleTo` in `tests/test_magic_inventory.lua`. Not tried in the game: how the rows look at the real font sizes, and
the edge scrolling.

## Withdrawing (`MI.BuildWithdraw` in `inventory/Plan.lua`; the guild bank's in `inventory/GuildPlan.lua` and `inventory/GuildRun.lua`)

A bank or guild bank rule with `flow` **withdraw** or **balance** tops the bags up to its keep amount (its **target**, which it
needs: without one it can't be turned on, "no-target"). Decided per item, for the bank that is open:

- **Which rule:** the first enabled rule of that kind that withdraws and matches the item (a guild bank rule only from its own tab).
  Rules that deposit or mail don't decide withdrawals.
- **Protections:** the Never transfer list and an enabled Never transfer rule block withdrawals too (nothing on them moves either way);
  the rule's own Never include list; a locked stack or one whose lock the game didn't say. A soulbound item may come out of your
  own bank (it is going to you).
- **How much:** target minus what the bags carry now. **Whole stacks only, never past the target:** the bank's stacks are taken
  largest first while each still fits. With 25 carried, a target of 40 and stacks of 20, 20, 10 and 5, the 10 and the 5 come out
  (40). With 30 carried and only stacks of 20, nothing comes out (50 would pass 40), and the review says "Short by 10: only whole
  stacks are taken, and the next stack would go over 40". What isn't in the bank stays missing.
- **No ping-pong:** every enabled rule that withdraws counts its target as a keep amount for the item (Precedence, step 4), so a
  deposit or mail rule never sends away what a withdrawing rule tops up. A rule that only withdraws never owns an item for deposits
  or mail; a balance rule owns it as a depositing rule does.
- **Balance:** above the target it deposits (as Deposit extras), below it withdraws; never both for one item at once.

**At your bank** (`Run.lua`, the review's "Withdraw from your bank" group): only while the bank is open (its bags are read then:
`C_Bank.FetchPurchasedBankTabIDs`, `C_Container`); the settings' Preview lists no withdrawals. Each stack: found again in the bank
by item and count, judged again, and **skipped** when the bags now carry so much that it would pass the target (the bags may change
after the review); then picked up and put on a bag stack of the same item with room, else an empty slot in a bag that can hold it.
Confirmed when the bank slot no longer holds it and the bag slot shows the right count. No room: "your bags are full", it stops.

**At a guild bank** (the panel's **Withdraw**, shown with an enabled withdrawing rule whose tab is in this guild; GuildPrep reads the
bank for it as it does for an arrangement): `MI.CurrentGuildPlan("withdraw")` plans one move a stack from the rule's tab to the bags;
a rule whose tab is unread, hidden, renamed or can't be withdrawn from is reported, never redirected; the rank's remaining withdrawals,
where the game says them (the shown tab), cap the moves ("limit"). The review gives each move an empty slot of an ordinary bag (no
profession bags), as the bags are then; none left: "bags-full", left out. The run is the guild bank run (source tab shown, pickup,
place in the bag, both sides confirmed), and before each move checks the rule still withdraws, the item isn't on the Never transfer
list, and that the bags as they are now plus the stack stay within the target (otherwise it stops: "over").

Tests: `tests/test_magic_inventory_run.lua` (the bank), `tests/test_magic_inventory_guildwithdraw.lua` (the guild bank plan, review,
rights, allowance, full bags, a change mid-run), the Withdraw button in `tests/test_magic_inventory_guildpanel.lua`, the editor in
`tests/test_magic_inventory_settings.lua`. **Not tried in the game.**

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
   bags** rule, the target of every enabled matching rule that withdraws, and an enabled vendor restocking target for it. Counted over every carried stack of that item (protected
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
Nothing is withdrawn by a deposit (withdrawals are their own action: "Withdrawing"), no bank tab is bought, nothing else in the bank is moved.

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
  another addon draws that interface (a bag addon's bank). The guild bank no longer gets this button: its panel
  (`inventory/GuildPanel.lua`, "The guild bank at the bank window") replaces it, so two guild deposit paths never compete. The
  older whole-stack guild deposit in `Run.lua` stays in the code and refuses while a guild run is under way.

## Settings (`TwichUI_Settings/pages/MagicInventory.lua`, Everyday > Magic Inventory)

Feature card and switch, then: **Your rules** (on/off, name, Items, Destination, Keep, Up/Down, Edit, Duplicate, Delete
with a question), **New rule from a template** (Cloth to bank alt, Herbs to bank, Metal & Stone to bank (the game files
ore, bars and stone together), Uncommon BoE equipment to a friend, Custom items; each starts off; templates name no
recipient), **Preview** (the review from your bags, no actions), **Destinations on this character** (recipient for this
character, **All my characters** only when ticked, **Use the tab shown now** with the guild bank open, Rename, Clear here,
Remove), **Never transfer** (Choose from bags, Add by ID or link). The editor: Name, then 1 Items, 2 Destination, 3
Exceptions and keep, 4 Review (the rule in one sentence, why it can't be turned on yet, Turn this rule on), Save, Cancel. Step 2
asks **Which way** for a bank or guild bank rule (Deposit extras, Withdraw to top up, Balance both ways; choosing a withdrawing way
with no keep amount sets 20), and step 3 then calls the keep amount **Target in bags** (a withdraw-only guild rule has no target
stack size). The table's Action column says Deposit, Withdraw or Balance for those rules, and Where says Bank or the tab.

## Guild bank previews (`inventory/GuildBank.lua`, `inventory/GuildPlan.lua`, `pages/MagicInventoryGuild.lua`)

Milestone 1 of guild-bank organization: guild bank rules with a target stack size, and two read-only placement previews.
**Nothing here moves, picks up, splits, deposits or withdraws anything, switches or queries a tab, and no button does.**
The settings page (see "The arrangement editor" below) draws one slot grid (7 columns of 14, as the game draws a tab) for the
selected tab and a switch between what the bank held (Current), the design being edited (Design) and what the rules would
do (Preview), with a mark in a slot's corner (`+` new stack, `*` stack changes, `-` leaves, `!` blocked, `?` can't tell,
`~` short of its reserved quantity, `R` reserved slot, `A` placed automatically; the legend is under Details) and, under
Details, the rules that matched and why something is stopped or left alone.

**Rules** are the existing ones (`inventory/Rules.lua`): a guild bank rule has categories, quality, equipment, binding,
Also include / Never include, a keep amount and now `stack` (0 = no target, 0..9999, guild rules only, cleaned like the
other fields). The first enabled transfer rule that matches owns an item (`MI.Owner`, shared with `Plan.lua`); an item a
mail or bank rule owns, or no rule owns, is left alone. A rule's tab is its destination's tab *on this character*:
guild name + tab number + tab name (+ icon, to show). A rule whose guild isn't the current guild's, whose tab number is
missing, whose tab was renamed, or whose rank can't see or deposit in it is **blocked**; one whose tab hasn't been read, or
whose rights the game didn't state, is **unknown**. Nothing is redirected. Tab names and icons seen are kept per guild in
`TwichUIDB.magicInventory.guilds` (at most 8 guilds, 8 tabs) only so a tab can be chosen with the bank closed; nothing is
planned from them. Guild identity is the guild's name (the project's existing convention): two guilds of the same name
can't be told apart.

**Stack sizes.** The target is the final stack size: floor(total / target) stacks of that size and one smaller stack
for the rest. Only the same item ID that stacks (limit above 1) merges; a name never decides. A target above an item's own
limit blocks that item (never cut down); an unstackable item stays 1. In a deposit an existing stack below the target
receives items, one above it is left and the plan says Reorganize would split it. Pieces are chosen exact fit first, then
the largest whole piece, then the smallest split, so splits are as few as the numbers allow.

**Deposit** reads the carried bags (`MI.BuildPlan` with the guild context: the same protections, keep amounts and
whole-stack rule) and places them in the rule's tab; the bank's own items don't move. **Reorganize** reads only the bank
tabs that have been read, gathers each claimed item into its rule's tab and re-stacks it; nothing comes from the bags. A
placement needs a free slot (or a stack with room) at that moment: items are ordered so one leaving a full tab frees a
slot for another, and two full tabs that need each other's room are reported as needing space ("swaps and parking in your
bags are not used"). Keep amounts don't apply to a reorganize (they are about the bags). Locked stacks, tabs the rank can't
take from, and items the game hasn't described stay and say why.

**What the game gives** (Forever UI source, `Blizzard_GuildBankUI.lua`): `GetNumGuildBankTabs`, `GetCurrentGuildBankTab`,
`GetGuildBankTabInfo(tab)` -> name, icon, isViewable, canDeposit, numWithdrawals (0: the rank can't withdraw there),
remainingWithdrawals (-1 unlimited; kept current only for the tab shown), `GetGuildBankItemInfo(tab, slot)` -> texture,
count, locked, isFiltered, quality, `GetGuildBankItemLink`, 98 slots a tab, up to 8 tabs; events `GUILDBANKFRAME_OPENED` /
`_CLOSED`, `GUILDBANK_UPDATE_TABS`, `GUILDBANKBAGSLOTS_CHANGED`. The Blizzard UI only ever reads the tab it shows, after it
asks the server for it, so **only the shown tab is read, and only after `GUILDBANKBAGSLOTS_CHANGED` arrived for it**: the
game answers an unsent tab like an empty one, so this file never trusts a tab it was not told about (it stays *unread*).
It never calls `QueryGuildBankTab` or `SetCurrentGuildBankTab`: the player shows each tab. A tab is *live* (shown now),
*earlier* (read while the bank was open, another tab shown since), *closed* (read in a visit that ended) or *unread*; a plan
is `live`, `mixed` or `stale` by the tabs it used, and the page says so in words. A kept preview says it is out of date
when the rules or destinations changed (`MI.Generation`), the bank was read again, the bags changed (deposit), or the bank
closed; **Refresh preview** makes it again. The snapshot lives in memory only, is dropped on turning the feature off or
leaving the world, and is discarded when the guild changes.

**Not established, so never assumed** (each is a requirement of an operation in `plan.ops`, not a promise): splitting a
stack (`SplitGuildBankItem` exists; whether it behaves on Forever's realms, and how a stack split in the bag is taken, is
unchecked: `MI.SPLIT.guild` is false, so an operation that needs a split is listed and marked blocked); picking an item up
on one tab and dropping it on another (the Blizzard UI always passes the shown tab; whether the cursor survives a tab
switch, and whether the game allows it, is unchecked); whether a move between tabs, or a split, counts against the rank's
daily withdrawal allowance; swapping two stacks; parking an item in the bags. Each operation carries its source (bag slot
or tab/slot), destination, count, rule and what it needs (`split`, `withdraw:<tab>`, `deposit:<tab>`).

**The executor** is "Carrying out an arrangement" below (`inventory/GuildRun.lua`). Everything in this section is still read-only: the
preview never moves anything; only the run does, and only when the player confirms a review.

Tests: `tests/test_magic_inventory_guild.lua` (rules, precedence, stack sizes, deposit vs reorganize, capacity, rights,
unread / stale / guild identity, read-only, 150 random arrangements replayed one operation at a time) and the guild part of
`tests/test_magic_inventory_settings.lua`. Simulator: `tools/simlab/guild_bank_preview.sh` runs
`tools/simlab/scenarios/guild_bank_preview.lua` once per launch from synthetic data (item lookups, bags and a five-tab guild
bank that answer reads only; any mutating guild-bank call would raise an error). It validates the page and planner, not
the game's answers.

## The arrangement editor (`inventory/Design.lua`, `pages/MagicInventoryGuild.lua`, `pages/MagicInventoryDrag.lua`)

Milestone 2 of guild-bank organization: the player arranges a mock guild bank and the addon translates that into ordinary guild
bank rules. **Editing is design only: dragging, splitting and placing in the editor never moves, picks up, splits, deposits or withdraws an
item, switches a tab, or touches the game's cursor.** Items move only from the Preview's Deposit and Organize bank, after a review
and a confirmation (see "Carrying out an arrangement"). The existing review's Deposit never acts on these rules (see "Existing
deposit" below).

**What the player sees.** The tabs' own names and icons across the top, one slot grid for the selected tab, "Arrange items
here to choose where they belong.", "Editing is design only: items move only when you review and confirm Deposit or Organize bank in the Preview.", a Current /
Design / Preview switch and one primary button, Preview changes. Beside the grid in Design: a searchable tray of item references (what the bags and the
guild bank snapshot hold, plus what the draft already names), "Placed automatically in this tab" (the tab's shelf), Add a
category (the existing category list) and the selected item's actions. Details (closed) holds the reading, operations,
shortages, extras, conflicts, held-back items, the rules the editor left alone, constraints and the legend. One contextual line
says what just happened or why nothing changed.

**Editing.** A drop edits a DRAFT held in memory (`Design.New/Load`); nothing is saved until **Save arrangement**; **Revert**
discards; leaving the page or the window neither saves nor discards (the draft stays, marked "Unsaved changes"); a rule
change made elsewhere never throws edits away. An item dropped on a tab is assigned to it with automatic placement; on a
slot it becomes a reserved stack (default a full stack, never above the item's own limit). A reserved stack dragged to a slot
or tab moves; onto a stack of the same item they combine up to the item's stack limit (what doesn't fit stays in its slot);
another item's slot refuses. Shift-click (`IsModifiedClick("SPLITSTACK")`, as the game's guild bank slots do:
`Blizzard_GuildBankUI.lua`, `GuildBankItemButtonMixin:OnClick`) or the item menu's **Split stack** opens a small dialog
(1 to count-1), then the new stack is placed by clicking a slot or a tab; Esc, Cancel or never choosing leaves the draft
untouched. **Move...** / **Place...** and then a click is the non-drag way. **Return to automatic placement** drops the slot
and quantity and keeps the item in its tab. Dragging assigns that one item, never its category; categories go in through
**Add a category**. Every drag is virtual (`Drag.Start`: a picture follows the pointer; the drop is decided where the mouse
button is let go; a drag doesn't start while the player holds a real item, and the real cursor is never read for more).

**Saved as rules.** One guild bank rule per tab (`rule.design = true`; `Rules.lua` for the exact shape): `dest` the tab's
destination (this character's choice of guild, tab number, name and icon, as for any guild rule), `include` the items,
`cats` the categories, `place = { { slot, id, count }, ... }` the reserved stacks (one per slot, every id also in
`include`), `rest = { [id] = true }` the items whose extras beyond their reserved stacks go to this tab's free slots. Two
stacks of 5 and one of 10 of the same item are three entries, not one target size. `Load(Commit(draft))` gives the draft
back (tested), so there is no lossy step. Every other rule is kept exactly (the same table, the same place); new rules go at
the END of the list, so nothing above them changes priority. A rule the editor can't show faithfully (turned off, a
quality/equipment/binding filter, a Never include list, a keep amount, a target stack size, another guild's, a tab that was
renamed, no tab chosen, a rule of its own made on the rules list) is "advanced": never rewritten, listed under Details. Opening
the editor writes nothing. A rule is drawn only for the guild and tab it was made for (guild name + tab number + tab name:
a renamed tab or another guild blocks it). Because the tab is this character's choice (as for every guild rule), another
character of the same guild has to choose the tabs on the destinations list before the rules run there.

**What the planner does with them** (`GuildPlan.lua`, header comment; tests `test_magic_inventory_design.lua`):
- A reserved stack is a **target, never an order**: with too little stock the slot is filled as far as it goes and reported
  short (the Preview shows a dimmed ghost with `~` where nothing came; Details gives "150 of 200 available (50 short)");
  nothing is bought, taken from unrelated places, sold or discarded.
- A reserved slot is kept for its item: no other item is placed in it, an empty one included. A slot that holds another
  item is **not cleared** (no swaps): the reservation is reported blocked. An arrangement item that must leave first (it is
  reserved elsewhere in the same tab) moves first.
- **Overflow policy:** what is held beyond the reserved stacks goes to the free slots of the one tab that takes the item's
  extras, in stacks of at most the item's limit, merging into compatible stacks first. That tab is the one that lists the item in
  `rest`; with none flagged, the only tab that has the item; otherwise there is none, and the extras stay where they are, with
  the reason ("Extras go here" in the item's menu picks the tab). No room: they stay in the bags (or the bank) and it says so.
  What a blocked reserved slot is waiting for is kept, not scattered as extras.
- Only stack-compatible items merge: the same item ID and a stack limit above 1; a name never decides. A reserved quantity
  above the item's limit is blocked, never cut.
- Priority, protections and keep amounts are the existing ones: the first enabled rule that moves items owns the item. A
  broader rule above the arrangement keeps the item and the arrangement is reported as **overridden** (Details, and "N rule
  conflicts" in the summary); a broader rule below is reported as shadowed. Nothing is reordered or rewritten. The Never
  transfer list, quest, conjured, equipment-set, locked and soulbound protections apply to a reserved item as to any other.
- **Preview sources:** "From my bags" is the Deposit planning (bags only; the bank's own items don't move except that a
  compatible stack with room receives items); "Already in the bank" is Reorganize (bank tabs that have been read; nothing from
  the bags). Splits are listed and blocked while splitting is unchecked (`MI.SPLIT.guild` false), so a reserved quantity that
  needs part of a stack shows as blocked. Unknown (unread) tabs are never empty. A preview is labelled "From your unsaved
  design" when it used the draft; one older than the design says "Design changed. Refresh preview."; one older than the bank
  or bags says "Bank contents changed. Refresh preview."

**Existing deposit.** `MI.CurrentPlan` (the mailbox/bank/guild bank review and its Deposit) treats an arrangement rule as
needing attention ("design only: nothing is moved from it"): it deposits nothing for those items and, as for any owner, no
lower rule takes them. The review's whole-stack, empty-slot deposit cannot honour a slot or a quantity, so it is not allowed to
guess.

Tests: `tests/test_magic_inventory_design.lua` (the draft: drops, moves, splits, combining, refusals, 600 random edits;
rules <-> draft round trip, other rules preserved in place, saving and reopening in the game's own storage, a failed save
writes nothing; the planner: distinct stacks of one item, shortage, extras, ambiguity, no room, an occupied slot, conflicts,
unread tabs, reorganize including a stack that must leave first, 320 random plans for conservation and read-only) and
`tests/test_magic_inventory_editor.lua` (the page's handlers with stand-in frames: the first screen, drops, split dialog with
cancel and Esc, combine, the menu's actions, preview labels and the one-line stale messages, Save/Revert/leaving, a held item,
nothing picked up). Simulator: see `docs/simulator-lab.md`.


### Stack sizes and layouts (the usual way to arrange a tab)

A tab lists the items it takes (drop an item on the tab, or on any slot of it: a plain drop never pins a slot). Each automatic item has a
**stack size** (menu: *Stack size...*; default a full stack, never above the item's own limit) and each tab a **layout**:
*Packed* (from slot 1, no gaps), *One empty slot between items*, or *Each item starts a new column* (the bank draws 7 columns of 14). The
slots are the addon's business: items are laid out by name, then item ID, and the grid shows exactly where they will go. Saved in the tab's
rule as `sizes` and `layout` (`Rules.lua`); `Design.lua` `D.Layout` / `D.Pieces` / `D.Theory` are the pure functions the editor's picture and the
planner share.

**What the planner does** (`GuildPlan.lua` `CompileLayouts`): for each automatic item the stacks its quantity makes at its size (`D.Pieces`;
quantity is what is in every tab read, plus the bags for a deposit, less what is pinned) get slots from the layout, stepping over pinned
slots and over slots holding an item no arrangement rule claims (never moved out of the way). Those stacks are then treated exactly like
pinned ones (merged, split and moved by the same machinery, never swapped; a stack nothing can fill is not drawn). Pinned stacks are filled
first. The reports count the laid-out stacks as "extras placed", not as reserved stacks. Consequences to know: **Organize** moves the
stacks already in the bank to the layout's slots (a stack in slot 9 goes to slot 1 when the layout says so), and a quantity that
changes can move what follows it in Packed and Spaced layouts (Columns keeps each item's column fixed). Over a deposit the quantity is the
raw count in the bags, so keep amounts can leave a stack unfilled; it is simply not drawn.

**Tidying (Organize only).** Items already in an arrangement tab that no arrangement rule names are tidied too: merged into stacks of at
most the item's limit, sorted by name, and moved to the far end of the tab (the highest free slots), away from the arrangement's items at
the front. Only an item **all of whose copies are in that tab** is tidied (the planner gathers every copy of an item it owns into one tab, and
tidying must not pull items out of other tabs); an item another rule owns, one on the Never transfer list, a locked stack, an item the game
hasn't described, and tabs the arrangement doesn't manage are left exactly where they are, and are stepped over by the layout. Moves go
through the same machinery (no swaps; an item that has to leave first does; what can't be done is reported as blocked). A deposit never
touches what is already in the bank. Implemented as a hidden rule per tab ("Other items in tab N, tidied", `GuildPlan.lua`
`CompileLayouts`), appended last, in Organize plans only.

**Pinning** an exact slot is still there but out of the way: the item's menu has *Pin to a slot...* (list items) or *Place...* (tray items),
then a click on the slot. Existing pinned stacks keep working unchanged.

## The guild bank at the bank window (`inventory/GuildPrep.lua`, `inventory/GuildPanel.lua`, `inventory/GuildRun.lua`)

Milestone 4: the arrangement is used from the guild bank window itself. The editor is unchanged and still edits a draft only.

**The player's workflow.** Open the guild bank. If this character has a saved arrangement for the guild, a small strip appears just
outside the bank window (below it, else above it, else at the top of the screen): "Reading bank..." while the tabs are read, then
"12 stacks ready to deposit . 8 stacks to organize" with **Deposit**, **Organize bank** and **Arrangement...**. With no arrangement
it says so and offers **Set up arrangement** (opens the editor's page). Deposit or Organize bank makes sure every tab is current,
then puts up ONE review: the tabs it touches, the quantities, splits, how many moves cross tabs, what is not included and why, and
what is not read. **Start** is the approval of exactly that review. The block under the strip is deliberately short: a big word (Deposit, Organize, then
Depositing with a **progress bar** of confirmed stacks and the stack being moved, then the result), one short line, the items involved as icons
with their quantities (hover for names), and in amber only what needs a look ("2 between tabs", "1 left out", "tab 3 not read"). **Stop**
(and **Continue** when the game wants a click) are on the strip. The result (Completed, Partially completed, Stopped, Needs review) stays until
dismissed; **Details** (closed unless asked for) has the evidence, including that the bank window will show each tab in turn. Nothing moves because the bank opened, a tab was read or an event
arrived; the only things the panel does by itself are reading, and showing a tab to read it.

### What the Forever client shows, and what it does not (Forever UI source, `forever` branch)

Checked 2026-10-31 in `Blizzard_GuildBankUI.lua` and `Blizzard_APIDocumentationGenerated/GuildBankDocumentation.lua`:

| Question | Source | Finding |
|---|---|---|
| How is another tab requested, and when is it trustworthy? | `GuildBankTabMixin:OnClick`: `SetCurrentGuildBankTab(n)`, `UpdateTabs`, `Update`, then `QueryGuildBankTab(n)` (the log or the tab text instead when those pages are up). `GUILDBANKBAGSLOTS_CHANGED` is documented with **no payload** | A tab's items are requested by showing it (or asking again with `QueryGuildBankTab` for the shown tab) and are trustworthy only when that event arrived while it is shown. The event does not say which tab: an answer to an earlier request arriving after a switch cannot be told apart (not established; stated as a residual risk, and every move is also checked from reads) |
| Can code (not a click) show a tab? | `GuildBankFrameMixin:OnShow` runs `Tabs[1]:OnClick()`; `SelectAvailableTab` runs `BankTabs[n]:OnClick("LeftButton")` from an event handler | **Yes for the frame's own code.** `GuildBank.lua` `GB.Show(tab)` calls exactly that handler (never `SetCurrentGuildBankTab` alone, which would leave the frame out of step). Whether it also works for an addon is a real-client check |
| Do reads need the displayed tab to change? | `GetGuildBankItemInfo(tab, slot)` and `QueryGuildBankTab(tab)` take a tab, but the Blizzard UI only ever uses the shown one and the generated documentation has nothing on either | **No, in practice.** GuildBankSort (in `reference_addons`, no licence: only the call pattern was read) queries every tab with `QueryGuildBankTab(tab)` and reads them all, and the player reports it working on this client. So background reads use `GB.Query`: one tab at a time, the player's tab untouched (they can use the bank meanwhile). The event that answers still carries no tab, so an answer is taken only after the event AND a quiet `GB.QUERY_DWELL` (0.5 s); the residual risk is that an unanswered tab looks like an empty one. Only when a tab does not answer, and only when the player pressed Deposit, Organize bank or Read again, is it shown to read it (`GB.Show`, then their own tab again) |
| Cross-tab pickup / place / split with explicit tabs? | `PickupGuildBankItem(tab, slot)`, `SplitGuildBankItem(tab, slot, n)`: the UI passes `GetCurrentGuildBankTab()` every time; not in the API documentation | **Not used.** Every call names the tab that is shown at that moment. A move between tabs is: pick up in the source tab, show the destination tab (the cursor is not touched by the tab handler in the source), read it, place, then show the source tab again and read it |
| Acknowledgments and slot locks | `GetGuildBankItemInfo` -> texture, count, locked; `GUILDBANK_ITEM_LOCK_CHANGED`, `GUILDBANKBAGSLOTS_CHANGED`, `CURSOR_CHANGED` | a move counts only when a fresh read of a shown, read tab shows the expected count, unlocked, and the cursor empty. Between tabs: the destination right after placing, the source after its tab is shown and read again, before the next move |
| Hardware input / continuation | nowhere (no protection flag, no hardware-event flag for these calls); `ADDON_ACTION_BLOCKED` / `_FORBIDDEN` | **Unknown.** The first move starts inside the confirming click; if the game blocks a call with nothing done, the run asks for **Continue** (one move per click: the next known-safe operation, never a replay of an uncertain one). A call the game merely ignores is a timeout, not a claimed click restriction |
| Allowance | `GetGuildBankTabInfo` -> remaining | only current for the tab being shown, so it is checked at each pickup (the source tab is shown then); whether a move between tabs counts against it is unknown |
| Split | `SplitGuildBankItem` | the part must land on the cursor (inferred); its count is not readable, so a split is verified only after it is placed |

**How the guild bank opens and closes on this client.** `Blizzard_GuildBankUI_Bootstrap.lua` registers the frame with the player
interaction manager (`Enum.PlayerInteractionType.GuildBanker`, 10): `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` carry it.
`GUILDBANKFRAME_OPENED` / `_CLOSED` are only routed on the Burning Crusade client (`Blizzard_Game/TBC/EventRouting.lua`), so the first
real-client run never saw the bank close (the panel stayed) or open (no automatic read). `GuildBank.lua` listens to both pairs, and a bank
that only sends its items is treated as open; opening or closing twice is one. The panel also hides whenever `GuildBankFrame` is hidden.

### Preparation (`inventory/GuildPrep.lua`, reads in `inventory/GuildBank.lua`)

Opening the bank, a tab list change, a saved rule, a finished run and a player's request each ask for a **cycle** (any number of
asks is one, a short timer later). A cycle reads every tab the rank can see whose items are missing, from another visit, or older than
`GB.MAX_AGE` (120 s), without showing any of them (`GB.Query`; the tab shown is asked again where it is): one at a time, a wait of `READ_WAIT`
(3 s) each, at most `TRIES` (2) asks per tab per cycle (a third, showing the tab, only for a cycle the player started), at most
`MAX_AUTO` (6) cycles a visit by themselves, `GAP` (1.5 s) between cycles. A tab that does not answer is **not read**, never empty,
is not asked again by itself, and is named in the panel (**Read again** asks again). A tab the rank cannot see is never asked for. The
summary (two reviews) is rebuilt only when idle, coalesced (0.4 s), and not during a run. A tab's state is `live` (shown, read after
the game's last word), `earlier` (read in this visit), `closed` (an earlier visit) or `unread`; a visit that ended never counts.

Because nothing is shown, the player's own tab clicks, cursor, other pages and combat do not matter to a read; only a run starting
(`run`), the bank closing or leaving the guild stop it. If a cycle does have to show a tab (the last resort above) it ends at once, and waits `QUIET`
(4 s), when the shown tab is not the one it asked for, when something is on the cursor, in combat, or when the bank shows its log or tab text, and it
shows the player's tab again when it finishes. While it reads, the panel shows a progress bar ("2 of 5 tabs").

### Review and approval (`GR.Review`, `GR.Start`)

`GR.Review(mode)` builds the plan from the **saved** rules (`MI.CurrentGuildPlan`, no draft) and every tab that is read and current,
then replays it on those cells: a move whose source or destination is not what the plan assumed, or that depends on an excluded one,
is left out with its reason; a move that needs an unread or forbidden tab is left out (`tab-unread`, `tab-rights`) and its
dependents with it. It refuses when the bank is closed or shows another page, the guild isn't the character's, combat, something is on
the cursor, or a run or an older deposit is under way. The review lists the action, every tab it touches, the quantities, splits, moves
**between tabs**, what is not included, which tabs are **not read** (the bank is then never called organized), and says the run does
only the listed moves. Its **fingerprint** binds the guild, each touched tab's name and rights, the saved-rules generation, every move
with the identity and count in each source and destination, the excluded work and the unread tabs.

**Start** makes the review again. When every touched tab is shown or was read within `GR.START_AGE` (15 s) the fingerprints are
compared at once; otherwise the run's first step shows and reads those tabs again and compares then. If anything changed the run ends
with **Stopped** (`stale`), nothing was moved, and the result carries the NEW review, which the panel puts up to read and approve: a
changed plan is never substituted and never started. A review is good for 120 s and one use. A page event, a rules change or closing
withdraws a waiting review. Unsaved design edits are never used.

### The run (`GR.Start` onward)

One run at a time. Before a move: bank open on its item page, same guild, the tab shown is the one this run asked for (any other tab
is the player's: the run stops), names and rights as reviewed, allowance (source tab), rules unchanged, cursor empty, the source (and a
destination in the same tab) exactly as reviewed, the protections again for a bag source. The run shows the source tab (or, for a bag
source, the destination tab), waits until its items arrived, then `split`/`pickup`; the cursor must hold exactly that item. A
destination in another tab: that tab is shown (item on the cursor), read, **judged the same way** (a placing onto a changed slot would
swap, so it is never done unchecked), then `place`. Then the destination is confirmed, and for a move between tabs the source tab is
shown and read again and must show the expected count, unlocked, before the move counts and the next starts.

Events only cause a read (coalesced); waits are bounded (`GR.WAIT` 4 s, reads at 0.5 and 1.5 s, a late tab is asked for once more);
there is no polling. Moves are **paced**: the next starts `GR.GAP` (1 s) after the last was confirmed (the game dropped placements made
right after the previous one in the first real-client run; GuildBankSort does one move a second). A move is handed to the game at most
twice (`GR.TRIES`), and the second time only when a fresh read after `GR.SETTLE` (1.5 s) shows the first did **not** start (cursor empty,
source and destination exactly as reviewed, unlocked, both readable) and the full revalidation passes again; the result says "confirmed on
the second try". Anything else is never repeated: a move that may have happened is **uncertain**. Items are never taken to the
bags, swapped, parked, sold, destroyed or mailed. After the last move every touched cell is read again (each tab shown in turn) against
the approved result, then the player's tab is shown again; **Completed** needs that verification.

**Cursor.** Something else on the cursor stops the run and is never touched. An item the run holds that cannot be placed (the destination
did not take it, or its tab could not be shown or read) is put back only in its source (that tab is shown again first) and the put-back is
confirmed (Stopped, "put back where it came from"); if that cannot be confirmed the item stays on the cursor and the result says exactly
where it belongs (Needs review). `ClearCursor` is never called.

**Interruption.** Stop ends the run at the next move boundary (a move in flight is finished and confirmed, not undone). The bank closing,
combat, leaving the world, a rules change, another guild, rights or allowance changes, a tab the run did not ask for, the bank's log page,
a surprise at the source or destination, a timeout, a cursor change and an error all stop it; reads that cannot be trusted (a tab not shown,
a closed bank) make a move in flight **uncertain**, never "done" or "not moved". Nothing is saved: a close, a reload or a reopened bank
resumes nothing.

**Outcomes:** **Completed** (every move confirmed, the approved result verified, nothing left out of the plan), **Partially completed**
(every included move confirmed and verified, work was not included), **Stopped** (clean stop: N of M confirmed, the rest not started, with
the reason), **Needs review** (anything uncertain, an unresolved cursor, a mismatch, a timeout, a final check that did not match). Unread tabs
are always listed; they do not turn a verified plan into "partial" unless a rule needed them.

### Supported and not supported

Supported: deposit into several tabs in one approval; organize inside a tab and between tabs, including a move that must wait for another
(a stack leaving a reserved slot first), with splits and merges; independent work goes on when another tab is unread, hidden or refuses
deposits. Not supported (reported as blocked, never improvised): swaps, taking items to the bags and back, temporary parking, a slot holding
another item, moving past a withdrawal allowance, resuming, rolling back, reading a tab without showing it.

Tests: `tests/test_magic_inventory_guildprep.lua` (preparation: one tab at a time, delayed/missing/unread tabs, rights, the player's navigation,
cursor, log page, duplicate events, close/reopen, coalescing; the plan across tabs: dependencies, unavailable tabs, stale and changed approvals;
cross-tab acknowledgments: delayed, duplicate, missing, uncertain, a tab that never answers with the item held, navigation, closing, cursor,
Stop, refused calls and Continue), `tests/test_magic_inventory_guildpanel.lua` (the panel), `tests/test_magic_inventory_guildrun.lua` (the
review, confirmation and a run on one tab, preserved) and `_guildrun_ui.lua` (the settings page's Preview, which uses the same review and run),
over the scripted stand-in server `tests/mi_guildsim.lua` (`S.Tabs()` gives it the frame's own tab buttons). A stand-in that does what the test
says proves the addon's decisions, not what Forever does. Simulator: `tools/simlab/guild_bank_preview.sh` stages the panel (see
`docs/simulator-lab.md`).

## Diagnostics

Scopes `inventory.plan` (`MI.CurrentPlan`), `inventory.step` (one stack attached or deposited), `inventory.guildRead`
(`GB.Capture`, the guild bank read on its events) and `inventory.guildPlan` (a guild bank preview, asked for in the settings), `inventory.guildReview` (the review before a confirmation), `inventory.guildPrep` (the bank panel's summary, coalesced, never during a run), `inventory.guildRun` (one move handed to the game, only during a confirmed run), `inventory.designTray` (the arrangement editor's item
references, rebuilt when the bags or the bank changed while the settings are shown),
in `DX.OPS` and `docs/diagnostics.md`. Gauges `inventory.frames` (review rows and buttons), `inventory.listeners`,
`inventory.itemCache` (bounded at 512), `inventory.guildBank` (slots held by the snapshot, at most 784), `inventory.design` (the arrangement draft and tray references held), `inventory.guildRunState` (moves held for the run and the last result), `inventory.guildPrepState` (summary, problems and waiting callbacks held), `inventory.guildPanel` (the panel's frames). No new load-on-demand addon. Reports hold no names, recipients or items.

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
- Whole stacks only, both ways: a withdrawal may end under its target rather than split a stack. The account bank isn't a
  destination or a source, and nothing is withdrawn from mail.
- Withdrawing from a bank or guild bank has been run only against stand-ins: whether `PickupContainerItem` from a bank slot onto a
  bag slot, and `PickupGuildBankItem` then `PickupContainerItem` onto an empty bag slot, work from an addon outside a click is
  unverified, as is how many stacks a withdrawal counts against a rank's daily allowance.
- A recipient is checked for its form only. Whether it exists, accepts mail, or who plays it isn't known.
- Disenchantability isn't checked: the template says "Uncommon BoE equipment", nothing more.
- Rules aren't exported or shared.
- The guild bank run (Deposit and Organize bank) has been run only against stand-ins. Whether Forever accepts `PickupGuildBankItem`,
  `SplitGuildBankItem` and `SplitContainerItem` from an addon, outside a click, for a split stack, and what it does with a locked
  slot or a merge are unverified, and so are showing a tab from addon code, a cursor held across a tab switch, and whether a move between
  tabs counts against the allowance (see "The guild bank at the bank window").
- The arrangement editor edits a draft only. Real pointer dragging, Shift-click and how the editor looks are not verified (the
  tests and the simulator drive handlers, not a pointer). An arrangement is tied to this character's choice of guild bank tabs
  (as every guild rule is); a second character in the guild chooses the tabs on the destinations list before the rules run
  there. A reserved slot that holds another item is never cleared, so a full bank rearranges only as far as free slots allow.

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
16. Guild bank previews (read-only; use a guild bank you may look at, and change nothing): open it and show tab 1, then tab 2:
    the settings page's **Preview changes** (From my bags) says the reading is current for the shown tab and *earlier* for the other, and
    a tab never shown is "not read", not empty. Close the bank: the preview says STALE and the guild bank was closed.
    Switch to a guild alt or another guild: the rules chosen in the first guild are blocked (guild changed). Rename a tab
    (a guild officer, or on a test guild): the rule says the tab was renamed. Check the counts match the game's own tab
    (slot positions, stack sizes) and that `GUILDBANKBAGSLOTS_CHANGED` arrives before the tab's items do (a slot that
    shows empty and then fills means the reading was too early). No item moved, the cursor never held anything.
17. Arrangement editor (design only; use a guild bank you may look at, change nothing in it): open Settings > Magic Inventory.
    The page shows the guild's own tab names and icons; opening it saved no rule (check the rules list). Drag an item from the
    tray onto a tab (it appears under "Placed automatically") and onto a slot (an `R` stack of a full quantity). Drag the stack
    to another slot, onto a tab, and onto a stack of the same item (they combine; leftovers stay). Shift-click a stack: the
    split dialog opens; choose 5, click a slot: the stack splits. Press Esc in the dialog, and Cancel after choosing a
    quantity: nothing changes. Right-click a stack: the menu offers Split stack, Move, Return to automatic placement, Remove.
    Pick up a real item from your bags and try to drag in the editor: it refuses and the item stays on the cursor. Throughout, no
    guild bank slot, bag slot or cursor changes (watch the real guild bank window).
18. Save arrangement: new rules appear last in the rules list, the rules above are untouched and in order; `/reload` and
    reopen: the same slots and quantities are there. Change a rule on the rules list while the editor has unsaved edits: the
    edits stay. Close the settings with unsaved edits and reopen: they are still there, marked unsaved.
19. Preview changes: "From my bags" and "Already in the bank" give a summary line; a reserved stack the bags can't fill shows
    a dimmed `~` ghost; a slot holding another item shows `!`; switch to another tab in the bank then back: "Bank contents
    changed. Refresh preview."; edit the design: "Design changed. Refresh preview." Make a broader rule above the arrangement
    (cloth to another tab): the Details list says that rule decides.
20. Guild bank panel (separately authorized; low-value items, tabs you chose, a guild bank you may use). Save a small arrangement (Linen
    to tab 2, Herbs to tab 3, a reserved stack of 10 Linen in tab 2 slot 5). Open the guild bank on tab 1: no click needed: the strip
    appears outside the window with a bar "N of M tabs" while it reads, and the bank window does NOT change tab (the tabs are read with
    `QueryGuildBankTab`); then "N stacks ready to deposit". Use the bank (click tabs, move items) while it reads: nothing should interfere.
    Note whether every tab's contents in the summary match the game's own view of that tab, and whether any tab ends as "not read" (that
    would mean the query did not work for it on this client).
21. Deposit: one review naming both tabs, nothing moved by Cancel. Start: watch each move land (a lock on the slot, then the item), the
    count rises only after each landing, the bank shows tab 3 for the herbs and your own tab at the end. Check both tabs slot by slot.
    **Open question:** does the first call inside the click work and the later ones outside it? If the strip shows "the game wants a
    click for the next move" with Continue, that answers it; note which call was refused.
22. Organize bank with a move **between tabs** (put Wool in tab 1 that belongs in tab 2): the review says "1 of them between tabs". Start:
    pick up in tab 1, tab 2 shows, the item is placed, tab 1 shows again to confirm. **Open questions:** does the cursor still hold the
    item after the tab switch; does the destination read show the slot as expected; does the move count against the daily allowance?
    If the item is not on the cursor after the switch the run must stop (Needs review) with nothing lost; report what the strip said.
23. Splits: a reserved stack of 10 taken from a stack of 20 must end as 10 in the slot and 10 left; any other amount must say **Needs
    review**, not Completed.
24. Stop during a run: it finishes the move in progress, then says Stopped with the counts. Close the guild bank mid-run, `/reload`, reopen:
    nothing resumes; the strip reads the bank again and needs a new review. Click another tab yourself mid-run: it stops at once.
25. With your own item on the cursor the review refuses. Change the bank between the review and Start (another member deposits, or you do
    from a second character) and wait over 15 seconds before Start: the run reads the tabs again and, if the plan differs, shows a NEW review
    and moves nothing. A rank with a daily withdrawal allowance: the run stops when it is spent and does not work around it.
26. The shared framed look (`FrameLook.lua`; the simulator's screenshots are structural, not colour or font review): the guild bank panel, the
    review window (**Magic Inventory** button at a mailbox or bank, or Preview) and the bag chooser share one frame and button style. Check at
    your UI scale and with EllesmereUI on and off: the frame's corners and rails join with no gap or overlap on every side; the header groove,
    close box, scroll bar and list recess sit inside the frame and nothing is clipped by the rails; buttons lift under the pointer, sink while
    pressed, go flat when unavailable, and never stay lit or sunk after the pointer leaves, after Start or Cancel hides them, or after
    they are disabled mid-click; tooltips and the whole button are clickable; dragging a window still moves it and Esc still closes it.
27. Withdrawing at your bank (low-value items): a rule **Withdraw to top up**, target 40, for a food; carry 25, put stacks of 20, 20,
    10 and 5 in the bank. Open the bank: the review has "Withdraw from your bank" with 2 stacks (the 10 and the 5). Withdraw: you
    carry exactly 40, and the stacks of 20 stay. With only stacks of 20 in the bank and 30 carried, nothing is offered and "Not
    withdrawn" says "Short by 10". Put the food on the Never transfer list: nothing is offered. Fill your bags: it stops, "your bags
    are full". **Open question:** do the pickups after the first work outside the click (the run stops if the game blocks them)?
28. Withdrawing at a guild bank (separately authorized; a tab your rank may withdraw from): the strip says "N stacks to withdraw" and
    shows **Withdraw**. Start: the source tab shows, each stack lands in an empty bag slot, both sides confirmed. A rank with an
    allowance of 1: one stack is offered and the other is "left out". Pick up more of the item yourself during the run: it stops
    ("over") rather than pass the target. **Open questions:** does a withdrawal count one per stack against the allowance, and does
    the panel fit its buttons at your UI scale (Read again, Withdraw, Deposit, Organize bank, Arrangement)?
