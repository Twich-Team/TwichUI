# TwichUI

A carefully crafted UI enhancement addon for **WoW Forever** that makes the game
interface feel a little cleaner, more cohesive, and more considered, without 
making it feel modernized beyond recognition.

Its purpose is to refine the experience, not replace it. Small, thoughtful touches
should help players read the game and make their own decisions while preserving
the atmosphere, discovery, and sense of place that make Forever compelling.

This addon is intended to work alongside EllesmereUI.

## Features

**Fonts and sounds.** Adds various thematic fonts to the game, allowing them to be
utilized for interface customization.

**Quiet login.** Attempts to hide all addon welcome messages when logging in to 
prevent being brought out of immersion by being inundated with unnecessary information.

**Upgrade hints.** When something you could wear looks better than what you
have, its tooltip gets one quiet line such as "Likely upgrade for Fury". Hold
Shift (your compare-items key) to see why: what it's compared with, the stat
changes that mattered most and which weights were used. Items that aren't
upgrades, or that you can't use, get nothing unless you ask. See
[how upgrade hints work](#how-upgrade-hints-work).

**Addon skins.** Provides EllemereUI skinning to various addons to create a cohesive look and feel. Currently supprts: Attune, Auctionator, DungeonJournal, and WhatsTraining.

**Configuration sharing.** Provides an ecosystem to share your addon configurations with friends.

* Pick the addons whose settings you want to share and save them as your addon configuration.
* Send it to a friend in game. They get a prompt, it downloads with a progress
bar, and they choose what to apply. Their own settings are backed up first; Undo puts them back.
* Later sends only include addons you changed.
* Your recommended addon list travels with it, with a download link for each addon they're missing.

**Restore points.** Save your own settings before you tinker, go back any time.

## Sending on Forever

The Forever beta currently drops the hidden direct messages addons use when a
character has a first and last name. Until that's fixed, TwichUI can send
through your group or guild channel instead, but only if you allow it
(Sending options, or `/twichui`). Group and guild messages are hidden addon
traffic; everyone there receives the data, and only the named friend's TwichUI
reads it. With group check on, TwichUI tests once per game build whether direct
messages work again and switches back automatically.

## How upgrade hints work

* **Your spec** is the talent tree you've put the most points into, in your
active talent group, unless you pick one in `/twichui gear`. Forever uses
classic-style talent trees, not retail specializations. Before your first talent
point, or when your points are split evenly, the class's usual levelling tree is
used, and the tooltip says so.
* **Each stat is weighed** for that tree, one of two ways, chosen per tree in
`/twichui gear`:
  * **Stat weights** (the default): a number per stat. You can change them; Rating stats (hit, crit, haste, defense...)
  are converted to percentages at your level with the game's own conversion.
  * **Stat priority:** you rank the stats your guide lists, most important first.
  Each counts 80% as much as the one above it, and stats you leave out count
  nothing. A point of each stat is scaled by roughly what it costs on an item, so
  "Strength > Attack Power" compares a point of strength with the two attack power
  an item would carry instead. Ratings count per point as printed. Weapon damage
  and armor keep the tree's weights.
* **What it's compared with** is what it would replace: the weaker of your two
rings or trinkets, both hands for a two-hander, or your off hand for a one-hander
if you dual wield. Off-hand items aren't compared while you wield a two-hander.
* **Items you can't use get no hint.** That covers any item whose tooltip shows
red requirement text (class, armor or weapon skill). An item held back only by
your level is still compared and says so: "Likely upgrade at level 32".

Limitations: it's a rough estimate from item stats. It doesn't simulate
damage, healing or survival, and it doesn't produce a best-in-slot list.

* "Use:" and "Chance on hit:" effects aren't weighed, so an item that has one
is at most a "possible" upgrade.
* "Equip:" effects count only when the game reports them as stats.
* Resistances, weapon speed, set bonuses, enchants, sockets and hit caps aren't
considered.
* The weights are hand-set starting points, not simulation results.
