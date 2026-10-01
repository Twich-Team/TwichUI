# TwichUI

A small companion addon for **WoW Forever** (and retail) that fills the gaps
around an EllesmereUI setup, and makes it easy to share your addon setup with
friends.

## Features

**Fonts and sounds.** Alegreya, Alegreya Sans (and Small Caps), Barlow Semi
Condensed and Cinzel, plus a set of bell-themed alert sounds (group death
tolls, GTFO alerts). They appear in the font and sound lists of EllesmereUI,
BigWigs and any other addon that uses LibSharedMedia. Nothing changes until you
pick them.

**Quiet login.** Hides the "v1.2 loaded, type /foo" lines addons print at login
and reload. Errors and warnings still show. `/twichui hidden` lists what was hidden.

**Upgrade hints.** When something you could wear looks better than what you
have, its tooltip gets one quiet line such as "Likely upgrade for Fury". Hold
Shift (your compare-items key) to see why: what it's compared with, the stat
changes that mattered most and which weights were used. Items that aren't
upgrades, or that you can't use, get nothing unless you ask. Optionally, upgrades
in your bags get a small mark. `/twichui gear` picks the talent tree, edits stat
weights and sets how hints behave. See
[how upgrade hints work](#how-upgrade-hints-work).

**Auctionator skin.** Gives Auctionator's tabs, lists, buttons, item icons and
bag headers the EllesmereUI look (needs EllesmereUI's Auction House skin on).

**WhatsTraining skin.** Gives WhatsTraining's floating window (`/wt`) the
EllesmereUI look (needs EllesmereUI's third-party skins on).

**Dungeon Journal skin.** Gives the Forever Dungeon Journal window (`/fj`) the
EllesmereUI look (needs EllesmereUI's third-party skins on).

**Attune skin.** Gives the Attune window (`/attune`) and its quest panels the
EllesmereUI look (needs EllesmereUI's third-party skins on).

**Configuration sharing** (`/pack`)

* Pick the addons whose settings you want to share and save them as your addon configuration.
* Send it to a friend in game. They get a prompt, it downloads with a progress
bar, and they choose what to apply. Their own settings are backed up first; Undo puts them back.
* Later sends only include addons you changed.
* Your recommended addon list travels with it, with a download link for each addon they're missing.

**Group check** (`/twichui check`, Group tab). Everyone's TwichUI version and
the recommended addons they're missing, and a heads-up when someone in your
group has a newer version. Off by default; everyone who wants to take part
turns it on.

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
* **Each stat is weighed** for that tree. You can change the weights in
`/twichui gear`; the defaults are in `gear/Weights.lua`. Rating stats (hit, crit,
haste, defense...) are converted to percentages at your level with the game's own
conversion.
* **What it's compared with** is what it would replace: the weaker of your two
rings or trinkets, both hands for a two-hander, or your off hand for a one-hander
if you dual wield. Off-hand items aren't compared while you wield a two-hander.
* **Items you can't use get no hint.** That covers any item whose tooltip shows
red requirement text (class, armor or weapon skill). An item held back only by
your level is still compared and says so: "Likely upgrade at level 32".

In `/twichui` > Gear you can turn **Upgrade hints in item tooltips** (on by
default) and **Mark upgrades in my bags** (off by default) on or off.
`/twichui gear`, or the **Upgrade hint options** button there, opens the options
window:

* **Weights**
  * **Weigh gear for:** Automatic, which follows your talent points, or a tree
  you pick. The choice is kept per character.
  * **Stat weights:** each tree's weights, which you can change. Your changes
  show in gold; **Reset these weights** puts the defaults back.
* **Behaviour**
  * Show possible upgrades at a glance, or only likely ones.
  * Hint at gear for higher levels.
  * **How big a gain counts:** Cautious, Balanced or Eager.
  * **Show the reasoning:** hold Shift, Alt or Ctrl, or always.
  * **Bag icons:** gilded arrow, green arrow or badge. The icons use the game's
  own art and show in Blizzard's bags, separate or combined.

Limitations: it's a rough estimate from item stats. It doesn't simulate
damage, healing or survival, and it doesn't produce a best-in-slot list.

* "Use:" and "Chance on hit:" effects aren't weighed, so an item that has one
is at most a "possible" upgrade.
* "Equip:" effects count only when the game reports them as stats.
* Resistances, weapon speed, set bonuses, enchants, sockets and hit caps aren't
considered.
* The weights are hand-set starting points, not simulation results.

## Commands

`/twichui` options · `/twichui help` all commands · `/pack` sharing window ·
`/pack test` send to yourself · `/pack status` sharing diagnostics ·
`/twichui check` group check · `/twichui restore` restore points ·
`/twichui gear` upgrade hint options ·
`/twichui hidden` hidden login messages · `/twichui version` your version ·
`/aeskin` Auctionator skin status

## Good to know

* The folder is named `!!!TwichUI` on purpose: it must load before other addons.
* Sending needs both players online and outside boss fights, Mythic+ and PvP matches
(the game blocks addon messages there).
* Keybinds and game options aren't addon settings and aren't shared.

