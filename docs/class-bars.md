# Class resource bars

Opt-in bars for the player's own resources: the power the client says the character is using (as a continuous bar),
combo points on the target (as segments) and, for a Druid whose power is not mana, a thin mana bar. Optional effects,
off by default. Code: `!!!TwichUI/classbars/`; settings: `TwichUI_Settings/pages/ClassBars.lua`.

Nothing here is verified in the game yet. "Verified" below means read from the Forever UI source
(`../wow-ui-source`, branch `forever`, game type `camelot`), or exercised by the offline tests with a stand-in for the
game. See "In-game checklist" for what is still to be done in a real client.

## What the client supports (the capability matrix)

Evidence is the Forever branch of Blizzard's UI. Where the client's own UI draws a resource, it has a data source for
it; where it does not, none is assumed. Retail's class design was not used to decide anything.

| Resource | When it applies | Data source | Events | Presentation | Limits |
|---|---|---|---|---|---|
| The power in use (mana, rage, energy, focus, ...) | Always, whatever the class or form | `UnitPowerType("player")` for which, `UnitPower` / `UnitPowerMax("player", type)` for how much | `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER` (all filtered to `player`) | Continuous | Shown as whatever the client reports, never from a table of "what each class uses". Colors and resting values are ours for mana, rage, energy, focus, runic power; any other reported power uses the color the client gives it and has no known resting value |
| Combo points | Rogue always; Druid while the power is energy (Cat Form) | `GetComboPoints("player", "target")`, maximum `UnitPowerMax("player", Enum.PowerType.ComboPoints)` capped at 5 | the above plus `UNIT_POWER_UPDATE`, `PLAYER_TARGET_CHANGED`, `COMBO_TARGET_CHANGED` | Segmented | They belong to the target: no target is 0 points. A target change is not treated as a transition (no effect plays). Source: `Blizzard_UnitFrame/Camelot/TargetBoundComboPointBar.lua`, `ComboFrame.lua`, `RogueComboPointBar.xml`, `DruidComboPointBar.xml` |
| Druid mana while shapeshifted | Druid while the power is not mana (Cat, Bear) | `UnitPower` / `UnitPowerMax("player", Enum.PowerType.Mana)` | as the power in use | Continuous | Same rule as Blizzard's own (`Blizzard_PersonalResourceDisplay/Camelot`: "show the mana alt bar whenever the main bar isn't already showing mana") |

Not covered, and why:

| Not drawn | Reason |
|---|---|
| Runes, soul shards, holy power, arcane charges, chi, essence, insanity, stagger, soul fragments, Evoker and Demon Hunter resources | `Blizzard_UnitFrame.toc` excludes their bars for `camelot`: the Forever client does not load them, so there is no evidence of a data source |
| Anything specialization-based | Forever has no specializations (`C_SpecializationInfo` is not used; its Personal Resource Display says so). Nothing in the bars reads a spec |
| Whirlwind or other buff-stack "resources", swing timers, spell cost prediction, mana regeneration markers | Aura-based or predicted, not a resource the client reports; auras may also be restricted. Deferred |
| Cooldown / recharge displays | No Forever resource recharges in a way the client exposes; the segmented bar never animates a recharge. If one is added later it needs a driver (`Anim.lua`) and a data source first |
| Hiding or moving Blizzard's, EllesmereUI's or another addon's bars | Not offered. If it ever is, it must be a separate explicit option with verified ownership |

If the client reports a value TwichUI cannot read (a restricted/"secret" value, a maximum of 0, no power at all), that
bar is **hidden**, never drawn from a guess, and it returns when the value does.

## Architecture

| Part | File | Responsibility | Knows nothing about |
|---|---|---|---|
| Providers | `Resources.lua` | When a resource applies, how to read it, which events change it; a normalized state `{ key, token, label, kind, cur, max, ok }` | drawing, settings |
| Configuration | `Config.lua` | Defaults, limits, validation, the shared style, per-class overrides, the resolved style (cached, invalidated on change), places | frames, the game's power APIs |
| Bar | `Bar.lua` | Draws a continuous or segmented state from a resolved style; smoothing; only touches what changed | classes, settings storage |
| Effects | `Effects.lua` | Decorates a state (generic highlight, Mage glints); a small registry with lifecycle methods | resource correctness, settings ownership |
| Animation | `Anim.lua` | One shared driver, bounded, idle when empty | everything else |
| Controller | `Controller.lua` | Events, visibility rules, layout, positioning mode, preview, the switch | how a resource is read or drawn |
| Sharing | `setup/TwichConfig.lua` | `ui.classBars`, `ui.classBarsLook` (flat groups) and `ui.classBarsOverrides` (a custom group) | |
| Settings | `TwichUI_Settings/pages/ClassBars.lua` | Rows that call the feature's Get/Set | storage |

SenseiClassResourceBar (`../reference_addons/`, MIT) was read for ideas only: separating "what the bar shows" from
"how it is laid out", a per-resource style, a primary / secondary split. Nothing was copied, called or required, and its
Retail assumptions (Edit Mode through LibEQOL, specializations, runes, shards, essence, spell-specific stacks) were not
carried over.

### Adding a resource (a provider)

Only after the resource is verified for this client (a data source and the events that change it):

```lua
R.ClassBarResources.Register({
    id = "myResource", slot = "secondary",        -- "primary", "secondary" or "tertiary": which bar it takes
    kind = "segmented",                           -- or "continuous"
    classes = { PALADIN = true },                 -- optional: only these classes
    keys = { "MY_RESOURCE" },                     -- optional: what settings offers an override for (segmented ones)
    unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" },   -- filtered to "player" by the client
    events = {},                                  -- anything else
    Applies = function(ctx) return ctx.class == "PALADIN" end,  -- ctx: class, powerType, token (the client's)
    Read = function(provider, ctx)                -- fill provider.state in place; set ok = false if it cannot be read
        local s = provider.state
        s.key, s.token, s.label = "MY_RESOURCE", "MY_RESOURCE", "My resource"
        s.cur, s.max, s.ok = ..., ..., true
    end,
})
```

Then add `REST["MY_RESOURCE"]` ("full" or "empty") and `COLORS["MY_RESOURCE"]` in `Resources.lua` if it has a resting
state and a color, and a test that reads it the way `tests/test_class_bars.lua` does. The registry refuses a malformed
provider and one with an existing id. A slot has one active provider at a time: the first registered one that applies.

### Adding an effect

```lua
R.ClassBarEffects.Register({
    id = "mine", setting = "effectsMine",         -- a boolean in Config.lua's DEFAULTS (and in CB.GROUPS.effects)
    Applies = function(view, ctx, slot) ... end,  -- which bars and resources it belongs on
    Attach = function(bar) ... return inst end,   -- make its objects once; inst needs a Step(self, dt) if it animates
    Update = function(inst, view, quiet) ... end, -- see the state; FX.Rising(inst, pct, threshold, quiet) is the transition test
    Play = function(inst, trigger) ... end,       -- start (A.Add(inst)); "test" from settings
    Stop = function(inst) ... end,                -- halt, hide, forget (A.Remove(inst))
    Release = function(inst) ... end,
})
```

An effect draws on `bar.fx` (above the fill, below the text), makes its objects once in `Attach`, never creates one
while playing, and honors `FX.Reduced()`.

## Lifecycle and events

| Moment | What happens |
|---|---|
| Switch off (default) | No frame, no event, no timer exists. `Refresh` tears everything down when it is turned off |
| Login / `/reload`, before the world | Only `PLAYER_ENTERING_WORLD` is registered; nothing is read |
| `PLAYER_ENTERING_WORLD` (login, zoning, instances) | Full refresh: sense class and power, choose providers, read, resolve styles, draw, lay out, register exactly the events needed. Effects only note the state |
| `UNIT_DISPLAYPOWER` (form change) | Full refresh: the resources may be others. A bar whose resource changed is cleared first (no stale label, segments or effects) |
| `UNIT_POWER_FREQUENT` / `_UPDATE`, `UNIT_MAXPOWER` | Read the active providers; draw only a bar whose numbers changed. An event for a power token we do not show is dropped before any API call |
| `PLAYER_TARGET_CHANGED`, `COMBO_TARGET_CHANGED` | (Only registered for classes with combo points.) Read; effects only note the state |
| `PLAYER_DEAD` / `_ALIVE` / `_UNGHOST` | Visibility; alive again is not a transition |
| `PLAYER_REGEN_DISABLED` / `_ENABLED` | Visibility; entering combat ends the preview and positioning |
| `PLAYER_MOUNT_DISPLAY_CHANGED` | Registered only while "Hide while mounted" is on |
| `UNIT_ENTERED_VEHICLE` / `_EXITED_VEHICLE` (player), `PLAYER_GAINS/LOSES_VEHICLE_DATA` | Registered only while "Hide in vehicles" is on. The bars never show a vehicle's own resource |
| `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` | Borders are whole pixels: the look is drawn again |
| A setting changes, a profile changes, LibSharedMedia registers media | `Config.Invalidate` -> one refresh (quiet) |

Unit events are registered with `RegisterUnitEvent(..., "player")` on the controller's own frame (the shared bus
cannot filter by unit); the client never delivers other units' power events to Lua.

### Visibility rules (resource-aware)

`Show the bars` is one of: **Always**; **Fade in during combat**; **Only in combat**; **In combat or when not at rest**. "At rest" is per
resource (`Resources.lua` `REST`): mana, energy and focus at their maximum; rage, runic power and combo points at 0. A
resource with no known resting value is never at rest, so it is never hidden by this rule. Each resource of a class can
override it (including "Never show"). On top: hide while dead or a ghost (on), mounted (off), in a vehicle (on). A bar
switched off in Layout, or with no value available, is never drawn. A group frame is shown only while one of its bars is.

## Storage and configuration

All in the profile in use (`TwichUIDB.ui`), so profile changes, copies and Reset follow the existing rules. The switch
is `TwichUIDB.modules.classBars` (false until turned on). Every value is validated on the way in and on the way out; an
invalid stored value reads as the default and is not erased; `0` and `false` are values.

| Key | Holds |
|---|---|
| `ui.classBars` | Shared style: `show`, `fadeIdle`, `hideDead/Mounted/Vehicle`; `opacity`, `scale`, `placement`, `gap`, `segmentGap`, `<slot>On/Width/Height`; `texture`, `fillStyle`, `gradientDir`, `colorSource`, `color`, `color2`, `shade`, `smoothing`; `<slot>Text`, `font`, `fontSize`, `fontOutline`, `textColor`, `textPlace`; `effects*`. Ranges in `Config.LIMITS` |
| `ui.classBarsLook` | Background and border: a MenuStyle look (the same textures, LibSharedMedia and EllesmereUI choices as the Mage menus) |
| `ui.classBarsOverrides` | `["CLASS:RESOURCE"] = { colorSource, color, text, show }`. At most 48 entries |
| `ui.classBarsPosition` | `{ main = { x, y }, aux = { x, y } }`: the group centre in screen units from the screen centre. Never shared |

**Shared versus per-class/resource.** A bar is drawn from the shared style; the entry for the player's class and the
resource on that bar, if any, overrides the fill source/color, text mode and visibility rule for that resource only.
A field that is not in the entry is inherited, and the Appearance page says which: "Following the shared style" or
"Set for this resource only". Entries are keyed by class token and resource key, never by localized names, so a Mage's
mana and a Priest's mana are separate and playing one class never touches another's. Settings shows only the
resources the current class can have; entries for other classes are kept and used when you play them.

**Resets** (each states its scope and asks first): When to show (`behavior` keys), Layout (`layout`), Fill and text
(`appearance`), Effects (`effects`), Background and border (the look), and one per resource of the class (that
resource's override). Positions have "Reset position". Nothing else changes.

**Places** are clamped to the screen on use (`Config.ClampPosition`) but the saved place itself is kept, so a place
saved on a large screen is back when the screen is large again. A place can always be recovered with Reset position, or
by moving the bars. Places are not part of sharing.

**Sharing.** `TwichConfig.lua` carries the switch, `ui.classBars`, `ui.classBarsLook` (flat groups) and
`ui.classBarsOverrides` (custom group, merged by `CLASS:RESOURCE`). Not carried: places, preview state, effect objects,
timers, resource values. See `docs/twichui-sharing.md`.

## Effects

Off by default (`effects = false`); with it off no effect object exists. Triggers fire only on a rising crossing of the
threshold (`FX.Rising`): the value must have been below it, rise through it, and drop well below (90% of the threshold)
before it can fire again. The first value after a login, zone, resource switch, profile change, target change or
resurrection is a start, not a transition. They stop when the bar is hidden, the feature or effects are switched off, the
resource changes or the preview ends.

| Effect | Setting | What it draws |
|---|---|---|
| Highlight at the threshold | `effectsAccent` | A soft tinted highlight over the bar (flat texture, additive, peak alpha 0.3, 0.5 s) when the resource rises through `effectsThreshold` (default 100%). Any bar and resource: combo points complete, rage reaches the top, mana is back to full |
| Mage frost glints | `effectsClass` | Six small star-shaped glints (`Interface\Cooldown\star4`, Blizzard's own cooldown "bling" texture) rise from the mana bar and fade when mana is back to full. Mage mana bar only. Other classes have no preset yet |

These are particle-like (tinted textures moved by the shared driver), not particles: the game's model and particle APIs
and any asset of ours were not used. Reduced motion (`effectsReducedMotion`, its own setting, not the notification or
settings-window ones): the highlight becomes a brief steady one and the glints are not drawn. Objects are made once per
bar in `Attach` and reused; nothing is created while playing; the driver holds at most 24 animated objects and refuses
more rather than queueing.

## Performance and combat safety

Nothing below is measured; these are the designed costs and how to look at them.

- **Off**: no frames, events or timers. **Hidden or idle**: the animation driver's `OnUpdate` is not set unless something is
  easing or playing (`Anim.Running()`); a hidden bar takes itself off the driver.
- **Per resource event** (a handful per second while resting, more in combat): one `RegisterUnitEvent`-filtered event, a
  token check that drops events for powers not shown, 2 to 4 API reads, number comparisons, and a draw only for a bar whose
  numbers changed. Text is set only when the words change; the layout, fonts and media are not touched on a tick. Styles
  are cached and rebuilt only after a setting, profile or media change. No table is created per event.
- **Smoothing** is a separate displayed fraction that eases on the shared driver; the raw numbers, text, visibility and
  effects always use the real value.
- **Effects cost** only while playing (about half a second, up to seven textures).
- Profiling: `/tui diagnostics` has a "Class resource bars" section (events registered, whether the driver is idle,
  effect objects). For CPU use the game's `/run` with `debugprofilestop` around `TwichUI.ClassBars.Refresh()`, or an addon
  profiler; for memory compare `collectgarbage("count")` with the switch off and on. Report those as measurements, with
  the conditions.
- **Combat**: the bars are plain, non-secure frames that take no clicks, so showing, hiding, moving, resizing and
  restyling them is legal in combat and is not deferred. Only the move handle takes the mouse, and only in positioning
  mode, which cannot start in combat and ends when combat starts.

## Using it

1. `/tui bars` (or Settings > Gear & class > Class resource bars). Turn on "Show class resource bars".
2. **Preview** shows the real bars with made-up numbers (marked Preview); the sample level and combo points sliders move
   them. It ends when you close settings, enter combat or turn the bars off.
3. **Move the bars** shows a highlighted handle: drag it, right-click it (or press Finish) when done. **Reset position**
   puts it back.
4. Layout, Appearance and Effects are tabs. Under Appearance, "Your class's resources" sets what one resource does
   differently.

## Tests

`tests/test_class_bars.lua` (providers, configuration and resolution, drawing, forms, visibility, layout and places,
smoothing, preview, positioning, effects, the driver, profiles, combat) and `tests/test_class_bars_settings.lua` (pages,
rows, resets, per-class rows, the report). Sharing is covered in `tests/test_twichui_share.lua`. The offline tests use a
stand-in for the game: they prove our logic and lifecycles, not the client's behavior.

## In-game checklist (not yet done)

- Mage: the mana bar follows `UNIT_POWER_FREQUENT`; full-mana glints on a rest refill; `Show the bars` > "In combat or
  when not at rest" hides it at full mana and shows it in combat.
- Warrior: rage bar; empty rage hidden out of combat under the active rule; the threshold highlight at 100 rage.
- Rogue: energy plus combo points; target change and `COMBO_TARGET_CHANGED` (points moved to a new target); no target is
  0; the combo bar completes with 5.
- Druid: Caster, Cat, Bear and back: bars switch with no stale label or lit segments; combo points only in Cat; the thin
  mana bar in Cat and Bear; no combo bar in Bear. Confirm `UnitPower("player", Enum.PowerType.Mana)` returns mana in Cat.
- Hunter / Priest / Shaman / Paladin / Warlock: the bar follows what `UnitPowerType` reports (Focus vs mana for Hunters).
- Whether any value is restricted ("secret") for the player's own power in combat; the bar should hide, not guess.
- Death, release, resurrection, zoning, instances, `/reload`, mounting, a vehicle.
- Preview and Move: sample numbers, "Preview" tag, handle drag, right-click finish, Reset position; at different UI
  scales (the Graphics UI Scale slider and 0.64 / 1.0 / 1.2 scale) and a different resolution: the bars stay on screen.
- Profiles: switch profile; overrides for other classes remain; sharing round-trip with a second client (shared style and
  overrides across, places not).
- Fonts and textures from LibSharedMedia and EllesmereUI (present and absent); a missing texture or font falls back.
- With EllesmereUI's own resource bars on, nothing of theirs is hidden or moved.
- `/tui diagnostics`: events registered and driver idle when nothing is happening; both 0 with the switch off.
