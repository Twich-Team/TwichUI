# Marker cycling

For anyone changing the feature. Code: `markers/Markers.lua` (`R.Markers`: identities, the saved order, checks, the
cycle's arithmetic, sharing helpers), `markers/Keys.lua` (`R.MarkerKeys`: the secure buttons and their snippets, applying
the order to them, combat deferral, the key binding API), `Bindings.xml` (six `CLICK` entries), the switches
`modules.markersTarget` and `modules.markersWorld` (default off; `Core.lua`, `Switches.lua`), the settings tabs
**Quality of life > Target markers / World markers** (`TwichUI_Settings/pages/Markers.lua`), and the sharing groups
`markers` and `markerOrder` in `setup/TwichConfig.lua`. Test: `tests/test_markers.lua`. The marker bar (a third tab) is below.
**Nothing here has been tried in the game.** The checklist at the end is what has to be.

It is an independent implementation. World Marker Cycler (`../reference_addons/WorldMarkerCycler`, no license file) was read
for what it does; no code, saved data or function of it is used, and TwichUI works the same with it absent, disabled or loaded.

## What the reference does, what the client allows, what TwichUI does

| | World Marker Cycler | WoW: Forever client (UI source) | TwichUI |
|---|---|---|---|
| Cycle world markers | `/wm [@cursor] N` macro on a secure button, index in a PreClick snippet | `/wm` is a secure slash command; `PlaceRaidMarker(N, "cursor")` | Same mechanism; own snippet and order |
| Clear world markers | `/cwm 9` macro (all) | `SECURE_ACTIONS.worldmarker` `clear` with no marker = `ClearRaidMarker(nil)` = all | Secure `worldmarker` clear (all) |
| Cycle target markers | secure `raidtarget` action on Forever (its comments: `/tm` from a button is ignored there) | `/tm` is registered with `CheckAddSlashCommand` (not secure); `raidtarget` `set` exists | Secure `raidtarget` `set` |
| Clear target marker | `raidtarget` `clear` | `SetRaidTarget(unit, 0)` | Same |
| Mouseover marking | a separate cycler, `[@mouseover,harm,nodead]`, else target | `SecureCmdOptionParse` is in the restricted environment | One choice on the target tab ("an enemy under your mouse, else your target") |
| Order | one shared list of world numbers, converted for targets; a "custom subset" mode | marker numbers differ per kind (below) | A separate order per kind; skipping keeps a marker's place |
| Reset | only as a side effect of Clear (and `/wmcclear`) | - | A restart key of its own per kind; clear restarts only if you leave that ticked |
| Reverse cycling | none | - | Not added (not in the reference) |
| Keys | override bindings set from its window or slash commands; default `B` / `Ctrl-B` for world | `SetBinding`, `SaveBindings`, override bindings win | The game's own key bindings (Key Bindings > TwichUI, or chosen on the tab); none by default |
| Click edge | per-key AnyUp/AnyDown handling, `/wmcclickedge` | `SecureActionButton_OnClick` acts on the edge `ActionButtonUseKeyDown` picks | Both edges registered; the snippet takes one step per press (below) |
| Marker toolbar, ready check, pull timer | yes | - | Not part of cycling; not added |

Marker identities (checked in the source, not assumed):
- Target markers, `SetRaidTarget` index: 1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square, 7 Cross, 8 Skull
  (`RAID_TARGET_1..8`; icons `Interface\TargetingFrame\UI-RaidTargetingIcon_1..8`, used by the chat frame's `{star}` codes).
- World markers, `PlaceRaidMarker` index: Blizzard's marker buttons (`Blizzard_CompactRaidFrameManager`, Mainline and Classic,
  same `WORLD_RAID_MARKER_ORDER`) show world marker `WORLD_RAID_MARKER_ORDER[9 - id]` with target icon `id`. So world 1..8 are
  Square, Triangle, Diamond, Cross, Star, Circle, Moon, Skull (target icons 6, 4, 3, 7, 1, 2, 5, 8).
- Defaults: both kinds in the game's own order, Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star
  (target `8,7,6,5,4,3,2,1`, world `8,4,1,7,2,3,6,5`).

## The keys

Six secure buttons (`TwichUIMarkTargetNext/Restart/Clear`, `TwichUIMarkWorldNext/Restart/Clear`), never placed on screen,
made once out of combat (at load, or after combat if the UI loaded during it). Each has a `PreClick` snippet
(`MK.SNIPPETS`, wrapped with `SecureHandlerWrapScript`, the button as its own header) and an insecure `PostClick` that only
writes a short line to `UIErrorsFrame` when a press can't do anything (feature off, every marker skipped) or after a restart, and
tells an open settings tab to redraw. Nothing in TwichUI clicks them; only their key bindings do.

**One step per press.** A binding sends a press and a release. The snippet acts on the first edge it receives and returns
early on the release that follows a press it acted on. The game's own button code (`SecureActionButton_OnClick`) acts on
whichever edge "cast on key down" picks, with the attributes the first edge set, so exactly one mark or placement happens and
the cycle moves one step, whichever edges the client sends.

**When the cycle moves.** The step (`twichui-step` on the next button: presses since it last restarted) increases only when
the press will do something: the kind is on, at least one marker is ticked, and, for target markers, a unit exists
(`[@target,exists]`, or `[@mouseover,harm,nodead]` first when chosen; the same check the game's button makes). Otherwise the
snippet clears the button's `type`, so the game does nothing, and the step is unchanged. The next marker is
`sequence[step % n + 1]`, so after the last it wraps to the first.

**What a press can't tell.** The key press can't read whether the game accepted it: no permission (in a group the game may
require leader or assistant), a unit that can't be marked, nothing under the pointer for a world marker, the world marker
system being off. Those presses still use their turn. TwichUI never claims a mark was made.

- Target, already wearing the marker: `raidtarget` `set` calls `SetRaidTarget` only when `GetRaidTargetIndex(unit) ~= marker`, so
  a press never takes a marker off (the game's `toggle` would; TwichUI doesn't use it). The cycle still moves on. What the game
  does with that marker if another unit wears it is the game's.
- World: `/wm [@cursor] N` places at once where the pointer is. There is no targeting circle, so nothing is pending, there is
  nothing to cancel, and a repeated press places the next marker. Whether placing a marker that is already on the ground moves it
  is the game's (Blizzard's own button clears it first); check in game. TwichUI can't tell whether a spell is being aimed; the tooltip
  says not to press it then.
- Changes by other players or addons are not watched and don't change the cycle.

**Restart** sets the step to 0: the next press uses the first ticked marker. It removes nothing. **Clear** removes (your
target's marker, or every world marker) and, while "Removing ... restarts the cycle" is ticked (default, as the reference does), also
restarts; with it unticked it only removes. Clear with no target does nothing at all.

**Restart when combat ends** (option `targetRestartAfterCombat`, target markers only, off by default). While it and target
cycling are both on, `markers/Keys.lua` listens for `PLAYER_REGEN_ENABLED` (and stops listening when either is turned off or a profile
without it is switched to). When combat ends it first gives the keys anything that waited for combat, then, if the cycle is not already
at its start, sets the step to 0, exactly as the restart key does: nothing is removed, nothing is said, and an open settings tab
redraws its preview. It does not touch world markers, and it is not a clear. It runs from the event, never from a timer.

## The marker bar

Holding a modifier key (Shift, Ctrl or Alt) while you have a target shows a bar of target markers; clicking one marks your target
with it, Remove (or a right-click on any marker) takes the marker off. Code: `markers/Bar.lua` (`R.MarkerBar`), the switch
`modules.markersBar` (default off), the settings tab **Quality of life > Marker bar** (`TwichUI_Settings/pages/MarkerBar.lua`), the
sharing group `markerBar`. Test: `tests/test_marker_bar.lua`. Saved in `TwichUIDB.ui.markerBar` (`B.DEFAULTS`), the look in
`ui.markerBarStyle` (the same choices as TwichUI's other frames, `modules/MenuStyle.lua`), the fixed place in
`ui.markerBarPosition` (`{ x, y }` from the middle of the screen; a place, so configuration sharing leaves it on the computer).

Why it is built this way (all from the Forever UI source):
- `SetRaidTarget` is restricted, so each icon is a `SecureActionButtonTemplate` button using the `raidtarget` action: `*type1`
  `raidtarget`, `*action1` `set`, `*marker1` the marker, `unit` `target`; `*type2` and the Remove button use `clear`. `set` never
  takes a marker off. A mouse click acts as the button comes up (`SecureActionButton_OnClick`: a secure mouse press acts on the up edge).
- A protected frame can only be shown, hidden, moved or resized by insecure code out of combat (and `IsAnchoringRestricted` exists on
  this client). Showing it in combat is the secure state driver's job: `RegisterStateDriver(frame, "visibility", "[...] show; hide")`,
  re-evaluated on `MODIFIER_STATE_CHANGED` and every 0.2 seconds (so combat starting or ending is noticed within 0.2 s).
- So there are **two** protected bars and nothing about a bar moves in combat. The **near** bar follows the target's nameplate and its
  condition always has `nocombat`; the **fixed** bar sits at the fixed place and is the one shown in combat. "Place the bar" and "In combat"
  are only these conditions (`B.Conditions`): nameplate + show: near out of combat, fixed in combat; nameplate + hide: near out of combat
  only; fixed + show: fixed always; fixed + hide: fixed out of combat only. All of them need a target and the held key.
- The nameplate is **never anchored to**: a protected bar anchored to a frame Blizzard's nameplate code moves would make that frame
  restricted. The near bar is placed from the plate's screen position (`C_NamePlate.GetNamePlateForUnit("target")`: nothing for a plate the
  game forbids addons to touch; its centre, top and bottom, converted for the plates' scale; kept on screen), read about 30 times a second
  only while that bar is shown, out of combat and the plate is readable. A missing, forbidden, anchoring-restricted or secret plate puts it at
  the fixed place. An unmoved plate isn't re-anchored.
- Markers on the bar, size, spacing, scale, the look and the place change the protected frames, so they are applied out of combat; in combat they
  are saved at once and given when combat ends (the latest only), and the tab says so (`B.Pending`). The held key and the two conditions are part
  of that, so switching the bar off in combat takes effect after it.
- The bar is built (and its frames and per-frame follow made) the first time it is on; off at login, nothing exists.
- The bar's padding clears the border's **line**, not its whole thickness (`MenuStyle.ApplyInset`), and the bar's scale is set before the
  look is drawn; both matter for an EllesmereUI textured border (see CLAUDE.md, "EllesmereUI textured borders").
- The ring on the marker your target wears reads `GetRaidTargetIndex("target")` only when it is readable (the game may keep it secret).
- The **fixed place** is moved by dragging the **preview**: an ordinary, non-secure copy of the bar (mouse-less buttons, nothing to click) shown
  by **Show and move**. It closes when combat starts, when the page is left or the window closed.
- Which markers are on the bar is its own tick per marker (`show1..8`, by target marker number), apart from the cycle's ticks; their order is
  the target cycle's order, so one order serves the keys and the bar.

## The order, and combat

Saved per profile in `TwichUIDB.ui.markerOrder[kind] = { order = { all eight ids }, off = { skipped ids } }`; options in
`TwichUIDB.ui.markers` (`targetUnit`, `targetClearRestarts`, `worldClearRestarts`, `targetRestartAfterCombat`). The order always holds all eight, so a
skipped marker keeps its place and moving one never changes its tick. A damaged order is used as the default and a damaged
skipped list as "none skipped", each on its own; nothing else is reset. The step and anything waiting for combat are runtime only:
a reload starts each kind at its first marker.

The buttons read the order as attributes (`twichui-on`, `twichui-count`, `twichui-m1..8`, `twichui-unit`, `twichui-restart`,
`twichui-cmd`). Attributes can't be set from addon code in combat, so `MK.Apply`:
- out of combat, gives the buttons what is saved, only for a kind whose values differ, and restarts that kind's cycle when its
  sequence changed (an option alone keeps its place);
- in combat, saves the change (it already is) and marks the kind pending; the settings tab says so and the keys keep the order they
  had; when combat ends the latest saved values are given, once. Changing it back during combat clears the wait.
The restart and clear keys work in combat (their snippets set the step); the tab's **Restart cycle** button is out of combat only.

Profile changes and imports are refused in combat by Profiles.lua and TwichConfig.lua; afterwards Markers.lua's `views` step calls
every listener, so the buttons follow the new profile. Key bindings aren't part of a profile.

## Keys and bindings

`Bindings.xml` lists the six actions under TwichUI in the game's Key Bindings, named by `MK.ACTIONS`. None is bound by TwichUI.
The tab's key rows open a small window that takes the next key (with modifiers), mouse button 3 to 5 or the wheel; Esc cancels
and is not passed on. A key that already does something is bound only after a question that names what loses it (`GetBindingAction`);
a key another addon holds with an override binding is warned about, and later shown under the row (`MK.TakenOver`), since overrides
win. `MK.SetKey` replaces only the action's first key (a second one set in the game's list stays); `MK.RemoveKeys` unbinds only that
action's keys; both refuse in combat and save with `SaveBindings(GetCurrentBindingSet())`. Turning the feature off, a profile change
and an import never touch bindings; while off, the keys do nothing and say so.

Coexistence with World Marker Cycler: its globals (`WorldMarkerCyclerAPI`, `WMC_*`) and buttons are never read or written; the
tab only notes that it is loaded (`C_AddOns.IsAddOnLoaded`) and that each keeps its own cycle and keys. Its override bindings win
over the game's bindings for the same key, which the row reports.

## Configuration sharing

`markers`: both switches and the four options, field by field. `markerOrder` (custom): each kind's order and skipped list, replaced
per kind as a whole; checked by `M.Clean` (only `target`/`world`, only `order`/`off`, the eight known ids once each, skipped ids known
and once). An import never changes key bindings, and the cycle's place never travels.

## In-game checklist (not yet done)

Use a training dummy or a quiet spot; mark only units and ground you mean to, and clear what you place.

Solo:
1. Fresh install: both tabs show Off, no key is bound (Key Bindings > TwichUI lists the six, unbound).
2. Turn on target markers, set a key on the tab. Target a dummy, press 9 times: Skull, Cross, ... Star, Skull. Note whether solo
   marking works on this client at all.
3. Hold the key: still one mark per press. Try with Options > Combat "cast on key down" on and off.
4. Press with no target: nothing, and the preview's "Next press" doesn't move.
5. Target a dummy already wearing the next marker: it keeps it; the next press gives the next one.
6. Untick two markers: they are skipped; drag one to another place; use the arrows; tick it again: it returns in its place.
7. Restart key: the next press is the first; nothing is removed. Remove key: your target's marker goes; with the restart box
   unticked the cycle keeps its place.
8. Choose "an enemy under your mouse, else your target": hover another enemy and press.
9. Choose a key already used (e.g. a movement key): it asks first and names it; Cancel leaves it; Esc in the key window doesn't
   close the settings.
10. Enter combat, change the order: the tab says it waits; the key keeps the old order; leaving combat applies the new one once.
    In combat, the restart key works and Restart cycle is greyed out. Record any "action blocked" or taint message.
11. Option "Restart the cycle when combat ends": mark a few targets so the cycle is mid-way, fight something, and after combat the
    next press is the first marker. With the option off it keeps its place. Record any message.
12. Marker bar (needs checking, in this order): turn it on, hold Shift with a target: the bar appears above its nameplate, follows it
    as the target or you move, and a click marks (record whether solo marking works and what a plain member of a group gets). Right-click and
    Remove clear. Try Ctrl and Alt; try nameplates turned off, a target off screen, and a friendly NPC (fixed place expected when there is
    no readable plate). Choose "Show it at the fixed place" and pull: the bar appears at the fixed place in combat and holding the key
    still works; choose Hide: nothing in combat. Choose a fixed placement. Show and move: drag it, close the page: the preview closes.
    Change the bar's markers/size in combat: waits, and applies afterwards. Record any "action blocked" message, and whether the bar
    ever sits in a wrong place for a frame when combat starts or ends (the driver takes up to 0.2 s).
13. `/reload`: orders and keys kept; both cycles start at their first marker. Repeat after a `/reload` in combat.

In a party (as leader, then not), and a raid (leader, assistant, plain member), with consent:
14. World markers: point at the ground and press: placed at once under the pointer, in order; pointing at the sky; pressing while a
    spell's targeting circle is up (record what happens); pressing again for a marker already down (does it move?).
15. Remove all world markers: all go (yours and others'); restart follows the box.
16. Permission: as a plain raid member, record what the game says and that the cycle still moved on.
17. Another player marks a unit with your next marker: record what the game does when you then press.
18. Profiles: a profile with marking off; switch to it: keys do nothing and say so; switch back.
19. Share a setup including Marker order with a second account: their keys unchanged, orders replaced, Undo restores.
20. With World Marker Cycler loaded and its default `B` key: the TwichUI row with the same key shows that another addon has it.
