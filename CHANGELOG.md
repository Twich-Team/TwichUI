# TwichUI changelog

## Unreleased
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
