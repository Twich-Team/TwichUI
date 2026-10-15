# Easy Fishing

One key to cast your line and, while it is out, reel in. `!!!TwichUI/qol/EasyFishing.lua` (core addon, a Quality of
life feature; switch `qolEasyFishing`, off by default), its rows in `TwichUI_Settings/pages/QoL.lua`, the binding in
`!!!TwichUI/Bindings.xml`, tests in `tests/test_easy_fishing.lua`. **Nothing here has been checked in the game.**

## What it does

- No default key. The player chooses one (Quality of life > Fishing, or Key Bindings > TwichUI).
- No line out: the key casts Fishing (a secure button, `type = "spell"`, by the localized name so the best rank is
  used; acts on the press only).
- Line out (a fishing channel is active): the same key is given the game's `INTERACTTARGET` action by an override
  binding, so a press interacts with the world object the game has picked (the bobber).
- Line out but the game has picked no world object, or the player is channeling something else: the key is bound to
  an inert secure button and does nothing. It never casts over a line that is out, and never interacts with an NPC
  or attacks.
- The line ends (catch, interruption, death, zoning, another cast): the overrides are removed and the key casts again.

Every cast and every reel is the player's own key press. There is no automatic casting, no bite detection and no
timer.

## What the client gave us

| Need | Source |
|---|---|
| Secure spell button | `SECURE_ACTIONS.spell`, `SecureActionButton_OnClick` and its `useOnKeyDown` (Blizzard_FrameXML/SecureTemplates.lua) |
| Interact | `INTERACTTARGET` = `C_PlayerInteractionManager.InteractUnit("anyinteract")` (Bindings_Camelot.xml). There is **no** secure action type for interacting. `INTERACTSOFTTARGET` (soft target only, no auto-attack) returns at once unless the gamepad UI is on |
| Override bindings | `SetOverrideBinding`, `SetOverrideBindingClick`, `ClearOverrideBindings`: protected in combat; used by Blizzard_GamepadSharedUtility and the restricted environment |
| Player's key | `GetBindingKey`, `GetBindingAction`, `SetBinding`, `SaveBindings(GetCurrentBindingSet())`, `C_KeyBindings.GetBindingContextForAction` as Blizzard_Keybindings.lua uses them; `UPDATE_BINDINGS` |
| Fishing channel | `UnitChannelInfo("player")` (spell id is the 8th result), `UNIT_SPELLCAST_CHANNEL_START` / `_STOP`; both may be secret (`SecretWhenUnitSpellCastRestricted`), so values go through `issecretvalue` |
| Soft interact target | `UnitIsGameObject("softinteract")` (Blizzard_GamepadActionBars/MainActionBarFrame.lua), `PLAYER_SOFT_INTERACT_CHANGED` (registered only while a line is out) |
| Interaction settings | `C_CVar.GetCVar` / `SetCVar`; `SoftTargetInteract`, `SoftTargetInteractRange`, `SoftTargetInteractArc` (Blizzard_Gamepad/Core.lua); `Enum.SoftTargetEnableFlags` (None 0, Gamepad 1, Kbm 2, Any 3) |

**From the BetterFishing reference only, not from the client:** Fishing's spell ids (`FISHING_ORDER`) and the three
setting values (`TARGETING`: 3, 2, 60). BetterFishing is not loaded, called or required.

## Limits (unavoidable on this client)

- The API names "a world object", not "your bobber". If the game prefers another object (a chest, a mailbox) the key
  reels that one. The inert state only protects against NPCs and players.
- No bite signal exists, so a press before the bite pulls the line in empty, as clicking the bobber early does.
- Whether the client picks the bobber as its soft interact target at all depends on the three settings above, and
  whether those values are enough is unverified.
- A reel binding already installed when combat starts can't be removed once lockdown is on. It is removed at
  `PLAYER_REGEN_DISABLED` while the game still allows it, and at the latest when combat ends. Fishing does not
  continue in combat.
- The fishing pole, mounted, swimming and similar cast conditions are the spell's own: the game refuses the cast with
  its usual message.

## Client settings

Never changed without the player's say-so (Quality of life > Fishing > Adjust interaction targeting while fishing,
which asks first). Allowed, they are set when a line goes out and put back when it ends, when Easy Fishing is turned
off or the permission withdrawn, at logout and, after a game that closed mid-line, at the next start. A value is put
back only if it is still what was set, so a change the player made meanwhile is kept. The record is
`TwichUIDB.ui.easyFishingClient` (account-wide, never in a profile or in sharing).

## Keys

`E.Assign` follows Blizzard's own Key Bindings: the old action loses only that key, Easy Fishing's first key is
replaced and a second stays, nothing else is touched, and an occupied key is never taken without a confirmation that
names what uses it. Changes are refused in combat. A key is never assigned by default, by a profile change or by
configuration sharing. Turning Easy Fishing off leaves the player's key where it is (inert); "Clear the key" removes
only Easy Fishing's own.

## Sharing, profiles

`modules.qolEasyFishing` is shared; `ui.qol` (which holds the permission) and `ui.easyFishingClient` stay local.
Key bindings and game settings are never part of an export.

## Coexistence

BetterFishing binds its own key (`BETTERFISHINGKEY`) and changes the same three settings. Give the two different keys.
The page notes when the key is the same; TwichUI reads that binding and never changes BetterFishing's state. With
both on and the same key, which override wins is the order they were set in; that has not been observed.

## In-game checklist

- [ ] BetterFishing disabled or absent: key casts, reels, casts again.
- [ ] No key set: the page says so, nothing is bound. Set a free key; set an occupied one (confirmation names the
      other action; Cancel changes nothing; accept leaves that action's other key).
- [ ] Key Bindings > TwichUI shows "Easy Fishing"; assigning there works the same.
- [ ] Cast; wait; reel when the bobber dips; cast again. Check the key release does not cast or reel twice.
- [ ] Press before the bite and rapidly: the line is pulled in empty, or nothing happens; never a recast over a live line.
- [ ] Walk away, jump, take damage, cast another spell, channel another ability: the next press behaves (cast, or
      nothing while another channel is active).
- [ ] Stand beside an NPC or a chest: the key never talks to the NPC; note what a chest does.
- [ ] Fishing not learned / no pole / mounted / swimming: the game's own refusal, no error from TwichUI.
- [ ] Interaction targeting off, permission not given: the key casts; reeling does nothing; the page says why.
      Give permission: settings change while the line is out and are restored after; change one yourself mid-line
      and confirm it is not overwritten; /reload and log out mid-line and confirm they are put back.
- [ ] Enter combat with a line out (pull a mob): no stale reel binding; after combat the key casts.
- [ ] Turn Easy Fishing off with a line out; turn it on again; change profile; /reload; zone; die and release.
- [ ] BetterFishing enabled with the same key: the page says so; with different keys both work.
- [ ] No "action blocked" errors in `/tui diagnostics` or the error log in any of the above.
