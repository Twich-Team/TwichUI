# TwichUI Fishing: Forever client feasibility (Stages 1 and 2)

What the WoW: Forever client (`camelot` game type, interface 16001) allows a fishing addon to do, and how TwichUI Fishing
does each part. Evidence is the Forever UI source (Gethe `wow-ui-source`, branch `forever`, build 1.60.1 (71037), read
2026-11-21) and this repository. **Nothing here has been checked in the real client.** The checklist in
[fishing.md](fishing.md#in-game-verification) covers that.

**Reference addons.** The Fishing Buddy, Better Fishing, OneCast, FishMate and OneKeyFishing sources could not be read here.
CurseForge does not resolve from this environment, the Fishing Buddy GitHub URL returned 404, and no repository matched the
other names. Nothing below comes from their code. The only third-party facts are the Fishing spell ids and the
interaction-targeting values (3, 2, 60). The repository's earlier Easy Fishing feature (commit `ae6e2a0`, removed in
`520fdd4`) recorded them from Better Fishing as data only. TwichUI Fishing uses that earlier design for reeling and the
targeting settings, and its own code for the rest.

## Supported, with evidence

| Need | How | Evidence |
|---|---|---|
| Cast on a key | Secure button, `type "spell"`; `SECURE_ACTIONS.spell` calls `CastSpellByID` | `Blizzard_FrameXML/SecureTemplates.lua` |
| One action per press | `RegisterForClicks("LeftButtonUp")` with `useOnKeyDown` false: `SecureActionButton_OnClick` acts on one edge only | SecureTemplates.lua; the refreshments keys use the same pattern |
| Equip a pole on a press | `type "item"` on its bag slot: `SECURE_ACTIONS.item` calls `C_Item.EquipItemByName` for an equippable item that is not worn | SecureTemplates.lua (it builds the `"bag slot"` form itself) |
| Apply a lure on a press | `type "item"` plus `target-slot` 16: after the use, `OnActionButtonClick` calls `UseInventoryItem(slot)` while `SpellCanTargetItem()` | SecureTemplates.lua |
| Outfit | `type "equipmentset"` → `C_EquipmentSet.UseEquipmentSet` | SecureTemplates.lua; `EquipmentManagerDocumentation.lua` |
| Weapons back in combat, on a press | `type "macro"` with `/equipslot N item:ID`; `/equip` and `/equipslot` are secure slash commands | `Blizzard_ChatFrameBase/Shared/SlashCommands.lua` |
| Open a container on a press | `type "item"` on its bag slot (`SecureCmdUseItem`) | SecureTemplates.lua |
| Reel with the same key | Override binding to `INTERACTTARGET` (`C_PlayerInteractionManager.InteractUnit("anyinteract")`) while the line is out | `Bindings_Camelot.xml`; `PlayerInteractionManagerDocumentation.lua` |
| Is the line out | `UnitChannelInfo("player")` (spell id is the 8th value), `UNIT_SPELLCAST_CHANNEL_START/STOP` with `castGUID`; `_FAILED`, `_INTERRUPTED` | `UnitDocumentation.lua` (some values `SecretWhenUnitSpellCastRestricted`) |
| Lure on the pole | `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.MainHand)`: `hasEnchant`, `timeLeft` (ms), `enchantID` | `ItemDocumentation.lua`; read the same way in `reminders/State.lua` |
| Pole identity | `C_Item.GetItemInfoInstant`: class Weapon, subclass `Fishingpole` (20) | `ItemConstantsDocumentation.lua` |
| Fishing loot | `LOOT_READY`, `LOOT_OPENED(autoLoot, isFromItem)`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `IsFishingLoot()`, `GetLootSlotType/Link/Info` | `LootDocumentation.lua`; `Blizzard_UIPanels_Game/Mainline/LootFrame.lua` (camelot loads it) |
| Openable bag items | `C_Container.GetContainerItemInfo(...).hasLoot` | `ContainerDocumentation.lua` |
| Loot confirmation | `CHAT_MSG_LOOT` and `LOOT_ITEM_SELF(_MULTIPLE)` | `ChatInfoDocumentation.lua` (text can be secret in lockdown) |

## Needs in-game verification

- Changing a secure button's attributes in its insecure `PreClick` out of combat, and having that same press perform the
  new action. This is a standard addon pattern, but it is not proven on Forever.
- The client picking the bobber as its soft-interact target, so `INTERACTTARGET` reels it in, and which `SoftTargetInteract*`
  values are needed. Easy Fishing hit the same unknown.
- Whether a key release that arrives after the override is cleared (a very fast catch) reaches the fishing key. The one-second
  guard is there in case it does.
- Which Fishing spell id Forever uses, the lure and clam item ids, and the lure enchant ids. All are seed data; enchants are
  learned at runtime.
- Whether `C_Item.EquipItemByName` and `C_Container.UseContainerItem` work from addon code outside a key press. Forever's API
  documentation marks neither `HasRestrictions`, but that is not proof. TwichUI uses them only for gear restoration and for
  the opt-in automatic container mode, and it falls back to a key press when blocked.
- Whether `LOOT_SLOT_CLEARED` fires under auto-loot. The loot chat line is the fallback.
- Event order between `LOOT_READY`, `LOOT_OPENED` and `UNIT_SPELLCAST_CHANNEL_STOP`, and when a hand-opened clam leaves the bags.

## Unsupported or restricted (never attempted)

- Any action without a press: casting, reeling, applying lures or equipping on a timer or a bite. No bite signal exists in
  the API, and none is simulated.
- Interacting with the bobber from addon code: `InteractUnit` has restrictions, and there is no secure action type for it.
- Changing attributes, override bindings, gear or CVars in combat lockdown.
- Binding keys for the player. TwichUI never calls `SetBinding`; the player chooses keys in Key Bindings > TwichUI.
- Opening a locked container (lockbox). The client refuses with `ERR_ITEM_LOCKED`; the container is marked and skipped.
- Taking an item that the outfit put in an originally empty slot back off. It is left on and reported.

## Recommended approach (implemented)

Every gameplay action goes through one secure button press, and each press makes one decision. Gear, lure and container
steps come before the cast; the reel comes from an override that exists only while the line is out. Automatic container
opening is opt-in (`/tui fish containers auto`). It stops for good the first time the client blocks it, and the
player-initiated queue is the default. Restoration first tries addon code out of combat. If that fails it stays pending,
and the fishing key performs it as a secure macro on the player's press, which works in combat for weapons. Records come
only from loot events. Bag changes are used for reconciliation, never as evidence of a catch.

## Stage 2: Fishing Mode

**Sources.**

- **Forever's own UI source**, Gethe `wow-ui-source` at revision `ca8368f` (1.60.1.70532, the revision the repository's
  simulator pins), read at the Stage 2 refinement.
- **EllesmereUI's public repository**, EllesmereGaming/EllesmereUI, at 9.9.1 (2026-11-20), read for its frames and alpha
  handling. Its license reserves all rights, so nothing was copied.
- **Not reachable:** warcraft.wiki.gg and CurseForge do not resolve from this environment. Dialogue UI's code was not
  read.

The Test Lab case `fishing.client.presentation` records the facts in the client.

| Need | How | Evidence and status |
|---|---|---|
| Camera distance moves | `CameraZoomIn(d)` / `CameraZoomOut(d)` once each way | Both exist: Forever's own camera key bindings call them (`Blizzard_FrameXML/Bindings_Standard.xml`). Whether addon code may call them, and whether they animate, is unverified |
| Reading the distance | `GetCameraZoom()` | **Not in Forever's UI source at all** (neither used nor documented). Fishing Mode reads it when present; without it the camera is left alone (`camera-unsupported`) and the settings page says so. Unverified |
| Shoulder offset | CVar `test_cameraOverShoulder`, opt-in | Setting an experimental camera variable raises `EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED`, which shows the game's `EXPERIMENTAL_CVAR_WARNING` popup (`Blizzard_Game/Shared/EventRouting.lua`, `GameDialogDefs.lua`). TwichUI never suppresses it. Whether the variable exists is unverified |
| Not used | `SetView`/`SaveView`/`ResetView` (they would overwrite your saved views), pitch, per-frame camera control, `UIParent:SetAlpha`, `SetUIVisibility` | Avoided on purpose |
| Fading | `frame:SetAlpha`, plus a `hooksecurefunc` post-hook on each faded frame's `SetAlpha` | EllesmereUI relies on `SetAlpha` not being protected, in combat on Forever too (its minimap and unit frame code says so). Hooks are standard; the in-game behaviour with EllesmereUI's real frames is unverified |
| Key Bindings | `Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_TWICHUI)` | Forever defines the id (`Blizzard_SettingsDefinitions_Frame/Keybindings.lua`) and opens it this way at a header (`PingSystem.lua`) |
| Bindings | `Bindings.xml` entries with Lua bodies; the reveal key uses `runOnUp` and `keystate` | Unverified on Forever. TwichUI calls no `SetBinding` |
| Gamepad | `C_GamePad.IsEnabled`, `GetActiveDeviceID`, `SetVibration(vibrationType, intensity)`, `StopVibration` | `SetVibration` takes a type name and an intensity (`GamePadDocumentation.lua`). The type `"Low"` is retail's and unverified here. Opt-in, only on a confirmed catch |
| Cast timing | `UnitChannelInfo("player")` start and end in milliseconds | As Stage 1 read it |
| Casting state | `UNIT_SPELLCAST_SENT(unitTarget, target, castGUID, spellID)` | Payload as documented (`UnitDocumentation.lua`) |
| Textures | 32-bit uncompressed TGA with power-of-two sides, as the rest of the repository | The texture pack's PNGs are not used in the game |

**EllesmereUI (from its source, not a running game).**

- **Unit frames:** every one is parented to `EllesmereUIUnitFrames_Hider`, which has only a secure pet-battle visibility
  driver. EllesmereUI never writes that frame's alpha; it writes the frames' own alpha and the player's wrapper.
- **Action bars:** `EABBar_<key>` are parented to UIParent. EllesmereUI writes their alpha only at state edges (mouse-over,
  Advanced Fade, visibility passes), from its own record `_fadeAlpha`, through an OnUpdate fader.
- **3D portraits:** they don't inherit alpha, and EllesmereUI mirrors their alpha itself.
- **Minimap:** EllesmereUI moves `Minimap` out of `MinimapCluster` and sets the cluster's alpha to 0. Blips don't dim.
- **Never touch:** its secure micro-menu buttons must never have their alpha changed.

Each fact shapes `Ellesmere.lua` and Fade.lua's policy (docs/fishing.md, "Fading"). The names are EllesmereUI's internals,
not a published interface, so a future version may change them; a missing name is simply not faded, and the settings page
and `/tui fish fade` say what was found.
