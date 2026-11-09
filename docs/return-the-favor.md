# Return the Favor

A short list of the players who just buffed you. Click a name to buff them back with something your class can
give; right-click to remove it. Optionally, thank them with an emote a few seconds later. Off until turned on
(`TwichUIDB.modules.buffBack`). Settings: **Everyday › Return the Favor** (`R:OpenSettings("buffBack")`).

Inspired by the Manners addon's "return the favor" idea. No Manners code is used; this is TwichUI's own
implementation.

## Files

| File | What it does |
|---|---|
| `buffback/Config.lua` | `R.BuffBack`: settings (`DEFAULTS`, `LIMITS`, `CHOICES`), `Get`/`Set`, the place, the rows' MenuStyle look (`buffBackLook`), change notices |
| `buffback/Spells.lua` | `R.BuffBackSpells`, pure: which buffs count (families of spell IDs, matched by ID or client name), what each class gives back (`Pick`), the macro a click runs (`Macro`) |
| `buffback/Watch.lua` | `R.BuffBackWatch`: your `UNIT_AURA` events, the session list, expiry, pauses, the cast-back check, the thank-you emote |
| `buffback/List.lua` | `R.BuffBackList`: the secure rows, combat deferral, the sample (preview) and dragging it |
| `buffback/Unlock.lua` | `R.BuffBackUnlock`: the optional EllesmereUI Unlock Mode mover |
| `TwichUI_Settings/pages/ReturnTheFavor.lua` | the settings page (four cards) |

## How it works

- **Noticing a buff.** `UNIT_AURA` for `player`: an added helpful aura whose `sourceUnit` is another player (not you,
  not a pet or NPC) and whose spell is in a known family is a favor; so is one of those auras being recast on you (its
  expiration moves on). A full update only takes stock. Secret aura fields are never compared; such an aura is not
  noticed. No combat log is read.
- **Families** (`Spells.lua`): Arcane Intellect, Fortitude, Divine Spirit, Shadow Protection, Mark of the Wild, Thorns,
  Blessings of Wisdom, Might, Kings, Salvation, Light and Sanctuary, Unending Breath, Amplify and Dampen Magic, Fear Ward,
  Detect Invisibility, Water Breathing and Water Walking, each with its group version. Battle Shout is given back but
  never counts as received (a warrior's shout reaches the whole party). "Count any helpful spell" lists anything.
- **Giving back** (`S.Pick`): your class's families you know, minus mana-only ones for players without mana (by class),
  minus a shout for anyone outside your party, and what they don't already wear (when their auras can be read) comes
  first; if they wear it all you still give the usual first choice, to refresh it. A player without mana gets Might
  before Kings. Cast by name, so the game picks the highest rank you know.
- **The click** (`S.Macro`, a `SecureActionButtonTemplate` row, `*type1 = macro`, `useOnKeyDown = false`): a group
  member is cast on with `/cast [@party2] Spell` (their unit token; a name with a space can't go in a conditional);
  anyone else is `/target Name Surname`, `/cast Spell`, then `/targetlasttarget` (or `/cleartarget` when you had no target). Already your
  target: `/cast [@target] Spell`. A shout is just `/cast`. Your own `UNIT_SPELLCAST_SUCCEEDED` of that family within
  3 s of the click removes the row.
  Names: on Forever `UnitName`'s second return is a surname (no realms), joined with a space
  (`CHARACTERNAME_SURNAME_SEPARATOR`). The list keys players by that full name; "Name-Realm" never resolved, which
  is why a click used to fall back to casting on you.
- **Combat.** Rows are laid out, armed and shown out of combat only. In combat new names wait and expired or dismissed
  rows dim (the skin's alpha); everything is brought up to date at `PLAYER_REGEN_ENABLED`. "Hide in combat" is the
  secure state driver (`[combat] hide; show`).
- **Pauses**: dungeons, raids (default on), battlegrounds/arenas (default on), resting. Paused means nothing listed,
  nobody thanked, the list hidden; arriving there empties it.
- **Thanks** (off by default, kept local by configuration sharing): `C_ChatInfo.PerformEmote(token, name)` (falls back
  to `DoEmote`) after the delay plus up to 1.5 s, out of combat, not paused, not in chat lockdown, only when a unit of
  yours names them (target, mouseover, focus, group, nameplates), once per player per 5 minutes, never two within 10 s,
  at most 3 waiting. The game's "restricted" answer is counted, not retried. With "Only after I buff them back"
  (`thankAfterReturn`, off by default, also kept local), nothing is scheduled when their buff lands: the delay starts
  when a click on their row is confirmed by your own cast of that buff, so someone you don't buff back is never thanked.
- **Look**: per row, a MenuStyle look drawn on a plain child of the secure button (never on the button). Font,
  size, outline, class or fixed name color, buff-name color, icon size, width, row height, spacing, scale, opacity,
  growth direction.
- **Place**: `ui.buffBack.x/y`, the list's centre from the screen's centre. The list is always as tall as its most rows.
  Moved by dragging the sample, or with EllesmereUI's Unlock Mode (`ui.buffBack.unlockMode`): a plain stand-in is
  registered, and the secure list follows it out of combat.

## Saved

`TwichUIDB.ui.buffBack` (settings and place) and `TwichUIDB.ui.buffBackLook` (the rows' look), both per profile.
Nothing about who buffed you, when, or whom you thanked. Configuration sharing keeps `x`, `y`, `unlockMode` (place)
and `thank`, `thankEmote`, `thankDelay` (network) on this computer.

## Diagnostics

Scopes `buffback.aura`, `buffback.event` (`Perf.Wrap` on the two private event frames) and `buffback.render`
(`Perf.Start` in `Render`, after the combat check). Gauges `buffback.events` and `buffback.rows`.

## In-game checks (not yet done)

1. A friend buffs you: the row appears with their class color and the buff's icon; it goes after the set time.
2. Click it (each class): the right spell lands on them, your own target comes back, the row goes. Out of range: the
   game's message, the row stays. In your group: no target change at all.
3. In combat: a new buff waits, an expired row dims, everything updates after combat with no "action blocked" message.
4. Thank emote: the emote fires once after the delay, not in combat, not in dungeons/raids with chat lockdown, and not
   if they walked away. Check `PerformEmote` takes a player name as `targetName` from addon code without a hardware event.
5. EllesmereUI Unlock Mode: the mover appears, moving it moves the list; anchors to another element hold after a reload.
6. An `eui:` border on the rows draws correctly after a `/reload`.
7. Casting a highest-rank buff on a low-level player: whether the game downranks it or refuses it.
