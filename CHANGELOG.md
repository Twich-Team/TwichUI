# TwichUI changelog

## Unreleased
- **Journey Chronicle** is now on by default for new installs (automatic entries; your own notes always work, and you can turn it off in the options). New option **Show Chronicle entries in chat** (on by default): when an entry is added automatically, a quiet line with its icon appears in your own chat window. It's never sent to anyone, and entries are still recorded when it's off.
- **Journey Chronicle** data bar source: a LibDataBroker object named "TwichUI Chronicle" shows "Journey Chronicle" with its icon, a tooltip (character, count, latest entry) and opens the Chronicle on click. In EllesmereUI add a Broker Plugin block to a data bar and pick "TwichUI Chronicle". Needs a broker display; nothing changes without one.
- **Journey Chronicle** icons: each entry shows a small icon for what happened (level, new zone, defeated encounter, fall, your own note). New optional entry, **Falling in battle** (off by default): records when your character dies and where.
- **Journey Chronicle** look: warm umber and bronze frame with a title band, quieter byline and status line (details in a tooltip), ledger-style entries with a small marker for automatic entries versus your own notes, a bronze "Write a note" button, a quieter Options button, and Edit / Delete that appear when you point at an entry.
- **Journey Chronicle** (new, optional): a quiet, private journal for each character. Open it with
  `/tui chronicle` or Options > AddOns > TwichUI > Journey Chronicle. Write short notes of your own
  (with the zone you're in, if you like) and edit or delete them any time. Automatic entries are off by
  default; turn them on to keep level milestones, new zones and defeated encounters, each switchable on its
  own. Nothing from before you turn it on is added, and nothing is announced in chat. Entries stay on that
  character (up to 500; the oldest automatic ones go first, your notes are never removed for you) and are
  never part of configuration sharing, setups or backups. Times show in 12-hour format by default;
  switch to 24-hour in the same options section.
- **Gear comparison**: the bag upgrade mark now also shows in EllesmereUI Bags (bags, reagent bag and bank), using its item overlay API.
- **Version and group check** is on by default for new installs (hidden addon messages; players
  without TwichUI see nothing). Anyone who already has the option saved keeps their choice.
- **Commands**: `/tui` is a short form of `/twichui`. `/tui` alone (or `/tui help`) now lists
  the commands instead of opening options; use `/tui options`. Unknown commands say so and point to
  `/tui help`. New `/tui share` (was `/pack`) and `/tui skin` (was `/aeskin`). The old `/pack` and `/aeskin` commands are removed.
- **Temporary**: `/tui commtest party|guild|whisper <name>` checks whether addon messages are
  delivered, by asking another TwichUI user to answer a tiny probe. Remove with setup/CommTest.lua.
- **Sharing window**: now three pages: **Share setup**, **Received setups** and **Backups**
  (Restore points are now called Backups). Share setup shows a short summary of what's
  included with Choose addons (searchable) and Scan installed addons; recommendations
  ("Recommend addons to friends") and the party compatibility check open from there. Received
  setups start with a summary and a Review step before anything can be applied, and
  "Use on this alt" is now "Use profiles already applied on another character". Saved data,
  the setup format and every option are unchanged.
- **Options**: TwichUI's settings now all live in Esc > Options > AddOns > TwichUI, grouped
  by feature (General, Gear comparison, Addon skins, Chat, Configuration sharing). Rarely
  changed options show when you tick "Show advanced options"; they keep working while hidden.
- **gear**: the separate upgrade hints window is gone. Talent tree, possible upgrades, higher
  levels, strictness, reveal key and bag mark style are ordinary options; stat weights and
  stat priority moved to a "Stat weights" page under TwichUI (`/twichui gear` opens it).
  Your existing choices carry over unchanged.
- **Addon skins**: each skin says whether its addon is installed, and its tooltip shows
  whether the skin is active, waiting for EllesmereUI or needs a reload.
- **Configuration sharing**: before applying, each addon shows whether your settings will be
  replaced or added, and a summary (repeated in the confirmation) says exactly what changes.

## 3.0.5
- Updated toc to reference only Forever build and match version of addon appropriately.

## 3.0.4
- **gear**: now supports either stat weights or stat priority gear analysis methods.
- **gear**: options panel is not fully skinned.
- **Auctionator skin**: fixed an issue that caused Auctionator's tabs on the Auction House interface to overlap.

## 3.0.3
- New **upgrade hints**: when something you could wear looks better for your class and main
  talent tree, its tooltip gets a quiet "Likely upgrade" line. Hold Shift to see why. Gear
  held back only by your level is compared too ("Likely upgrade at level 32").
  Toggles: "Upgrade hints in item tooltips" and "Mark upgrades in my bags" (off by default)
  in `/twichui`. `/twichui gear` picks the talent tree, values stats by a ranked stat
  priority (as guides list them) or by editable stat weights, and sets how hints behave
  (glance, strictness, reveal key, bag icon style).
- New **Attune skin**: the Attune window (`/attune`) and its quest panels get the EllesmereUI look.
  Toggle: "Skin Attune" in `/twichui`.
- New **Dungeon Journal skin**: the Forever Dungeon Journal window (`/fj`) gets the EllesmereUI look.
  Toggle: "Skin Dungeon Journal" in `/twichui`.
- New **WhatsTraining skin**: the floating window (`/wt`) gets the EllesmereUI look.
  Toggle: "Skin WhatsTraining" in `/twichui`.

## 3.0.1
- Version and group check is now **off by default** (opt-in). Turn it on in
  `/twichui` or with the button on the Group tab; everyone who wants to show up
  in a group check needs it on. The automatic switch back to direct messages
  also needs it, since it tests over the same channel.

## 3.0.0
- **Group check**: `/twichui check` or the Group tab shows everyone in your
  group, their TwichUI version, and which of your recommended addons they're missing.
- **Version check**: when you're grouped, TwichUI tells you if someone has a newer
  version, or one too old to share configurations with. Group channel only, a few bytes.
- **Direct messages come back automatically**: once per game build TwichUI tests
  whether Forever delivers addon whispers again, and switches sharing back to them.
- **Restore points**: save your own addon settings and go back to them later.
- New "Version and group check" option; the window gained Group and Restore points tabs.
- Release packaging for CurseForge/Wago, offline test suite, licenses.

## 2.6.x
- Sending options: group and guild channels are opt-in, with an explanation of why
  Forever needs them. Auctionator skin covers item icons, bag headers, refresh
  button, scroll bar frames and gold labels.

## 2.5.x
- Sharing works on Forever (group/guild routing, first-and-last names). Large
  configurations pack over several frames. Fixed a division-by-zero error in the
  serializer that stopped every send in game.

## 2.0 - 2.4
- Combined media, Auctionator skin and configuration sharing into one addon.
  In-game sending, addon list with download links, quiet login, saved data manager.
