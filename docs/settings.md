# Options panel: structure and conventions

For anyone adding or changing a TwichUI option. The panel is Blizzard's own (Esc > Options > AddOns > TwichUI),
built from its standard controls; TwichUI does not skin it. Workflows with lists, previews or confirmations
(sharing, backups, saved data, the pin window, stat weights) stay in their own windows and are only linked from here.

## Files

| File | Holds |
|---|---|
| `settings/Kit.lua` | The page list (`K.Page`), the controls every page uses (`K.Toggle`, `K.Proxy`, `K.Choice`, `K.Slider`, `K.Swatch`, `K.Dropdown`, `K.Checkbox`, `K.Button`, `K.Header`, `K.Appearance`, `K.ResetButton`), `K.Advanced`/`K.Under`, the overview's rows, `K.SetSwitch` |
| `settings/<Page>.lua` | One page each: `Gear`, `Notifications`, `QoL`, `FoodDrink`, `Mage`, `Chronicle` (+ Chronicle appearance), `Pins` (+ Pin appearance), `Auction`, `Skins`, `RestedXP`, `SpeakStone`, `Sharing`, `Profiles`, `Troubleshooting`, `Overview` |
| `settings/Register.lua` | At start-up: makes the pages in order, builds each in its own `pcall`, adds a page's Advanced row, builds the overview last, adds TwichUI to the AddOns list |

Load order (`.toc`): after every feature, `Kit.lua` first, `Register.lua` last. Nothing is built until TwichUI's
saved variables are in (`R:OnInit`), as before.

Navigation:

```
TwichUI   overview: a row per page with its status, Help, General (Show advanced options, fonts, quiet login)
├ Gear comparison › Stat weights (its own frame, gear/Window.lua)
├ Notifications
├ Quality of life
├ Food and drink
├ Mage (Mages only) › Refreshment shares (its own frame, modules/RefreshmentsShares.lua)
├ Journey Chronicle › Chronicle appearance
├ Party pins › Pin appearance
├ Auction House
├ Addon skins › RestedXP guide window, SpeakStone speech frame
├ Configuration sharing
├ Profiles
└ Troubleshooting
```

`R:OpenSettings(key)` opens a page by its key (`gear`, `notifications`, `qol`, `food`, `mage`, `chronicle`,
`chronicleLook`, `pins`, `pinsLook`, `auction`, `skins`, `restedxp`, `speakstone`, `sharing`, `profiles`, `troubleshooting`; none
for the overview).

## Adding a page

```lua
K.Page({
    key = "example", name = "Example", order = 85,          -- order: its place in the list
    parent = nil,                                            -- or a page key, for a page under another
    when = function() return R.Example ~= nil end,           -- optional: whether it exists this session
    overview = { label = "Example", tip = "...",             -- optional: its row on the overview
        status = function() return K.OnOff(R:Enabled("example")) end },
    build = function(page)
        K.Header("Example", "What it is for.")
        K.Toggle("example", "Do the thing", "What happens, in plain words.", false,
            function() R.Example.Refresh() end)
    end,
})
```

A page that errors while building is reported (`R.Fault`) and the other pages are still there.

## Rules for a setting

- **Persisted keys never change** for a label or a page move. A setting's variable (`TWICHUI_<name>`), its key in
  `TwichUIDB` and its default are part of the contract below.
- **The feature owns its data.** Read and write through its `Get`/`Set` (or its switch in `TwichUIDB.modules`).
  A setter validates, refuses what it can't use, **does nothing when the saved value is already the same**, saves
  once, and redraws only what the key changes. A page never writes `TwichUIDB` itself.
- **Switches** (`K.Toggle(key, label, tooltip, needsReload, onChange, onStatus)`): the game calls a setting's
  callback even when nothing changed (Defaults, a Reset, `NotifyUpdate`). `onChange(on)` runs only on a real
  change; a reload is asked for only when the value differs from the one the UI loaded with; `onStatus()` (tooltip
  text) and the overview's status run every time and must stay cheap. Code elsewhere that flips a switch calls
  `R:SetEnabled(key, on, alreadyApplied)`, never `TwichUIDB.modules[key] = ...`.
- **Reset buttons** (`K.ResetButton(label, resettable, reset, tooltip)`) call the feature's own `Reset` once and then
  `NotifyUpdate` on each control, so the feature redraws once.
- **Advanced**: `K.Advanced(row)` hides a row until "Show advanced options" is on. A page with any such row gets an
  "Advanced options — Show" row at its end automatically, shown only while they are hidden. Essential status, safety
  and recovery controls are never advanced.
- **Greyed out**: `K.Under(row, parentRow, isOn, why)`; the tooltip says why for as long as it is greyed out.
- **Status in a tooltip** is read when the tooltip is shown (replace `GetTooltip`, calling the one `K.Under`
  installed), never captured once at start-up.
- **Reload**: pass `needsReload` so the tooltip says "Takes effect after you reload your UI."
- **Combat**: the panel does not decide. The feature applies what it can and defers protected work to
  `PLAYER_REGEN_ENABLED`, coalesced to the latest value (docs/lifecycle.md). Say so in the tooltip where a change
  waits (Food and drink's Appearance does).

## Food and Drink: what a change redraws

`FoodDrink.Set` → `F.Changed(key)`:

| Keys | Redraw | In combat |
|---|---|---|
| `buttonOpacity`, `mouseover`, `idleOpacity` | the buttons' alpha only | at once (not protected) |
| `borderTexture`, `borderSize`, `borderColor`, `borderClass`, `borderOpacity`, `zoom`, `showCount` | restyle the buttons, no bag scan | waits for combat to end (it resizes secure buttons) |
| `size`, `spacing`, `layout`, `preferConjured` | a whole new look (bags, layout) | waits, as before |

## Profiles

The options in `modules`, `ui` and `gear` belong to the profile in use (`docs/profiles.md`). A new option needs nothing
extra to be part of profiles, as long as it follows the rules above:

- it is read through its feature's `Get` (or `R:Enabled`) when needed, never kept in a variable at start-up;
- its feature registers once what a profile change means for it, if anything has to be redrawn:
  `R.Profiles.OnApply("look" | "layout" | "views", name, fn)`. A switch needs nothing: profile changes go through
  `SettingsKit.SyncSwitches`, which runs its `onChange` as a click does.

An option that must be the same in every profile (a protection, a record, another addon's setting) is added to
`Profiles.ACCOUNT` and to the list in `docs/profiles.md`. The Profiles page's dropdowns have no default, so the
panel's Defaults button never acts on profiles.

## Defaults and Reset scope

- The panel's **Defaults** button is Blizzard's: *this page* resets the settings on the page shown; *all settings*
  resets every registered setting, TwichUI's included. Since the appearance pages are their own, Defaults on Journey
  Chronicle or Party pins no longer resets their appearance (use Defaults on the appearance page, or its Reset).
- No option, Reset or Defaults touches map pins (kept or not), Chronicle entries, backups, received setups or
  positions other than the one a Reset names. `tests/test_settings_kit.lua` checks pins.
- Stat weights have no Defaults hook on purpose (hand-entered weights); the page has its own resets.

## The contract test

`tests/test_settings_contract.lua` compares the panel with `tests/fixtures/settings_contract.lua`: pages and
parents, `R:OpenSettings` keys, every setting's variable, kind, type, default and label, each page's rows (kind,
label, advanced, greyed-out-under, tooltip checksum), what `TwichUIDB` holds after every setting is changed to
another valid value, and after Blizzard's Defaults. After an **intended** change:

```
cd tests && TWICHUI_GENERATE_CONTRACT=1 lua5.1 -e 'require("bit"); ROOT="../"; TESTS="./"' test_settings_contract.lua
```

and review the fixture's diff: a page move changes only the page column and rows; `changed*`/`defaulted*` must
stay identical unless what is saved is meant to change.

## Measuring (in the game; none of this has been measured yet)

No memory or CPU figures are claimed for this layout. To compare before and after, with only TwichUI (and the same
other addons) loaded, in the same place:

1. `/reload`, wait ~30 s, `/run collectgarbage("collect") UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("!!!TwichUI"))`
   three times; note the lowest (retained memory, after a full collection).
2. Open and close Esc > Options > AddOns > TwichUI and every page ten times; repeat step 1. Growth beyond a first
   opening (Blizzard creates its pooled row frames once) points at retained references.
3. Temporary allocation: `UpdateAddOnMemoryUsage()` before and after dragging one slider end to end, **without**
   collecting in between. Libraries shared with other addons (LibSharedMedia, AceComm) are attributed to whichever
   addon loaded them first; TwichUI loads first (`!!!`), so their memory counts as TwichUI's.
4. CPU: `/console scriptProfile 1`, reload, `UpdateAddOnCPUUsage()`/`GetAddOnCPUUsage` around the same actions;
   turn profiling off afterwards (it slows everything).

## In-game checklist

Turn on Display Lua Errors. Test TwichUI alone, then with EllesmereUI. After each group, `/tui diagnostics`.

1. **Fresh defaults.** New install (move `!!!TwichUI.lua` out, game closed). Every page opens; values match the
   defaults; the overview's statuses read sensibly.
2. **Existing saved variables.** Your normal save: every value as before, on its page (appearance on the new pages).
3. **Open, close, reopen** the panel and switch between all pages repeatedly (with and without "Show advanced
   options"). No error, no duplicated rows, the bag mark preview square appears once beside its dropdown.
4. **Advanced row.** On Gear comparison, "Advanced options — Show" is there; Show reveals the sections on every page
   and the row disappears; turning "Show advanced options" off on the overview brings it back.
5. **Only the intended feature updates.** Change a Chronicle accent color: only the Chronicle window changes. Change a
   Food and Drink border color with the buttons on: the border changes at once, the buttons keep their items. Change
   the button size: they resize.
6. **Same value again.** Press Defaults on a page whose values are already defaults: no reload question, nothing
   flickers.
7. **Reload question.** Turn an addon skin off: asked once. Turn it back on before reloading: not asked again.
8. **Rapid changes.** Drag sliders end to end (Chronicle text opacity, Food and Drink size, pin text size) and move
   the color picker quickly: no error; the final value sticks after `/reload`.
9. **Resets.** Each Reset button: the controls jump to their defaults, the look redraws once, nothing else changes
   (Food and Drink keeps its place and its conjured preference).
10. **Combat.** In combat change a Food and Drink border color and size: nothing changes until combat ends, then once;
    opacity changes at once. RestedXP "Use it" in combat says it will apply after.
11. **Disabled features and missing addons.** Without RestedXP, Leatrix Plus, EllesmereUI, a data-bar addon: TwichUI
    loads; their rows say why they are inactive; no Lua error. Not a Mage: no Mage page.
12. **Pins intact.** With local, party and kept pins: open Party pins and Pin appearance, use every Reset and both
    Defaults choices. Every pin is still there, kept pins still kept.
13. **Group check from the sharing window.** Turn group check off in options, then use the sharing window's "Turn on
    group check": the checkbox shows on, no reload question; turning it off in options asks once.
14. **Configuration sharing and backups.** Export/import and a restore point work as before (TwichUI's own settings
    are never part of them).
15. **Repeated opening.** Steps 1–2 of "Measuring"; note the numbers before and after this build.
