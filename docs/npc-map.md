# Vendors and trainers

**TwichUI settings > Vendors and trainers** (`npcs/`; the switch is `modules.npcMap`, off until turned on; `/tui npcs`).
Written against the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the
game yet**: everything below is source-verified and covered by offline tests with stand-ins for the game
(`tests/test_npcs.lua`, `tests/test_npcs_map.lua`), not seen working in play, alone or in a group.

When you deal with an NPC (buy from it, train, use its bank, inn, auction house, stable or flight master), TwichUI notes
what it offered and where you stood, and the world map shows it by the kinds you choose: reagent vendors, ammunition,
class trainers and so on. Nothing is downloaded or guessed. Your list grows as you play, and other TwichUI users can send
you theirs when they choose.

## Where the facts come from

| Fact | How it is read | Evidence |
|---|---|---|
| A service NPC | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (payload `type`): Banker 8, Binder (innkeeper) 20, Auctioneer 21, StableMaster 22, TaxiNode (flight master) 6, SpiritHealer 18, Registrar (guild master) 11 | `PlayerInteractionManagerDocumentation.lua`, `PlayerInteractionManagerConstantsDocumentation.lua` |
| A merchant's stock | `MERCHANT_SHOW`, `MERCHANT_UPDATE`; `GetMerchantNumItems`, `GetMerchantItemID`; each item's class and subclass from `C_Item.GetItemInfoInstant` (no item cache needed) | `MerchantFrameDocumentation.lua`, `ItemDocumentation.lua`; `modules/Restock.lua` reads merchants the same way |
| Repairs | `CanMerchantRepair()` | `Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua` (Forever uses the Mainline merchant frame) |
| Trainer type | `TRAINER_SHOW`; `C_Trainer.GetTrainerType()`: General 0, Tradeskills 2, Pet 3 | `TrainerDocumentation.lua`, `TrainerConstantsDocumentation.lua`, `Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI_Camelot.lua` |
| Profession name | `GetTrainerServiceSkillLine(1)` at a Tradeskills trainer | `Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua` |
| Item classes | Consumable 0 (Fooddrink subclass 5), Container 1, Reagent 5, Projectile 6, Tradegoods 7, Recipe 9, Quiver 11 | `ItemConstantsDocumentation.lua` |
| The NPC | the creature id from `UnitGUID("npc")` (`Creature-0-…-<id>-<spawn>`), its name from `UnitName("npc")` | `UnitDocumentation.lua`; `modules/RefreshmentsTrade.lua` reads `UnitGUID("NPC")` |
| Where | `C_Map.GetBestMapForUnit("player")` and `C_Map.GetPlayerMapPosition(map, "player")`: **your** place, not the NPC's | `MapDocumentation.lua` |

`Enum` values are used when the client has them, the documented numbers otherwise.

## Kinds

`npcs/Kinds.lua` decides, from what was seen only (never a name, a title or what someone said). One NPC can be several.

| Section | Kinds (shown by default unless marked) |
|---|---|
| Vendors | reagent vendors (sold any Reagent-class item), ammunition (Projectile), repairs, trade supplies (Tradegoods), food and drink (Consumable / Fooddrink); recipes, bags and quivers, other merchants (none of the above): off |
| Trainers | class trainers (General trainer type, recorded for the class of the character who saw it), profession trainers (Tradeskills, with the profession's name), pet trainers |
| Services | innkeepers, bankers, auctioneers; flight masters, stable masters, guild masters, spirit healers: off |

The marker wears the icon of its first **shown** kind in a fixed order (trainers, then services, then vendors), so an
innkeeper who also sells food shows as an innkeeper unless innkeepers are hidden.

## The list

`TwichUIDB.npcs = { v = 1, list = { entry } }`, account-wide (like map pins): not part of a profile, a backup, a restore
or a shared setup (`setup/Restore.lua`'s `OWN_LEFT_OUT`, `setup/TwichConfig.lua`'s `LOCAL`), and protected from the Saved
Data Explorer's cleanup. Entry: `{ id, n (name), m (map), x, y (0..10000), tags, cls, prof, own, seen, rep, at }`.

- **Yours or reported.** `own = true` is an NPC you dealt with yourself. Anything another player sent you is a report
  (`own` absent, `rep` counts the reports). A report never changes an entry of yours (it only counts as one more report);
  the first time you deal with a reported NPC yourself it becomes yours, and what you saw replaces what was reported.
- **Place.** Where you stood when its window opened, a few yards from the NPC. Later visits average it (the last few
  count). The same creature seen more than 4% of the map away is another spawn (another entry), at most four per
  creature.
- **Maps.** Only a map the client knows that is a zone, a dungeon or smaller (`mapType >= Zone`). Nothing is noted inside
  an instance (`IsInInstance`) or where the game gives no position.
- **Checks** are the same for what you saw and what arrived: creature id, map, coordinates, kinds from the list only,
  class tokens from the nine classes only, names and profession as plain text (`Pins.CleanName`: escape sequences,
  links, textures and control characters removed, cut on a character boundary at 48 and 32 bytes).
- **Bounds.** 3000 entries. Making room removes the oldest report first; a report never pushes out one of yours. Reports
  not refreshed for 120 days go at login. An entry that can't be read is skipped, never erased. A list written by a
  newer TwichUI (`v` higher than 1) is read but never written.
- **Removing.** One NPC from its marker (Forget this NPC, asks first); everything others sent you, or your whole list,
  from the settings' second tab (each asks first and states the count).

## On the map

`npcs/Map.lua`: a map data provider, like `pins/Map.lua`, installed only while the switch is on.

- Shown on the map the NPC was noted on and on the maps it is inside down to a zone (a Stormwind NPC on Elwynn Forest),
  never on a continent or the world, and never on a sibling zone. Placed through the game's world-position conversion
  (`PinsMap.Position`), which also handles map exploration's seamless map.
- Square plaques (`media/textures/npc-<kind>.tga`, drawn by `tools/make_npc_icons.py`): pins are diamonds and the map's
  places are round, so they differ by shape. Reports are dimmed (60%) and greyed, and their tooltip says "not seen by you
  yet". At most 300 at once.
- A click opens the NPC's actions: **Set waypoint** (the game's own; replaces yours), **Pin this place** (the new pin
  window; needs Party pins), **Navigate here** (while Navigation is on), **Forget this NPC**. Nothing happens until one
  is chosen. Alt, Shift and Ctrl clicks go to the map's own click handlers, so the pin and ping shortcuts work over a
  marker.
- Redrawn when the map, the list or a choice changes; nothing runs per frame.

## Sharing

`npcs/Share.lua`, prefix `TwichUINpc`, protocol 1. Sending is always the player's choice (the second settings tab, or
`/tui npcs send party|guild|<name>`; `send` alone asks for a name, filling in your target if it is a player).

- **What goes.** Only NPCs you dealt with yourself, unless "Also send what others sent you" is on. Each entry is
  `{ i, n, m, x, y, k (kind codes), c (class tokens), p (profession) }`: nothing about the sender, no dates. The question
  before sending states the count; what is sent is exactly that list.
- **Messages.** `offer { t, k (parts), n (entries) }` then `part { t, i, l }` of at most 150 entries each, at most 20
  parts. Serialized, not compressed (nothing grows on arrival). Sent at BULK priority through AceComm and
  ChatThrottleLib. One send every 20 seconds.
- **Receiving** checks, before anything is kept: the switch, the receive choice, readable text, the channel (whisper,
  party, raid, instance, guild), that a group message comes from someone in your group now, a per-sender rate
  (a burst of 25, then one a second), the size (40,000 characters), the version, the offer's numbers, each part once,
  and every entry (`ReadWire`). A transfer is held in memory only, three senders at most, until its parts are in or for
  180 seconds; a partial one is asked about as partial.
- **Receive choice** (`ui.npcMap.receive`): **Ask each time** (default: names the sender and how many are new to you,
  add to reports, or are yours already), **Add from party and guild** (without asking; a whisper still asks; one chat
  line says what was added), **Don't take any**. A list with nothing new is not asked about.
- Sent means the game took the message. Nothing claims anyone received it.

## Settings

`ui.npcMap` (in the profile): `show.<kind>`, `trainerClass` (`mine` / `all`), `reports`, `labels`, `iconSize` (60 to
150), `receive` (`ask` / `auto` / `off`), `sendReports`. All stay on this computer when a setup is shared (`network`).

## The probe

`/tui npcs probe` (or the Probe button) prints, for this session only, what the game reported at each merchant, trainer
or service window: the interaction type, the NPC's creature id and name, your map and place, whether the client gives
the NPC's own position (`UnitPosition("npc")`), the merchant's items by class and subclass, repairs, the trainer type and
skill line, and what would be noted. Nothing is saved or sent. With the switch off it only prints.

## Still to check in the game

1. `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` fires with the types above for bankers, innkeepers, auctioneers, stable
   masters, flight masters, spirit healers and guild registrars on Forever.
2. `UnitGUID("npc")` and `UnitName("npc")` name the NPC while its window is open (and the GUID's form).
3. A merchant's list is complete at `MERCHANT_SHOW` or a moment later; `CanMerchantRepair` answers.
4. Reagent vendors' items are item class 5, arrows and bullets 6, food and drink 0/5 on Forever.
5. `C_Trainer.GetTrainerType()` at a class trainer (General), a profession trainer (Tradeskills) and a pet trainer, and
   whether weapon masters or riding trainers also report General (they would be listed as class trainers).
6. Whether `UnitPosition("npc")` gives the NPC's own position (the probe says). If it does, marks could be exact.
7. Markers on the world map and on map exploration's seamless map: placement, the click menu, dimmed reports.
8. Sharing between two or more clients over whisper, party and guild: the question, auto from guild, a whisper asking
   on auto, and how long a full list takes to arrive.
