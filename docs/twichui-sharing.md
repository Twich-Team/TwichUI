# Sharing TwichUI's own settings

For anyone adding a setting or changing configuration sharing. The code is `setup/TwichConfig.lua` (the schema, the
export, the checks, the review, applying and Undo); the windows are in `setup/Window.lua`; the transport is
`setup/Share.lua`. Nothing here has been checked in the game; see "In-game checks".

## What it is

A setup (Share setup / Received setups) carried other addons' saved settings tables, and one EllesmereUI profile.
TwichUI's own settings are now a third part of it, `pack.twichui`, chosen by feature and reviewed by feature. It is not
a table the way an addon's settings are: tables whose names start `TwichUI` are still refused at every door
(`Setups.ValidName`). Your own backups (restore points, `TUIBK2`) keep a full copy of TwichUI's settings separately, as
`point.own` (`docs/persistence.md`); that is never sent to anyone.

```
pack.twichui = {
    schema = 1,                 -- TwichConfig.SCHEMA: the shape of this part. Not the addon version, TwichUIDB.schema or pack.format
    status = "ok",              -- "ok" | "newer" (a payload schema this version doesn't read) | "damaged"
    made = <time>, addon = "3.0.12",
    groups = { [group] = { [slot] = { [key] = value } } },    -- the values of the features the sender ticked
    unknown = n,                -- fields this version doesn't know, ignored (counted, not kept)
    rejected = { [group] = n }, -- groups dropped whole because a value in them can't be used
}
```

`slot` is where the values are kept: `modules` (the on/off switches), `ui` (single values), or the name of a saved table
(`foodDrink`, `chronicleAppearance`, `restedxpSkinText`, ...). The payload names fields; it never carries a path.

## What is in it

One group per feature, each listing its settings explicitly (`Define` in TwichConfig.lua). Three groups are not flat and answer a small interface of their own (`usable`, `count`, `label`, `export`, `clean`, `plan`, `review`, `apply`, `restore`; their Undo records are kept in `twichUndo.weights` and `twichUndo.custom[group]`): stat weights, the restock list and chat cleaning's channels and rules. A feature's own `DEFAULTS`
and `LIMITS` supply defaults and ranges, so the schema cannot drift from the feature.

| Group | Holds |
|---|---|
| General | `media`, `quietLogin`; the settings window's motion preference (account-wide) |
| Notifications | the zone and training cards, the Battle.net friend card, their sound choices |
| Quality of life | only the Quick Keybind button |
| Food and drink | the switches and the whole look |
| Auction House | the Sell from Bags tab and the mailbox gold summary switches |
| Vendor restocking | how it buys (`ui.restock.mode`: ask first or automatically), the spending limit for a visit (`useLimit`, `limit`), and how the question window looks (`ui.restockPromptStyle`: background and border). Not whether restocking is on, and not your confirmation that it may buy without asking (`ui.restockAck`) |
| Restock items | the restock list: item IDs, targets and on/off, in order (merged by item on import: named items are set, new ones go at the end, nothing is removed). Never bag counts, merchants or purchases |
| Chat cleaning | whether chat cleaning is on (`modules.chatClean`; the review says plainly when an import turns it on or off) |
| Chat cleaning channels and rules | `ui.chatClean`: each channel's choice (by key: `zone:<id>` or `custom:<name>`) and the custom rules with the channels they apply to. Every key, flag, label and rule is checked as the feature checks its own (Lua patterns for shape and cost too); one bad entry refuses the group. Merged on import: a named channel takes the share's choice; a rule is matched by mode, case and text and takes the share's name, on/off and channels; new rules go at the end; nothing is removed. Undo puts the whole channel choice and rule list back. Never hidden messages, senders, counts or the repeat memory; a shared rule that matches every message is called out in the review |
| Class resource bars | whether the bars are on (`modules.classBars`), and the shared style in `ui.classBars` (when to show, sizes and spacing, fill, text, effects) and `ui.classBarsLook` (background and border). Not where the bars sit (`ui.classBarsPosition` stays on this computer) |
| Target dragon artwork | whether it is on (`modules.targetArt`) and `ui.targetArt` (the artwork for each kind of enemy, opacity, scale, anchors, offsets, mirroring, layer, each artwork's own adjustment, and hiding EllesmereUI's own dragon) |
| Hunter ammunition warning | whether it is on (`modules.ammoWarning`), `ui.ammo` (when it shows, the icon, text, size, opacity, the sound and its channel) and `ui.ammoLook` (background and border; none by default). Not where it sits (`ui.ammoPosition` stays on this computer) |
| Custom ammunition | `ui.ammoCustom`: the items you registered as arrows or bullets, by item ID. Every entry is checked (a usable ID, a known kind, no repeats, at most 40); one bad entry refuses the group. Merged on import: an item the share names takes the share's kind, new ones go at the end, nothing is removed, and Undo puts the list back. Never anything about what is equipped or carried |
| Class resource bar overrides | `ui.classBarsOverrides`: what one resource of one class does differently (fill source and color, text mode, when it shows), by `CLASS:RESOURCE`. Every key and field is checked as the feature checks its own; one bad entry refuses the group. Merged on import: an entry the share names replaces that class and resource's entry, every other entry is kept and nothing is removed. Undo puts the replaced entries back |
| Journey Chronicle | which events are recorded, sound, chat line, Welcome Back, the clock |
| Chronicle appearance | the window's background, border, text and accents |
| Party pins | clicks, labels, minimap, `/way`, the data bar entry, the sound (not whether pins are on) |
| Map pings | `ui.pinsPing`: the gesture, hint, sound and its channel, how long a ping and a list entry stay, the list, reduced motion. Not whether pings are on, sent or taken in (`modules.mapPings*` stay on this computer, like Party pins), and never a ping or the list |
| Pin appearance | the pin window, map text, data bar menu and editor looks |
| Gear comparison | hints, bag marks, and how hints behave |
| Gear stat weights | weights, rankings and "weigh by ranking", by class and talent tree (account-wide) |
| Mage | launchers, refreshments panel and its look, shares and reserve, trade button, and how selling is handled (`ui.mageSellMode`: sell directly or mark with EllesmereUI). Not whether selling is on, Dry run, the never-sell list or the confirmation, and not auto-fill |
| Addon skins | the four EllesmereUI-based skins' switches (they need a reload) |
| RestedXP guide window | the skin's look, text and timer bars (not the on/off switch) |
| SpeakStone speech frame | the switch and the whole look |

Exported values are the **effective** ones: what the feature is using now (the saved value when usable, the default
otherwise). So a sender who never changed a setting sends its default, and importing it puts the receiver's custom
value back to that default, which is what "the same configuration" means. Values are written as explicit values; a
`false`, `0` or default is written like any other.

## What stays on this computer

`TwichConfig.LOCAL` lists every key not shared and why; a test checks that every switch, every key of the feature
registries and every key the settings window can save is either shared or listed.

| Reason | Keys |
|---|---|
| Acts for you | `mageSell*` (the switches; not `ui.mageSellMode`), `mageRefreshmentsAutoFill`, `qolSummons`, `qolResurrect*`, `qolReleasePvP`, `qolDuels*`, `qolGuideWaypoint`, `ui.qol`, `ui.mageSell` (the never-sell list and `euiAck`, your confirmation of EllesmereUI marking), `ui.guideWaypoint`, `restock` (whether vendor restocking is on), `ui.restockAck` (your confirmation that it may buy without asking) |
| Sent to or accepted from others | `setupSharing`, `acceptSetups`, `groupCheck`, `partyPins`, `shareTransport` |
| Where things sit | `foodDrinkUnlock`, every `*Position`/`*Place`, `ui.settingsWindow`, the refreshments panel's and pin window's place |
| Other | `restedxpSkin` (turning it on chooses RestedXP's own theme), `restedxpSkinState`, `gear.trees` (per character), pins, `reminders` and `ui.reminders` (your reminders: they can name your characters), `setup`, profiles and their bookkeeping, `welcome`, `schema` |

Also never in it: the Journey Chronicle, backups and restore points, Undo copies, received setups, your own saved
setup, diagnostics and anything transient. The export is built from the schema, so none of that is reachable from it.

The "acts for you" and "sent to others" rows are a decision, not a limit of the mechanism: a shared setup should not
turn on selling, automatic acceptance, or what you send to others. Moving a key out of `LOCAL` and into a group is
the whole change if that is wanted.

## Scope: where an import goes

- **Profile settings** (almost everything) go into the profile **in use**, the one this character uses
  (`docs/profiles.md`). The review names it, and says how many other characters use it (they see the change too).
- **Apply to a new profile** first makes an independent copy of the profile in use (`Profiles.Duplicate`, named
  "From <sender>"), switches this character to it, and applies there. The profile it was copied from, and every other
  character's choice, stay exactly as they were.
- **Account-wide** settings (stat weights, the window-motion preference) are written account-wide and marked so in the
  review. Stat weights are replaced per class and tree that the share names; a class or tree it doesn't name is
  untouched. Entries for classes you don't play are kept for when you do.
- Nothing per character, and no character name, travels. The payload carries no identity beyond the sender's name on
  the setup itself (as for any setup).

## Checks

On arrival (and again when reviewed and applied) every field is looked up in the schema, never trusted by path:

- the entry must be a table with an integer `schema`; a higher one is kept as a note (`status = "newer"`) and nothing
  is read from it; no schema, or a malformed entry, is `damaged`;
- an unknown group, slot or key is **ignored and counted**; a switch kept local is unknown even if it is named;
- each value must be the right kind (boolean, whole number in the feature's range, one of its choices, an
  `AARRGGBB` colour, a plain name of at most 100 characters without control or `|` characters);
- one value a group can't use drops **that group whole** (reported in the review as "can't be used"); other groups
  are unaffected, and nothing is ever half-applied within a group;
- bounds: at most 1000 values, and the walk is bounded however much is sent (looping, deep or enormous input is
  refused, not walked);
- the two pin clicks may not be the same click unless both are off.

Nothing is run or loaded as code; the data is read with LibSerialize and walked.

## Applying

`TwichConfig.Apply(entry, { selection, from, newProfile, expect })`, refused in combat and when profiles aren't available
this session (a newer save is running on a stand-in that isn't saved).

The review (the popup, `setup/Window.lua`) says where the settings come from (sender, the TwichUI version that made
them, when), the profile they go to and how many other characters share it, that **only the values listed are
replaced** (every other setting in the profile keeps its value), which features it **turns on or off**
(`plan.turnsOn` / `plan.turnsOff`, for switches in the share), what it means for spending (`plan.spending`, from a group's `disclose`: vendor restocking's purchase mode, whether automatic buying is confirmed here, the spending limit and how many restock items it turns on; chat cleaning turning on or off and how many channel choices and rules change), what needs a reload (named, never done for you),
what the share doesn't hold or this version can't use (skipped features and counts), what always stays yours, and that
Undo can put the replaced values back (last import only). Hovering a feature lists its values, yours first.

**The approval is for what was reviewed.** `TwichConfig.PlanKey(plan)` is a fingerprint of the destination profile
(and how many characters share it) and, for each ticked feature, each setting with the value it would replace and the
one it would bring. The confirmation passes the review's key as `expect`; `Apply` plans again at that moment and
refuses with `"stale"` (nothing written, "Review it again") if the key differs: the profile in use changed, or a
setting did, while the question was open. The popup also still refuses if the received setup was replaced or removed.
A caller that passes no `expect` behaves as before.

1. Plan: re-check the entry, compare with what is in use, list the changes (shown before confirming).
2. Take the Undo copy: the raw value (or its absence) of every field about to change, and the stat weight entries.
3. Plain assignments of the planned values (all checked; a failure would put the old values back).
4. `Profiles.Refresh("import")`: the same steps as a profile change (`Switches.Sync`, each feature's applier, the open
   settings window redrawn). Features follow at once; switches that always needed a reload (the four skins, media,
   quiet login) ask for one as they do when clicked, and the review and report name them.

**Undo** (`TwichConfig.Undo`, one step, kept in `TwichUIDB.setup.twichUndo`) puts back exactly what step 2 recorded. It is
only offered for the profile it changed; after switching away, it says which profile to switch back to. A later
import replaces the Undo copy. It is listed in Saved data and can be deleted there.

This is separate from the existing apply/undo of addon tables (`TwichUIBackupDB`, `setup.pending`), which are
unchanged, and from restore points.

## Wire format

`pack.twichui` is sent in the data message as `payload.twichui` (the whole part, always; it is a few KB). The offer
carries `offer.twichui = { schema, groups }`, so the prompt can say TwichUI's settings are in it. `PROTOCOL` is
unchanged (2): a receiver that doesn't know the field ignores it, and a sender without it sends nothing extra. A
pack's `format` is unchanged (2).

## Selecting what to send

Share setup > **Choose addons** lists **TwichUI's own settings** first, with each feature under it. It needs no scan.
The choice is `TwichUIDB.setup.twichui = { included, skip = { [group] = true } }` and is off until ticked. With no
scan this session, **Save setup** saves TwichUI's settings (and the EllesmereUI profile) live and keeps the addon
settings already in the saved setup; a scan is only needed to refresh those.

## Adding a setting

1. A new key in a feature's saved table: add it to that feature's `DEFAULTS` (and `LIMITS` if it is a number), and
   list it in the group's key list in `Define`. A new enum gets a set in `ENUM`.
2. A new switch: add it to a group's `Switches(...)` or to `LOCAL` with a reason.
3. A new feature: a new `Group(...)` in `Define`, reading its registry (nothing is built until first needed).
4. Run `tests/test_twichui_share.lua`: it fails until every switch, registry key and saved settings key is placed.
5. If a payload needs a new shape, raise `SCHEMA` and add the migration for the older one; never reuse a number.

## Performance and loading

Nothing is built at login: the schema is built on first use (the review, the export, a received setup). It doesn't
load or need `TwichUI_Settings`; the window code that shows it is the sharing window's (`/tui share`), as before. The
export is a few hundred values read from live tables; no saved variable is walked and nothing is copied at login.
No timing or memory has been measured.

## Tests

`tests/test_twichui_share.lua`: the schema and its coverage; two clients through the real send and receive; what is
and isn't in the payload (sentinels in backups, the Chronicle, pins, positions, received setups); size independent of
history; review, apply, reload report, Undo; profile scope (other profiles and characters untouched, new profile,
undo waits for its profile); defaulted, false and zero values; unknown, invalid, older, newer, looping and oversized
payloads; stat weights; load-time repair; the rest of sharing unchanged. It runs the window code against stand-in
frames only.

## In-game checks

Two characters (or one, with **Test on myself**) and, ideally, two accounts. None of this has been run in the game.

1. **Export.** Change a few settings on character A (a Food and drink size, a Chronicle appearance colour, turn
   Welcome Back off, a stat weight). `/tui share` > **Choose addons**: TwichUI's own settings is at the top, unticked.
   Tick it, expand it, untick one feature. **Save setup** without scanning: the line says it saved TwichUI's own
   settings. **Review** shows TwichUI's settings in INCLUDED and none of the "stays local" entries.
2. **Send.** Send to B (or **Test on myself**). B's prompt says "and TwichUI's own settings". Accept.
3. **Review.** On B, Received setups shows "TwichUI settings"; **TwichUI settings...** lists the features, the
   profile it would change and how many other characters use it, what needs a reload, what was left out. Hover a row
   for its changes. Untick a feature.
4. **Import.** **Apply to this profile** (or **to a new profile**), confirm. The features change at once; the footer or
   a question asks for a reload if skins, media or quiet login changed. Open `/tui options`: the controls show the new
   values. Check with **Profiles** that the profile used by another character is unchanged.
5. **Undo.** Reopen the review: **Undo last import** puts everything back (also the stat weight).
6. **Unrelated data.** Your pins, the Chronicle, backups, window positions, sending method, `qol` automatic options
   and Mage selling are as they were before the import; `/tui saved` shows the Undo copy under Backups.
7. **Combat.** In combat the import and Undo are refused with a message; nothing changes.
8. **Reload / relog.** The imported values persist; the Undo copy is still there (it is listed in Saved data).
