# Magic Inventory

For anyone changing the feature. Code: `inventory/Rules.lua` (rules, destinations, recipients, the Never transfer
list, templates), `inventory/Items.lua` (item facts, categories, matching, reading the bags), `inventory/Plan.lua` (the
dry run: precedence, keep amounts, allocation, batches), `inventory/Design.lua` (the guild bank arrangement as a draft and its
translation to rules), `inventory/GuildBank.lua` and `inventory/GuildPlan.lua` (reading and previewing the guild bank), `inventory/Run.lua` (moving items when asked: mail, bank, guild
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

A rule: `{ id, name, enabled, kind, dest, cats, qualities, equip, bind, include, exclude, keep }`, plus `stack` on guild
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

**For the executor milestone** (not built): `plan.ops` and `plan.tabs[i].current/proposed` plus `plan.guild`, `plan.seq`,
`plan.generation` and each tab's name and reading are what an approval would bind to; execution must run one operation at a
time, recheck guild, tab names, rights, source and destination contents and an empty cursor before each, confirm the source
and destination counts from a fresh read (an event only says to read again), wait with a bound and stop on a timeout, an
unexpected change, lost access, a cursor the player used, or the bank closing, with no retry, no clearing of the cursor, no
rollback and no new plan after a partial run, and report confirmed / blocked / remaining / uncertain exactly.

Tests: `tests/test_magic_inventory_guild.lua` (rules, precedence, stack sizes, deposit vs reorganize, capacity, rights,
unread / stale / guild identity, read-only, 150 random arrangements replayed one operation at a time) and the guild part of
`tests/test_magic_inventory_settings.lua`. Simulator: `tools/simlab/guild_bank_preview.sh` runs
`tools/simlab/scenarios/guild_bank_preview.lua` once per launch from synthetic data (item lookups, bags and a five-tab guild
bank that answer reads only; any mutating guild-bank call would raise an error). It validates the page and planner, not
the game's answers.

## The arrangement editor (`inventory/Design.lua`, `pages/MagicInventoryGuild.lua`, `pages/MagicInventoryDrag.lua`)

Milestone 2 of guild-bank organization: the player arranges a mock guild bank and the addon translates that into ordinary guild
bank rules. **Design only: nothing here moves, picks up, splits, deposits or withdraws an item, switches a tab, or touches the
game's cursor, and no executor exists.** The existing review's Deposit never acts on these rules either (see "Existing
deposit" below).

**What the player sees.** The tabs' own names and icons across the top, one slot grid for the selected tab, "Arrange items
here to choose where they belong.", "Design only: your items will not move.", a Current / Design / Preview switch and one
primary button, Preview changes. Beside the grid in Design: a searchable tray of item references (what the bags and the
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

## Diagnostics

Scopes `inventory.plan` (`MI.CurrentPlan`), `inventory.step` (one stack attached or deposited), `inventory.guildRead`
(`GB.Capture`, the guild bank read on its events) and `inventory.guildPlan` (a guild bank preview, asked for in the settings), `inventory.designTray` (the arrangement editor's item
references, rebuilt when the bags or the bank changed while the settings are shown),
in `DX.OPS` and `docs/diagnostics.md`. Gauges `inventory.frames` (review rows and buttons), `inventory.listeners`,
`inventory.itemCache` (bounded at 512), `inventory.guildBank` (slots held by the snapshot, at most 784), `inventory.design` (the arrangement draft and tray references held). No new load-on-demand addon. Reports hold no names, recipients or items.

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
- The arrangement editor is design only. Real pointer dragging, Shift-click and how the editor looks are not verified (the
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
