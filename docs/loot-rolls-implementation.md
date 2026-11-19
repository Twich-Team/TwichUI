# Loot Rolls: implementation tracker

Branch `feature/loot-rolls`. This is the working record of the feature: what exists, what the client is known (and not known) to do,
how it is tested, and what has to be checked in the real Forever client before anything here is called working. Evidence labels as in
`CLAUDE.md`: **unit-tested**, **simulator-tested**, **screenshot-reviewed**, **real-client-tested**, **not tested**.

Nothing in this feature has been **real-client-tested**. Every statement below about the client comes from reading its UI source
(`../wow-ui-source`, branch `forever`, game type `camelot`) or from code already in this repository, and says so.

## What it is

Two parts, both off until the player turns them on.

1. **Loot cards** (`loot/Cards.lua`, switch `modules.lootRolls`): a card for each group-loot roll in the framed look (espresso and aged
   bronze) with painted Need, Greed and Pass icons, the item, its quality, an optional vendor price, a "Potential upgrade" mark from the
   existing upgrade judge, a countdown, and, when the game gives it, the other players' rolls and the winner.
2. **Loot rules** (`loot/Rules.lua`, `loot/Config.lua`, `loot/Auto.lua`): "when an item matches these conditions, choose Need, Greed or
   Pass", with a visible countdown on the card that the player can stop, roll early, or override by choosing. Automation has its own master
   switch, a separate permission for Need, and a separate permission for rules that ask about upgrades.

## Files

| File | Role |
|---|---|
| `loot/Rules.lua` | The rule engine. Pure: conditions, three-valued evaluation, first-match-wins, summaries. |
| `loot/Config.lua` | What is stored (`TwichUIDB.ui.lootRolls`): settings, place, rules; validation; change notices. |
| `loot/Roll.lua` | Watches the game's rolls. One record per roll; item facts; the only place a choice is sent; results from the roll history. |
| `loot/Auto.lua` | Turns a rule's decision into a countdown and, if everything still holds, one choice through `Roll.lua`. One timer for all rolls. |
| `loot/Blizzard.lua` | Lets the game's `GroupLootFrame1..N` step aside for a roll while a card shows it; gives them back at once otherwise. |
| `loot/Cards.lua` | The cards, their stack, the renderer shared with the settings preview. |
| `loot/Main.lua` | The switch (`LootRolls.Refresh`), the diagnostics snapshot. |
| `media/loot/*.tga` | Icons cut from the approved mockup by `tools/make_loot_roll_art.py` (sources: `assets/LOOT_ROLLS_*_MOCKUP.png`). |
| `tests/test_loot_rolls.lua` | Unit tests (fake world). |
| `tools/simlab/loot.sh`, `scenarios/loot.lua` | Simulator scenarios and screenshots. |

## Client API capability matrix

Source for every row: `../wow-ui-source/Interface/AddOns/` (branch `forever`). The Forever client is the `camelot` game type; per
`docs/magic-inventory.md` and `docs/class-bars.md` it loads the mainline family's frame code (`Blizzard_UIPanels_Game.toc` loads
`GroupLootFrame.lua` for `mainline`, which includes camelot; `Blizzard_FrameXML/Camelot/LootHistory.lua` overrides one method of the mainline
`LootHistory.lua`). `GetLootRollItemLink` and `GroupLootFrame*` are also used by `NaowhForever_BiS` (a Forever addon) and by `gear/Rolls.lua`
here, which is the nearest thing to runtime evidence in this repository.

| Capability | Status | Evidence and contract |
|---|---|---|
| A roll starts | **Confirmed in source** | `START_LOOT_ROLL(rollID, rollTime, lootHandle)`; `rollTime` is milliseconds (`GroupLootFrame_OnUpdate` compares `GetLootRollTimeLeft`, in ms, with the `Timer`'s `0..rollTime` range). `lootHandle` is nilable. |
| Item and eligibility | **Confirmed in source** | `GetLootRollItemInfo(rollID)` returns `texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired, canTransmog` (`GroupLootFrame_SetupItemDisplay`). Reasons index `LOOT_ROLL_INELIGIBLE_REASON<n>`. `GetLootRollItemLink(rollID)` (also used by `gear/Rolls.lua`). `C_TooltipInfo.GetLootRollItem(rollID)` (used by `gear/Rolls.lua`). |
| Time left | **Confirmed in source** | `GetLootRollTimeLeft(rollID)` (ms); `C_Loot.GetLootRollDuration(rollID)`; `GetActiveLootRollIDs()` (used by the game to re-open rolls after a reload). |
| Choosing | **Confirmed in source, not exercised** | `RollOnLoot(rollID, type)` with `0` pass, `1` need, `2` greed (`LOOT_ROLL_TYPE_*`, `Constants.lua`; the game's own buttons call exactly this). `3` disenchant and `4` transmog exist; **not offered**. A roll that `canTransmog` is not specially handled (the card offers Need, Greed, Pass only). |
| Roll accepted | **Unverified** | There is no "accepted" event. The game's own frame closes on `CANCEL_LOOT_ROLL`, which is sent when the roll is over *for you*. The card therefore treats a send as **sent**, and calls it **placed** only after `CANCEL_LOOT_ROLL` follows a send or the roll history shows the player's choice. Whether `CANCEL_LOOT_ROLL` really follows a placed roll in Forever is an in-game check (below). |
| Confirmation | **Confirmed in source, not exercised** | `CONFIRM_LOOT_ROLL(rollID, rollType, reason)` opens the game's own `CONFIRM_LOOT_ROLL` popup (`GameDialogDefs.lua`), whose accept calls `ConfirmLootRoll`. The card never answers it; it shows "Confirm in the game's window", stays open, and lets the player choose again if they cancel the popup. |
| Roll cancelled/expired | **Confirmed in source** | `CANCEL_LOOT_ROLL(rollID)`, `CANCEL_ALL_LOOT_ROLLS`, `LOOT_ROLLS_COMPLETE(lootHandle)`. |
| Other players' choices, roll numbers, winner | **Present in the API, unverified in Forever** | `C_LootHistory`: `GetAllEncounterInfos`, `GetSortedDropsForEncounter`, `GetSortedInfoForDrop(encounterID, lootListKey)` returning `playerRollState`, `rollInfos` (`playerName`, `playerClass`, `isSelf`, `state`, `isWinner`, `roll`), `winner`, `allPassed`, `isTied`; event `LOOT_HISTORY_UPDATE_DROP`. The camelot override only stops Blizzard's history window from opening by itself, which *suggests* the data exists; it proves nothing. **The history names no roll id**: a drop is matched to a roll by item link, and only when exactly one open roll could be it (never guessed; ambiguity is counted as `loot-history-ambiguous` and nothing is shown). |
| Hiding the game's frames | **Strategy chosen, not exercised** | Forever's `START_LOOT_ROLL` handler is a private one (`Blizzard_Game/Shared/EventRouting.lua`), so older tricks (`UIParent:UnregisterEvent`) do not apply. `GroupLootFrame1..4` are plain, unprotected frames parented to `UIParent`. `loot/Blizzard.lua` sets them to alpha 0 and turns the mouse off on the frame and its buttons while a card shows the same `rollID`, and restores both when the card goes. No Blizzard function is called, replaced or hooked (only `HookScript` on the frames, as `gear/Rolls.lua` does), so none of the game's own bookkeeping is touched and the player can never be left without controls. Side effect: the game's container still reserves its space. |
| Combat and protected actions | **Not an issue by design** | No secure frame is created or touched. `RollOnLoot` is not a protected function in the game's own (insecure) button handlers. Cards are plain frames; nothing is changed in combat that the game restricts. |
| Automatic submission | **Unverified** | The same `RollOnLoot` call as a click, made from a timer. Whether Forever accepts it from addon code is an in-game check. It is a clearly visible countdown, never silent, never Need without its own permission. |
| Disenchant / transmog rolls | **Not supported** | Out of scope. |

## Card states

`pending` (the player may choose) -> `scheduled` (a rule's countdown runs) -> `submitted` (a choice was sent; `placed` once the game closed the
roll for the player or the history shows the choice) -> `resolved` (the roll is over; results shown only if the game gave them); or `ended`
(`expired` or `canceled`, with no choice). A resolved card whose winner is the player is shown as **Won**. A card is removed after
`afterResult` seconds (a few seconds when nothing was chosen). Every state has words as well as color.

The card's close box on a live roll **hands the roll back to the game's own window** (stops a pending automatic choice and releases the
frame), never passes.

## Rule model

A rule: `{ id, name, enabled, action = need | greed | pass, match = all | any, delay (1..15 s), result (show it afterward), conditions }`.
Rules are read top to bottom: the **first enabled, complete rule that is not a definite "no" decides**. A rule that cannot be answered
("unknown": the fact is missing or the client does not say) **stops the search**: nothing decides and the roll stays manual (a rule above
might have matched, so a rule below must not speak for it). Actions of two rules are never combined. A rule with no condition, or with an
invalid one, is incomplete: skipped and explained in the editor. Negating an unknown condition leaves it unknown.

Conditions: item quality (is / at least / at most), item type (equipment, weapon, armor, recipe, consumable, ...), equipment slot (by the
game's `INVTYPE_*` and its own words), profession recipe (for one of my professions / one I can learn / one I already know / any), specific
item, armor type (cloth / leather / mail / plate / shield, from the item's class and sub-class), can I equip it, binding (when picked up / when equipped), potential upgrade (informational; only counts when upgrade-based rules are allowed), where
you are (outside raids, in raids, in dungeons, outside dungeons).

Recipe facts: the profession comes from `GetItemSubClassInfo(9, subclass)` compared with the player's skill lines (both the game's own words);
"already known" is the tooltip line equal to the game's `ITEM_SPELL_KNOWN`; "can learn" additionally needs the item to have no red
requirement line (`GearData.RedLines`). Without the tooltip those facts are unknown, not guessed.

"Can I equip it" is true for gear (anything with a slot) whose tooltip has no red line, the game's own way of saying class, armor type, weapon
skill or reputation is in the way (`GearData.RedLines`). A red "Requires Level" line is ignored (matched from `ITEM_MIN_LEVEL`), since the level
fixes itself. Items that are not gear are "can't equip". Without the tooltip it is unknown. "Armor type" is true only for armor (class 4) of
that sub-class; cloaks are cloth, so a cloth rule takes them too.

## Automation safety

* Master switch `auto` **off**; `autoNeed` **off** (a rule that would choose Need does nothing, and says so on the card); `autoUpgrade` **off**
  (a rule that asks about upgrades does nothing). `paused` stops everything without touching a rule; it is saved, so a reload does not resume it.
* No card, no automation: a countdown must be visible.
* A countdown is at least one second, ends at least a second before the roll does, and is never started with less than two seconds left.
* Everything is rechecked when it ends (switches, the rule still matching with the same action, Need permission, eligibility, time left);
  anything changed hands the roll back to the player. Editing or removing the rule, pausing, or switching automation off cancels it.
* Stop returns the roll to the player and is never a Pass. Choosing by hand cancels the countdown and sends that choice.
* One send per roll, ever (`sending` guard, state check, deadline check). A send that needs the game's confirmation can be sent again once.
* An unknown fact, an unloaded item, missing tooltip data or an unreadable profession leaves the roll manual.

## Failure and fallback

Any error while drawing hands every roll back to the game's frames (`Cards.lua` `Fail`), stops automatic choices, and is reported once through
`R.Fault`. Switching the feature off removes every card and listener and gives the frames back. `GetActiveLootRollIDs()` takes a roll that is
already open (a reload, or the switch turned on mid-roll) back in with the time it has left.

## Settings

`TwichUI_Settings/pages/LootRolls.lua` (the **Loot cards** tab: the switch, size and place, what a card shows; "Place the cards" opens a
sample card you drag, kept only on Finish, refused in combat and while a roll is open) and `pages/LootRules.lua` (the **Loot rules** tab: the
automatic rolling strip and switches, the rule list, the rule editor). The live preview beside the window is `Companion.lua`'s `loot` family:
the real card renderer (`LootCards.Draw`) over a made-up item (`LootCards.SampleView`), with a picker for the card's states (waiting for your
choice, a rule about to roll, choice sent, resolved with the rolls, ran out of time). It reads no roll and sends nothing; clicking it opens the
appearance settings. Saved data: `TwichUIDB.ui.lootRolls` (a profile's; `docs/profiles.md` rules apply). Sharing: the whole group stays local
(`TwichConfig.lua`, "acts"): a shared setup never turns automatic rolling on for someone.

## Evidence so far

* **unit-tested** (`tests/test_loot_rolls.lua`): rules, conditions, priority and unknown handling; configuration and rule editing; roll lifecycle,
  eligibility, one send per roll, confirmation, results from the history, ambiguity, secret values, missing APIs, reload adoption; automation
  (opt-ins, stop, override, pause, edits, deadlines, stale timers, duplicate events); frame handover and fallback; cards and failure.
* **simulator-tested** (`bash tools/simlab/loot.sh`, 13 views, all pass): manual, stack, auto, resolved, waiting, expired, unavailable cards;
  rules, builder, cards, narrow, empty settings views; placement (cancel keeps the place, Finish saves it, refused while a roll is open).
  Handler-level checks over synthetic rolls only (see `docs/simulator-lab.md`, "The Loot Rolls scenario").
* **screenshot-reviewed** (structure only: the simulator draws solid colors lighter and falls back to the game font): compared against
  `assets/LOOT_ROLLS_CARD_MOCKUP.png` and `assets/LOOT_ROLLS_RULE_BUILDER_MOCKUP.png`, three rounds for the cards and four for the editor.
  Corrected after review: the item line and the upgrade pill overlapped; the countdown text was clipped; result columns overflowed the card;
  list rows overlapped their status line; condition rows were too crowded (now two lines); the Need/Greed/Pass labels were clipped.
* **real-client-tested**: nothing.

## Remaining differences from the mockups

Cards: the frame is the shared framed look (`FrameLook`), simpler than the mockup's ornate gold corner brackets; the interior is that look's
espresso with rock grain, not painted leather; the countdown bar is flat green with a highlight line, not glossy; the winner banner has no
laurel ends (a laurel cut from the mockup carried part of its background and was dropped); the name uses Cinzel (the simulator shows the game font).
Rules page: the automatic rolling strip and switches are an addition (the mockup has none); conditions are two lines each instead of one so they
survive a narrow window; no "?" help button (each control has a tooltip); the delay is a slider, not a spinner; there is no "Allow manual
override" switch, because overriding is never optional here; "N of 24 rules" is at the top of the list; the live preview shows the whole card
(scaled), with a picker for its states, rather than a small card with a "Rules active" tag. On a narrow screen the shared preview overlays the
window, as it does for the other pages.

## In-game acceptance (not done)

1. With a group, switch Loot Rolls on, let an item drop that starts a roll: a card appears, the game's own roll window does **not**, and the
   item tooltip shows on hovering the icon.
2. Press Greed: the card says "Sending Greed", then "You chose Greed" (this proves `CANCEL_LOOT_ROLL` follows a placed roll), and the game's
   chat shows your roll. If the card stays at "Sending" until the roll ends, `CANCEL_LOOT_ROLL` does not follow a roll in Forever: report it.
3. After the roll ends: does the card show the other players, their rolls and the winner? Which of those, and when? (`C_LootHistory`)
4. An item bound on pickup: Need/Greed shows the game's own confirmation window; the card says to confirm there; cancelling it leaves the card
   usable.
5. Turn the feature off during a roll: the game's window is there again and works.
6. Automation: one Greed rule, master switch on, a matching green item: the card counts down visibly; Stop works; letting it finish sends Greed
   once and the game accepts it. Then Need: confirm it is refused until Need automation is allowed.
7. Recipe rules: confirm "already known" and "one of my professions" are read correctly for real recipe drops.
8. Equip and armor-type rules: on a character that wears cloth, a mail drop reads "can't equip" (red type line) and a cloth drop reads "can";
   an item above your level still reads "can equip"; a cloth rule takes cloth and not mail. (Unit-tested with a fake tooltip only.)
9. Two rolls at once, a roll that runs out, `/reload` in the middle of a roll.

## Remaining limitations

* The game's `GroupLootContainer` keeps reserving its space while a card is showing a roll.
* Rolls beyond the player's card limit keep the game's own frame (no card, so no automation for them).
* Disenchant and transmog rolls are not offered.
* Results depend entirely on `C_LootHistory` behaving in Forever as its API says.
