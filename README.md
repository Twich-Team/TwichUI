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

**Auctionator skin.** Gives Auctionator's tabs, lists, buttons, item icons and
bag headers the EllesmereUI look (needs EllesmereUI's Auction House skin on).

**Configuration sharing** (`/pack`)

* Pick the addons whose settings you want to share and save them as your addon configuration.
* Send it to a friend in game. They get a prompt, it downloads with a progress
bar, and they choose what to apply. Their own settings are backed up first; Undo puts them back.
* Later sends only include addons you changed.
* Your recommended addon list travels with it, with a download link for each addon they're missing.
* Friends on other realms: build a file version with `tools\\make\_pack.bat`.

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

## Commands

`/twichui` options · `/twichui help` all commands · `/pack` sharing window ·
`/pack test` send to yourself · `/pack status` sharing diagnostics ·
`/twichui check` group check · `/twichui restore` restore points

## Good to know

* The folder is named `!!!TwichUI` on purpose: it must load before other addons.
* Sending needs both players online and outside boss fights, Mythic+ and PvP matches
(the game blocks addon messages there).
* Keybinds and game options aren't addon settings and aren't shared.

