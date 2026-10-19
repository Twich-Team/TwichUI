# RestedXP guide: show and hide automatically

**RestedXP > Show and hide automatically > Hide the guide in some situations** (`qol/GuideAutoHide.lua`, switch
`modules.qolGuideAuto`, off by default). Written against RestedXP Guides v4.11.22 and the WoW: Forever UI source.
Nothing here has been run in the game yet.

It hides RestedXP's guide while one of the situations the player ticked is on, and shows it again when none is.
The guide's content, progress and settings are RestedXP's own and are never changed: the only thing done is what
RestedXP's own Show/Hide does.

## The situations

Each is its own switch under the master one (`modules.qolGuideAuto<Name>`), all kept local: configuration sharing
treats them as "acts", like the waypoint, so a shared setup never starts hiding someone's guide.

| Switch | Default | True when |
|---|---|---|
| `qolGuideAutoDungeon` | on | `IsInInstance()` type is `"party"` |
| `qolGuideAutoRaid` | on | type is `"raid"` |
| `qolGuideAutoPvP` | on | type is `"pvp"` or `"arena"` |
| `qolGuideAutoGroup` | off | `IsInGroup()` (party or raid, anywhere) |
| `qolGuideAutoResting` | off | `IsResting()` (inn or city) |
| `qolGuideAutoFlight` | off | `UnitOnTaxi("player")` |

Scenarios and the open world are none of these. Combat is deliberately not one: RestedXP leaves its secure
frames alone in combat, and a guide that blinks in and out of fights would be the opposite of calm.

## How it acts

* It acts on a **change**: nothing wanted then something wanted hides the guide; the last situation ending shows
  it. Two situations at once (a dungeon you are grouped for) are one hide and one show.
* It **only shows a guide it hid itself.** A guide you had hidden before stays hidden. A toggle you make while
  it has the guide hidden (a `ToggleActive` it did not make, noticed through a `hooksecurefunc`) is yours: the
  guide is left as you made it until the next time a situation begins or ends.
* That it hid the guide is remembered per character in `ui.guideAuto[playerGUID] = true` (account-wide in
  `Profiles.lua`'s list of records, like `guideWaypoint`), so after a `/reload` inside a dungeon the guide still
  comes back when you leave. A record with no situation on at login shows the guide.
* Turning the feature off, or unticking the situation that has the guide hidden, shows it again.
* A RestedXP profile change (`settings:RefreshProfile`, hooked once) forgets the record: the new profile's
  own shown/hidden state stands, and the situations are looked at again.
* **Nothing is changed in combat**: the change waits for `PLAYER_REGEN_ENABLED`.

## Events

Only what the ticked situations need: `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_NEW_AREA` for the instance
ones, `GROUP_ROSTER_UPDATE`, `PLAYER_UPDATE_RESTING`, `PLAYER_CONTROL_LOST` / `PLAYER_CONTROL_GAINED`. Each
handler is a few API calls that return when nothing changed. No `OnUpdate`, no polling. The flight state is
looked at once more a second after each control event, because the taxi flag may lag them.

## Limits

* `settings.ToggleActive`, `settings.profile.showEnabled` and `RefreshProfile` are RestedXP internals, not a
  public interface. A RestedXP without them is reported as "This RestedXP isn't supported" and nothing is hooked.
* Unverified in the game: that `UnitOnTaxi` is true soon enough after `PLAYER_CONTROL_LOST` (the one-second
  second look is a guess), that `IsInInstance()` is already right at `PLAYER_ENTERING_WORLD` on every kind of
  loading screen, and how RestedXP's v2 guide window (beta) looks after its `GuideWindowRefresh` visibility event.
* Another addon or RestedXP's own Show/Hide while a situation is on is treated as the player's choice.

## Tests

`tests/test_guide_auto.lua` simulates RestedXP's `ToggleActive` and the situation APIs. It covers: off by
default and silent; no RestedXP or an unusable one; each situation; two at once; the player hiding or showing
the guide in between; combat; turning off or unticking; a reload inside a dungeon; a profile change; and that
only the needed events are registered. Static checks cannot show how it looks or behaves in the game.
